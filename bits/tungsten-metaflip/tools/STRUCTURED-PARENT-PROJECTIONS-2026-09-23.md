# Exact structured-parent projections, 2026-09-23

This finite search started from the 81 exact GF(2) tensors in the
[structured-parent portfolio](certificates/structured-parent-portfolio-20260922/manifest.json).
It deleted each possible coordinate on each of the three tensor axes (4,279
projections), cancelled duplicate terms over GF(2), and applied exact
shared-factor matrix cleanup. Sixteen distinct target shapes improved the
existing local construction and fall numerically below the corresponding
[Lille table](https://fmm.univ-lille.fr/) entries: twelve cross the listed
rank for the first time in this local closure, and four strengthen earlier
below-table constructions. These are exact field-specific upper bounds, not
claims of optimality, cross-field validity, or worldwide novelty.

| Shape | New GF(2) rank | Lille entry | Previous local rank |
| --- | ---: | ---: | ---: |
| 14×16×24 | 3078 | 3138 | 3084 |
| 12×16×29 | 3164 | 3216 | 3200 |
| 14×16×28 | 3634 | 3674 | 3716 |
| 15×16×29 | 4005 | 4044 | 4055 |
| 10×20×23 | 2743 | 2775 | 2879 |
| 15×17×20 | 3039 | 3069 | 3054 |
| 15×16×27 | 3758 | 3787 | 3768 |
| 8×23×25 | 2752 | 2779 | 2821 |
| 10×19×24 | 2735 | 2754 | 2817 |
| 10×19×30 | 3417 | 3433 | 3496 |
| 8×17×30 | 2496 | 2509 | 2518 |
| 15×19×20 | 3399 | 3409 | 3414 |
| 9×16×17 | 1515 | 1524 | 1588 |
| 9×16×29 | 2495 | 2502 | 2576 |
| 3×18×25 | 999 | 1002 | 1014 |
| 8×14×20 | 1411 | 1414 | 1433 |

The rank-999 `3×18×25` result composes with three block copies of the
packaged rank-54 `3×4×6` tensor to give a full `3×18×29` tensor of rank
1161, one below the listed 1162. The
[manifest](certificates/structured-parent-projections-20260923/manifest.json)
pins the source schemes, deletion coordinates, cleanup counts, output hashes,
and that additional block construction. The full tensors are deliberately
not vendored: focused replay reconstructs every one from the pinned recipes.

Verification includes an independent bit-grid coordinate projector, exact
full-tensor parity checks after each construction, and the Ruby tensor
verifier on each materialized output. The comparison digest is external
`fmm_sota.json`, created 2026-09-18T17:17:29 with SHA-256
`a77c4286cd7ad9b5212b679d9e1e21672c7519a41124a3d71079d68bf0878213`;
the Lille page was checked again on 2026-09-23. A fresh digest may give a
different numerical comparison without changing the tensor certificates.

From the repository root, repeat the finite screen with a local digest, or
replay the pinned witnesses into a new output directory:

```sh
python3 bits/tungsten-metaflip/tools/screen_structured_parent_projections.py \
  --digest PATH/TO/fmm_sota.json
python3 bits/tungsten-metaflip/tools/screen_structured_parent_projections.py \
  --replay-manifest bits/tungsten-metaflip/tools/certificates/structured-parent-projections-20260923/manifest.json \
  --output-dir /tmp/metaflip-projection-replay
python3 bits/tungsten-metaflip/spec/structured_parent_projections_test.py
```

This is automated algebraic projection and cleanup, not a live MetaFlip flip
walk. The current runtime does not automatically apply this whole offline
pipeline to every discovered tensor.
