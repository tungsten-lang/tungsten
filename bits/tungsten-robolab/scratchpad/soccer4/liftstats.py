"""Per-seed state at the lift (first b_lift chunk) and outcome. liftstats.py params ctl seeds_lo:hi seconds [set]"""
import os, sys, math, json, multiprocessing as mp
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
from search4 import read_params

def run(job):
    params, seed, ctl, secs = job
    os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
    from myo_bridge import MyoSim
    from tasks.myo_soccer import MyoSoccerTask
    snap = {}
    class T(MyoSoccerTask):
        def on_step(self, sim, obs, reward, info):
            super().on_step(sim, obs, reward, info)
            m, d = sim.m, sim.d
            lab = sim.label.split(":")[-1] if sim.label else ""
            def st():
                pel = d.xmat[m.body("pelvis").id].reshape(3, 3)
                out = {"t": round(float(d.time), 2), "yaw": round(math.atan2(pel[1, 0], pel[0, 0]), 3)}
                ct = sim.foot_contacts()
                for sd in "lr":
                    R = d.xmat[m.body("calcn_" + sd).id].reshape(3, 3)
                    out["fy" + sd] = round(math.atan2(R[1, 0], R[0, 0]), 3)
                    out["ld" + sd] = round(ct[sd], 2)
                    for j in ("hip_rotation_", "hip_flexion_", "hip_adduction_"):
                        out[j[:-1] + sd] = round(float(d.qpos[m.jnt_qposadr[m.joint(j + sd).id]]), 3)
                com = d.subtree_com[m.body("root").id]
                v = d.subtree_linvel[m.body("root").id] if hasattr(d, "subtree_linvel") else [0, 0, 0]
                fcl = 0.5 * (d.xpos[m.body("calcn_l").id] + d.xpos[m.body("toes_l").id])
                out["comy"] = round(float(com[1] - fcl[1]), 3)
                out["comx"] = round(float(com[0] - fcl[0]), 3)
                return out
            if "b_lift" in lab and "lift" not in snap:
                snap["lift"] = st()
            if "b_hold" in lab and "hold" not in snap:
                snap["hold"] = st()
            if abs(float(d.time) - 0.3) < 0.005:
                snap["t03"] = st()
    try:
        r = MyoSim(T(), params=params, controller=ctl, seed=seed).run(secs)
        return seed, {k: r.get(k) for k in ("bal1_s", "stand_time", "fallen", "time")}, snap
    except Exception as e:
        return seed, {"error": str(e)[:200]}, snap

if __name__ == "__main__":
    p = read_params(sys.argv[1])
    for kv in (sys.argv[5] if len(sys.argv) > 5 else "").split(","):
        if "=" in kv:
            k, v = kv.split("="); p[k] = float(v)
    lo, hi = sys.argv[3].split(":")
    jobs = [(p, s, os.path.abspath(sys.argv[2]), float(sys.argv[4])) for s in range(int(lo), int(hi))]
    with mp.Pool(4) as pool:
        res = pool.map(run, jobs)
    json.dump(res, open(os.environ.get("OUT", "/tmp/liftstats.json"), "w"))
    for seed, r, snap in res:
        ok = r.get("bal1_s", 0) > 4
        L = snap.get("lift", {}); H = snap.get("t03", {})
        print(seed, "OK " if ok else "BAD", r.get("bal1_s"), r.get("stand_time"), "| t0.3", {k: H.get(k) for k in ("yaw", "fyl", "fyr", "hip_rotationl", "hip_rotationr", "ldl", "ldr")}, "| lift", {k: L.get(k) for k in ("t", "yaw", "fyl", "hip_rotationl", "hip_flexionl", "comy", "comx")})
