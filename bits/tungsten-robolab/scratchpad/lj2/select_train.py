"""Gap-stratified training set of captured penultimate-touchdown states, both plant sides: writes scratchpad/lj2/<prefix>_train.txt
(comma list) and <prefix>_val.txt (the rest that have a plant).  usage: select_train.py <prefix> [n_train=32] [gap_max=2.05] [n_right=6]"""
import json
import os
import sys

os.environ.setdefault("MUJOCO_GL", "cgl")
ROOT = "/Users/erik/tungsten/bits/tungsten-robolab"
sys.path.insert(0, ROOT + "/playground")
import long_jump_limits as L  # noqa: E402
import long_jump_mine as M  # noqa: E402


def main():
    X = sys.argv[1]
    n_train = int(sys.argv[2]) if len(sys.argv) > 2 else 32
    gap_max = float(sys.argv[3]) if len(sys.argv) > 3 else 2.05
    n_right = int(sys.argv[4]) if len(sys.argv) > 4 else 6
    d = ROOT + "/out/long_jump_limits"
    names = sorted(f[:-len("_capture.npz")] for f in os.listdir(d) if f.startswith(X + "_s") and f.endswith("_capture.npz"))
    c0 = L.load_capture(names[0])
    body = L.Body(c0["task"], c0["board_x"], json.loads(c0["env"]))
    rows = []
    for nm in names:
        c = L.load_capture(nm)
        f = M.features(body, c)
        rows.append((f["gap"], nm, str(c["plant"])))
    rows.sort()
    ok = [r for r in rows if r[0] <= gap_max]
    left = [r for r in ok if r[2] == "l"]
    right = [r for r in ok if r[2] != "l"]
    # right-plant starts: evenly spread over the gap range; left-plant: fill the rest evenly
    def spread(lst, k):
        if k >= len(lst):
            return list(lst)
        return [lst[int(round(i * (len(lst) - 1) / max(1, k - 1)))] for i in range(k)]
    pick_r = spread(right, min(n_right, len(right)))
    pick_l = spread(left, n_train - len(pick_r))
    train = sorted(pick_l + pick_r)
    tn = {r[1] for r in train}
    val = [r for r in rows if r[1] not in tn]
    open(ROOT + "/scratchpad/lj2/%s_train.txt" % X, "w").write(",".join(r[1] for r in train) + "\n")
    open(ROOT + "/scratchpad/lj2/%s_val.txt" % X, "w").write(",".join(r[1] for r in val) + "\n")
    print("%s: %d captures (gap %.2f-%.2f, mean %.3f); train %d (plant l %d, r %d, gaps %.2f-%.2f); held-out %d" % (
        X, len(rows), rows[0][0], rows[-1][0], sum(r[0] for r in rows) / len(rows), len(train), len(pick_l), len(pick_r),
        train[0][0], train[-1][0], len(val)))


if __name__ == "__main__":
    main()
