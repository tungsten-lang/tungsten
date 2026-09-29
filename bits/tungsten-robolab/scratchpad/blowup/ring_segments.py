"""Which wrapped tendon segments hover near their wrap tangent in a captured hold? usage: ring_segments.py DIR [t_from=5]
For every ring state (control-step resolution) the margin of every cylinder/sphere wrap segment (wrapscan.probe); per segment: steps within 1e-3 and
1e-4 of the tangent, sign changes, smallest positive margin. Prints the segments with any step within 1e-3."""
import sys
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/blowup")
import numpy as np, mujoco, replaylib, wrapscan

D = sys.argv[1]; t_from = float(sys.argv[2]) if len(sys.argv) > 2 else 5.0
m, ring = replaylib.load(D)
replaylib.quiet()
segs = wrapscan.segments(m)
d = mujoco.MjData(m)
T = np.array(ring["t"])
acc = {i: {"n": 0, "near3": 0, "near4": 0, "flips": 0, "last": None, "minpos": 9.0} for i in range(len(segs))}
for k in np.where(T >= t_from)[0]:
    mujoco.mj_setState(m, d, ring["state"][k], int(ring["spec"])); mujoco.mj_fwdPosition(m, d)
    for i, seg in enumerate(segs):
        r = wrapscan.probe(m, d, seg, exact_below=0.0)
        if r is None or r[0] is None:
            continue
        mg = r[0]; a = acc[i]
        a["n"] += 1; a["near3"] += abs(mg) < 1e-3; a["near4"] += abs(mg) < 1e-4
        if mg > 0: a["minpos"] = min(a["minpos"], mg)
        if a["last"] is not None and a["last"] != (mg > 0): a["flips"] += 1
        a["last"] = mg > 0
print(f"{D}: {int((T >= t_from).sum())} control steps from t = {t_from} s, {len(segs)} wrapped segments")
for i, a in sorted(acc.items(), key=lambda x: -x[1]["near3"]):
    if a["near3"] > 0:
        s = segs[i]
        print(f"  {s[1]:24s} geom {mujoco.mj_id2name(m, mujoco.mjtObj.mjOBJ_GEOM, s[3]):26s} steps |m|<1e-3: {a['near3']:4d}/{a['n']}  <1e-4: {a['near4']:4d}  flips {a['flips']:3d}  min positive {a['minpos']:.2e}")
