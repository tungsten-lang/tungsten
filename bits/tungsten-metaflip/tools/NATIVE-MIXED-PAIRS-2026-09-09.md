# Native mixed-axis pair engine

This ports a useful part of offline algebraic composition into native
Tungsten. It does not add a new record, replace the live flip kernel, or yet
enable mixed-axis recipes in the automatic background queue.

## Implemented

`composition/mixed_pairs.w` accepts a complete narrow parent tensor and
constructive singleton/pair leaf costs. Terms can be paired along U, V or W,
but each term belongs to at most one pair. Positive-saving edges form
connected components. Components with at most 16 terms use exact weighted
matching, subject to a caller-specified total state budget. Larger or
budget-exhausted components keep the best of six deterministic greedy axis
orders. This fallback is a valid packing and no worse than any pure-axis
pair packing with the same leaves. Status distinguishes exact work from
fallback; a fallback is not an optimality certificate.

The mapper handles all 27 ordered scale triples in `{2,3,4}^3`. Arbitrary
linear parent factors are substituted into the appropriate leaves; members
need not be independent. Packed factors support up to 1,024 bits, with
16,384 output terms and 512 input terms. Zero images and even duplicate
multiplicities are canceled canonically. Reported slab lengths, factor
widths, costs and the symmetric partition are checked before output writes.
The caller must still run the full tensor gate before archive admission.

`composition/mixed_bank.w` constructs and verifies the 22 distinct canonical
leaves required by those contexts, reusing shipped witnesses and the existing
native rank-15/rank-26 small-leaf builders. Exact block sums fill missing
leaves. Its `MFM_BANK1` manifest binds full immutable `MFR1` tensors; loading
checks canonical bytes, ordered shapes and every tensor coefficient. Hashes
and numerical ranks are never accepted as identity proofs. There is no
Ruby/Python or catalog-download dependency in the native engine.

The constructive bank ranks are:

```text
shape 222 223 224 233 234 244 333 334 344 444
rank    7  11  14  15  20  26  23  29  38  47
shape 226 236 246 336 346 446 228 238 248 338 348 448
rank   21  30  40  44  54  73  28  40  52  58  74  94
```

These are the available constructive costs, not claims of globally best
ranks. Larger groups and grids from the offline packer are not included.

## Focused verification

From the repository root:

```sh
bin/tungsten-compiler compile \
  bits/tungsten-metaflip/spec/mixed_composition_test.w \
  --out /tmp/metaflip-mixed-test --release --native --no-lto
python3 bits/tungsten-metaflip/spec/mixed_composition_parity_test.py \
  /tmp/metaflip-mixed-test
```

The same focused checks pass with both release/native and debug/native
builds (without LTO):

- 369 matching cases, including an independent exact oracle for small
  components, odd cycles, disconnected graphs, 16/17-term boundaries,
  512-term input, one-state exhaustion and repeatable fallback partitions.
- 24 malformed-call rejection gates, before destination mutation.
- All 22 leaves independently tensor-checked, including cached-bank reload.
- 194 full output tensor and exact term-set replays across all 27 contexts;
  redundant parent terms exercise cancellation and non-injective maps.
  Skinny inputs exercise the 63-bit parent / 1,024-bit output boundary.
- A bank forgery with freshly recomputed hashes, valid nonzero factor widths
  and sorted canonical bytes is rejected by the full tensor check.

The native fixture also exposes `--bank ROOT RUNTIME` and
`--compose ROOT PARENT_ID BANK_ID A B C OUTPUT STATE_BUDGET` for bounded
developer replay. Inputs are canonical verified spool objects, not raw
unchecked rank prices. A successful composition writes the full `MFW1`
tensor plus its selected partition. This is a fixture interface, not a new
live-fleet launch mode.

## Matched corpus replay

The same 33 retained parents and 891 ordered contexts from the preceding
[projection/packing study](PROJECTION-PACKING-2026-09-09.md) were replayed
with a 50,000-state budget. Source hashes were checked before loading.
Every component finished exactly within the native pair-only family:
no component-size or state-budget fallback occurred in this corpus.

- 214 prices improve on pure-axis **pair** packing with the same leaves.
- 205 improve on the previous fixed-axis **group** formulas.
- 829 match the broader offline packer's price; 62 are worse, none better.
- 322 selected outputs were fully expanded and independently checked as
  complete tensors and exact term sets.

The two useful recipes are retained:

| Parent and scales | Output | Exact rank | Previous pure-axis price |
| --- | --- | ---: | ---: |
| 3x5x5/r58, scales 3x4x3 | 9x20x15 | 1,646 | 1,654 |
| 3x3x8/r56, scales 2x2x4 | 6x6x32 | 774 | 778 |

These reproduce already retained local improvements. Relative to the prior
study's completed outputs there are **zero new local bounds**, and therefore
no new public-reference crossings or world-record claims. In particular,
the saved public comparisons remain stronger (1,604 and 758 respectively).

The bounded study took about 31 seconds including native subprocess launches
and independent Python replay, with one low-priority CPU process at a time
and no GPU work. This is not a standalone native-kernel throughput benchmark.
Its report, parent/bank spool and full witnesses are retained outside the
checkout at `/private/tmp/metaflip-native-mixed-20260909/`; no generated
tensor corpus or imported parent was added to the repository.

## Remaining automatic integration

Do not simply append these 27 contexts inside `ffbc_submit_parent`.
`refinement_budget.w` reserves at most nine recipes per parent and recovers
at most nine unacknowledged records. Expanding that family in place can
overflow the default backlog or make a whole source reservation impossible.

The next step is durable deferred parent/context admission, with bounded
recipe expansion, explicit pending counters, restart-safe deduplication,
and stop/backpressure tests. The current fixed-axis queue and CPU/GPU paths
are unchanged by this engine milestone. Mixed outputs also remain wide
archive witnesses, not live wide-worker seeds.
