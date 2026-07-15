# Exact residual-worm experiment for `<2,2,5>`

## Question

The checked lower-bound package leaves the primitive GF(2) interval

```text
17 <= R(<2,2,5>) <= 18.
```

Ordinary FlipFleet walks only through exact decompositions.  The residual-worm
prototype asks whether it is useful to work directly at rank 17 while carrying
a small exact defect:

```text
S XOR G = T,
```

where `S` always contains exactly 17 distinct nonzero rank-one terms, `T` is
the complete `<2,2,5>` multiplication tensor, and `G` is its complete 400-bit
syndrome.  A hit is `G=0`; no projected fingerprint is accepted.

## Implementation and invariants

`flipfleet_rect_residual_worm.w` is pure Tungsten and remains offline.  A
one-factor replacement updates `G` incrementally by XORing the old and new
outer products.  Every 4,096 proposals, the code reconstructs `T XOR S` from
scratch and compares all seven carrier words.  A zero carrier is passed to a
fresh `metaflip_rect_worker` state, which independently checks all 400 tensor
coefficients before the result can be reported as exact.

The search orders candidates by exact syndrome weight and then by the number
of active U/V/W coordinate slices.  It records the exact GF(2) ranks of all
three carrier flattenings for retained bests.  Three move scales are mixed:

1. an exact coordinate-descent replacement of one whole factor;
2. a syndrome-directed one-bit edit whose delta contains a live defect cell;
3. bounded random/partner kicks, followed by descent and a reset to the best
   sparse carrier after 2,048 unsuccessful proposals.

The third case is essential.  A one-term deletion of an exact rank-18 scheme
leaves a rank-one carrier.  Both d84 and d88 contain four terms whose outer
products have weight one, so the initial rank-17 search is already at the
smallest possible nonzero syndrome, with flattening ranks `1/1/1`.  There is
no downhill step unless rank 17 is attainable.

`flipfleet_rect_residual_worm_test.w` supplies a planted rank-17 tensor,
damages one factor to create a weight-two carrier, checks incremental
apply/undo word for word, and recovers `G=0`.  It also runs all eighteen real
deletion doors as a smoke test.  The planted test passes.

## Bounded real audit

Build and replay:

```sh
bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_rect_residual_worm_test.w \
  -o /tmp/ff-rect-residual-worm-test
/tmp/ff-rect-residual-worm-test

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_rect_residual_worm_bench.w \
  -o /tmp/ff-rect-residual-worm-bench
/tmp/ff-rect-residual-worm-bench 18000000
```

The July 14, 2026 release/LTO run used 18,000,000 residual proposals and an
equal 18,000,000 ordinary FlipFleet moves from each of d84 and d88:

| door | deletion weights | starts improved | floor-ending moves | floor configurations* | best `|G|` | exact hit | ordinary control |
|---|---:|---:|---:|---:|---:|---:|---:|
| d84 | 1--8, mean 3.777; four unit | 14/18 | 44,677 | 111 | **1** | 0 | rank 18/d84 |
| d88 | 1--18, mean 4.555; four unit | 12/18 | 43,649 | 150 | **1** | 0 | rank 18/d88 |

`*` The configuration number is the sum of per-deletion distinct 17-term
hash archives, each capped at 64; it is not a claim that all entries are
globally distinct across deletion restarts.

The worm performed 193,333 and 193,330 forced tunnel entries, respectively,
and reset 8,783/8,778 unproductive excursions.  It made 3,071/3,159 complete
incremental-versus-rebuilt carrier checks with no disagreement.  The d84 and
d88 runs accepted 204,154/191,617 uphill moves and repeatedly returned to
weight one, demonstrating real movement among 17-term presentations.

The negative boundary is sharper than “no hit.”  For each parent the floor
archive still covered only the same four unit residual coordinates exposed by
the four unit-weight deletions.  The directed floor counter was zero: no legal
single-factor edit containing a unit defect kept all 17 terms nonzero and
distinct.  Reaching alternative weight-one presentations therefore required
an uphill excursion, and none of those excursions moved the carrier to a
fifth coefficient or closed it.

