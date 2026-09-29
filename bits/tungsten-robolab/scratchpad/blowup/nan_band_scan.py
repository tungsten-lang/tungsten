"""Scan one swing-hip joint through the failing state and report where MuJoCo's own mj_tendon returns a NaN tendon length.
usage: nan_band_scan.py DIR joint span step   (e.g. out/blowup/r91049_a hip_flexion_r 2e-6 1e-10)
For every scan point: NaN flag of ten_length[239] from MuJoCo, and the exact (60-digit Decimal) 1-dot of the two tangent-point directions
(wrapdiag.decimal_circle). Prints the NaN fraction per bin of exact 1-dot."""
import sys
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/blowup")
import numpy as np, mujoco, replaylib, wrapdiag

D, joint, span, step = sys.argv[1], sys.argv[2], float(sys.argv[3]), float(sys.argv[4])
m, ring = replaylib.load(D)
replaylib.quiet()
f = np.load(D + "/fail.npz")
d = mujoco.MjData(m)
mujoco.mj_setState(m, d, ring["state"][-1], int(ring["spec"]))
d.qpos[:] = f["qpos"]
q0 = d.qpos.copy()
adr = m.jnt_qposadr[m.joint(joint).id]
g = 67
r = float(m.geom_size[g][0])


def exact_omd(dd):
    xm = dd.geom_xmat[g].reshape(3, 3)
    loc = lambda x: xm.T @ (x - dd.geom_xpos[g])
    p0, p1, s3 = loc(dd.site_xpos[654]), loc(dd.site_xpos[847]), loc(dd.site_xpos[746])
    end = [p0[0], p0[1], p1[0], p1[1]]
    sd = np.array([s3[0], s3[1]]); sd = list(sd / np.linalg.norm(sd) * r)
    w, info = wrapdiag.wrap_circle(end, sd, r)
    if info.get("exit") != "wrap":
        return None, (info["sqrad"] - info["tmp2"]) / info["sqrad"]
    dec = wrapdiag.decimal_circle(end, sd, r)
    return float(dec[f"one_minus_dot{info['chosen']}"]), (info["sqrad"] - info["tmp2"]) / info["sqrad"]


pts = []
for dl in np.arange(-span, span + step / 2, step):
    d.qpos[:] = q0
    d.qpos[adr] = q0[adr] + dl
    mujoco.mj_fwdPosition(m, d)
    nan = bool(np.isnan(d.ten_length[239]))
    omd, mg = exact_omd(d)
    pts.append((dl, nan, omd, mg))
n = len(pts)
print(f"{n} scan points over +-{span:g} rad of {joint}; NaN {sum(p[1] for p in pts)}")
edges = [0, 1e-17, 3e-17, 6e-17, 8e-17, 1e-16, 1.2e-16, 1.5e-16, 2e-16, 2.5e-16, 3e-16, 5e-16, 1e-15, 1e-14, 1e-9, 1.0]
print("exact 1-dot bin              points  NaN  NaN fraction")
for lo, hi in zip(edges[:-1], edges[1:]):
    sel = [p for p in pts if p[2] is not None and lo <= p[2] < hi]
    if sel:
        k = sum(p[1] for p in sel)
        print(f"  [{lo:8.1e}, {hi:8.1e})   {len(sel):6d} {k:5d}   {k / len(sel):.3f}")
nowrap = [p for p in pts if p[2] is None]
print(f"  no wrap (margin < 0)        {len(nowrap):6d} {sum(p[1] for p in nowrap):5d}")
nan_margins = [p[3] for p in pts if p[1]]
if nan_margins:
    print(f"NaN margins: min {min(nan_margins):+.3e} max {max(nan_margins):+.3e}")
