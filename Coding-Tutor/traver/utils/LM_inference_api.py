"""
API-based LM inference for HPC (no local model needed).
Drop-in replacement for LM_inference.py that uses an OpenAI-compatible API
(Groq, Together AI, HuggingFace, etc.) instead of loading the model locally.

Uses asyncio for concurrent API calls:
  - All N completions per task fire simultaneously
  - Up to --max_concurrent_tasks tasks process in parallel
  - Exponential backoff with jitter on rate-limit (429) errors

Usage:
    python traver/utils/LM_inference_api.py \
        --prompt_file prompt.jsonl \
        --output_dir output/ \
        --model_name_or_path meta-llama/Llama-3.1-8B-Instruct \
        --api_base https://api.groq.com/openai/v1 \
        --api_key gsk_xxx \
        --max_concurrent_tasks 5
"""

import asyncio
import json
import os
import random
import re
import time
from tqdm import tqdm
from argparse import ArgumentParser
from openai import AsyncOpenAI


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

    # Async concurrency config
    parser.add_argument('--max_concurrent_tasks', type=int, default=5,
                        help="Max number of tasks to process in parallel")
    parser.add_argument('--max_retries', type=int, default=8,
                        help="Max retries per API call on rate-limit errors")

    return parser.parse_args()


def load_finished_data(output_file):
    finished = set()
    if os.path.exists(output_file):
        with open(output_file, 'r') as f:
            for line in f:
                js = json.loads(line)
                finished.add(js['namespace'])
    return finished


async def async_single_completion(client, model, prompt, temperature, top_p,
                                  max_tokens, max_retries):
    """Make a single API call with exponential backoff on rate-limit errors."""
    for attempt in range(max_retries):
        try:
            response = await client.chat.completions.create(
                model=model,
                messages=[{"role": "user", "content": prompt}],
                temperature=temperature,
                top_p=top_p,
                max_tokens=max_tokens,
            )
            return response.choices[0].message.content
        except Exception as e:
            error_str = str(e).lower()
            if '429' in error_str or 'rate' in error_str:
                # Exponential backoff with jitter
                wait = min(2 ** attempt + random.uniform(0, 1), 60)
                print(f"  Rate limited (attempt {attempt + 1}/{max_retries}), "
                      f"waiting {wait:.1f}s...")
                await asyncio.sleep(wait)
            else:
                print(f"  API error: {e}")
                return ""
    print(f"  Max retries ({max_retries}) exceeded, returning empty string")
    return ""


async def async_api_generate(client, model, prompt, n, temperature, top_p,
                              max_tokens, max_retries):
    """Generate n completions concurrently via asyncio.gather()."""
    tasks = [
        async_single_completion(client, model, prompt, temperature, top_p,
                                max_tokens, max_retries)
        for _ in range(n)
    ]
    return await asyncio.gather(*tasks)


async def async_yes_or_no(client, model, prompt, temperature, top_p,
                           max_tokens, max_retries):
    """Handle yes/no classification with sequential retries."""
    max_tries = 3
    for attempt in range(max_tries):
        result = await async_single_completion(
            client, model, prompt, temperature, top_p, max_tokens, max_retries
        )
        text = result.strip().lower() if result else ""
        if re.match(r"yes|y|yea|yeah|yep|yup|sure|ok|okay|alright",
                    text, re.IGNORECASE):
            return "yes"
        elif re.match(r"no|n|nope|nah|nay", text, re.IGNORECASE):
            return "no"
    return "no"


async def process_task(semaphore, client, args, js, f_out, pbar):
    """Process a single task (all N completions) under the semaphore."""
    async with semaphore:
        prompt = js['prompt']
        task_id = js['namespace']

        if args.yes_or_no_required:
            completions = await async_yes_or_no(
                client, args.model_name_or_path, prompt,
                args.T, args.top_p, args.max_tokens, args.max_retries
            )
        else:
            results = await async_api_generate(
                client, args.model_name_or_path, prompt,
                args.N, args.T, args.top_p, args.max_tokens, args.max_retries
            )
            completions = list(results)

        cases = {'namespace': task_id, 'completion': completions}
        f_out.write(json.dumps(cases) + '\n')
        f_out.flush()
        pbar.update(1)


async def async_main(args, todo_tasks):
    """Main async entry point: process all tasks with bounded concurrency."""
    client = AsyncOpenAI(
        api_key=args.api_key,
        base_url=args.api_base
    )

    semaphore = asyncio.Semaphore(args.max_concurrent_tasks)
    output_file = os.path.join(args.output_dir, 'completion_lm.jsonl')

    with open(output_file, 'a') as f_out:
        with tqdm(total=len(todo_tasks), desc="Generating") as pbar:
            tasks = [
                process_task(semaphore, client, args, js, f_out, pbar)
                for js in todo_tasks
            ]
            await asyncio.gather(*tasks)


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
    print(f"Concurrency: {args.max_concurrent_tasks} tasks in parallel")

    # Verify connectivity (synchronous, one-off check)
    from openai import OpenAI
    sync_client = OpenAI(api_key=args.api_key, base_url=args.api_base)
    try:
        models = sync_client.models.list()
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

    # Load all tasks and filter out finished ones
    todo_tasks = []
    with open(args.prompt_file, 'r') as f_in:
        for line in f_in:
            js = json.loads(line)
            if js['namespace'] not in finished_data:
                todo_tasks.append(js)

    print(f"TODO tasks: {len(todo_tasks)}")

    if not todo_tasks:
        print("All tasks already completed!")
        return

    start = time.time()
    asyncio.run(async_main(args, todo_tasks))
    elapsed = time.time() - start

    print(f"Done. Output: {output_file}")
    print(f"Wall time: {elapsed:.1f}s ({elapsed/60:.1f} min)")


if __name__ == '__main__':
    main()
