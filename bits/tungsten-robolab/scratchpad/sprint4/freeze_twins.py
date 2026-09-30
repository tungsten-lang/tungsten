"""freeze_twins.py IN OUT [--set k=v,...]: write OUT = IN plus an explicit value for every gear twin g<K>_<X> that IN does not name,
equal to what the controller uses for it now (the value the twin falls back to: the previous gear's, else gear 1's), so that a later
search of gear-1 names (or of one gear's twins) cannot change another gear through the fallback. Optional --set overrides (after freezing).
  . scratchpad/sprint4/env.sh; ROBOLAB_CONTROLLER=bin/challengers/run_gearx-a .venv/bin/python scratchpad/sprint4/freeze_twins.py IN OUT [--set k=v,...]"""
import argparse, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
os.environ.setdefault("ROBOLAB_CONTROLLER", os.path.join(ROOT, "bin", "challengers", "run_gearx-a"))
from search import describe
from practice import read_params

ap = argparse.ArgumentParser()
ap.add_argument("inp"); ap.add_argument("out"); ap.add_argument("--set", default=""); ap.add_argument("--note", default="")
a = ap.parse_args()
init = read_params(a.inp)
tun = describe("sprint_touch_v4x", init)
d, order = {}, []
for line in open(a.inp):
    if line.startswith("#") or not line.strip():
        continue
    k, v = line.split()[:2]
    if k not in d:
        order.append(k)
    d[k] = v
added = 0
for name, default, lo, hi in tun:
    if len(name) > 2 and name[0] == "g" and name[1].isdigit() and name[2] == "_" and name not in d:
        d[name] = repr(float(default)); order.append(name); added += 1
for kv in a.set.split(","):
    if kv:
        k, v = kv.split("=")
        if k not in d:
            order.append(k)
        d[k] = v
with open(a.out, "w") as f:
    f.write(f"# robolab params: {a.inp} with every gear twin frozen explicitly (freeze_twins.py, {added} twins added) {a.note}\n# \n")
    for k in sorted(d):
        f.write(f"{k} {d[k]}\n")
print("wrote", a.out, len(d), "keys,", added, "twins frozen")
