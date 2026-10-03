"""interp_gear.py CHAIN OUT --frac F [--von V] [--von-next W]: insert an INTERMEDIATE gear between gear 1 and gear 2 of a 3-gear chain file (explicit twins):
new gear 2 = (1-F) x gear 1 + F x gear 2 for every tunable that both name, new gear 3 = the old gear 2, new gear 4 = the old gear 3; gears 4,
g2_v_on = V (default 7.0), g3_v_on = W (default the old g2_v_on), g4_v_on = the old g3_v_on. Practice switches are kept as they are in CHAIN."""
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
ap.add_argument("chain"); ap.add_argument("out"); ap.add_argument("--frac", type=float, default=0.5)
ap.add_argument("--von", type=float, default=7.0); ap.add_argument("--von-next", type=float)
a = ap.parse_args()
d, order = rd(a.chain)
old_g2 = {k[3:]: v for k, v in d.items() if k.startswith("g2_")}
old_g3 = {k[3:]: v for k, v in d.items() if k.startswith("g3_")}
out = {k: v for k, v in d.items() if not re.match(r"^g[2-9]_", k)}
von2_old = float(old_g2.get("v_on", "7.6")); von3_old = float(old_g3.get("v_on", "9.4"))
n_i = 0
for name, v2 in old_g2.items():
    if name == "v_on":
        continue
    v1 = d.get(name)
    try:
        mid = (1 - a.frac) * float(v1) + a.frac * float(v2) if v1 is not None else float(v2)
        if v1 is not None: n_i += 1
    except ValueError:
        mid = v2
    out["g2_" + name] = repr(mid)
    out["g3_" + name] = v2
for name, v3 in old_g3.items():
    if name == "v_on":
        continue
    out["g4_" + name] = v3
out["g2_v_on"] = repr(a.von); out["g3_v_on"] = repr(a.von_next if a.von_next is not None else von2_old); out["g4_v_on"] = repr(von3_old)
out["gears"] = "4.0"
with open(a.out, "w") as f:
    f.write(f"# robolab params: {a.chain} with an intermediate gear (frac {a.frac}) inserted between gears 1 and 2 (interp_gear.py)\n# \n")
    for k in sorted(out):
        f.write(f"{k} {out[k]}\n")
print("wrote", a.out, len(out), "keys,", n_i, "interpolated values")
