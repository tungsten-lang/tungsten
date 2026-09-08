# Projection continuation and unified walk admission

The structured-parent follow-up produced four independently expanded GF(2)
local improvements. None crosses the pinned reference screen, improves a
primitive/main-square rank, or establishes a new world record.

| Shape | Previous local | Checked construction | Pinned reference screen |
| --- | ---: | ---: | ---: |
| 8x15x15 | 1136 | 1135 | 1122 |
| 8x25x30 | 3556 | 3552 | 3516 |
| 16x18x24 | 3921 | 3918 | 3870 |
| 15x24x24 | 4851 | 4842 | 4720 |

All four shapes are new to the preceding bounded improvement cohort. Its
deduplicated total is **255 lower-local-price shapes**, with **18 expanded
outputs and 237 unexpanded recipes**. The scoped reference-crossing shortlist
remains **42**. These counts are not confirmed records or the historical
campaign's separate candidate tally. The reference numbers are from the
previously pinned mixed-field screen; this negative comparison was not a fresh
novelty audit, and reference-only prices never supply unchecked tensor leaves.

## Verified admission instead of one-off scripts

`verify_observer_walk.py` now accepts rank-only controls with no observer
sidecars. They must use exactly the four-row native price format. An extra
grid row or an `observers 0` header is rejected; neither silently changes the
objective. Sources, winners, endpoints, scores, and accounting still undergo
the full tensor replay. Runs with one through eight observers are unchanged.

`extend_composition_parents.py --observer-walk` consumes that report format
and its `independent-audit.json`, including ordinary rank-only controls. It
checks the audit/report digest, attempt and cell counts, all pinned source
bytes, and a matching full-tensor audit entry for each admitted tensor.
Every source, rank winner, endpoint, and observer winner keeps its full
oriented literal identity. Equal ranks or bucket histograms do not merge
search states. Pricing, materialization, and reference/novelty checks remain
separate gates; neither command mutates a live fleet archive.

```sh
nice -n 10 python3 -B benchmarks/matmul/metaflip/verify_observer_walk.py \
  --root /path/to/completed-walk \
  --price-plan /path/to/frozen-plan/report.json \
  --output /path/to/completed-walk/independent-audit.json

nice -n 10 python3 -B benchmarks/matmul/metaflip/extend_composition_parents.py \
  --inputs /path/to/prior/inputs.json --plan /path/to/prior/report.json \
  --observer-walk /path/to/completed-walk --output /path/to/new-pricing
```

The frozen plan and prior corpus require verified constructive ancestry.
The walk replay does not itself reverify price-plan leaves, reference bounds,
or larger products. Synthetic tests cover rank-only and observer admission,
equal-rank distinct states, endpoints, and mutations of the report, tensor,
price file, proof entry, shape, attempt count, and cell count. The four focused
modules pass 32 tests:

```sh
cd benchmarks/matmul/metaflip
nice -n 10 python3 -B -m unittest test_verify_observer_walk \
  test_extend_composition_parents test_projection_variant_portfolio \
  test_projection_composition_scan
```

## Bounded search

The coordinate scan selected **1,176 parents**: all newly imported/retained
literal identities since the pre-import corpus, plus the twelve prior walk
controls. It deleted zero or one coordinate on each axis, excluding the
unchanged parent and shapes with a dimension below two. It did not enumerate
arbitrary linear projections or deeper named target families.

Across **269,345 views**, retention kept **1,229 new literal images** within
two terms of the current local target rank. This includes 210 images above
their particular parent's minimum. Independent dense-coordinate replay checks
1,889 parent/image tensors, 126,194 terms, and 1,775,593 support-pair XORs.
The raw images give no lower price after complete bounded recomposition.

Each new image then received four trials of eight chunks of 65,536 attempted
moves, debt two, density slack four, observation interval 65,536, and RNG
912223. Forty-one identical-shape/starting-rank prior controls received the
same per-seed work. Four groups had no rank-matched control: 2x3x6 at 31/32,
4x4x7 at 86, and 4x5x6 at 92. All projected seeds were still searched.
Unequal cohort sizes and those missing controls preclude an aggregate
strategy win-rate claim.

The **1,270-seed, 2,663,383,040-attempt** run completed sequentially at low
priority, CPU only. No GPU or fleet stress run was launched. Full replay
checks **10,082 tensors, 517,863 terms, and 6,134,264 support-pair XORs**.
No primitive minimum improved. Admission adds 8,605 literal states beyond the
17,875-parent projected corpus, giving **26,480** parents. Recomposition
through side 32 gives the four prices above.

## Why these witnesses matter

The two 8x15x15/8x25x30 recipes use a **rank-76 endpoint**, not the saved rank
winner, from a rank-77 4x5x5 projection. It has five pairs in its V buckets.
It descends from a 5x5x6 parent with one coordinate removed on the first and
third axes. Its SHA-256 is
`2021045455f39d0b81765df17b2b67e63eebc5caf1e3a3b2201958b46686b23e`.
This identifies the retained witness; it is not an exhaustive claim that no
rank winner could realize an equivalent bound.

The 16x18x24 recipe uses a rank-73 4x4x6 winner reached from a rank-75 image of
a 4x5x7 parent. The 15x24x24 recipe uses a rank-90 4x5x6 winner reached from a
rank-92 image of the imported 4x6x7 source. None of the useful primitive ranks
is new; the improvements are in their composition structure.

All four products, their leaves, substitutions, and orientation changes were
independently replayed: **19 tensors, 23,028 terms, 2,805,866 support-pair XORs**.
A follow-up mixed-bucket/elementary-grid search on these four contexts found
no further gain, with limits of 40 active vertices, 100,000 states, 50,000
candidates, grid side four, and leaf side 32. All four searches report complete
within those model limits. A separate checker verifies the returned disjoint
covers and prices, not search optimality or exhaustion.

Local-only evidence lives in
`benchmarks/matmul/metaflip/structured_projection_audit_2026_09_08/`.
It retains the projection maps, completed walks, compressed pricing inputs,
four self-contained expanded products, packing checks, provenance, and the
deduplicated cohort ledger. Copied product/walk/projection checkers replay
without the earlier source tree. Full pricing regeneration still needs the
pinned earlier local ancestry. Imported tensors and derivatives remain out of
source commits pending redistribution review; no submission or publication
was made.
