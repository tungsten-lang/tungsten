# Projective-plane quadrilateral tunnel

Status: exact move-lab operator, **not scheduled** in the CPU or GPU pools.

## Identity

Fix one tensor axis and let its live factors lie in the seven nonzero points
of a three-dimensional GF(2) span. Write the maximal subtotal as

```text
T = sum(p tensor A_p),    p in F_2^3 - {0},
```

where each `A_p` is a matrix in the combined spans of the other two factors.
The complement of every Fano line is a four-point circuit `C`, so
`xor(p for p in C) = 0`. For any complementary matrix `D`, toggling `D` in all
four buckets preserves the tensor exactly:

```text
A'_p = A_p + D  if p in C,
A'_p = A_p      otherwise.
```

The new local CP cost is `sum_p rank(A'_p)`. Thus each circuit is a
rank-metric four-median problem, the projective-plane analogue of the
three-bucket matrix-pencil line objective.

`flipfleet_projective_plane.w` canonicalizes the seven points, captures the
maximal plane subtotal, builds exact complementary coordinates, optimizes all
seven circuits, minimally factors the resulting matrices, and exhaustively
compares every local tensor coefficient. `ffmp_splice_state` then
parity-compacts external collisions and performs the full `n^6`
matrix-multiplication gate.

For at most `max_cells` complementary coordinates, every `D` is exhausted.
Larger planes use a regular exact candidate family containing every live
bucket matrix, every XOR of two buckets, and every rank-one matrix in the
combined spans. This fallback is admission-sound but not
optimization-complete.

## Coverage boundary

The planted five-term subtotal has a direct exact 5->4 quadrilateral drop.
All ten 3-term subsets and all five 4-term subsets were exhaustively checked:
the existing complete span lane found zero 3->2 or 4->3 reductions. All seven
projective lines were also exhausted; no line-pencil reduced rank and the
largest line contained only three terms. A separate rank-11 Strassen shoulder
closes to rank seven and passes the complete tensor gate. Corrupting one
output factor is rejected.

This proves that the atomic move is outside one span-4 refactor and outside
one projective-line pencil move. It is **not** a new algebraic component:
viewed along the fixed axis it remains a structured change of a flattening
factorization. The shipped depth-four/beam-32 flatten-gauge search already
finds a rank drop on the tiny plant in two orientations. The projective
operator's contribution is complete structured optimization over `D`, not a
proof of disconnection from arbitrary `GL(k,2)` gauge words.

## Real-frontier audit

The widest bounded audit used the first 32 distinct factors on each axis,
canonicalized every independent triple, and capped accepted groups at 2,048
per tensor. It considered 110,181 distinct planes, found 5,450 maximal
subtotals with at least five terms, optimized 5,439 of them, rejected seven
whose complementary rank exceeded the structured bound, and left four late
7x7 groups beyond the explicit cap. The searches evaluated 81,227,377
`(circuit,D)` candidates. Forty-four groups received a complete `2^cells`
search and 5,395 used the structured fallback.

| frontier | planes | groups `k>=5` | optimized | changed exact endpoints |
|---|---:|---:|---:|---:|
| 4x4 r49/d432 | 12,204 | 137 | 137 | 0 |
| 4x4 r47/d450 | 13,423 | 28 | 28 | 0 |
| 5x5 r93/d1155 | 13,869 | 347 | 347 | 1 neutral, distance 6 |
| 5x5 r93/d968 | 14,443 | 1,247 | 1,246 | 0 |
| 6x6 r153/d2508 | 14,447 | 735 | 734 | 0 |
| 6x6 r153/d1860 | 14,350 | 460 | 460 | 0 |
| 7x7 r250/d2966 | 13,488 | 439 | 439 | 0 |
| 7x7 r247/d3098 | 13,957 | 2,057 | 2,048 | 2 neutral, distance 8 |

All three changed endpoints passed both local and full gates. There was no
rank drop and no density improvement. The 5x5 endpoint starts at r93/d1160.
The pinned 7x7 endpoint starts at r247/d3125.

Matched continuations were also negative on objective reward:

| tensor | trials x moves/arm | aggregate moves | result |
|---|---:|---:|---|
| 5x5 | 16 x 10M, source/projective/pair | 480M | no rank win; source beat projective 6, tied 10; projective produced 4 distinct endpoints vs source 1 and pair 2 |
| 7x7 | 8 x 5M, source/projective/pair | 120M | no rank win; source beat projective 8/8; projective produced 8 distinct endpoints but only returned to d3100, versus source d3098 |

The diversity signal is real, especially on 7x7, but it came with worse
objective basins. No production lane or restart seed is justified by these
measurements.

## Replay

```sh
bin/tungsten compile --release \
  benchmarks/matmul/metaflip/flipfleet_projective_plane_test.w \
  -o /tmp/flipfleet-projective-plane-test
/tmp/flipfleet-projective-plane-test

bin/tungsten compile --release \
  benchmarks/matmul/metaflip/flipfleet_projective_plane_bench.w \
  -o /tmp/flipfleet-projective-plane-bench
/tmp/flipfleet-projective-plane-bench 16 32 2048

bin/tungsten compile --release \
  benchmarks/matmul/metaflip/flipfleet_projective_plane_continuation_bench.w \
  -o /tmp/flipfleet-projective-plane-continuation
/tmp/flipfleet-projective-plane-continuation 16 10000000 5
/tmp/flipfleet-projective-plane-continuation 8 5000000 7
```
