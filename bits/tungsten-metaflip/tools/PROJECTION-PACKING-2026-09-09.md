# Projection scheduling and native-bank packing follow-up

This is a bounded GF(2) study and a tooling integration fix, not a new
world-record claim or a live-fleet strategy change. All searches used one
low-priority CPU process at a time, no GPU, and have stopped.

## Kept: the packer can reuse verified native banks

`bud_packings.rb` now accepts `--native-spool DIR` in both direct-parent and
`--from-report` modes. It calls the same bounded, immutable, full-tensor bank
loader as the composer and parent search. Without this option, a baseline
using native-only leaves could fail with `baseline leaf pricing changed`.
The option is explicit; default packaged-only behavior is unchanged.

Reports retain manifest/member provenance. Every used leaf is copied into the
self-contained exported recipe, so replay does not need the original spool.
An invalid bank fails before the output directory is created. No Ruby/Python
dependency was added to native MetaFlip, and no production acceptance policy
was changed.

Focused checks pass:

- `bud_packings_test.rb`: 8 tests, 158 assertions. Both CLI modes reproduce the
  known rank-7 Strassen construction, reject mismatched pricing/corrupt bank
  pointers, and replay after deleting the source spool.
- `bud_products_test.rb`: 17 tests, 145 assertions, including full-tensor bank
  forgery rejection with freshly recomputed hashes.
- `bud_packing_context_test.rb`: 6 tests, 242 assertions.
- A real direct CLI replay with the scale-3/4 native banks reproduces the
  rank-1,646 construction below.

```sh
ruby bits/tungsten-metaflip/tools/bud_packings.rb \
  --native-spool /path/to/status.txt.refinement \
  --from-report /path/to/bud-products/report.json --output NEW_DIRECTORY
```

`--from-report` consumes a bud-products recipe report, not a parent-walk
policy report. Report and direct-parent modes remain mutually exclusive.

## Rejected: replacing the projection selector with summed group cost

The current native worker selects one extra projection base by rank then
shared-pair count. The experiment compared that policy with minimizing the
sum of all nine fixed-axis scale-2/3/4 composition prices, weighted by
`144 / scale^2`. Rank and pair count broke ties. It also projected all six
basis proposals as a diagnostic; this larger family was not enabled.

Inputs were 121 native-width-compatible parents from the earlier 168-parent
compact corpus, plus 110 distinct endpoints from the latest walk study:
231 exact sources. The other 47 compact parents exceed the 63-bit limit.
All policies retained every basis proposal; only the projected base selection
changed. Complete sorted tensors, not bucket signatures, determined identity.

The combined family contained 10,134 independently tensor-checked objects.
Pair selection retained 5,236; summed group-cost selection retained 5,223.
The selector changed six choices, lowered no aggregate target minimum, and
worsened one from 1,654 to 1,656. Projecting all bases improved 20 prices
relative to the pair-selection control, but none beat an available retained
comparison. Seven of those targets are outside the dimension-32 comparator;
they are not credited as records or best-known results.

The old compact input price table predated its own successful projections.
Before counting gains, the follow-up switched to the later padding-corrected
table, SHA-256
`0b4ad918bd36a262797cb89017513cbed0fe07dbdb832df4d5462c4e4e2c0da7`.
The known rank-651 and rank-1,132 constructions are therefore not counted
again.

## Near-miss expansion and sparse paired projections

From the combined family, 160 recipes within 3% of the retained price and
within native wide-output limits were expanded. Selection kept at most three
per target before the global cap. Complete tensor checks preceded and
followed pair/matrix cleanup. No mapped cancellation or cleanup rank reduction
occurred in this sample. This does not rule out cancellations elsewhere.

A separate 33-parent study checked 12,058 sparse dual-kernel projections:
30 nonsquare shapes with maximum dimension eight/rank at most 128, plus
the packaged 3-, 4-, and 5-cube controls. Every image was pair/matrix cleaned;
there was no raw-rank prune. Retained children were independently rebuilt
with dense paired maps and checked as complete tensors. No noncoordinate
paired projection beat the retained bounds. The one lower price came from
an ordinary coordinate control and is included in the table below.

## Exact mixed packing and local results

All 891 combinations of those 33 parents and scales in `{2,3,4}^3` were
checked with the packaged plus verified native library. Limits were leaf
dimension 16, component size 24, 20,000 states and 20,000 candidates, with
elementary grids of side two. Every case completed within its finite packing
model. This certifies the minimum *formula price in that model*, not tensor
rank optimality or unrestricted packing completeness.

Mixed packing beat the pure-axis formula in 220 cases. All 220 were expanded
and replayed. Including the separately retained projection construction,
the older independent Python verifier checked 221 full output tensors:
417,887 terms and 34,627,166 support-pair XORs.

| Canonical shape | Prior local bound | Exact construction | Saved reference |
| --- | ---: | ---: | ---: |
| 6x6x32 | 777 | 774 | 758 |
| 7x9x18 | 774 | 768 | 726 |
| 9x15x20 | 1654 | 1646 | 1604 |

These are **three distinct local improvements**, not 220 new shapes or
world records. None improves the main small cubes or crosses the saved
public comparison. No fresh literature/novelty audit was needed to reject
them as record candidates against these already stronger saved references.

A paired control/augmented block-sum, Kronecker-product and padding price
closure through dimension 32 gives five lower prices: the three above,
9x15x22 at 1,856 (previously 1,857), and 9x17x20 at 1,926 (previously 1,934).
The latter two remain price-only, not newly expanded witnesses. There are
zero new saved-reference crossings. Reclosing the baseline itself improved
158 old prices; those are expressly excluded from the five credited changes.

Reports, disposable drivers and standalone recipes remain under
`/private/tmp/metaflip-projection-policy-20260909/`, outside the checkout.
The source commit adds no imported tensors or bulk benchmark directories.
The retained productive direction is mixed-group composition; neither the
summed-cost projection selector nor the broader projection family is promoted
on these results alone.
