"""Aim-error structure of a bat_rep.py eval JSON: hit/miss and aim_n / aim_v against the pitch (x, z, v).

    .venv/bin/python scratchpad/bat/an1.py out/bat_r2/base_3000_144.json
"""
import json
import sys

import numpy as np

d = json.load(open(sys.argv[1]))
rows = d["rows"]
P = np.array([r["pitch"] for r in rows])          # v, x, z
v, x, z = P[:, 0], P[:, 1], P[:, 2]
hit = np.array([r["hit"] for r in rows])
an = np.array([r["rec"].get("aim_n_cm", np.nan) for r in rows])
av = np.array([r["rec"].get("aim_v_ms", np.nan) for r in rows])
adz = np.array([r["rec"].get("aim_dz_cm", np.nan) for r in rows])
asr = np.array([r["rec"].get("aim_s", np.nan) for r in rows])
sp = np.array([r["rec"].get("bat_speed", 0.0) for r in rows])
flow = np.array([r["flow"] if r["flow"] is not None else np.nan for r in rows])
print(d["summary"])
ok = ~np.isnan(an)
print("n", len(rows), "hits", hit.sum(), "aim_n mean %.2f sd %.2f min %.1f max %.1f" % (np.nanmean(an), np.nanstd(an), np.nanmin(an), np.nanmax(an)))


def fit(y, names, cols, mask):
    A = np.column_stack([np.ones(mask.sum())] + [c[mask] for c in cols])
    coef, res, rk, sv = np.linalg.lstsq(A, y[mask], rcond=None)
    pred = A @ coef
    r2 = 1 - np.sum((y[mask] - pred) ** 2) / np.sum((y[mask] - y[mask].mean()) ** 2)
    print("  %-10s R2 %.3f rms resid %.2f | " % ("+".join(names), r2, np.sqrt(np.mean((y[mask] - pred) ** 2))) +
          " ".join("%s %+.3g" % (n, c) for n, c in zip(["1"] + names, coef)))
    return coef


print("aim_n (cm) linear in the pitch:")
fit(an, ["x", "z", "v"], [x, z, v], ok)
fit(an, ["x", "z"], [x, z], ok)
print("aim_n quadratic in (x, z):")
fit(an, ["x", "z", "xx", "xz", "zz", "v"], [x, z, x * x, x * z, z * z, v], ok)
print("aim_v (ms) linear in the pitch:")
fit(av, ["x", "z", "v"], [x, z, v], ok)
print("bat speed of hits linear in the pitch:")
fit(sp, ["x", "z", "v"], [x, z, v], hit)
print("flow linear in the pitch:")
fit(flow, ["x", "z", "v"], [x, z, v], ~np.isnan(flow))
# hit probability by height and x
print("hit rate by z (bins of 0.06) and x (3 bins):")
zb = np.array([0.62, 0.68, 0.74, 0.80, 0.86, 0.92, 1.0001])
xb = np.array([-0.15, -0.05, 0.05, 0.1501])
print("        " + "  ".join("x[%+.2f,%+.2f)" % (xb[i], xb[i + 1]) for i in range(3)))
for i in range(len(zb) - 1):
    cells = []
    for j in range(3):
        m = (z >= zb[i]) & (z < zb[i + 1]) & (x >= xb[j]) & (x < xb[j + 1])
        cells.append("%2d/%2d an %+5.1f" % (hit[m].sum(), m.sum(), np.nanmean(an[m])) if m.sum() else "   -          ")
    print("z[%.2f,%.2f) " % (zb[i], zb[i + 1]) + "  ".join(cells))
print("misses:")
for r in rows:
    if not r["hit"]:
        p = r["pitch"]
        print("  seed %5d v %.1f x %+.3f z %.3f  aim_n %.1f aim_v %.1f gap %.1f s %.2f" % (r["seed"], p[0], p[1], p[2], r["rec"].get("aim_n_cm", np.nan), r["rec"].get("aim_v_ms", np.nan), r["rec"].get("gap_cm", np.nan), r["rec"].get("aim_s", np.nan)))
