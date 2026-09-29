import glob, os, re, sys
sys.path.insert(0, "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/kick")
import kcommon as K
import kreplay as R
import kbatch as B

def main():
    ctl = os.path.abspath(sys.argv[1])
    lo, hi = [int(v) for v in sys.argv[2].split(":")]
    files = []
    for g in ("kbase_n0.05_*", "kbase_n0.1_*"):
        files += sorted(glob.glob(R.CK + "kbase/" + g + ".pkl.gz"))
    files = [f for f in files if lo <= int(re.search(r"_s(\d+)\.pkl", f).group(1)) < hi]
    good = []
    for f in files:
        r = R.load(f)["row"]; cy = r["cross_y"]
        if (r["ball_speed"] or 0) > 8.5 and cy is not None and 0.5 < abs(cy) < 3.2: good.append(f)
    print(len(files), "packs,", len(good), "with a good contact", flush=True)
    res = {}
    for label, pf in (("champion follow-through", "params/myo_kick_base.txt"), ("kr (routine's stance terms after the touch)", "params/myo_kick_kr0.txt")):
        rows = B.run(good, K.read_params(pf), ctl, 2, 2, kind="touch")
        res[label] = rows
        B.summarize(rows, label)
    a, b = res["champion follow-through"], res["kr (routine's stance terms after the touch)"]
    fixed = sum(1 for x, y in zip(a, b) if y["ok"] and not x["ok"]); broke = sum(1 for x, y in zip(a, b) if x["ok"] and not y["ok"])
    print("paired: kr fixed", fixed, "broke", broke)

if __name__ == "__main__":
    main()
