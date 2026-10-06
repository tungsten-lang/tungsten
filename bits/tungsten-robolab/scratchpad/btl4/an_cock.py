"""Left arm joint angles at the palm's highest point during the stage-1 table stroke vs at the reflex swing start of the second stroke (live traces)."""
import glob, sys
import numpy as np
sys.path.insert(0, "scratchpad/btl3")
import m1_analyze as A
JN = ["sh_flex", "sh_abd", "sh_rot", "elbow", "wr_flex", "wr_dev"]
Q1, Q3, Z1, Z3, T1 = [], [], [], [], []
for fn in sorted(glob.glob("out/btl4/live_base/live_*.npz")):
    z = np.load(fn)
    ws = A.stage_windows(z)
    if len(ws) < 3:
        continue
    r, l = A.parse_states(z["label"])
    k1 = ws[1][1]
    rec = A.extract(z, "l", k1)
    if rec is None or "touch" not in rec:
        continue
    kt = k1 + int(round(rec["touch"]["t"] / 0.005))
    pz = z["palm_l"][:, 2]
    kk = k1 + int(np.argmax(pz[k1:kt + 1]))
    Q1.append(z["q_l"][kk][:6]); Z1.append(pz[kk]); T1.append((kk - k1) * 5)
    ks = None; kc = None
    for k in range(ws[2][1], len(l)):
        if l[k] == "x_swing" and ks is None:
            ks = k
        if l[k] == "x_carry" and kc is None:
            kc = k
    if ks is None or kc is None:
        continue
    Q3.append(z["q_l"][ks][:6]); Z3.append(pz[ks])
Q1, Q3 = np.array(Q1), np.array(Q3)
print("stage 1: left palm peak height %.3f +- %.3f at %.0f ms after the trigger; second stroke swing start palm height %.3f +- %.3f" % (np.mean(Z1), np.std(Z1), np.mean(T1), np.mean(Z3), np.std(Z3)))
print("joint     stage-1 peak    swing start (2nd)   difference")
for j, n in enumerate(JN):
    print(f"{n:8s} {Q1[:, j].mean():7.3f}+-{Q1[:, j].std():5.3f}  {np.median(Q3[:, j]):7.3f} (median)   {Q1[:, j].mean() - np.median(Q3[:, j]):+.3f}")
