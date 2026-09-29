"""State at the lift (first b_lift tick) and 0.5 s after the swing foot leaves, per seed, with the scan outcome.
usage: liftfeat.py <params> <controller> <seeds a:b> [workers]  -> writes scan/liftfeat_<a>.json and prints a table"""
import math, os, sys, json, multiprocessing as mp
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
from search4 import read_params

def run(job):
    params, seed, ctl = job
    os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
    os.environ["MYO_SOCCER_MAX_TIME"] = "310"
    import mujoco
    from myo_bridge import MyoSim
    from tasks.myo_soccer import MyoSoccerTask
    snap = {}
    class T(MyoSoccerTask):
        def on_step(self, sim, obs, reward, info):
            super().on_step(sim, obs, reward, info)
            m, d = sim.m, sim.d
            lab = sim.label.split(":")[-1] if sim.label else ""
            t = float(d.time)
            def st():
                pel = d.xmat[m.body("pelvis").id].reshape(3, 3)
                tor = d.xmat[m.body("torso").id].reshape(3, 3)
                com = d.subtree_com[m.body("root").id].copy()
                mujoco.mj_subtreeVel(m, d)
                v = d.subtree_linvel[m.body("root").id].copy()
                out = {"t": round(t, 2), "yaw": float(math.atan2(pel[1, 0], pel[0, 0])), "roll": float(pel[2, 2]),
                       "tpitch": float(math.atan2(tor[0, 1], tor[2, 1])), "pz": float(d.xpos[m.body("pelvis").id][2])}
                ct = sim.foot_contacts()
                out["ld_l"], out["ld_r"] = float(ct["l"]), float(ct["r"])
                fc = {}
                for sd in "lr":
                    c = 0.5 * (d.xpos[m.body("calcn_" + sd).id] + d.xpos[m.body("toes_" + sd).id])
                    R = d.xmat[m.body("calcn_" + sd).id].reshape(3, 3)
                    fc[sd] = c
                    out["fy_" + sd] = float(math.atan2(R[1, 0], R[0, 0]))
                # capture point relative to the left foot centre, in the foot's frame (fwd, outward=+left)
                h = out["fy_l"]
                w = 0.311
                dx = com[0] + v[0] * w - fc["l"][0]
                dy = com[1] + v[1] * w - fc["l"][1]
                out["cpf"] = float(dx * math.cos(h) + dy * math.sin(h))
                out["cpo"] = float(dy * math.cos(h) - dx * math.sin(h))
                out["comf"] = float((com[0] - fc["l"][0]) * math.cos(h) + (com[1] - fc["l"][1]) * math.sin(h))
                out["como"] = float((com[1] - fc["l"][1]) * math.cos(h) - (com[0] - fc["l"][0]) * math.sin(h))
                out["vf"] = float(v[0] * math.cos(h) + v[1] * math.sin(h))
                out["vo"] = float(v[1] * math.cos(h) - v[0] * math.sin(h))
                # feet separation
                out["sep_f"] = float((fc["r"][0] - fc["l"][0]) * math.cos(h) + (fc["r"][1] - fc["l"][1]) * math.sin(h))
                out["sep_o"] = float(-((fc["r"][1] - fc["l"][1]) * math.cos(h) - (fc["r"][0] - fc["l"][0]) * math.sin(h)))
                out["avz"] = float(d.subtree_angmom[m.body("root").id][2]) if hasattr(d, "subtree_angmom") else 0.0
                return out
            if "b_shift" in lab and "shift" not in snap:
                snap["shift"] = st()
            if "b_lift" in lab and "lift" not in snap:
                snap["lift"] = st(); snap["t_lift"] = t
            if "lift" in snap and "post" not in snap and t >= snap["t_lift"] + 0.5:
                snap["post"] = st()
            if "lift" in snap and "post2" not in snap and t >= snap["t_lift"] + 1.5:
                snap["post2"] = st()
    try:
        r = MyoSim(T(), params=params, controller=ctl, seed=seed).run(3.6)
        return seed, {k: r.get(k) for k in ("bal1_s", "stand_time", "fallen")}, snap
    except Exception as e:
        return seed, {"error": str(e)[:200]}, snap

if __name__ == "__main__":
    p = read_params(sys.argv[1]); ctl = os.path.abspath(sys.argv[2]); lo, hi = sys.argv[3].split(":")
    workers = int(sys.argv[4]) if len(sys.argv) > 4 else 3
    seeds = list(range(int(lo), int(hi)))
    with mp.Pool(workers) as pool:
        res = pool.map(run, [(p, s, ctl) for s in seeds])
    out = os.environ.get("OUT", f"/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4/scan/liftfeat_{lo}.json")
    json.dump(res, open(out, "w"))
    for seed, r, snap in res:
        L = snap.get("lift", {}); P = snap.get("post", {})
        if not L: print(seed, "no lift", r); continue
        print(seed, f"t_lift {snap.get('t_lift'):.2f} | lift: cpf {L['cpf']:+.3f} cpo {L['cpo']:+.3f} comf {L['comf']:+.3f} como {L['como']:+.3f} vf {L['vf']:+.2f} vo {L['vo']:+.2f} ldR {L['ld_r']:.2f} roll {L['roll']:+.2f} yaw {L['yaw']:+.2f} sep {L['sep_f']:+.2f}/{L['sep_o']:+.2f} | +0.5: cpo {P.get('cpo', float('nan')):+.3f} cpf {P.get('cpf', float('nan')):+.3f} roll {P.get('roll', float('nan')):+.2f} yaw {P.get('yaw', float('nan')):+.2f}")
