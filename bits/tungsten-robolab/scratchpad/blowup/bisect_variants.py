"""Single-change bisect of the 91049 blow-up (DIAGNOSTIC variants of a private copy of the model, never the official environment).

usage: bisect.py DIR [t_start=13.5]
For every variant (one change of the model/options at a time) two replays with the recorded ctrl:
  A  from the ring state at t_start (~300 control steps before the blow-up) with the variant model for the whole window: does a MuJoCo
     instability warning still fire in the window? (any change re-rolls the rounding of the NaN sliver, so 'no' is not evidence of a cause)
  B  bit-exact replay with the ORIGINAL model up to the failing substep (16.517 s), then only that substep with the variant model:
     is the tendon length still NaN? (the NaN is produced by the position stage, so solver/contact/integrator/actuator variants cannot change it)
Column B also reports whether mj_fwdPosition alone (kinematics + tendon, no solver) gives the NaN under the variant model."""
import copy
import sys
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/blowup")
import numpy as np, mujoco, replaylib

D = sys.argv[1]
t_start = float(sys.argv[2]) if len(sys.argv) > 2 else 13.5
m0, ring = replaylib.load(D)
spec = int(ring["spec"])
T = np.array(ring["t"])
k0 = int(np.argmin(np.abs(T - t_start)))
ctrl_fail = ring["ctrl_fail"]
warns = []
mujoco.set_mju_user_warning(lambda msg: warns.append(msg))
J = mujoco.mjtObj.mjOBJ_JOINT


def variant_models():
    """(name, description, make(m) -> None edits a fresh copy in place, substeps per control step)"""
    out = []
    def add(name, desc, fn, nsub=10):
        out.append((name, desc, fn, nsub))
    add("none", "unchanged model", lambda m: None)
    add("dt/2", "timestep 0.0005, 20 substeps per control step", lambda m: setattr(m.opt, "timestep", 0.0005), 20)
    add("solver CG", "opt.solver = CG", lambda m: setattr(m.opt, "solver", mujoco.mjtSolver.mjSOL_CG))
    add("solver PGS", "opt.solver = PGS", lambda m: setattr(m.opt, "solver", mujoco.mjtSolver.mjSOL_PGS))
    add("iterations 500, tol 1e-12", "Newton, 500 iterations, tolerance 1e-12", lambda m: (setattr(m.opt, "iterations", 500), setattr(m.opt, "tolerance", 1e-12)))
    add("elliptic cone", "opt.cone = elliptic", lambda m: setattr(m.opt, "cone", mujoco.mjtCone.mjCONE_ELLIPTIC))
    add("impratio 10", "opt.impratio = 10", lambda m: setattr(m.opt, "impratio", 10.0))
    add("noslip 10", "opt.noslip_iterations = 10", lambda m: setattr(m.opt, "noslip_iterations", 10))
    add("no islands", "islands disabled", lambda m: setattr(m.opt, "disableflags", int(m.opt.disableflags) | int(mujoco.mjtDisableBit.mjDSBL_ISLAND)))
    add("implicitfast", "integrator implicitfast", lambda m: setattr(m.opt, "integrator", mujoco.mjtIntegrator.mjINT_IMPLICITFAST))
    add("dense jacobian", "opt.jacobian = dense", lambda m: setattr(m.opt, "jacobian", mujoco.mjtJacobian.mjJAC_DENSE))
    add("no warmstart", "warmstart disabled", lambda m: setattr(m.opt, "disableflags", int(m.opt.disableflags) | int(mujoco.mjtDisableBit.mjDSBL_WARMSTART)))
    add("no contact", "contacts disabled", lambda m: setattr(m.opt, "disableflags", int(m.opt.disableflags) | int(mujoco.mjtDisableBit.mjDSBL_CONTACT)))
    add("no constraints", "all constraints disabled", lambda m: setattr(m.opt, "disableflags", int(m.opt.disableflags) | int(mujoco.mjtDisableBit.mjDSBL_CONSTRAINT)))
    def no_leg_pair(m):
        g1, g2 = m.geom("r_tibia1_col").id, m.geom("l_femur2_col").id
        far1, far2 = m.geom("base").id, m.geom("logo").id  # goalkeeper geoms 11 m away: the pair can no longer touch
        for i in range(m.npair):
            if {m.pair_geom1[i], m.pair_geom2[i]} == {g1, g2}:
                m.pair_geom1[i], m.pair_geom2[i] = far1, far2
    add("no tibia_r-femur_l pair", "the 215 N swing-shank / stance-thigh contact pair removed", no_leg_pair)
    def soft_pair(m):
        g1, g2 = m.geom("r_tibia1_col").id, m.geom("l_femur2_col").id
        for i in range(m.npair):
            if {m.pair_geom1[i], m.pair_geom2[i]} == {g1, g2}:
                m.pair_solref[i] = [0.05, 1.0]                      # 2.5x softer
                m.pair_solimp[i] = [0.5, 0.9, 0.005, 0.5, 2.0]
                m.pair_margin[i] = 0.002
    add("softened tibia_r-femur_l pair", "pair solref [0.05 1], solimp [0.5 0.9 0.005 .5 2], margin 2 mm", soft_pair)
    def slow_muscles(m):
        m.actuator_dynprm[:, 0] *= 2.0   # muscle activation time constant x2
        m.actuator_dynprm[:, 1] *= 2.0   # deactivation time constant x2
    add("muscle activation dynamics x2", "actuator_dynprm tau_act, tau_deact x2 (all muscles)", slow_muscles)
    def no_side(m):
        t = m.tendon("recfem_r_tendon").id
        adr = m.tendon_adr[t]
        for j in range(m.tendon_num[t]):
            if int(m.wrap_type[adr + j]) == int(mujoco.mjtWrap.mjWRAP_CYLINDER):
                m.wrap_prm[adr + j] = -1                            # sidesite removed: the wrap picks the shorter path
    add("recfem_r wrap sidesite removed", "tendon geometry: the KnExt cylinder wrap of recfem_r without its sidesite", no_side)
    def ankle_damp(m):
        for nm in ("ankle_angle_r", "subtalar_angle_r"):
            a = m.jnt_dofadr[m.joint(nm).id]
            m.dof_damping[a] += 0.5
            m.dof_armature[a] += 0.02
    add("swing ankle damping+armature", "ankle_angle_r / subtalar_angle_r damping +0.5, armature +0.02", ankle_damp)
    add("wrap radius x(1+1e-6)", "KnExt_at_fem_r_wrap cylinder radius +2.5e-8 m", lambda m: m.geom_size.__setitem__((m.geom("KnExt_at_fem_r_wrap").id, 0), 0.025 * (1 + 1e-6)))
    add("wrap radius x(1-1e-3)", "KnExt_at_fem_r_wrap cylinder radius -2.5e-5 m", lambda m: m.geom_size.__setitem__((m.geom("KnExt_at_fem_r_wrap").id, 0), 0.025 * (1 - 1e-3)))
    add("wrap radius 0", "KnExt_at_fem_r_wrap wrap disabled (radius 0: no wrap)", lambda m: m.geom_size.__setitem__((m.geom("KnExt_at_fem_r_wrap").id, 0), 0.0))
    return out


