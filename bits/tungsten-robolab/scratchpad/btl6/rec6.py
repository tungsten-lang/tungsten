"""Closed-loop records for the CHAINED replay (round 6): one pickle per start with the activations, the ball path, the controller's labels, the physics
snapshots at the TRIGGER ticks of the programmed stages (the top of the tick at which the stage's table starts: stage 2 = the right hand's second g_run,
3 = the left hand's second, 4 = the right hand's third) and the event ticks (g_run onsets = stage triggers, x_recover onsets = the previous stage's release).

    scratchpad/btl6/py scratchpad/btl6/rec6.py ctl params s0 s1 out_dir [workers] [t_end]       (run from bits/tungsten-robolab)

Everything is exactly what `oracle_lib.record` / `Sim.run` do (same loop), so the record IS the closed loop. Skips starts whose pickle exists.
"""
import os
import pickle
import sys

import numpy as np

sys.path.insert(0, "scratchpad/btl2")
sys.path.insert(0, "playground")
sys.path.insert(0, "playground/tasks")
from multiprocessing import Pool  # noqa: E402

T_END = 6.0
SUBSTEPS = 5


def onsets_from_labels(labels):
    """tick -> list of events: ('g', hand) at a g_run onset, ('x', hand) at an x_recover onset."""
    ev = {}
    prev = {"right": "", "left": ""}
    for k, lab in enumerate(labels):
        cur = {}
        for part in lab.split("|"):
            if part.startswith("right:"):
                cur["right"] = part[6:]
            elif part.startswith("left:"):
                cur["left"] = part[5:]
        for h in ("right", "left"):
            c = cur.get(h, "")
            if c != prev[h]:
                if c == "g_run":
                    ev.setdefault(k, []).append(("g", h))
                if c == "x_recover":
                    ev.setdefault(k, []).append(("x", h))
                if prev[h] == "g_run":
                    ev.setdefault(k, []).append(("e", h))
                prev[h] = c
    return ev


def record_one(job):
    import mujoco
    import oracle_lib as O
    from common import load
    seed, pfile, ctl, out_dir = job[:4]
    t_end = job[4] if len(job) > 4 else T_END
    fn = os.path.join(out_dir, f"rec_{seed}.pkl")
    if os.path.exists(fn):
        return seed
    params = load(pfile)
    t, sim = O.build_sim(seed, params, ctl)
    m, d = sim.m, sim.d
    t.reset(m, d)
    mujoco.mj_forward(m, d)
    sim.start_controller()
    acts, labels, ball, ballv = [], [], [], []
    snaps = {}
    cur_snap = None
    prev = {"right": "", "left": ""}
    n_g = 0
    try:
        while d.time < t_end - 1e-9:
            cur_snap = O.snapshot(d)          # the top of tick len(acts): the state the frame is built from
            act, c = sim.tick()
            k = len(acts)
            acts.append(act.copy())
            labels.append(sim.label)
            cur = {}
            for part in sim.label.split("|"):
                if part.startswith("right:"):
                    cur["right"] = part[6:]
                elif part.startswith("left:"):
                    cur["left"] = part[5:]
            for h in ("right", "left"):
                if cur.get(h, "") != prev[h]:
                    if cur.get(h, "") == "g_run":
                        # the stage ordinal = the number of g_run onsets before this one (the chain alternates hands: stage 0 = the right hand's launch,
                        # 1 = the left return, 2 = the right return, 3 = the left second stroke, 4 = the right second stroke); a chain that broke
                        # is recognised by the hand parity and left out
                        st = n_g
                        n_g += 1
                        if 2 <= st <= 4 and st not in snaps and (h == "right") == (st % 2 == 0):
                            snaps[st] = (k, cur_snap)
                    prev[h] = cur.get(h, "")
            for _ in range(SUBSTEPS):
                t.before_step(m, d)
                mujoco.mj_step(m, d)
            ball.append(d.body("ball").xpos.copy())
            ballv.append(d.qvel[t.ball_dof:t.ball_dof + 3].copy())
            if t.lost_t is not None and d.time > t.lost_t + 0.6:
                break
    finally:
        sim.stop_controller()
    try:
        met = t.metrics(m, d, [])
        pass_log, streak = met.get("pass_log", []), met.get("btl_streak", 0)
    except Exception:
        pass_log, streak = [], 0
    ks2 = snaps[2][0] if 2 in snaps else None
    k_base = max(0, (ks2 if ks2 is not None else len(acts)) - 40)
    rec = {"seed": seed, "pass_log": pass_log, "streak": streak, "k_base": k_base, "n": len(acts),
           "acts": np.array(acts)[k_base:], "ball": np.array(ball)[k_base:], "ballv": np.array(ballv)[k_base:], "labels": labels[k_base:],
           "ev": {k - k_base: v for k, v in onsets_from_labels(labels).items() if k >= k_base},
           "ks": {s: v[0] for s, v in snaps.items()}, "snaps": {s: v[1] for s, v in snaps.items()},
           "act_ids": np.array(sim.act_ids), "names": [mu.name for mu in sim.muscles]}
    os.makedirs(out_dir, exist_ok=True)
    tmp = fn + f".{os.getpid()}"
    with open(tmp, "wb") as f:
        pickle.dump(rec, f, protocol=4)
    os.replace(tmp, fn)
    return seed


def main():
    ctl, pfile, s0, s1, out_dir = sys.argv[1], sys.argv[2], int(sys.argv[3]), int(sys.argv[4]), sys.argv[5]
    workers = int(sys.argv[6]) if len(sys.argv) > 6 else 6
    t_end = float(sys.argv[7]) if len(sys.argv) > 7 else T_END
    with Pool(workers) as p:
        for s in p.imap_unordered(record_one, [(sd, pfile, ctl, out_dir, t_end) for sd in range(s0, s1)]):
            print("done", s, flush=True)
    print("ALL DONE", flush=True)


if __name__ == "__main__":
    main()
