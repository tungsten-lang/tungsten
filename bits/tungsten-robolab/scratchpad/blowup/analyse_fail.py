"""Which tendon is NaN at a captured failing substep, and where does its wrap sit? usage: analyse_fail.py DIR [DIR ...]"""
import sys
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/blowup")
import numpy as np, mujoco, replaylib, wrapscan

for D in sys.argv[1:]:
    m, ring = replaylib.load(D)
    replaylib.quiet()
    f = np.load(D + "/fail.npz")
    d = mujoco.MjData(m)
    mujoco.mj_setState(m, d, ring["state"][-1], int(ring["spec"]))
    d.qpos[:] = f["qpos"]
    d.qvel[:] = f["qvel"]
    d.act[:] = f["act"]
    mujoco.mj_fwdPosition(m, d)
    bad = np.where(~np.isfinite(d.ten_length))[0]
    segs = wrapscan.segments(m)
    T = mujoco.mjtObj.mjOBJ_TENDON
    print(f"{D}: time {float(f['time'][0]):.4f}; NaN tendons {[(int(t), mujoco.mj_id2name(m, T, int(t))) for t in bad]}; actuator_force NaN {int((~np.isfinite(f['actuator_force'])).sum())}")
    for t in bad:
        for seg in segs:
            if seg[0] == t:
                r = wrapscan.probe(m, d, seg, exact_below=1.0)
                print(f"   segment {seg[1]} geom {seg[3]} r {seg[7]}: margin {r[0]:+.4e} exit {r[1]} exact 1-dot {r[2]}")