def load_model():
    return mujoco.MjModel.from_binary_path(D.rstrip("/") + "/model.mjb")


rows = []
for name, desc, fn, nsub in variant_models():
    # ---- A: replay from t_start with the variant model
    m = load_model(); fn(m)
    d = replaylib.data_at(m0, ring, k0)  # state layout is identical for every variant (same sizes)
    mujoco.mj_setState(m, d, ring["state"][k0], spec)
    warns.clear()
    fired_at = None
    n_ctrl = len(T) - k0
    for i in range(k0 + 1, len(T) + 1):
        ctrl = ring["state"][i][467:757] if i < len(T) else ctrl_fail   # CTRL block of ring state i (= ctrl of control step i)
        d.ctrl[:] = ctrl
        for s in range(nsub):
            t0 = float(d.time)
            mujoco.mj_step(m, d)
            if float(d.time) < t0:
                fired_at = t0
                break
        if fired_at is not None:
            break
    a_res = f"blow-up at {fired_at:.3f} s" if fired_at is not None else "no warning to 16.52 s"
    # ---- B: bit-exact to the failing substep with the original model, then the failing substep under the variant
    d0 = replaylib.data_at(m0, ring, len(T) - 1)
    d0.ctrl[:] = ctrl_fail
    for s in range(7):
        mujoco.mj_step(m0, d0)
    snap = np.zeros(mujoco.mj_stateSize(m0, spec)); mujoco.mj_getState(m0, d0, snap, spec)
    mv = load_model(); fn(mv)
    dv = mujoco.MjData(mv)
    mujoco.mj_setState(mv, dv, snap, spec)
    mujoco.mj_fwdPosition(mv, dv)   # position stage only: no solver, no contacts, no actuators
    pos_nan = bool(np.isnan(dv.ten_length[239]))
    mujoco.mj_setState(mv, dv, snap, spec)
    dv.ctrl[:] = ctrl_fail
    t_before = float(dv.time)
    mujoco.mj_step(mv, dv)
    b_res = "NaN tendon 239 in mj_fwdPosition" if pos_nan else "finite (no NaN)"
    b_step = "step resets (blow-up)" if float(dv.time) < t_before else "step completes"
    rows.append((name, a_res, b_res, b_step))
    print(f"{name:30s} | A (from {T[k0]:.2f} s): {a_res:26s} | B (failing substep only): {b_res:34s} {b_step}", flush=True)
