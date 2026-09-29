"""morph: interpolate gear K's stride between a practice file (alpha 0) and another gait's params (alpha 1), flying-start lab.

  ROBOLAB_SNAP=run_v4_p95j [ROBOLAB_TRUNK_STAB=...] .venv/bin/python scratchpad/sprint2/morph.py BASEFILE OTHER --gear 5 --alphas 0,0.2,0.4 [--groups leg|trunk|all] [--seeds 0,1,3,4]
"""
import argparse, multiprocessing as mp, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE)
import numpy as np
import lab
from practice import read_params

LEG = ["psi_reach", "k_reach", "a_reach", "psi_fo", "k_fo", "a_fo", "k_land", "a_land", "psi_ms", "psi_to", "k_push", "a_push", "psi_mid", "k_mid",
       "psi_late", "k_late", "d_push", "vz_push", "t_land", "t_push", "t_push_max", "t_flight", "t_absorb", "pre_knee", "knee_lift", "heel_tuck",
       "toe_land", "toe_push", "toe_fly", "z_ref", "k_z", "drv_swk", "drv_rf", "drv_hamb", "drv_pre", "drv_toe", "retract", "psi_v", "cv"]
TRUNK = ["lean", "spine", "torso_kp", "torso_kd", "hip_lead", "k_swc", "k_fly", "k_fly_d", "comp_fly", "fall_place", "fall_lean", "arm", "elbow"]
GAINS = ["g_st", "g_sw", "g_kl", "g_al", "leg_kp", "leg_kd", "stiff", "stiff_st", "stiff_sw", "stiff_up", "bi_gain", "gait_spring"]

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("base"); ap.add_argument("other")
    ap.add_argument("--gear", type=int, default=5); ap.add_argument("--alphas", default="0,0.25,0.5,0.75,1.0")
    ap.add_argument("--groups", default="leg"); ap.add_argument("--seeds", default="0,1,3,4"); ap.add_argument("--seconds", type=float, default=12.0)
    ap.add_argument("--workers", type=int, default=4); ap.add_argument("--task", default="sprint_touch_v4x")
    ap.add_argument("--controller", default=os.path.join(ROOT, "bin", "challengers", "run_gear-v4c"))
    ap.add_argument("--attrs", default="objective=3,fly_touch=2,fall_pen=300")
    a = ap.parse_args()
    base = read_params(a.base); other = read_params(a.other)
    names = []
    for g in a.groups.split(","):
        names += {"leg": LEG, "trunk": TRUNK, "gains": GAINS, "all": LEG + TRUNK + GAINS}[g]
    def gv(d, name, gear):
        k = gear
        while k >= 2:
            if f"g{k}_{name}" in d: return d[f"g{k}_{name}"]
            k -= 1
        return d.get(name)
    attrs = {kv.split("=")[0]: float(kv.split("=")[1]) for kv in a.attrs.split(",") if kv}
    seeds = [int(s) for s in a.seeds.split(",")]
    alphas = [float(x) for x in a.alphas.split(",")]
    jobs = []
    for al in alphas:
        p = dict(base)
        for n in names:
            b = gv(base, n, a.gear - 1 if a.gear > 1 else 1); o = other.get(n)
            if b is None or o is None: continue
            p[f"g{a.gear}_{n}"] = (1 - al) * b + al * o
        for s in seeds:
            jobs.append((a.task, p, s, a.seconds, "flying", attrs, a.controller, None, None, 0.5, False))
    with mp.Pool(a.workers) as pool:
        res = pool.map(lab.run_one, jobs, chunksize=1)
    cols = ["tc", "flight", "step", "th_td", "th_lo", "kn_td", "kn_max", "fz_mean", "fz_peak", "pitch_rock"]
    print(f"{'alpha':8s} falls  peak   steady tfall | " + " ".join(f"{c:>8s}" for c in cols))
    k = len(seeds)
    for i, al in enumerate(alphas):
        rr = res[i * k:(i + 1) * k]
        ok = [r for r in rr if "error" not in r and not r["fell"]]
        falls = [r for r in rr if r.get("fell") or "error" in r]
        tf = np.mean([r.get("t", 0) for r in falls]) if falls else 0.0
        if ok:
            pk = np.mean([r["peak"] for r in ok]); sd = np.mean([r["steady"] for r in ok])
            row = " ".join(f"{np.nanmean([r.get(c, np.nan) for r in ok]):8.3f}" for c in cols)
        else:
            pk = sd = 0.0; row = ""
        print(f"{al:<8.2f} {len(falls)}/{k}  {pk:6.3f} {sd:6.3f} {tf:5.1f} | {row}")

if __name__ == "__main__":
    main()
