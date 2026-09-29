"""Graze margin of a cylinder-wrapped tendon along a captured run: for every ring state, tmp2 vs r^2 of the wrap (see wrapdiag.py).
usage: margin_series.py DIR [tendon] [stride]   -> prints t, margin=(r^2-|tmp|^2)/r^2 (positive = wrapping active), 1-dot (arc), NaN flag from MuJoCo"""
import sys, math
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/blowup")
import numpy as np, mujoco, replaylib, wrapdiag

D = sys.argv[1]; ten = int(sys.argv[2]) if len(sys.argv) > 2 else 239; stride = int(sys.argv[3]) if len(sys.argv) > 3 else 1
m, ring = replaylib.load(D)
replaylib.quiet()
adr = m.tendon_adr[ten]; n = m.tendon_num[ten]
segs = []
for j in range(n - 1):
    tp = int(m.wrap_type[adr + j + 1])
    if tp in (int(mujoco.mjtWrap.mjWRAP_CYLINDER), int(mujoco.mjtWrap.mjWRAP_SPHERE)):
        segs.append((int(m.wrap_objid[adr + j]), int(m.wrap_objid[adr + j + 1]), int(m.wrap_objid[adr + j + 2]), int(round(m.wrap_prm[adr + j + 1])), tp))
print("wrap segments (site0, geom, site1, side, type):", segs)
d = mujoco.MjData(m)
rows = []
for k in range(0, len(ring["t"]), stride):
    mujoco.mj_setState(m, d, ring["state"][k], int(ring["spec"]))
    mujoco.mj_fwdPosition(m, d)
    for (s0, g, s1, side, tp) in segs:
        xm = d.geom_xmat[g].reshape(3, 3)
        loc = lambda x: xm.T @ (x - d.geom_xpos[g])
        p0, p1 = loc(d.site_xpos[s0]), loc(d.site_xpos[s1])
        r = float(m.geom_size[g][0])
        if tp != int(mujoco.mjtWrap.mjWRAP_CYLINDER):
            continue
        end = [p0[0], p0[1], p1[0], p1[1]]
        sd = None
        if side >= 0:
            s3 = loc(d.site_xpos[side]); sd = np.array([s3[0], s3[1]]); sd = list(sd / np.linalg.norm(sd) * r)
        w, info = wrapdiag.wrap_circle(end, sd, r)
        tmp2 = info.get("tmp2"); sqrad = info["sqrad"]
        margin = None if tmp2 is None else (sqrad - tmp2) / sqrad
        rows.append((ring["t"][k], g, margin, info.get("exit"), (1.0 - info["dot"]) if "dot" in info else None, float(d.ten_length[ten])))
for row in rows:
    t, g, margin, ex, omd, L = row
    print(f"t {t:8.3f} geom {g} margin {margin if margin is None else format(margin, '+.4e')} exit {ex} 1-dot {omd if omd is None else format(omd, '.3e')} L {L:.9f}")
