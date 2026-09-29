# Composition utility of three alternative tensors

The ten-minute alternative-search campaign produced rank ties, not primitive
rank improvements. The three newly distinct tensors were:

| Tensor | Rank | Approach |
|---|---:|---|
| 2x4x5 | 33 | Numerical ALS plus exact GF(2) repair |
| 4x4x5 | 60 | Numerical ALS plus exact GF(2) repair |
| 5x5x5 | 93 | Python tabled finite-domain logic, not SWI-Prolog |

Their candidate SHA256 values, respectively:

- `542382ac289ae32445843418a92812fd84fc324337551e390b8aeb7625f27635`
- `127d325105bd264a13dcee881f08c2e1e2cb2c56fbe33e5e1cfe7624b8bd8483`
- `f120180868f9b31fe7484f74dcc8d8285ebf02a844624041046f12f5a583cd2d`

## Matched screen

All integral scale triples producing dimensions at most 32 were tested, except
the original unscaled parent. Old and new parents received identical bounded
shared-factor/grid packing budgets, recursive block/Kronecker leaves from the
curated GF(2) seed directory, and exact shared-factor matrix cleanup. Full
tensors, not formula prices alone, were checked for every row. Packing is
bounded (two seconds, 10,000 states, 20,000 candidates, 24-vertex components,
grid sides at most three); this is not unrestricted composition optimization.

| Parent | Matched scales | New cheaper than old | New cheaper than old and library |
|---|---:|---:|---:|
| 2x4x5 | 767 | 235 | 8 |
| 4x4x5 | 383 | 0 | 0 |
| 5x5x5 | 215 | 57 | 22 |

The 1,365 rows have 2,730 full-tensor checks. They cover 615 shapes after axis
permutation deduplication. Comparing the best new construction against BOTH
the curated library and every tested old-parent orientation leaves 11 distinct
local improvements, six from 2x4x5 and five from 5x5x5:

| Canonical shape | Previous local comparison | New | Parent |
|---|---:|---:|---|
| 12x14x25 | 2599 | 2591 | 2x4x5 |
| 8x10x30 | 1547 | 1543 | 2x4x5 |
| 30x30x30 | 14225 | 14221 | 5x5x5 |
| 4x12x25 | 822 | 819 | 2x4x5 |
| 8x12x30 | 1779 | 1776 | 2x4x5 |
| 20x25x25 | 7047 | 7044 | 5x5x5 |
| 4x8x30 | 691 | 689 | 2x4x5 |
| 10x10x20 | 1300 | 1298 | 5x5x5 |
| 10x10x25 | 1645 | 1643 | 5x5x5 |
| 10x15x25 | 2298 | 2297 | 5x5x5 |
| 10x20x20 | 2501 | 2500 | 2x4x5 |

Every final winning tensor was additionally checked by an independent Python
full-tensor verifier. Input/library hashes were rechecked; recipes include
materialized leaves. The 4x4x5 alternative provides no improvement over its
parent in this screen, even though some constructions from BOTH representations
beat the simple recursive library. Those are not new-candidate gains.

These are local comparison gains, NOT world-record claims. No fresh external
record comparison, seed admission, or reference update was performed. Counts
must not be added to primitive-decomposition record counts.

## Evidence

- Combined source-pinned audit and all 11 witness paths:
  `/tmp/metaflip-compose-combined-audit-20260914.json`.
- Full paired reports/recipes: `/tmp/metaflip-{2x4x5,4x4x5,5x5x5}-compose32-20260914/`.
- Campaign originals: `/tmp/metaflip-extended-v3-20260913/inputs/`.
- New candidates: `/tmp/metaflip-extended-v4-600s-bounded-20260913/jobs/`.

Large artifacts remain outside the repository. All bounded composition runs
finished; no background search was left running by this audit.
