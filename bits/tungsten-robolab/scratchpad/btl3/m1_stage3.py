"""The left hand's SECOND stroke (A4's reflex x_swing after the right return) in the champion's traces: timing and release velocity vs the programmed left return."""
import sys, json, glob
import numpy as np
sys.path.insert(0, "scratchpad/btl3")
import m1_analyze as A
d = sys.argv[1]
rows = []
for fn in sorted(glob.glob(d + "/live_*.npz")):
    z = np.load(fn)
    ws = A.stage_windows(z)
    if len(ws) < 3: continue
    r, l = A.parse_states(z["label"])
    k2 = ws[2][1]
    # first left touch after stage 2's trigger
    F = z["F_l"]
    kt, kr = A.touch_release(F, k2 + 20)
    if kt is None or kr is None: continue
    # left x_swing onset before the touch
    sw = [k for k in range(k2, kt) if l[k] == "x_swing" and l[k - 1] != "x_swing"]
    ks = sw[-1] if sw else None
    pl = json.loads(str(z["pass_log"]))
    rows.append((int(fn.split("_")[-1].split(".")[0]), kt, kr, ks, z["ballv"][min(kr + 1, len(z["ballv"]) - 1)], z["ball"][kt], z["palm_l"][kt] - z["ball"][kt], z["pv_l"][kt], z["q_l"][ks if ks else kt], l[kt]))
print(len(rows), "starts with a left touch after the right return")
RV = np.array([r[4] for r in rows]); print("release v mean", np.round(RV.mean(0), 2), "sd", np.round(RV.std(0), 2), "| stage 1 (programmed) mean (1.44, -1.74, -3.36)")
dur = np.array([(r[2] - r[1]) * 5 for r in rows]); print("contact ms", dur.mean(), dur.std())
Q = np.array([r[8] for r in rows]); print("left arm q at swing start mean", np.round(Q.mean(0), 2), "sd", np.round(Q.std(0), 2))
print("ball z at touch", np.round(np.mean([r[5][2] for r in rows]), 3), "palm-ball off at touch", np.round(np.mean([r[6] for r in rows], 0), 3), "palm v", np.round(np.mean([r[7] for r in rows], 0), 2))
