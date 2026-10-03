"""report.py FILE.jsonl [...]: one table of fr.py result files: n, falls (rate, Wilson 95 %), phases, survivors' mean peak (min-max), all-start mean (fall = 0), falls before 20 s (the 150 m run-up of the long jump)."""
import json, math, sys
def wilson(k, n, z=1.96):
    p = k / n; den = 1 + z * z / n; c = (p + z * z / (2 * n)) / den
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / den
    return 100 * max(0, c - h), 100 * min(1, c + h)
for fn in sys.argv[1:]:
    rows = [json.loads(l) for l in open(fn) if l.strip()]
    n = len(rows); f = [r for r in rows if r["fell"]]
    surv = [r["peak"] for r in rows if not r["fell"] and r.get("peak")]
    ph = {k: sum(1 for r in f if r["phase"] == k) for k in ("START", "HANDOVER", "TOP")}
    lo, hi = wilson(len(f), n)
    print(f"{fn.split('/')[-1]:<32} n={n} falls={len(f)} ({100*len(f)/n:.1f} %, Wilson {lo:.1f}-{hi:.1f})  START {ph['START']} HANDOVER {ph['HANDOVER']} TOP {ph['TOP']}  "
          f"survivors' peak {sum(surv)/len(surv):.3f} ({min(surv):.3f}-{max(surv):.3f})  all-start mean {sum((0 if r['fell'] else r['peak']) for r in rows)/n:.3f}  falls < 20 s: {sum(1 for r in f if r['time'] < 20.0)}")
