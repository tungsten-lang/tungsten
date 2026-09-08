# Joint folds without greedy prefix pruning

The bounded fold runner now supports `--max-folded-axes 2` (or 3). It combines
one-sided folds on distinct shared dimensions, allowing at most one deleted
coordinate per dimension. Each individual map still satisfies `M*N^T = I`.
The maps are applied in dimension order with no intermediate pair reduction;
the complete image is then simplified before its rank is compared.

This is an optional extension. The default remains the previous one-active-axis
family, with its original report format and behavior. The joint family has an
exact preflight view count, and over-budget families are rejected before
opening the parent or allocating projection caches. Recursive generation avoids
traversing combinations that exceed the active-axis limit.

Only the current prefix path is cached, not the whole Cartesian tree of
intermediate tensors. A three-axis map needs at most three live stage caches.
Dense small-coordinate and lazy large-coordinate fold tables are reused. A
process snapshot in the large run showed about 99 MB RSS on one low-priority
CPU worker; this is a sampled value, not a peak-memory guarantee.

## Exact non-greedy example

The checked rank-7,042 20x24x28 parent has a saved 19x23x28 keep set that deletes
coordinate 16 on dimension 0 and coordinate 22 on dimension 1. Two folds, both
on factor 0, interact as follows:

| Folds | Raw rank | Rank after cleanup |
| --- | ---: | ---: |
| None | 6,921 | 6,898 |
| Dimension 0, mask `1 << 12` | 6,930 | 6,899 |
| Dimension 1, mask `1 << 18` | 6,936 | 6,912 |
| Both | 6,926 | **6,897** |

Neither fold is an improving intermediate. Greedy prefix pruning would discard
both routes to the better combined image. Raw-rank pruning would also miss it.
The combined cleanup trace is 6,926 -> 6,916 -> 6,903 -> 6,899 -> 6,897.

All two-active-axis, weight-at-most-one folds of two fixed keep sets were
tested: 2,145 views for 19x24x27 and 1,833 for 19x23x28. The first stayed at
6,854; the second improved by one term. The 3,978-view run took 112.24 seconds
wall / 111.94 seconds CPU. Independent stage-by-stage dense-grid reconstruction,
separate sort/group cleanup and full tensor expansion checked three tensors,
20,793 terms and 4,874,104 support-pair XORs.

## Two more nearby shapes

A separate one-axis, weight-at-most-two run on two other saved maps tested
1,424 views in 21.67 seconds wall / 20.12 seconds CPU:

| Shape | Previous | Verified bound | Saved corrected reference |
| --- | ---: | ---: | ---: |
| 20x23x29 | 7,442 | **7,439** | 7,421 |
| 21x24x29 | 8,028 | **8,026** | 7,950 |

The first uses dimension 1 / factor 1 / mask 557056, with raw rank 7,447 and
cleanup 7,447 -> 7,442 -> 7,439. The second uses dimension 2 / factor 1 / mask
8320 and needs no pair cleanup. Both masks have two set bits. The separate
audit expanded four tensors, 31,051 terms and 7,696,796 support-pair XORs.

These are bounded constructive improvements over GF(2), not tensor-rank
optimality or confirmed world records. The 19x23x28 bound remains above its
saved reference of 6,820. A small diagnostic search over 768 seeded naive-walk
parents did not reproduce the non-greedy interaction; it does not supersede
the fully checked large-parent example.

## Composition and cumulative accounting

Admitting the three improved folded tensors and the previously checked
19x25x27=7,367 block gives a corpus of **31,267 literal parents**. A complete
pricing pass checked 2,721,772 expressions and lowered 15 prices: the three
direct improvements and 12 block descendants.

One descendant of each new parent was expanded and independently verified:

| Shape | Previous | Checked block bound |
| --- | ---: | ---: |
| 19x23x29 | 7,335 | 7,334 |
| 21x23x29 | 8,109 | 8,106 |
| 21x25x29 | 8,637 | 8,635 |

The recipe audit checked 12 tensors, 49,197 terms and 10,602,329 support-pair
XORs. Thus **six new or stronger bounds** were expanded this turn; the other
nine improved prices remain recipe-only. The three block outputs have not yet
been added back as literal parents for another pricing pass.

The deduplicated cohort remains **387 lower-local-price shapes**, now **54
expanded at their current best prices and 333 recipe-only**. No new shape was
added to the cohort in this turn; these were improvements within it. Superseded
witnesses are replaced or removed before counting. The restriction-corrected
shortlist is still 49 shapes, with nine cohort crossings, all nine expanded.
There is no new reference crossing or fresh literature audit.

## Replay

```sh
nice -n 10 python3 -B benchmarks/matmul/metaflip/refine_fold_projections.py \
  --seed AUDITED_COORDINATE_DIRECTORY:OUTPUT_INDEX \
  --prices PRICE_PLAN --output NEW_SCAN \
  --max-mask-weight 1 --max-folded-axes 2 --max-views-per-seed 3000
nice -n 10 python3 -B benchmarks/matmul/metaflip/verify_refined_fold_projections.py \
  --root NEW_SCAN --output NEW_SCAN/independent-audit.json --workers 1
```

The joint verifier validates distinct axes, each stage's paired linear maps,
the mask and axis allowances, the declared cleanup order and trace, and the
complete source/result tensors. It rejects duplicated axes, illegal sides,
changed ranks/orders/modes and incompatible metadata. Neither the old nor new
checker certifies unreported search minima or global exhaustion.

All **77 focused Python tests pass**, including all joint sides on small exact
tensors, cache-prefix switching in both traversal directions, all six cleanup
orders, preflight limits, repeated-axis rejection, identity controls and report
mutation checks. Existing single-axis and composition tests remain green.

Local-only evidence is retained in
`benchmarks/matmul/metaflip/joint_fold_audit_2026_09_08/`: both map scans, the
pricing pass, three expanded block products, all independent audits, the toy
diagnostic, source snapshots, drivers, cumulative summary and checked manifest.
Ancestry artifacts are resolved by content hash; large input tables are
losslessly compressed.

Imported tensors and derivatives remain local-only pending redistribution
review. No GPU/fleet run, general-field lift or primitive/main-square
improvement is claimed.
