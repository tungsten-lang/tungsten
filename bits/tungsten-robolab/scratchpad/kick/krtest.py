import glob, os, re, sys
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
import kcommon as K
import kreplay as R
import kbatch as B

def main():
    ctl_a = os.path.abspath(sys.argv[1]); par_a = K.read_params(sys.argv[2])
    dirn = sys.argv[3]
    files = []
    for g in ("p1base_n0.05_*", "p1base_n0.1_*") if dirn == "p1base" else ("kbase_n0.05_*", "kbase_n0.1_*"):
        files += sorted(glob.glob(R.CK + dirn + "/" + g + ".pkl.gz"))
    files = [f for f in files if int(re.search(r"_s(\d+)\.pkl", f).group(1)) < 5048]
    good = []
    for f in files:
        r = R.load(f)["row"]; cy = r["cross_y"]
        if (r["ball_speed"] or 0) > 8.5 and cy is not None and 0.5 < abs(cy) < 3.2: good.append(f)
    print(len(good), "good-contact packs", flush=True)
    rows = B.run(good, par_a, ctl_a, 2, 2, kind="touch")
    B.summarize(rows, sys.argv[1].split("/")[-1] + " " + sys.argv[2].split("/")[-1])

if __name__ == "__main__":
    main()
