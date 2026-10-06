import sys, time
import numpy as np
sys.path.insert(0, "scratchpad/btl4")
import rlib
st = int(sys.argv[1]) if len(sys.argv) > 1 else 2
hand = rlib.STAGES[st][0]
seeds = [int(s) for s in sys.argv[2].split(",")] if len(sys.argv) > 2 else [13001, 13003, 13004]
names = [f"{jn}_{sg}" for jn in rlib.POSTURE_JOINTS for sg in ("pos", "neg")]
YN = ["vx", "vy", "vz", "bx", "by", "ax", "ay", "apex"]
for sd in seeds:
    d = rlib.StartData(sd, f"out/btl4/rec/rec_{sd}.pkl")
    if st not in d.ks:
        continue
    out, s0 = d.run_stage(st)
    y0, _ = rlib.smooth_outcomes(out, hand)
    print("seed", sd, "base", dict(zip(YN, np.round(y0, 3).tolist())))
    rows = []
    for m in range(16):
        for k in range(rlib.NDT):
            res = {}
            for dl in (-0.04, -0.02, -0.01, 0.01, 0.02, 0.04):
                tab = np.zeros((16, rlib.NDT)); tab[m, k] = dl
                o, s = d.run_stage(st, tab)
                y, _ = rlib.smooth_outcomes(o, hand)
                res[dl] = None if y is None else y - y0
            rows.append((m, k, res))
    ok = [r for r in rows if all(v is not None for v in r[2].values())]
    print(" usable (m,k):", len(ok), "of", len(rows))
    # linearity: slope(0.01) vs slope(0.02) vs slope(0.04) for vz, by, apex over the 12 biggest effects
    print("  m  k name               | vz: s.01  s.02  s.04 | by: s.01  s.02  s.04 | apex: s.01 s.02 s.04")
    big = sorted(ok, key=lambda r: -abs(r[2][0.02][2] - r[2][-0.02][2]))
    for m, k, res in big[:10]:
        sl = lambda dl, i: (res[dl][i] - res[-dl][i]) / (2 * dl)
        print(f" {m:2d} {k:2d} {names[m]:18s} | {sl(0.01,2):6.2f} {sl(0.02,2):6.2f} {sl(0.04,2):6.2f} | {sl(0.01,4):6.2f} {sl(0.02,4):6.2f} {sl(0.04,4):6.2f} | {sl(0.01,7):6.2f} {sl(0.02,7):6.2f} {sl(0.04,7):6.2f}")
    # overall: the ratio of the +0.02 and -0.02 responses (symmetry) over all usable
    a = np.array([[r[2][0.02][2], -r[2][-0.02][2]] for r in ok])
    print("  symmetry of the vz response (+0.02 vs -(-0.02)): corr", round(float(np.corrcoef(a[:, 0], a[:, 1])[0, 1]), 3), " rms", round(float(np.sqrt((a ** 2).mean())), 4))
    b1 = np.array([[(r[2][0.01][2] - r[2][-0.01][2]) / 0.02, (r[2][0.04][2] - r[2][-0.04][2]) / 0.08] for r in ok])
    print("  slope(0.01) vs slope(0.04) vz: corr", round(float(np.corrcoef(b1[:, 0], b1[:, 1])[0, 1]), 3), " rms", round(float(np.sqrt((b1 ** 2).mean(0))[0]), 3), round(float(np.sqrt((b1 ** 2).mean(0))[1]), 3))
