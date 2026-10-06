"""bo6: the BEST-OF-SIX metric of the long-jump round 6 (agent L6). LABELLED beyond-human body, unlimited run-up.

Definitions (fixed before any run; the metric is not changed after seeing results):
  * the mark of a start = official_m if the jump is legal (not foul, not fell_approach, official_m > 0) else 0;
  * per set: legal fraction, legal mean / median / p90 / max, per-attempt P(mark > T) with its count, mean over all starts (illegal = 0);
  * COMPETITION numbers (six attempts, T = 8.95 m = the human record): P(best of six > T), median and mean best-of-six mark, from DRAWS (20000)
    resamplings of 6 starts WITHOUT replacement (seeded RNG), plus the EXACT values (order statistics; they agree with the resampling up to its noise)
    and a bootstrap 95 % interval over starts (each replicate resamples the starts with replacement and uses the exact formulas).

usage: bo6.py [--T 8.95] [--k 6] [--draws 20000] [--boot 2000] [--seeds A-B] [--label NAME] FILE.json [FILE2.json ... = merged into ONE candidate]
       bo6.py ... --vs OTHER.json[,OTHER2.json]   paired bootstrap of the differences on the seeds both files have
a file is the json written by playground/long_jump_eval.py (keys seeds, rows, scores). Several candidates: call it once per candidate (or use the module: load / summary / compete).
"""
import argparse
import json
import math
import sys

import numpy as np

T_DEFAULT = 8.95
K_DEFAULT = 6


def is_legal(r):
    return (not r.get("error")) and (not r.get("foul")) and (not r.get("fell_approach")) and r.get("official_m", 0.0) > 0.0


def load(paths):
    """-> (seeds list, marks array, rows list) merged over the files, in file order."""
    if isinstance(paths, str):
        paths = [paths]
    seeds, marks, rows = [], [], []
    for p in paths:
        d = json.load(open(p))
        for s, r in zip(d["seeds"], d["rows"]):
            seeds.append(s)
            rows.append(r)
            marks.append(float(r["official_m"]) if is_legal(r) else 0.0)
    return seeds, np.array(marks), rows


def restrict(seeds, marks, rows, spec):
    if not spec:
        return seeds, marks, rows
    a, b = [int(x) for x in spec.split("-")]
    keep = [i for i, s in enumerate(seeds) if s is not None and a <= s <= b]
    return [seeds[i] for i in keep], marks[keep], [rows[i] for i in keep]


def summary(marks, T=T_DEFAULT):
    n = len(marks)
    leg = marks[marks > 0]
    out = {"n": n, "legal": int(len(leg)), "legal_frac": len(leg) / n if n else float("nan"),
           "mean_all": float(marks.mean()) if n else float("nan"),
           "n_gt": int((marks > T).sum()), "p_gt": float((marks > T).mean()) if n else float("nan")}
    if len(leg):
        out.update(legal_mean=float(leg.mean()), legal_median=float(np.median(leg)), legal_p90=float(np.percentile(leg, 90)),
                   legal_max=float(leg.max()))
    else:
        out.update(legal_mean=float("nan"), legal_median=float("nan"), legal_p90=float("nan"), legal_max=float("nan"))
    return out


def _cdf_max(n, k):
    """cdf of the index (1..n) of the maximum of k drawn without replacement: C(i,k)/C(n,k)."""
    i = np.arange(0, n + 1, dtype=float)
    c = np.ones(n + 1)
    for j in range(k):
        c = c * np.maximum(i - j, 0.0) / (n - j)
    return c  # c[i] = P(max index <= i), c[0] = 0


def compete_exact(marks, T=T_DEFAULT, k=K_DEFAULT):
    """exact P(best of k > T), median and mean best-of-k mark, drawing k of the n starts without replacement."""
    n = len(marks)
    m = np.sort(np.asarray(marks, dtype=float))
    c = _cdf_max(n, k)
    pm = np.diff(c)                      # P(max = m[i]), i = 0..n-1
    mean = float((pm * m).sum())
    med = float(m[np.searchsorted(c[1:], 0.5, side="left")])
    cgt = int((m > T).sum())
    p_gt = 1.0 - (c[n - cgt] if cgt < n else 0.0)   # P(all k among the n - cgt marks <= T) = cdf at index n - cgt
    return {"p_gt": float(p_gt), "median": med, "mean": mean}


def compete_mc(marks, T=T_DEFAULT, k=K_DEFAULT, draws=20000, seed=6):
    """the brief's definition: `draws` resamplings of k starts without replacement."""
    rng = np.random.default_rng(seed)
    n = len(marks)
    marks = np.asarray(marks, dtype=float)
    best = np.empty(draws)
    chunk = 2000
    for a in range(0, draws, chunk):
        b = min(draws, a + chunk)
        r = rng.random((b - a, n))
        idx = np.argpartition(r, k - 1, axis=1)[:, :k]
        best[a:b] = marks[idx].max(axis=1)
    return {"p_gt": float((best > T).mean()), "median": float(np.median(best)), "mean": float(best.mean())}


def bootstrap(marks, T=T_DEFAULT, k=K_DEFAULT, B=2000, seed=61):
    """bootstrap over starts: 95 % intervals of the competition numbers (exact formulas per replicate) and of the per-attempt numbers."""
    rng = np.random.default_rng(seed)
    n = len(marks)
    marks = np.asarray(marks, dtype=float)
    rec = {"p6": [], "med6": [], "mean6": [], "legal_frac": [], "p1": [], "mean_all": []}
    for _ in range(B):
        s = marks[rng.integers(0, n, n)]
        e = compete_exact(s, T, k)
        rec["p6"].append(e["p_gt"])
        rec["med6"].append(e["median"])
        rec["mean6"].append(e["mean"])
        rec["legal_frac"].append((s > 0).mean())
        rec["p1"].append((s > T).mean())
        rec["mean_all"].append(s.mean())
    return {k_: (float(np.percentile(v, 2.5)), float(np.percentile(v, 97.5))) for k_, v in rec.items()}


