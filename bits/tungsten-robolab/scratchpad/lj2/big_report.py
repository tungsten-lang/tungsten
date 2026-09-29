"""Summarise the never-used-seed evaluations of the final robust programs (scratchpad/lj2/eval_big_<tag>.json) and pair them.
usage: big_report.py [tag ...]   (default final2 final1 final3)"""
import json
import math
import random
import statistics as st
import sys
from collections import Counter

D = "/Users/erik/tungsten/bits/tungsten-robolab/scratchpad/lj2/"


def cls(r):
    if r.get("official_m", 0) > 0:
        return "legal"
    if r.get("fell_approach"):
        return "fell in run"
    if r.get("foul_lj") or r.get("foul"):
        return "foul"
    if r.get("somersault"):
        return "somersault"
    return "other"


def pct(xs, q):
    xs = sorted(xs)
    k = (len(xs) - 1) * q
    lo, hi = int(math.floor(k)), int(math.ceil(k))
    return xs[lo] + (xs[hi] - xs[lo]) * (k - lo)


def signflip(diff, n=200000, seed=3):
    nz = [d for d in diff if abs(d) > 1e-12]
    rng = random.Random(seed)
    obs = abs(sum(nz))
    cnt = 0
    for _ in range(n):
        s = 0.0
        for d in nz:
            s += d if rng.random() < 0.5 else -d
        if abs(s) >= obs - 1e-12:
            cnt += 1
    return cnt / n


def main():
    tags = sys.argv[1:] or ["final2", "final1", "final3"]
    data = {t: json.load(open(D + "eval_big_%s.json" % t)) for t in tags}
    for t, d in data.items():
        sc = d["scores"]
        legal = [s for s in sc if s > 0]
        c = Counter(cls(r) for r in d["rows"])
        sd = st.pstdev(sc)
        print("%s: n=%d seeds %s-%s mean %.3f (+-%.3f, 95%%) legal %d (%.1f %%) %s" % (
            t, len(sc), d["seeds"][0], d["seeds"][-1], sum(sc) / len(sc), 1.96 * sd / math.sqrt(len(sc)), len(legal),
            100.0 * len(legal) / len(sc), dict(c)))
        print("   legal marks: mean %.3f median %.3f p10 %.3f p90 %.3f min %.3f max %.3f" % (
            sum(legal) / len(legal), st.median(legal), pct(legal, 0.1), pct(legal, 0.9), min(legal), max(legal)))
        blocks = [sc[i:i + 96] for i in range(0, len(sc), 96)]
        print("   per block of 96: " + ", ".join("%.3f" % (sum(b) / len(b)) for b in blocks))
        fell = [s for s, r in zip(d["seeds"], d["rows"]) if cls(r) == "fell in run"]
        print("   failure seeds: fell in run %s" % fell)
    ts = list(data)
    for i in range(len(ts)):
        for j in range(i + 1, len(ts)):
            a, b = data[ts[i]], data[ts[j]]
            diff = [y - x for x, y in zip(a["scores"], b["scores"])]
            nz = [x for x in diff if abs(x) > 1e-12]
            print("paired %s -> %s: mean diff %+.3f, %d starts differ (%d up, %d down), sign-flip p = %.3f" % (
                ts[i], ts[j], sum(diff) / len(diff), len(nz), sum(1 for x in nz if x > 0), sum(1 for x in nz if x < 0),
                signflip(diff)))


if __name__ == "__main__":
    main()
