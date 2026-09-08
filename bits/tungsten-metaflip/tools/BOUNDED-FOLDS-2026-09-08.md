# Bounded folds of checked projection maps

`refine_fold_projections.py` starts from explicit keep sets in an independently
audited coordinate-projection report. It tries one-sided XOR folds of each
single deleted shared coordinate, with bounded mask Hamming weight. The other
incident factor still uses the ordinary coordinate map. These maps satisfy
`M*N^T = I`, so they preserve the matrix-multiplication tensor. Exact shared-pair
cleanup runs before comparing ranks; there is no raw-rank pruning.

The existing fold cache used to materialize all `2^k` masks per distinct factor
word. It now keeps that dense path only for `k <= 8`. Larger coordinates store
the base word and `k` XOR additions, evaluating only requested masks, once per
distinct word. A 31-coordinate fold no longer attempts a billion-entry table.
The original exhaustive fold CLI still has its family-size guard and unchanged
search scope; this new runner supplies a separate, explicitly bounded family.

## Bounded large-parent result

Three saved maps were tested, all over GF(2):

| Target | Coordinate + cleanup | Fold + cleanup | Saved corrected reference |
| --- | ---: | ---: | ---: |
| 19x24x27 | 6,872 | **6,854** | 6,830 |
| 14x29x30 | 6,952 | 6,952 | 6,918 |
| 19x23x28 | 6,898 | 6,898 | 6,820 |

The winning 19x24x27 image comes from the checked rank-7,042 20x24x28 parent.
Its keep set deletes coordinates 16 and 24 on the first and third dimensions.
The fold acts on factor 2 along dimension 2 with mask `1 << 16`. The projected
rank is 6,932; shared-pair cleanup follows 6,932 -> 6,926 -> 6,854. This removes
18 terms beyond the previous selected bound. It remains 24 above the saved
reference, so this is not a world-record claim.

Weight-at-most-one masks took 237 views, 6.33 seconds wall / 6.28 seconds CPU.
The weight-at-most-two superset took 2,941 views, 67.90 seconds wall / 67.75
seconds CPU, with no further reduction. The latter includes the first 237
views; these are not 3,178 distinct maps. Both runs used one `nice -n 10` CPU
worker, no GPU or fleet. These are workload timings, not a general throughput
speedup claim.

Each run's retained outputs passed independent dense-grid fold reconstruction,
separate sort/group cleanup replay and full tensor expansion: five tensors,
34,736 terms and 9,056,352 support-pair XORs. Both reports retained the same
three literal outputs. The audit validates the reported constructions and
their reduction traces, not unreported minima or exhaustion of linear maps.

## Restrictions, composition and cumulative accounting

The folded tensor was also tested over its 70 one-axis coordinate deletions,
again with cleanup before selection. This independently verified two further
reductions: 19x23x27 from 6,866 to **6,758**, and 19x24x26 from 6,825 to
**6,781**. This follow-up took 5.53 seconds wall / 5.46 seconds CPU. Its audit
expanded four tensors, 27,144 terms and 6,063,945 support-pair XORs.

The first admission pass added the folded tensor and six independently
audited literal representations from the prior two block constructions.
The second added the three newly projected representations. The final corpus
has **31,263 literal parents**, with 2,721,760 pricing expressions checked.
The seven net improvements against the previous closed plan are:

| Shape | Previous price | New price | Expanded at this price |
| --- | ---: | ---: | --- |
| 19x23x27 | 6,866 | 6,758 | yes |
| 19x24x26 | 6,825 | 6,781 | yes |
| 19x24x27 | 6,872 | 6,854 | yes |
| 19x25x27 | 7,385 | 7,367 | yes |
| 19x26x26 | 7,558 | 7,544 | no |
| 19x26x27 | 7,665 | 7,647 | no |
| 19x27x29 | 8,638 | 8,620 | no |

The 19x25x27 block was re-expanded from the folded parent plus a thin naive
leaf. Its independent recipe replay checked five tensors, 15,248 terms and
3,151,260 support-pair XORs. An initial expansion correctly rejected an
inherited price-only seed entry; the versioned replacement uses the recorded,
unchanged constructive recipe from the earlier plan instead of guessing a
leaf witness. The three remaining lower prices are recipe-only, not newly
expanded constructions.

The deduplicated cohort is **387 lower-local-price shapes: 52 expanded at their
current best price and 335 recipe-only**, up from 385/51/334. Four new or
stronger bounds were independently expanded; superseded higher-rank witnesses
are not counted as witnesses at the new prices. The saved restriction-corrected
reference shortlist remains 49, including nine cohort shapes, all nine
expanded. No new reference crossing occurred.

## Replay

```sh
nice -n 10 python3 -B benchmarks/matmul/metaflip/refine_fold_projections.py \
  --seed AUDITED_PROJECTION_DIRECTORY:OUTPUT_INDEX \
  --prices PRICE_PLAN --output NEW_SCAN \
  --max-mask-weight 1 --max-views-per-seed 2000 --pair-order 0,1,2
nice -n 10 python3 -B benchmarks/matmul/metaflip/verify_refined_fold_projections.py \
  --root NEW_SCAN --output NEW_SCAN/independent-audit.json --workers 1
```

Repeat `--seed` to refine several maps. The input audit must bind the selected
report, parent and child bytes. Output directories cannot be overwritten.
Use this dedicated checker, then the existing `extend_composition_parents.py
--projection` admission path. Literal tensor identity, not rank or a bucket
signature, remains the state key.

The **72 focused Python tests pass**. They cover dense/lazy cache parity,
all fold sides, additional restrictions,
large coordinates, every cleanup order on an exact toy family, allowance
checks before allocation, changed masks/ranks/orders/traces, stale seed
audits, invalid tensors with rebound hashes, and output protection.

Local-only evidence is retained under
`benchmarks/matmul/metaflip/refined_fold_audit_2026_09_08/`: both bounded fold
runs, the follow-up projections, admission/pricing passes, the checked block
construction, source snapshots, versioned drivers, cohort summary and checked
manifest. Its source resolutions also bind retained ancestry artifacts by
content hash; large input tables are losslessly compressed.

References here are the pinned September 8 comparison, not a new literature
audit. Imported tensors and derivatives remain local-only pending
redistribution review. No general-field lift, primitive/main-square
improvement, publication or confirmed world record is claimed.
