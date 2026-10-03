"""Why does the harness replay of a capture differ from its rollout? Re-run the capture's rollout, keep every tick's state after the
penultimate touchdown, replay the recorded controls in a fresh Body from the captured state, and compare tick by tick. (L3 scratch)"""
import os, sys, json, importlib
os.environ.setdefault("MUJOCO_GL", "cgl")
HERE = "/Users/erik/tungsten/bits/tungsten-robolab/playground"
sys.path.insert(0, HERE)
import numpy as np
import mujoco
import long_jump_limits as L


def main():
    name = sys.argv[1]
    cap = L.load_capture(name)
    body = L.Body(cap["task"], cap["board_x"], json.loads(cap["env"]))
    from bridge import Sim
    from search import read_params
    task = L.load_task(cap["task"], cap["board_x"])
    sd = int(cap["seed"]) if int(cap["seed"]) >= 0 else None
    task.seed = sd
    params = json.loads(cap["params"])
    params.pop("j_ik", None)
    sim = Sim(task, params=params, controller=cap["controller"])
    m, d = sim.m, sim.d
    print("model compare: timestep", m.opt.timestep, body.m.opt.timestep, "nu", m.nu, body.m.nu, "nq", m.nq, body.m.nq, "nv", m.nv, body.m.nv, "na", m.na, body.m.na)
    for attr in ("actuator_gainprm", "actuator_biasprm", "actuator_dynprm", "geom_friction", "geom_solref", "geom_solimp", "body_mass", "jnt_stiffness", "dof_damping", "actuator_lengthrange", "tendon_stiffness", "tendon_damping"):
        a, b = getattr(m, attr), getattr(body.m, attr)
        print("  %-22s shapes %s %s maxdiff %s" % (attr, a.shape, b.shape, float(np.abs(a - b).max()) if a.shape == b.shape and a.size else "-"))
    size = mujoco.mj_stateSize(m, L.SPEC)
    task.reset(m, d)
    mujoco.mj_forward(m, d)
    sim.start_controller()
    substeps = max(1, round(task.control_dt / m.opt.timestep))
    states, ctrls, times = [], [], []
    t_cap = float(cap["t0"])
    try:
        while d.time < t_cap + 0.85:
            st = np.zeros(size)
            mujoco.mj_getState(m, d, st, L.SPEC)
            act, c = sim.tick()
            states.append(st)
            ctrls.append(d.ctrl[sim.act_ids].copy())
            times.append(d.time)
            for _ in range(substeps):
                task.before_step(m, d)
                mujoco.mj_step(m, d)
            sim.log.append((d.time, sim.label, act.copy(), c.copy(), sim.targets.copy()))
            if task.done(m, d):
                break
    finally:
        sim.stop_controller()
    k0 = int(np.argmin(np.abs(np.array(times) - t_cap)))
    print("k0", k0, "t", times[k0], "capture t0", t_cap, "state diff to capture", float(np.abs(states[k0] - cap["state"]).max()))
    # replay
    mujoco.mj_setState(body.m, body.d, cap["state"], L.SPEC)
    mujoco.mj_forward(body.m, body.d)
    bm, bd = body.m, body.d
    cc = cap["ctrl"]
    print("recorded ctrl vs re-run ctrl (first ticks): max diff", float(np.abs(cc[:10] - np.array(ctrls[k0:k0 + 10])).max()))
    for j in range(0, 200):
        k = k0 + j
        stq = np.zeros(size)
        mujoco.mj_getState(bm, bd, stq, L.SPEC)
        diff = np.abs(stq - states[k])
        if j % 20 == 0 or diff.max() > 1e-6:
            print("tick %2d t %.3f max|dstate| %.3e  (qpos %.3e qvel %.3e)" % (j, times[k], diff.max(), np.abs(bd.qpos - states[k][1:1 + bm.nq]).max() if True else 0, np.abs(bd.qvel - states[k][1 + bm.nq:1 + bm.nq + bm.nv]).max()))
        if diff.max() > 1e-3 and j > 3:
            break
        bd.ctrl[body.act_ids] = np.clip(cc[min(j, len(cc) - 1)], 0, 1)
        for _ in range(body.substeps):
            mujoco.mj_step(bm, bd)


main()
