"""How robust is the phase-1 kick to what makes phase 2 different? The P2 environment with the reset replaced:
the root at (39 + dx, dy) and every joint at the P1 key frame plus `noise` times the P2 seed's joint noise.

  p1probe.py --controller C --params P --dx 0,-0.1 --dy 0,0.1 --noise 0,1 --seeds 5000:5006 [--seconds 4]
"""
import argparse, json, os, sys, itertools, multiprocessing as mp
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
from search4 import read_params


def run(job):
    params, ctl, dx, dy, noise, seed, secs = job
    os.environ["MYO_SOCCER_ENV"] = os.environ.get("PROBE_ENV", "myoChallengeSoccerP2-v0")
    import mujoco
    from myosuite.utils import gym as mgym
    from myo_bridge import MyoSim
    from tasks.myo_soccer import MyoSoccerTask
    # the P1 key frame
    e1 = mgym.make("myoChallengeSoccerP1-v0"); e1.reset(seed=0)
    u1 = e1.unwrapped
    q_p1 = u1.mj_data.qpos.copy()
    orig_make = mgym.make

    def make2(*a, **k):
        env = orig_make(*a, **k)
        u = env.unwrapped
        orig_grs = u._get_reset_state

        def grs():
            qn, qv = orig_grs()          # the env's own randomized state (noise drawn from its seeded rng)
            m = u.mj_model
            q = q_p1.copy()
            for j in range(m.njnt):
                if m.jnt_type[j] in (2, 3):
                    adr = m.jnt_qposadr[j]
                    q[adr] = q_p1[adr] + noise * (qn[adr] - q_p1[adr])
            ra = m.jnt_qposadr[m.joint("root").id]
            q[ra] = q_p1[ra] + dx
            q[ra + 1] = q_p1[ra + 1] + dy
            return q, np.zeros_like(qv)
        u._get_reset_state = grs
        return env
    mgym.make = make2
    try:
        m = MyoSim(MyoSoccerTask(), params=params, controller=ctl, seed=seed).run(secs)
    finally:
        mgym.make = orig_make
    return {"dx": dx, "dy": dy, "noise": noise, "seed": seed, "goal": m.get("goal"), "ball_speed": m.get("ball_speed"),
            "t_touch": m.get("t_touch"), "stand": m.get("stand_time"), "fallen": m.get("fallen"), "plant_err": m.get("plant_err"),
            "cross_y": m.get("cross_y", m.get("pred_y")),
            "events": [(e[1].split(":")[-1], e[0]) for e in (m.get("events") or [])][:14],
            "t_fall": m.get("t_fall"), "touch_body": m.get("touch_body"), "launch": m.get("launch_deg")}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--controller", required=True)
    ap.add_argument("--params", required=True)
    ap.add_argument("--dx", default="0")
    ap.add_argument("--dy", default="0")
    ap.add_argument("--noise", default="0,1")
    ap.add_argument("--seeds", default="5000:5004")
    ap.add_argument("--seconds", type=float, default=4.0)
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--set", default="")
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()
    lo, hi = a.seeds.split(":")
    seeds = list(range(int(lo), int(hi)))
    p = read_params(a.params)
    for kv in a.set.split(","):
        if "=" in kv:
            k, v = kv.split("="); p[k.strip()] = float(v)
    ctl = os.path.abspath(a.controller)
    jobs = [(p, ctl, float(dx), float(dy), float(nz), s, a.seconds)
            for dx in a.dx.split(",") for dy in a.dy.split(",") for nz in a.noise.split(",") for s in seeds]
    with mp.Pool(a.workers) as pool:
        res = pool.map(run, jobs)
    import collections
    agg = collections.OrderedDict()
    for r in res:
        agg.setdefault((r["dx"], r["dy"], r["noise"]), []).append(r)
    for k, rs in agg.items():
        g = sum(1 for r in rs if r["goal"])
        sp = np.mean([r["ball_speed"] or 0 for r in rs])
        st = np.mean([r["stand"] or 0 for r in rs])
        pe = [r["plant_err"] for r in rs if r["plant_err"] is not None]
        if a.verbose:
            for r in rs:
                print("   seed", r["seed"], "goal", r["goal"], "ball", r["ball_speed"], "touch", r["t_touch"], r["touch_body"], "launch", r["launch"], "stand", r["stand"], "|", " ".join(f"{n}@{t:.2f}" for n, t in r["events"]))
        print(f"dx {k[0]:+.2f} dy {k[1]:+.2f} noise {k[2]:.2f}: goals {g}/{len(rs)} ball {sp:5.2f} m/s stand {st:.2f} plant_err {np.mean(pe) if pe else float('nan'):.2f} fallen {sum(1 for r in rs if r['fallen'])}", flush=True)
