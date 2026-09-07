# Composition-aware parent walks, 2026-09-06

The bounded native experiment finds a verified **8x8x9 rank-381 GF(2)**
product, improving the earlier local rank-387 witness. This is not a new
primitive-rank result or a confirmed world record. The
[Lille rank-388 construction](https://fmm.univ-lille.fr/8x8x9.html) already
uses four `<4,4,5>` and three `<4,4,4>` leaves. Replacing its ranks 61/48
with the checked-in GF(2) ranks 60/47 gives the same rank formula found here:

`4*60 + 3*47 = 381`.

This establishes useful recovery of an existing construction pattern with
lower-rank field-specific leaves; it does not establish novelty. No result
was submitted, published, committed, or inserted into a live record ledger.

## What changed

`bud_parent_walk.w` wraps the existing native rectangular worker without
changing production scheduling or the flip hot loop. It walks a frozen
parent, scores short batches by the constructible product rank, and retains
an exact-verified composition winner separately from the primitive-rank best.
`bud_parent_score.w` uses reusable scratch and a certificate-backed price
table. The score is the minimum of three pure-axis bucket partitions, with
integer DP prices for splitting each bucket. It is a constructive upper
bound, not a rank lower bound or an optimal mixed-axis partition.

`bench_bud_parents.rb` builds that table from full exact leaf witnesses,
snapshots inputs, records binary/source hashes and native attempt counters,
checks every native score against the Ruby composer, then constructs and
verifies every winning product. Rejected batches cannot repeat the same RNG
state or roll back the external move-attempt clock. Trials restart from the
same input; they are not continuations of the live fleet.

Three acceptance policies share the same worker, rank debt of two, initial
seeds, and move-attempt budgets:

- `walk`: accept every completed batch, retaining its best observed product.
- `greedy`: accept only a non-worsening composition score.
- `anneal`: cycle through allowances 0/1/2/4/8 above the trial best.

The worker still uses its existing density-aware wandering and split rules.
Thus `walk` is the ordinary-wandering control, not an unbiased random walk.

## Matched search results

Each cell below uses 16 trials, 512 batches of 512 move attempts per trial:
**4,194,304 attempts per policy per parent**, 88,080,384 total across the
seven rows. The 148-file leaf library was held fixed. These are search-quality
comparisons, not CPU throughput measurements: the separate CPU/GPU fleet
continued running throughout.

| Parent | Scale | Initial product score | Walk best | Greedy best | Anneal best |
|---|---|---:|---:|---:|---:|
| 2x2x5, rank 18 | 4x4x1 | 256 | 236 | 250 | 236 |
| 2x2x7, rank 25 | 4x4x1 | 316 | 302 | 302 | 302 |
| 2x2x8, rank 28 | 4x4x1 | 329 | 329 | 329 | 329 |
| 2x2x9, rank 32 | 4x4x1 | 387 | 381 | 381 | 381 |
| 2x3x4, rank 20 | 4x4x1 | 304 | 304 | 304 | 304 |
| 2x3x5, rank 25 | 3x3x1 | 221 | 219 | 221 | 221 |
| 3x3x5, rank 36 | 3x3x1 | 321 | 320 | 320 | 320 |

All 336 saved products passed the older independent Python verifier:
100,830 terms and 2,065,681 support-pair XORs. Native/Ruby score, parent rank,
and density agreed in every trial. The best rank-219 product uses a rank-26
parent even though the starting primitive rank is 25.

Greedy acceptance is **not promoted**. On the 2x2x5 row, ordinary wandering
reached 236 in 13/16 trials; greedy stayed at 250 in 16/16. Annealing reached
236 in 6/16. Both restrictive policies also missed the two improvements
found by ordinary wandering on 2x3x5. Retaining composition winners is useful;
rejecting exploration based only on this score was not better in this study.

An equal-attempt 2x2x9 follow-up sampled every four moves rather than every
512 (65,536 batches per trial). All three policies again reached exactly
381 in 16/16 trials. Native elapsed times rose from about 0.24 seconds to
about 9 seconds per arm, reflecting the copying/scoring overhead in this
concurrent run; no controlled hardware speedup claim follows. The denser
sampling yielded a lower-density parent/product tie, retained below.

## Observation-only cadence follow-up

`--observe-every N` now observes inside the existing chunk without changing
the chunk/RNG/rejection boundaries. The default remains one observation per
chunk. A copied winner is verified instead of the live walked state. Explicit
cadence runs also export final anchor tensors for trajectory comparisons.

The earlier four-move experiment above also shortened acceptance/RNG chunks;
it was not a pure observation-only ablation. In the new test, ordinary and
greedy walks preserve both accepted-flip counts and final tensor hashes across
cadences. Annealing can change trajectory because its threshold depends on
the best observed score; that difference is intentional and recorded.

Four parents (3x4x7, the retained 4x4x5 winner, 2x2x9, and 3x3x5) were tested
at cadences 512/8/1, holding 16 trials, 256 chunks and 512 attempts per chunk
fixed: 2,097,152 attempts per policy/cadence/parent. No cadence improved their
respective best product ranks 1634/1530/381/536. Some equal-rank parents had
different densities or identities. Observing every attempt raised native
elapsed times from roughly 0.07–0.11 seconds to 1.47–6.16 seconds per arm in
this concurrent-fleet experiment; this is not an isolated throughput test.
The production observation policy is not changed.

The new binary also reproduced all 144 saved winners and search counters
from three prior default-cadence runs exactly. Focused native integration
tests passed 4 tests/211 assertions. Evidence is in
`/private/tmp/metaflip-observation-study-20260906`, with the broader independent
audit described in [the coverage report](SEARCH-COVERAGE-AUDIT-2026-09-06.md).

## Reusing the new parents

Appending the observed winners to the frozen earlier corpus gives 324
term-order-distinct parents instead of 204. With the same 148 leaf witnesses,
16 mixed-packing trials, maximum scale 4 and dimensions 16, the composer
scored 9,772 products across the same 352 target shapes. **19 local results
improved**, saving 59 terms summed across those separate targets. Examples:
8x8x9 387→381, 7x8x8 309→302, 6x8x9 308→302, and 6x6x9 235→231.
These are comparisons with our frozen local corpus, not published records.
All 352 recipes passed independent tensor reconstruction: 161,661 terms,
4,933,137 support-pair XORs.

The experiment also exposes missing leaf-library coverage. The initial
fallback ranks for 2x3x3 and 2x4x4 were 17 and 28. Pinned Hopcroft–Kerr
catalog witnesses at ranks 15 and 26 were subsequently imported **only into
a temporary comparison library**, reduced modulo two, and independently
reconstructed by the existing Python importer and Ruby checker. That is
known-algorithm reuse, not a discovery. Original-library results above remain
unchanged; enriched-library results must be reported separately. No imported
catalog data was added to the bit's distributable seed directory.

Holding the same 324 parents and all scan limits fixed, the 150-leaf library
improves another **70/352** product results, with 1,869 terms saved in total.
All 352 enriched-library outputs passed independent verification: 159,792
terms and 5,213,450 support-pair XORs. This is a library-coverage ablation,
not an improvement caused by additional flip attempts. A separate matched
2x2x5 rerun now reaches the known 5x8x8 rank 230; greedy and annealing still
have fewer improving trials than ordinary wandering (2/16 and 3/16 versus
15/16).

Three enriched-library candidates are saved in the research artifact's
`enriched` subdirectory, with complete recipes and license cautions:

| Canonical shape | Exact GF(2) rank | Constructive formula |
|---|---:|---|
| 10x16x16 | 1535 | 50*26 + 5*47 |
| 10x12x12 | 895 | 50*15 + 5*29 |
| 8x12x15 | 896 | 52*15 + 4*29 |

These use five U-pairs or four V-pairs in the existing rank-60 4x4x5 parent.
They save 25, 5, and 4 terms compared with ordinary products using the same
parent and enriched library. The old local block manifest contains rank
1558 for 10x16x16; the first candidate is 23 below that local witness. The
pinned public catalog filename minima are respectively 1560, 900, and 904,
but those mixed-field filename comparisons are not independent GF(2)
comparator verifications or exhaustive novelty checks. No record is promoted.

The enriched audit is `/private/tmp/metaflip-bud-products-20260906-enriched`;
the normalized source/field audit is
`/private/tmp/metaflip-bud-leaf-library-20260906/source-audit.json`.
Candidate copies remain outside the dual-licensed bit. Redistribution of the
new catalog-derived data has not been cleared.

The final Python 3.14.7 aggregate replay passed all 432 native-study outputs
plus the four retained research witnesses: 436 cases, 134,159 terms and
2,969,581 support-pair XORs. Focused checks passed for the native scorer, the
two native end-to-end tests (107 assertions), twelve composer tests (97
assertions), and five tensor-verifier tests (43 assertions). Invalid prices,
strategy names, nonzero in-width tensor corruption, and output overwrite
attempts are rejected. No full repository test suite was run.

## Replay and tests

From the bit directory:

```sh
tungsten --release --native -o /tmp/bud-parent-walk tools/bud_parent_walk.w
tungsten --release --native -o /tmp/bud-parent-score-test spec/bud_parent_score_test.w
/tmp/bud-parent-score-test
METAFLIP_BUD_WALK_BINARY=/tmp/bud-parent-walk ruby spec/bud_parent_walk_test.rb
ruby spec/bud_products_test.rb

ruby tools/bench_bud_parents.rb --binary /tmp/bud-parent-walk \
  --parent lib/metaflip/seeds/gf2/matmul_2x2x9_rank32_d156_perminov_2025_pperm_cycle_gf2.txt \
  --scale 4x4x1 --trials 16 --chunks 512 --steps 512 \
  --output /tmp/my-bud-parent-study

ruby tools/bud_products.rb --replay ../../benchmarks/matmul/metaflip/bud_parent_walk_2026_09_06/8x8x9.recipe.json
python3 tools/verify_bud_products.py \
  --verifier ../../benchmarks/matmul/metaflip/verify_block_composition_records.py \
  ../../benchmarks/matmul/metaflip/bud_parent_walk_2026_09_06/8x8x9.recipe.json
```

Evidence directories are `/private/tmp/metaflip-bud-parent-20260906-{225,227,228,229,234,235,335}`,
the `229-fine` follow-up, and `/private/tmp/metaflip-bud-products-20260906-walk-corpus`.
The native binary SHA-256 was
`d0643d32da3bad11a38c54b69fcce3cbf1171bdf1f22783ae95cf1e34595dd8f`.
The saved research recipe and leaf lineage are described in
`benchmarks/matmul/metaflip/bud_parent_walk_2026_09_06/README.md`.
Its rank-60 leaf has GPL lineage; it remains outside the dual-licensed bit.
