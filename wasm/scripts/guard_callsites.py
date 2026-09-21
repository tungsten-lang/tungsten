#!/usr/bin/env python3
"""For every name printed by guard_audit.py, report call sites that are NOT
inside any `on …` block (those would break once the wrapper is guarded)."""
import re, subprocess, sys

path = "core/numeric/big_int.w"
lines = open(path).read().split("\n")
audit = subprocess.run([sys.executable, "wasm/scripts/guard_audit.py", path],
                       capture_output=True, text=True).stdout.strip().split("\n")
names = [l.split(": ")[1].split(" ->")[0] for l in audit]
defs = {l.split(": ")[1].split(" ->")[0]: tuple(map(int, l.split(":")[0].split("-"))) for l in audit}

# guard regions at any indentation
regions = []
for i, line in enumerate(lines):
    m = re.match(r"^(\s*)on\s+\S", line)
    if m:
        ind = len(m.group(1))
        j = i + 1
        while j < len(lines) and (lines[j].strip() == "" or len(lines[j]) - len(lines[j].lstrip()) > ind):
            j += 1
        regions.append((i, j, line.strip()))

def guarded(idx):
    return any(a <= idx < b for a, b, _ in regions)

unguarded_sites = 0
for name in names:
    pat = re.compile(r"\b" + re.escape(name) + r"\b")
    for i, line in enumerate(lines):
        if pat.search(line) and not (defs[name][0] - 1 == i):
            inside_def = any(d[0] - 1 <= i < d[1] for d in defs.values())
            if not guarded(i) and not line.lstrip().startswith("#"):
                unguarded_sites += 1
                print(f"{i+1}: {'(in audited wrapper) ' if inside_def else ''}{line.strip()[:120]}")
print(f"# {unguarded_sites} unguarded call sites", file=sys.stderr)
