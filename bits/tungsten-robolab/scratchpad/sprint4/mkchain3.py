"""mkchain3.py BASE GEAR3SRC OUT [--von2 X] [--von3 Y] [--set k=v,...]
Chain file: gears 1-2 (and every key that is not a gear-3 twin) from BASE, the gear-3 twins g3_* from GEAR3SRC, gears 3, g2_v_on / g3_v_on as given.
BASE must be a gears-2 (or 3) chain file; GEAR3SRC any file that carries g3_* keys (a gear-3 practice file, ge_snap2.txt ...). Practice switches (gear0, fly_entry) are dropped."""
import argparse, re
def rd(p):
    d, order = {}, []
    for line in open(p):
        if line.startswith("#") or not line.strip():
            continue
        k, v = line.split()[:2]
        if k not in d:
            order.append(k)
        d[k] = v
    return d, order
ap = argparse.ArgumentParser()
ap.add_argument("base"); ap.add_argument("g3src"); ap.add_argument("out")
ap.add_argument("--von2", type=float); ap.add_argument("--von3", type=float); ap.add_argument("--set", default=""); ap.add_argument("--note", default="")
a = ap.parse_args()
d, order = rd(a.base)
s, _ = rd(a.g3src)
for k, v in s.items():
    if re.match(r"^g3_", k) and k != "g3_v_on":
        d[k] = v
for k in ("gear0", "fly_entry"):
    d.pop(k, None)
d["gears"] = "3.0"
if a.von2 is not None: d["g2_v_on"] = repr(a.von2)
if a.von3 is not None: d["g3_v_on"] = repr(a.von3)
for kv in a.set.split(","):
    if kv:
        k, v = kv.split("="); d[k] = v
with open(a.out, "w") as f:
    f.write(f"# robolab params: chain gears 1-2 from {a.base}, gear 3 from {a.g3src} {a.note}\n# \n")
    for k in sorted(d):
        f.write(f"{k} {d[k]}\n")
print("wrote", a.out, len(d), "keys")
