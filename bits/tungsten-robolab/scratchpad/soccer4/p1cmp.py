"""Compare the same P1-posture start in the P1 and the P2 environment (same controller): first divergence."""
import os, sys, numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
from search4 import read_params
import multiprocessing as mp

def run(job):
    envid, ctl, params = job
    os.environ["MYO_SOCCER_ENV"] = envid
    import mujoco
    from myosuite.utils import gym as mgym
    from myo_bridge import MyoSim
    from tasks.myo_soccer import MyoSoccerTask
    e1 = mgym.make("myoChallengeSoccerP1-v0"); e1.reset(seed=0)
    q_p1 = e1.unwrapped.mj_data.qpos.copy()
    orig_make = mgym.make
    def make2(*a, **k):
        env = orig_make(*a, **k)
        orig_reset = env.reset
        def reset2(*ra, **rk):
            out = orig_reset(*ra, **rk)
            u = env.unwrapped
            d, m = u.mj_data, u.mj_model
            d.qpos[:] = q_p1
            d.qvel[:] = 0
            mujoco.mj_forward(m, d)
            return out
        env.reset = reset2
        return env
    mgym.make = make2
    rec = []
    class T(MyoSoccerTask):
        def on_step(self, sim, obs, reward, info):
            super().on_step(sim, obs, reward, info)
            k = round(float(sim.d.time) * 100)
            if k in (0, 1, 2, 5, 10, 20, 50, 100, 150):
                rec.append((k, sim.d.qpos.copy(), sim.d.act.copy() if sim.m.na else None, sim.label))
    try:
        sim = MyoSim(T(), params=params, controller=ctl, seed=500)
        r = sim.run(1.6)
    finally:
        mgym.make = orig_make
    return rec, {k: r.get(k) for k in ("stand_time", "goal", "ball_speed")}, sim.muscle_ids and len(sim.muscle_ids)

if __name__ == "__main__":
    p = read_params("/Users/erik/tungsten/bits/tungsten-robolab/playground/arena/params/soccer_p1-20260926-151503.txt")
    ctl = "/Users/erik/tungsten/bits/tungsten-robolab/bin/champions/soccer_p1-20260926-151503"
    with mp.Pool(2) as pool:
        (r1, m1, n1), (r2, m2, n2) = pool.map(run, [("myoChallengeSoccerP1-v0", ctl, p), ("myoChallengeSoccerP2-v0", ctl, p)])
    print("P1", m1, "P2", m2)
    for (k1, q1, a1, l1), (k2, q2, a2, l2) in zip(r1, r2):
        dq = np.abs(q1 - q2)
        da = np.abs(a1 - a2).max() if a1 is not None else 0
        idx = np.argsort(-dq)[:3]
        print(f"t={k1/100:.2f} max|dqpos| {dq.max():.5f} at {idx.tolist()} max|dact| {da:.4f} labels {l1} | {l2}")
