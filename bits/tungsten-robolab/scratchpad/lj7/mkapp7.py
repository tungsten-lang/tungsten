"""mkapp7 (L7): an approach params file = a base runner file (default scratchpad/lj6/params/runner_H011_SB2.txt) with k=v overrides (later values replace earlier ones; j_ik / j_il written 0).
usage: mkapp7.py <out> k=v [k=v ...]   env LJ7_BASE overrides the base file"""
import os, sys
out = sys.argv[1]
over = dict(kv.split("=") for kv in sys.argv[2:])
base = os.environ.get("LJ7_BASE", "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj6/params/runner_H011_SB2.txt")
lines = []
for line in open(base):
    t = line.split()
    if line.startswith("#") or len(t) < 2 or t[0] in ("j_ik", "j_il") or t[0] in over:
        continue
    lines.append(line.rstrip("\n"))
with open(out, "w") as f:
    f.write("# approach: %s + overrides %s (L7)\n" % (os.path.basename(base), over))
    f.write("\n".join(lines) + "\n")
    f.write("j_ik 0\nj_il 0\n")
    for k, v in over.items():
        f.write(f"{k} {v}\n")
print("wrote", out, len(lines), "base lines +", len(over), "overrides")
