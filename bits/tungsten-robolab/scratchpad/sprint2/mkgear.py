"""mkgear: write a params file for gear K on top of a base params file.

  .venv/bin/python scratchpad/sprint2/mkgear.py BASE OUT --gears 5 [--fly] [--von 7.9] [--set g5_k_reach=0.5,...] \
        [--from FILE [--prefix g5_] [--only a,b] [--exclude a,b]]

--fly   practice file: gear0 K + fly_entry 2 (a flying start begins in gear K), no g<K>_v_on
--von   standing-start file: g<K>_v_on = V (and no gear0 / fly_entry)
--from  copy FILE's plain tunables as g<K>_ twins (an entire stride family: e.g. the extended-mode gait), optionally filtered
--set    explicit values (names written as given)
Keys the run does not read (v_on/gear0/fly_entry handled above) are replaced, not duplicated.
"""
import argparse, sys

def rd(path):
    d, order = {}, []
    for line in open(path):
        if line.startswith("#") or not line.strip():
            continue
        k, v = line.split()[:2]
        if k not in d:
            order.append(k)
        d[k] = v
    return d, order

ap = argparse.ArgumentParser()
ap.add_argument("base"); ap.add_argument("out")
ap.add_argument("--gears", type=int, required=True)
ap.add_argument("--fly", action="store_true"); ap.add_argument("--von", type=float)
ap.add_argument("--set", default=""); ap.add_argument("--from", dest="frm"); ap.add_argument("--only", default=""); ap.add_argument("--exclude", default="")
ap.add_argument("--note", default="")
a = ap.parse_args()
d, order = rd(a.base)
K = a.gears
d["gears"] = str(float(K)); 
if "gears" not in order: order.append("gears")
for k in ("gear0", "fly_entry", f"g{K}_v_on"):
    d.pop(k, None)
if a.fly:
    d["gear0"] = f"{float(K)}"; d["fly_entry"] = "2.0"
if a.von is not None:
    d[f"g{K}_v_on"] = f"{a.von}"
if a.frm:
    src, _ = rd(a.frm)
    only = set(x for x in a.only.split(",") if x); excl = set(x for x in a.exclude.split(",") if x)
    for k, v in src.items():
        if k.startswith("g") and len(k) > 2 and k[1].isdigit() and k[2] == "_":
            continue
        if k in ("gears", "gear0", "fly_entry", "knots", "ri") or k.endswith("_v_on"):
            continue
        if only and k not in only: continue
        if k in excl: continue
        d[f"g{K}_{k}"] = v
for kv in a.set.split(","):
    if kv:
        k, v = kv.split("="); d[k] = v
with open(a.out, "w") as f:
    f.write(f"# robolab params: gear {K} file from {a.base}" + (f" + {a.frm}" if a.frm else "") + (" (flying practice)" if a.fly else " (standing start)") + f" {a.note}\n# \n")
    for k in sorted(d):
        f.write(f"{k} {d[k]}\n")
print("wrote", a.out, len(d), "keys")
