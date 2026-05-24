# -*- coding: utf-8 -*-
"""Run the low-level scaffolded TRAVER condition.

This experiment is motivated by the project finding that low-level students do
better without McMiner: they need executable scaffolding and enough dialogue
turns before final code generation, not misconception diagnosis.
"""

import argparse
import copy
import re
import sys

import run_traver


SCAFFOLD_GUIDANCE = """

Low-Level Scaffold Policy:
- Do not use misconception-mining language or diagnose hidden beliefs.
- Assume the student needs help building an executable solution structure.
- Prefer concrete scaffolding over abstract explanations.
- In early turns, identify the function inputs, expected output, and one
  relevant dependency/API at a time.
- When useful, provide a small code skeleton with placeholders, then ask the
  student to fill exactly one missing line or branch.
- Use one simple test-case trace when the logic is unclear.
- Keep each response under 60 words and focus on one action.
"""


def _compact_lines(text, limit=5):
    lines = []
    for raw in (text or "").splitlines():
        line = raw.strip()
        if line and line not in lines:
            lines.append(line)
        if len(lines) >= limit:
            break
    return lines


def build_api_hint_block(d):
    """Build compact project/API hints for low-level tutoring.

    The block avoids pasting the full reference solution. It gives the tutor
    concrete API names and relevant solution actions so low-level dialogue can
    focus on repository usage rather than abstract diagnosis.
    """
    dependency_lines = _compact_lines(d.get("dependency_sampled") or d.get("dependency_all"), limit=6)
    step_lines = _compact_lines(d.get("reference_steps"), limit=4)

    reference_code = d.get("reference_code", "")
    call_names = []
    for match in re.finditer(r"\b([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+)\s*\(", reference_code):
        name = match.group(1)
        if name not in call_names:
            call_names.append(name)
        if len(call_names) >= 6:
            break

    if not dependency_lines and not step_lines and not call_names:
        return ""

    parts = ["\n\n[LOW-LEVEL API HINTS]"]
    if dependency_lines:
        parts.append("Relevant repository dependencies:")
        parts.extend(f"- {line}" for line in dependency_lines)
    if call_names:
        parts.append("Likely API calls/utilities to explain concretely:")
        parts.extend(f"- {name}" for name in call_names)
    if step_lines:
        parts.append("Use these as scaffolded teaching checkpoints, not as a full answer:")
        parts.extend(f"- {line}" for line in step_lines)
    parts.append("[END LOW-LEVEL API HINTS]")
    return "\n".join(parts)


def parse_wrapper_args():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument(
        "--min_low_level_rounds",
        type=int,
        default=6,
        help="Minimum full tutor/student rounds before the moderator may stop.",
    )
    parser.add_argument(
        "--scaffold_tutor_setting",
        type=str,
        default="traver_low_scaffold",
        help="Output tutor_setting name for this experiment.",
    )
    wrapper_args, remaining = parser.parse_known_args()
    return wrapper_args, remaining


def main():
    wrapper_args, remaining = parse_wrapper_args()
    sys.argv = [sys.argv[0], *remaining]
    args = run_traver.parse_args()

    if args.student_setting != "low_level":
        raise ValueError("run_low_scaffold_traver.py is only intended for --student_setting low_level")

    args.tutor_setting = wrapper_args.scaffold_tutor_setting

    original_prompt_tutor = run_traver.prompt_tutor

    def prompt_tutor_with_scaffold(d, tokenizer, setting="base", max_code_context=1024):
        prompt = original_prompt_tutor(
            d,
            tokenizer,
            setting=setting,
            max_code_context=max_code_context,
        )
        if setting == "base":
            prompt = f"{prompt}{build_api_hint_block(d)}{SCAFFOLD_GUIDANCE}"
        return prompt

    original_conversation = run_traver.TutoringConversation

    class LowScaffoldTutoringConversation(original_conversation):
        def __init__(self, *args, **kwargs):
            kwargs.setdefault("min_moderator_rounds", wrapper_args.min_low_level_rounds)
            super().__init__(*args, **kwargs)

    run_traver.prompt_tutor = prompt_tutor_with_scaffold
    run_traver.TutoringConversation = LowScaffoldTutoringConversation

    log_args = copy.copy(args)
    if getattr(log_args, "vllm_api_key", None):
        log_args.vllm_api_key = "<redacted>"
    print(log_args)
    print(f"Low-level scaffold policy enabled; min rounds = {wrapper_args.min_low_level_rounds}")
    run_traver.main(args)


if __name__ == "__main__":
    main()
