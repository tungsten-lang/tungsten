import os, pickle, sys, collections
import numpy as np
D = sys.argv[1] if len(sys.argv) > 1 else "out/btl6/recG"
rows = []
for f in sorted(os.listdir(D)):
    if not f.endswith(".pkl"): continue
    r = pickle.load(open(os.path.join(D, f), "rb"))
    ks = r["ks"]; kb = r["k_base"]
    ev = r["ev"]
    def hand_at(k, kind):
        return [h for (kk, h) in ev.get(k - kb, []) if kk == kind]
    ok2 = 2 in ks and "right" in hand_at(ks[2], "g")
    ok3 = 3 in ks and "left" in hand_at(ks[3], "g")
    ok4 = 4 in ks and "right" in hand_at(ks[4], "g")
    ok = [p["ok"] for p in r["pass_log"]]
    rows.append((r["seed"], r["streak"], ok2, ok3, ok4, ok))
n = len(rows)
st = np.array([r[1] for r in rows], float)
print("starts", n, "mean streak (6 s)", st.mean().round(3), "ge3", (st>=3).sum(), "ge4", (st>=4).sum(), "ge5", (st>=5).sum())
print("stage2 proper", sum(r[2] for r in rows), "stage3 proper", sum(r[3] for r in rows), "stage4 proper", sum(r[4] for r in rows), "all three", sum(r[2] and r[3] and r[4] for r in rows))
c = collections.Counter()
for k in range(1, 7):
    nn = sum(1 for r in rows if len(r[5]) >= k and all(r[5][:k-1]))
    ok = sum(1 for r in rows if len(r[5]) >= k and all(r[5][:k]))
    print("pass", k, "reached", nn, "ok", ok, f"{100*ok/max(nn,1):.0f}%")
