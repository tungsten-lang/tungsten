"""Bit-exact open-loop replay of a captured run (recorded ctrl per control step), recording at EVERY substep the graze margin of a
cylinder-wrapped tendon's wrap and, for the wrapping-active substeps close to the boundary, the exact 1-dot of the tangent points.

usage: hazard_replay.py DIR [tendon=239] [t_from=0]
prints: validation (replayed states == ring states bit for bit), the substep margin histogram, the near-boundary substeps, and the expected
number of NaN events sum_p(1-dot) under the empirical NaN probability table of nan_band_scan.py, against the observed number of warnings."""
import sys
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/blowup")
import numpy as np, mujoco, replaylib, wrapdiag

D = sys.argv[1]
ten = int(sys.argv[2]) if len(sys.argv) > 2 else 239
t_from = float(sys.argv[3]) if len(sys.argv) > 3 else 0.0
m, ring = replaylib.load(D)
spec = int(ring["spec"]); S = ring["state"]
catcher = replaylib.WarnCatcher()
mujoco.set_mju_user_warning(catcher)
adr = m.tendon_adr[ten]
segs = []
for j in range(m.tendon_num[ten] - 1):
    if int(m.wrap_type[adr + j + 1]) == int(mujoco.mjtWrap.mjWRAP_CYLINDER):
        segs.append((int(m.wrap_objid[adr + j]), int(m.wrap_objid[adr + j + 1]), int(m.wrap_objid[adr + j + 2]), int(round(m.wrap_prm[adr + j + 1]))))
s0, g, s1, side = segs[0]
r = float(m.geom_size[g][0])


def probe(d):
    """margin and (if wrapping and close) exact 1-dot of the state d evaluated in its LAST forward pass"""
    xm = d.geom_xmat[g].reshape(3, 3)
    loc = lambda x: xm.T @ (x - d.geom_xpos[g])
    p0, p1 = loc(d.site_xpos[s0]), loc(d.site_xpos[s1])
    end = [p0[0], p0[1], p1[0], p1[1]]
    sd = None
    if side >= 0:
        s3 = loc(d.site_xpos[side]); v = np.array([s3[0], s3[1]]); sd = list(v / np.linalg.norm(v) * r)
    w, info = wrapdiag.wrap_circle(end, sd, r)
    tmp2 = info.get("tmp2")
    if tmp2 is None:
        return None, None
    mg = (info["sqrad"] - tmp2) / info["sqrad"]
    omd = None
    if info.get("exit") == "wrap" and mg < 1e-5:
        dec = wrapdiag.decimal_circle(end, sd, r)
        omd = float(dec[f"one_minus_dot{info['chosen']}"])
    return mg, omd


d = replaylib.data_at(m, ring, 0)
N = len(ring["t"])
mism = 0
margins, near, exp_nan, nsub = [], [], 0.0, 0
P_TABLE = [(1e-17, .295), (3e-17, .202), (6e-17, .135), (8e-17, .071), (1e-16, .047), (1.2e-16, .045), (1.5e-16, .022), (2.5e-16, .004)]


def p_nan(omd):
    for hi, p in P_TABLE:
        if omd < hi:
            return p
    return 0.0


first_bad = None
for i in range(N - 1):
    tnext = float(ring["t"][i + 1])
    dn = replaylib.data_at(m, ring, i + 1)
    ctrl = dn.ctrl.copy()
    d.ctrl[:] = ctrl
    for sub in range(10):
        nw = len(catcher.events)
        mujoco.mj_step(m, d)
        if len(catcher.events) > nw:
            print("WARNING during replay control step", i + 1, "substep", sub, catcher.events[-1])
            first_bad = first_bad or (i + 1, sub)
            break
        if float(d.time) >= t_from:
            mg, omd = probe(d)
            if mg is not None:
                margins.append(mg)
                if omd is not None:
                    exp_nan += p_nan(omd)
                    near.append((float(d.time) - 0.001, mg, omd))
            nsub += 1
    if first_bad:
        break
    st = np.zeros(mujoco.mj_stateSize(m, spec)); mujoco.mj_getState(m, d, st, spec)
    if not np.array_equal(st.view(np.uint64), S[i + 1].view(np.uint64)):
        mism += 1
        if mism == 1:
            print("first state mismatch at control step", i + 1, "t", tnext, "max diff", float(np.abs(st - S[i + 1]).max()))
print(f"replayed {i + 1} control steps ({nsub} substeps evaluated); state mismatches vs ring: {mism}")
mg = np.array(margins)
print("substeps with wrap evaluated:", len(mg), " wrapping-active (margin>0):", int((mg > 0).sum()), " no-wrap:", int((mg <= 0).sum()))
for lo, hi in [(0, 1e-8), (1e-8, 6e-8), (6e-8, 1e-7), (1e-7, 1e-6), (1e-6, 1e-5), (1e-5, 1e-4), (1e-4, 1e-3), (1e-3, 1e-2), (1e-2, 1.0)]:
    print(f"  margin in [{lo:7.0e}, {hi:7.0e}): {int(((mg >= lo) & (mg < hi)).sum()):7d} substeps")
print("nearest-boundary wrapping substeps (t, margin, exact 1-dot) - the 12 smallest margins:")
for t, mgv, omd in sorted(near, key=lambda x: x[1])[:12]:
    print(f"  t {t:9.4f} margin {mgv:+.3e} exact 1-dot {omd:.3e} p_nan {p_nan(omd):.3f}")
print(f"expected NaN events over the replayed substeps (sum of p_nan): {exp_nan:.3f}; observed warnings: {len(catcher.events)} (first at {first_bad})")
