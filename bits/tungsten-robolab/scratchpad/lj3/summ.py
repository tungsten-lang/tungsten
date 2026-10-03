"""Summarise long_jump_eval.py json outputs: mean, legal fraction, failure classes with seeds, legal-mark quantiles (L3).
usage: summ.py <ev.json> [<ev2.json> ...]"""
import json, sys, math
import numpy as np


def why(m):
    if m.get("error"):
        return "error"
    if m.get("official_m", 0.0) > 0.0:
        return ""
    for k, lab in (("foul", "foul"), ("somersault", "somersault"), ("landed_short", "short"),
                   ("touched_runway_after_landing", "runway-after"), ("fell_approach", "fell-in-run")):
        if m.get(k):
            return lab
    return "no-take-off" if m.get("takeoff_vx") is None else "0"


def main():
    allrows, allseeds, allsc = [], [], []
    for p in sys.argv[1:]:
        j = json.load(open(p))
        allrows += j["rows"]; allseeds += j["seeds"]; allsc += j["scores"]
    sc = np.array([s if abs(s) < 1e8 else 0.0 for s in allsc])
    n = len(sc)
    legal = sc[sc > 0]
    cls = {}
    for s, m in zip(allseeds, allrows):
        w = why(m)
        if w:
            cls.setdefault(w, []).append(s)
    print("n %d  mean %.3f (95%% CI +-%.3f)  legal %d (%.1f%%)  mean of legal %.3f" % (
        n, sc.mean(), 1.96 * sc.std(ddof=1) / math.sqrt(n), len(legal), 100.0 * len(legal) / n, legal.mean() if len(legal) else 0.0))
    if len(legal):
        print("legal marks: median %.3f  p10 %.3f  p90 %.3f  best %.3f  worst %.3f  above 8.95 m: %d (%.1f%% of starts)" % (
            np.median(legal), np.percentile(legal, 10), np.percentile(legal, 90), legal.max(), legal.min(), int((legal > 8.95).sum()), 100.0 * (legal > 8.95).sum() / n))
    for k, v in sorted(cls.items()):
        print("  %-13s %3d  %s" % (k, len(v), v if len(v) <= 40 else str(v[:40]) + " ..."))
    off = [m.get("board_offset_m") for m in allrows if m.get("official_m", 0) > 0 and m.get("board_offset_m") is not None]
    if off:
        print("take-off foot offset of the legal jumps (m behind the line): mean %.3f sd %.3f" % (np.mean(off), np.std(off)))


main()
