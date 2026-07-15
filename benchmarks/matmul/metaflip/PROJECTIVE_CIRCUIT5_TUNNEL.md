# Five-bucket projective-circuit tunnel

## Identity

Let five distinct factors on one tensor axis form a minimal binary circuit

```text
f0 xor f1 xor f2 xor f3 xor f4 = 0,
```

so the five factors span a four-dimensional space.  Grouping one live tensor
term under each factor gives five complementary rank-one matrices `M_i`.  For
any complementary rank-one matrix `D`, the replacement

```text
M_i -> M_i xor D,  i = 0..4
```

is exact because the added tensor is

```text
(f0 xor f1 xor f2 xor f3 xor f4) tensor D = 0.
```

`flipfleet_projective_circuit5.w` enumerates every minimal five-circuit (or a
bounded prefix). It tests both `D = y tensor z` from the selected complementary
factors and every nonzero `D` in the span of the five old slice matrices—at
most 31 additional, possibly higher-rank medians. It minimally factors every
changed slice, parity-compacts duplicate terms, and returns only a changed
endpoint. Callers rebuild the complete matrix-multiplication tensor before
admission. This is the rank-four member after the three-bucket matrix pencil
and four-bucket Fano-plane move.

## Correctness controls

The planted unit test constructs a genuine 5-to-4 replacement that the new
operator finds directly.  It then adds a collision-free nine-term zero
relation to the exact 3x3 rank-23 scheme, producing an exact rank-32 shoulder.
Complete enumeration finds the planted circuit and restores rank 23 under the
full tensor gate. A separate planted median forces the general matrix path to
select and factor a rank-two `D`. The current regression covers 1,219 circuits
and 7,762 changed endpoints.

## Real-frontier audit

The complete 4x4 and 5x5 passes, followed by bounded 2,048-circuit 6x6 and
7x7 passes, produced:

| source | coverage | circuits | changed low-debt endpoints | best endpoint |
|---|---:|---:|---:|---:|
| 4x4 r47/d450 | complete, 489,555 four-tuples | 356 | 0 | none |
| 4x4 r47/d677 | complete | 335 | 0 | none |
| 5x5 r93/d967 | complete, 8,382,465 four-tuples | 1,882 | 1,036 | r94/d973 |
| 5x5 r93/d1155 | complete | 1,827 | 849 | r94/d1166 |
| 6x6 r153/d1860 | first 2,048 circuits | 2,048 | 990 | r155/d1870 |
| 6x6 r153/d2502 | first 2,048 circuits | 2,048 | 440 | r155/d2518 |
| 7x7 r247/d3098 | first 2,048 circuits | 2,048 | 580 | r249/d3103 |
| 7x7 r247/d3554 | first 2,048 circuits | 2,048 | 320 | r249/d3561 |

There was no direct rank or density improvement and no exact-gate failure.
The matrix-span medians added 92 and 69 changed low-debt 5x5 endpoints over
the rank-one-only search, but did not improve the best debt or density. The
useful distinction remains debt: only the 5x5 frontiers supplied `+1`
shoulders; the larger tensors started at `+2`.

## Matched continuation

The best 5x5 circuit shoulder was compared with one ordinary exact `+1` split
from the same r93/d967 source.  Twelve paired trials gave each arm 10 million
ordinary worker moves, for 240 million aggregate moves.  Both arms returned
to rank 93 in all 12 trials and neither beat d967.  The circuit arm did,
however, finish at a non-source term set in 12/12 trials versus 9/12 for the
split arm, with mean source distance 12 versus 9.  Pairwise objectives favored
the circuit arm 7 times and the split arm 5 times; their aggregate bests were
d969 and d967 respectively.

That is modest but repeatable basin-diversity evidence, not evidence for a new
rank component.

## Scheduling decision

For 5x5 only, one quarter of existing `lifted-identity` pool launches first
try a nonce-rotated 256-circuit prefix.  A projective result is admitted only
when it is an exact `+1` shoulder; otherwise the ordinary lifted split remains
the fallback.  The bounded host step costs roughly 40--60 ms and the selected
shoulder is then continued by the existing GPU pool lane.  No new strategy row
or TUI layout was added.  The `+2` 6x6/7x7 results and zero-yield 4x4 results
remain offline.

## Replay

From the repository root:

```sh
bin/tungsten compile benchmarks/matmul/metaflip/flipfleet_projective_circuit5_test.w \
  --out /tmp/flipfleet-projective-circuit5-test --release --fast --lto
/tmp/flipfleet-projective-circuit5-test

bin/tungsten compile benchmarks/matmul/metaflip/flipfleet_projective_circuit5_bench.w \
  --out /tmp/flipfleet-projective-circuit5-bench --release --fast --lto
/tmp/flipfleet-projective-circuit5-bench \
  benchmarks/matmul/metaflip/matmul_5x5_rank93_d967_four_split_control_gf2.txt \
  5 0 0 /tmp/projective-circuit5-r94.txt

bin/tungsten compile benchmarks/matmul/metaflip/flipfleet_projective_circuit5_continuation_bench.w \
  --out /tmp/flipfleet-projective-circuit5-continuation --release --fast --lto
/tmp/flipfleet-projective-circuit5-continuation 12 10000000
```
