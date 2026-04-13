"""
API-based LM inference for HPC (no local model needed).
Drop-in replacement for LM_inference.py that uses an OpenAI-compatible API
(Groq, Together AI, HuggingFace, etc.) instead of loading the model locally.

Usage:
    python traver/utils/LM_inference_api.py \
        --prompt_file prompt.jsonl \
        --output_dir output/ \
        --model_name_or_path meta-llama/Llama-3.1-8B-Instruct \
        --api_base https://api.groq.com/openai/v1 \
        --api_key gsk_xxx
"""

import json
import os
import re
import time
from tqdm import tqdm
from argparse import ArgumentParser
from openai import OpenAI


def parse_args():
    parser = ArgumentParser()
    parser.add_argument('--prompt_file', type=str, required=True)
    parser.add_argument("--output_dir", type=str, required=True)
    parser.add_argument("--model_name_or_path", type=str,
                        default="meta-llama/Llama-3.1-8B-Instruct")
    parser.add_argument('--decoding', type=str, default='sampling',
                        choices=['greedy', 'sampling'])
    parser.add_argument("--max_tokens", type=int, default=500)
    parser.add_argument('--T', type=float, default=0.4)
    parser.add_argument('--top_p', type=float, default=0.95)
    parser.add_argument('--N', type=int, default=10)
    parser.add_argument("--yes_or_no_required", action='store_true')

    # API config
    parser.add_argument('--api_base', type=str,
                        default=os.environ.get('LLAMA_API_ENDPOINT',
                                               'https://api.groq.com/openai/v1'))
    parser.add_argument('--api_key', type=str,
                        default=os.environ.get('GROQ_API_KEY', ''))
    parser.add_argument('--rate_limit_delay', type=float, default=0.5,
                        help="Seconds to wait between API calls (rate limiting)")

    return parser.parse_args()


def load_finished_data(output_file):
    finished = set()
    if os.path.exists(output_file):
        with open(output_file, 'r') as f:
            for line in f:
                js = json.loads(line)
                finished.add(js['namespace'])
    return finished


def api_generate(client, model, prompt, n, temperature, top_p, max_tokens):
    """Generate n completions via OpenAI-compatible API."""
    completions = []

    # Most API providers don't support n>1, so we loop
    for _ in range(n):
        try:
            response = client.chat.completions.create(
                model=model,
                messages=[{"role": "user", "content": prompt}],
                temperature=temperature,
                top_p=top_p,
                max_tokens=max_tokens,
            )
            completions.append(response.choices[0].message.content)
        except Exception as e:
            print(f"  API error: {e}")
            completions.append("")
            time.sleep(2)  # Back off on error

    return completions


def main():
    args = parse_args()

    if not args.api_key:
        raise ValueError(
            "API key required. Set LLAMA_API_KEY env var or use --api_key")

    if args.yes_or_no_required:
        args.N = 1
    if args.decoding == 'greedy':
        args.T = 0
        args.top_p = 1
        args.N = 1

    print(f"Model:    {args.model_name_or_path}")
    print(f"API base: {args.api_base}")
    print(f"N:        {args.N}")
    print(f"Temp:     {args.T}")

    client = OpenAI(
        api_key=args.api_key,
        base_url=args.api_base
    )

    # Verify connectivity
    try:
        models = client.models.list()
        available = [m.id for m in models.data]
        print(f"Available models: {available[:5]}...")
    except Exception as e:
        print(f"⚠  Could not list models: {e}")

    if not os.path.exists(args.output_dir):
        os.makedirs(args.output_dir)

    output_file = os.path.join(args.output_dir, 'completion_lm.jsonl')
    finished_data = load_finished_data(output_file)
    print(f"Skipping {len(finished_data)} already completed tasks")

    if not os.path.exists(args.prompt_file):
        print(f"Prompt file not found: {args.prompt_file}")
        return

    with open(args.prompt_file, 'r') as f_in:
        lines = f_in.readlines()

    with open(output_file, 'a') as f_out:
        for line in tqdm(lines):
            js = json.loads(line)
            prompt = js['prompt']
            task_id = js['namespace']

            if task_id in finished_data:
                continue

            if args.yes_or_no_required:
                max_tries = 3
                result = "no"
                for attempt in range(max_tries):
                    completions = api_generate(
                        client, args.model_name_or_path, prompt,
                        1, args.T, args.top_p, args.max_tokens
                    )
                    text = completions[0].strip().lower() if completions else ""
                    if re.match(
                        r"yes|y|yea|yeah|yep|yup|sure|ok|okay|alright",
                        text, re.IGNORECASE
                    ):
                        result = "yes"
                        break
                    elif re.match(
                        r"no|n|nope|nah|nay", text, re.IGNORECASE
                    ):
                        result = "no"
                        break
                completions = result
            else:
                completions = api_generate(
                    client, args.model_name_or_path, prompt,
                    args.N, args.T, args.top_p, args.max_tokens
                )

            cases = {'namespace': task_id, 'completion': completions}
            f_out.write(json.dumps(cases) + '\n')
            f_out.flush()

            # Rate limiting
            time.sleep(args.rate_limit_delay)

    print(f"Done. Output: {output_file}")


if __name__ == '__main__':
    main()