The residual engine took about 12.35 seconds for d84 and 12.50 seconds for d88
on this machine; the proposal-matched ordinary controls took 0.90 and 0.92
seconds.  Thus residual proposals are roughly thirteen times more expensive
than ordinary moves here.  Neither method found rank 17.

As a wall-time cross-check, fresh ordinary lanes then ran 240,000,000 moves
from each parent. The d84 lane took 15.42 seconds and stayed rank 18/d84; the
d88 lane took 14.42 seconds and stayed rank 18/d88. Both performed 48,000
split attempts, accepted 64,334,437 and 59,734,634 moves, respectively, and
finished with exact reconstruction. This additional control also found no
rank 17, but it reinforces the scheduling comparison: an ordinary lane can
spend roughly an order of magnitude more proposals in the worm's wall time.

## Scheduling decision

This is a sound offline experiment but not yet a production CPU or GPU pool
strategy.  It passes a planted exact recovery and proves that bounded uphill
tunnels can reach many different rank-17 term lists, but the real carrier is
confined to four already-present unit cells after 36 million proposals.  The
absence of a direct floor edge and the roughly 13x per-proposal cost leave no
clear reward signal for displacing an ordinary lane.

A follow-up would need a genuinely correlated two-term or nullspace-guided
edit that can change the unit residual coordinate without first diffusing the
carrier.  Merely increasing the current one-factor tunnel budget is not
supported by this audit.

## Correlated two-term repair audit

The follow-up now exists as a separate offline experiment.  At any unit-floor
rank-17 state `S` with residual `G`, replace old terms `x_i,x_j` by terms
`y_1,y_2`.  Exactness is equivalent to

```text
y_1 + y_2 = G + x_i + x_j.
```

[`flipfleet_rect_two_term_repair.w`](flipfleet_rect_two_term_repair.w)
recognizes whether the right side has tensor rank at most two without SAT.
It first rejects U-flattening rank above two.  A one-dimensional U slice
space reduces to matrix rank at most two.  For a two-dimensional slice space,
the three nonzero GF(2) basis choices are exhaustive, and a choice succeeds
only when both resulting V-by-W matrices have rank one.  Every returned
decomposition is rebuilt word-for-word, and every candidate child is admitted
only after `FFBCScheme` reconstructs the complete multiplication tensor.

The residual-worm API now has an extended offline entry point,
`ffrrw_walk_target_floor_states`.  It materializes up to 64 distinct ordered
17-term configurations for each deletion restart.  Hashes are only a fast
filter: equal hashes are followed by full comparison of all 51 factors.
The original `ffrrw_walk_target` signature is a wrapper around the extension,
so production and existing test callers are unchanged.  The planted worm
test additionally checks that an initial unit-deletion state is archived
exactly.

Build and run the matched audit with:

```sh
bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_rect_two_term_repair_test.w \
  -o /tmp/ff-rect-two-term-repair-test
/tmp/ff-rect-two-term-repair-test

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_rect_two_term_repair_bench.w \
  -o /tmp/ff-rect-two-term-repair-bench
/tmp/ff-rect-two-term-repair-bench 72000000 64
```

The July 14 release/LTO campaign gave each d84/d88 parent 72,000,000 worm
proposals, four million per deletion:

| door | deletions reaching floor | archived states | archive maximum | pair carriers | U-flat rank <=2 | rank <=2 carriers | exact r17 |
|---|---:|---:|---:|---:|---:|---:|---:|
| d84 | 5/18 | 280 | 62/64 | 38,080 | 9,131 | **0** | 0 |
| d88 | 6/18 | 353 | 64/64 (five saturated) | 48,008 | 12,565 | **0** | 0 |

Thus 633 independently materialized floor configurations contributed exactly
86,088 old-term pairs.  The cheap U-flattening screen retained 21,696
carriers, but the complete rank-two recognizer rejected every one.  There was
no decomposition to rebuild or submit to the independent exact gate, and no
rank-17 output file was created.  Both parents remained confined to the same
four unit residual cells seen in the earlier audit.

