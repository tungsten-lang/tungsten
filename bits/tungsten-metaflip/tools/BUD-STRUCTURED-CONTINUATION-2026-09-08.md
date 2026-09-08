# Structured-parent continuation: a new reference-crossing candidate

Independent construction and tensor replay establish the GF(2) upper bound
**R(21,24,30) <= 8064**, improving the previous local 8070. A fresh, bounded
comparison of public catalog data and recursively composed reference costs
still gives 8067. This is a reference-crossing candidate, **not a confirmed
world record, optimal rank, or characteristic-zero result**.

The useful change is two additional shared-U pairs in a rank-150 5x6x7
parent. Its primitive rank is unchanged. At scale `(6,4,3)`:

```text
old: 130 * R(6,4,3) + 10 * R(6,4,6) = 130*54 + 10*105 = 8070
new: 126 * R(6,4,3) + 12 * R(6,4,6) = 126*54 + 12*105 = 8064
```

All terms, leaf schemes, substitution maps, and the final dimension permutation
were checked, not merely the formula. Parent tensor SHA-256:
`bbef5c3e2451cbb8733ecf472d2ebdbd8305434d95c033de9db5941e5f4c2006`.
Expanded product SHA-256:
`e2380a3fe6da7fd29215291b06a68db6230dddc0d48f0e02330e1151d9811e91`.

## Matched bounded search

After importing the structured literature corpus, the context selector screened
eight high-leverage families. Seven had qualifying objectives: 2x3x7, 2x4x6,
4x5x7, 5x5x6, 5x5x7, 5x6x7, and 5x5x8. The 5x6x6 family had no qualifying
context and was not walked. Selection retained every new imported presentation
within two terms of the family's minimum plus up to two prior-corpus controls.
It used up to eight price tables per family, identifying proportional complete
tables only for objective selection, never for tensor identity or dominance.

The resulting 20 seeds comprise eight imported presentations and twelve prior
controls. Each received 16 trials of 64 chunks of 65,536 attempts, observation
interval 4,096, debt two, density slack four, RNG 912173. This is
**1,342,177,280 attempted moves** across 49 family/objective combinations and
143 seed/objective comparisons. All jobs were sequential, low priority, CPU
only. No fleet or GPU stress run was launched.

Observers do not steer the walk. They retain composition-useful states from
the same path as the primary rank objective. In 81/143 seed/objective
comparisons their saved cost beats the rank winner's cost; this is not a
strategy win-rate comparison. Unequal imported/control cohort sizes likewise
do not justify comparing aggregate success totals.

Full tensor/score/accounting replay checks **1,156 distinct tensors, 116,107
terms, and 2,280,925 support-pair XORs**. The 8064 witness comes from cell
`5-0`, trial zero, observer one, starting from the imported `567.exp` reduced
modulo two. The selected parent remains rank 150; no walked family improved
its primitive minimum, and no main-square rank improved.

## Recomposition and certificates

With the imported corpus fixed as the baseline:

- Rank winners and endpoints add 477 literal identities and give 58 lower
  local prices, but no reference crossing.
- Context winners add another 659 identities. The combined corpus has
  **16,646** literal shape-plus-tensor identities and **76** lower local prices.
- Compared directly with rank-only retention, context retention improves 30
  prices: 18 additional shapes plus further savings on 12 control gains.

Three representative products were materialized:

| Shape | Previous local | Checked upper bound | Refreshed reference screen |
| --- | ---: | ---: | ---: |
| 21x24x30 | 8070 | 8064 | 8067 |
| 18x25x30 | 7438 | 7420 | 7340 |
| 18x20x30 | 5919 | 5910 | 5903 |

Independent recipe replay covers **16 tensors, 43,686 terms, and 8,398,365
support-pair XORs**, including all three final products. The other 73 gains
remain arithmetic recipes rather than newly expanded certificates.

