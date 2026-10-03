"""gearcopy: a practice file whose gear 5 is a COPY of gear K's effective stride (the nearest g<j>_ twin at or below K, else the plain gear-1 value).

  .venv/bin/python scratchpad/anat5/gearcopy.py BASE OUT --from 3 [--to 5] [--fly]
Writes BASE's keys with g<to>_<name> := the value gear <from> uses for <name> (all tunables that have a twin anywhere in BASE or a plain value), `gears`, and with --fly gear0 <to> + fly_entry 2 and no g<to>_v_on.
"""
import argparse
ap = argparse.ArgumentParser(); ap.add_argument("base"); ap.add_argument("out"); ap.add_argument("--from", dest="frm", type=int, required=True)
ap.add_argument("--to", type=int, default=5); ap.add_argument("--fly", action="store_true"); a = ap.parse_args()
d, order = {}, []
for l in open(a.base):
    if l.startswith("#") or not l.strip(): continue
    k, v = l.split()[:2]
    if k not in d: order.append(k)
    d[k] = v
def gear_key(k):
    return len(k) > 3 and k[0] == "g" and k[1].isdigit() and k[2] == "_"
plain = {k for k in d if not gear_key(k) and k not in ("gears", "gear0", "fly_entry")}
names = set(plain) | {k[3:] for k in d if gear_key(k)}
skip = {"v_on", "gears", "gear0", "fly_entry", "knots", "ri"}
for n in sorted(names):
    if n in skip or n.endswith("_v_on"): continue
    val = None
    for j in range(a.frm, 1, -1):
        if f"g{j}_{n}" in d: val = d[f"g{j}_{n}"]; break
    if val is None and n in d: val = d[n]
    if val is not None: d[f"g{a.to}_{n}"] = val
d["gears"] = f"{float(max(a.to, int(float(d.get('gears', 1)))))}"
for k in ("gear0", "fly_entry", f"g{a.to}_v_on"): d.pop(k, None)
if a.fly: d["gear0"] = f"{float(a.to)}"; d["fly_entry"] = "2.0"
with open(a.out, "w") as f:
    f.write(f"# robolab params: {a.base} with gear {a.to} := gear {a.frm}'s effective stride (anat5 gearcopy)" + (" (flying practice)" if a.fly else "") + "\n# \n")
    for k in sorted(d): f.write(f"{k} {d[k]}\n")
print("wrote", a.out, len(d), "keys")