def report(label, marks, T=T_DEFAULT, k=K_DEFAULT, draws=20000, boot=2000, quiet=False):
    s = summary(marks, T)
    mc = compete_mc(marks, T, k, draws)
    ex = compete_exact(marks, T, k)
    bs = bootstrap(marks, T, k, boot) if boot else None
    if not quiet:
        print("== %s: n %d  (LABELLED beyond-human body, unlimited run-up, best of %d, T = %.2f m)" % (label, s["n"], k, T))
        print("   per attempt: legal %d (%.1f %%)  legal mean %.3f median %.3f p90 %.3f max %.3f  |  P(mark > T) %.2f %% (%d)  |  mean over all starts (illegal = 0) %.3f"
              % (s["legal"], 100 * s["legal_frac"], s["legal_mean"], s["legal_median"], s["legal_p90"], s["legal_max"], 100 * s["p_gt"], s["n_gt"], s["mean_all"]))
        line = "   COMPETITION (resampling %d x %d without replacement): P(best of %d > T) %.1f %%  median best %.3f  mean best %.3f   [exact: %.1f %%  %.3f  %.3f]" % (
            draws, k, k, 100 * mc["p_gt"], mc["median"], mc["mean"], 100 * ex["p_gt"], ex["median"], ex["mean"])
        print(line)
        if bs:
            print("   bootstrap 95 %% over starts (%d): P(best of %d > T) [%.1f, %.1f] %%  median best [%.3f, %.3f]  mean best [%.3f, %.3f]  legal [%.1f, %.1f] %%  per-attempt P(>T) [%.2f, %.2f] %%  mean all [%.3f, %.3f]" % (
                boot, k, 100 * bs["p6"][0], 100 * bs["p6"][1], bs["med6"][0], bs["med6"][1], bs["mean6"][0], bs["mean6"][1],
                100 * bs["legal_frac"][0], 100 * bs["legal_frac"][1], 100 * bs["p1"][0], 100 * bs["p1"][1], bs["mean_all"][0], bs["mean_all"][1]))
        tails = [8.0, 8.5, 8.75, 8.95, 9.2, 9.5]
        print("   tail counts (marks above): " + "  ".join("%.2f: %d" % (t, int((marks > t).sum())) for t in tails))
    return {"summary": s, "mc": mc, "exact": ex, "boot": bs}


def paired(label_a, ma, label_b, mb, T=T_DEFAULT, k=K_DEFAULT, B=2000, seed=62):
    """paired bootstrap over the shared starts: A - B for the mean mark, per-attempt P(>T), P(best of k > T), mean best-of-k."""
    rng = np.random.default_rng(seed)
    n = len(ma)
    d = {"mean_all": [], "p1": [], "p6": [], "mean6": [], "legal": []}
    for _ in range(B):
        ix = rng.integers(0, n, n)
        a, b = ma[ix], mb[ix]
        ea, eb = compete_exact(a, T, k), compete_exact(b, T, k)
        d["mean_all"].append(a.mean() - b.mean())
        d["p1"].append((a > T).mean() - (b > T).mean())
        d["p6"].append(ea["p_gt"] - eb["p_gt"])
        d["mean6"].append(ea["mean"] - eb["mean"])
        d["legal"].append((a > 0).mean() - (b > 0).mean())
    ea, eb = compete_exact(ma, T, k), compete_exact(mb, T, k)
    pt = {"mean_all": ma.mean() - mb.mean(), "p1": (ma > T).mean() - (mb > T).mean(), "p6": ea["p_gt"] - eb["p_gt"],
          "mean6": ea["mean"] - eb["mean"], "legal": (ma > 0).mean() - (mb > 0).mean()}
    print("-- paired %s - %s on %d shared starts (bootstrap 95 %% interval):" % (label_a, label_b, n))
    for key, name, scale in (("mean_all", "mean mark", 1), ("legal", "legal fraction", 100), ("p1", "per-attempt P(>T)", 100), ("p6", "P(best of %d > T)" % k, 100), ("mean6", "mean best of %d" % k, 1)):
        lo, hi = np.percentile(d[key], [2.5, 97.5])
        print("   %-22s %+8.3f  [%+.3f, %+.3f]%s" % (name, scale * pt[key], scale * lo, scale * hi, " %" if scale == 100 else " m"))
    return pt


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+")
    ap.add_argument("--T", type=float, default=T_DEFAULT)
    ap.add_argument("--k", type=int, default=K_DEFAULT)
    ap.add_argument("--draws", type=int, default=20000)
    ap.add_argument("--boot", type=int, default=2000)
    ap.add_argument("--seeds", default="")
    ap.add_argument("--label", default="")
    ap.add_argument("--vs", default="", help="comma list of files of a second candidate: paired comparison")
    a = ap.parse_args()
    seeds, marks, rows = restrict(*load(a.files), a.seeds)
    label = a.label or ",".join(a.files)
    report(label, marks, a.T, a.k, a.draws, a.boot)
    if a.vs:
        s2, m2, r2 = restrict(*load(a.vs.split(",")), a.seeds)
        common = [s for s in seeds if s in set(s2)]
        ia = {s: i for i, s in enumerate(seeds)}
        ib = {s: i for i, s in enumerate(s2)}
        ma = np.array([marks[ia[s]] for s in common])
        mb = np.array([m2[ib[s]] for s in common])
        paired(a.label or "A", ma, "B", mb, a.T, a.k, max(200, a.boot))


if __name__ == "__main__":
    main()
