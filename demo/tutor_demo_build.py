#!/usr/bin/env python3
"""Combine the HTML shell with demo_data.json into a single self-contained artifact.

NOTE (2026-06): This script is DEPRECATED for normal use.
The updated tutor_demo.html now fetches tutor_demo_data.json dynamically at runtime
(from Google Drive or a local file), so there is no need to bake the data inline.

This script is kept for reference only. If you need a fully self-contained HTML
(e.g. for email attachment), you can still use a modified version of this approach.
"""
import json
from pathlib import Path

# Original paths from the cloud session (no longer used):
# OUT_DIR = Path("/sessions/dazzling-zealous-davinci/mnt/outputs")

# Local paths:
DEMO_DIR = Path(__file__).parent
DATA = DEMO_DIR / "tutor_demo_data.json"
SHELL = DEMO_DIR / "tutor_demo.html"
FINAL = DEMO_DIR / "tutor_demo_standalone.html"

if __name__ == "__main__":
    data_str = DATA.read_text()
    shell = SHELL.read_text()

    # Inject DATA as inline JSON for a standalone version
    inject = f"const DATA = {data_str};"
    # Replace the fetch-based loading with inline data
    # (This is a rough approach — for a proper standalone build,
    #  you'd need to replace the loadData() function entirely.)
    print(f"DEPRECATED: Use tutor_demo.html + tutor_demo_data.json directly.")
    print(f"Data file: {DATA} -- {len(data_str)} bytes")
