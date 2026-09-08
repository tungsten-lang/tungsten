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
