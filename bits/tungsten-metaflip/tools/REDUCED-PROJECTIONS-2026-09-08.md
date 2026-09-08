# Exact cleanup before projection selection

The coordinate projector now accepts an optional `--pair-order 0,1,2`.
For **every** coordinate image it applies the existing exact GF(2) identity
`(a,b,c) + (a,b,d) = (a,b,c XOR d)`, cycling through the supplied axis order
until no shared-pair merge remains. It selects minima only after cleanup.
There is no raw-rank cutoff, and the default remains the original raw search.
Only one deterministic order is searched per invocation; this is not a global
normal-form or tensor-rank minimization theorem.

This ordering matters even on a tiny exact control. A seeded 3x3x3 parent has
a best raw 3x2x3 image of rank 19 that remains rank 19 after cleanup. Another
image starts at rank 20 and cleans to rank 18. The regression test requires the
new selector to keep the latter. The raw projector still returns its original
rank-19 control, so existing callers do not silently change behavior.

## Large-parent falsification test

The independently verified rank-7,042 20x24x28 parent was tested over all 1,784
one/two-axis coordinate restrictions. Cleanup changed 948 images. The scan took
91.88 seconds wall time / 91.02 seconds worker CPU time on one `nice -n 10`
worker. This is a bounded efficacy test, not a throughput speedup claim.

| Target | Prior raw minimum | Cleanup of that retained image | New selected bound |
| --- | ---: | ---: | ---: |
| 19x23x28 | 6,919 | 6,911 | 6,898 |
| 19x24x27 | 6,935 | 6,932 | 6,872 |
| 19x24x28 | 6,986 | 6,983 | 6,983 |
| 20x23x27 | 6,936 | 6,934 | 6,931 |

The new 19x24x27 winner starts at raw rank 6,947, worse than the raw minimum,
but its exact cleanup removes 75 terms. Postprocessing only the retained raw
winner would miss a further 60-term saving. The 19x23x28 winner starts at 6,921
and cleans to 6,898, also demonstrating the difference on the actual workload.

Independent replay rebuilt the six retained images with a bit-grid projector
and a separate sort/group cleanup implementation, then expanded every tensor
coefficient: seven tensors, 48,704 terms and 11,209,735 support-pair XORs. The
checker validates the raw rank, declared order and exact reduction trace as
well as the final tensor. A source with rebound hashes but an incorrect tensor
is rejected. It does not certify unreported minima or search exhaustion.

## Composition and cumulative accounting

Admitting the previous nine verified projections produced 60 improvements
against the old pricing plan: those nine literal bounds and 51 block-composition
descendants. Two representative downstream bounds, 19x24x29 and 20x23x29 at
7,442, were independently reproduced by projections of an existing verified
20x24x29 parent. No new comparison threshold was crossed by the 51 block rows.

The other three shortlisted parents contributed the checked bounds
14x29x30=6,952, 21x23x30=8,016 and 21x24x29=8,028. A matched one-axis run with
cleanup used the same 222 views; it added the expected 19x24x29=7,439 but no
further bounds. Separately, all six cleanup orders on the 22 retained raw
outputs found nine mergeable parents and seven retained results in 54 order
trials, including 19x23x27=6,866 and 23x25x27=8,806. All retained outputs passed
independent replay; the six-order post-selection run remains a control, not an
exhaustive six-order projection search.

The final admission/repricing pass uses **31,253 literal parents** and checked
2,721,550 pricing expressions. It lowered another 45 prices, overlapping the
first pass. Across the turn there are **68 net lower prices**, not 60+45 new
shapes. Two fresh block descendants were expanded and independently verified:

| Target | First-pass price | Final checked price | Padding-corrected reference |
| --- | ---: | ---: | ---: |
| 19x23x29 | 7,356 | 7,335 | 7,075 |
| 19x25x27 | 7,448 | 7,385 | 7,198 |

Their complete recipe audit checked nine tensors, 30,391 terms and 6,238,579
support-pair XORs. These do not beat the reference; they verify that the new
projected shapes compose correctly rather than merely supplying lower prices.

The deduplicated campaign cohort is **385 lower-local-price shapes: 51
expanded at their current best price and 334 recipe-only**. This adds 40
distinct shapes to the previous 345. Thirteen new or lower bounds were
independently expanded this turn. Superseded witnesses are not counted as
expanded at a new lower recipe price; for example, 19x24x32 is now recipe-only
at 8,195 rather than expanded at the older 8,226.

The restriction-corrected reference shortlist remains 49; nine of those shapes
belong to this improvement cohort and all nine have current expanded witnesses.
There is no new crossing shape in this turn. References are the September 8
pinned comparison and earlier refresh, not a new literature or field-transfer
audit. Padding-only metadata changes remain excluded from discovery counts.

## Replay

```sh
nice -n 10 python3 -B benchmarks/matmul/metaflip/projection_composition_scan.py \
  --inputs INPUTS --prices PLAN --output NEW_SCAN \
  --max-source-rank 10000 --max-source-dimension 32 \
  --max-deleted-axes 2 --pair-order 0,1,2 --workers 1
nice -n 10 python3 -B benchmarks/matmul/metaflip/verify_reduced_coordinate_projections.py \
  --root NEW_SCAN --output NEW_SCAN/independent-audit.json --workers 1
```

Use the reduced-projection checker for this mode, not the ordinary coordinate
checker. Its audited outputs use the existing `extend_composition_parents.py
--projection` admission path. Full oriented tensor identity remains the key;
neither rank nor a grouping signature substitutes for an actual state.

The focused suite passes **61 Python tests**, including all six cleanup orders
on small exact tensors, the nonminimum-raw control, independent replay,
raw-rank/order/trace mutations, invalid tensors with rebound hashes, CLI output
protection, default projector compatibility and audited composition admission.

Local-only evidence is retained under
`benchmarks/matmul/metaflip/reduced_projection_audit_2026_09_08/`: both pricing
passes, raw and reduced controls, post-selection cleanup, full tensor/recipe
audits, the two expanded products, exact source snapshots, cohort summary,
drivers, provenance and checked manifest. Historical producer hashes resolve
to their historical source bytes, including the raw projector at `2048e7a8`.

All reported bounds are over GF(2). Imported tensors and derived artifacts
remain local-only pending redistribution review. No primitive/main-square
improvement, confirmed world record, fleet change, push or publication is
claimed.
