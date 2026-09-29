"""Slow trend of the recfem_r wrap margin along a captured hold: per second mean / min / max and the fraction of control steps with the wrap active.
usage: margin_trend.py DIR [bin_s=1]"""
import sys
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/blowup")
import numpy as np, mujoco, replaylib, wrapscan
D = sys.argv[1]; b = float(sys.argv[2]) if len(sys.argv) > 2 else 1.0
m, ring = replaylib.load(D)
replaylib.quiet()
seg = [s for s in wrapscan.segments(m) if s[1] == "recfem_r_tendon"][0]
d = mujoco.MjData(m)
T = np.array(ring["t"]); mg = []
for k in range(len(T)):
    mujoco.mj_setState(m, d, ring["state"][k], int(ring["spec"])); mujoco.mj_fwdPosition(m, d)
    mg.append(wrapscan.probe(m, d, seg, exact_below=0.0)[0])
mg = np.array([np.nan if x is None else x for x in mg])
print(D, "control steps", len(T))
t0 = np.floor(T[0] / b) * b
while t0 < T[-1]:
    sel = (T >= t0) & (T < t0 + b) & np.isfinite(mg)
    if sel.sum():
        x = mg[sel]
        print(f"  t {t0:7.1f}-{t0 + b:7.1f} s: margin mean {x.mean():+.2e} min {x.min():+.2e} max {x.max():+.2e} active {np.mean(x > 0):.2f}")
    t0 += b
