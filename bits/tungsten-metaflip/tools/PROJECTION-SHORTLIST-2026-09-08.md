# Staged projections and padding-corrected comparisons

The offline coordinate projector now accepts `--max-deleted-axes 1`, `2`, or
`3`. This limits the base neighborhood to deleting at most one coordinate on
that many axes. The default remains three, including the established view
order. Explicit `--target` subset families are unaffected. This permits cheap
one-axis screening before a combined-axis run; it changes neither the live
fleet nor the exact tensor gate.

`restriction_price_envelope.py` supplies a second, screen-only improvement.
Zero-padding already gives a smaller matrix-multiplication shape every upper
bound available for a componentwise larger shape. The tool closes both the
local and reference tables under this restriction before comparing them. It
keeps the original supplying shape and checks the Bellman equalities on the
complete finite dimension grid. These are metadata bounds, not independently
verified source tensors, constructive admission recipes, or rank optima.

From the repository root:

```sh
nice -n 10 python3 -B benchmarks/matmul/metaflip/projection_composition_scan.py \
  --inputs INPUTS --prices PLAN --output NEW_DIRECTORY \
  --max-deleted-axes 1 --max-source-rank 10000 \
  --max-source-dimension 32 --workers 1
nice -n 10 python3 -B benchmarks/matmul/metaflip/restriction_price_envelope.py \
  --plan PLAN --reference COMPARISON --output NEW_SCREEN.json
```

## Verified saved results

The rank-8,952 recipe for 24x25x28 is now expanded and independently checked,
including its mixed-bud recipe and leaf tensors. This completes an existing
candidate, not a newly lower price. Of the previous 45 reference-shortlist
shapes, only five belonged to the current improvement cohort; the other 40
were older baseline bounds. All five now have expanded witnesses.

Saved projections of that parent and the verified rank-7,042 20x24x28 parent
give nine additional local improvements. All nine beat the padding-corrected
local baseline as well as the raw composition table:

| Shape | Raw local | Padded local | Verified rank | Corrected comparison |
| --- | ---: | ---: | ---: | ---: |
| 19x23x27 | 7,004 | 7,004 | 6,874 | 6,639 |
| 19x23x28 | 7,273 | 7,042 | 6,919 | 6,820 |
| 19x24x27 | 7,040 | 7,040 | 6,935 | 6,830 |
| 19x24x28 | 7,271 | 7,042 | 6,986 | 7,012 |
| 20x23x27 | 7,190 | 7,042 | 6,936 | 6,962 |
| 20x23x28 | 7,209 | 7,042 | 6,982 | 7,050 |
| 20x24x27 | 7,080 | 7,042 | 6,996 | 7,046 |
| 23x25x27 | 8,988 | 8,873 | 8,807 | 8,421 |
| 23x25x28 | 9,118 | 8,952 | 8,903 | 8,816 |

The first parent used 77 one-axis and 2,049 up-to-two-axis views. The second
used 72 one-axis and 15,224 up-to-three-axis views. Independent replay of the
final two projection reports checked 15 tensors, 117,610 terms and 34,192,439
support-pair XORs. The product audit additionally checked 10 tensors, 18,758
terms and 6,271,031 XORs. Replay certifies the retained constructions, not the
producer's search exhaustion or optimality. These runs used one low-priority
CPU worker, with no GPU or fleet.

The deduplicated audit cohort is now **345 lower-local-price shapes: 45
expanded at the best retained price and 300 recipe-only**. This counts nine
new shapes and one completed older recipe, not duplicate axis-stage outputs.
The new projections have not yet been admitted to the shared parent corpus or
propagated through another composition run. The last pricing plan itself
therefore remains unchanged.

Four of the nine projections are below the pinned, restriction-corrected
comparison. They are candidates for further record checking, **not confirmed
world records**. There is no new main-square or primitive-leaf improvement.

## Reference and provenance boundaries

On the frozen 5,984-shape grid, padding alone lowers 500 local prices and 117
comparison prices. Do not count these 500 metadata changes as discoveries.
The reference input mixes field-specific reported bounds and their earlier
composition closure; restriction does not improve their field applicability.

The September 8 refresh retained the catalog JSON and 14 FMM pages with HTTP
metadata and hashes. The catalog byte hash and all three inspected repository
heads were unchanged. We retain stronger existing combined comparison bounds
rather than replacing them with weaker individual web-page ranks. This is a
scoped reference refresh, not an exhaustive novelty, isomorphism, or
redistribution review.

