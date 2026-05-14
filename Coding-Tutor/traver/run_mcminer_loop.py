# -*- coding: utf-8 -*-
"""
McMiner-in-the-Loop TRAVER Pipeline

Runs dialogue round-by-round. After each student response:
1. Generates diagnostic code (N=1 via HF API)
2. Runs McMiner on that code (Gemini API)
3. Injects misconceptions into tutor prompt for next round
"""
import time
import json
import os
import re
import argparse
import tiktoken
import torch
from tqdm import tqdm

from chatarena.agent import Player, Moderator
from chatarena.agent_tutor import Tutor
from chatarena.backends import VLLMChat
from chatarena.environments.conversation_tutoring import TutoringConversation
from chatarena.arena_tutoring import TutoringArena
from utils.utils import load_json_dict, load_json_data, load_finished_data, convert_to_json
from utils.make_prompt import prompt_student, prompt_tutor, prompt_moderator, prompt_student_posttest
from verifier.data_utils import OnlineDataBuilder
from verifier.model_utils import load_model


def parse_args():
    parser = argparse.ArgumentParser()
    parser.add_argument("--namespace_file", type=str, required=True)
    parser.add_argument("--prompt_element_file", type=str, required=True)
    parser.add_argument("--output_dir", type=str, required=True)
    parser.add_argument("--student_setting", type=str, choices=['low_level', 'med_level', 'high_level'])
    parser.add_argument("--max_interaction_round", type=int, default=8)
    parser.add_argument("--max_code_context", type=int, default=1024)

    # Models
    parser.add_argument("--tutor_model_name_or_path", type=str, default="meta-llama/Llama-3.1-70B-Instruct")
    parser.add_argument("--student_model_name_or_path", type=str, default="Mistral-7B-Instruct-v0.2")
    parser.add_argument("--codegen_model", type=str, default="meta-llama/Llama-3.1-8B-Instruct")
    parser.add_argument("--codegen_api_base", type=str, default="https://router.huggingface.co/v1")
    parser.add_argument("--tutor_num_responses", type=int, default=1)
    parser.add_argument("--tutor_max_tokens", type=int, default=300)
    parser.add_argument("--student_max_tokens", type=int, default=300)
    parser.add_argument("--max_latest_messages", type=int, default=8)
    parser.add_argument("--temperature", type=float, default=0.4)
    parser.add_argument("--top_p", type=float, default=0.95)

    # Verifier
    parser.add_argument("--verifier_base_model_path", type=str, default=None)
    parser.add_argument("--verifier_model_dir", type=str, default=None)
    parser.add_argument("--verifier_model_parts", type=str, default="0")
    parser.add_argument("--verifier_max_length", type=int, default=2000)
    parser.add_argument("--use_KT", type=str, default="true")

    # API keys
    parser.add_argument("--vllm_api_key", type=str, default="EMPTY")
    parser.add_argument("--vllm_endpoint_tutor", type=str)
    parser.add_argument("--vllm_endpoint_student", type=str, default="local")
    parser.add_argument("--google_api_key", type=str, required=True)

    parser.add_argument("--show_description", type=str, default="false")
    parser.add_argument("--show_message", type=str, default="true")
    return parser.parse_args()


def str2bool(v):
    return v.lower() in ('true', 'yes', 't', 'y', '1')


# ── McMiner ──────────────────────────────────────────────
MCMINER_PROMPT = """You are an expert programming instructor. Analyze this student code for
programming MISCONCEPTIONS (fundamental misunderstandings, NOT just bugs/typos).

Student's code:
```python
{code}
```

If you find a misconception, respond:
<misconception>
<description>Concise description</description>
<explanation>What the student believes vs reality</explanation>
<confidence>high/medium/low</confidence>
</misconception>

If no misconception: <misconception>NONE</misconception>"""


def init_mcminer(api_key):
    import google.generativeai as genai
    genai.configure(api_key=api_key)
    return genai.GenerativeModel("gemini-2.5-flash")


def run_mcminer(model, code):
    """Run McMiner on code. Returns (detected, description) tuple."""
    try:
        resp = model.generate_content(MCMINER_PROMPT.format(code=code))
        raw = resp.text
        desc = re.search(r"<description>(.*?)</description>", raw, re.DOTALL)
        if desc and "NONE" not in raw:
            return (True, desc.group(1).strip())
        return (False, None)
    except Exception as e:
        print(f"    ⚠️ McMiner error: {e}")
        return (False, None)


