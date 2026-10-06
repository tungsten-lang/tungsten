"""sstab (L7): robust summary of stepscan json files. usage: sstab.py name [name ...]   (out/lj7/ss_<name>.json)"""
import json, sys
import numpy as np
print("%-10s %4s %5s %6s %6s %6s %6s %6s %5s" % ("variant", "n", "nopl", "mean", "sd", "rsd", "mad", "p5-p95", ">.25"))
for nm in sys.argv[1:]:
    try:
        d = json.load(open("out/lj7/ss_%s.json" % nm))
    except Exception as e:
        print(nm, "missing"); continue
    rows = d["rows"]
    g = np.array([r["pen"]["gap"] for r in rows if r["pen"] and r["plant"]])
    nopl = sum(1 for r in rows if not r["plant"])
    if len(g) == 0: print(nm, "no data"); continue
    rsd = (np.percentile(g, 75) - np.percentile(g, 25)) / 1.349
    mad = 1.4826 * np.median(np.abs(g - np.median(g)))
    p = np.percentile(g, [5, 95])
    out = int((np.abs(g - np.median(g)) > 0.25).sum())
    print("%-10s %4d %5d %6.3f %6.3f %6.3f %6.3f %6.2f %5d" % (nm, len(g), nopl, g.mean(), g.std(), rsd, mad, p[1] - p[0], out))
