#!/usr/bin/env python3
"""Combine the HTML shell with demo_data.json into a single self-contained artifact."""
import json
from pathlib import Path

OUT_DIR = Path("/sessions/dazzling-zealous-davinci/mnt/outputs")
DATA = OUT_DIR / "demo_data.json"
SHELL = OUT_DIR / "artifact_shell.html"
FINAL = OUT_DIR / "tutor_demo.html"

data_str = DATA.read_text()
shell = SHELL.read_text()
final = shell.replace("__DEMO_DATA_PLACEHOLDER__", data_str)
FINAL.write_text(final)
print(f"Wrote {FINAL} -- {len(final)} bytes")
