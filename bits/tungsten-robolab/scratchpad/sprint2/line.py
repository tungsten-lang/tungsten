"""line: a line search along (B - A) in the g5 twins of two practice files (A + t (B - A), clipped to the ES boxes), flying-start lab.
  ROBOLAB_SNAP=run_v4_p95j .venv/bin/python scratchpad/sprint2/line.py A B --ts 1.0,1.5,2.0 [--seeds ...] [--out prefix]"""
import argparse, multiprocessing as mp, os, sys
HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(os.path.dirname(HERE))
sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(ROOT, "playground"))
import numpy as np
import lab
from practice import read_params
from search import describe

BOX = "g5_z_ref=0.6:1.0,g5_k_land=-0.2:0.9,g5_t_push_max=0.03:0.3,g5_a_push=0.2:1.3,g5_k_late=0.3:3.0,g5_g_kl=0.1:2.5,g5_hip_lead=0:0.3,g5_vz_push=-0.8:0.4,g5_k_fly=0:3,g5_elbow=0.3:3.0,g5_psi_to=-1.0:0.2,g5_k_push=0:0.8,g5_psi_reach=-0.3:0.9,g5_k_reach=0:0.9,g5_t_land=0.002:0.25"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("a"); ap.add_argument("b"); ap.add_argument("--ts", default="1.0,1.5,2.0"); ap.add_argument("--seeds", default="15,13,2,0,1,3,5,6")
    ap.add_argument("--seconds", type=float, default=12.0); ap.add_argument("--workers", type=int, default=2); ap.add_argument("--out")
    ap.add_argument("--controller", default=os.path.join(ROOT, "bin", "challengers", "run_gear-v4c"))
    a = ap.parse_args()
    A, B = read_params(a.a), read_params(a.b)
    os.environ.setdefault("ROBOLAB_CONTROLLER", a.controller)
    tun = describe("sprint_touch_v4x", B)
    lim = {t[0]: (t[2], t[3]) for t in tun}
    for kv in BOX.split(","):
        k, v = kv.split("="); lim[k] = tuple(float(x) for x in v.split(":"))
    seeds = [int(s) for s in a.seeds.split(",")]
    ts = [float(x) for x in a.ts.split(",")]
    attrs = {"objective": 3.0, "fly_touch": 2.0, "fall_pen": 300.0}
    jobs, files = [], []
    for t in ts:
        p = dict(B)
        for k in B:
            if not k.startswith("g5_") or k not in A:
                continue
            if k in ("g5_drv_hip", "g5_drv_swh") or k not in lim:
                continue
            v = A[k] + t * (B[k] - A[k])
            lo, hi = lim[k]
            p[k] = min(hi, max(lo, v))
        if a.out:
            with open(f"{a.out}_t{t}.txt", "w") as f:
                for k in sorted(p):
                    f.write(f"{k} {p[k]}\n")
        for s in seeds:
            jobs.append(("sprint_touch_v4x", p, s, a.seconds, "flying", attrs, a.controller, None, None, 0.5, False))
    with mp.Pool(a.workers) as pool:
        res = pool.map(lab.run_one, jobs, chunksize=1)
    k = len(seeds)
    print("t      falls  peak   steady | tc flight step th_td th_lo kn_td kn_max fz_mean fz_peak rock")
    for i, t in enumerate(ts):
        rr = res[i * k:(i + 1) * k]
        ok = [r for r in rr if "error" not in r and not r["fell"]]
        if ok:
            cols = ["tc", "flight", "step", "th_td", "th_lo", "kn_td", "kn_max", "fz_mean", "fz_peak", "pitch_rock"]
            print(f"{t:<6.2f} {k - len(ok)}/{k}  {np.mean([r['peak'] for r in ok]):6.3f} {np.mean([r['steady'] for r in ok]):6.3f} | " + " ".join(f"{np.nanmean([r.get(c, np.nan) for r in ok]):.3f}" for c in cols))
        else:
            print(f"{t:<6.2f} {k}/{k}")

if __name__ == "__main__":
    main()
