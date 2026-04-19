#!/usr/bin/env python3
"""Download Tutor-Agents dataset from HuggingFace locally.
Usage: HF_TOKEN=your_token_here python3 download_benchmark_data.py
"""
import os
import sys
import subprocess
from huggingface_hub import snapshot_download

token = os.environ.get("HF_TOKEN", "").strip()
if not token:
    print("❌ Please set HF_TOKEN environment variable:")
    print("   HF_TOKEN=your_token python3 download_benchmark_data.py")
    sys.exit(1)

BASE = "/Users/catherine/PycharmProjects/Coding-Tutor/benchmark_data"
os.makedirs(f"{BASE}/Tutor-Agents", exist_ok=True)

print("⬇️  Downloading Tutor-Agents dataset...")
snapshot_download(
    "nlpscu/Tutor-Agents",
    repo_type="dataset",
    local_dir=f"{BASE}/Tutor-Agents",
    token=token
)
print("✅ Tutor-Agents done!\n")

print("📦 Final size:")
subprocess.run(["du", "-sh", f"{BASE}/Tutor-Agents"])
print(f"\n✅ Upload to Google Drive at: MyDrive/Coding-Tutor-Colab/data/Tutor-Agents/")
