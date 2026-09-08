# Mixed-cover reuse on retained 5x6x7 parents

Pricing mixed-axis groups and elementary grids on existing parents produces
**17 direct lower local composition prices and 52 more through recomposition**.
Four selected products pass independent full GF(2) reconstruction. Three are
below the refreshed, bounded reference comparison; these are **not confirmed
world records**. No primitive rank, main square rank, or live fleet setting changes.

## Reusable implementation

`benchmarks/matmul/metaflip/verify_parent_cover_scan.py` independently checks a
saved scan against its frozen corpus and price plan. It verifies literal source
identity and term order, every complete disjoint partition, each shared-factor
or grid substitution map, every reported formula price, and independently
recomputed pure-axis bucket prices. Each source passes full tensor replay.
Complete-scan claims must cover the entire declared parent/scale domain.
The producer's `exact_within_model` metadata is not an independent optimality
certificate; timeouts and bounded results are explicitly distinguished.

`extend_composition_parents.py --parent-cover DIR` admits those audited covers
to the existing literal parent, not to a rank/signature-equivalent substitute.
It rechecks factor maps, partition completeness, frozen inputs, source hashes,
term order, and cover hashes. Repeated covers are deduplicated while every
source occurrence remains in `admissions.json`. No new literal parent is needed.

Adding a cover to an existing parent invalidates append-only expression reuse:
the old certificate covers appended parents, not new expressions on old ones.
The extension therefore reprices fully when any new cover is added. A regression
test first verifies reuse with an unchanged corpus, then requires recomputation
after adding an existing-parent cover. Exact duplicate admission alone is harmless.

Example replay, with fresh output locations:

```sh
nice -n 10 /opt/homebrew/bin/python3 -B benchmarks/matmul/metaflip/verify_parent_cover_scan.py \
  --root SCAN --inputs BASE/inputs.json --price-plan BASE/report.json \
  --output SCAN/independent-audit.json
nice -n 10 /opt/homebrew/bin/python3 -B benchmarks/matmul/metaflip/extend_composition_parents.py \
  --inputs BASE/inputs.json --plan BASE/report.json \
  --parent-cover SCAN --output NEW_PLAN
```

The frozen plan must already have constructive ancestry. The scan checker does
not reverify its leaf library or materialize the implied larger products; use
`verify_composition_recipes.py --workers 1` after separately constructing selected
outputs. The retained scan driver uses the existing `bud_packings.rb` solver.

## Bounded experiment and products

The 31,215-parent corpus contained 198 literal 5x6x7 parents, only four of which
had retained mixed partitions. The scan covered all 120 integral scales through
side 32 for each parent: **23,760 cases**, yielding **3,634 saved covers**. Limits
were 24 component vertices, 50,000 states/candidates, elementary grid sides
through four, two seconds per case, and 180 seconds for the campaign. All cases
completed in 82.19 seconds. One `nice -n 10` CPU worker was used, with no GPU.

The scan audit checked 198 tensors, 29,705 terms, and 685,268 support-pair XORs.
Full repricing evaluated 2,461,730 total group expressions, including 575,742
mixed expressions (1,885,988 ordinary), in
54.79 seconds wall time. These are non-exclusive-host observations, not general
performance guarantees. The 69 improvements overlap earlier discoveries: only
**42 additional distinct shapes** enter the running improvement cohort.

| Shape | Previous local price | Independently expanded rank | Refreshed grouping comparison |
| --- | ---: | ---: | ---: |
| 14x30x30 | 6,996 | 6,990 | 6,996 |
| 20x24x28 | 7,050 | 7,042 | 7,050 |
| 20x24x29 | 7,530 | 7,522 | 7,530 |
| 25x28x30 | 11,288 | 11,266 | 11,189 |

The four outputs and their recipe dependencies independently replay as 27
shape/orientation tensors, 54,413 terms, and 14,114,733 support-pair XORs. No
unchecked numerical reference entry was used as a constructive leaf. All leaf
prices materialized at their planned cost using checked literals, block sums,
or Kronecker products; the constructor fails if such a leaf cannot be produced.

Useful exact formulas (R denotes an independently checked leaf rank):

- 14x30x30: `128*47 + 6*90 + 174 + 2*130 = 6990`, with leaves
  `(2,5,6), (4,5,6), (4,5,12), (5,6,6)` respectively. It combines singleton,
  same-axis, and elementary-grid groups.
- 20x24x28: `146*R(4,4,4) + R(4,8,8) = 146*47 + 180 = 7042`.
- 20x24x29: the preceding product plus a rank-480 20x24x1 block.
- 25x28x30: `120*76 + 5*146 + 7*144 + 2*204 = 11266`, with leaves
  `(4,5,5), (4,5,10), (5,5,8), (5,5,12)` respectively.

All three direct expanded products use the same retained rank-150 5x6x7
parent (corpus index 15495), imported from
[`structured/567.exp`](https://github.com/mkauers/matrix-multiplication/blob/12c26b29a5458e173813911fb4f2c2865fba841e/structured/567.exp),
not a newly discovered rank-150 scheme. Its GF(2) literal SHA-256 is
`42fd42dfc304d5b3139f4eaf30c5a8182b9e4d651324c36789e12f488d3e4513`;
the original source SHA-256 is
`2fc127c9cf9e284f57089940095d3f56ace5b79f80baf3d2bf9f195cb0b03182`.

## Reference scope and cumulative accounting

On September 8, fresh Git HEAD checks matched the retained data:

- `dronperminov/FastMatrixMultiplication`: `db560ca5811bc38d5a6d5c0a3ec4315937ceabce`.
- `solven-eu/matmulcatalog`: `f3a7f0f61b1005666c2cb03f98f2a16727604ea0`.

The four FMM Lille pages also fetched successfully with retained headers and
body hashes. The stronger comparison includes 8,453 catalog grouping families,
261 published families, and 359,973 expressions; 49 inconsistent rank-sum
partitions are explicitly excluded. It mixes reported fields and is comparison
metadata, not an independently constructive GF(2) bound. In particular,
25x28x30 is below its direct page listing but **not** below this stronger bound.
The comparison does not enumerate all elementary-grid/isomorphism possibilities
or establish novelty of a construction derived from the published parent.

The deduplicated cohort is now **300 lower-local-price shapes: 25 independently
expanded outputs at their current best price and 275 recipe-only candidates**.
The pinned scoped shortlist increases from 42 to **45** shapes. These are not
confirmed record totals and are separate from earlier historical campaign counts.

## Validation and local retention

All **60 focused Python tests** pass: cover replay, cover admission, expression
reuse, composition pricing/recipes, observer walks, coordinate projections,
parent walks, and factor-map replay. Mutation cases reject overlap, wrong grid
order/axis, identity/source/term-order drift, stale plan/audit hashes, false
prices, incomplete accounting, and a wrong tensor even with rebound metadata.

Local-only evidence is retained under
`benchmarks/matmul/metaflip/mixed_parent_cover_audit_2026_09_08/`, including the
frozen corpus/plan, source snapshots, all covers, expanded products, independent
audits, reference bodies, drivers, checker sources, provenance, and a verified
hash manifest. Large corpus JSON is gzip-compressed with its uncompressed hash.
Imported tensors and derivatives remain outside source commits pending
redistribution review. No live archive update, push, publication, or submission
is performed. Search and replay processes finish rather than leaving a fleet running.
