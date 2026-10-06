"""scanres.py NAME [NAME2 ...]: one line per parameter set of scan.sh runs (out/sprint6/scan_NAME_<i>.jsonl); the set labels come from the log's [..] tags in order."""
import glob, json, os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
for name in sys.argv[1:]:
    log = open(os.path.join(ROOT, "out/sprint6", f"scan_{name}.log")).read()
    labels = re.findall(r"^\[(.*?)\] \[", log, flags=re.M)
    print(f"== scan {name}")
    i = 0
    while True:
        i += 1
        p = os.path.join(ROOT, "out/sprint6", f"scan_{name}_{i}.jsonl")
        if not os.path.exists(p):
            break
        rows = []
        for l in open(p):
            l = l.strip()
            if l:
                try:
                    rows.append(json.loads(l))
                except Exception:
                    pass
        if not rows:
            continue
        n = len(rows)
        falls = [r for r in rows if r.get("fell")]
        ph = {k: sum(1 for r in falls if r["phase"] == k) for k in ("START", "HANDOVER", "TOP")}
        surv = [r["peak"] for r in rows if not r.get("fell") and r.get("peak")]
        ms = sum(surv) / len(surv) if surv else float("nan")
        sst = [r["steady"] for r in rows if not r.get("fell") and r.get("steady")]
        mst = sum(sst) / len(sst) if sst else float("nan")
        tf = sorted(round(r["time"], 1) for r in falls)
        ma = sum((0 if r.get("fell") else (r.get("peak") or 0)) for r in rows) / n
        early = sum(1 for r in falls if r["time"] < 3.0)
        lab = labels[i - 1] if i - 1 < len(labels) else "?"
        import math
        real = len(falls) - early
        adj = real * math.exp(9.7 * (10.06 - mst)) if mst == mst else float("nan")
        done = "" if n else ""
        print(f"{lab:<44} n={n:<4} falls={len(falls):<4} {100*len(falls)/n:5.1f}%  S={ph['START']:<3} H={ph['HANDOVER']:<3} T={ph['TOP']:<3} (<3s: {early})  surv peak {ms:6.3f} steady {mst:6.3f}  all-mean {ma:6.3f}  falls-adj-to-10.06 {adj:5.1f}")
