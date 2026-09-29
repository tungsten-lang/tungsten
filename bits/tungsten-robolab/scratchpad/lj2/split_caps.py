"""List the captures of a prefix by plant side: writes scratchpad/lj2/<prefix>_l.txt (plant l) and <prefix>_r.txt; prints counts. usage: split_caps.py <prefix>"""
import os, sys, json
import numpy as np
d = "/Users/erik/tungsten/bits/tungsten-robolab/out/long_jump_limits"
X = sys.argv[1]
names = sorted(f[:-len("_capture.npz")] for f in os.listdir(d) if f.startswith(X + "_s") and f.endswith("_capture.npz"))
nom = X + "_nom"
if os.path.exists(f"{d}/{nom}_capture.npz"):
    names = [nom] + names
def plant(nm):
    z = np.load(f"{d}/{nm}_capture.npz"); first = json.loads(str(z["labels"]))[0].split(":")[-1]
    return "r" if first.startswith("l_") else "l"
L = [n for n in names if plant(n) == "l"]; R = [n for n in names if plant(n) == "r"]
open(f"/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj2/{X}_l.txt", "w").write(",".join(L) + "\n")
open(f"/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj2/{X}_r.txt", "w").write(",".join(R) + "\n")
print(X, len(names), "captures: plant l", len(L), "r", len(R))
