"""addgear.py CHAIN OUT --von V [--set k=v,...]: append gear 4 = a copy of gear 3 (explicit twins), switched to at g4_v_on = V (the first flight after the filtered speed reaches V);
`gears 4`. With --set the g4_ values are changed (e.g. g4_k_pp=0.3: a slower, safer 'cool-down' gait taken once the peak speed is banked)."""
import argparse
def rd(p):
    d = {}
    for line in open(p):
        if line.startswith("#") or not line.strip():
            continue
        k, v = line.split()[:2]
        d[k] = v
    return d
ap = argparse.ArgumentParser()
ap.add_argument("chain"); ap.add_argument("out"); ap.add_argument("--von", type=float, required=True); ap.add_argument("--set", default="")
a = ap.parse_args()
d = rd(a.chain)
for k, v in list(d.items()):
    if k.startswith("g3_") and k != "g3_v_on":
        d["g4_" + k[3:]] = v
d["g4_v_on"] = repr(a.von)
d["gears"] = "4.0"
for kv in a.set.split(","):
    if kv:
        k, v = kv.split("="); d[k] = v
with open(a.out, "w") as f:
    f.write(f"# robolab params: {a.chain} + gear 4 (a copy of gear 3, g4_v_on {a.von}) {a.set}\n# \n")
    for k in sorted(d):
        f.write(f"{k} {d[k]}\n")
print("wrote", a.out, len(d), "keys")
