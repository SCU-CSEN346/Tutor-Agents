#!/usr/bin/env python3
"""
Create a data subset for HPC experiments with limited storage.

Filters prompt_elements, namespaces, and EvoCodeBench metadata to only
include tasks from selected cross-validation folds. Also creates a script
to subset the EvoCodeBench Source_Code and Dependency_Data directories.

Usage:
    python scripts/hpc/create_subset.py \
        --folds 0 1 \
        --output_dir hpc_subset \
        --evocodebench_root /path/to/EvoCodeBench-2403 \
        --max_data_gb 5.0
"""

import os
import sys
import json
import shutil
import argparse
from collections import defaultdict


def parse_args():
    parser = argparse.ArgumentParser(description="Create HPC data subset")
    parser.add_argument(
        "--folds", type=int, nargs="+", default=[0, 1],
        help="Which cross-validation folds to include (0-4). Default: 0 1"
    )
    parser.add_argument(
        "--namespace_file", type=str, default="prompt/namespaces.json",
        help="Path to namespaces.json"
    )
    parser.add_argument(
        "--prompt_element_file", type=str, default="prompt/prompt_elements_final.jsonl",
        help="Path to prompt_elements_final.jsonl"
    )
    parser.add_argument(
        "--metadata_file", type=str, default="benchmark/EvoCodeBench-2403/metadata.jsonl",
        help="Path to EvoCodeBench metadata.jsonl"
    )
    parser.add_argument(
        "--evocodebench_root", type=str, default=None,
        help="Path to EvoCodeBench-2403 root (with Source_Code/, Dependency_Data/). "
             "If not provided, only generates the subset list without copying files."
    )
    parser.add_argument(
        "--output_dir", type=str, default="hpc_subset",
        help="Output directory for the subset data"
    )
    parser.add_argument(
        "--max_data_gb", type=float, default=5.0,
        help="Maximum total data size in GB for EvoCodeBench subset"
    )
    return parser.parse_args()


