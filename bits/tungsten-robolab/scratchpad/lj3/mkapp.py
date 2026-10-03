"""Approach params for the LABELLED BEYOND-HUMAN body: chain D (scratchpad/lj3/B0.txt minus its j_ik / j_il lines) + jump planner settings.
usage: mkapp.py <out> k=v [k=v ...]   (later values replace earlier ones; j_ik / j_il are written 0)"""
import sys

out = sys.argv[1]
over = dict(kv.split("=") for kv in sys.argv[2:])
lines = []
for line in open("/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj3/B0.txt"):
    t = line.split()
    if line.startswith("#") or len(t) < 2 or t[0] in ("j_ik", "j_il") or t[0] in over:
        continue
    lines.append(line.rstrip("\n"))
with open(out, "w") as f:
    f.write("# approach: chain D + planner %s\n" % over)
    f.write("\n".join(lines) + "\n")
    f.write("j_ik 0\nj_il 0\n")
    for k, v in over.items():
        f.write(f"{k} {v}\n")
print("wrote", out, len(lines), "runner lines +", len(over), "overrides")
