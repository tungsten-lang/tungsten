"""Per-seed outcome (hold >= T-4 s standing) plus dense early-phase features, for finding what predicts a failing attempt.
usage: featscan.py <params> <controller> <a:b> <T> [workers] [k=v,...]   -> scan/feat_<a>.json"""
import math, os, sys, json, multiprocessing as mp
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/playground")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
from search4 import read_params

def run(job):
    params, seed, ctl, T = job
    os.environ["MYO_SOCCER_ENV"] = "myoChallengeSoccerP2-v0"
    os.environ["MYO_SOCCER_MAX_TIME"] = "310"
    import mujoco
    from myo_bridge import MyoSim
    from tasks.myo_soccer import MyoSoccerTask
    rows = []
    class Tk(MyoSoccerTask):
        def on_step(self, sim, obs, reward, info):
            super().on_step(sim, obs, reward, info)
            k = round(float(sim.d.time) * 100)
            if k % 5:
                return
            m, d = sim.m, sim.d
            pel = d.xmat[m.body("pelvis").id].reshape(3, 3)
            tor = d.xmat[m.body("torso").id].reshape(3, 3)
            com = d.subtree_com[m.body("root").id]
            ct = sim.foot_contacts()
            fy = {}
            fc = {}
            for sd in "lr":
                R = d.xmat[m.body("calcn_" + sd).id].reshape(3, 3)
                fy[sd] = math.atan2(R[1, 0], R[0, 0])
                fc[sd] = 0.5 * (d.xpos[m.body("calcn_" + sd).id] + d.xpos[m.body("toes_" + sd).id])
            lab = sim.label.split(":")[-1] if sim.label else ""
            mujoco.mj_subtreeVel(m, d)
            v = d.subtree_linvel[m.body("root").id]
            hh = fy["l"]
            dxx = com[0] + v[0] * 0.311 - fc["l"][0]
            dyy = com[1] + v[1] * 0.311 - fc["l"][1]
            cpo = dyy * math.cos(hh) - dxx * math.sin(hh)
            rows.append((float(d.time), lab, float(pel[2, 2]), math.atan2(pel[1, 0], pel[0, 0]), float(math.atan2(tor[0, 1], tor[2, 1])),
                         float(ct["l"]), float(ct["r"]), fy["l"], fy["r"], float(com[0] - fc["l"][0]), float(com[1] - fc["l"][1]),
                         float(math.atan2(pel[0, 1], pel[2, 1])), float(cpo)))
    try:
        r = MyoSim(Tk(), params=params, controller=ctl, seed=seed).run(T)
    except Exception as e:
        return {"seed": seed, "error": str(e)[:100]}
    Aall = np.array([[x[0]] + list(x[2:]) for x in rows])
    labs_all = [x[1] for x in rows]
    A = Aall[Aall[:, 0] <= 3.0]
    labs = [x[1] for x in rows]
    out = {"seed": seed, "bal1_s": r.get("bal1_s"), "stand_time": r.get("stand_time"), "fallen": bool(r.get("fallen"))}
    t = A[:, 0]
    def win(a, b): return (t >= a) & (t <= b)
    w = win(0.2, 2.0)
    out["roll_max"] = float(np.abs(A[w, 1]).max()) if w.any() else 0.0
    out["roll_std_set"] = float(np.std(A[win(0.3, 0.8), 1])) if win(0.3, 0.8).any() else 0.0
    out["ld_osc"] = float(np.std(A[win(0.3, 0.8), 4] - A[win(0.3, 0.8), 5])) if win(0.3, 0.8).any() else 0.0
    out["ld_osc2"] = float(np.std(A[win(0.8, 1.6), 4] - A[win(0.8, 1.6), 5])) if win(0.8, 1.6).any() else 0.0
    out["fy_drift"] = float(abs(A[win(1.8, 2.0), 6].mean() - A[win(0.2, 0.4), 6].mean()) + abs(A[win(1.8, 2.0), 7].mean() - A[win(0.2, 0.4), 7].mean())) if win(1.8, 2.0).any() else 0.0
    out["fy_abs_max"] = float(max(np.abs(A[w, 6]).max(), np.abs(A[w, 7]).max())) if w.any() else 0.0
    out["yaw_max"] = float(np.abs(A[w, 2]).max()) if w.any() else 0.0
    out["pitch_range"] = float(np.ptp(A[win(0.5, 2.0), 3])) if win(0.5, 2.0).any() else 0.0
    out["comf_end"] = float(A[win(1.0, 1.4), 8].mean() - A[win(0.4, 0.8), 8].mean()) if win(1.0, 1.4).any() else 0.0
    out["ppitch_drift"] = float(A[win(1.0, 1.4), 10].mean() - A[win(0.4, 0.8), 10].mean()) if win(1.0, 1.4).any() else 0.0
    # whole-run and hold-phase stability indicators (t_lift = first b_lift label)
    tl = next((x[0] for x in rows if x[1].startswith("b_lift")), None)
    tt = Aall[:, 0]
    out["t_lift"] = tl
    out["roll_max_all"] = float(np.abs(Aall[tt >= 0.2, 1]).max()) if (tt >= 0.2).any() else 0.0
    if tl is not None:
        wh = tt >= tl + 0.5
        if wh.any():
            out["roll_max_hold"] = float(np.abs(Aall[wh, 1]).max())
            out["roll_std_hold"] = float(np.std(Aall[wh, 1]))
            out["cpo_max_hold"] = float(Aall[wh, 11].max())
            out["cpo_min_hold"] = float(Aall[wh, 11].min())
            out["yaw_rng_hold"] = float(np.ptp(Aall[wh, 2]))
            out["tp_max_hold"] = float(np.abs(Aall[wh, 3]).max())
    out["min_ld"] = float(min(A[win(0.3, 1.0), 4].min(), A[win(0.3, 1.0), 5].min())) if win(0.3, 1.0).any() else 0.0
    return out

if __name__ == "__main__":
    p = read_params(sys.argv[1]); ctl = os.path.abspath(sys.argv[2]); lo, hi = sys.argv[3].split(":"); T = float(sys.argv[4])
    workers = int(sys.argv[5]) if len(sys.argv) > 5 else 3
    for kv in (sys.argv[6] if len(sys.argv) > 6 else "").split(","):
        if "=" in kv:
            a, b = kv.split("="); p[a.strip()] = float(b)
    seeds = list(range(int(lo), int(hi)))
    with mp.Pool(workers) as pool:
        res = pool.map(run, [(p, s, ctl, T) for s in seeds])
    out = os.environ.get("OUT", f"/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4/scan/featB_{lo}.json")
    json.dump(res, open(out, "w"))
    ok = [r for r in res if "error" not in r and (r["bal1_s"] or 0) >= T - 4 and not r["fallen"]]
    print(f"{len(ok)}/{len(res)} hold to {T:.0f} s ->", out)
