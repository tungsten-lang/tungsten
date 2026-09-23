# Composed-parent projection chain, 2026-09-23

The [top-two beam](TOP-TWO-PROJECTION-CHILDREN-2026-09-23.md) produced an
exact rank-7,308 GF(2) tensor for 16×26×32 by composing its 8×13×16 child
with Strassen's 2×2×2 tensor. This finite screen projects that *composed*
tensor and then recursively projects each improving child. It also checks
the three top-two direct tensors as initial parents. Each new generation is
compared against the previous local composition closure and a dated
[Lille table](https://fmm.univ-lille.fr/) entry.

| Shape | Previous local rank | New GF(2) rank | Dated Lille entry | Route |
| --- | ---: | ---: | ---: | --- |
| 16×25×32 | 7055 | 6996 | 7096 | 16×26×32:7308, delete middle coordinate 13 |
| 16×25×31 | 6915 | 6905 | 6914 | 16×25×32:6996, delete last coordinate 18 |
| 16×24×31 | 6645 | 6499 | 6549 | 16×25×31:6905, delete middle coordinate 12 |

The bounded six-generation run evaluated 441 coordinate deletions. It
found the three rows above and no further rank improvement after the third
generation. Retaining a third distinct first-step representation in the
earlier 81-parent beam (rank slack 50) separately evaluated 307
intermediates and 15,284 second-step deletions with no new rank improvement.
That negative result does not cover wider beams or other operations.

The [manifest](certificates/composed-parent-children-20260923/manifest.json)
pins every source tensor hash, deletion, raw/cleaned rank, cleanup count and
child tensor hash. Replay rebuilds the original portfolio parents and the
Strassen product, checks each deletion against an independent bit-grid
projector, proves every full GF(2) tensor identity, and runs the Ruby
full-tensor verifier. Generated MFW1 tensors live outside the repository.
The three new seeds also lower 26 numerical entries in the local
composition closure; 23 of those remain above the dated public table and
have not been materialized as new constructions.

The comparison digest was created 2026-09-18T17:17:29 with SHA-256
`a77c4286cd7ad9b5212b679d9e1e21672c7519a41124a3d71079d68bf0878213`.
These are exact GF(2) upper bounds, not claims of optimality, cross-field
validity, or worldwide novelty. The screen is bounded by the four pinned
initial tensors and one-coordinate deletions through depth six.

From the repository root:

```sh
python3 bits/tungsten-metaflip/tools/screen_composed_parent_children.py \
  --digest PATH/TO/fmm_sota.json --depth 6 \
  --output-dir /tmp/metaflip-composed-child-screen
python3 bits/tungsten-metaflip/tools/screen_composed_parent_children.py \
  --replay-manifest bits/tungsten-metaflip/tools/certificates/composed-parent-children-20260923/manifest.json \
  --output-dir /tmp/metaflip-composed-child-replay
python3 bits/tungsten-metaflip/spec/composed_parent_children_test.py
```
