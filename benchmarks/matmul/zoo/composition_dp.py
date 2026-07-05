"""Composition DP over the mod-2 matmul record table.

Closes a table of best-known GF(2) ranks under the classical composition
rules, looking for assemblies that beat published search results:
  perm      R(n,m,p) invariant under all 6 permutations
  monotone  R(n,m,p) <= R(n',m',p')   for n<=n', m<=m', p<=p'  (embedding)
  split     R(n1+n2,m,p) <= R(n1,m,p) + R(n2,m,p)   (and each coordinate)
  kron      R(n1*n2, m1*m2, p1*p2) <= R1 * R2

Seeds are PRIMITIVES only (published search/construction results, not
compositions), so any DP entry that undercuts a published number is a
genuine composition find. Run: python3 composition_dp.py [maxdim]
"""
import itertools
import sys

# Primitive seeds: (n,m,p) sorted -> (rank, source). Mod-2-valid only.
# Integer-coefficient schemes reduce mod 2, so classical entries qualify.
PRIMITIVES = {
    (2, 2, 2): (7, "verified table 2026-07-05"),
    (2, 2, 3): (11, "verified table 2026-07-05"),
    (2, 2, 4): (14, "verified table 2026-07-05"),
    (2, 2, 5): (18, "verified table 2026-07-05"),
    (2, 2, 6): (21, "verified table 2026-07-05"),
    (2, 2, 7): (25, "verified table 2026-07-05"),
    (2, 3, 3): (15, "verified table 2026-07-05"),
    (2, 3, 4): (20, "verified table 2026-07-05"),
    (2, 3, 5): (25, "verified table 2026-07-05"),
    (2, 3, 6): (30, "verified table 2026-07-05"),
    (2, 3, 7): (35, "verified table 2026-07-05"),
    (2, 4, 4): (26, "verified table 2026-07-05"),
    (2, 4, 5): (33, "verified table 2026-07-05"),
    (2, 4, 6): (39, "verified table 2026-07-05"),
    (2, 4, 7): (45, "verified table 2026-07-05"),
    (2, 5, 5): (40, "verified table 2026-07-05"),
    (2, 5, 6): (47, "verified table 2026-07-05"),
    (2, 5, 7): (55, "verified table 2026-07-05"),
    (2, 6, 6): (56, "verified table 2026-07-05"),
    (2, 6, 7): (66, "verified table 2026-07-05"),
    (2, 7, 7): (76, "verified table 2026-07-05"),
    (3, 3, 3): (23, "verified table 2026-07-05"),
    (3, 3, 4): (29, "verified table 2026-07-05"),
    (3, 3, 5): (36, "verified table 2026-07-05"),
    (3, 3, 6): (42, "verified table 2026-07-05"),
    (3, 3, 7): (49, "verified table 2026-07-05"),
    (3, 4, 4): (38, "verified table 2026-07-05"),
    (3, 4, 5): (47, "verified table 2026-07-05"),
    (3, 4, 6): (54, "verified table 2026-07-05"),
    (3, 4, 7): (64, "verified table 2026-07-05"),
    (3, 5, 5): (58, "verified table 2026-07-05"),
    (3, 5, 6): (68, "verified table 2026-07-05"),
    (3, 5, 7): (79, "verified table 2026-07-05"),
    (3, 6, 6): (83, "verified table 2026-07-05"),
    (3, 6, 7): (96, "verified table 2026-07-05"),
    (3, 7, 7): (111, "verified table 2026-07-05"),
    (4, 4, 4): (47, "verified table 2026-07-05"),
    (4, 4, 5): (61, "verified table 2026-07-05"),
    (4, 4, 6): (73, "verified table 2026-07-05"),
    (4, 4, 7): (85, "verified table 2026-07-05"),
    (4, 4, 8): (94, "verified table 2026-07-05"),
    (4, 5, 5): (76, "verified table 2026-07-05"),
    (4, 5, 6): (89, "verified table 2026-07-05"),
    (4, 5, 7): (104, "verified table 2026-07-05"),
    (4, 6, 6): (105, "verified table 2026-07-05"),
    (4, 6, 7): (123, "verified table 2026-07-05"),
    (4, 7, 7): (144, "verified table 2026-07-05"),
    (5, 5, 5): (93, "verified table 2026-07-05"),
    (5, 5, 6): (110, "verified table 2026-07-05"),
    (5, 5, 7): (127, "verified table 2026-07-05"),
    (5, 6, 6): (130, "verified table 2026-07-05"),
    (5, 6, 7): (150, "verified table 2026-07-05"),
    (5, 7, 7): (176, "verified table 2026-07-05"),
    (6, 6, 6): (153, "verified table 2026-07-05"),
    (6, 6, 7): (183, "verified table 2026-07-05"),
    (6, 7, 7): (212, "verified table 2026-07-05"),
    (7, 7, 7): (248, "verified table 2026-07-05"),
    (7, 7, 8): (273, "verified table 2026-07-05"),
    (7, 7, 9): (313, "verified table 2026-07-05"),
    (7, 8, 8): (302, "verified table 2026-07-05"),
    (8, 8, 8): (329, "verified table 2026-07-05"),
    (8, 8, 9): (391, "verified table 2026-07-05"),
    (8, 9, 9): (432, "verified table 2026-07-05"),
    (9, 9, 9): (486, "verified table 2026-07-05"),
}