# ── Diagnostic Codegen ───────────────────────────────────
def generate_diagnostic_code(client, model_name, prompt_text):
    """Generate a single code completion for misconception diagnosis."""
    try:
        import uuid
        # Inject unique seed to bust HF API response cache
        seed = f"\n[seed:{uuid.uuid4().hex[:8]}]"
        msgs = [{"role": "user", "content": prompt_text + seed}]
        resp = client.chat.completions.create(
            model=model_name, messages=msgs,
            temperature=0.4, top_p=0.95, max_tokens=1024, n=1
        )
        return resp.choices[0].message.content.strip()
    except Exception as e:
        print(f"    ⚠️ Codegen error: {e}")
        return ""


# ── Misconception Formatting ─────────────────────────────
def format_misconception(round_idx, description):
    """Format a single misconception for injection into tutor prompt."""
    return (
        "\n\n[MISCONCEPTION FEEDBACK]\n"
        "The student's latest code attempt (after round {round}) shows the following misconception. "
        "Address this directly in your next response:\n\n"
        "- {desc}\n"
        "[END MISCONCEPTION FEEDBACK]"
    ).format(round=round_idx, desc=description)


def inject_misconception(original_desc, round_idx, description):
    """Insert latest misconception before the last paragraph of tutor desc.
    Replaces any previous injection. If description is None, returns original."""
    if description is None:
        return original_desc
    parts = original_desc.split("\n\n")
    mc_text = format_misconception(round_idx, description)
    parts.insert(-1, mc_text)
    return "\n\n".join(parts)