Focused validation passes 30 Python tests: staged-domain parity, unchanged
target families, direct bit-grid reconstruction, audit mutations, brute-force
restriction minima, false witness roots and padding-corrected comparisons.

Local-only evidence is retained in
`benchmarks/matmul/metaflip/shortlist_projection_audit_2026_09_08/`, including
the product, all projection stages, audits, reference snapshots, frozen price
metadata, source pins, drivers, checkers, cohort rollup and checked manifest.
Large pinned input documents are gzip-compressed with original hashes. Tensor
and recipe audits can replay from the copied result directories; producer
inputs retain their historical absolute paths and need relocation to rerun.

Imported tensors and derivatives remain outside commits pending redistribution
review. Only tools, tests and this note are committed. No live search restart,
canonical-archive update, push, publication or submission is part of this step.

## Focused target-only follow-ups

`--target` remains additive by default: it adds named subset families to the
usual one-coordinate-per-axis neighborhood. Use `--targets-only` to search
just the named targets, including every fitting orientation. This avoids
repeating unrelated neighborhoods during recursive follow-ups. The flag
requires at least one `--target`; existing per-family view allowances and
explicit skipped-family reporting are unchanged.

```sh
nice -n 10 python3 -B benchmarks/matmul/metaflip/projection_composition_scan.py \
  --inputs AUDITED_PARENTS --prices PLAN --output NEW_DIRECTORY \
  --max-source-rank 8000 --max-source-dimension 32 \
  --target 20x23x27 --targets-only --pair-order 0,1,2 --workers 1
```

For two 20x23x29 parents, this requests 812 maps (two complete 406-element
two-deletion families), instead of 31,050 maps with the default neighborhood.
That is a reduction in requested work, not a measured 38-fold speedup. A
mistaken additive launch was explicitly stopped before this focused run;
the incomplete launch supplies no result or exhaustion evidence.

The focused run completed in 75.81 seconds CPU and independently verified
**20x23x27=6,925**, down from 6,931. It deletes original coordinates 0 and 1
on dimension 2 of the rank-7,430 parent. The raw image has 6,926 terms, then
factor-2 cleanup removes one. Replay checked two tensors, 14,355 terms, and
3,225,216 support-pair XORs. The target is already below its saved reference;
this is a stronger existing crossing, not a new world-record claim.

The equivalent one-deletion route from the verified rank-6,970 20x23x28
parent took only 28 target-only views and recovered the same bound. A
757-view fixed-anchor paired refinement tied 6,925 in 9.24 seconds CPU.
Tests check unchanged default coverage, named-family minima, all target
orientations, duplicate targets, view-budget handling, missing-target
rejection, and independent CLI output replay.

The broader second-stage run tried all 21,196 sparse paired kernels on the
28-wide coordinate and improved the same target to **6,920** in 273.70 seconds
CPU. It uses `u=(1<<8)|(1<<12)`, `v=1<<12`, with shared anchor 12 and canonical
pivot 8. Its raw rank is 6,925; cleanup gives 6,925 -> 6,923 -> 6,920.
Independent reconstruction and full expansion checked two tensors, 13,890
terms and 3,207,020 support-pair XORs.

The useful anchor is not the best coordinate-only anchor:

| Image of the rank-6,970 parent | Raw rank | After cleanup |
| --- | ---: | ---: |
| Best coordinate control, anchor 0 | 6,926 | 6,925 |
| Coordinate control at anchor 12 | 6,957 | 6,955 |
| Paired map above, anchor 12 | 6,925 | **6,920** |

The fixed-anchor refinement did not improve; allowing a worse coordinate
anchor before the linear map did. The resulting tensor composes the earlier
paired restriction on dimension 1 with this restriction on dimension 2. This
is a bounded constructive example, not a general dominance or optimality
theorem. All 94 focused Python tests pass, including unchanged legacy modes.

Full composition pricing (no reuse of cached expression prices) admitted four
distinct parents and checked 2,722,106 expressions, including 835,454 mixed
expressions. It lowered five raw composition-table prices:

| Shape | Previous price | New price | Replay status |
| --- | ---: | ---: | --- |
| 20x23x27 | 6,931 | 6,920 | Expanded, independently checked |
| 22x23x27 | 7,889 | 7,878 | Expanded, independently checked |
| 23x23x27 | 8,315 | 8,304 | Recipe only |
| 23x26x27 | 9,265 | 9,264 | Recipe only |
| 23x27x29 | 10,298 | 10,287 | Recipe only |