def close(maxdim=9):
    R = {}
    src = {}

    def key(t):
        return tuple(sorted(t))

    def improve(t, val, why):
        t = key(t)
        if val < R.get(t, 10 ** 9):
            R[t] = val
            src[t] = why
            return True
        return False

    dims = [t for t in itertools.combinations_with_replacement(range(1, maxdim + 1), 3)]
    for t in dims:
        n, m, p = t
        improve(t, n * m * p, "naive")
    for t, (v, s) in PRIMITIVES.items():
        improve(t, v, f"primitive: {s}")

    changed = True
    rounds = 0
    while changed and rounds < 40:
        changed = False
        rounds += 1
        for t in dims:
            n, m, p = t
            cur = R[t]
            # monotone embedding from any smaller-or-equal triple is implied
            # by split with naive padding; keep explicit for tightness:
            # (handled by split below since R includes all triples)
            # split on each coordinate of each permutation
            for perm in set(itertools.permutations(t)):
                a, b, c = perm
                for a1 in range(1, a // 2 + 1):
                    v = R[key((a1, b, c))] + R[key((a - a1, b, c))]
                    if v < cur:
                        if improve(t, v, f"split {a1}+{a-a1} of {a} in {perm}"):
                            cur = v
                            changed = True
            # kronecker
            for perm in set(itertools.permutations(t)):
                a, b, c = perm
                for a1 in range(2, a + 1):
                    if a % a1: continue
                    for b1 in range(1, b + 1):
                        if b % b1: continue
                        for c1 in range(1, c + 1):
                            if c % c1: continue
                            if (a1, b1, c1) == perm or (a1, b1, c1) == (1, 1, 1):
                                continue
                            v = R[key((a1, b1, c1))] * R[key((a // a1, b // b1, c // c1))]
                            if v < cur:
                                if improve(t, v, f"kron ({a1},{b1},{c1})x({a//a1},{b//b1},{c//c1})"):
                                    cur = v
                                    changed = True
    return R, src, rounds


def main():
    maxdim = int(sys.argv[1]) if len(sys.argv) > 1 else 9
    R, src, rounds = close(maxdim)
    print(f"closure in {rounds} rounds over dims<={maxdim}\n")
    print("--- vs primitives (DP < published would be a composition find) ---")
    for t, (v, s) in sorted(PRIMITIVES.items()):
        d = R[t]
        flag = "  <<< COMPOSITION BEATS PUBLISHED" if d < v else ""
        print(f"{t}: published={v}  dp={d}  via {src[t]}{flag}")
    print("\n--- full table (n<=m<=p<=7), derivation ---")
    for t in sorted(R):
        if t[2] <= 7:
            print(f"{t}: {R[t]}  [{src[t]}]")


if __name__ == "__main__":
    main()
