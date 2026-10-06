"""Pass 4 (the left second stroke) outcomes on the 840 training records: gate / body / bounce / arrival by outcome."""
import pickle, sys, collections
import numpy as np
rows = []
for sd in range(13001, 13841):
    rec = pickle.load(open(f"out/btl4/rec/rec_{sd}.pkl", "rb"))
    pl = rec["pass_log"]
    if len(pl) < 4 or not pl[2]["ok"]:
        continue            # pass 3 ok: the left hand really made its second stroke from a received ball
    e = pl[3]
    rows.append(e)
n = len(rows)
print("starts with pass 3 ok:", n, " pass 4 ok:", sum(e["ok"] for e in rows))
cat = collections.Counter()
for e in rows:
    if e["ok"]: c = "ok"
    elif not e["released"]: c = "not released"
    elif not e["gate"]: c = "no gate"
    elif e["body"]: c = "body"
    else: c = "gate ok, then " + str(e["outcome"])
    cat[c] += 1
print(cat.most_common())
for c in ("ok", "no gate", "body"):
    sel = [e for e in rows if (c == "ok" and e["ok"]) or (c == "no gate" and e["released"] and not e["gate"] and not e["ok"]) or (c == "body" and e["body"] and not e["ok"])]
    bx = np.array([e["bounce_xy"] for e in sel if e["bounce_xy"]])
    ar = np.array([e["arrive_xy"] for e in sel if e["arrive_xy"]])
    ap = np.array([e["rise_apex"] for e in sel if e["rise_apex"]])
    gd = np.array([e["bounce_gd"] for e in sel if e["bounce_gd"] is not None])
    print(f"{c:8s} n {len(sel):3d} bounce xy mean {np.round(bx.mean(0),3).tolist() if len(bx) else None} sd {np.round(bx.std(0),3).tolist() if len(bx) else None} | arrival xy {np.round(ar.mean(0),3).tolist() if len(ar) else None} sd {np.round(ar.std(0),3).tolist() if len(ar) else None} | apex {ap.mean():.2f} | bounce-gate-dist {gd.mean() if len(gd) else float('nan'):.3f}")