The two worms consumed 49.502 and 52.908 seconds on this host.  Exhausting all
86,088 repair pairs took only 26 and 32 milliseconds respectively, so the
recognizer is not the bottleneck; generating new floor configurations is.
The benchmark can serialize every archived state as a header plus 17 decimal
`u v w` lines and emits a TSV manifest.  Each header records its door,
deletion, state index, and independently rebuilt residual cell, allowing a
different repair engine to audit the same finite corpus.  A deterministic
repeat with serialization reproduced all counts and wrote 633 states to
`/tmp/flipfleet_225_floor_manifest.tsv` (SHA-256
`999c001f8a7fb6b0e63eacb6db6d73e2997493e6fc8b574ce2a77b34735c7045`).
An independent Python reconstruction parsed every file, rebuilt all 400
coefficients, and confirmed that each residual has weight one at the header's
stated cell.  The serialized-run transcript SHA-256 is
`12024da7c0184641ed53abd2dd22b140599efe6ff6bbdd0741ddf754a93a3a2c`.

This is a useful, sharply measured negative, but it supplies no reward signal
for a production lane.  The two-term repair remains offline and no TUI,
kernel-pool, or tensor-profile scheduling was changed.

## Exhaustive unit-to-unit tunneling

Direct repair fixes the desired next residual to zero.  A more permissive
correlated move chooses another unit residual `E` and solves

```text
y_1 + y_2 = G + E + x_i + x_j.
```

This preserves rank 17 while moving the worm from unit cell `G` to unit cell
`E`.  [`flipfleet_rect_two_term_hop_bench.w`](flipfleet_rect_two_term_hop_bench.w)
exhausts all 399 alternative cells for all 136 old-term pairs in every one of
the 633 serialized floor states.  A decomposed carrier is rebuilt exactly;
the child multiset is GF(2)-compacted; and all 400 residual coefficients must
reconstruct to the selected target unit before an edge is retained.  If
compaction ever leaves at most 16 near-scheme terms, appending the target unit
would give rank at most 17, so that branch is independently `FFBCScheme`
verified and written as a record candidate.

The deterministic real-floor regression
[`flipfleet_rect_two_term_hop_test.w`](flipfleet_rect_two_term_hop_test.w)
checks a d84 transition from residual cell 377 to 227, rebuilds both sides,
and verifies that appending cell 227 gives an exact rank-18 scheme.  Build and
run the full scan with:

```sh
bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_rect_two_term_hop_test.w \
  -o /tmp/ff-rect-two-term-hop-test
/tmp/ff-rect-two-term-hop-test

bin/tungsten compile --release --native --lto --fast \
  benchmarks/matmul/metaflip/flipfleet_rect_two_term_hop_bench.w \
  -o /tmp/ff-rect-two-term-hop-bench
/tmp/ff-rect-two-term-hop-bench \
  /tmp/flipfleet_225_floor_manifest.tsv
```

The exhaustive result was:

| metric | value |
|---|---:|
| target-cell/pair/state carriers | 34,349,112 |
| U-flattening rank at most two | 3,747,930 |
| rank-at-most-two decompositions | 14,439 |
| independently full-gated unit hops | 14,439 |
| rank-one repair / exact-r17 opportunities | 0 / 0 |
| unique directed residual-cell edges | 24 |
| new residual cells | **0** |
| elapsed | 15.776 s |

The graph is exactly two disjoint complete directed four-cell components:

```text
d84: {22, 172, 227, 377}
d88: {44, 194, 249, 399}
```

There is no bridge between the parent components and no edge to any of the
other 392 tensor coordinates.  Consequently the compact new-seed manifest is
empty, and the planned resumed worms had no new component to run from.  The
full transcript SHA-256 is
`1cb17f29ff64c623951af8c13ce7f682da6ad1a5e65504f6b76779560551b677`.
This move explains the within-component floor diversity but does not tunnel
out of the infertile basin, so it also remains offline.
