"""mkchain5.py BASE OUT [--g1 FILE] [--g2 FILE] [--g3 FILE] [--set k=v,...] [--note ...]
Chain file: every key of BASE, then the plain (gear-1) tunables from --g1, the g2_* twins from --g2 and the g3_* twins from --g3 (v_on keys kept from BASE unless
--set), the practice switches gear0 / fly_entry dropped, `gears 3`."""
import argparse, re
def rd(p):
    d = {}
    for line in open(p):
        if line.startswith("#") or not line.strip():
            continue
        k, v = line.split()[:2]
        d[k] = v
    return d
ap = argparse.ArgumentParser()
ap.add_argument("base"); ap.add_argument("out")
ap.add_argument("--g1"); ap.add_argument("--g2"); ap.add_argument("--g3"); ap.add_argument("--set", default=""); ap.add_argument("--note", default="")
a = ap.parse_args()
d = rd(a.base)
def twin(k):
    return re.match(r"^g[2-9]_", k) is not None
if a.g1:
    for k, v in rd(a.g1).items():
        if not twin(k) and k not in ("gears", "gear0", "fly_entry"):
            d[k] = v
for src, pref in ((a.g2, "g2_"), (a.g3, "g3_")):
    if src:
        for k, v in rd(src).items():
            if k.startswith(pref) and not k.endswith("_v_on"):
                d[k] = v
for k in ("gear0", "fly_entry"):
    d.pop(k, None)
d["gears"] = "3.0"
for kv in a.set.split(","):
    if kv:
        k, v = kv.split("=")
        d[k] = v
with open(a.out, "w") as f:
    f.write(f"# robolab params (sprint 5): base {a.base}, gear 1 from {a.g1}, gear 2 from {a.g2}, gear 3 from {a.g3} {a.note}\n# \n")
    for k in sorted(d):
        f.write(f"{k} {d[k]}\n")
print("wrote", a.out, len(d), "keys")
