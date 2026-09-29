"""Oracle headroom: per pack, is there ANY variant (random perturbations of some swing parameters) that gives a good kick? (replays from the swing start)"""
import argparse, glob, os, re, sys, time
import numpy as np
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/soccer4")
import kcommon as K
import kreplay as R
import kbatch as B


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="kbase")
    ap.add_argument("--glob", action="append", required=True)
    ap.add_argument("--seeds", default="")
    ap.add_argument("--ctl", required=True)
    ap.add_argument("--params", required=True)
    ap.add_argument("--only", required=True)
    ap.add_argument("--k", type=int, default=24)
    ap.add_argument("--s", type=float, default=0.1)
    ap.add_argument("--seed", type=int, default=1)
    a = ap.parse_args()
    from search4 import describe
    files = []
    for g in a.glob:
        files += sorted(glob.glob(R.CK + a.dir + "/" + g + ".pkl.gz"))
    if a.seeds:
        lo, hi = [int(v) for v in a.seeds.split(":")]
        files = [f for f in files if lo <= int(re.search(r"_s(\d+)\.pkl", f).group(1)) < hi]
    ctl = os.path.abspath(a.ctl)
    base = K.read_params(a.params)
    tun = {t[0]: t for t in describe(base, "myoChallengeSoccerP2-v0", ctl)}
    names = a.only.split(",")
    rng = np.random.default_rng(a.seed)
    variants = [dict(base)]
    for _ in range(a.k):
        p = dict(base)
        for n in names:
            lo, hi = tun[n][2], tun[n][3]
            p[n] = float(np.clip(base.get(n, tun[n][1]) + a.s * (hi - lo) * rng.uniform(-1, 1), lo, hi))
        variants.append(p)
    res = np.zeros((len(variants), len(files)))
    oks = np.zeros((len(variants), len(files)), bool)
    t0 = time.time()
    for i, p in enumerate(variants):
        rows = B.run(files, p, ctl, 2, 2)
        res[i] = [r["score"] for r in rows]
        oks[i] = [r["ok"] for r in rows]
        print(f"variant {i:2d}: ok {oks[i].sum()}/{len(files)} score {res[i].mean():.2f}  ({time.time()-t0:.0f}s)", flush=True)
    print(f"baseline: ok {oks[0].sum()}/{len(files)}; best-of-{len(variants)-1} per pack: ok in {oks[1:].any(0).sum()}/{len(files)} packs; mean best score {res[1:].max(0).mean():.2f} vs baseline {res[0].mean():.2f}; best single variant ok {oks[1:].sum(1).max()}")


if __name__ == "__main__":
    main()
