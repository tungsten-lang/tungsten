"""steppred3 (L7): predictability of the step from the state tp seconds AFTER the flight chunk starts (toe-off), with the feed-forward nudge adj as a regressor. usage: steppred3.py trace.json"""
import json, sys
import numpy as np
d = json.load(open(sys.argv[1]))
tps = [0.0, 0.016, 0.032, 0.048, 0.064, 0.08]
data = {t: [] for t in tps}
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
        toe_b = tdb[0][2] + r["board_x"]
        last_toe = toe_b - b["step"]
        k0 = None
        for k in range(len(T)):
            if T[k] >= a["t"] - 0.002 and lab[k] == "body:" + side + "flight":
                k0 = k; break
        if k0 is None or k0 < 5: continue
        adj = min(max(a["plan"] - a["stride"], -0.35), 0.35)
        for tp in tps:
            kk = k0 + int(round(tp / 0.004))
            if kk >= len(T) or T[kk] > tdb[0][1] - 0.01: continue
            com_x, com_z, vx, vz, pel_x, pel_z, ltx, ltz, rtx, rtz, lhx, lhz, rhx, rhz = A[kk]
            Ap = A[kk - 4]
            dt = T[kk] - T[kk - 4]
            sx, sz = (rtx, rtz) if land == "r_" else (ltx, ltz)
            sxp, szp = (Ap[8], Ap[9]) if land == "r_" else (Ap[6], Ap[7])
            data[tp].append((b["step"], adj, a["stride"], sx - last_toe, sz, (sx - sxp) / dt, (sz - szp) / dt, com_x - last_toe, vx, vz, com_z, sx - com_x))
print("samples per tp:", {t: len(v) for t, v in data.items()})
for tp in tps:
    S = np.array(data[tp]); y = S[:, 0]
    def fit(cols):
        X = np.column_stack([S[:, c] for c in cols] + [np.ones(len(S))])
        c = np.linalg.lstsq(X, y, rcond=None)[0]
        res = y - X @ c
        return res.std(), 1.4826 * np.median(np.abs(res - np.median(res))), c
    r0 = fit([1, 2]); r1 = fit([1, 2, 8, 9]); r2 = fit([1, 3, 4, 5, 6, 7, 8, 9, 10]); r3 = fit([1, 3, 5, 7, 8, 9]); r4 = fit([1, 11, 5, 8, 9]); r5 = fit([1, 11, 5, 6, 8, 9])
    print("tp %.3f: [adj,stride] %.3f | +vx,vz %.3f | foot+com+adj %.3f (MAD %.3f) | [adj,sx,svx,comx,vx,vz] %.3f | [adj,sx-comx,svx,vx,vz] %.3f | +svz %.3f" % (tp, r0[0], r1[0], r2[0], r2[1], r3[0], r4[0], r5[0]))
    if abs(tp - 0.032) < 1e-6:
        print("   coef foot+com+adj (adj,sx,sz,svx,svz,comx,vx,vz,comz,c):", np.round(r2[2], 3))
        print("   coef [adj,sx-comx,svx,svz,vx,vz,c]:", np.round(r5[2], 3))
