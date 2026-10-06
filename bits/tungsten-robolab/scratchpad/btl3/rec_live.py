"""Closed-loop recorder of the LIVE state (round 3, M1): runs a controller on seeds and keeps, per 5 ms tick, what a stroke with
feedback could sense or what determines its outcome.

    OMP_NUM_THREADS=1 .venv/bin/python scratchpad/btl3/rec_live.py ctl params s0 s1 secs out_dir [workers]

One npz per seed in out_dir (live_<seed>.npz): t, label, ball pos / vel, per side (l, r) the palm site position and velocity, the 8 arm
joints' q and qd (POSTURE_JOINTS), the arm muscles' activations (16 per side), the muscle contraction and its rate (16 per side), the
hand-ball contact force (max over the tick's 5 physics steps, in ball weights) and the task's pass_log.
Run from bits/tungsten-robolab.
"""
import os
import sys

import mujoco
import numpy as np

sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")
sys.path.insert(0, "scratchpad/btl2")

JOINTS = ["shoulder_flex", "shoulder_abd", "shoulder_rot", "elbow", "wrist_flex", "wrist_dev", "finger_mcp", "finger_pip"]
SUBSTEPS = 5


def run_live(seed, params, ctl, secs):
    import oracle_lib as O
    t, sim = O.build_sim(seed, params, ctl)
    m, d = sim.m, sim.d
    t.reset(m, d)
    mujoco.mj_forward(m, d)
    sim.start_controller()
    ball_id = m.body("ball").id
    ball_geom = m.geom("ball").id
    ball_dof = t.ball_dof
    hand_geoms = {}
    for s in "lr":
        for g in ("hand", "fingers1", "fingers2"):
            hand_geoms[m.geom(f"{s}_{g}").id] = s
    palm = {s: m.site(f"{s}_palm").id for s in "lr"}
    qadr = {s: [m.jnt_qposadr[m.joint(f"{s}_{j}").id] for j in JOINTS] for s in "lr"}
    dadr = {s: [m.jnt_dofadr[m.joint(f"{s}_{j}").id] for j in JOINTS] for s in "lr"}
    names = [mu.name for mu in sim.muscles]
    arm_idx = {s: [names.index(f"{s}_{j}_{sg}") for j in JOINTS for sg in ("pos", "neg")] for s in "lr"}
    w = 0.62 * 9.81
    f6 = np.zeros(6)
    res6 = np.zeros(6)
    rows = {k: [] for k in ("t", "ball", "ballv", "palm_l", "palm_r", "pv_l", "pv_r", "q_l", "q_r", "qd_l", "qd_r",
                            "act_l", "act_r", "c_l", "c_r", "cd_l", "cd_r", "F_l", "F_r")}
    labels = []
    try:
        while d.time < secs - 1e-9:
            act, c = sim.tick()
            _, cd, _ = sim.contraction()
            fm = {"l": 0.0, "r": 0.0}
            for _ in range(SUBSTEPS):
                t.before_step(m, d)
                mujoco.mj_step(m, d)
                for i in range(d.ncon):
                    g1, g2 = d.contact.geom1[i], d.contact.geom2[i]
                    if g1 != ball_geom and g2 != ball_geom:
                        continue
                    o = g2 if g1 == ball_geom else g1
                    s = hand_geoms.get(o)
                    if s is None:
                        continue
                    mujoco.mj_contactForce(m, d, i, f6)
                    fm[s] = max(fm[s], abs(f6[0]) / w)
            labels.append(sim.label)
            rows["t"].append(d.time)
            rows["ball"].append(d.xpos[ball_id].copy())
            rows["ballv"].append(d.qvel[ball_dof:ball_dof + 3].copy())
            for s in "lr":
                rows["palm_" + s].append(d.site_xpos[palm[s]].copy())
                mujoco.mj_objectVelocity(m, d, mujoco.mjtObj.mjOBJ_SITE, palm[s], res6, 0)
                rows["pv_" + s].append(res6[3:].copy())
                rows["q_" + s].append(d.qpos[qadr[s]].copy())
                rows["qd_" + s].append(d.qvel[dadr[s]].copy())
                rows["act_" + s].append(act[arm_idx[s]].copy())
                rows["c_" + s].append(c[arm_idx[s]].copy())
                rows["cd_" + s].append(cd[arm_idx[s]].copy())
                rows["F_" + s].append(fm[s])
    finally:
        sim.stop_controller()
    try:
        met = t.metrics(m, d, [])
    except Exception:
        met = {}
    out = {k: np.array(v) for k, v in rows.items()}
    out["label"] = np.array(labels)
    return out, met


def job(a):
    ctl, pfile, seed, secs, out_dir = a
    from common import load
    params = load(pfile)
    fn = os.path.join(out_dir, f"live_{seed}.npz")
    if os.path.exists(fn):
        return seed
    out, met = run_live(seed, params, ctl, secs)
    import json
    np.savez_compressed(fn, pass_log=np.array(json.dumps(met.get("pass_log", []))), streak=met.get("btl_streak", -1), **out)
    return seed


def main():
    from multiprocessing import Pool
    ctl, pfile, s0, s1, secs, out_dir = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), float(sys.argv[5]), sys.argv[6]
    workers = int(sys.argv[7]) if len(sys.argv) > 7 else 4
    os.makedirs(out_dir, exist_ok=True)
    with Pool(workers) as p:
        for s in p.imap_unordered(job, [(ctl, pfile, s, secs, out_dir) for s in range(s0, s1)]):
            print("done", s, flush=True)


if __name__ == "__main__":
    main()
