# Exact bud-product search, 2026-09-06

The new offline composer produced an exact **8x8x9 rank-387 GF(2)** witness.
This is a candidate for a better published bound, not a confirmed world-record
claim. It is a composition of existing witnesses, not a new rank drop in a
primitive shape. Nothing was published, submitted, committed, or injected
into the live fleet's archive.

Follow-up: the [native parent-walk study](BUD-PARENT-WALKS-2026-09-06.md)
reached exact rank 381. The rank-387 evidence below is retained as the frozen
baseline. The improved witness uses the already-published Lille grouping
with lower-rank GF(2) leaves, so the grouping is not a new construction.

The construction implements the single-equal-factor cases of the established
[serendipitous product](https://arxiv.org/html/2606.02480v1). A U bucket of k
terms represents a mapped `<1,1,k>` tensor; V and W buckets analogously give
`<k,1,1>` and `<1,k,1>`. Product leaves may be mapped non-injectively: zero
terms are discarded and exact duplicate terms cancel by XOR. The full output
tensor is independently reconstructed before it is saved. More general
multi-axis grids and exhaustive mixed-bucket partitions are not implemented.

## Search evidence

All runs used the same 148 checked-in GF(2) witness files as the leaf library.
Missing leaves use verified block sums or the naive algorithm, never an
unwitnessed catalog rank. Products have dimensions at most 16 and scale
coordinates at most 4. Three pure-axis partitions use dynamic programming;
mixed-axis trials are deterministic greedy packings with seed 12345.

| Parent set | Trials per scale | Products scored | Target shapes materialized |
|---|---:|---:|---:|
| Seven rank/density leaders | 8 | 177 | 122 |
| Their frozen 63-file live archive | 8 | 1,593 | 122 |
| Curated corpus plus that archive: 204 term-order-distinct parents | 16 | 5,716 | 352 |

The archive improves **28 of 122** exact product ranks over the leader-only
control, saving 102 terms summed across those 28 independent targets. Three
winning recipes use a parent above its shape's minimum rank. For example,
5x8x8 improves from 256 to 243 with a rank-20 2x2x5 parent instead of rank 18;
this still loses to the public rank 230. This is evidence for retaining
composition-useful parents, not 28 new records or a time-matched flip-search
benchmark. All controls use frozen snapshots, not concurrently changing files.

The 352 corpus recipes replayed exactly (161,720 terms). The older independent
Python block verifier also checked all 352, reconstructing 4,889,724 support
pairs. A deliberately corrupted coefficient was rejected. The code's focused
tests cover all three bud axes, six dimension permutations, dense factors,
wide integers, block leaves, parity cancellation, overlapping/bad partitions,
snapshot hashes, reproducibility, and CLI overwrite refusal.

The CPU/GPU fleet continued throughout these bounded scans: 16 CPU lanes and
8,192 GPU walkers, using the CPU/GPU-overlap scheduler. The composer is not a
new production fleet lane; no efficacy claim is made for feeding these wide
products into the existing u64 kernels. Core ML remains unpromoted.

## Rank-387 construction and comparison

Use the existing `2x2x9_rank32_d156_perminov_2025_pperm_cycle` parent, scale
`(4,4,1)`, and disjoint U groups of sizes `5,5,4,4,4,4,4,1,1`:

`2 * R(4,4,5) + 5 * R(4,4,4) + 2 * R(4,4,1) = 2*60 + 5*47 + 2*16 = 387`.

The output has density 5966 and SHA-256
`36e8029b64a6a85803072e5eef59762ea00061f420da8ba883b8ee8498ebc93b`.
Its 576 required nonzero tensor positions and every off-support coefficient
were checked by both implementations. This witness is GF(2)-only; integer or
characteristic-zero correctness is not implied.

The [Lille page](https://fmm.univ-lille.fr/8x8x9.html) lists rank 388.
The [matmulcatalog](https://github.com/solven-eu/matmulcatalog/tree/f3a7f0f61b1005666c2cb03f98f2a16727604ea0)
tree at `f3a7f0f61b1005666c2cb03f98f2a16727604ea0` contains rank-388 derived
schemes in all three distinct orientations and rank-391/rank-412 catalog
witnesses. Its rank-388 scheme has F3/Q/R/C metadata and coefficients with
denominators 2, 4, and 8: it cannot simply be reduced modulo 2. The rank-391
ternary witness was fetched at that pinned commit, transposed into output-row
order, reduced mod 2, and exact-verified. Thus 387 saves four terms against
that verified GF(2) comparator. The
[FastMatrixMultiplication table](https://github.com/dronperminov/FastMatrixMultiplication/tree/db560ca5811bc38d5a6d5c0a3ec4315937ceabce)
at `db560ca5811bc38d5a6d5c0a3ec4315937ceabce` likewise lists 391 (ZT/Z) and
388 (Q). These bounded catalog checks do not establish that no other or
implicit construction is known.

Other numerical catalog beats from this scan include ordinary tensor-product
rediscoveries and rows already beaten by this repository's older block
campaign. They are deliberately not promoted as new records.

## Replay

From `bits/tungsten-metaflip`:

```sh
ruby spec/bud_products_test.rb
ruby tools/bud_products.rb --replay ../../benchmarks/matmul/metaflip/bud_products_2026_09_06/8x8x9.recipe.json
python3 tools/verify_bud_products.py --verifier ../../benchmarks/matmul/metaflip/verify_block_composition_records.py ../../benchmarks/matmul/metaflip/bud_products_2026_09_06/8x8x9.recipe.json
```

To rerun the corpus scan into a new output directory (the live archive is
optional; all inputs are read once and snapshotted):

```sh
ruby tools/bud_products.rb --output /tmp/my-bud-products --trials 16 lib/metaflip/seeds/gf2/*.txt
```

The full September evidence directories are
`/private/tmp/metaflip-bud-products-20260906-{live,leaders,corpus}`. Each has a
hashed input manifest, report, and self-contained recipes. The saved rank-387
recipe and its required witnesses live in the repository's research directory
`benchmarks/matmul/metaflip/bud_products_2026_09_06`, outside the dual-licensed
bit: the rank-60 leaf has third-party GPL lineage. Follow `THIRD_PARTY.md` and
the asset-level attribution before any redistribution. No relicensing is
implied by generation or verification.

Next experiment: score short, same-rank parent walks by these exact product
costs and retain the best composition parents separately. General multi-axis
blocks and missing low-rank leaves should also be measured against this
bounded baseline before adding runtime complexity.
