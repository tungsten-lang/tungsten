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

## Refining a retained paired map

`--dual-edit-radius 1`, `2`, or `3` explores an audited paired-map winner's
neighborhood, instead of returning to coordinate or weight-two kernels. An
edit toggles one bit in the concatenated `(u,v)` pair. The family contains
every nonzero pair at the declared total bit distance with odd inner product,
including the center first. It retains the canonical least-pivot basis and
fixes the other dimensions' keep sets. It does not walk the tensor's terms.

```sh
nice -n 10 python3 -B benchmarks/matmul/metaflip/refine_fold_projections.py \
  --seed AUDITED_PAIRED_DIRECTORY:OUTPUT_INDEX \
  --prices PRICE_PLAN --output NEW_SCAN \
  --dual-edit-radius 2 --max-views-per-seed 2000
nice -n 10 python3 -B benchmarks/matmul/metaflip/verify_refined_fold_projections.py \
  --root NEW_SCAN --output NEW_SCAN/independent-audit.json --workers 1
```

Neighborhood mode requires a previously audited paired-map seed and rejects
mixed anchor/fold-family options. Its exact size is checked before opening a
parent or allocating caches. The independent checker reconstructs the maps,
checks the declared bit distance and unchanged other-axis coordinates, then
replays cleanup and the complete tensor. It certifies retained constructions,
not every trial rank, seed-lineage history, or an exhaustive rank minimum.

The two-bit runs tested 977 maps around the 20x23x29 winner and 1,409 around
the 19x24x27 winner. They tied 7,430 and 6,854, respectively, in 74.77 seconds
CPU. A three-bit run around the first winner tested 13,725 maps in 222.66
seconds CPU and also tied 7,430. The first 977 maps are included in that wider
family, so these runs cover 15,134 distinct parent/map combinations, not
16,111. These are finite negative search results, not optimality claims.

Five alternate cleanup orders added 4,885 evaluations of the first two-bit
family in 95.62 seconds CPU. All tied 7,430. Orders beginning with factor 1,
and order `(2,1,0)`, produced a second exact representation at term-set
distance 80 from the original. It is a structural alternative, not a lower
rank. No raw-rank pruning was used in any of these scans.

All 91 focused Python tests pass, including brute-force small bit balls,
nontrivial odd-overlap kernels on all three axes, all six cleanup orders,
audited-seed chaining, pre-allocation limits, incompatible modes, and corrupt
radius/center/coordinate/report rejection. The new strategy remains offline;
it changes no live CPU/GPU fleet defaults.

## Downward replay and another composition pass

Both rank-7,430 representations were screened through every one- and
two-axis coordinate deletion, followed by cleanup: 3,558 views in 199.31
seconds CPU. This found **20x23x28 at rank 6,970**, improving 6,982. The
winner comes from deleting coordinate 0 of dimension 2 from the original
20x23x29 tensor; no additional cleanup is needed. The alternative parent
did not give a lower minimum. Thus this gain is downward propagation of the
earlier all-anchor winner, not a successful radius-three map refinement.

Independent replay checked all six retained projections: seven tensors,
50,117 terms, and 10,904,445 support-pair XORs. The stronger result remains
below the saved restriction-corrected reference of 7,050. This strengthens an
existing comparison crossing; it is not a new crossing or a novelty proof.

The checked alternative, six projected endpoints and previously expanded
21x23x29 block were admitted by exact tensor identity, adding eight parents
for 31,283 total. A full, non-reused pricing pass checked 2,722,001 expressions
(835,454 mixed-bud expressions) in 55.47 seconds CPU. Seventeen prices fall:
the direct shape and sixteen block descendants. Fifteen were already in the
audit cohort; 20x23x32 and 23x23x32 are newly improved cohort shapes.

The 21x23x28 block was expanded at **7,614**, down from 7,626. Its independent
audit checked four recipes and four tensors, 15,229 terms and 3,292,137 XORs.
Other examples remain recipe-only: 20x23x30=7,681, 20x23x32=8,182,
22x23x28=7,962, and 23x23x32=9,823. Superseded witnesses are removed before
counting: the cumulative cohort is **389 lower local prices, 55 expanded at
their current best price and 334 recipe-only**. All nine cohort crossings
remain expanded; the larger metadata shortlist is still 49. There is no new
main-square or primitive-rank improvement.

New evidence is kept as a single local-only, hash-deduplicated compressed
archive outside the checkout:
`~/.local/share/tungsten-metaflip/evidence/2026-09-08-dual-neighborhood.tar.gz`.
It retains reports, source/checker snapshots, witnesses, recipes and the
scoped reference refresh. The large composition input uses a lossless
base-prefix-plus-tail delta against the prior archive instead of another
full copy. Retained-tensor replay is self-contained after materializing the
manifest; producer reruns additionally need the pinned ancestry inputs.
Existing unpacked archives were not moved or deleted.
The archive is 14,142,702 bytes: 108 logical files stored as 84 unique objects.
The 498,647,805-byte corpus round-trips exactly from its 496,027,008-byte shared
prefix plus a 2,620,797-byte tail. The archive hash is
`9c783041e370db209146e20db1c68f4d635eeb9c055b168416a86016c7da2e2e`.
