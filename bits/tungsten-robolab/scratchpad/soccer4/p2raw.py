"""Goals of a controller+params on the real P2 seeds (no reset patch): p2raw.py C P a:b [k=v,...]"""
import os, sys, json, multiprocessing as mp
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
from search4 import read_params

def run(job):
    params, ctl, seed, secs = job
    os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
    from myo_bridge import MyoSim
    from tasks.myo_soccer import MyoSoccerTask
    m = MyoSim(MyoSoccerTask(), params=params, controller=ctl, seed=seed).run(secs)
    return {"seed": seed, "goal": m.get("goal"), "ball": m.get("ball_speed"), "touch": m.get("t_touch"), "stand": m.get("stand_time"), "fallen": m.get("fallen")}

if __name__ == "__main__":
    ctl = os.path.abspath(sys.argv[1]); p = read_params(sys.argv[2]); lo, hi = sys.argv[3].split(":")
    for kv in (sys.argv[4] if len(sys.argv) > 4 else "").split(","):
        if "=" in kv:
            k, v = kv.split("="); p[k] = float(v)
    seeds = list(range(int(lo), int(hi)))
    with mp.Pool(3) as pool:
        res = pool.map(run, [(p, ctl, s, 10.0) for s in seeds])
    g = [r for r in res if r["goal"]]
    print(f"goals {len(g)}/{len(res)}", [r["seed"] for r in g], "touched", sum(1 for r in res if r["touch"]), "mean ball", round(float(np.mean([r["ball"] or 0 for r in res])), 2))
    fast = sorted([r for r in res if (r["ball"] or 0) > 6], key=lambda r: -r["ball"])[:10]
    print("fast strikes:", [(r["seed"], round(r["ball"], 1), r["goal"]) for r in fast])
