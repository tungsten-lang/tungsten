"""Mean inter-leg contact force during a hold: legcontact.py <params> <controller> <seeds a:b> <T> [workers]"""
import os, sys, multiprocessing as mp
import numpy as np, mujoco
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
from search4 import read_params

def run(job):
    params, seed, ctl, T = job
    os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
    os.environ["MYO_SOCCER_MAX_TIME"] = "310"
    from myo_bridge import MyoSim
    from tasks.myo_soccer import MyoSoccerTask
    acc = {"n": 0, "sum": 0.0, "max": 0.0, "pairs": {}}
    class Tk(MyoSoccerTask):
        def on_step(self, sim, obs, reward, info):
            super().on_step(sim, obs, reward, info)
            m, d = sim.m, sim.d
            if float(d.time) < 4.0: return
            tot = 0.0
            for i in range(d.ncon):
                c = d.contact[i]
                b1, b2 = m.geom_bodyid[c.geom1], m.geom_bodyid[c.geom2]
                n1, n2 = m.body(b1).name, m.body(b2).name
                if n1 == "world" or n2 == "world": continue
                s1, s2 = n1[-2:], n2[-2:]
                if {s1, s2} == {"_l", "_r"}:
                    f6 = np.zeros(6); mujoco.mj_contactForce(m, d, i, f6)
                    tot += abs(f6[0])
                    key = tuple(sorted((n1, n2)))
                    acc["pairs"][key] = acc["pairs"].get(key, 0.0) + abs(f6[0])
            acc["n"] += 1; acc["sum"] += tot; acc["max"] = max(acc["max"], tot)
    try:
        r = MyoSim(Tk(), params=params, controller=ctl, seed=seed).run(T)
    except Exception as e:
        return seed, None
    top = sorted(acc["pairs"].items(), key=lambda kv: -kv[1])[:2]
    return seed, (acc["sum"] / max(acc["n"], 1), acc["max"], [(k, round(v / max(acc["n"], 1), 1)) for k, v in top], r.get("bal1_s"))

if __name__ == "__main__":
    p = read_params(sys.argv[1]); ctl = os.path.abspath(sys.argv[2]); lo, hi = sys.argv[3].split(":"); T = float(sys.argv[4])
    workers = int(sys.argv[5]) if len(sys.argv) > 5 else 3
    with mp.Pool(workers) as pool:
        res = pool.map(run, [(p, s, ctl, T) for s in range(int(lo), int(hi))])
    for s, r in res:
        print(s, "mean force %.1f N max %.1f N" % (r[0], r[1]) if r else "ERR", r[2] if r else "", "bal1", r[3] if r else "")
