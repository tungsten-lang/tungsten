"""Does the swing-ankle chatter drive the tendon line across its tangent? Open-loop replay (recorded ctrl) of the last 3 s before the blow-up in the
unchanged model and in variants that suppress the swing ankle's response (damping / armature), reporting the substep statistics of the recfem_r wrap
margin: std of the margin, fraction of substeps within 1e-4 of the tangent, sign changes per second, and the swing ankle's angle chatter.
usage: chatter_effect.py DIR [t_start=13.5]   (the replay stops at the recorded failing step)"""
import sys
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/blowup")
import numpy as np, mujoco, replaylib, wrapscan

D = sys.argv[1]; t_start = float(sys.argv[2]) if len(sys.argv) > 2 else 13.5
m0, ring = replaylib.load(D)
T = np.array(ring["t"]); k0 = int(np.argmin(np.abs(T - t_start)))
spec = int(ring["spec"])
replaylib.quiet()
seg = [s for s in wrapscan.segments(m0) if s[1] == "recfem_r_tendon"][0]
ank = m0.jnt_qposadr[m0.joint("ankle_angle_r").id]


def run(edit):
    m = replaylib.load(D)[0]
    edit(m)
    d = mujoco.MjData(m); mujoco.mj_setState(m, d, ring["state"][k0], spec)
    mg, qa = [], []
    for i in range(k0 + 1, len(T)):
        d.ctrl[:] = ring["state"][i][467:757]
        for s in range(10):
            mujoco.mj_step(m, d)
            r = wrapscan.probe(m, d, seg, exact_below=0.0)
            if r[0] is not None:
                mg.append(r[0])
        qa.append(d.qpos[ank])
    mg = np.array(mg)
    return mg, np.array(qa)


def report(name, mg, qa):
    secs = len(qa) / 100.0
    flips = int((np.diff(mg > 0) != 0).sum())
    print(f"{name:34s} margin mean {mg.mean():+.2e} std {mg.std():.2e}  within 1e-4: {np.mean(np.abs(mg) < 1e-4):.3f}  within 1e-6: {np.mean(np.abs(mg) < 1e-6):.4f}  crossings/s {flips / secs:6.1f}  "
          f"ankle step-to-step |dq| {np.median(np.abs(np.diff(qa))):.2e}")


def damp(add_d, add_a):
    def f(m):
        for nm in ("ankle_angle_r", "subtalar_angle_r"):
            a = m.jnt_dofadr[m.joint(nm).id]
            m.dof_damping[a] += add_d
            m.dof_armature[a] += add_a
    return f


for name, edit in (("unchanged", lambda m: None), ("ankle damping +0.5, armature +0.02", damp(0.5, 0.02)), ("ankle damping +2, armature +0.1", damp(2.0, 0.1))):
    mg, qa = run(edit)
    report(name, mg, qa)
