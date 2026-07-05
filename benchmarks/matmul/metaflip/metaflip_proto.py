"""Meta-flip-graph prototype — correctness-first scaffold.
Layer 1 (this file): base flip graph (flip / reduction / structured plus), verified.
Layer 2 (TODO, pending spec): symmetric quotient (C3 orbit-moves).
Layer 3 (TODO, pending spec): the meta-flip construction (Kauers-Wood).
A scheme is a set of (u,v,w) int-mask tuples; reduction is automatic via XOR-toggle.
"""
import random

def naive(n): return set((1 << (i*n+k), 1 << (k*n+j), 1 << (i*n+j))
                         for i in range(n) for j in range(n) for k in range(n))
def T(n): return set((i*n+k, k*n+j, i*n+j) for i in range(n) for j in range(n) for k in range(n))

def recon(S, n):
    D = n*n; acc = {}
    for u, v, w in S:
        bu = [x for x in range(D) if (u >> x) & 1]
        bv = [x for x in range(D) if (v >> x) & 1]
        bw = [x for x in range(D) if (w >> x) & 1]
        for a in bu:
            for b in bv:
                for c in bw:
                    acc[(a, b, c)] = acc.get((a, b, c), 0) ^ 1
    return set(k for k, x in acc.items() if x)

def xins(S, t):  # XOR-toggle a term into the set (duplicate->cancel = reduction); drop zero-factor
    if not (t[0] and t[1] and t[2]): return
    S.discard(t) if t in S else S.add(t)

def flip(S):
    terms = list(S); ti = random.choice(terms); ax = random.randrange(3)
    cands = [t for t in terms if t != ti and t[ax] == ti[ax]]
    if not cands: return False
    tj = random.choice(cands); ui, vi, wi = ti; uj, vj, wj = tj
    if ax == 0:   a = (ui, vi, wi ^ wj); b = (ui, vi ^ vj, wj)
    elif ax == 1: a = (ui, vi, wi ^ wj); b = (ui ^ uj, vi, wj)
    else:         a = (ui, vi ^ vj, wi); b = (ui ^ uj, vj, wi)
    for t in (ti, tj, a, b): xins(S, t)
    return True

def plus(S):  # structured: split a term using a factor already in the scheme
    terms = list(S); ti = random.choice(terms); ax = random.randrange(3); sf = ti[ax]
    others = [t[ax] for t in terms if t[ax] != sf and t[ax] != 0]
    if not others: return
    sm = random.choice(others); sf2 = sf ^ sm
    if sf2 == 0: return
    a1 = list(ti); a1[ax] = sm; a2 = list(ti); a2[ax] = sf2
    for t in (ti, tuple(a1), tuple(a2)): xins(S, t)

def walk(n, steps, S0=None, cap=15, plus_every=200):
    S = set(S0) if S0 else naive(n)
    Tn = T(n); assert recon(S, n) == Tn, "seed invalid"
    best = len(S); bestS = set(S)
    for st in range(steps):
        flip(S)
        if st % plus_every == 0: plus(S)
        if len(S) < best:
            assert recon(S, n) == Tn, "INVALID best"
            best = len(S); bestS = set(S)
        if len(S) > best + cap: S = set(bestS)
    return best, bestS

if __name__ == "__main__":
    random.seed(7)
    overall = 99; oS = None
    for r in range(8):
        b, bs = walk(3, 400000)
        if b < overall: overall = b; oS = bs
    print(f"3x3 base flip-graph, 8 restarts x 400k: best rank = {overall}  (record 23)")
    print(f"  tensor-valid: {recon(oS, 3) == T(3)}  all-nonzero: {all(u and v and w for u, v, w in oS)}")
