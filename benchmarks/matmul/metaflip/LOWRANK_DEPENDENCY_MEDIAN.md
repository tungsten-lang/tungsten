# Rank-two GF(2) dependency medians

## Identity and implementation

Fix one tensor axis and write the scheme as factor buckets

```text
T = sum_i f_i tensor M_i.
```

For any zero-sum set of bucket factors, `xor_{i in S} f_i = 0`, replacing
every complementary matrix in the set by `M_i xor D` is exact because the
change is `(xor_{i in S} f_i) tensor D = 0`.

`flipfleet_gf2_lowrank_dependency_median.w` extends the rank-one operator in
`flipfleet_gf2_dependency_median.w`. On each axis it collects the distinct
live rank-one complementary matrices, retains each singleton as a control,
and constructs every pair XOR

```text
D = (a tensor b) xor (c tensor d).
```

Thus `rank(D) <= 2`. Every nonzero `D` is minimally factored with
`ffsm_rank_factor_matrix`; a chained exact hash table deduplicates the
canonical physical factorization. The real audit can filter out the
rank-one controls and count only rank-two values.

For each bucket the operator computes the exact value

```text
delta_i = rank(M_i xor D) - rank(M_i),
```

now in `{-2,-1,0,+1,+2}`. It uses the same coordinate-recovering GF(2)
elimination as the rank-one lane: a negative anchor is solved against every
other nonpositive bucket, then against one and two positive buckets. Direct,
neutral, and `+1` predicted debt are considered in that order. Every selected
replacement passes a coefficient-level local gate, parity compaction, a fresh
worker rebuild, and the exhaustive `n^6` tensor gate.

The implementation is pure Tungsten and required no syntax, compiler, or
runtime extension.

## Adversarial plant

The regression contains a minimal eight-factor dependency whose eight bucket
matrices each have rank two. Exhausting every distinct live rank-one `D`
cannot lower the 16-term objective: its minimum remains 16. The pair-XOR

```text
D = (6 tensor 14) xor (13 tensor 5)
```

has physical rank two and lowers the complete dependency `16 -> 13`. The
local relation is exact coefficient-for-coefficient. Mapping its 16-term zero
relation into unused factors of the checked-in 3x3 rank-23 scheme constructs
an exact rank-39 shoulder; the bounded full-state search restores rank 23 and
passes the full tensor gate. This proves the new code reaches algebra that the
live rank-one controls do not.

## Complete 4x4--7x7 audit

Both retained doors at every square size were scanned on all three axes with
the rank-two-only filter. The table counts unique physical rank-two `D`
values; every admitted endpoint was independently full-gated.

| source | rank-two `D` | negative deltas | dependencies | direct / neutral / `+1` | best |
|---|---:|---:|---:|---:|---:|
| 4x4 r47/d450 | 3,243 | 0 | 0 | 0 / 0 / 0 | none |
| 4x4 r47/d677 | 3,243 | 0 | 0 | 0 / 0 / 0 | none |
| 5x5 r93/d967 | 12,802 | 31 | 7 | 0 / 0 / 7 | r94/d975 |
| 5x5 r93/d1155 | 12,810 | 30 | 6 | 0 / 0 / 6 | r94/d1167 |
| 6x6 r153/d1860 | 34,842 | 33 | 0 | 0 / 0 / 0 | none |
| 6x6 r153/d2502 | 34,836 | 48 | 0 | 0 / 0 / 0 | none |
| 7x7 r247/d3098 | 91,057 | 127 | 0 | 0 / 0 / 0 | none |
| 7x7 r247/d3554 | 91,057 | 127 | 0 | 0 / 0 / 0 | none |

In total, the complete scan evaluated 283,890 unique rank-two matrices. It
found 13 exact endpoints, all on 5x5, all predicted and realized rank `+1`,
and all three-bucket `5 -> 6` replacements. There were no neutral endpoints,
rank drops, or gate failures. A complete second pass on both 5x5 doors
required at least six buckets and found no witness. The other six doors had
no dependency even with the weaker two-bucket minimum, so the stricter filter
cannot admit one under this elimination representation.

The bounded nonce-0 endpoint from d967 has parity-set distance 11 from its
source (five terms removed, six added) and SHA-256
`94618d13d5a97a810a8f03977061c51fabd04fa8fc4cea9edda7d7ec0c13b25a`.
The complete scan finds the slightly denser r94/d975 representative.

## Matched continuation and scheduling decision

Twelve paired 10-million-move continuations compared the complete-scan
r94/d975 rank-two shoulder with an ordinary exact `+1` split from the same
r93/d967 source, for 240 million aggregate moves. Both arms returned to rank
93 in all twelve trials. Neither found a rank or density improvement. The
rank-two arm won one paired objective and lost eleven; its aggregate best was
r93/d973, versus r93/d967 for the split controls. It did travel farther from
the source (mean term-set distance 19 versus 11), but that diversity was
strictly unrewarded at the measured budget.

The operator is therefore retained as an exact offline move and adversarial
regression, with no CPU or GPU pool allocation. The empirical failure mode is
also informative: for a pair XOR built from live rank-one atoms, nearly every
unrelated bucket pays `+2`; only rare absorption coincidences create a
negative delta. On these records that makes useful zero-sum dependencies much
rarer than for rank-one `D`, and the surviving 5x5 cases lead to infertile
three-bucket shoulders.

## Replay

From the repository root:

```sh
bin/tungsten compile --release --native --lto \
  benchmarks/matmul/metaflip/flipfleet_gf2_lowrank_dependency_median_test.w \
  -o /tmp/flipfleet-gf2-lowrank-dependency-test
/tmp/flipfleet-gf2-lowrank-dependency-test

bin/tungsten compile --release --native --lto \
  benchmarks/matmul/metaflip/flipfleet_gf2_lowrank_dependency_median_bench.w \
  -o /tmp/flipfleet-gf2-lowrank-dependency-bench
/tmp/flipfleet-gf2-lowrank-dependency-bench \
  benchmarks/matmul/metaflip/matmul_5x5_rank93_d967_four_split_control_gf2.txt \
  5 0 1 0 2 2

bin/tungsten compile --release --native --lto \
  benchmarks/matmul/metaflip/flipfleet_gf2_lowrank_dependency_median_continuation_bench.w \
  -o /tmp/flipfleet-gf2-lowrank-dependency-continuation
/tmp/flipfleet-gf2-lowrank-dependency-continuation 12 10000000
```