Twenty-five of these 76 shapes overlap the preceding 200-shape bounded cohort.
Its deduplicated total is now **251 lower-price shapes**, with **14 expanded
outputs and 237 remaining recipes**. The scoped reference-crossing shortlist
grows from 41 to **42**. These are not counts of confirmed world records or
the older campaign's separate candidate tally.

## Reference scope

Remote HEADs were rechecked on 2026-09-08 and were unchanged:

- [Perminov catalog](https://github.com/dronperminov/FastMatrixMultiplication/tree/db560ca5811bc38d5a6d5c0a3ec4315937ceabce):
  `db560ca5811bc38d5a6d5c0a3ec4315937ceabce`.
- [Matrix Multiplication Catalog](https://github.com/solven-eu/matmulcatalog/tree/f3a7f0f61b1005666c2cb03f98f2a16727604ea0):
  `f3a7f0f61b1005666c2cb03f98f2a16727604ea0`.
- [Imported structured sources](https://github.com/mkauers/matrix-multiplication/tree/12c26b29a5458e173813911fb4f2c2865fba841e/structured):
  `12c26b29a5458e173813911fb4f2c2865fba841e`.

The [live Lille 21x24x30 page](https://fmm.univ-lille.fr/21x24x30.html), freshly
downloaded with response headers and a body hash, lists 8240. The pinned
catalog's direct bilinear minimum is 8070. Combining reference costs through
block/Kronecker and reported-structure closure gives 8067, including 8,453
catalog partition families, 261 published families, and 359,973 expressions.
Forty-nine reported partitions were excluded because their term-count sums
disagreed with their advertised ranks; none was a 5x6x7 partition.

Reference fields and reported partitions are not all independently reverified.
Their numbers strengthen a novelty screen only, never supply unverified
constructor leaves. This finite comparison does not prove global novelty;
the inherited imported data also remain outside source commits pending
redistribution review. No submission or publication was made.

## Reusable observer checker

`benchmarks/matmul/metaflip/verify_observer_walk.py` replaces the one-off audit
path for this rank-primary/read-only-observer report format. It checks every
saved source, primary winner, endpoint, and observer winner; price tables
against an explicit frozen plan; trial/observer indices; scores/densities;
summaries; and attempt/observation counts. Partial observation spans use a
per-chunk ceiling, not an incorrect whole-run floor.

```sh
nice -n 10 python3 -B benchmarks/matmul/metaflip/verify_observer_walk.py \
  --root /path/to/completed-observer-run \
  --price-plan /path/to/frozen-pricing/report.json \
  --output /tmp/observer-audit.json

cd benchmarks/matmul/metaflip
nice -n 10 python3 -B -m unittest \
  test_verify_observer_walk test_verify_parent_only_walk
```

Ten focused tests pass, with mutation cases for tables, source tensors even
after updating their hashes, prices, identities/indices, accounting, and path
escape. The checker also replayed the earlier 51-cell campaign unchanged:
1,044 tensors and 1,711,276,032 attempts. It explicitly does **not** verify the
plan's leaf certificates, public reference bounds, product construction,
timing, optimality, or novelty. Those remain separate gates.

## Follow-up and local evidence

A short nested holdout test compared ordinary walking with keeping the first
six or all twelve new U-pairs fixed. Each arm received 16 trials, 64 chunks,
65,536 attempts, observation interval 1,024, debt two, density slack four,
RNG 912191: **201,326,592 attempts** in total. All stayed at 8064; fixing all
twelve pairs sharply reduced accepted flips. This tests only three selected
subsets and is not an impossibility proof. No default policy changed.

Local evidence is retained under
`benchmarks/matmul/metaflip/structured_continuation_audit_2026_09_08/`:
selection, complete walk outputs, standalone checkers, two pricing cohorts,
three expanded products, the holdout test, and refreshed reference pages and
hashes. Full product replay is self-contained; regenerating complete pricing
still requires the pinned earlier local ancestry. Imported data are local-only.
