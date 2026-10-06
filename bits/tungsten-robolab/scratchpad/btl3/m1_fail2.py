"""Failure anatomy of a stage's pass (stage index 2 = the right return): by what the ball does after the release."""
import sys, json, glob, collections
import numpy as np
sys.path.insert(0, "scratchpad/btl3")
import m1_analyze as A
d = sys.argv[1]; stage = int(sys.argv[2]); recv = sys.argv[3] if len(sys.argv) > 3 else "l"
C = collections.Counter()
rows = []
for fn in sorted(glob.glob(d + "/live_*.npz")):
    z = np.load(fn)
    ws = A.stage_windows(z)
    if len(ws) <= stage: continue
    side, k0 = ws[stage]
    rec = A.extract(z, side, k0)
    if rec is None or "rel_v" not in rec: continue
    pl = json.loads(str(z["pass_log"]))
    e = pl[stage] if stage < len(pl) else {}
    ball, ballv = z["ball"], z["ballv"]
    kr = rec["kr"]
    # bounces after release
    nb = 0; kb1 = None; kb2 = None
    for k in range(kr + 1, len(ball) - 1):
        if ball[k, 2] < 0.16 and ballv[k, 2] > 0 and ballv[k - 1, 2] <= 0:
            nb += 1
            if nb == 1: kb1 = k
            elif nb == 2: kb2 = k; break
    # first touch by the receiving hand after release
    Fr = z["F_" + recv]
    kt = None
    for k in range(kr + 1, len(Fr)):
        if Fr[k] > 0.3: kt = k; break
    apex = float(ball[kb1:kb1 + 200, 2].max()) if kb1 else None
    a = A.arrival(z, kr)
    if not e.get("gate"): cat = "no gate"
    elif e.get("body"): cat = "body"
    elif kb1 is None: cat = "no bounce"
    elif kt is None or (kb2 is not None and kt > kb2): cat = "no receive before 2nd bounce (apex %s)" % ("<0.58" if (apex or 0) < 0.58 else ">=0.58")
    elif e.get("outcome") != "ok": cat = "touched by wrong hand/other"
    elif not e.get("ok"): cat = "received, then lost (continuation failed)"
    else: cat = "ok"
    C[cat] += 1
    rows.append((cat, a[0] if a else None))
n = sum(C.values())
print(f"stage {stage}: n {n}")
for k, v in C.most_common(): print(f"  {v:3d} ({100*v/n:.0f}%) {k}")
# arrival of the 'no receive' ones
for cat in C:
    if cat.startswith("no receive"):
        arr = np.array([r[1] for r in rows if r[0] == cat and r[1] is not None])
        if len(arr): print(cat, "arrival mean", np.round(arr.mean(0), 3), "sd", np.round(arr.std(0), 3), "n", len(arr))
