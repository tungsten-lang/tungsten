# Read-only mixed-packing observers

The automatic composer supports mixed-axis pairs, groups and grids. The
offline parent walker can retain up to eight objectives of any one of these
families along the same trajectory, without steering it toward one target.
This is optional native research tooling, not a new default fleet lane.
The bounded studies below found no new local bound or world-record candidate.

## Interface and invariants

`bud_parent_walk.w` accepts this alternative price-table suffix after its
usual four primary lines:

```text
LIMIT
primary U costs: LIMIT+1 integers, starting with zero
primary V costs
primary W costs
mixed-observers N STATE_BUDGET
singleton_cost U_pair_cost V_pair_cost W_pair_cost
...one four-cost row per remaining observer...
```

`N` is 1..8, `STATE_BUDGET` is 1..1,000,000 and each leaf cost is a canonical
integer in 1..128. The rank-table limit is at most 512. The sidecars require
`walk`, cannot be combined with a holdout/grid or fixed-axis observer suffix,
and do not replace the primary objective. Four-line ordinary tables and the
previous fixed-axis observer/grid interfaces retain their behavior.

The legacy three-word header above selects pairs. Named headers also accept
`mixed-observers pairs N BUDGET`, `mixed-observers groups N BUDGET`, or
`mixed-observers grids N BUDGET`. Group rows have ten prices: singleton,
U/V/W pairs, triples, then quadruples. Grid rows append three 2x2-grid prices
for U/V, U/W and V/W, for thirteen prices total. The first four prices must
be in 1..128; optional group/grid prices may instead be `-1`, meaning no
verified leaf. Zero is not an absence marker. Each row must have exactly
the required width and canonical integer spelling. Count and budget limits
are unchanged. Named modes still require an ordinary `walk`; they are not
a multi-objective acceptance rule or a Pareto-optimality claim.

For scales `(a,b,c)`, costs correspond to leaves of shapes `(a,b,c)`,
`(a,b,2c)`, `(2a,b,c)` and `(a,2b,c)`. A caller must bind those numbers to
verified leaf witnesses before treating a score as a constructive rank
bound. Arbitrary score tables, hashes and the matching price alone cannot
establish a new tensor bound. Materialize and independently check products.

The observer copies the live terms into reusable private scratch and sorts
them canonically **once per observation**. It invokes the same `ffmm_plan`,
`ffmg_plan` or `ffmx_plan` used by automatic recipes for each context,
with no mutation of the walk state, hash chains, RNG or counters. Canonical
ordering is important for deterministic fallback: a live slot order must not
silently yield a different price from the later archived tensor.

Winners use score, then rank and density, and retain the earliest equal
observation. Full tensors are checked before retention and export. Outputs
are `mixed-observer-I-trial-J.txt` with `BUD_MIXED_OBSERVER` rows, deliberately
distinct from fixed-axis observers. `BUD_MIXED` reports evaluation count,
visited matching states, fallback components and total components. A fallback
score is a legal packing, never an optimality certificate.
The original pair statistics retain their format. Group/grid statistics
add `kind`, `probes_or_states` and `pair_states`; grid mode also exposes the
baseline `group_probes`, `group_fallback_components` and `group_components`.
Each pass in each context has its own budget. The eight contexts share
scratch, not a plan or an unfinished-solve classification.

## Focused verification

```sh
bin/tungsten compile bits/tungsten-metaflip/tools/bud_parent_walk.w \
  --out /tmp/bud-mixed-observers --release --native
python3 bits/tungsten-metaflip/spec/mixed_observer_walk_test.py \
  /tmp/bud-mixed-observers
python3 bits/tungsten-metaflip/spec/packing_observer_walk_test.py \
  /tmp/bud-mixed-observers
METAFLIP_BUD_WALK_BINARY=/tmp/bud-mixed-observers \
  ruby bits/tungsten-metaflip/spec/bud_parent_walk_test.rb
```

The new focused test passes with release/native and debug/native builds:

- Independently reconstruct all 33 observations of a small trajectory and
  calculate all eight matching minima, including tie metrics/time.
- Compare separate and simultaneous observers byte-for-byte, with identical
  primary winners, endpoints, attempted/accepted flips and chunks.
- Replay one-state fallback with an independent canonical BFS/six-order
  greedy implementation, including 3x3x3 and rank-above-64 5x5x5 states.
- Reject 16 malformed or incompatible calls before exporting a candidate.

