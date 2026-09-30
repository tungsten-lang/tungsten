"""expo_table.py ROWS.jsonl [ROWS2.jsonl ...]: exposure of recfem_r's wrap tangent per ARM (tag before '|') from the substep histogram of the guarded task (t >= 3 s):
starts, start-seconds watched, substeps within 1e-4 / 1e-3 of the tangent (per start-second), sliver states met (survived; 0 < margin < 1e-7), NaN events (count-only mode: each would end an official hold),
starts with > 1 % of the watched substeps within 1e-4, and the tangent crossings of recfem_r (control steps)."""
import collections
import json
import sys

import numpy as np

rows = {}
for path in sys.argv[1:]:
    for l in open(path):
        try:
            r = json.loads(l)
        except Exception:
            continue
        rows[r["tag"]] = r
arms = collections.OrderedDict()
for t, r in rows.items():
    arms.setdefault(t.split("|")[0], []).append(r)
print(f"{'arm':10s} {'starts':>6s} {'start-s':>8s} {'sub<1e-4 /s':>12s} {'sub<1e-3 /s':>12s} {'sliver':>7s} {'NaN':>4s} {'>1% starts':>10s} {'flips(rf)':>9s}  {'falls':>5s}")
for arm, rs in arms.items():
    ok = [r for r in rs if r.get("wrap_r_hist")]
    if not ok:
        continue
    tot_s, s4, s3, sl, nan, hot, flips, falls = 0.0, 0.0, 0.0, 0, 0, 0, 0.0, 0
    for r in ok:
        pos, neg = r["wrap_r_hist"].split("|")
        pos = np.array([int(x) for x in pos.split(",")])
        neg = np.array([int(x) for x in neg.split(",")])
        both = pos + neg
        n = both.sum()
        tot_s += n / 1000.0
        s4 += both[:6].sum()
        s3 += both[:7].sum()
        sl += int(pos[:2].sum())
        nan += int(r.get("nan_events") or 0)
        hot += int(both[:6].sum() > 0.01 * n)
        flips += float(r.get("seg_flips_rf") or r.get("wrap_r_flips") or 0)
        falls += int(bool(r.get("fallen")) or (r.get("stand_time") or 0) < r["seconds"] - 0.11)
    print(f"{arm:10s} {len(ok):6d} {tot_s:8.0f} {s4 / tot_s:12.3f} {s3 / tot_s:12.3f} {sl:7d} {nan:4d} {hot:10d} {flips:9.0f}  {falls:5d}")
