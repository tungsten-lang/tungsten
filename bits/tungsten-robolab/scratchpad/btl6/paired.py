"""Paired comparison of two per-start streak files ("seed streak" lines): mean difference, se, sign-flip p, better/worse/ties.
    scratchpad/btl5/py scratchpad/btl5/paired.py base.streaks cand.streaks [...more cands]"""
import sys
import numpy as np

def load(f):
    return {int(a): int(b) for a, b in (l.split() for l in open(f) if l.strip())}

base = load(sys.argv[1])
for cf in sys.argv[2:]:
    c = load(cf)
    ks = sorted(set(base) & set(c))
    b = np.array([base[k] for k in ks], float); x = np.array([c[k] for k in ks], float)
    d = x - b
    rng = np.random.default_rng(1)
    flips = rng.choice([-1.0, 1.0], size=(20000, len(d)))
    pm = np.abs((flips * d).mean(1))
    p = float((pm >= abs(d.mean()) - 1e-12).mean())
    print(f"{cf}: n {len(ks)} base {b.mean():.3f} cand {x.mean():.3f} diff {d.mean():+.3f} (se {d.std(ddof=1)/np.sqrt(len(d)):.3f}, sign-flip p {p:.4f}) better {(d>0).sum()} worse {(d<0).sum()} ties {(d==0).sum()}  >=3 {(b>=3).sum()}->{(x>=3).sum()} >=4 {(b>=4).sum()}->{(x>=4).sum()} >=5 {(b>=5).sum()}->{(x>=5).sum()}")