def load_jsonl(path):
    data = []
    with open(path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                data.append(json.loads(line))
    return data


def save_jsonl(data, path):
    os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
    with open(path, "w", encoding="utf-8") as f:
        for item in data:
            f.write(json.dumps(item, ensure_ascii=False) + "\n")


def get_dir_size(path):
    """Get total size of a directory in bytes."""
    total = 0
    if not os.path.exists(path):
        return 0
    for dirpath, dirnames, filenames in os.walk(path):
        for f in filenames:
            fp = os.path.join(dirpath, f)
            if os.path.isfile(fp):
                total += os.path.getsize(fp)
    return total


def main():
    args = parse_args()

    print("=" * 65)
    print("  Coding-Tutor HPC Data Subset Creator")
    print("=" * 65)
    print(f"  Selected folds: {args.folds}")
    print(f"  Max data size:  {args.max_data_gb}GB")
    print(f"  Output dir:     {args.output_dir}")
    print()

    # --- 1. Load and filter namespaces ---
    with open(args.namespace_file, "r") as f:
        ns_data = json.load(f)

    all_namespaces = ns_data["namespaces_all"]
    part_lists = ns_data["part_lists"]
    num_parts = ns_data["num_parts"]

    selected_namespaces = set()
    for fold_idx in args.folds:
        if fold_idx < 0 or fold_idx >= num_parts:
            print(f"  ❌ Fold {fold_idx} out of range (0-{num_parts-1})")
            sys.exit(1)
        selected_namespaces.update(part_lists[fold_idx])

    print(f"  ✓ Selected {len(selected_namespaces)} namespaces from {len(args.folds)} folds")
    print(f"    (out of {len(all_namespaces)} total)")

    # Create filtered namespaces.json
    filtered_ns = {
        "namespaces_all": [ns for ns in all_namespaces if ns in selected_namespaces],
        "num_parts": len(args.folds),
        "part_lists": [part_lists[i] for i in args.folds],
    }

    # --- 2. Filter prompt_elements ---
    prompt_elements = load_jsonl(args.prompt_element_file)
    filtered_prompts = [p for p in prompt_elements if p["namespace"] in selected_namespaces]
    print(f"  ✓ Filtered prompt_elements: {len(filtered_prompts)}/{len(prompt_elements)}")

    # --- 3. Filter EvoCodeBench metadata ---
    if os.path.exists(args.metadata_file):
        metadata = load_jsonl(args.metadata_file)
        # EvoCodeBench metadata uses project-based namespaces; we need to match
        # by checking if the prompt namespace relates to the metadata namespace.
        # The prompt namespaces come from prompt_elements, while metadata has
        # EvoCodeBench task namespaces. We'll keep all metadata entries whose
        # namespace appears in the prompt subset.
        metadata_namespaces = set(m["namespace"] for m in metadata)
        prompt_metadata_overlap = selected_namespaces & metadata_namespaces
        
        if prompt_metadata_overlap:
            filtered_metadata = [m for m in metadata if m["namespace"] in selected_namespaces]
        else:
            # If namespaces don't directly overlap, keep all metadata but note it
            # The prompt_elements and metadata may use different namespace schemes
            filtered_metadata = metadata
            print(f"  ⚠  Namespace schemes differ between prompts and metadata.")
            print(f"     Keeping all {len(metadata)} metadata entries.")
            print(f"     Prompt namespaces sample: {list(selected_namespaces)[:3]}")
            print(f"     Metadata namespaces sample: {list(metadata_namespaces)[:3]}")
    else:
        filtered_metadata = []
        print(f"  ⚠  Metadata file not found: {args.metadata_file}")

    # --- 4. Collect EvoCodeBench project paths needed ---
    needed_projects = set()
    for m in (filtered_metadata if filtered_metadata else []):
        # completion_path format: "ProjectName/path/to/file.py"
        cp = m.get("completion_path", "")
        if "/" in cp:
            needed_projects.add(cp.split("/")[0])

    print(f"  ✓ EvoCodeBench projects needed: {len(needed_projects)}")

    # --- 5. Write subset data ---
    os.makedirs(args.output_dir, exist_ok=True)

    # Save filtered namespaces
    ns_out = os.path.join(args.output_dir, "prompt", "namespaces.json")
    os.makedirs(os.path.dirname(ns_out), exist_ok=True)
    with open(ns_out, "w") as f:
        json.dump(filtered_ns, f, indent=2)
    print(f"  ✓ Saved: {ns_out}")

    # Save filtered prompt_elements
    pe_out = os.path.join(args.output_dir, "prompt", "prompt_elements_final.jsonl")
    save_jsonl(filtered_prompts, pe_out)
    print(f"  ✓ Saved: {pe_out}")

    # Copy prompt_elements.jsonl (original, filter same way)
    pe_orig = args.prompt_element_file.replace("_final", "")
    if os.path.exists(pe_orig):
        orig_prompts = load_jsonl(pe_orig)
        filtered_orig = [p for p in orig_prompts if p["namespace"] in selected_namespaces]
        pe_orig_out = os.path.join(args.output_dir, "prompt", "prompt_elements.jsonl")
        save_jsonl(filtered_orig, pe_orig_out)

    # Save filtered metadata
    if filtered_metadata:
        meta_out = os.path.join(args.output_dir, "benchmark", "EvoCodeBench-2403", "metadata.jsonl")
        save_jsonl(filtered_metadata, meta_out)
        print(f"  ✓ Saved: {meta_out}")

    # Copy prompt templates (small, always needed)
    template_src = os.path.join(os.path.dirname(args.prompt_element_file), "template")
    template_dst = os.path.join(args.output_dir, "prompt", "template")
    if os.path.exists(template_src):
        shutil.copytree(template_src, template_dst, dirs_exist_ok=True)
        print(f"  ✓ Copied prompt templates")

    # --- 6. Subset EvoCodeBench Source_Code and Dependency_Data ---
    if args.evocodebench_root and os.path.exists(args.evocodebench_root):
        source_code_root = os.path.join(args.evocodebench_root, "Source_Code")
        dep_data_root = os.path.join(args.evocodebench_root, "Dependency_Data")

        max_bytes = args.max_data_gb * 1024 * 1024 * 1024
        total_copied = 0

        if os.path.exists(source_code_root):
            src_out = os.path.join(args.output_dir, "EvoCodeBench-2403", "Source_Code")
            os.makedirs(src_out, exist_ok=True)

            # Copy only needed projects, sorted by size (smallest first)
            project_sizes = {}
            for proj in needed_projects:
                proj_path = os.path.join(source_code_root, proj)
                if os.path.exists(proj_path):
                    project_sizes[proj] = get_dir_size(proj_path)

            sorted_projects = sorted(project_sizes.items(), key=lambda x: x[1])
            copied_projects = []
            for proj, size in sorted_projects:
                if total_copied + size > max_bytes:
                    print(f"  ⚠  Skipping {proj} ({size/1e9:.2f}GB) — would exceed {args.max_data_gb}GB limit")
                    continue
                src = os.path.join(source_code_root, proj)
                dst = os.path.join(src_out, proj)
                shutil.copytree(src, dst, dirs_exist_ok=True)
                total_copied += size
                copied_projects.append(proj)

            print(f"  ✓ Copied {len(copied_projects)}/{len(needed_projects)} Source_Code projects "
                  f"({total_copied/1e9:.2f}GB)")

        if os.path.exists(dep_data_root):
            dep_out = os.path.join(args.output_dir, "EvoCodeBench-2403", "Dependency_Data")
            os.makedirs(dep_out, exist_ok=True)

            # Only copy dependency data for projects we have source code for
            for proj in copied_projects:
                dep_proj_path = os.path.join(dep_data_root, proj)
                if os.path.exists(dep_proj_path):
                    dep_size = get_dir_size(dep_proj_path)
                    if total_copied + dep_size > max_bytes:
                        print(f"  ⚠  Skipping dependency data for {proj} ({dep_size/1e9:.2f}GB)")
                        continue
                    dst = os.path.join(dep_out, proj)
                    shutil.copytree(dst_path := dep_proj_path, dst, dirs_exist_ok=True)
                    total_copied += dep_size

            print(f"  ✓ Copied dependency data ({total_copied/1e9:.2f}GB total)")
    else:
        # Generate a script to copy data on HPC instead
        copy_script = os.path.join(args.output_dir, "copy_evocodebench.sh")
        with open(copy_script, "w") as f:
            f.write("#!/bin/bash\n")
            f.write("# Run this on HPC after downloading EvoCodeBench\n")
            f.write("# Usage: bash copy_evocodebench.sh /path/to/EvoCodeBench-2403\n\n")
            f.write('ECB_ROOT="${1:?Usage: bash copy_evocodebench.sh /path/to/EvoCodeBench-2403}"\n')
            f.write(f'SUBSET_DIR="$(dirname "$0")"\n\n')
            f.write(f'mkdir -p "$SUBSET_DIR/EvoCodeBench-2403/Source_Code"\n')
            f.write(f'mkdir -p "$SUBSET_DIR/EvoCodeBench-2403/Dependency_Data"\n\n')
            for proj in sorted(needed_projects):
                f.write(f'# Project: {proj}\n')
                f.write(f'[ -d "$ECB_ROOT/Source_Code/{proj}" ] && '
                        f'cp -r "$ECB_ROOT/Source_Code/{proj}" "$SUBSET_DIR/EvoCodeBench-2403/Source_Code/"\n')
                f.write(f'[ -d "$ECB_ROOT/Dependency_Data/{proj}" ] && '
                        f'cp -r "$ECB_ROOT/Dependency_Data/{proj}" "$SUBSET_DIR/EvoCodeBench-2403/Dependency_Data/"\n\n')
            f.write('\necho "EvoCodeBench subset copied."\n')
            f.write(f'du -sh "$SUBSET_DIR/EvoCodeBench-2403"\n')
        os.chmod(copy_script, 0o755)
        print(f"  ✓ Generated: {copy_script}")
        print(f"    (Run on HPC to copy EvoCodeBench subset)")

    # --- 7. Save manifest ---
    manifest = {
        "folds": args.folds,
        "num_tasks": len(selected_namespaces),
        "namespaces": sorted(selected_namespaces),
        "needed_projects": sorted(needed_projects),
        "max_data_gb": args.max_data_gb,
    }
    manifest_path = os.path.join(args.output_dir, "subset_manifest.json")
    with open(manifest_path, "w") as f:
        json.dump(manifest, f, indent=2)
    print(f"  ✓ Saved manifest: {manifest_path}")

    # --- Summary ---
    print()
    print("=" * 65)
    print("  SUBSET SUMMARY")
    print("=" * 65)
    print(f"  Folds:      {args.folds}")
    print(f"  Tasks:      {len(selected_namespaces)} / {len(all_namespaces)}")
    print(f"  Projects:   {len(needed_projects)}")
    print(f"  Output dir: {args.output_dir}")
    print()

    # List output files
    total_size = 0
    for dirpath, _, filenames in os.walk(args.output_dir):
        for fn in filenames:
            fp = os.path.join(dirpath, fn)
            sz = os.path.getsize(fp)
            total_size += sz
            rel = os.path.relpath(fp, args.output_dir)
            print(f"    {rel:50s} {sz/1024:.1f} KB")
    print(f"\n  Total subset size: {total_size/1e6:.1f} MB")
    print("=" * 65)


if __name__ == "__main__":
    main()
