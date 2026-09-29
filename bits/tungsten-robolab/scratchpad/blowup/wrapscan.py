"""Graze margins of EVERY cylinder/sphere-wrapped tendon segment of the model (MuJoCo 3.6.0 mju_wrap frames, wrapdiag.wrap_circle).

    segs = wrapscan.segments(m)                      # [(tendon, name, site0, geom, site1, side, type, radius)]
    rows = wrapscan.probe_all(m, d, segs)            # per segment: (margin, wrapping, exact_or_None) evaluated from d's LAST forward pass

margin = (r^2 - |tmp|^2) / r^2 in the wrap's 2D frame: > 0 the tendon line cuts the circle (the wrap is active), < 0 it misses it; the NaN of
length_circle can only occur for 0 < margin < ~6e-8 (arc angle < 1.5e-8 rad).
"""
import math
import numpy as np
import mujoco
import wrapdiag


def segments(m):
    out = []
    T = mujoco.mjtObj.mjOBJ_TENDON; G = mujoco.mjtObj.mjOBJ_GEOM
    CYL, SPH, JNT, PUL = (int(mujoco.mjtWrap.mjWRAP_CYLINDER), int(mujoco.mjtWrap.mjWRAP_SPHERE),
                          int(mujoco.mjtWrap.mjWRAP_JOINT), int(mujoco.mjtWrap.mjWRAP_PULLEY))
    for t in range(m.ntendon):
        adr, n = m.tendon_adr[t], m.tendon_num[t]
        if int(m.wrap_type[adr]) == JNT:
            continue
        j = 0
        while j < n - 1:
            t0, t1 = int(m.wrap_type[adr + j]), int(m.wrap_type[adr + j + 1])
            if t0 == PUL or t1 == PUL:
                j += 1
                continue
            if t1 in (CYL, SPH):
                g = int(m.wrap_objid[adr + j + 1])
                out.append((t, mujoco.mj_id2name(m, T, t), int(m.wrap_objid[adr + j]), g, int(m.wrap_objid[adr + j + 2]),
                            int(round(m.wrap_prm[adr + j + 1])), t1, float(m.geom_size[g][0])))
                j += 2
            else:
                j += 1
    return out


def _frame(p0, p1, kind):
    """2D frame of mju_wrap: cylinder = local x, y; sphere = p0 direction and the p0-0-p1 plane"""
    if kind == int(mujoco.mjtWrap.mjWRAP_CYLINDER):
        return np.array([1.0, 0, 0]), np.array([0, 1.0, 0])
    a0 = p0 / np.linalg.norm(p0)
    nrm = np.cross(p0, p1)
    n = np.linalg.norm(nrm)
    if n < 1e-15:
        return None, None
    nrm = nrm / n
    a1 = np.cross(nrm, a0)
    a1 = a1 / np.linalg.norm(a1)
    return a0, a1


def probe(m, d, seg, exact_below=1e-5):
    t, name, s0, g, s1, side, kind, r = seg
    xm = d.geom_xmat[g].reshape(3, 3)
    loc = lambda x: xm.T @ (x - d.geom_xpos[g])
    p0, p1 = loc(d.site_xpos[s0]), loc(d.site_xpos[s1])
    if np.linalg.norm(p0) < 1e-15 or np.linalg.norm(p1) < 1e-15:
        return None
    a0, a1 = _frame(p0, p1, kind)
    if a0 is None:
        return None
    end = [p0 @ a0, p0 @ a1, p1 @ a0, p1 @ a1]
    sd = None
    inside = False
    if side >= 0:
        s3 = loc(d.site_xpos[side])
        v = np.array([s3 @ a0, s3 @ a1])
        nv = np.linalg.norm(v)
        if nv > 0:
            sd = list(v / nv * r)
        inside = np.linalg.norm(s3) < r
    if inside:  # wrap_inside (Newton) - not the length_circle path
        return (None, "inside", None)
    w, info = wrapdiag.wrap_circle(end, sd, r)
    tmp2 = info.get("tmp2")
    if tmp2 is None:
        return (None, info.get("exit"), None)
    mg = (info["sqrad"] - tmp2) / info["sqrad"]
    omd = None
    if info.get("exit") == "wrap" and mg < exact_below:
        dec = wrapdiag.decimal_circle(end, sd, r)
        omd = float(dec[f"one_minus_dot{info['chosen']}"])
    return (mg, info.get("exit"), omd)


def probe_all(m, d, segs, exact_below=1e-5):
    return [probe(m, d, s, exact_below) for s in segs]
