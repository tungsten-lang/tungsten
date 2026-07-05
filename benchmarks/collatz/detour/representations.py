#!/usr/bin/env python3
"""Reproduces the computational facts in representations.md.

Each block prints the numbers cited there, so every claim is checkable:
  python3 representations.py
"""
import math
from collections import Counter, defaultdict
from fractions import Fraction as F


def step(n):                      # full Collatz map
    return n // 2 if n % 2 == 0 else 3 * n + 1


def steps_to_1(n):
    c = 0
    while n != 1:
        n = step(n); c += 1
    return c


def parities(n, k):               # first k parities (full map)
    out = []
    for _ in range(k):
        out.append(n & 1); n = step(n)
    return tuple(out)


print("== (3) symbolic affine forms: x+1 is unreachable ==")
# forms (coeff,const) under A: n->2n, B: n->(n-1)/3; reachable coeffs are 2^a/3^b
forms = {(F(1), F(0))}; frontier = [(F(1), F(0))]
for _ in range(8):
    nxt = []
    for c, d in frontier:
        for g in ((2 * c, 2 * d), (c / 3, (d - 1) / 3)):
            if g not in forms:
                forms.add(g); nxt.append(g)
    frontier = nxt
print("   forms with coeff 1:", sorted(f for f in forms if f[0] == 1),
      "-> x+1=(1,1) reachable:", (F(1), F(1)) in forms)

print("== (7) Collatz respects only the prime 2 ==")
print("   x2 chain (clean):", [steps_to_1(7 * 2**i) for i in range(4)], "(each +1)")
print("   odd-prime x:", {f"x{p}": steps_to_1(p * 7) for p in (3, 5, 7, 11)}, "(no pattern)")
print("   products:", {f"{a}*{b}": steps_to_1(a * b) for a, b in [(5, 7), (5, 11), (7, 11)]})

print("== (8a) parity dynamics is the golden-mean subshift (no two consecutive odd) ==")
fib = [0, 1]
while len(fib) < 30:
    fib.append(fib[-1] + fib[-2])
for k in (8, 12, 16):
    distinct = len({parities(r, k) for r in range(1 << k)})
    print(f"   k={k}: {distinct} distinct k-step behaviors = F({k+2})={fib[k+2]}  ->  {distinct==fib[k+2]}")

print("== (8b) residue tower -> 2-adic; the climber -1 survives at every level ==")
def T(n):                          # shortcut map, for the Terras bijection
    return (3 * n + 1) // 2 if n % 2 else n // 2
def pv(n, k):
    v = []
    for _ in range(k):
        v.append(n & 1); n = T(n)
    return tuple(v)
for k in (8, 10, 12):
    print(f"   mod 2^{k}: bijection residue<->parities:",
          len({pv(r, k) for r in range(1 << k)}) == (1 << k))
for k in (5, 10, 20):
    n = (1 << k) - 1
    print(f"   2^{k}-1 = {n} (= -1 mod 2^{k}) climbs all {k} steps:", all(pv(n, k)))

print("== (8c) Syracuse: the whole conjecture is one inequality, avg v2(3m+1) > log2(3) ==")
def v2(n):
    v = 0
    while n % 2 == 0:
        n //= 2; v += 1
    return v
c = Counter(v2(3 * m + 1) for m in range(1, 4_000_000, 2))
tot = sum(c.values())
ev = sum(v * c[v] for v in c) / tot
print("   P(v=j):", {j: round(c[j] / tot, 4) for j in range(1, 6)})
print(f"   E[v] = {ev:.3f}   >   log2(3) = {math.log2(3):.3f}   (gap {ev - math.log2(3):.3f})")
# 27's odd trajectory average, for flavor
m, vs = 27, []
while m != 1:
    t = 3 * m + 1; v = v2(t); vs.append(v); m = t >> v
print(f"   27: {len(vs)} odd-steps, avg v = {sum(vs)/len(vs):.3f} (barely clears 1.585)")

print("== (5) the negatives have disjoint components: 'grow the set' can't cross ==")
def comp(seeds, B=20000):
    seen = set(seeds); fr = list(seeds)
    while fr:
        nx = []
        for n in fr:
            cands = [2 * n]
            if (n - 1) % 3 == 0 and ((n - 1) // 3) % 2:
                cands.append((n - 1) // 3)
            for p in cands:
                if p not in seen and abs(p) <= B:
                    seen.add(p); nx.append(p)
        fr = nx
    return seen
A = comp([-1, -2]); Bc = comp([-5, -14, -7, -20, -10])
print(f"   -1 component ({len(A)} nums) contains -5: {-5 in A};  disjoint from -5 cycle: {A.isdisjoint(Bc)}")
