"""Capture lists for the robust stage (agent L4): the captured states <prefix>_s<seed> of seeds a-b sorted by gap (line - penultimate toe), split gap-stratified:
every <k>-th state (by gap order, offset <o>) goes to the held-out list, the rest to the training list.
usage: mklist.py <prefix> <first_seed> <last_seed> <out_prefix> [k=4] [o=1]   writes <out_prefix>_all.txt, _train.txt, _held.txt (comma lists) and prints a summary"""
import os, sys, json
os.environ.setdefault("MUJOCO_GL", "cgl")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
import numpy as np
import long_jump_limits as L
import long_jump_mine as M

prefix, a, b, outp = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
k = int(sys.argv[5]) if len(sys.argv) > 5 else 4
o = int(sys.argv[6]) if len(sys.argv) > 6 else 1
body = None
rows = []
for sd in range(a, b + 1):
    name = f"{prefix}_s{sd}"
    if not os.path.exists(os.path.join(L.OUT, f"{name}_capture.npz")):
        continue
    cap = L.load_capture(name)
    if body is None:
        body = L.Body(cap["task"], cap["board_x"], json.loads(cap["env"]))
    f = M.features(body, cap)
    rows.append((f["gap"], name, cap["plant"]))
rows.sort()
allv = [r[1] for r in rows]
held = [r[1] for i, r in enumerate(rows) if i % k == o % k]
train = [r[1] for i, r in enumerate(rows) if i % k != o % k]
open(outp + "_all.txt", "w").write(",".join(allv))
open(outp + "_train.txt", "w").write(",".join(train))
open(outp + "_held.txt", "w").write(",".join(held))
g = np.array([r[0] for r in rows])
print("%s: %d states (gap %.2f..%.2f mean %.3f sd %.3f, plant l/r %d/%d); train %d held %d" % (
    prefix, len(rows), g.min(), g.max(), g.mean(), g.std(), sum(1 for r in rows if r[2] == "l"), sum(1 for r in rows if r[2] == "r"), len(train), len(held)))
