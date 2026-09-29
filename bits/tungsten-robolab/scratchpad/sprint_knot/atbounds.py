"""atbounds: list the tunables of a params file that sit within `edge` of their declared bound.
usage: ROBOLAB_CALIB=v4 ROBOLAB_CONTROLLER=... .venv/bin/python atbounds.py TASK PARAMS [--edge 0.03]"""
import argparse, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, os.path.join(ROOT, "playground"))
from search import describe
from practice import read_params
ap = argparse.ArgumentParser(); ap.add_argument("task"); ap.add_argument("params"); ap.add_argument("--edge", type=float, default=0.03)
a = ap.parse_args()
init = read_params(a.params)
tun = describe(a.task, init)
lo_hit, hi_hit = [], []
for name, d, lo, hi in tun:
    v = init.get(name, d); w = hi - lo
    if v - lo < a.edge * w: lo_hit.append(f"{name}={v:.3g}[{lo:g}]")
    if hi - v < a.edge * w: hi_hit.append(f"{name}={v:.3g}[{hi:g}]")
print("AT LOWER:", " ".join(lo_hit)); print("AT UPPER:", " ".join(hi_hit))
