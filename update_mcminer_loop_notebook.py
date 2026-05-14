#!/usr/bin/env python3
"""Update colab_mcminer_loop.ipynb to embed run_mcminer_loop.py as base64."""
import json, base64

NB = "/Users/catherine/PycharmProjects/Coding-Tutor/colab_mcminer_loop.ipynb"
SCRIPT = "/Users/catherine/PycharmProjects/Coding-Tutor/Coding-Tutor/traver/run_mcminer_loop.py"

with open(NB) as f:
    nb = json.load(f)

with open(SCRIPT, 'rb') as f:
    script_b64 = base64.b64encode(f.read()).decode()

# Find cell 14 (the existing patch cell that writes VLLMChat + model_utils)
# We'll add a NEW cell right after it (insert at position 15) that writes run_mcminer_loop.py

inject_cell = {
    "cell_type": "code",
    "execution_count": None,
    "metadata": {},
    "outputs": [],
    "source": [
        "# ── Write run_mcminer_loop.py to the cloned repo ──\n",
        "import base64, pathlib\n",
        "\n",
        f"_mcloop_b64 = \"{script_b64}\"\n",
        "\n",
        "mcloop_path = f\"{WORK_DIR}/traver/run_mcminer_loop.py\"\n",
        "pathlib.Path(mcloop_path).write_text(\n",
        "    base64.b64decode(_mcloop_b64).decode()\n",
        ")\n",
        "print(f\"✅ Wrote run_mcminer_loop.py ({len(_mcloop_b64)} b64 chars)\")\n",
        "print(f\"   → {mcloop_path}\")\n"
    ]
}

# Insert after cell 14 (the existing patch cell)
# Find the right position - it should be after the VLLMChat/model_utils patch
nb['cells'].insert(15, inject_cell)

with open(NB, "w") as f:
    json.dump(nb, f, indent=1)

print(f"✅ Inserted run_mcminer_loop.py cell (b64: {len(script_b64)} chars)")
print(f"   Notebook now has {len(nb['cells'])} cells")
