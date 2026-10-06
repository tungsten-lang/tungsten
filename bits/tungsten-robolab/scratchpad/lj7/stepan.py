"""stepan (L7): response of the realized step to the planner's nudge, from stepscan json files. usage: stepan.py file.json [st_max st_up]"""
import json, sys
import numpy as np
f = sys.argv[1]
st_max = float(sys.argv[2]) if len(sys.argv) > 2 else 0.35
st_up = float(sys.argv[3]) if len(sys.argv) > 3 else 0.35
rows = json.load(open(f))["rows"]
X = []   # (n_i, stride_i, plan_i, adj_i, s_next, s_prev, gap_i)
pens = []
for r in rows:
    dbg = r["dbg"]
    for i in range(len(dbg) - 1):
        a, b = dbg[i], dbg[i + 1]
        if a["n"] >= 2 and not a["pen"]:
            adj = min(max(a["plan"] - a["stride"], -st_max), st_up)
            X.append((a["n"], a["stride"], a["plan"], adj, b["step"], a["step"], a["gap"], r["seed"]))
        if a["n"] == 1 and a["pen"]:
            pass
    pen = r["pen"]
    if pen and r["plant"]:
        i = [k for k, x in enumerate(dbg) if x["pen"]][0]
        pens.append((pen["gap"], dbg[i]["step"], dbg[i-1]["n"] if i > 0 else -1, dbg[i-1]["plan"] if i > 0 else 0, dbg[i-1]["stride"] if i > 0 else 0, r["seed"]))
X = np.array(X)
print("steering touchdowns:", len(X))
for n in range(2, 9):
    m = X[:, 0] == n
    if m.sum() < 5: continue
    # realized step minus the planned step
    e = X[m, 4] - X[m, 2]
    adj = X[m, 3]
    # response: s_next - stride = b adj + c
    A = np.vstack([adj, np.ones(m.sum())]).T
    coef = np.linalg.lstsq(A, X[m, 4] - X[m, 1], rcond=None)[0]
    res = (X[m, 4] - X[m, 1]) - A @ coef
    print("n=%d: count %d  adj mean %+.3f sd %.3f | s_next - plan: mean %+.3f sd %.3f | s_next - stride = %+.3f %+.3f adj, residual sd %.3f | clipped %d" % (
        n, m.sum(), adj.mean(), adj.std(), e.mean(), e.std(), coef[1], coef[0], res.std(), int((np.abs(adj) >= min(st_max, st_up) - 1e-9).sum())))
m = X[:, 0] >= 2
A = np.vstack([X[m, 3], np.ones(m.sum())]).T
coef = np.linalg.lstsq(A, X[m, 4] - X[m, 1], rcond=None)[0]
print("all n>=2: s_next - stride = %+.3f %+.3f adj; residual sd %.3f" % (coef[1], coef[0], ((X[m, 4] - X[m, 1]) - A @ coef).std()))
# dependence of the residual on the previous step (the step-to-step variation: stride filter vs actual)
res = (X[m, 4] - X[m, 1]) - A @ coef
print("corr(residual, s_prev - stride) %.3f ; corr(residual, stride) %.3f" % (np.corrcoef(res, X[m, 5] - X[m, 1])[0, 1], np.corrcoef(res, X[m, 1])[0, 1]))
P = np.array(pens)
print("pen: n %d, gap mean %.3f sd %.3f" % (len(P), P[:, 0].mean(), P[:, 0].std()))
# the last nudge (n == 2 at P-1: plan to pen)
m = P[:, 2] == 1
print("pens whose previous touchdown had n=1 (plan_n 1 -> pen step is this) ", int(m.sum()))
# pen gap vs previous plan: error of the last steering step = actual pen step - planned
e_last = P[:, 1] - P[:, 3]
print("pen step (realized) minus the plan of the previous touchdown: mean %+.3f sd %.3f; pen step sd %.3f" % (e_last.mean(), e_last.std(), P[:, 1].std()))
