"""Paired probe analysis: change of aim_n / bat speed / flow against a baseline eval, regressed on the blend mismatch.

    .venv/bin/python scratchpad/bat/an3.py BASE.json PROBE.json
"""
import json, sys
import numpy as np

LOCS = np.array([[0.0, 0.80], [-0.14, 1.00], [0.15, 0.62], [-0.06, 0.68], [0.10, 0.95], [-0.12, 0.72]])


def weights(x, z, pw=2.0):
    d2 = (x - LOCS[:, 0]) ** 2 + (z - LOCS[:, 1]) ** 2
    w = 1.0 / (d2 ** (pw / 2) + 1e-8)
    return w / w.sum()


def load(path):
    d = json.load(open(path))
    return {r["seed"]: r for r in d["rows"]}, d


A, da = load(sys.argv[1])
B, db = load(sys.argv[2])
seeds = sorted(set(A) & set(B))
rows = []
for s in seeds:
    a, b = A[s], B[s]
    x, z = a["pitch"][1], a["pitch"][2]
    w = weights(x, z)
    dz = z - w @ LOCS[:, 1]
    dx = x - w @ LOCS[:, 0]
    rows.append((s, x, z, dz, dx, a["rec"].get("aim_n_cm", np.nan), b["rec"].get("aim_n_cm", np.nan), a["hit"], b["hit"],
                 a["rec"].get("bat_speed", 0.0) if a["hit"] else 0.0, b["rec"].get("bat_speed", 0.0) if b["hit"] else 0.0,
                 a["flow"], b["flow"], a["rec"].get("aim_v_ms", np.nan), b["rec"].get("aim_v_ms", np.nan)))
R = np.array(rows, float)
s_, x, z, dz, dx, an0, an1, h0, h1, sp0, sp1, f0, f1, av0, av1 = R.T
d_an = an1 - an0
ok = ~np.isnan(d_an)
print("n", len(R), "hits base %d probe %d" % (h0.sum(), h1.sum()), "power base %.3f probe %.3f" % (sp0.mean(), sp1.mean()),
      "flow base %.3f probe %.3f" % (np.nanmean(f0), np.nanmean(f1)), "hit speed base %.3f probe %.3f" % (sp0[h0 > 0].mean(), sp1[h1 > 0].mean()))
print("aim_n base mean %.2f sd %.2f | probe mean %.2f sd %.2f" % (np.nanmean(an0), np.nanstd(an0), np.nanmean(an1), np.nanstd(an1)))
A_ = np.column_stack([np.ones(ok.sum()), dz[ok], dx[ok]])
coef = np.linalg.lstsq(A_, d_an[ok], rcond=None)[0]
pred = A_ @ coef
r2 = 1 - np.sum((d_an[ok] - pred) ** 2) / np.sum((d_an[ok] - d_an[ok].mean()) ** 2)
print("delta aim_n (cm) ~ 1 + dz + dx: %+.2f %+.1f dz(m) %+.1f dx(m)   R2 %.3f rms %.2f" % (coef[0], coef[1], coef[2], r2, np.sqrt(np.mean((d_an[ok] - pred) ** 2))))
d_sp = sp1 - sp0
both = (h0 > 0) & (h1 > 0)
print("bat speed change on pitches hit by both: mean %+.3f sd %.3f (n %d)" % (d_sp[both].mean(), d_sp[both].std(), both.sum()))
print("timing aim_v: base mean %.2f probe mean %.2f" % (np.nanmean(av0), np.nanmean(av1)))