The first block replay checked four tensors, 15,757 terms and 3,154,915
support-pair XORs. Its historical small leaves were restored from the retained
checked catalog. An attempted broader materialization stopped at an unavailable
3x14x27 rank-840 construction; its incomplete output is not a verified result.
The three remaining prices above are not counted as expanded witnesses.

At that point the shape-deduplicated raw-price cohort was **390 shapes: 56
expanded and 334 recipe-only**. This added one distinct shape, not five. All
nine cohort crossings of the saved reference are expanded; no new crossing,
primitive improvement, main-square improvement, or confirmed world record is
claimed. The broader restriction shortlist still has 49 metadata crossings.

New evidence is stored outside the checkout at
`~/.local/share/tungsten-metaflip/evidence/2026-09-08-focused-projections.tar.gz`
(7,337,123 bytes; SHA-256
`d4009133ff986610666919b72116e1e84966995798d307397caddad698bba27d`).
It stores 76 logical files as 66 unique hash-addressed objects. Five copied
independent checkers replay the retained tensors after archive extraction.
The large pricing input is losslessly represented by a hash-checked prefix of
the retained balanced-dual gzip corpus plus a new tail; that round trip is
also checked. This is retained-output replay, not full search exhaustion.
Existing dated bundles were neither removed nor moved, and imported data
remains local-only pending redistribution review.

## Next neighbor and corrected cumulative screen

The verified 20x23x27/r6,920 parent gives **20x23x26=6,834**. The previous
padding-corrected bound was 6,852 (the raw composition table said 6,921), so
the genuine local gain is 18, not 87. Its saved comparison is already 6,707;
this does not add a reference crossing or establish a world record.

A 70-view coordinate screen reached 6,860; 2,703 fixed-anchor linear views
tied it. Allowing every anchor tried 18,981 views in 197.19 seconds CPU and
found dimension-2 kernels `u=1<<19`, `v=(1<<19)|(1<<15)`, with shared anchor
19. Their raw 6,862 terms reduce to 6,860 and then 6,834. Rejecting that raw
rank against the 6,860 coordinate control would have discarded the winner.
Independent map reconstruction and full tensor expansion checked two tensors,
13,754 terms and 3,011,596 support-pair XORs. The child SHA-256 is
`63e4ad96ef08db9fb7c98c77c81bf77966650076c774524ce1cea2f45d3a02fd`.

The missing historical 3x14x27/r840 ancestry was recovered as a mixed-bud
recipe from the checked 3x7x9/r141 parent. Replaying it completed the earlier
**23x23x27=8,304** construction: ten tensors, 18,170 terms, 3,169,434 XORs,
eight recipes including two buds. This completes an existing priced result,
not a newly lower price. The earlier failed materialization remains incomplete.

Full propagation checked 2,737,698 expressions (835,454 mixed), with no cached
pricing reuse, and increased the parent corpus from 31,287 to 31,296. Besides
the 6,834 result it lowered 23x23x26's raw price from 8,237 to 8,168, but a
pre-existing padding bound of 8,079 already dominates that result. Likewise,
the earlier 22x23x27/r7,878 and 23x26x27/r9,264 raw-price changes were already
dominated by padding bounds 7,735 and 9,225. They are not new best local bounds.

The cumulative audit therefore separates **392 raw-price shapes** (58 expanded,
334 recipe-only) from **311 not dominated by the current padding table**
(54 expanded, 257 recipe-only). The other 81 raw-price shapes are retained for
audit provenance, not counted as current best candidates. All nine raw-cohort
reference crossings remain expanded; the broader metadata shortlist still
contains 49 crossings. This finite table screen is not a novelty certificate.

The follow-up evidence archive is outside the checkout:
`~/.local/share/tungsten-metaflip/evidence/2026-09-08-focused-followup.tar.gz`
(7,247,049 bytes; SHA-256
`76af7075d067fa3836a5b5ba89b90d9a2f8422f3d9a89e39a9adc8254d8af201`).
It contains 89 logical files as 73 unique objects, including source pins,
drivers, tensors, recipes, the corrected rollup and a lossless pricing-input
delta. Four copied independent checkers successfully replayed the extracted
coordinate, fixed-anchor, all-anchor and recipe outputs; the input delta also
passed its complete hash round trip. Retained-output verification does not
certify search exhaustion.

The same GF(2) cleanup identity is now implemented in the packaged live
coordinator, with native/offline parity tests. This does not move the large
projection searches into the fleet or expand its signed-i64 shape envelope.
No new long-running search, GPU run, publication or submission was started.

## Shared-factor matrices and neutral bases

