"""vonshift.py BASE OUT DELTA [--only 2,3,4,5]: copy BASE with every g<k>_v_on shifted by DELTA m/s."""
import sys
base, out, delta = sys.argv[1], sys.argv[2], float(sys.argv[3])
lines = open(base).read().splitlines()
res = []
for l in lines:
    if l.strip() and not l.startswith("#"):
        k, v = l.split()[:2]
        if k.endswith("_v_on") and k[0] == "g":
            l = f"{k} {float(v) + delta:.4f}"
    res.append(l)
open(out, "w").write("\n".join(res) + "\n")
