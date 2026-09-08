# Compact projections with composition leverage

This bounded GF(2) search found a much more useful **rank-85 4x4x7
representation**, four new direct projected bounds, and many lower composition
prices. All selected constructions are independently replayed. They are
reference-crossing candidates, not confirmed world records or optimal ranks.
The live CPU/GPU fleet and canonical seed archive are unchanged.

## The useful parent keeps the same rank

The literal parent has ordered shape `(4,7,4)` and SHA-256
`8b3e5862d6400aab50874bf928abe42bd7b962d95143e0d0e51db0bc81c3c8be`.
Grouping by its third factor gives **nine singletons and 38 pairs**. The
previous corpus has 388 rank-85 representations of this shape, with at most
11 pairs on any factor axis. This is a comparison of the retained corpus,
not an upper bound on all rank-85 representations.

It comes from deleting one coordinate of a verified `(4,8,4)` rank-94
parent. Raw and shared-pair-cleaned rank are both 90; five exact shared-factor
matrix factorizations each remove one term. Selecting the pair-ranked
minimum instead would retain rank 87. Scoring every projection after matrix
cleanup therefore matters even when the final primitive rank only ties the
existing best.

At scale `(a,b,c)`, the retained grouping gives the exact construction

```text
R(4a,7b,4c) <= 9 R(a,b,c) + 38 R(a,2b,c).
R(12,7,12) <= 9*9 + 38*15 = 651.
```

The full recipe verifies the parent, all term groups, coefficient maps,
leaf tensors and final orientation, not just this arithmetic. The 7x12x12
witness has SHA-256
`9f0ef7323c1170600b8301f74335f9b92c9183f6b115a2d7c47c95f1479b2ab5`.
Its saved comparison is 657; the freshly fetched Lille page lists 660.

This is why direct rank ties remain useful search states. The scan also
retains a rank-102 3x4x11 parent even though that shape has a lower primitive
incumbent: its grouping improves several larger constructions. Neither rank
nor a bucket histogram replaces full tensor identity.

## Bounded search and controls

From the frozen 31,495-parent corpus, select nonsquare shapes with minimum
dimension at least three and maximum at most 16. Keep only parents at or
below the shape's padding-corrected price, then take the first and last
available full literal identities in each canonical shape. This is a
representation sample, not a dominance rule or exhaustive parent search.
All eligible paths were available. The resulting **168 parents cover 86
shape families**.

Both matched policies enumerate the same **3,334 one-axis coordinate
deletions**, with no raw-rank pruning:

| Scoring policy | Wall seconds | Direct improving shapes | Best 15x15x16 |
| --- | ---: | ---: | ---: |
| Shared-pair cleanup | 7.59 | 1 | 2,112 |
| Pair then matrix cleanup | 21.15 | 2 | 2,081 |

These are single-run efficacy observations, not a speedup benchmark. The
matrix run's 8.46 seconds of Python CPU excludes its serial Ruby worker.
Independent audits cover 509 full tensors per policy: 131,940 terms in the
pair control and 130,047 in the matrix run. Both check retained constructions,
not unreported minima or the producer's complete search census.

Sixty two-pass basis configurations on the five improving oriented outputs
complete in 3.76 seconds, yielding 22 distinct endpoints but no further rank
drop. Their independent audit replays 360 steps, 328 distinct transitions
and 27 full tensors. Then 182 one-axis deletions from the four retained
minimum-rank orientations produce two more direct gains in 4.70 seconds.
That audit checks 14 full tensors.

| Direct projected shape | Prior padded bound | Verified bound | Saved comparator |
| --- | ---: | ---: | ---: |
| 13x14x16 | 1,798 | **1,788** | 1,796 |
| 13x15x16 | 1,885 | **1,865** | 1,878 |
| 15x15x15 | 2,048 | **2,030** | 2,048 |
| 15x15x16 | 2,132 | **2,081** | 2,132 |

The 15-cube is an expanded square improvement. The main 3-, 4-, 5- and
6-cube primitive ranks remain 23, 47, 93 and 153. Larger square recipe
changes at 23, 28 and 31 are not promoted to new expanded square witnesses;
some remain padding-dominated.

## Composition, materialization and cumulative counts

The two complete repricing passes admit 687 literal identities, growing the
corpus to **32,182 parents**. They evaluate 2,945,289 and 2,945,481 expressions,
respectively, including 835,454 mixed expressions each, without cached-price
reuse. CPU times are 59.23 and 61.74 seconds.

