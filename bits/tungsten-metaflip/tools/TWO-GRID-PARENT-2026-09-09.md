# Two disjoint grids from an ordinary parent walk

This bounded study yields **five independently verified GF(2) local
improvements**, two below the freshly screened public comparisons. They are
record candidates, not confirmed world records, tensor-rank optimality
claims or a change to the default live-fleet strategy.

| Canonical shape | Prior local bound | Verified rank | Screened comparison |
| --- | ---: | ---: | ---: |
| 8x10x14 | 726 | **724** | 726 |
| 8x14x26 | 1807 | **1805** | 1807 |
| 8x15x21 | 1552 | **1548** | 1542 |
| 8x15x23 | 1738 | **1736** | 1714 |
| 12x14x15 | 1544 | **1542** | 1528 |

No main small-cube rank improved in this batch. All search parents have
shape 4x5x7; the gain is in their composition structure, not primitive rank.

## Mechanism and attribution

The new ordered parent has rank 104 and canonical `MFR1` identity
`aff53644b9d84e0ef7c4b6509050897b54b5894b8b89bf6004ca724990a56357`.
Its canonically sorted terms contain two disjoint elementary 2x1x2 groups:
indices `[7,8,25,26]` and `[28,30,56,57]`. Each is a 2x2 grid in two factor
classes; the third factor is a general linear image. Full coefficient maps,
not merely equalities or group counts, are checked in the exported recipes.

At scale `(2,2,2)`, the remaining 96 terms use rank-seven leaves and each
grid uses a checked 4x2x4 leaf of rank 26:

```text
R(8,10,14) <= 96*7 + 2*26 = 724.
R(8,15,21) <= 96*15 + 2*54 = 1548.
R(12,15,14) <= 84*15 + 6*29 + 2*54 = 1542.
```

The last construction also packs six shared-factor pairs. The 8x10x14
output tensor SHA-256 is
`e833ec39782e9b81f92a83012c5d4f849150a681add35e87182b11005936b85a`.

The source is **ordinary walk trial 6 of the free 2x3x3 control**, not the
new packing-primary policy, annealing or the fixed-grid arm. Its initial
parent was the previous near-miss representation
`d64c9510bdf9ac3988432f7cb8c24f42994cd7280e99b341dadac1164fcc3efc`.
Automated full grid packing after the walk finds the winning construction.
No individual equation was manually altered to obtain it.

The preflight ruled out the initially proposed richer-leaf objective:
on that starting parent, group-only prices at scales 2x3x3 and 3x3x2 remain
1558 and 1550, whereas adding a grid gives 1554 and 1546. Those improvements
come from geometry, not a missing leaf price. Repeating group-only scoring
with the richer prices would not target the useful structure.

## Bounded experiment

Four studies compare ordinary, greedy and annealing walks at scales 2x3x3
and 3x3x2, with and without a fixed elementary grid. Every arm uses seed
957113, 16 trials, 256 chunks, 8192 attempts per chunk, observation interval
1024, debt two and density slack eight. The total is 402,653,184 requested
flip attempts, with exact attempt and observation checks. The launcher limits
each study to 120 seconds and the full search to 300 seconds, stopping its
own process group on timeout. All studies completed; no timeout occurred.

The held arm preserves the original literal indices `[7,8,30,32]` as a
checked 2x1x2 group. The internal residual is never treated as a full
matrix-multiplication tensor: it is joined back before scoring/admission,
and the held-group price is used only while all four terms survive.

Raw held scores improve from 1554 to 1552 and from 1546 to 1545. However,
common full-packing repricing of every retained winner and endpoint gives
the five final wins from the free-control parent. Held search improves three
other control-relative target minima, but none beats the retained archive.
This does not justify enabling held-grid search as the default strategy.

The 384 output occurrences deduplicate to **350 full parents**, scored at
all 27 ordered native-scale contexts: **9450 distinct recipes / 27 target
shapes**. The broader bounded model uses leaf dimension at most 16,
components at most 24 terms, 50,000 states/candidates, and grids of side two.
All 9450 solves finish within that model; this is not unrestricted packing
or tensor-rank exhaustion. Eight selected products pass independent Python
substitution and full-tensor checks, covering 26 distinct tensors, 18,842
terms and 1,493,781 support-pair XORs.

