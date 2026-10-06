"""steppred4 (L7): physics-based in-flight predictors of the touchdown toe x (time-to-go from the swing foot's height and descent speed). usage: steppred4.py trace.json"""
import json, sys
import numpy as np
d = json.load(open(sys.argv[1]))
tps = [0.04, 0.06, 0.08, 0.10, 0.12]
data = {t: [] for t in tps}
ztd = []
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
        k0 = None
        for k in range(len(T)):
            if T[k] >= a["t"] - 0.002 and lab[k] == "body:" + side + "flight":
                k0 = k; break
        if k0 is None or k0 < 5: continue
        ktd = int(np.argmin(np.abs(T - t_td)))
        sz_td = A[ktd][9] if land == "r_" else A[ktd][7]
        ztd.append(sz_td)
        adj = min(max(a["plan"] - a["stride"], -0.35), 0.35)
        for tp in tps:
            kk = k0 + int(round(tp / 0.004))
            if kk >= len(T) or T[kk] > t_td - 0.012: continue
            com_x, com_z, vx, vz, pel_x, pel_z, ltx, ltz, rtx, rtz, lhx, lhz, rhx, rhz = A[kk]
            Ap = A[kk - 3]; dt = T[kk] - T[kk - 3]
            sx, sz = (rtx, rtz) if land == "r_" else (ltx, ltz)
            sxp, szp = (Ap[8], Ap[9]) if land == "r_" else (Ap[6], Ap[7])
            svx, svz = (sx - sxp) / dt, (sz - szp) / dt
            data[tp].append((b["step"], adj, a["stride"], sx - last_toe, sz, svx, svz, com_x - last_toe, vx, vz, com_z, t_td - T[kk], toe_b - last_toe, sx - com_x))
print("toe z at touchdown: mean %.3f sd %.3f" % (np.mean(ztd), np.std(ztd)))
for tp in tps:
    S = np.array(data[tp])
    y = S[:, 0]
    sz, svz, svx, sx = S[:, 4], S[:, 6], S[:, 5], S[:, 3]
    tau_true = S[:, 11]
    # time to go from the foot's descent
    with np.errstate(all="ignore"):
        tau_hat = np.where(svz < -0.3, (sz - 0.02) / (-svz), np.nan)
    ok = ~np.isnan(tau_hat) & (tau_hat > 0) & (tau_hat < 0.2)
    print("tp %.2f: n %d, usable %d | tau true mean %.3f sd %.3f | tau_hat vs true corr %.2f  resid sd %.4f s (bias %.4f)" % (tp, len(S), ok.sum(), tau_true.mean(), tau_true.std(), np.corrcoef(tau_hat[ok], tau_true[ok])[0, 1], (tau_hat[ok] - tau_true[ok]).std(), (tau_hat[ok] - tau_true[ok]).mean()))
    xh = sx + svx * tau_hat
    xh2 = S[:, 7] + S[:, 8] * tau_hat + (S[:, 13])   # com-based: com advance + current foot-com offset (crude)
    for nm, f in (("foot extrapolation", xh), ("com based", xh2)):
        res = y[ok] - f[ok]
        c = np.polyfit(f[ok], y[ok], 1)
        res2 = y[ok] - np.polyval(c, f[ok])
        print("     %-20s raw resid mean %.3f sd %.3f | after linear fit (slope %.2f) sd %.4f" % (nm, res.mean(), res.std(), c[0], res2.std()))
    # regression with the true tau (oracle on timing) to see what timing knowledge is worth
    X = np.column_stack([S[:, 1], S[:, 3], S[:, 4], S[:, 5], S[:, 6], S[:, 7], S[:, 8], S[:, 9], tau_true, np.ones(len(S))])
    c = np.linalg.lstsq(X, y, rcond=None)[0]; print("     oracle-time regression resid sd %.4f" % (y - X @ c).std())
    X = np.column_stack([S[:, 1], S[:, 3], S[:, 4], S[:, 5], S[:, 6], S[:, 7], S[:, 8], S[:, 9], np.ones(len(S))])
    c = np.linalg.lstsq(X, y, rcond=None)[0]; print("     linear no-time regression resid sd %.4f" % (y - X @ c).std())
