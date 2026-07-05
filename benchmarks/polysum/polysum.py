"""Polynomial ranged-sum benchmark — multi-term polynomials (Python, BigInt).

Python's int is arbitrary-precision, so this computes the CORRECT values
(unlike the fixed-width systems languages) — but it must iterate every
element of every rep-shifted range, O(N·REPS) per polynomial. It is the
correctness reference and the "exact but O(n)" contrast to Tungsten's
closed form.

N/REPS from argv (defaults 1_000_000 / 100), matching every language.
"""

import sys

N = int(sys.argv[1]) if len(sys.argv) > 1 else 1_000_000
REPS = int(sys.argv[2]) if len(sys.argv) > 2 else 100

t1 = t2 = t3 = t7 = t20 = 0
for r in range(REPS):
    lo, hi = 1 + r, N + r
    for x in range(lo, hi + 1):
        t1 += 2 * x + 3
        t2 += 5 * x ** 2 - 3 * x + 1
        t3 += 4 * x ** 3 - 2 * x ** 2 + 7 * x - 5
        t7 += 92 * x ** 7 + 13 * x ** 3 - 5 * x + 8
        t20 += x ** 20 + 17 * x ** 13 - 4 * x ** 5 + 2 * x + 9

print(t1)
print(t2)
print(t3)
print(t7)
print(t20)