Across the recent observer, packing-primary and current studies, the
deduplicated rollup is **916 parents and 24,732 parent/context pairs**.
All 350 current identities are new to the preceding 566-parent cohort.
These are search identities, not 916 new shapes or records.

Shared-factor matrix cleanup checks all 350 current parents and the three
direct improving products. None of these 353 inputs decreases in rank.
Everything ran serially at low CPU priority, with no GPU or live-fleet run.

## Composition checks and the unresolved sixth price

Paired control/augmented recursive block/Kronecker pricing checks all 5984
canonical shapes through dimension 32. A separately implemented bottom-up
recurrence agrees with the memoized top-down recurrence on both complete
grids. Recloses of older baseline prices are excluded from new-gain counts.

Two propagated improvements are materialized from hash-pinned, fully checked
component witnesses:

```text
R(8,14,26) <= R(8,14,10) + R(8,14,16) = 724 + 1081 = 1805.
R(8,15,23) <= R(8,15,21) + R(8,15,2) = 1548 + 188 = 1736.
```

Independent replay checks both outputs, covering five distinct tensors,
7083 terms and 431,021 support-pair XORs. Thus there are five materialized
improving shapes in total, not merely formula-price improvements.

One further price, 15x23x23/4778 versus the reclosed baseline 4780, remains
unexpanded. The selected recipe needs 15x15x23/3042, inherited by restriction
from a 15x15x24 price of 3042. The requested component has no recovered
checked construction in the supplied materializer sources. Its exact error
is `price has no checked construction: [15, 15, 23]=3042`. It is explicitly
excluded from the five verified improvements; the generic materializer was
not weakened to accept a rank number as a witness.

## Public comparison and retention

Fresh read-only HEAD checks are unchanged at:

- [Perminov](https://github.com/dronperminov/FastMatrixMultiplication/tree/db560ca5811bc38d5a6d5c0a3ec4315937ceabce).
- [Matrix Multiplication Catalog](https://github.com/solven-eu/matmulcatalog/tree/f3a7f0f61b1005666c2cb03f98f2a16727604ea0).
- [Structured sources](https://github.com/mkauers/matrix-multiplication/tree/12c26b29a5458e173813911fb4f2c2865fba841e).

The freshly fetched catalog lists 8x10x14 at rank 726, including a verified
F2 entry. The direct Lille HTTP fetch also returns 726; an older search-cache
view returns 728 and is not used as the stronger comparison. Lille lists
8x14x26 at 1818, but the already stronger corrected comparison is 1807.
The screen includes 261 published structure families, 8453 catalog bud
families and 359,973 reported composition expressions, plus recursive block
sums and Kronecker products. The two candidates remain below 726 and 1807.
Mixed-field reference metadata are comparison data, not constructive leaves
or evidence of complete global novelty.

The retained local comparator is pinned by SHA-256
`0b4ad918bd36a262797cb89017513cbed0fe07dbdb832df4d5462c4e4e2c0da7`,
plus the already retained 6x6x32/774, 7x9x18/768, 9x15x20/1646,
9x15x22/1856 and 9x17x20/1926. Future runs must also include the five verified
improvements above, and label the sixth price separately, to avoid recrediting
this batch.

The evidence remains outside the repository at
`~/.local/share/tungsten-metaflip/evidence/2026-09-09-two-grid-parent.tar.gz`:
5,519,194 bytes, SHA-256
`d070afe40aea4e7eb4f9b868cb7bcf5b5e58c42c2f9bda53b6b0a33697684c77`.
A fresh extraction checks 735 file hashes and reruns both copied independent
tensor checkers, with audit JSON identical to the originals. This validates
retained witnesses, not a replay of every flip or an independent full search
census. The archive includes reports, source metadata, raw outputs and
disposable drivers. Its original directory is
`/private/tmp/metaflip-grid-holdout-20260909/`.

At the time of this search, the native automatic composer supported disjoint
equal-factor groups, not these two-factor grids. The subsequent
[native multi-grid integration](NATIVE-MIXED-GRIDS-2026-09-09.md) now reproduces
the three direct constructions automatically, with full-mask identity,
versioned replay, explicit budgets and full tensor admission. That replay
does not add discoveries to this study's count.
No imported tensor, canonical seed promotion, push or publication is part
of this source commit.
