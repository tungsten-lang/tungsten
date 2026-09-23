# Two-pass basis children of structured projections, 2026-09-23

The native wide transform queue already has twelve two-pass, three-axis basis
contexts (modes 6–17). The earlier offline structured-parent screen tested only
six one-axis contexts. Screening the existing twelve modes on all 24 certified
structured-projection parents gives these exact GF(2) upper bounds:

| Shape | Previous local | New rank | Dated Lille index |
| --- | ---: | ---: | ---: |
| 8×14×20 | 1411 | 1407 | 1414 |
| 8×22×25 | 2676 | 2675 | 2686 |
| 8×23×25 | 2752 | 2746 | 2779 |
| 9×16×17 | 1515 | 1514 | 1524 |
| 9×16×29 | 2495 | 2494 | 2502 |
| 10×19×30 | 3417 | 3413 | 3433 |
| 10×20×22 | 2671 | 2663 | 2673 |
| 10×20×23 | 2743 | 2737 | 2775 |
| 12×16×29 | 3164 | 3160 | 3216 |
| 14×16×27 | 3576 | 3565 | 3604 |
| 14×16×28 | 3634 | 3630 | 3674 |
| 15×16×27 | 3758 | 3754 | 3787 |
| 15×16×29 | 4005 | 4002 | 4044 |
| 15×17×20 | 3039 | 3037 | 3069 |
| 15×19×20 | 3399 | 3395 | 3409 |

The finite screen covers 288 basis contexts and 14,928 one-coordinate
projections; no native basis context exhausted its algebra-work cap. The
15 retained results are best-per-shape selections, not 15 independent
search strategies. Adding them as seeds decreases 94 prices in the local
block/Kronecker closure over sorted triples in `[2,32]³`; none of those
additional price decreases newly crosses the dated Lille table. These
composition prices are **not** independently expanded tensor artifacts.

The [manifest](certificates/two-pass-basis-children-20260923/manifest.json)
pins each parent, basis, and output digest. Replay rebuilds the 24 parents
from their certified source schemes, applies an independent integer-row
two-pass implementation, checks every retained full tensor in Python and Ruby,
and optionally checks that the native queue's basis mode yields the same bytes.
Large `.mfw` outputs are generated outside the repository. The pinned Lille
digest was created 2026-09-18T17:17:29 and has SHA-256
`a77c4286cd7ad9b5212b679d9e1e21672c7519a41124a3d71079d68bf0878213`.
The [live Lille index](https://fmm.univ-lille.fr/) was also checked on
2026-09-23. This is a GF(2) comparison against that index, **not** a claim of
optimality, validity over other fields, or worldwide novelty.

From the repository root (choose a fresh output directory for each replay):

```sh
python3 -B bits/tungsten-metaflip/tools/screen_two_pass_basis_children.py \
  --replay-manifest bits/tungsten-metaflip/tools/certificates/two-pass-basis-children-20260923/manifest.json \
  --output-dir /tmp/metaflip-two-pass-replay
tungsten compile bits/tungsten-metaflip/spec/wide_transform_queue_test.w \
  --out /tmp/metaflip-two-pass-native-test --release --native
python3 -B bits/tungsten-metaflip/spec/two_pass_basis_children_test.py \
  --native /tmp/metaflip-two-pass-native-test
python3 -B bits/tungsten-metaflip/tools/screen_two_pass_basis_children.py \
  --digest PATH/TO/fmm_sota.json --output-dir /tmp/metaflip-two-pass-full-screen
```

No new runtime strategy was added: the productive modes are already offered
automatically for admitted wide parents. The new spec interface and replay
script expose and guard that behavior; they do not make these offline parent
objects live fleet seeds.
