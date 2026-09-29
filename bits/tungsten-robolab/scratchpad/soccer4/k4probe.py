"""The standing kick from the robust left stance, in isolation: the P2 environment with the reset moved so both feet stand d0 behind
the ball (the P2 seed's joint noise kept), the routine's shift/lift onto the left leg, the right leg wound back and the parent's swing.

  k4probe.py --controller C --params P --d0 0.35,0.45 --seeds 90000:90006 [--set k=v,..] [--kick p1] [--seconds 6]
"""
import argparse, json, os, sys, multiprocessing as mp
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
from search4 import read_params

KICK = ["th_back", "knee_back", "ankle_back", "th_k1", "knee_k1", "ankle_k", "th_k2", "knee_k2", "hip_snap", "drv_hip", "drv_knee",
        "t_swing", "t_snap", "add_k", "k_ky", "kick_dy", "rot_k", "aim_add", "aim_dy", "aim_rot", "aim_split", "left_add", "left_dy",
        "left_rot", "left_pdy", "ks_dx", "ks_dz", "ks_pitch", "t_follow", "th_fol", "knee_fol", "ankle_land", "th_land", "knee_land", "drv_brake", "g_kick", "g_anta"]


def run(job):
    params, ctl, d0, dy0, seed, secs = job
    os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
    import mujoco
    from myosuite.utils import gym as mgym
    from myo_bridge import MyoSim
    from tasks.myo_soccer import MyoSoccerTask
    e1 = mgym.make("myoChallengeSoccerP1-v0"); e1.reset(seed=0)
    q_p1 = e1.unwrapped.mj_data.qpos.copy()
    orig_make = mgym.make
    dx = 1.077 - d0

    def make2(*a, **k):
        env = orig_make(*a, **k)
        u = env.unwrapped
        orig_grs = u._get_reset_state

        def grs():
            qn, qv = orig_grs()
            m = u.mj_model
            q = qn.copy()
            ra = m.jnt_qposadr[m.joint("root").id]
            q[ra] = q_p1[ra] + dx
            q[ra + 1] = q_p1[ra + 1] + dy0
            return q, np.zeros_like(qv)
        u._get_reset_state = grs
        return env
    mgym.make = make2
    p = dict(params)
    p.update({"k4_pdx": -1.077 + dx, "k4_pdy": 0.0895 + dy0, "k4_rdx": -1.0775 + dx, "k4_rdy": -0.0925 + dy0})
    try:
        m = MyoSim(MyoSoccerTask(), params=p, controller=ctl, seed=seed).run(secs)
    finally:
        mgym.make = orig_make
    ev = m.get("events") or []
    return {"d0": d0, "seed": seed, "goal": m.get("goal"), "ball_speed": m.get("ball_speed"), "t_touch": m.get("t_touch"),
            "touch_body": m.get("touch_body"), "zone": m.get("strike_zone"), "stand": m.get("stand_time"), "fallen": m.get("fallen"),
            "launch": m.get("launch_deg"), "cross_y": m.get("cross_y", m.get("pred_y")),
            "events": [(e[1].split(":")[-1], e[0]) for e in ev][:16]}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--controller", required=True)
    ap.add_argument("--params", required=True)
    ap.add_argument("--kickparams", default="playground/arena/params/soccer_p1-20260926-151503.txt")
    ap.add_argument("--d0", default="0.45")
    ap.add_argument("--dy0", type=float, default=0.0)
    ap.add_argument("--seeds", default="90000:90006")
    ap.add_argument("--set", default="")
    ap.add_argument("--seconds", type=float, default=6.0)
    ap.add_argument("--workers", type=int, default=3)
    ap.add_argument("--verbose", action="store_true")
    a = ap.parse_args()
    p = read_params(a.params)
    kp = read_params(a.kickparams)
    for k in KICK:
        if k in kp:
            p[k] = kp[k]
    p.update({"bal": 0.0, "ap3": 1.0, "ap4": 1.0, "k4": 1.0, "s4set": 1.0})
    for kv in a.set.split(","):
        if "=" in kv:
            k, v = kv.split("="); p[k.strip()] = float(v)
    lo, hi = a.seeds.split(":")
    seeds = list(range(int(lo), int(hi)))
    ctl = os.path.abspath(a.controller)
    jobs = [(p, ctl, float(d0), a.dy0, s, a.seconds) for d0 in a.d0.split(",") for s in seeds]
    with mp.Pool(a.workers) as pool:
        res = pool.map(run, jobs)
    for d0 in a.d0.split(","):
        rs = [r for r in res if abs(r["d0"] - float(d0)) < 1e-9]
        g = sum(1 for r in rs if r["goal"])
        touched = [r for r in rs if r["t_touch"] is not None]
        print(f"d0 {d0}: goals {g}/{len(rs)}, touched {len(touched)}, mean ball {np.mean([r['ball_speed'] or 0 for r in rs]):.2f} m/s, "
              f"max {max([r['ball_speed'] or 0 for r in rs]):.2f}, standing at end {sum(1 for r in rs if not r['fallen'])}", flush=True)
        if a.verbose:
            for r in rs:
                print("  ", r["seed"], "ball", r["ball_speed"], "touch", r["t_touch"], r["touch_body"], r["zone"], "launch", r["launch"], "cross_y", r["cross_y"], "stand", r["stand"], "|", " ".join(f"{n}@{t:.1f}" for n, t in r["events"]))
