#!/usr/bin/env python3
"""Audit core/numeric/big_int.w for unguarded top-level fns that call fns which
only exist under an `on <target>` guard (so the file cannot be lowered for any
other target). Prints the transitive set, in source order."""
import re, sys

path = sys.argv[1] if len(sys.argv) > 1 else "core/numeric/big_int.w"
lines = open(path).read().split("\n")

# Top-level regions: [start, end) with guard (or None) for col-0 `on` blocks.
fns = {}        # name -> dict(start, end, guarded, body)
order = []
i = 0
n = len(lines)
guard_end = -1
guard = None
while i < n:
    line = lines[i]
    if re.match(r"^on\s+\S", line):
        guard = line.strip()
        j = i + 1
        while j < n and (lines[j].strip() == "" or lines[j].startswith(" ") or lines[j].startswith("#")):
            j += 1
        guard_end = j
    m = re.match(r"^(\s*)fn\s+([A-Za-z_0-9?!]+)", line)
    if m and len(m.group(1)) in (0, 2):
        indent = len(m.group(1))
        j = i + 1
        while j < n and (lines[j].strip() == "" or len(lines[j]) - len(lines[j].lstrip()) > indent):
            j += 1
        guarded = i < guard_end
        if indent == 2 and not guarded:
            i += 1
            continue  # fn inside a class body; not a top-level fn
        fns[m.group(2)] = dict(start=i, end=j, guard=guard if guarded else None,
                               body="\n".join(lines[i + 1:j]))
        order.append(m.group(2))
    i += 1

guarded = {k for k, v in fns.items() if v["guard"]}
bad = {}
changed = True
while changed:
    changed = False
    for name in order:
        f = fns[name]
        if f["guard"] or name in bad:
            continue
        calls = set(re.findall(r"\b(__[A-Za-z_0-9]+)\s*\(", f["body"]))
        dep = [c for c in calls if c in guarded or c in bad]
        if dep:
            bad[name] = dep
            changed = True

for name in order:
    if name in bad:
        f = fns[name]
        print(f"{f['start']+1}-{f['end']}: {name} -> {', '.join(sorted(bad[name]))}")
print(f"# {len(bad)} unguarded fns depend on guarded kernels; {len(guarded)} guarded fns", file=sys.stderr)
