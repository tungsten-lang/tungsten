"""Inter-leg contact force and clearance during the hold, per start.
usage: legforce.py <params> <controller> <seeds a:b|s,s,..> <seconds> [workers] [k=v,...]
per start: mean / max inter-leg contact force after 3 s, the fraction of steps with any inter-leg contact, the smallest
swing-leg / stance-leg geom distance seen after 3 s (negative = penetration), bal1_s and stand time."""
import os, sys, json, math, multiprocessing as mp
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
from search4 import read_params


def run(job):
    params, seed, ctl, secs = job
    os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
    os.environ["MYO_SOCCER_MAX_TIME"] = "310"
    import numpy as np
    import mujoco
    from myo_bridge import MyoSim
    from tasks.myo_soccer import MyoSoccerTask
    acc = {"n": 0, "sum": 0.0, "max": 0.0, "hit": 0, "dmin": 1.0, "ids": None}

    class T(MyoSoccerTask):
        def on_step(self, sim, obs, reward, info):
            super().on_step(sim, obs, reward, info)
            m, d = sim.m, sim.d
            if acc["ids"] is None:
                L, R = set(), set()
                for b in range(m.nbody):
                    nm = m.body(b).name
                    if nm.endswith("_l"):
                        L.add(b)
                    elif nm.endswith("_r"):
                        R.add(b)
                gl = [g for g in range(m.ngeom) if m.geom_bodyid[g] in L and m.geom_contype[g] + m.geom_conaffinity[g] > 0]
                gr = [g for g in range(m.ngeom) if m.geom_bodyid[g] in R and m.geom_contype[g] + m.geom_conaffinity[g] > 0]
                acc["ids"] = (L, R, gl, gr)
            if float(d.time) < 3.0:
                return
            L, R, gl, gr = acc["ids"]
            tot = 0.0
            f6 = np.zeros(6)
            for i in range(d.ncon):
                c = d.contact[i]
                b1, b2 = m.geom_bodyid[c.geom1], m.geom_bodyid[c.geom2]
                if (b1 in L and b2 in R) or (b1 in R and b2 in L):
                    mujoco.mj_contactForce(m, d, i, f6)
                    tot += abs(f6[0])
            acc["n"] += 1
            acc["sum"] += tot
            acc["max"] = max(acc["max"], tot)
            acc["hit"] += tot > 0
            if acc["n"] % 20 == 0:
                fromto = np.zeros(6)
                best = 1.0
                for a in gl:
                    for b in gr:
                        if m.geom_bodyid[a] == m.geom_bodyid[b]:
                            continue
                        best = min(best, mujoco.mj_geomDistance(m, d, a, b, 0.2, fromto))
                acc["dmin"] = min(acc["dmin"], best)

    try:
        r = MyoSim(T(), params=params, controller=ctl, seed=seed).run(secs)
    except Exception as e:
        return seed, {"error": str(e)[:200]}
    n = max(acc["n"], 1)
    return seed, {"mean": acc["sum"] / n, "max": acc["max"], "hit": acc["hit"] / n, "dmin": acc["dmin"], "bal1": r.get("bal1_s"), "stand": r.get("stand_time"), "fallen": r.get("fallen")}


if __name__ == "__main__":
    params = read_params(sys.argv[1]); ctl = os.path.abspath(sys.argv[2]); sp = sys.argv[3]; secs = float(sys.argv[4])
    workers = int(sys.argv[5]) if len(sys.argv) > 5 else 4
    if len(sys.argv) > 6:
        for kv in sys.argv[6].split(","):
            if "=" in kv:
                k, v = kv.split("="); params[k] = float(v)
    seeds = list(range(int(sp.split(":")[0]), int(sp.split(":")[1]))) if ":" in sp else [int(x) for x in sp.split(",")]
    with mp.Pool(workers) as pool:
        res = pool.map(run, [(params, s, ctl, secs) for s in seeds])
    for s, r in sorted(res):
        if "error" in r:
            print(s, "ERROR", r["error"]); continue
        print(f"{s} force mean {r['mean']:6.1f} max {r['max']:6.1f} contact {100 * r['hit']:5.1f} % dmin {1000 * r['dmin']:+7.1f} mm | bal1 {r['bal1']:.1f} stand {r['stand']:.1f} fallen {r['fallen']}")
    ok = [r for _, r in res if "error" not in r]
    print(f"mean force {sum(r['mean'] for r in ok) / len(ok):.1f} N, worst max {max(r['max'] for r in ok):.1f} N, "
          f"starts with contact {sum(r['hit'] > 0 for r in ok)}/{len(ok)}, falls {sum(bool(r['fallen']) for r in ok)}/{len(ok)}")