# ── Main Loop ────────────────────────────────────────────
def run_mcminer_loop(args, prompt_data, elements, tutor_backend, student_backend,
                     moderator_backend, verifier_model, verifier_data_builder,
                     codegen_client, gemini_model, tokenizer):
    """Run round-by-round dialogue with McMiner injection."""

    model_name = args.tutor_model_name_or_path.split("/")[-1]
    output_subdir = os.path.join(args.output_dir,
                                 f"traver/{model_name}/{args.student_setting}")
    os.makedirs(output_subdir, exist_ok=True)
    output_path = os.path.join(output_subdir, "simulated_dialogs.jsonl")

    finished_data = load_finished_data(output_path)
    print(f"  Skip {len(finished_data)} finished tasks.")
    total = len([j for j in prompt_data if j['namespace'] not in finished_data])
    print(f"  Running {total} tasks with McMiner-in-the-loop (latest-only injection)...")

    with open(output_path, "a", encoding='utf-8') as fw:
        for task_idx, js in enumerate(prompt_data):
            ns = js["namespace"]
            if ns in finished_data:
                continue

            # Find matching prompt element for posttest prompt building
            elem = None
            for e in elements:
                if e["namespace"] == ns:
                    elem = e
                    break
            if elem is None:
                print(f"  ⚠️ No element for {ns}, skipping")
                continue

            if verifier_data_builder is not None:
                verifier_data_builder.set_namespace(namespace=ns)

            original_tutor_desc = js["tutor_desc"]
            all_misconceptions = []  # full log for saving
            current_misconception = None  # only latest for injection

            # Create arena components
            tutor = Tutor(
                role_desc=original_tutor_desc, KT_desc=js["KT_desc"],
                backend=tutor_backend, request_prompt=js["request_prompt"],
                verifier=verifier_model, verifier_data_builder=verifier_data_builder,
                num_responses=args.tutor_num_responses,
                use_KT=str2bool(args.use_KT)
            )
            student = Player(name="student", role_desc=js["student_desc"],
                             backend=student_backend)
            moderator = Moderator(
                role_desc=js["moderator_desc"], backend=moderator_backend,
                terminal_condition="According to the dialogue history above, do you think the tutor's goal is completed? Please answer 'yes' or 'no'.",
            )
            env = TutoringConversation(
                player_names=[tutor.name, student.name],
                moderator=moderator, moderator_period="round"
            )
            arena = TutoringArena(players=[tutor, student], environment=env)

            print(f"\n{'='*60}")
            print(f"  Task {task_idx+1}: {ns}")
            print(f"{'='*60}")

            MIN_ROUNDS = 2  # Force at least 2 rounds before allowing early stop

            for round_idx in range(args.max_interaction_round):
                t0 = time.time()
                rnd = round_idx + 1

                # ── Tutor speaks ──
                try:
                    ts = arena.step()
                except Exception as e:
                    print(f"    R{rnd} tutor error: {e}")
                    break

                # Print tutor message
                msgs_so_far = env.get_observation()
                tutor_msg = msgs_so_far[-1].content if msgs_so_far else "(empty)"
                print(f"\n    ┌─ R{rnd} TUTOR ─────────────────────────────────")
                for line in tutor_msg.split('\n'):
                    print(f"    │ {line}")
                print(f"    └────────────────────────────────────────────")

                if ts.terminal and rnd > MIN_ROUNDS:
                    print(f"    ⚠️  Early stop (after tutor, R{rnd})")
                    break
                elif ts.terminal:
                    print(f"    ⏩ Ignoring early stop at R{rnd} (min {MIN_ROUNDS} rounds)")

                # ── Student responds ──
                try:
                    ts = arena.step()
                except Exception as e:
                    print(f"    R{rnd} student error: {e}")
                    break

                # Print student message
                msgs_so_far = env.get_observation()
                student_msg = msgs_so_far[-1].content if msgs_so_far else "(empty)"
                print(f"\n    ┌─ R{rnd} STUDENT ───────────────────────────────")
                for line in student_msg.split('\n'):
                    print(f"    │ {line}")
                print(f"    └────────────────────────────────────────────")

                # ── Extract conversation ──
                messages = env.get_observation()
                conversation = []
                for msg in messages:
                    if msg.agent_name == tutor.name:
                        conversation.append({"tutor": msg.content})
                    else:
                        conversation.append({"student": msg.content})

                # ── Build posttest prompt & generate diagnostic code ──
                posttest_prompt = prompt_student_posttest(
                    conversation, elem, tokenizer,
                    level=args.student_setting,
                    max_code_context=args.max_code_context
                )

                # Print posttest prompt (truncated)
                print(f"\n    ┌─ R{rnd} POSTTEST PROMPT ({len(posttest_prompt)} chars) ──────")
                prompt_preview = posttest_prompt[:500]
                for line in prompt_preview.split('\n'):
                    print(f"    │ {line}")
                if len(posttest_prompt) > 500:
                    print(f"    │ ... ({len(posttest_prompt) - 500} more chars)")
                print(f"    └────────────────────────────────────────────")

                code = generate_diagnostic_code(
                    codegen_client, args.codegen_model, posttest_prompt
                )

                # Print generated code
                print(f"\n    ┌─ R{rnd} GENERATED CODE ({len(code)} chars) ──────────")
                code_preview = code[:600]
                for line in code_preview.split('\n'):
                    print(f"    │ {line}")
                if len(code) > 600:
                    print(f"    │ ... ({len(code) - 600} more chars)")
                print(f"    └────────────────────────────────────────────")

                # ── Run McMiner ──
                detected, desc = run_mcminer(gemini_model, code)
                elapsed = time.time() - t0

                if detected:
                    current_misconception = desc
                    all_misconceptions.append((rnd, desc))
                    print(f"\n    ┌─ R{rnd} McMINER RESULT ─────────────────────")
                    print(f"    │ 🔴 MISCONCEPTION DETECTED")
                    for line in desc.split('\n'):
                        print(f"    │ {line}")
                    print(f"    └────────────────────────────────────────────")
                    # Inject ONLY latest into tutor prompt (replace, not accumulate)
                    tutor.role_desc = inject_misconception(
                        original_tutor_desc, rnd, current_misconception
                    )
                    print(f"    📝 Injected into tutor prompt for R{rnd+1}")
                else:
                    current_misconception = None
                    # No misconception → tutor operates with original prompt
                    tutor.role_desc = original_tutor_desc
                    print(f"\n    ┌─ R{rnd} McMINER RESULT ─────────────────────")
                    print(f"    │ ✅ No misconception detected")
                    print(f"    └────────────────────────────────────────────")

                print(f"    ⏱️  Round {rnd} total: {elapsed:.1f}s")

                if ts.terminal and rnd > MIN_ROUNDS:
                    print(f"    ⚠️  Early stop (moderator, R{rnd})")
                    break
                elif ts.terminal:
                    print(f"    ⏩ Ignoring early stop at R{rnd} (min {MIN_ROUNDS} rounds)")

            # ── Save dialogue + misconceptions ──
            messages = env.get_observation()
            simulated_convs = []
            for msg in messages:
                if msg.agent_name == tutor.name:
                    simulated_convs.append({"tutor": msg.content})
                else:
                    simulated_convs.append({"student": msg.content})

            thoughts = env.get_thought(player_name=tutor.name)
            tutor_thoughts = []
            for thought in thoughts:
                tutor_thoughts.append({
                    "turn": thought.turn,
                    "agent_name": thought.agent_name,
                    "response_candidates": thought.candidates
                })

            write_line = {
                "namespace": ns,
                "conversation": simulated_convs,
                "tutor_thoughts": tutor_thoughts,
                "misconceptions_detected": [
                    {"round": r, "description": d} for r, d in all_misconceptions
                ]
            }
            fw.write(json.dumps(write_line, ensure_ascii=False) + "\n")
            fw.flush()

            n_mc = len(all_misconceptions)
            n_rounds = len(simulated_convs) // 2
            print(f"  ✅ {ns}: {n_rounds} rounds, {n_mc} misconceptions")

    convert_to_json(output_path, output_path.replace(".jsonl", ".json"))
    print(f"\n💾 Saved to {output_path}")