The existing parent-walk suite passes 16 runs / 958 assertions, with no
failures, errors or skips when `METAFLIP_GROUP_BINARY` supplies the native
group fixture. Without that optional fixture, its bank case is skipped.
No compiler/runtime source was changed for this feature. The release/native
walker SHA-256 used by both studies is
`f2a03f59456bde06191c002b744d60e6d0655c1066ceb6821b9eb1357b47154e`.

## Matched searches

Both studies used the same immutable, independently checked native 22-leaf
bank, identity
`90a48facfb6c04cfd585d684fc4ec9a757805d7b12e454e0bddaeae608abf02b`.
Each paired run had a rank primary, eight fixed-axis **pair** observers in
the control, and eight mixed observers in the other arm. This is not a
comparison against unrestricted offline group packing. All endpoints and
attempt/acceptance counters match. Debt is two, density slack eight,
observations every 4,096 attempts, matching budget 50,000.

The initial study selected eight near-reference parent families from the
retained 33-parent corpus: 3x6x8, 4x4x4, 4x4x5, 6x3x4, 3x4x7, 4x5x7,
5x5x7 and 5x5x5. It used four trials, 32 chunks of 16,384 attempts, RNG
940901. The deeper study selected the four closest families whose initial
mixed price already improved a pure-axis pair price: 4x4x5, 4x5x7, 5x5x7
and 5x5x5. It used eight trials, 128 chunks of 65,536 attempts, RNG 941117.

| Study | Attempts, both arms | Distinct parent tensors | Target shapes | Better target minima than control | Full output replays |
| --- | ---: | ---: | ---: | ---: | ---: |
| Initial | 33,554,432 | 105 | 149 | 6 | 6 |
| Deeper | 536,870,912 | 185 | 73 | 4 | 4 |

The deduplicated union is **289 parent tensors**, **7,803 distinct recipes**
and **149 target shapes**, from 1,280 saved occurrences and 7,830 pricing
replays. Six distinct target shapes improve relative to the corresponding
controls; the deeper four overlap the first six and are not four new shapes.
All ten selected outputs pass independent full coefficient and exact term-set
replay. No component-size or state-budget fallback occurred in either study.

The nearest selected output is 8x15x21 at rank 1,556, versus the retained
local bound 1,552 and saved reference 1,542. Every selected output remains
dominated by an existing comparison. There are **zero new local bounds,
zero new reference crossings and no main-square rank improvement**. The
cumulative candidate-record count does not increase.

Comparisons use the padding-corrected saved closure, SHA-256
`0b4ad918bd36a262797cb89017513cbed0fe07dbdb832df4d5462c4e4e2c0da7`,
augmented with the five already retained projection/packing bounds to avoid
crediting them again. This is not a fresh worldwide literature audit.

Reports and self-contained parent/bank/output tensors remain outside the
checkout under `/private/tmp/metaflip-mixed-observer-study-20260909/` and
`/private/tmp/metaflip-mixed-observer-deep-20260909/`. No imported tensors or
bulk benchmark directories were added. Both finite studies have stopped.
Runs used one low-priority CPU process at a time and no GPU. Compilation or
focused checks could overlap; recorded timings are not isolated performance
measurements. Mixed scoring costs more than fixed-axis scoring in most
tested cells, and no live-flip throughput improvement is claimed.

## Group/grid retention and scale-one follow-up

The named modes share the primary scorer's bounded dispatch, while preserving
the original pair-header behavior. Their focused test independently checks
every one of 33 small states against eight group and grid objectives; compares
batched and separate retention byte-for-byte; checks repeated multi-trial
walks, unchanged primary winners and endpoints, budget-one fallback above
rank 64, and 22 malformed/incompatible calls. It passes in release/native
and non-release builds. The legacy mixed-observer tests, packing-primary
tests and parent-walk suite (16 runs / 958 assertions, no skips) also pass.

A matched study used seven parents: 3x3x3/r23, 4x4x4/r47, 5x5x5/r93,
4x4x5/r60, 4x7x4/r85, 4x5x7/r104 and 5x5x7/r127. Each of the pair,
group and grid arms retained eight objectives selected by closeness to
retained bounds, deduplicated target and proportional cost profile. Selected
contexts enlarge at least two axes, but may keep the third at one. The
post-hoc audit includes **all 63 nonidentity scales in {1,2,3,4} cubed**,
including single-axis expansions. No dominance claim excludes those scales.

