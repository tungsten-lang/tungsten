"""Direct-sum two schemes along the n axis (block rows of A and C):
<n1,m,p> (+) <n2,m,p> -> <n1+n2,m,p>. Exact-validates the result.

Usage: python3 stack.py <seed1> <n1> <seed2> <n2> <m> <p>   (mask-seed files)
Emits combined seed block on stdout.
"""
import sys

from metaflip_proto2 import T, recon
from seed_prep import parse_terms, remap


def main():
    f1, n1, f2, n2, m, p = (sys.argv[1], int(sys.argv[2]), sys.argv[3],
                            int(sys.argv[4]), int(sys.argv[5]), int(sys.argv[6]))
    s1 = parse_terms(f1)[0]
    s2 = parse_terms(f2)[0]
    n = n1 + n2
    out = []
    for u, v, w in s1:
        out.append((remap(u, n1, m, lambda i, j: i * m + j),
                    v,
                    remap(w, n1, p, lambda i, k: i * p + k)))
    for u, v, w in s2:
        out.append((remap(u, n2, m, lambda i, j: (i + n1) * m + j),
                    v,
                    remap(w, n2, p, lambda i, k: (i + n1) * p + k)))
    S = set()
    for t in out:
        S.discard(t) if t in S else S.add(t)
    valid = recon(S, n, m, p) == T(n, m, p)
    print(f"stacked <{n},{m},{p}> rank={len(S)} valid={valid}", file=sys.stderr)
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
