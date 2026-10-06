"""Left arm posture at the stage-1 trigger, at the stage-3 trigger (the ball's predicted crossing 0.165 s away after the right return's bounce),
at the end of x_recover and at the touch, from rec_live traces. Joint angles q_l (POSTURE_JOINTS order).

    .venv/bin/python scratchpad/btl4/an_posture3.py out/btl4/live_base
"""
import glob
import json
import sys

import numpy as np

sys.path.insert(0, "scratchpad/btl3")
import dlib  # noqa: E402
import m1_analyze as A  # noqa: E402

JN = ["sh_flex", "sh_abd", "sh_rot", "elbow", "wr_flex", "wr_dev", "f_mcp", "f_pip"]
d = sys.argv[1]
P1, P3, PE, PT = [], [], [], []
for fn in sorted(glob.glob(d + "/live_*.npz")):
    z = np.load(fn)
    ws = A.stage_windows(z)
    if len(ws) < 3:
        continue
    r, l = A.parse_states(z["label"])
    q = z["q_l"]
    qd = z["qd_l"]
    k1 = ws[1][1]
    rec2 = A.extract(z, "r", ws[2][1])
    if rec2 is None or "rel_v" not in rec2:
        continue
    nx = dlib.next_input(z, rec2["kr"])
    if nx is None:
        continue
    k3 = nx["k"]
    # end of x_recover (first x_wait or x_swing after k3 - 40)
    ke = kt = None
    for k in range(ws[2][1], len(l)):
        if l[k] in ("x_wait", "x_swing") and ke is None:
            ke = k
        if l[k] == "x_carry" and kt is None:
            kt = k
    if ke is None or kt is None:
        continue
    P1.append(q[k1 - 1]); P3.append(q[k3 - 1]); PE.append(q[ke]); PT.append(q[kt])
P1, P3, PE, PT = map(np.array, (P1, P3, PE, PT))
print("n", len(P1))
print(f"{'joint':8s} {'stage1 trig':>16s} {'stage3 trig':>16s} {'x_recover end':>16s} {'touch':>16s}")
for j, nme in enumerate(JN):
    print(f"{nme:8s} {P1[:, j].mean():7.3f}+-{P1[:, j].std():5.3f} {P3[:, j].mean():7.3f}+-{P3[:, j].std():5.3f} {PE[:, j].mean():7.3f}+-{PE[:, j].std():5.3f} {PT[:, j].mean():7.3f}+-{PT[:, j].std():5.3f}")

# distribution of wrist flexion at the stage-3 trigger and pass-4 outcome
import collections
ok4 = []
for fn in sorted(glob.glob(d + "/live_*.npz")):
    z = np.load(fn)
    ws = A.stage_windows(z)
    if len(ws) < 3:
        continue
    rec2 = A.extract(z, "r", ws[2][1])
    if rec2 is None or "rel_v" not in rec2:
        continue
    nx = dlib.next_input(z, rec2["kr"])
    if nx is None:
        continue
    r, l = A.parse_states(z["label"])
    ke = kt = None
    for k in range(ws[2][1], len(l)):
        if l[k] in ("x_wait", "x_swing") and ke is None:
            ke = k
        if l[k] == "x_carry" and kt is None:
            kt = k
    if ke is None or kt is None:
        continue
    pl = json.loads(str(z["pass_log"]))
    ok4.append(bool(pl[3]["ok"]) if len(pl) > 3 else False)
ok4 = np.array(ok4)
w = P3[:, 4]
print("wrist flexion at the stage-3 trigger: quantiles", np.round(np.quantile(w, [0, .1, .25, .5, .75, .9, 1]), 2).tolist())
for lo, hi in ((-2, 0.0), (0.0, 0.4), (0.4, 0.7), (0.7, 0.9), (0.9, 3)):
    s = (w >= lo) & (w < hi)
    print(f"wrist flex {lo:5.1f}..{hi:4.1f}: n {s.sum():3d}  pass4 ok {ok4[s].sum():2d} ({100 * ok4[s].mean() if s.sum() else 0:.0f} %)  shoulder flex mean {P3[s, 0].mean() if s.sum() else 0:.2f} elbow mean {P3[s, 3].mean() if s.sum() else 0:.2f}")
print("corr of the stage-3 trigger posture with the wrist flexion:", {JN[j]: round(float(np.corrcoef(P3[:, j], w)[0, 1]), 2) for j in range(8) if j != 4})
