"""steppred2 (L7): predictability of the touchdown toe x from the in-flight state, tau seconds before the touchdown. usage: steppred2.py trace.json"""
import json, sys
import numpy as np
d = json.load(open(sys.argv[1]))
taus = [0.15, 0.12, 0.10, 0.08, 0.06, 0.04, 0.02]
data = {t: [] for t in taus}
for r in d["rows"]:
    rows = r["rows"]; dbg = r["dbg"]
    if len(rows) < 100: continue
    T = np.array([x[0] for x in rows]); lab = [x[1] for x in rows]
    A = np.array([[x[k] for k in range(2, 16)] for x in rows], float)
    for i in range(1, len(dbg) - 1):
        a, b = dbg[i], dbg[i + 1]
        if a["pen"] or a["n"] < 2 or not (1.4 < b["step"] < 3.3): continue
        side = a["side"]; land = "r_" if side == "l_" else "l_"
        tdb = [k for k in r["tds"] if abs(k[1] - b["t"]) < 0.03 and k[0] == land[0]]
        if not tdb: continue
        t_td = tdb[0][1]
        toe_b = tdb[0][2] + r["board_x"]
        last_toe = toe_b - b["step"]
        # flight start
        k0 = None
        for k in range(len(T)):
            if T[k] >= a["t"] - 0.002 and lab[k] == "body:" + side + "flight":
                k0 = k; break
        if k0 is None: continue
        adj = min(max(a["plan"] - a["stride"], -0.35), 0.35)
        for tau in taus:
            kk = int(np.argmin(np.abs(T - (t_td - tau))))
            if kk <= k0 + 1 or kk < 4: continue
            com_x, com_z, vx, vz, pel_x, pel_z, ltx, ltz, rtx, rtz, lhx, lhz, rhx, rhz = A[kk]
            Ap = A[kk - 4]
            dt = T[kk] - T[kk - 4]
            sx, sz = (rtx, rtz) if land == "r_" else (ltx, ltz)
            sxp, szp = (Ap[8], Ap[9]) if land == "r_" else (Ap[6], Ap[7])
            svx, svz = (sx - sxp) / dt, (sz - szp) / dt
            data[tau].append((b["step"], adj, a["stride"], sx - last_toe, sz, svx, svz, com_x - last_toe, vx, vz, com_z))
print("samples per tau:", {t: len(v) for t, v in data.items()})
for tau in taus:
    S = np.array(data[tau])
    if len(S) < 50: continue
    y = S[:, 0]
    def fit(cols, label):
        X = np.column_stack([S[:, c] for c in cols] + [np.ones(len(S))])
        c = np.linalg.lstsq(X, y, rcond=None)[0]
        res = y - X @ c
        return res.std(), 1.4826 * np.median(np.abs(res - np.median(res)))
    f1 = fit([2, 8, 9], "stride vx vz")
    f2 = fit([3, 4, 5, 6], "swing foot only")
    f3 = fit([3, 4, 5, 6, 7, 8, 9, 10], "foot + com")
    f4 = fit([1, 3, 4, 5, 6, 7, 8, 9, 10], "foot + com + adj")
    print("tau %.2f s: resid sd [stride,vx,vz] %.3f | [swing foot x,z,vx,vz] %.3f (MAD %.3f) | [foot+com] %.3f (MAD %.3f) | [foot+com+adj] %.3f (MAD %.3f)" % (tau, f1[0], f2[0], f2[1], f3[0], f3[1], f4[0], f4[1]))
