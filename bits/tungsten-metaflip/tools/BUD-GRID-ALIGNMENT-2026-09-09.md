# Simultaneous shared-span grid alignment

The offline span-bridge tool now exposes **two** common vectors in two
equal-factor groups at once. This can reveal a 2x2 elementary grid that was
not visible as literal equalities in the original representation. It uses
only existing reversible GF(2) flips, not a new tensor identity.

The bounded study below generated 1,149 new same-rank representations and
improved composition prices relative to their source parents for 74 target
shapes. **None beats the retained best bounds.** This remains an offline
research refinement, not additional default CPU/GPU or background work.

## Interface and exactness boundary

```ruby
require_relative 'bud_span_bridges'

stats = MetaflipBudSpanBridges.each_grid_alignment(
  parent.terms, max_vectors: 3, max_pivots: 2,
  max_pairs: 4096, max_alignments: 4096, max_candidates: 128
) do |proposal|
  # Proposal generation is not admission. Check the complete tensor.
  child = MetaflipBudProducts::Scheme.new(
    parent.shape, MetaflipBudProducts.text(proposal.fetch(:terms)))
  # Retain the complete identity and exact flip word; price or search it
  # separately. Rank ties can be useful composition parents.
end
```

Inputs have at most 256 terms, with positive factors of at most 256 bits.
The two chosen buckets each have 2..`max_group` terms (default/cap 32).
The enumerator computes their span intersection on another factor axis and
selects distinct nonzero target vectors. Over GF(2), two distinct nonzero
vectors are independent. At most `max_vectors` (default 15, cap 255)
intersection-basis combinations and `max_pivots` choices per bucket are used.
These limits define a proposal family, not an exhaustive basis-orbit search.

For each target, the current bucket is eliminated again to obtain its
coefficient mask. Reusing masks from the original bucket after the first
rewrite would be incorrect. An unused pivot receives that target through
legal equal-factor transvections. Later targets preserve previously exposed
vectors, although their paired factors may change. Two buckets and two
targets supply a literal grid unless zero/duplicate-term cancellation instead
reduces the rank. The original tensor is never mutated.

The tool returns candidate terms and a complete replayable flip word. It
deduplicates full term sets with private immutable keys, not group signatures.
Its existing `each_bridge` operation is unchanged: that operation exposes
one vector and performs a cross-group flip; this one exposes two vectors
without that final cross-group flip.

Group-pair probes, alignment attempts and emitted candidates have separate
hard counters. Results report `pairs`, `alignments`, or `candidates` cutoffs.
An exhausted budget is not evidence that no other candidate exists.
`exhaustive` remains false even without a counter cutoff. No claim about a
globally optimal packing, rank, or world record follows from this API.

## Finite search and negative inventory

The starting corpus is the recent **2,119 distinct native-walk parents**,
not the older 31,215-parent projection corpus. Every input was independently
checked against the complete matrix-multiplication tensor.

- Literal rectangle inventory, sides 2..4: 222 parents have a 2x2 grid;
  zero have a larger grid. A separate Python adjacency/intersection check
  confirms this without importing the Ruby enumerator.
- Span inventory: 322,102 group-pair/axis checks. 282 parents have a
  two-dimensional common span, including 60 without any literal grid.
  None has a common span of dimension three or more. The largest input
  bucket has four terms, so the 32-term bucket cap excludes none here.
- Thus raising only the existing grid-side pricing limit cannot help this
  corpus. This does not rule out larger grids after further flips or rewrites.

The alignment study used all 282 eligible parents, three common-vector
combinations, two pivot choices per bucket, and at most 128 outputs per
parent. No generation limit was reached; the largest per-parent number of
alignment attempts was 48. Deduplication produced 1,149 new representations.
All preserve primitive rank; subsequent exact shared-factor matrix
compression produced zero reductions.

All 1,431 source/child tensors were priced in the **63 nonidentity scales
in {1,2,3,4} cubed**, with the same 168-leaf constructive library and retained
comparison table as the preceding observer study. Mixed groups and 2x2 grids
use the existing bounded set-packing solver: 24 component vertices,
50,000 states and 50,000 candidates. All 90,153 calls finished without a
packing fallback. This is exact only within that enumerated packing model.

There are 9,958 cheaper child/source/context comparisons across 74 target
shapes. The largest source-relative saving is 12 multiplications: for
4x20x28, 1,658 becomes 1,646, still worse than retained 1,423. The best
8x10x14/r724, 8x15x21/r1548 and 12x14x15/r1542 results reproduce already
retained bounds and are not credited again. No main-square primitive rank
or retained target bound improves; no fresh worldwide reference audit was
performed.

The recent deduplicated cohort is now **3,268 parents and 151,092 distinct
parent/context pairs**. This includes the prior 69,057 pairs, 72,387 pairs
from new parents, and 9,648 previously unpriced scale-one contexts on old
parents. It is not `3268 * 63`, nor a count of new best-known shapes.

## Verification and retention

Focused tests:

```sh
ruby bits/tungsten-metaflip/spec/bud_grid_alignment_test.rb
ruby bits/tungsten-metaflip/spec/bud_span_bridges_test.rb
ruby bits/tungsten-metaflip/spec/bud_packings_test.rb
```

Results: 4 runs / 1,349 assertions, 4 / 2,483, and 8 / 158 respectively;
zero failures, errors or skips. Tests compare full tensor coefficients,
replay and reverse every word, cover dependent bucket columns and randomized
inputs, preserve the original terms, enforce each work cap, and reject a
deliberately corrupted full tensor.

An independent Python checker verifies all 3,268 corpus tensors and all
1,149 forward/reverse words. Twelve selected compositions pass independent
full term-set substitution and tensor checks (27 distinct parent/leaf/output
witnesses, 19,747 terms). A cold replay with the final capped implementation
reproduces every ordered proposal and all 90,153 prices. Adding the separate
alignment-attempt cap after the first study does not change any study output;
the cold replay records both source hashes.

Evidence is retained outside the checkout in
`~/.local/share/tungsten-metaflip/evidence/2026-09-09-span-grid-alignment.tar.gz`.
The archive is 3,558,364 bytes, SHA-256
`d870ccb676e7106af89ab6da6a861a2af175fe056f944ea47d8ab630c50edb40`.
It includes canonical inputs/outputs, exact words, comparison tables, the
constructive leaf library, source snapshots, independent checkers and a file
manifest. No bulk benchmark tree, canonical seed promotion, or live worker
was added. The finite jobs used low-priority CPU processes and no GPU;
their timings are not isolated throughput benchmarks.

The [matched continuation and native-refinement control](ALIGNED-CONTINUATION-AUDIT-2026-09-09.md)
is now complete: no new retained bound, and existing native refinement
matches all four selected raw starting gains. Merely exposing a grid does
not justify making this an unconditional default refinement stage.
