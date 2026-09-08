# Exact price-context reuse for offline packing

The opt-in `MetaflipBudPackings::ContextCache` reduces repeated offline packing
work without changing its result. Across 21,586 contexts on 28 checked imported
parents, four counterbalanced passes give **1.30x mean whole-wall speedup**.
Every complete result, including group indices and bounded-search metadata, is
byte-identical after JSON serialization. This is not a native flip/GPU speedup
and no live fleet default changes.

## Why reuse is sound

A cache is bound to one checked `Scheme`, whose shape and ordered literal
terms are immutable. It is never shared using a rank, bucket histogram, or
unordered tensor identity. A packing objective depends only on the prices of
usable group shapes. If those prices all change by one positive scalar, every
gain, comparison, tie, and state transition is unchanged; only the final formula
cost scales.

The key records exact integer prices divided by their common gcd, retaining
`nil` for group shapes excluded by the leaf-size cap. It includes all possible
shared-bucket sizes and the elementary-grid shapes actually present in the
parent. Grid detection is bounded; if the catalog truncates, the key falls back
to the entire grid-shape universe. A partial catalog never proves absence.
An initial census using the entire universe found no equivalent contexts;
excluding only structurally impossible grids finds 9,770 potential reuses.

Every price the cold solver may query is frozen before solving, preserving its
ordered shape even for orientation-sensitive libraries. Only
`exact_within_model` results enter the cache; incomplete results are returned
unchanged but not reused or upgraded. Serialized internal copies isolate cached
groups from caller mutations. Storage is bounded to 2,048 contexts by default,
with FIFO eviction. Price truth, whole tensor validity of resulting products,
and novelty remain separate verification obligations.

For a batch caller using an already-verified leaf library:

```ruby
require_relative "bud_packing_context"
cache = MetaflipBudPackings::ContextCache.new(parent,
  max_leaf: 32, grids: true, grid_side: 4)
scales.each do |scale|
  result = cache.solve(scale, leaf_library)
  # Retain/check the returned partition and materialize selected products.
end
puts cache.stats
```

## Matched measurement and tests

The sequence is control, cached, cached, control in one bounded, single-worker
process at `nice -n 10`, with no GPU. Each pass visits all integral scales through
side 32 for the same 28 parents and the same frozen price table. Timing includes
cache construction, lookups, result hashing, and trace writes. The host was not
reserved; these are workload-specific observations, not a general guarantee.
The host runtime is Ruby 4.0.6 with YJIT enabled on arm64 Darwin.

| Pass | Calls | Cache hits | Wall seconds | CPU seconds |
| --- | ---: | ---: | ---: | ---: |
| Control 1 | 21,586 | 0 | 19.604125 | 19.501728 |
| Cached 1 | 21,586 | 9,770 | 15.164629 | 15.059691 |
| Cached 2 | 21,586 | 9,770 | 15.134284 | 14.990983 |
| Control 2 | 21,586 | 0 | 19.696701 | 19.534256 |

Mean wall time is 19.650413 versus 15.149457 seconds, a 22.91% reduction.
All four full-context traces have the same SHA-256:
`d07969db1427a69c802dc572076fc7827d3570d522f2c066fef8d88d1854d567`.

The new focused suite passes six tests / 242 assertions. It compares complete
results across scales, proportional and changed prices, grid/no-grid models,
and reversed literal term orders, including orientation-sensitive prices.
It also checks caller mutation, bounded
storage, truncated grid-catalog fallback, incomplete-result non-admission, and
invalid inputs. The existing packing suite passes seven tests / 144 assertions.
The first implementation assumed canonical prices. Review caught that API
restriction; the final implementation preserves lookup orientation and was
remeasured from scratch. All eight old/new control/cache traces are identical
on the canonical real-workload library. The earlier version is retained for
replaying the completed 4x5x6 scan, not silently replaced in its provenance.

## Search follow-up

The remaining 27 imported parents (excluding the previously scanned 5x6x7
parent) had no retained mixed covers. A complete 21,466-case scan adds 257
covers: 19 directly lower local prices and 18 propagated improvements after
full recomposition. No added formula beats the pinned reference comparison.
Six representative products have been expanded and independently replayed:

| Shape | Previous local price | Expanded GF(2) rank | Pinned comparison |
| --- | ---: | ---: | ---: |
| 6x6x28 | 682 | 680 | 665 |
| 6x12x28 | 1,264 | 1,258 | 1,236 |
| 8x15x32 | 2,348 | 2,345 | 2,295 |
| 15x21x25 | 4,526 | 4,519 | 4,475 |
| 25x25x30 | 10,114 | 10,098 | 10,009 |
| 25x25x31 | 10,739 | 10,723 | 10,449 |

The scan's independent audit covers 27 tensors / 1,551 terms / 29,844
support-pair XORs. The products and dependencies cover 40 shape/orientation
tensors / 40,034 terms / 9,589,109 support-pair XORs. Leaf constructors fail
closed when a planned price has no checked literal/block/Kronecker witness.
These are improvements over local constructions, not primitive-rank or world
record claims. The benchmark's use of the 28th parent does not add another
independent search discovery.

The cached follow-up sampled 201 of the 3,580 retained 4x5x6 parents: the latest
literal member of each pricing-histogram class, plus the previous mixed-cover
controls. This is sampling, not a state-dominance rule. All 48,240 scale cases
completed, with 15,018 cache hits and 2,993 checked covers. The independent audit
replayed 201 tensors / 18,107 terms / 299,259 support-pair XORs. Full subsequent
repricing confirmed **zero** additional lower-price shapes. This does not rule
out the unsampled literal states or other move families.

Accounting clarification: the planner's `bud_expressions` field already includes
`mixed_bud_expressions`; these fields must not be added together. Earlier prose
calling the total an ordinary-expression count has been corrected. The original
immutable run reports and retained historical documentation are unchanged.

The current corpus still has 31,215 literal parents. The deduplicated improvement
cohort is **329 shapes: 31 expanded at their current best price and 298
recipe-only candidates**. This turn adds 29 distinct shapes, not 37 new distinct
discoveries. The scoped reference-crossing shortlist remains 45. Reference
metadata was not refreshed again for this all-above-reference batch; no record
claim or new main-square rank is implied.

The focused Ruby context, packing, and product suites pass 27 tests / 516
assertions in total. The 60 directly applicable Python audit, admission, and
composition tests also pass.

Local-only runs, exact contexts, audits, reference pins, snapshots, sources,
and a hash manifest are retained under
`benchmarks/matmul/metaflip/packing_context_audit_2026_09_08/`.
Imported tensors and derivatives remain outside source commits pending
redistribution review. No push, publication, archive change, or submission is
authorized or performed.
