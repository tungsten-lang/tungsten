# Elementary groups and exact grid packing

The research product search now supports checked elementary groups, not
only equal-factor buckets. It found a **6×9×9 rank-338 GF(2)** construction;
both checked explicit-F2 catalog comparators have rank 341. This is not a
confirmed world record. The lower rank-332 catalog entry excludes F2.

[The retained research fixture](../../../benchmarks/matmul/metaflip/elementary_grid_search_2026_09_06/README.md)
contains the construction, raw pinned sources, comparator witnesses,
original search code and independent verification commands. Nothing was
published, submitted, committed or added to the distributable seed set.

## Interface and exactness

```sh
ruby bits/tungsten-metaflip/tools/bud_products.rb \
  --library /path/to/exact/leaves --recursive-products \
  --grids --grid-side 3 --max-scale 8 --max-dimension 16 \
  --trials 32 --output /new/output /path/to/parents/matmul_*_gf2.txt
```

Both `bud_products.rb` and `bud_packings.rb` accept `--grids`; the default
maximum side is 2. `--grid-side 3` admits 2×3 and 3×3 rectangles as well;
the bounded option permits sides through 4. Without `--grids`, legacy search
behavior is retained. Larger-side packing is not enabled by default.

Schema-2 groups carry `elementary_shape` and term indices in i,j,k order.
The checker derives and validates each factor's linear map. It rejects
inconsistent coordinate images and overlapping/missing parent terms, while
allowing noninjective maps and exact GF(2) cancellations. Existing schema-1
recipes remain supported; schema 1 cannot silently contain elementary groups.
The map layer handles general elementary shapes; the search enumerator is
restricted to rectangles in two factor classes, with the third factor free.

Only positive formula-gain groups are packed. Candidate/state/component
limits produce a legal fallback with a false optimality flag, not a false
exhaustion claim. A completed packing is optimal only for the stated
fixed-parent, fixed-leaf-price group model, not arbitrary tensor rank or
post-mapping cancellation. Exact tensor reconstruction remains the admission
gate for every exported result.

## Results and controls

- Same 362 parents, 908 exact library files, 25,237 combinations, 435 targets.
- Side 2: 13 lower product formulas; six below both previous local controls.
- Side 3: four additional lower product formulas; all 2,043 packing jobs complete.
- Recursive reuse of side-2 results: eight further finite-library improvements.
- All original 435 recipes still replay byte-for-byte. The independent
  verifier checked 435 outputs per pass; retained evidence includes all maps.
- A complete six-order two-equal-factor cleanup sweep produced no extra
  reduction on the side-2 outputs.

## Enumeration performance

A native process sample identified repeated row-combination enumeration and
array intersections as the larger-grid bottleneck. The optimized enumerator
uses column bitsets and prunes a row prefix when fewer than the required
number of common columns remain. Adding rows can only shrink that set, so
the pruning is exact. It preserves duplicate-cell choices and output order.

A paired old-then-new pass over every parent produced exactly the same
150 ordered grids. Its summed enumeration times were 183.241 seconds and
0.162 seconds. That comparison ran alongside other work and is not a
controlled end-to-end throughput benchmark. Full-search replay, not that
ratio, is the correctness gate.

The full side-3 rerun reproduced all 435 recipe files byte-for-byte, with
the same 25,237 combinations and 2,043 complete packing jobs. Observed
elapsed time fell from 319.536 to 132.991 seconds. Background loads differed,
so this is an observed same-workload timing, not an isolated 2.4× throughput
claim; `performance.json` retains the hashes and comparison.

Focused checks cover general maps, malformed groups, all axis orientations,
duplicate choices, independent small subset/partition exhaustion, cutoff
fallbacks, schema replay, side-4 enumeration and more than 64 column classes.
No production fleet engine, binary or runtime manifest changed in this work.

Private evidence:

- `/private/tmp/metaflip-elementary-grids-20260906-all`
- `/private/tmp/metaflip-grid-comparator-20260906`
- `/private/tmp/metaflip-elementary-grids3-20260906-all`
- `/private/tmp/metaflip-elementary-grids3-fast-20260906-all`
- `/private/tmp/metaflip-elementary-closure-20260906`
- `/private/tmp/metaflip-grid-enum-fast-probe-20260906.json`
- `/private/tmp/metaflip-grids3-sample-20260906.txt`

## Native parent-objective followup

The offline native walker now accepts square parents and an optional fifth
price-table row, `grids Puv Puw Pvw`. It scores one 2×2 elementary grid plus
the best pure-axis complement. `bench_bud_parents.rb --grids` constructs this
table from exact leaf witnesses and independently reconstructs the grouping.
`--recursive-products` matches the recursive leaf pricing used above. Old
four-row price tables preserve pure-axis behavior. This is a read-only
constructive objective, not a change to production fleet acceptance.

A matched 100,663,296-attempt test recognized the existing 338 construction
but found no improvement. A second, 301,989,888-attempt matched test covered
all twelve catalog 3×3×3 parent variants with denser observations and wider
excursions. It produced 202 distinct best/end parents. Their 25,048 product
combinations did not improve any of 34 target ranks over the original
twelve-parent control. All native products and both target sweeps passed
independent tensor checking; all 4,588 expanded packing jobs completed.

The [retained parent-walk audit](../../../benchmarks/matmul/metaflip/grid_parent_audit_2026_09_06/README.md)
also records stronger block controls: 9,714,243 positive allocation/orientation
combinations across three outer witnesses did not beat the four candidates
listed in the earlier fixture. These are finite-family controls, not a record
oracle or an exhaustion of higher-formula cancellation opportunities.

The comparison wrapper now filters unreachable leaves before balanced
tie materialization. Four timed checks fell from 126.982 to 1.188 seconds,
with byte-identical certificates; startup/library load is excluded and other
work ran concurrently. No production composer or flip engine was changed.

Next useful search should change the move/construction family or outer
witness, not treat more walks through this sampled rank-23 neighborhood as
evidence of progress. Do not infer primitive-rank progress from a cheaper
composition formula.
