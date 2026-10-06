"""runtab (L7): falls before the pen and speed at the board of stepscan json files. usage: runtab.py name [name ...]"""
import json, sys
import numpy as np
print("%-18s %5s %7s %9s %8s %8s %7s" % ("variant", "rows", "no pen", "fell+nopen", "vx_board", "t_board", "gap sd"))
for nm in sys.argv[1:]:
    try: d = json.load(open("out/lj7/ss_%s.json" % nm))
    except Exception: print(nm, "missing"); continue
    rows = d["rows"]
    nopen = sum(1 for r in rows if not r["pen"])
    fn = sum(1 for r in rows if r["fell"] and not r["pen"])
    vb = np.array([r["vx_board"] for r in rows if r.get("vx_board") and r["pen"]])
    tb = np.array([r["t_board"] for r in rows if r.get("t_board") and r["pen"]])
    g = np.array([r["pen"]["gap"] for r in rows if r["pen"] and r["plant"]])
    print("%-18s %5d %7d %9d %8.3f %8.3f %7.3f" % (nm, len(rows), nopen, fn, vb.mean(), tb.mean(), g.std()))
