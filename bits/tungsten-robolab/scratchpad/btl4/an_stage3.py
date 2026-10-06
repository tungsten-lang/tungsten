"""Left second stroke (stage 3, A4's reflex x_* chunks) timing anatomy from rec_live traces (round 4).

    .venv/bin/python scratchpad/btl4/an_stage3.py out/btl4/live_base [side=l]

Per start: the left track's chunk times of the stroke after the stage-1 table (x_recover start, x_wait start/end, x_swing start, x_carry start = touch),
the handoff time (the right hand's release), and pass 4's outcome (ok, apex of the rise).
"""
import glob
import json
import sys

import numpy as np

sys.path.insert(0, "scratchpad/btl3")
import m1_analyze as A  # noqa: E402

d = sys.argv[1]
rows = []
for fn in sorted(glob.glob(d + "/live_*.npz")):
    z = np.load(fn)
    seed = int(fn.split("_")[-1].split(".")[0])
    t = z["t"]
    r, l = A.parse_states(z["label"])
    pl = json.loads(str(z["pass_log"]))
    ws = A.stage_windows(z)
    if len(ws) < 3 or len(pl) < 4:
        continue
    k_right_g = ws[2][1]                      # right return trigger
    # left chunk starts after the stage-1 g_run ended
    k_l1 = ws[1][1]
    seq = []
    prev = None
    for k in range(k_l1, len(l)):
        if l[k] != prev:
            seq.append((k, l[k]))
            prev = l[k]
    def first(name, after=0):
        for k, n in seq:
            if n == name and k >= after:
                return k
        return None
    krec = first("x_recover", k_l1 + 5)
    kwait = first("x_wait", krec or 0)
    kswing = first("x_swing", krec or 0)
    kcarry = first("x_carry", krec or 0)
    kidle1 = first("idle", k_l1 + 5)
    if None in (krec, kwait, kswing, kcarry):
        continue
    e = pl[3]
    rows.append({"seed": seed, "t_rec_start": float(t[krec]), "wait_dur": (kswing - kwait) * 0.005, "swing_dur": (kcarry - kswing) * 0.005, "rec_dur": (kwait - krec) * 0.005,
                 "idle_dur": (krec - kidle1) * 0.005 if kidle1 else None, "ok": bool(e["ok"]), "apex": e.get("rise_apex"), "gate": bool(e["gate"]), "outcome": e["outcome"], "body": e["body"],
                 "t_right_trig": float(t[k_right_g]), "dt_trig_to_rec": float(t[krec] - t[k_right_g])})
n = len(rows)
print("n", n)
sd = np.array([r["swing_dur"] for r in rows]) * 1000
wd = np.array([r["wait_dur"] for r in rows]) * 1000
ok = np.array([r["ok"] for r in rows])
ap = np.array([r["apex"] if r["apex"] else 0.3 for r in rows])
print("swing duration ms (x_swing -> touch): mean %.0f sd %.0f  min %.0f max %.0f" % (sd.mean(), sd.std(), sd.min(), sd.max()))
print("wait duration ms: mean %.0f sd %.0f; fraction with wait <= 10 ms: %.2f" % (wd.mean(), wd.std(), (wd <= 10).mean()))
print("rec duration ms:", np.mean([r["rec_dur"] for r in rows]) * 1000)
print("dt(right trigger -> left x_recover start) ms: mean %.0f sd %.0f" % (np.mean([r["dt_trig_to_rec"] for r in rows]) * 1000, np.std([r["dt_trig_to_rec"] for r in rows]) * 1000))
for lo, hi in ((0, 60), (60, 90), (90, 120), (120, 160), (160, 400)):
    sel = (sd >= lo) & (sd < hi)
    if sel.sum():
        print(f"swing {lo:3d}-{hi:3d} ms: n {sel.sum():3d}  pass4 ok {ok[sel].sum():2d} ({100 * ok[sel].mean():.0f} %)  mean apex {ap[sel].mean():.2f}  gate {np.mean([r['gate'] for r, s in zip(rows, sel) if s]):.2f}")
print("corr(swing dur, apex) %.2f  corr(swing dur, ok) %.2f" % (np.corrcoef(sd, ap)[0, 1], np.corrcoef(sd, ok.astype(float))[0, 1]))
for lo, hi in ((0, 10), (10, 40), (40, 100), (100, 1000)):
    sel = (wd >= lo) & (wd < hi)
    if sel.sum():
        print(f"wait {lo:3d}-{hi:4d} ms: n {sel.sum():3d}  pass4 ok {ok[sel].sum():2d} ({100 * ok[sel].mean():.0f} %)  mean swing {sd[sel].mean():.0f} ms  mean apex {ap[sel].mean():.2f}")
