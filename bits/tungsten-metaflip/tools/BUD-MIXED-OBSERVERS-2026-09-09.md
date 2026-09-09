# Read-only mixed-pair observers

The automatic composer now supports mixed-axis pairings, but the offline
parent walker previously retained only fixed-axis price winners. The walker
can now retain up to eight mixed-pair objectives along the same trajectory.
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

For scales `(a,b,c)`, costs correspond to leaves of shapes `(a,b,c)`,
`(a,b,2c)`, `(2a,b,c)` and `(a,2b,c)`. A caller must bind those numbers to
verified leaf witnesses before treating a score as a constructive rank
bound. Arbitrary score tables, hashes and the matching price alone cannot
establish a new tensor bound. Materialize and independently check products.

The observer copies the live terms into reusable private scratch and sorts
them canonically. It invokes the same `ffmm_plan` used by automatic recipes,
with no mutation of the walk state, hash chains, RNG or counters. Canonical
ordering is important for deterministic fallback: a live slot order must not
silently yield a different price from the later archived tensor.

Winners use score, then rank and density, and retain the earliest equal
observation. Full tensors are checked before retention and export. Outputs
are `mixed-observer-I-trial-J.txt` with `BUD_MIXED_OBSERVER` rows, deliberately
distinct from fixed-axis observers. `BUD_MIXED` reports evaluation count,
visited matching states, fallback components and total components. A fallback
score is a legal packing, never an optimality certificate.

## Focused verification

```sh
bin/tungsten-compiler compile bits/tungsten-metaflip/tools/bud_parent_walk.w \
  --out /tmp/bud-mixed-observers --release --native --no-lto
python3 bits/tungsten-metaflip/spec/mixed_observer_walk_test.py \
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

## Decision

Keep the explicit observer tool and its exact replay tests. Do not enable
the extra scoring in the default hot loop on these results. It demonstrates
a real retention difference without extra flips, but that difference has
not yet supplied a new best-known bound. The next productive test needs a
stronger parent neighborhood or broader constructive packing, not a claim
that another control-relative win is a record.
