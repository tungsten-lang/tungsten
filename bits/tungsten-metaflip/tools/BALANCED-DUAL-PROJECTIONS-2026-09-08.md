# Balanced dual projections without exponential tables

The offline refinement runner now supports `--dual-kernels`. It changes both
linear maps on one shared dimension, using nonzero kernels `u,v` with odd
GF(2) inner product and exact pairing `M*N^T = I`. Each kernel is the deleted
coordinate's unit vector plus at most one other unit vector. Other dimensions'
coordinate keep sets stay fixed. Pair cleanup runs on every complete image;
there is no raw-rank or intermediate-rank pruning.

This is optional. Ordinary one-sided folds and joint folds retain their
existing defaults. Dual mode rejects incompatible fold weight/axis options.
The entire bounded family is counted before opening a parent or allocating
projection caches, and exceeding `--max-views-per-seed` fails explicitly.

For one active dimension of size `n`, the fixed-anchor family has
`1 + n*(n-1)` views, including the coordinate control. This equals the view
count of the one-sided weight-at-most-two family, but not necessarily its CPU
cost. `--all-dual-anchors` instead tries every anchor. It covers every odd
pair of nonzero kernels of weight at most two on that dimension: 13,272 views
when `n=24`. This is a bounded strategy, not exhaustive general projection
search. The canonical output basis drops the least set bit of `u`, which can
differ from the shared anchor; both keep sets are recorded and checked.

## Memory and repeated work

Previously `WordMap` built `2**n` row combinations or column lookup entries.
That is unsuitable for the 20–32-wide shared coordinates in these products.
Dense tables remain for `n<=8`. Larger maps retain row chunks and evaluate
only requested XOR combinations, or only column chunks actually present.

The accelerated path also caches ordinary coordinate images and requested
XOR deltas. A new map changes only the affected output rows or columns. It
does not rebuild a complete lookup table or remap every unchanged bit.
Caches grow with requested masks and coordinate bases, not with all `2**n`
masks. Left-map streams continue to be reused for repeated `u` values.

The independent verifier still constructs dense matrices and checks their
pairing independently. Its tensor loop skips zero matrix entries, then uses
separate sort/group cleanup and full GF(2) tensor expansion. It does not reuse
the search's delta or lookup caches.

## Matched replay

The lazy implementation, before delta reuse, and the accelerated implementation
evaluated the same 1,690 views with identical proposal order, raw ranks, final
ranks, winner metadata, cleanup traces, parent bytes and retained tensor bytes.
Both used one CPU worker at `nice -n 10`, with no GPU or live fleet.

| Target | Views | Lazy-only CPU | With delta reuse | CPU reduction |
| --- | ---: | ---: | ---: | ---: |
| 20x23x29 | 553 | 23.040 s | 15.526 s | 32.6% |
| 19x24x27 | 1,137 | 34.953 s | 32.705 s | 6.4% |
| Total | 1,690 | 57.994 s | 48.231 s | 16.8% |

These are single matched runs, not a statistical throughput guarantee or a
live-fleet speedup. The larger scan still performs cleanup on every image.

## All-anchor improvement and negative controls

The fixed-anchor scans did not improve the current bounds: 20x23x29 reached
7,441 versus the existing 7,439, while 19x24x27 tied 6,854. A separate
4,095-view, weight-at-most-three one-sided scan also tied 7,439.

Moving the dual anchor produced a better result. All 13,272 sparse paired
kernels on dimension 1 of the rank-7,522 20x24x29 parent were checked, with
the other dimensions unchanged. The best 20x23x29 image has **rank 7,430**,
down from 7,439. It uses `u = (1<<12) | (1<<16)` and
`v = (1<<12) | (1<<8)`. The raw image has 7,450 terms; a shared-factor cleanup
on factor 0 removes 20. Its independent reconstruction and full tensor audit
checked 14,952 terms and 3,375,600 support-pair XORs across source and result.

The corresponding control rows in the scan demonstrate why both maps and
post-map cleanup matter:

| Kernels at anchor 12 | Raw rank | After cleanup |
| --- | ---: | ---: |
| Both unit vectors | 7,489 | 7,489 |
| Only `u` changed | 7,457 | 7,457 |
| Only `v` changed | 7,452 | 7,452 |
| Both changed | 7,450 | **7,430** |

Even the raw combined image is worse than the original anchor-23 coordinate
control at 7,442. A raw-rank threshold would miss the improvement. The full
all-anchor run used 301.57 seconds CPU. This is a valid GF(2) upper bound, not
optimality or a world-record claim: the saved corrected reference is 7,421.

## Composition and accounting

The new image and retained alternatives were admitted together with the
previous turn's checked block outputs. Exact identity deduplication yielded
eight additional literal parents, for **31,275** in the closed corpus. A full
pricing pass checked 2,721,979 expressions, including 835,454 mixed-bud
expressions, in 61.11 seconds CPU. It did not use the unchanged-expression
shortcut.

Six prices improved by nine terms each:

| Shape | Previous local price | New local price |
| --- | ---: | ---: |
| 20x23x29 | 7,439 | **7,430** |
| 21x23x29 | 8,106 | **8,097** |
| 22x23x29 | 8,467 | 8,458 |
| 23x23x29 | 8,928 | 8,919 |
| 23x26x29 | 9,985 | 9,976 |
| 23x29x29 | 11,102 | 11,093 |

The direct result and 21x23x29 block descendant are independently expanded;
the block audit checked four tensors, 16,195 terms and 3,293,183 support-pair
XORs. The other four improved prices remain recipe-only. The deduplicated
cohort is still **387 lower-local-price shapes: 54 expanded at the current best
price and 333 recipe-only**. Superseded witnesses are replaced before counting.
The restriction-corrected shortlist remains 49 shapes, with nine cohort
crossings, all nine expanded. There is no new reference crossing,
primitive/main-square improvement, or fresh literature audit.

## Replay

```sh
nice -n 10 python3 -B benchmarks/matmul/metaflip/refine_fold_projections.py \
  --seed AUDITED_COORDINATE_DIRECTORY:OUTPUT_INDEX \
  --prices PRICE_PLAN --output NEW_SCAN \
  --dual-kernels --max-views-per-seed 2000
nice -n 10 python3 -B benchmarks/matmul/metaflip/verify_refined_fold_projections.py \
  --root NEW_SCAN --output NEW_SCAN/independent-audit.json --workers 1
```

For the all-anchor 24-wide family, additionally pass `--all-dual-anchors` and
raise the allowance to 14,000. The output directory must not already exist.
Retained tensor audits do not certify the minimum of unreported candidates
or general search exhaustion. Imported tensors and derivatives remain
local-only pending provenance and redistribution review.

All **87 focused Python tests pass**, including dense/lazy/delta equivalence
through width 32, all small admissible kernel pairs, all three shared axes,
changing canonical pivots, every cleanup order, exact family counts, preflight
guards and corrupted report/source rejection. Existing projection and
composition tests remain green.

The local-only bundle at
`benchmarks/matmul/metaflip/balanced_dual_audit_2026_09_08/` retains the four
scans, independent audits, composition pass and expanded block, cumulative
summary, drivers, checker source closure, both historical producer snapshots
and a checked manifest. Ancestry inputs are resolved by content hash; large
input tables are losslessly compressed. The source-only commit excludes
imported tensors and generated witnesses. The expanded block has not yet been
readmitted as a literal parent for another pricing pass.
