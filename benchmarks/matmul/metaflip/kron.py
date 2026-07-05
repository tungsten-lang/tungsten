"""Kronecker-compose two schemes: <n1,m1,p1> (x) <n2,m2,p2> -> <n1n2, m1m2, p1p2>.

Each pair of rank-1 terms composes to one term whose factor matrices are the
tensor products of the factor matrices: U[(i1,i2),(j1,j2)] = U1[i1,j1]*U2[i2,j2]
(over GF(2): AND), with row-major index (i1*n2+i2)*(m1*m2) + (j1*m2+j2).
Exact-validates the result.

Usage: python3 kron.py <seed1> <n1> <m1> <p1> <seed2> <n2> <m2> <p2>
"""
import sys

from metaflip_proto2 import T, recon
from seed_prep import parse_terms


def kron_mask(mask1, r1, c1, mask2, r2, c2):
    out = 0
    for b1 in range(r1 * c1):
        if not (mask1 >> b1) & 1:
            continue
        i1, j1 = divmod(b1, c1)
        for b2 in range(r2 * c2):
            if not (mask2 >> b2) & 1:
                continue
            i2, j2 = divmod(b2, c2)
            out |= 1 << ((i1 * r2 + i2) * (c1 * c2) + (j1 * c2 + j2))
    return out


def main():
    f1, n1, m1, p1, f2, n2, m2, p2 = (sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4]),
                                      sys.argv[5], int(sys.argv[6]), int(sys.argv[7]), int(sys.argv[8]))
    s1 = parse_terms(f1)[0]
    s2 = parse_terms(f2)[0]
    n, m, p = n1 * n2, m1 * m2, p1 * p2
    S = set()
    for u1, v1x, w1 in s1:
        for u2, v2x, w2 in s2:
            t = (kron_mask(u1, n1, m1, u2, n2, m2),
                 kron_mask(v1x, m1, p1, v2x, m2, p2),
                 kron_mask(w1, n1, p1, w2, n2, p2))
            S.discard(t) if t in S else S.add(t)
    valid = recon(S, n, m, p) == T(n, m, p)
    print(f"kron <{n},{m},{p}> rank={len(S)} valid={valid}", file=sys.stderr)
    if not valid:
        sys.exit(1)
    terms = sorted(S)
    for k, (u, v, w) in enumerate(terms):
        print(f"us[{k}] = {u}")
    for k, (u, v, w) in enumerate(terms):
        print(f"vs[{k}] = {v}")
    for k, (u, v, w) in enumerate(terms):
        print(f"ws[{k}] = {w}")


if __name__ == "__main__":
    main()
