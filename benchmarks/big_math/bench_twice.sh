#!/bin/sh
# Item 19 — two-run keep gate for "all 100 quick cells < 1.0 vs GMP".
# Runs the accurate quick matrix TWICE and reports, per cell, the WORSE
# (max) W/GMP ratio; exits non-zero if any cell reaches >= 1.0 in either run.
# The +-5% band drifts run-to-run, so a single green pass is not proof.
set -e
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="${OUT:-/tmp/bench_twice}"; mkdir -p "$OUT"
"$ROOT/bin/tungsten" bench bignum --quick --accurate --no-capacity --json > "$OUT/run1.json" 2>/dev/null
"$ROOT/bin/tungsten" bench bignum --quick --accurate --no-capacity --json > "$OUT/run2.json" 2>/dev/null
python3 - "$OUT/run1.json" "$OUT/run2.json" <<'PY'
import json,sys
def cells(p):
    d=json.load(open(p)); rows=None
    for k in ("results","cells","matrix"):
        if isinstance(d.get(k),list): rows=d[k]; break
    if rows is None:
        for k in d:
            if isinstance(d[k],list) and d[k] and isinstance(d[k][0],dict): rows=d[k]; break
    out={}
    for r in rows or []:
        op,lm=r.get("operation"),r.get("limbs")
        rt=r.get("tungsten_over_gmp")
        if rt is None:
            t,g=r.get("tungsten_ns"),r.get("gmp_ns"); rt=(t/g) if t and g else None
        if op and lm is not None and rt: out[(op,lm)]=rt
    return out
a,b=cells(sys.argv[1]),cells(sys.argv[2])
keys=sorted(set(a)|set(b))
worst=[]; losers=[]
for k in keys:
    m=max(a.get(k,0),b.get(k,0))
    worst.append((m,k))
    if m>=1.0: losers.append((m,k))
worst.sort(reverse=True)
print("worst 8 cells (max of two runs):")
for m,(op,lm) in worst[:8]: print(f"  {op}@{lm}: {m:.3f}")
print(f"\ncells: {len(keys)}, wins-both: {sum(1 for k in keys if max(a.get(k,9),b.get(k,9))<1.0)}/{len(keys)}")
if losers:
    print("FAIL — cells >= 1.0 in some run:", ", ".join(f"{op}@{lm}={m:.3f}" for m,(op,lm) in losers))
    sys.exit(1)
print("PASS — all cells < 1.0 in BOTH runs")
PY
