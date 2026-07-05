#!/usr/bin/env python3
"""Reproduces every number in reach.md — the refined cycle-minimum bound and the true reach.

  python3 reach.py

Cross-checks the corpus bound M(a) against proof.md, then computes the v1=1 / v2<=2
refinement M''(a) = M(a)/(3/2)^2 and the largest odd-step cutoff excludable under the
published Collatz verification frontiers.  Exact bignum throughout (Python ints); D is
found by integer comparison, never floats.
"""
import math


def D_of(a, p3):
    """Smallest d with 2^d > 3^a  (= ceil(a*log2 3), never integral)."""
    d, pw = 0, 1
    while pw <= p3:
        pw <<= 1
        d += 1
    return d, pw                      # pw = 2^D


def bounds(a):
    """Return (D, Q, M, M', M'') as exact integers."""
    p3 = 3 ** a
    D, pw = D_of(a, p3)
    Q = pw - p3                        # 2^D - 3^a  >= 1
    cmax = p3 // 3                      # i=1 term 3^{a-1}
    for i in range(2, a + 1):          # i=2..a: 3^{a-i} 2^{D-a+i-1}, decreasing in i
        cmax += 3 ** (a - i) * (1 << (D - a + i - 1))
    cmax1 = cmax
    if a >= 2:                         # v1=1: i=2 term 3^{a-2}2^{D-a+1} -> 3^{a-2}*2
        cmax1 -= 3 ** (a - 2) * ((1 << (D - a + 1)) - 2)
    cmax2 = cmax1
    if a >= 3:                         # v2<=2: i=3 term 3^{a-3}2^{D-a+2} -> 3^{a-3}*8
        cmax2 -= 3 ** (a - 3) * ((1 << (D - a + 2)) - 8)
    return D, Q, cmax // Q, cmax1 // Q, cmax2 // Q


# frontiers
B_OURS = 4_500_000_000_000            # proof.md certificate, 4.5e12
B_2021 = 1 << 68                      # Barina 2021 (published)
B_2025 = 1 << 71                      # Barina 2025 (live, 2025-01-15)


def reach(idx, B):
    """Largest A whose running-max bound (index 2=M,3=M',4=M'') stays < B."""
    rm, A = 0, 0
    for a in range(1, 600):
        rm = max(rm, bounds(a)[idx])
        if rm < B:
            A = a
        else:
            return A
    return A


def wall(idx, B):
    rm = 0
    for a in range(1, 600):
        rm = max(rm, bounds(a)[idx])
        if rm >= B:
            return a


print("== cross-check M(a) against proof.md ==")
known = {67: 977094711835, 68: 4394687298972, 69: 2638021326111, 70: 39461763431316}
for a in sorted(known):
    _, _, M, _, M2 = bounds(a)
    print(f"   a={a}: M={M}  proof.md={known[a]}  match={M == known[a]}   M''={M2}  (M/M''={M / M2:.3f})")

print("\n== reach: largest odd-step cutoff A with running-max bound < frontier B ==")
print(f"   {'frontier B':34s}{'M (corpus)':>12s}{'M'' (refined)':>16s}")
for name, B in (("our certificate  4.5e12", B_OURS),
                ("Barina 2021  2^68 (published)", B_2021),
                ("Barina 2025  2^71 (live)", B_2025)):
    print(f"   {name:34s}{'a<=' + str(reach(2, B)):>12s}{'a<=' + str(reach(4, B)):>16s}")

print("\n== structural wall: first a whose running-max bound exceeds the frontier ==")
for name, B in (("2^68", B_2021), ("2^71", B_2025)):
    print(f"   B={name}:  corpus M -> wall at a={wall(2, B)},  refined M'' -> wall at a={wall(4, B)}")

_, _, _, _, M2_306 = bounds(306)
print(f"\n== the deep convergent a=306 is out of computational reach forever ==")
print(f"   M''(306) = {M2_306}")
print(f"            ~ 2^{math.log2(M2_306):.0f} ~ 10^{math.log10(M2_306):.0f}  -> would need Collatz verified that far")
print("   => general case needs an effective bound on |2^d - 3^a| (Baker/Rhin), not compute.")

print("\n== refinement is a clean (3/2)^2 shrink (geometric mean over a=40..130) ==")
r1 = [bounds(a)[2] / bounds(a)[3] for a in range(40, 131)]
r2 = [bounds(a)[2] / bounds(a)[4] for a in range(40, 131)]
gm = lambda xs: math.exp(sum(map(math.log, xs)) / len(xs))
print(f"   M/M'  = {gm(r1):.3f}  (v1=1),   M/M'' = {gm(r2):.3f}  (v1=1 & v2<=2) ~ (3/2)^2 = 2.25")
