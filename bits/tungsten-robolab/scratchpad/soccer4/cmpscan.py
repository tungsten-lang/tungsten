"""Paired comparison of two failscan JSONs on the same seeds (base vs variant).
usage: cmpscan.py <base.json> <variant.json> [label]
prints pass counts, fixed / broke lists with the phase and time of each fall, and the one-sided exact sign-test p."""
import json, sys
from math import comb


def load(fn):
    return {r["seed"]: r for r in json.load(open(fn))}


def fell(r):
    if r["good"]:
        return "ok"
    st = r["stand_time"] or 0.0
    ph = [e for e in r["events"] if e[1] <= st]
    lab = ph[-1][0] if ph else "?"
    return f"fell {st:.1f}s in {lab}"


a = load(sys.argv[1]); b = load(sys.argv[2])
label = sys.argv[3] if len(sys.argv) > 3 else ""
seeds = sorted(set(a) & set(b))
fixed = [s for s in seeds if not a[s]["good"] and b[s]["good"]]
broke = [s for s in seeds if a[s]["good"] and not b[s]["good"]]
both_bad = [s for s in seeds if not a[s]["good"] and not b[s]["good"]]
na = sum(a[s]["good"] for s in seeds); nb = sum(b[s]["good"] for s in seeds)
print(f"{label}: base {na}/{len(seeds)}  variant {nb}/{len(seeds)}   fixed {len(fixed)}, broke {len(broke)}, both bad {len(both_bad)}")
for s in fixed:
    print(f"   fixed {s}: was {fell(a[s])}")
for s in broke:
    print(f"   BROKE {s}: now {fell(b[s])}")
for s in both_bad:
    print(f"   both bad {s}: base {fell(a[s])} | variant {fell(b[s])}")
k = len(fixed); n = len(fixed) + len(broke)
if n:
    p = sum(comb(n, i) for i in range(k, n + 1)) / 2 ** n
    print(f"   one-sided exact sign test on the changed starts: p = {p:.4f} (k={k}, n={n})")
