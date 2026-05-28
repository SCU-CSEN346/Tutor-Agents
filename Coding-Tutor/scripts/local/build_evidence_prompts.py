import argparse
import json
import os
from pathlib import Path

from openai import OpenAI


def load_jsonl(path):
    with open(path) as f:
        for line in f:
            if line.strip():
                yield json.loads(line)


def read_lines(path, start, end):
    lines = path.read_text(errors="replace").splitlines()
    start = max(1, start)
    end = min(len(lines), end)
    return "\n".join(f"{i}: {lines[i - 1]}" for i in range(start, end + 1))


def source_context(source_root, item, radius=80):
    source_path = Path(source_root) / item["completion_path"]
    sig = item["signature_position"][0]
    body_start, body_end = item["body_position"]
    start = max(1, sig - 35)
    end = body_end + radius
    return read_lines(source_path, start, end)


def test_context(source_root, item, max_chars=5000):
    project = item["completion_path"].split("/")[0]
    project_root = Path(source_root) / project
    chunks = []
    seen = set()
    for test in item.get("tests", []):
        test_file = test.split("::", 1)[0]
        if test_file in seen:
            continue
        seen.add(test_file)
        path = project_root / test_file
        if not path.exists():
            continue
        text = path.read_text(errors="replace")
        chunks.append(f"# {test_file}\n{text[:max_chars]}")
    return "\n\n".join(chunks)


def build_note_prompt(item, src_ctx, tst_ctx):
    req = item.get("requirement", {})
    tests = "\n".join(f"- {t}" for t in item.get("tests", []))
    return f"""You are a student reading a repository before coding.

Target function: {item['namespace']}

Function requirement:
{req.get('Functionality', '')}
{req.get('Arguments', '')}

Relevant source excerpt:
```python
{src_ctx}
```

Relevant test files/excerpts:
```python
{tst_ctx}
```

Tests that will be run:
{tests}

Write a short evidence note for yourself before coding.
Rules:
- Do not write the solution algorithm.
- Do not write final code.
- Only list evidence visible in the source/tests.
- Mention relevant existing variables, methods, return type, and test expectations.
- Keep it under 90 words.
"""


def generate_note(client, model, prompt):
    response = client.chat.completions.create(
        model=model,
        messages=[{"role": "user", "content": prompt}],
        temperature=0.2,
        top_p=0.9,
        max_tokens=180,
    )
    return response.choices[0].message.content.strip()


def inject_note(prompt, note):
    block = (
        "\n\nBefore writing code, I read the repository/tests and wrote this evidence note:\n"
        f"{note}\n"
        "Use this evidence only as repository-reading context. Now complete the function.\n"
    )
    marker = "\n\nPlease directly complete"
    if marker in prompt:
        return prompt.replace(marker, block + marker, 1)
    return prompt + block


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prompt_file", required=True)
    parser.add_argument("--metadata_file", required=True)
    parser.add_argument("--source_code_root", required=True)
    parser.add_argument("--output_prompt_file", required=True)
    parser.add_argument("--notes_file", required=True)
    parser.add_argument("--project_prefix", default="easyvolcap.")
    parser.add_argument("--model", default="meta-llama/Llama-3.3-70B-Instruct")
    parser.add_argument("--api_base", default="https://router.huggingface.co/v1")
    parser.add_argument("--api_key", default=os.environ.get("HF_TOKEN", ""))
    args = parser.parse_args()

    if not args.api_key:
        raise ValueError("HF_TOKEN or --api_key is required")

    metadata = {
        item["namespace"]: item
        for item in load_jsonl(args.metadata_file)
        if item["namespace"].startswith(args.project_prefix)
    }
    prompts = [
        item
        for item in load_jsonl(args.prompt_file)
        if item["namespace"] in metadata
    ]

    notes_path = Path(args.notes_file)
    notes_path.parent.mkdir(parents=True, exist_ok=True)
    existing = {}
    if notes_path.exists():
        for item in load_jsonl(notes_path):
            existing[item["namespace"]] = item["evidence_note"]

    client = OpenAI(api_key=args.api_key, base_url=args.api_base)
    out_prompts = []

    with notes_path.open("a") as notes_out:
        for prompt_item in prompts:
            namespace = prompt_item["namespace"]
            if namespace not in existing:
                item = metadata[namespace]
                note_prompt = build_note_prompt(
                    item,
                    source_context(args.source_code_root, item),
                    test_context(args.source_code_root, item),
                )
                note = generate_note(client, args.model, note_prompt)
                notes_out.write(json.dumps({
                    "namespace": namespace,
                    "evidence_note": note,
                }) + "\n")
                notes_out.flush()
                existing[namespace] = note
                print(f"generated evidence: {namespace}")
            else:
                print(f"cached evidence: {namespace}")

            updated = dict(prompt_item)
            updated["prompt"] = inject_note(prompt_item["prompt"], existing[namespace])
            out_prompts.append(updated)

    out_path = Path(args.output_prompt_file)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w") as f:
        for item in out_prompts:
            f.write(json.dumps(item) + "\n")
    print(f"wrote {len(out_prompts)} prompts to {out_path}")


if __name__ == "__main__":
    main()
