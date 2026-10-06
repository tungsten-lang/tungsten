"""Paired comparison of two per-start streak lists.

    .venv/bin/python scratchpad/btl3/paired_test.py a.streaks b.streaks   (lines "seed streak"; b minus a)

Prints the means, the paired mean difference with its standard error and the one-sided sign-flip p-value (mean of d >= observed
under random sign flips of the per-start differences, 400k flips; the arena's test).
"""
import sys
import numpy as np


def load(fn):
    d = {}
    for line in open(fn):
        t = line.split()
        if len(t) >= 2:
            d[int(t[0])] = int(t[1])
    return d


def main():
    a, b = load(sys.argv[1]), load(sys.argv[2])
    seeds = sorted(set(a) & set(b))
    x = np.array([a[s] for s in seeds], float)
    y = np.array([b[s] for s in seeds], float)
    d = y - x
    rng = np.random.default_rng(1)
    obs = d.sum()
    flips = rng.choice([-1.0, 1.0], size=(400000, len(d))) @ d
    p = float((flips >= obs - 1e-9).mean())
    print(f"n {len(d)}  mean a {x.mean():.3f}  mean b {y.mean():.3f}  diff {d.mean():+.3f} (se {d.std(ddof=1) / np.sqrt(len(d)):.3f})  sign-flip p {p:.4f}  "
          f"b>a on {int((d > 0).sum())}, b<a on {int((d < 0).sum())}, ties {int((d == 0).sum())}")


if __name__ == "__main__":
    main()
