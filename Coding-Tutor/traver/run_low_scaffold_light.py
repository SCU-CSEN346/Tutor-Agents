# -*- coding: utf-8 -*-
"""Run a light low-level scaffold condition for TRAVER.

This variant tests the core scaffold idea without the heavy interventions from
run_low_scaffold_traver.py: it does not force extra moderator rounds, and it
only gives the tutor a compact list of likely repository API names.
"""

import argparse
import copy
import re
import sys

import run_traver


LIGHT_SCAFFOLD_GUIDANCE = """

Low-Level Scaffold Policy:
- Help the student build one executable step at a time.
- Prefer concrete inputs, outputs, API roles, and tiny code skeletons.
- Mention only APIs that are clearly relevant to the current task.
- Do not reveal a full reference solution or add unrelated reference steps.
- Keep each tutor response short and ask for exactly one next action.
"""


def build_light_api_hint_block(d, max_calls=4):
    reference_code = d.get("reference_code", "") or ""
    call_names = []
    for match in re.finditer(r"\b([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+)\s*\(", reference_code):
        name = match.group(1)
        if name not in call_names:
            call_names.append(name)
        if len(call_names) >= max_calls:
            break

    if not call_names:
        return ""

    parts = ["\n\n[LOW-LEVEL API AFFORDANCES]"]
    parts.append("Likely repository/API names to explain only if useful:")
    parts.extend(f"- {name}" for name in call_names)
    parts.append("[END LOW-LEVEL API AFFORDANCES]")
    return "\n".join(parts)


def parse_wrapper_args():
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument(
        "--scaffold_tutor_setting",
        type=str,
        default="traver_low_scaffold_light",
        help="Output tutor_setting name for this experiment.",
    )
    wrapper_args, remaining = parser.parse_known_args()
    return wrapper_args, remaining


def main():
    wrapper_args, remaining = parse_wrapper_args()
    sys.argv = [sys.argv[0], *remaining]
    args = run_traver.parse_args()

    if args.student_setting != "low_level":
        raise ValueError("run_low_scaffold_light.py is only intended for --student_setting low_level")

    args.tutor_setting = wrapper_args.scaffold_tutor_setting

    original_prompt_tutor = run_traver.prompt_tutor

    def prompt_tutor_with_light_scaffold(d, tokenizer, setting="base", max_code_context=1024):
        prompt = original_prompt_tutor(
            d,
            tokenizer,
            setting=setting,
            max_code_context=max_code_context,
        )
        if setting == "base":
            prompt = f"{prompt}{build_light_api_hint_block(d)}{LIGHT_SCAFFOLD_GUIDANCE}"
        return prompt

    run_traver.prompt_tutor = prompt_tutor_with_light_scaffold

    log_args = copy.copy(args)
    if getattr(log_args, "vllm_api_key", None):
        log_args.vllm_api_key = "<redacted>"
    print(log_args)
    print("Light low-level scaffold policy enabled; moderator stopping is unchanged.")
    run_traver.main(args)


if __name__ == "__main__":
    main()
