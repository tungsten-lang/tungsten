# Wider exact-parent search and archive controls

No confirmed world record. The retained
[research fixture](../../../benchmarks/matmul/metaflip/catalog_parent_search_2026_09_06/README.md)
contains four complete bud constructions, three stronger block witnesses and
all 435 comparison rows. Imported/derived data is not part of the bit's
distributable runtime. No canonical record ledger, commit, publication or
submission was changed.

## Verified coverage

The catalog import scanned 450 pinned source paths (known, constructed,
curated and bud-base schemes, each dimension 2..8). It admitted 413 explicitly
F2-verified entries, corresponding to 404 files and 362 distinct term-level
parents. All source Git blobs and converted tensors were checked. Thirty-seven
paths without the required explicit F2 verification were excluded; none was
accepted on a rank label alone.

The broader set produced 25,237 parent/scale combinations over 435 targets.
The 908-file leaf/comparison library included prior exact recursive and
uneven-block results, rather than only the original 150 leaves. Its recursive
block/Kronecker closure remains a bounded comparison family.

At 32 mixed-grouping trials per combination, 125 target ranks beat this local
baseline. Examples: 3x12x12 324→323; 8x10x16 826→812; 10x12x16 1188→1158;
12x14x16 1624→1601. They are known-parent coverage gains, not new primitive
flip discoveries. Current catalogs do not provide a complete GF(2) novelty
oracle, so these are not labeled world records.

## Controlled retention and grouping comparisons

All controls used the same leaf library, bounds and random seed:

| Parent policy | Distinct parents | Combinations | Targets where full set is better |
|---|---:|---:|---:|
| All term-distinct variants | 362 | 25237 | — |
| All minimum-rank variants | 245 | 20663 | 37 |
| One minimum-rank/density representative | 95 | 5205 | 124 |

This establishes a coverage loss, not throughput superiority: the policies
spend different computation. With the full set and identical library,
mixed grouping beats pure-axis grouping on ten targets. The earlier wide
pure-axis run used a smaller library and is not that ablation.

The minimum-rank control loses 10x12x16 (1190 vs 1158) to a rank-48 3x4x5
parent, and 12x14x16 (1634 vs 1601) to a rank-67 3x4x7 parent. Parent rank or
density alone is therefore not a sufficient admission objective for product
search. Keep exact parent identities and assess constructive child costs;
this does not justify dominance pruning of future flip continuations.

The bounded set-packing checker matched all 36 shortlisted formulas, with
every component search complete and no cutoffs. This is optimality only
within disjoint equal-factor groups, fixed parents, fixed prices and leaf
bound 16. More retries cannot lower those formula costs without changing the
model or parents; post-mapping tensor cancellations are also outside that
formula objective.

`bud_packings.rb --recursive-products` now explicitly matches the leaf-price
policy used by the product search. Without it, a product-priced baseline is
still rejected when its prices differ. A regression test checks the 4x4x4
Strassen product price 49 versus the block-only price 56, then replays the
matched result.

## Stronger comparisons and negative walk result

Seventy exact uneven-block comparisons were reconstructed with the existing
native block composer, using rank-7 and rank-47 outer tensors and 120 exact
leaves. Of 35 shortlisted targets eligible for both outers, 26 bud outputs
remain strictly better than those two comparisons. Others are matched or
beaten: 7x12x12 666→657, 12x12x15 1320→1315, 14x14x16 1922→1881.
The remaining shortlisted target has minimum dimension three and was not
part of this two-outer screen. Balanced allocations/minimum-formula ties do
not exhaust arbitrary block constructions.

A fresh rank-48 3x4x5 parent walk used 16 trials × 2048 chunks × 512 attempts
for each of walk/greedy/anneal, density slack 16 and rank debt 2. All three
arms remained at product rank 1158. They are 50,331,648 matched total attempts,
not a throughput comparison with the concurrent fleet.

## Verification

- Independent pure-axis audit: 435 tensors, 197541 terms, 11423814 pair XORs.
- Independent mixed + parent-walk audit: 483 tensors, 253061 terms, 16026225 pair XORs.
- Independent uneven-block audit: 70 tensors, 74937 terms, 4342985 pair XORs.
- Independent bounded-packing audit: 36 tensors, 36916 terms, 3177326 pair XORs.
- Retained fixture: 21 tensors, 8310 terms, 524779 pair XORs; all four recipes replay.
- Focused packing specs: 7 tests/144 assertions; product specs: 14/130.

Private complete evidence roots:

- `/private/tmp/metaflip-catalog-parents-20260906-wide`
- `/private/tmp/metaflip-wide-catalog-comparison-20260906`
- `/private/tmp/metaflip-catalog-products-20260906-wide-axis-matched`
- `/private/tmp/metaflip-catalog-products-20260906-wide-mixed`
- `/private/tmp/metaflip-catalog-products-20260906-wide-minrank`
- `/private/tmp/metaflip-catalog-products-20260906-wide-leaders`
- `/private/tmp/metaflip-wide-catalog-packings-20260906`
- `/private/tmp/metaflip-wide-triage-20260906`
- `/private/tmp/metaflip-bud-parent-catalog345-442-20260906`

The live fleet remains separate: 16 CPU lanes plus 8192 GPU walkers, state
`/private/tmp/metaflip-record-search-20260906-gpu-recovery`, indefinite runtime.
No production binary or archive was changed during this study.

Next useful experiment: richer elementary groups and new parent identities.
The [serendipitous-product paper](https://arxiv.org/html/2606.02480v1)
describes multi-axis elementary blocks as well as same-factor buds; any
extension should first implement exact group/map validation and independent
tensor replay. Repeating already-complete fixed-parent packing searches is
not evidence of broader exhaustion.
