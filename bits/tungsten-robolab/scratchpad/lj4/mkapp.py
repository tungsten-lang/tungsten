"""Approach params for the LABELLED BEYOND-HUMAN body: chain F1 (params/run_geary_v4_beyond_s5b.txt) + jump planner settings, j_ik / j_il written 0 (agent L4).
usage: mkapp.py <out> k=v [k=v ...]   (later values replace earlier ones; the base file's j_ik / j_il lines are dropped and written 0)
env: LJ4_BASE overrides the base runner file."""
import os
import sys

out = sys.argv[1]
over = dict(kv.split("=") for kv in sys.argv[2:])
base = os.environ.get("LJ4_BASE", "/Users/erik/tungsten/bits/tungsten-robolab/params/run_geary_v4_beyond_s5b.txt")
lines = []
for line in open(base):
    t = line.split()
    if line.startswith("#") or len(t) < 2 or t[0] in ("j_ik", "j_il") or t[0] in over:
        continue
    lines.append(line.rstrip("\n"))
with open(out, "w") as f:
    f.write("# approach: %s + planner %s\n" % (os.path.basename(base), over))
    f.write("\n".join(lines) + "\n")
    f.write("j_ik 0\nj_il 0\n")
    for k, v in over.items():
        f.write(f"{k} {v}\n")
print("wrote", out, len(lines), "runner lines +", len(over), "overrides")