This matters for useful existing constructions: 4x7x4 at scale 3x1x3 gives
7x12x12/r651. All three observer modes reproduce price 651 in every trial.
The earlier {2,3,4}-cubed studies could not see this context. Its verified
bound is already in the retained comparison and is not a new discovery.
Scale-one leaf witnesses here are exactly constructed by the offline library.
At the time of this study the automatic **mixed** composer still required
every scale coordinate to be at least two; the older fixed-axis lane already
reproduced rank 651. The subsequent
[scale-one integration](AUTOMATIC-SCALE-ONE-COMPOSITION-2026-09-09.md) adds
27 exactly-one-unit mixed contexts. Numeric observer tables themselves do
not supply leaf witnesses or expand the worker's constructive domain.

Each arm used 16 trials, 128 chunks of 16,384 attempts, observations every
2,048 attempts, debt two, density slack eight and a 50,000 budget per packing
pass. The study made **704,643,072 attempted flips**, with three matched
arms following the same 234,881,024-attempt trajectory set. Every primary
winner and endpoint is byte-identical across those arms. No GPU or live
fleet was launched. Native evaluations total 2,755,200. There was one pair
fallback, one group fallback, and eight grid fallback components, all in
the 3x3 cell; these retain valid constructive plans, not optimality claims.

There are **329 distinct parents** from 3,360 output occurrences. Common
repricing with the same 168-leaf constructive library completed all
**20,727 parent/context recipes**, covering 236 canonical targets, within
the bounded group/grid model (max leaf 16, component 24, 50,000 states and
candidates). No group-arm target beats the pair arm on these common prices.
Grid retention captures a new rank-23 3x3 representation with identity
`54b8c0bdb0ccf51dfdecd885dc98d87a2590439ca7a28602fcdeb89017771ed3`,
which improves these twelve minima over **both** controls:

| Target | Pair/group control | Grid-retained exact rank | Retained bound |
| --- | ---: | ---: | ---: |
| 3x3x6 | 46 | 45 | 42 |
| 3x3x9 | 69 | 68 | 63 |
| 3x3x12 | 92 | 90 | 84 |
| 3x6x9 | 134 | 133 | 122 |
| 6x6x6 | 161 | 159 | 153 |
| 6x6x9 | 245 | 243 | 224 |
| 6x6x12 | 314 | 309 | 294 |
| 6x9x9 | 341 | 338 | 338 |
| 6x9x12 | 452 | 451 | 433 |
| 9x9x9 | 521 | 517 | 482 |
| 9x9x12 | 651 | 648 | 626 |
| 9x12x12 | 862 | 857 | 810 |

All twelve products plus four scale-one diagnostics passed independent
Python substitution and full tensor checks: 51 distinct parent/leaf/output
tensors and 5,857 terms. Exact matrix cleanup was then applied to **all 329**
parents and independently replayed; none reduced. There is **no primitive
3x3/4x4/5x5 rank improvement, new retained bound or reference crossing**.
This was an attempt-matched retention test, not a wall-time win: group and
grid scoring cost more than pairs, and no default hot-loop change follows.

Deduplication against earlier studies adds **325**, not 329, identities.
The recent rollup is **2,119 parents / 69,057 distinct parent-context pairs**.
That second number is not 2,119 times 63: older parents only have their
already-tested 27 contexts, with the new 36 added where actually checked.
These are coverage counts, not record counts. The comparison includes all
five prior two-grid follow-up bounds, so none is recredited.

Evidence is outside the checkout at
`/private/tmp/metaflip-packing-observer-study-20260909`: `setup.json`,
`search.json`, `reprice.json` and `independent.json`, with bound leaf witnesses
and sixteen complete products. The compression source and independently
audited report are in the sibling `metaflip-packing-observer-compression-source-20260909`
and `metaflip-packing-observer-compressed-20260909` directories.

The durable local archive is
`/Users/erik/.local/share/tungsten-metaflip/evidence/2026-09-09-packing-observers.tar.gz`
(6,241,012 bytes; SHA-256
`b8589270c2eedd90eee56126e35e5ee4987909ab0f414ee7f06a8f05a649fdf0`).
A fresh extraction checked all 4,374 manifest hashes, the deduplicated
coverage rollup, all 329 compression inputs and all sixteen expanded
products. Imported tensors remain private local evidence; this archive
does not establish redistribution rights or worldwide novelty.

## Decision

Keep the explicit observer tool and its exact replay tests. Do not enable
the extra scoring in the default hot loop on these results. It demonstrates
a real retention difference without extra flips, but that difference has
not yet supplied a new best-known bound. The next productive test needs a
stronger parent neighborhood or broader constructive packing, not a claim
that another control-relative win is a record.
