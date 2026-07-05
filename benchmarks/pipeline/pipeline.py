"""Fused map-filter-reduce pipeline benchmark (Python, generator expression).

A genexpr is lazy and fused — no intermediate lists are built — so this
is Python's best-case shape for the pipeline. It still pays per-element
interpreter overhead, which is the comparison point against Tungsten's
fused native loop.

Each rep uses a shifted range (1+r .. N+r) so the work can't be hoisted.
N/REPS from argv (defaults 1_000_000 / 100), matching every language.
"""

import sys

N = int(sys.argv[1]) if len(sys.argv) > 1 else 1_000_000
REPS = int(sys.argv[2]) if len(sys.argv) > 2 else 100

total = 0
for r in range(REPS):
    total += sum(x * x for x in range(1 + r, N + r + 1) if x % 2 == 0)

print(total)