The audited compression runner now accepts flat projection outputs as well as
the existing wrapped composition outputs. A present but invalid `result` does
not fall back to the flat form. Both producer and checker reject a declared
source rank that disagrees with its hash-pinned complete tensor. Thirteen
focused Python tests pass under Python 3.14, covering both formats, mutation
rejection, wide exact matrix rank, and neutral-basis replay. The system Python
3.9 cannot run the older `int.bit_count`-using cofactor tests; it is not the
validation interpreter for this run.

The stronger identity fixes one tensor factor and treats the other two as a
binary matrix. Exact matrix-rank factorization can reduce a group even when
no two terms share both remaining factors. Neutral column-basis changes can
then expose new reductions on another axis. Ruby produces the factorizations;
Python independently chooses a basis and solves a separate row-equation
system, then expands every complete retained tensor.

| Shape | Previous tensor | Matrix cleanup | Basis round 1 | Final verified tensor |
| --- | ---: | ---: | ---: | ---: |
| 20x23x26 | 6,834 | 6,776 | 6,746 | **6,742** |
| 20x23x27 | 6,920 | 6,879 | 6,847 | **6,844** |
| 22x23x27 | 7,878 | 7,837 | 7,805 | 7,805 |
| 23x23x27 | 8,304 | 8,263 | 8,231 | **8,228** |

Round 1 ran all six axis orders with forward/reverse column ordering, two
passes each: 48 trials on the four compressed inputs. Round 2 used only the
two 20x23 parents, keeping both distinct tied minima for 20x23x26: 36 trials.
Both bounded sweeps completed, for 84 trials and 504 replayed axis steps. The
last 23x23x27 result is the explicit block sum 3x23x27/r1,384 plus the new
20x23x27/r6,844 parent, not an inferred subtraction from a reported rank.
Its three complete tensors and block recipe passed independent replay.
No unrestricted basis-orbit exhaustion or optimality is asserted.

Full pricing admitted 79 new canonical tensor identities (31,296 -> 31,375
parents) and evaluated 2,737,912 expressions, including 835,454 mixed ones,
without cached-price reuse. It used 70.44 seconds CPU. The eight changes below
beat the previous padding-corrected table; recipe-only rows have not yet been
expanded at their newly lower price.

| Shape | Previous padded bound | New bound | Evidence |
| --- | ---: | ---: | --- |
| 20x23x26 | 6,834 | 6,742 | Expanded |
| 20x23x27 | 6,920 | 6,844 | Expanded |
| 21x23x27 | 7,485 | 7,465 | Recipe only |
| 23x23x26 | 8,079 | 8,076 | Recipe only |
| 23x23x27 | 8,304 | 8,228 | Expanded |
| 23x26x26 | 9,041 | 9,020 | Recipe only |
| 23x26x27 | 9,225 | 9,188 | Recipe only |
| 23x27x29 | 10,287 | 10,211 | Recipe only |

Four other raw-price changes remain padding-dominated: 21x23x26/r7,340,
22x23x26/r7,664, 22x23x27/r7,802, and 23x27x31/r10,990. In particular, the
verified 22x23x27/r7,805 tensor and its cheaper r7,802 composition recipe are
both worse than the existing r7,735 padding bound.

The cumulative raw-price cohort is **396 shapes: 57 expanded at the current
price and 339 recipe-only**. This adds four distinct shapes, not twelve.
After padding, **314 remain: 54 expanded and 260 recipe-only**; 82 are
dominated. The expanded count can fall when a lower, not-yet-expanded recipe
supersedes an older witness. All nine cohort reference crossings remain
expanded, and the broader reference shortlist remains 49. No new crossing,
main-square improvement, or confirmed world record was found. The saved
20x23x26 reference is 6,707, still below the new 6,742 tensor.

These runs used one low-priority CPU worker, no GPU and no live fleet. The
stronger matrix/basis operations remain offline. Imported derivatives remain
local-only; no older bundle was removed or moved and no publication or push
was performed.

Replay evidence is saved outside the checkout at
`~/.local/share/tungsten-metaflip/evidence/2026-09-08-shared-factor-basis.tar.gz`
(80,187,483 bytes; SHA-256
`f2668423fa81f5d9a33ec1ade2624324ce6af82ca203af601537b19e3cc4713c`).
It retains 233 logical files as 143 unique objects, including all retained
basis endpoints, source pins, drivers, independent checkers, the cohort rollup
and a lossless pricing-input delta. All seven copied checkers passed after
extraction and reproduced their saved audits exactly. The complete input-delta
hash round trip also passed. Existing historical source corpora remain
externally pinned; this is retained-construction replay, not complete search
or worldwide-novelty certification.
