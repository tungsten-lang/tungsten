"""Does the aim error follow the blend's location mismatch?  aim_n against dz_eff, dx_eff = pitch - sum_i w_i loc_i.

    .venv/bin/python scratchpad/bat/an2.py out/bat_r2/base_3000_144.json
"""
import json, sys
import numpy as np

LOCS = np.array([[0.0, 0.80], [-0.14, 1.00], [0.15, 0.62], [-0.06, 0.68], [0.10, 0.95], [-0.12, 0.72]])   # x, z of the 6 programs


def weights(x, z, pw=2.0):
    d2 = (x - LOCS[:, 0]) ** 2 + (z - LOCS[:, 1]) ** 2
    w = 1.0 / (d2 ** (pw / 2) + 1e-8)
    return w / w.sum()


d = json.load(open(sys.argv[1]))
rows = d["rows"]
P = np.array([r["pitch"] for r in rows])
v, x, z = P[:, 0], P[:, 1], P[:, 2]
hit = np.array([r["hit"] for r in rows])
an = np.array([r["rec"].get("aim_n_cm", np.nan) for r in rows])
W = np.array([weights(xi, zi) for xi, zi in zip(x, z)])
xe = W @ LOCS[:, 0]
ze = W @ LOCS[:, 1]
dx = x - xe
dz = z - ze
dmin = np.sqrt(((P[:, None, 1:] - LOCS[None]) ** 2).sum(-1)).min(1)
ok = ~np.isnan(an)


def fit(y, names, cols, mask=None):
    mask = ok if mask is None else mask
    A = np.column_stack([np.ones(mask.sum())] + [c[mask] for c in cols])
    coef = np.linalg.lstsq(A, y[mask], rcond=None)[0]
    pred = A @ coef
    r2 = 1 - np.sum((y[mask] - pred) ** 2) / np.sum((y[mask] - y[mask].mean()) ** 2)
    print("  aim_n ~ %-14s R2 %.3f rms %.2f | " % ("+".join(names), r2, np.sqrt(np.mean((y[mask] - pred) ** 2))) +
          " ".join("%s %+.3g" % (n, c) for n, c in zip(["1"] + names, coef)))
    return coef


print("blend mismatch dz, dx (m): mean %.3f/%.3f, abs mean %.3f/%.3f, max %.3f/%.3f" % (dz.mean(), dx.mean(), np.abs(dz).mean(), np.abs(dx).mean(), np.abs(dz).max(), np.abs(dx).max()))
fit(an, ["dz", "dx"], [dz, dx])
fit(an, ["dz", "dx", "v"], [dz, dx, v])
fit(an, ["z", "x"], [z, x])
fit(an, ["dz", "dx", "z", "x"], [dz, dx, z, x])
print("aim_n vs distance to the nearest program:")
for lo, hi in ((0, 0.03), (0.03, 0.05), (0.05, 0.07), (0.07, 0.09), (0.09, 0.12), (0.12, 0.3)):
    m = (dmin >= lo) & (dmin < hi) & ok
    if m.sum():
        print("  d in [%.2f,%.2f): n %3d hits %3d  mean |aim_n| %.1f  mean aim_n %+.1f" % (lo, hi, m.sum(), hit[m].sum(), np.abs(an[m]).mean(), an[m].mean()))
