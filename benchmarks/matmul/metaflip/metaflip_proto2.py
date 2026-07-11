"""Meta-flip prototype, layer 3 core: RECTANGULAR formats + cross-format edges.
Format (n,m,p): A is n*m, B is m*p, C is n*p.
  u-mask over A entries (i,j)->i*m+j ; v over B (j,k)->j*p+k ; w over C (i,k)->i*p+k.
  matmul tensor T = {(i*m+j, j*p+k, i*p+k)}.
Edges: extension (p->p+1, append n*m naive column terms) and projection (p->p-1, zero last col).
"""
def naive(n, m, p):
    return set((1 << (i*m+j), 1 << (j*p+k), 1 << (i*p+k))
               for i in range(n) for j in range(m) for k in range(p))
def T(n, m, p):
    return set((i*m+j, j*p+k, i*p+k) for i in range(n) for j in range(m) for k in range(p))
def recon(S, n, m, p):
    AU, BV, CW = n*m, m*p, n*p
    acc = {}
    for u, v, w in S:
        bu = [x for x in range(AU) if (u >> x) & 1]
        bv = [x for x in range(BV) if (v >> x) & 1]
        bw = [x for x in range(CW) if (w >> x) & 1]
        for a in bu:
            for b in bv:
                for c in bw:
                    acc[(a, b, c)] = acc.get((a, b, c), 0) ^ 1
    return set(k for k, x in acc.items() if x)

def widen_cols(mask, rows, oldc, newc):   # rows x oldc  ->  rows x newc (newc>=oldc), same entries
    r = 0
    for b in range(rows*oldc):
        if (mask >> b) & 1:
            i, c = divmod(b, oldc)
            r |= 1 << (i*newc + c)
    return r
def drop_last_col(mask, rows, oldc):       # rows x oldc -> rows x (oldc-1), kill column (oldc-1)
    r = 0
    for b in range(rows*oldc):
        if (mask >> b) & 1:
            i, c = divmod(b, oldc)
            if c == oldc-1:
                continue
            r |= 1 << (i*(oldc-1) + c)
    return r

def extend(S, n, m, p):                    # (n,m,p) -> (n,m,p+1)
    out = set()
    for u, v, w in S:                      # re-index existing terms into the wider B,C
        out_add(out, (u, widen_cols(v, m, p, p+1), widen_cols(w, n, p, p+1)))
    for i in range(n):                     # append naive terms computing the new column (index p)
        for j in range(m):
            out_add(out, (1 << (i*m+j), 1 << (j*(p+1)+p), 1 << (i*(p+1)+p)))
    return out
def project(S, n, m, p):                   # (n,m,p) -> (n,m,p-1): zero last B-col, drop last C-col
    out = set()
    for u, v, w in S:
        v2 = drop_last_col(v, m, p)
        w2 = drop_last_col(w, n, p)
        if u and v2 and w2:                # drop terms that vanish under the projection
            out_add(out, (u, v2, w2))
    return out
def out_add(S, t):                         # XOR-toggle (reduction) into a building set
    if not (t[0] and t[1] and t[2]): return
    S.discard(t) if t in S else S.add(t)

def load_555_93():
    import os
    import re
    us = {}; vs = {}; ws = {}
    path = os.path.join(os.path.dirname(__file__), "..", "search", "seed_mp93.txt")
    for line in open(path):
        mm = re.match(r'(us|vs|ws)\[(\d+)\] = (\d+)', line)
        if mm: {'us': us, 'vs': vs, 'ws': ws}[mm.group(1)][int(mm.group(2))] = int(mm.group(3))
    return set((us[r], vs[r], ws[r]) for r in range(len(us)))

if __name__ == "__main__":
    ok = lambda S, n, m, q: recon(S, n, m, q) == T(n, m, q)
    print("=== rectangular base + cross-format edges ===")
    nv = naive(5, 5, 5)
    print(f"naive(5,5,5) rank={len(nv)} valid={ok(nv,5,5,5)}")
    e = extend(nv, 5, 5, 5)
    print(f"extend ->(5,5,6) rank={len(e)} valid={ok(e,5,5,6)}  (expect rank 125+25=150)")
    pr = project(e, 5, 5, 6)
    print(f"project->(5,5,5) rank={len(pr)} valid={ok(pr,5,5,5)}")
    print("=== on the real MP-93 record scheme ===")
    s93 = load_555_93()
    print(f"MP-93 rank={len(s93)} valid={ok(s93,5,5,5)}")
    e93 = extend(s93, 5, 5, 5)
    print(f"extend ->(5,5,6) rank={len(e93)} valid={ok(e93,5,5,6)}  (expect 93+25=118)")
    p93 = project(e93, 5, 5, 6)
    print(f"project->(5,5,5) rank={len(p93)} valid={ok(p93,5,5,5)}  (round-trip back to (5,5,5))")
