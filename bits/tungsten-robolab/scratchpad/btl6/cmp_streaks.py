"""Paired comparison of per-start streak files, optionally restricted to a seed subset.
    scratchpad/btl6/py scratchpad/btl6/cmp_streaks.py base.streaks cand.streaks [train|val|all|lo:hi]   (train/val = the fits' split: (seed - 84001) % 10 < 7 / >= 7)"""
import sys
import numpy as np
def load(f): return {int(a): int(b) for a, b in (l.split() for l in open(f) if l.strip())}
b, c = load(sys.argv[1]), load(sys.argv[2])
sub = sys.argv[3] if len(sys.argv) > 3 else "all"
ks = sorted(set(b) & set(c))
if sub == "train": ks = [k for k in ks if (k - 84001) % 10 < 7]
elif sub == "val": ks = [k for k in ks if (k - 84001) % 10 >= 7]
elif ":" in sub:
    lo, hi = (int(x) for x in sub.split(":")); ks = [k for k in ks if lo <= k < hi]
x0 = np.array([b[k] for k in ks], float); x1 = np.array([c[k] for k in ks], float); d = x1 - x0
rng = np.random.default_rng(1); fl = rng.choice([-1.0, 1.0], size=(20000, len(d))); p = float((np.abs((fl * d).mean(1)) >= abs(d.mean()) - 1e-12).mean())
print(f"{sub}: n {len(ks)} base {x0.mean():.3f} cand {x1.mean():.3f} diff {d.mean():+.3f} (se {d.std(ddof=1)/np.sqrt(len(d)):.3f}, sign-flip p {p:.4f}) better {(d>0).sum()} worse {(d<0).sum()} ties {(d==0).sum()}  >=3 {(x0>=3).sum()}->{(x1>=3).sum()} >=4 {(x0>=4).sum()}->{(x1>=4).sum()} >=5 {(x0>=5).sum()}->{(x1>=5).sum()}")