def main():
    args = parse_args()
    print(f"\n{'='*60}")
    print(f"  McMiner-in-the-Loop TRAVER")
    print(f"  Level: {args.student_setting}")
    print(f"  Tutor: {args.tutor_model_name_or_path}")
    print(f"  Codegen: {args.codegen_model}")
    print(f"{'='*60}\n")

    tokenizer = tiktoken.encoding_for_model("gpt-4")
    prompt_elements = load_json_data(args.prompt_element_file)

    # Init McMiner (Gemini)
    gemini_model = init_mcminer(args.google_api_key)
    print("✅ McMiner (Gemini) ready")

    # Init codegen client
    from openai import OpenAI
    codegen_client = OpenAI(api_key=args.vllm_api_key, base_url=args.codegen_api_base)
    print(f"✅ Codegen client ready ({args.codegen_model})")

    # Init backends
    tutor_backend = VLLMChat(
        vllm_api_key=args.vllm_api_key, vllm_endpoint=args.vllm_endpoint_tutor,
        model_name_or_path=args.tutor_model_name_or_path,
        temperature=args.temperature, top_p=args.top_p,
        max_tokens=args.tutor_max_tokens, max_latest_messages=args.max_latest_messages
    )
    student_backend = VLLMChat(
        vllm_api_key=args.vllm_api_key, vllm_endpoint=args.vllm_endpoint_student,
        model_name_or_path=args.student_model_name_or_path,
        max_tokens=args.student_max_tokens, max_latest_messages=args.max_latest_messages,
        temperature=0.4, top_p=0.95
    )
    moderator_backend = VLLMChat(
        vllm_api_key=args.vllm_api_key, vllm_endpoint=args.vllm_endpoint_student,
        model_name_or_path=args.student_model_name_or_path,
        temperature=0.1, top_p=0.95, max_tokens=100, max_latest_messages=-1
    )
    print("✅ Tutor/Student/Moderator backends ready")

    # Load verifier + run
    namespaces_cfg = load_json_dict(args.namespace_file)
    part_lists = namespaces_cfg["part_lists"]
    verifier_parts = [p for p in args.verifier_model_parts.split(",")]
    verifier_template = open('prompt/template/verifier.txt', 'r').read()

    for idx, part_namespaces in enumerate(part_lists):
        part_idx = verifier_parts[idx] if idx < len(verifier_parts) else str(idx)
        verifier_path = os.path.join(args.verifier_model_dir, f"part{part_idx}", "pytorch_model.bin")
        print(f"\n🔧 Loading verifier part {part_idx}: {verifier_path}")

        if idx > 0:
            del verifier_model, verifier_tokenizer
            import gc; gc.collect()
            torch.cuda.empty_cache()

        verifier_model, verifier_tokenizer = load_model(
            base_model_name_or_path=args.verifier_base_model_path,
            trained_verifier_model_path=verifier_path
        )

        elements = [d for d in prompt_elements if d["namespace"] in part_namespaces]
        verifier_data_builder = OnlineDataBuilder(
            elements=elements, data_template=verifier_template,
            tokenizer=verifier_tokenizer, max_length=args.verifier_max_length
        )

        prompt_data = []
        for d in elements:
            prompt_data.append({
                "namespace": d['namespace'],
                "tutor_desc": prompt_tutor(d, tokenizer, setting="base",
                                           max_code_context=args.max_code_context),
                "KT_desc": prompt_tutor(d, tokenizer, setting="KT"),
                "request_prompt": prompt_tutor(d, tokenizer, setting="RG"),
                "student_desc": prompt_student(d, tokenizer, level=args.student_setting,
                                               max_code_context=args.max_code_context,
                                               is_pretest=False),
                "moderator_desc": prompt_moderator(d, tokenizer,
                                                   max_code_context=args.max_code_context)
            })

        run_mcminer_loop(
            args, prompt_data, elements,
            tutor_backend, student_backend, moderator_backend,
            verifier_model, verifier_data_builder,
            codegen_client, gemini_model, tokenizer
        )

    print("\n✅ McMiner-in-the-Loop dialogue complete!")


if __name__ == '__main__':
    main()
