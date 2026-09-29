"""One-at-a-time scan of parameter settings on replays of a dump set. kscan.py --dir kbase --glob 'kbase_n0.05_*' --glob 'kbase_n0.1_*' --seeds 5000:5024 --ctl C --params P 'kc_rk=200' 'kc_rk=-200' ..."""
import argparse, glob, os, re, sys, time
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
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
    ap.add_argument("--workers", type=int, default=2)
    ap.add_argument("settings", nargs="+")
    a = ap.parse_args()
    files = []
    for g in a.glob:
        files += sorted(glob.glob(R.CK + a.dir + "/" + g + ".pkl.gz"))
    if a.seeds:
        lo, hi = [int(v) for v in a.seeds.split(":")]
        files = [f for f in files if lo <= int(re.search(r"_s(\d+)\.pkl", f).group(1)) < hi]
    ctl = os.path.abspath(a.ctl)
    base = K.read_params(a.params)
    for st in a.settings:
        p = dict(base)
        for kv in st.split(","):
            if "=" in kv:
                k, v = kv.split("=")
                p[k.strip()] = float(v)
        t0 = time.time()
        rows = B.run(files, p, ctl, 2, a.workers)
        B.summarize(rows, f"{st:44s} ({time.time()-t0:.0f}s)")


if __name__ == "__main__":
    main()
