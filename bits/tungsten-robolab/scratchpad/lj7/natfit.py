"""natfit (L7): fit the natural-step predictor at toe-off: step - adj = c0 + c1 stride + c2 vx + c3 vz; train on one trace file, test on another.
usage: natfit.py train.json [test.json]"""
import json, sys
import numpy as np

def samples(path, nudge_model="old"):
    d = json.load(open(path))
    S = []
    for r in d["rows"]:
        rows = r["rows"]; dbg = r["dbg"]
        if len(rows) < 100: continue
        T = np.array([x[0] for x in rows]); lab = [x[1] for x in rows]
        A = np.array([[x[k] for k in range(2, 16)] for x in rows], float)
        for i in range(1, len(dbg) - 1):
            a, b = dbg[i], dbg[i + 1]
            if a["pen"] or a["n"] < 2 or not (1.4 < b["step"] < 3.3): continue
            side = a["side"]; land = "r_" if side == "l_" else "l_"
            k0 = None
            for k in range(len(T)):
                if T[k] >= a["t"] - 0.002 and lab[k] == "body:" + side + "flight":
                    k0 = k; break
            if k0 is None: continue
            com_x, com_z, vx, vz = A[k0 - 1][:4]   # the observation of the tick that enters the flight chunk = the state after the previous tick's step
            adj = min(max(a["plan"] - a["stride"], -0.35), 0.35)
            S.append((b["step"], adj, a["stride"], vx, vz, com_z, a["plan"], r["seed"], a["n"]))
    return np.array(S)

A = samples(sys.argv[1])
print("train samples", len(A))
def design(S, cols):
    return np.column_stack([S[:, c] for c in cols] + [np.ones(len(S))])
for name, cols in (("stride,vx,vz", [2, 3, 4]), ("vx,vz", [3, 4]), ("stride,vx", [2, 3]), ("stride,vx,vz,com_z", [2, 3, 4, 5])):
    X = design(A, cols); y = A[:, 0] - A[:, 1]
    c = np.linalg.lstsq(X, y, rcond=None)[0]
    res = y - X @ c
    msg = "%-20s coef %s  train resid sd %.4f MAD %.4f" % (name, np.round(c, 4), res.std(), 1.4826 * np.median(np.abs(res - np.median(res))))
    if len(sys.argv) > 2:
        B = samples(sys.argv[2]); yb = B[:, 0] - B[:, 1]
        rb = yb - design(B, cols) @ c
        # baseline on test: (step - adj) - stride
        msg += " | TEST n %d resid sd %.4f MAD %.4f (stride-only baseline sd %.4f)" % (len(B), rb.std(), 1.4826 * np.median(np.abs(rb - np.median(rb))), (yb - B[:, 2]).std())
    print(msg)
