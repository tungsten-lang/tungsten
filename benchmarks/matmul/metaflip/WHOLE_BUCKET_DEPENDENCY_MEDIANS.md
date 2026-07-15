# Whole-bucket and polynomial GF(2) dependency medians

## Exact identities

Fix one tensor axis and group every live term with factor `f_i` into its
physical complementary matrix `M_i`. If five distinct factors form a minimal
circuit,

```text
f0 xor f1 xor f2 xor f3 xor f4 = 0,
```

then a common matrix toggle is exact:

```text
M_i -> M_i xor D,  i = 0..4.
```

`flipfleet_projective_bucket5.w` captures the *entire* five factor buckets,
not one representative term per factor. It exhausts the 31 nonempty choices
`D = xor_{j in S} M_j` and minimizes `sum rank(M_i xor D)`. All matrix ranks
and factorizations operate directly on physical `i64` factors through
`ffsm_rank_factor_matrix`; there is no packed coordinate-matrix limit.

The same identity has a polynomial arbitrary-size form for rank-one `D`. Set

```text
delta_i = rank(M_i xor D) - rank(M_i).
```

A rank-one update has `delta_i` in `{-1,0,+1}`. For every negative anchor,
`flipfleet_gf2_dependency_median.w` builds a coordinate-recovering GF(2)
basis from every other nonpositive factor bucket. It first solves for a
zero-sum dependency using only those buckets, then permits one `+1` bucket,
and finally two. The three families have predicted debt below zero, at most
zero, and at most `+1`, respectively. This searches dependencies of arbitrary
cardinality without minimum-codeword enumeration.

Both operators compare the local tensors coefficient-for-coefficient,
minimally refactor the changed buckets, parity-compact the full splice, rebuild
a fresh worker, and run the exhaustive `n^6` matrix-multiplication gate.

## Planted controls

The whole-bucket regression uses five rank-two matrices. Their best common
toggle is a rank-two bucket matrix and lowers the exact subtotal `10 -> 9`.
Complete `flipfleet_projective_circuit5` representative-term search bottoms
out at ten, so the test genuinely requires whole buckets. Mapping the
19-term zero relation into an exact 3x3 scheme produces an exact rank-42
shoulder that the new full-state path restores to rank 23.

The polynomial regression uses a minimal eight-factor dependency. One bucket
has `delta=-1`, the other seven have `delta=0`, and elimination finds the
direct exact `8 -> 7` refactor. There is no five-factor subcircuit. Its
15-term zero relation similarly gives an exact rank-38 3x3 shoulder, and one
rank-one-D iteration restores rank 23 under the full gate.

## Whole-bucket five-circuit audit

Complete 4x4/5x5 passes and 2,048-circuit 6x6/7x7 passes used both the sparse
and alternate doors:

| source | coverage | circuits | minimum debt | debt `+1/+2` |
|---|---:|---:|---:|---:|
| 4x4 r47/d450 | complete | 356 | `+3` | 0 / 0 |
| 4x4 r47/d677 | complete | 335 | `+3` | 0 / 0 |
| 5x5 r93/d967 | complete | 1,441 | `+2` | 0 / 85 |
| 5x5 r93/d1155 | complete | 1,434 | `+2` | 0 / 90 |
| 6x6 r153/d1860 | first 2,048 | 2,048 | `+2` | 0 / 105 |
| 6x6 r153/d2502 | first 2,048 | 2,048 | `+2` | 0 / 63 |
| 7x7 r247/d3098 | first 2,048 | 2,048 | `+2` | 0 / 90 |
| 7x7 r247/d3554 | first 2,048 | 2,048 | `+1` | 1 / 66 |

Across 11,758 circuits, all 364,498 subset-mask evaluations were locally
exact; the sole debt-admitted full gate also passed. There was no rank or
density improvement. The sole `+1` result was an exact r248/d3562 7x7 shoulder. Its
five buckets each contained one term, so the stronger whole-bucket algebra
was not responsible; distinct-factor enumeration merely reached a useful
circuit before the representative-term prefix, whose same cap returned only
r249/d3555.