Across both passes there are **412 net raw-price improvements**, of which
**338 beat the preceding padding-corrected table**. The second pass's four
changes overlap one first-pass gain; summing batch counts would overcount.

Sixty selected outputs are fully materialized: all 59 improved rows below
the saved comparison and the scaled 30x30x32 control. Independent replay
checks **129 recipes, including 34 shared-factor recipes, and 221 complete
tensors** (336,002 terms; 38,000,645 support-pair XORs).

| Expanded shape | Prior padded bound | Verified bound | Saved comparator |
| --- | ---: | ---: | ---: |
| 7x12x12 | 657 | **651** | 657 |
| 7x16x16 | 1,152 | **1,132** | 1,148 |
| 14x16x16 | 2,062 | **2,020** | 2,099 |
| 14x28x28 | 6,292 | **6,156** | 6,233 |
| 20x21x32 | 7,392 | **7,270** | 7,368 |
| 28x32x32 | 14,194 | **14,122** | 14,194 |
| 30x30x32 | 14,924 | **14,567** | 13,857 |

The last construction is `7 * 2081`; its 357-term saving propagates the
51-term direct improvement. It does not cross the reference. The 28x32x32
result instead uses the grouping-rich rank-85 parent.

Materialization initially rejected an inherited price labeled `seed` after
repricing. Restoring the earlier, hash-pinned shared-factor recipe resolves
it; no price is accepted without a construction. An optional unchanged
30x30x30 control was then excluded because its unrelated historical recipe
was not recovered. All 60 actual reported outputs pass independent replay.

The deduplicated campaign cohort is now **787 shapes: 119 expanded at the
current price and 668 recipe-only**, adding 388 distinct shapes to the prior
399. After padding, **630 remain: 115 expanded and 515 recipe-only**; 157
raw-price rows are dominated. All **68 cohort reference crossings** have
current expanded witnesses. The broader metadata shortlist grows from 49
to 100: 51 newly crossing shapes, not 59, because eight selected rows were
already on that broader list.

## Reference and retention boundaries

At 2026-09-08 19:43--19:44 UTC, the three upstream HEADs remain unchanged:

- [Perminov](https://github.com/dronperminov/FastMatrixMultiplication/tree/db560ca5811bc38d5a6d5c0a3ec4315937ceabce): `db560ca5811bc38d5a6d5c0a3ec4315937ceabce`.
- [Matrix Multiplication Catalog](https://github.com/solven-eu/matmulcatalog/tree/f3a7f0f61b1005666c2cb03f98f2a16727604ea0): `f3a7f0f61b1005666c2cb03f98f2a16727604ea0`.
- [Structured sources](https://github.com/mkauers/matrix-multiplication/tree/12c26b29a5458e173813911fb4f2c2865fba841e): `12c26b29a5458e173813911fb4f2c2865fba841e`.

The freshly downloaded 9,532-entry catalog and all 59 Lille pages are pinned
with timestamps, response headers and body hashes. All 59 candidates are
below the listed **bilinear** minima and their saved, sometimes stronger,
composition-corrected comparisons. Reference metadata are not constructor
leaves and do not strengthen coefficient-field applicability.

The catalog also lists a commutative-only Waksman 15-cube algorithm at 2,003
over `Z`. It is explicitly marked `commutative: true`, not a competing
GF(2) bilinear tensor decomposition; it is retained in the comparison audit,
not silently dropped. This remains a source-scoped novelty screen, not a
complete literature/isomorphism or redistribution review.

Evidence is deduplicated and compressed outside the checkout. All work used
one low-priority CPU worker, no GPU and no live fleet. Imported tensors and
derivatives remain local-only. No seed promotion, push, publication or
submission occurred.

The retained bundle is
`~/.local/share/tungsten-metaflip/evidence/2026-09-08-compact-parent-projections.tar.gz`
(52,713,007 bytes), SHA-256
`0b1ff65ba2519b0cff17a46073899ecacbe0cf4ac2f251f1b041fe34f8f13030`.
Fresh extraction verifies all 2,239 logical files / 1,233 content objects,
round-trips the final pricing-input delta against its pinned compressed base,
and reruns all five copied independent checkers. Their complete audit JSON
matches the original audits exactly. The bundle certifies retained
constructions and metadata, not full search exhaustion or independent
recertification of every unexpanded composition price.
