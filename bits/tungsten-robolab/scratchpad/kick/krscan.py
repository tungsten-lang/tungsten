import glob, os, re, sys, time
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
import kcommon as K
import kreplay as R
import kbatch as B

def main():
    ctl = os.path.abspath(sys.argv[1]); base = K.read_params(sys.argv[2])
    files = []
    for g in ("kbase_n0.05_*", "kbase_n0.1_*"):
        files += sorted(glob.glob(R.CK + "kbase/" + g + ".pkl.gz"))
    files = [f for f in files if int(re.search(r"_s(\d+)\.pkl", f).group(1)) < 5048]
    good = []
    for f in files:
        r = R.load(f)["row"]; cy = r["cross_y"]
        if (r["ball_speed"] or 0) > 8.5 and cy is not None and 0.5 < abs(cy) < 3.2: good.append(f)
    for st in sys.argv[3:]:
        p = dict(base)
        for kv in st.split(","):
            if "=" in kv:
                k, v = kv.split("="); p[k.strip()] = float(v)
        t0 = time.time()
        rows = B.run(good, p, ctl, 2, 2, kind="touch")
        B.summarize(rows, f"{st:50s} ({time.time()-t0:.0f}s)")

if __name__ == "__main__":
    main()
