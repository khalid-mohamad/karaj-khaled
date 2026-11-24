#!/usr/bin/env python3
"""Static checks for index.html, run locally and in CI before every deploy.

Catches the three classes of bugs that have bitten this project before:
duplicate element ids, dangling getElementById() references, and JS syntax errors.
Requires: pip3 install esprima
"""
import os
import re
import sys

import esprima

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
HTML_PATH = os.path.join(ROOT, "index.html")

failed = False


def fail(msg):
    global failed
    print("FAIL: " + msg)
    failed = True


with open(HTML_PATH, "r", encoding="utf-8") as f:
    html = f.read()

# 1. Duplicate id="..." attributes
ids = re.findall(r'\bid="([^"]+)"', html)
counts = {}
for i in ids:
    counts[i] = counts.get(i, 0) + 1
dupes = [(i, n) for i, n in counts.items() if n > 1]
if dupes:
    fail("duplicate id attributes: " + ", ".join(f"{i} (x{n})" for i, n in dupes))
else:
    print(f"OK: no duplicate ids ({len(ids)} total)")

# 2. Dangling getElementById references (referenced but never defined)
id_set = set(ids)
referenced = re.findall(r"getElementById\(['\"]([^'\"]+)['\"]\)", html)
dangling = sorted(set(referenced) - id_set)
if dangling:
    fail("getElementById() references with no matching id=\"...\": " + ", ".join(dangling))
else:
    print(f"OK: no dangling getElementById references ({len(referenced)} calls checked)")

# 3. JS syntax check on the site's own inline <script> blocks (skip external src= scripts)
script_blocks = re.findall(
    r"<script(?![^>]*\bsrc=)[^>]*>([\s\S]*?)</script>", html
)
if not script_blocks:
    fail("no inline <script> blocks found — extraction regex may be broken")
else:
    combined = "\n;\n".join(script_blocks)
    try:
        esprima.parseScript(combined)
        print(f"OK: inline JS parses cleanly ({len(script_blocks)} block(s), {len(combined)} chars)")
    except Exception as e:
        fail("JS syntax error in inline <script>:\n" + str(e))

if failed:
    print("\nverify.py: one or more checks failed.")
    sys.exit(1)
else:
    print("\nverify.py: all checks passed.")