Twelve paired 10-million-move continuations compared that shoulder with an
ordinary exact `+1` split (240 million aggregate moves). Both arms returned
to rank 247 in all trials and improved density in all trials. The bucket arm
won 3, the split arm won 4, and 5 tied; aggregate bests were d3510 and d3508.
The bucket arm traveled slightly farther from the source (mean term-set
distance 27 versus 25), but this is not enough reward for a pool share.

## Polynomial arbitrary-dependency audit

The rank-one-D scan was complete on both 4x4--7x7 doors:

| source | unique D | exact dependencies | direct / neutral / `+1` | maximum buckets | best |
|---|---:|---:|---:|---:|---:|
| 4x4 r47/d450 | 141 | 99 | 0 / 0 / 99 | 3 | r48/d446 |
| 4x4 r47/d677 | 141 | 96 | 0 / 0 / 96 | 3 | r48/d670 |
| 5x5 r93/d967 | 279 | 222 | 0 / 8 / 214 | 4 | r93/d967 |
| 5x5 r93/d1155 | 279 | 207 | 0 / 6 / 201 | 4 | r93/d1156 |
| 6x6 r153/d1860 | 459 | 333 | 0 / 0 / 333 | 4 | r154/d1840 |
| 6x6 r153/d2502 | 459 | 351 | 0 / 0 / 351 | 3 | r154/d2494 |
| 7x7 r247/d3098 | 741 | 591 | 0 / 20 / 571 | 5 | r247/d3104 |
| 7x7 r247/d3554 | 741 | 586 | 0 / 20 / 566 | 5 | r247/d3555 |

All 2,485 materialized endpoints passed both exact gates. There was no direct
drop. A separate all-D pass rejected canonical elimination witnesses shorter
than six and found no longer witness on any door. This exhausts D values and
the basis representation selected by the operator; it does not enumerate
alternate representations obtained by adding nullspace relations. Every
recovered real hit therefore lies in already-enumerated 3--5-bucket geometry.
The best d967 neutral endpoint was only distance four from its source and is a
three-bucket projective-line refactor already covered by the complete
matrix-pencil lane.

The most attractive shoulder was r154/d1840 from the 6x6 d1860 leader, at
term-set distance seven. In twelve paired 10-million-move continuations it
failed to return to rank 153 even once, while all twelve ordinary splits did;
the paired score was 0--12. Its best endpoint remained r154/d1829. Thus even
the lower-density shoulder is an infertile basin, and the polynomial
generalization remains a sound offline operator with no CPU/GPU pool share.

## Replay

From the repository root:

```sh
bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_projective_bucket5_test.w \
  -o /tmp/flipfleet-projective-bucket5-test
/tmp/flipfleet-projective-bucket5-test

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_projective_bucket5_bench.w \
  -o /tmp/flipfleet-projective-bucket5-bench
/tmp/flipfleet-projective-bucket5-bench \
  benchmarks/matmul/metaflip/matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt \
  7 2048 1 7

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_projective_bucket5_continuation_bench.w \
  -o /tmp/flipfleet-projective-bucket5-continuation
/tmp/flipfleet-projective-bucket5-continuation 12 10000000

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_gf2_dependency_median_test.w \
  -o /tmp/flipfleet-gf2-dependency-median-test
/tmp/flipfleet-gf2-dependency-median-test

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_gf2_dependency_median_bench.w \
  -o /tmp/flipfleet-gf2-dependency-median-bench
/tmp/flipfleet-gf2-dependency-median-bench \
  benchmarks/matmul/metaflip/matmul_5x5_rank93_d967_four_split_control_gf2.txt \
  5 0 1 0

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_gf2_dependency_median_long_bench.w \
  -o /tmp/flipfleet-gf2-dependency-median-long
/tmp/flipfleet-gf2-dependency-median-long \
  benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_global_isotropy_gf2.txt \
  7 0 1 0 6

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_gf2_dependency_median_continuation_bench.w \
  -o /tmp/flipfleet-gf2-dependency-median-continuation
/tmp/flipfleet-gf2-dependency-median-continuation 12 10000000
```
