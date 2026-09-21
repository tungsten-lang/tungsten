#!/usr/bin/env python3
"""One-shot source fix for core/numeric/big_int.w (already applied; kept for
the record and so the transformation can be replayed onto a newer big_int.w).

Every `__bigint_*_raw` wrapper that calls a kernel defined only under
`on macos && arm64` is moved under the same guard, so the file lowers for any
other target. All their call sites are already guarded (guard_callsites.py)."""
import re, subprocess, sys

path = "core/numeric/big_int.w"
GUARD = "on macos && arm64"

def audit():
    out = subprocess.run([sys.executable, "wasm/scripts/guard_audit.py", path],
                         capture_output=True, text=True).stdout.strip()
    return [tuple(map(int, l.split(":")[0].split("-"))) for l in out.split("\n") if l]

while True:
    ranges = audit()          # 1-based start, end = index after the body
    if not ranges:
        break
    lines = open(path).read().split("\n")
    # merge runs separated only by blank/comment lines
    runs = []
    for s, e in ranges:
        s -= 1
        if runs and all(lines[k].strip() == "" or lines[k].startswith("#") for k in range(runs[-1][1], s)):
            runs[-1][1] = e
        else:
            runs.append([s, e])
    for s, e in reversed(runs):
        while e > s and lines[e - 1].strip() == "":
            e -= 1
        body = [("  " + l) if l.strip() else l for l in lines[s:e]]
        lines[s:e] = [GUARD] + body
    open(path, "w").write("\n".join(lines))
    print(f"guarded {len(ranges)} fns in {len(runs)} blocks")
