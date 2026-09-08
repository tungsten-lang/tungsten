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
expressions. It lowered five local prices:

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

The shape-deduplicated cumulative cohort is **390 local improvements: 56
expanded and 334 recipe-only**. This adds one distinct shape, not five. All
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
