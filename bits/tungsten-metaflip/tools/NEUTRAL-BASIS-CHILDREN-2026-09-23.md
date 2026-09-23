# Neutral-basis projection children, 2026-09-23

The exact [composed-parent chain](COMPOSED-PARENT-CHILDREN-2026-09-23.md)
contains useful rank-tied representations, not just ranks. This finite
screen applies the independent GF(2) shared-factor matrix refactor to each
source tensor, retaining a basis variant even when its term count is
unchanged. It then deletes one coordinate and runs exact matrix cleanup.

| Shape | Previous local rank | New GF(2) rank | Dated Lille entry | Source |
| --- | ---: | ---: | ---: | --- |
| 16×24×31 | 6499 | 6487 | 6549 | neutral basis of 16×25×31:6905 |
| 16×25×31 | 6905 | 6903 | 6914 | neutral basis of 16×25×32:6996 |
| 16×23×31 | 6488 | 6381 | 6384 | neutral basis of 16×24×31:6487 |

The bounded three-generation run tested 36 changed basis variants and
2,574 coordinate deletions. It found the three rows above and no further
improvement in generation three. Their seeds lower 41 numerical local
composition-closure entries, but only the three direct rows cross the
dated public comparison. A separate delayed-cleanup test of 211
first-step intermediates and 10,521 second deletions found no improvement;
that result does not cover other intermediate representations or moves.

The [manifest](certificates/neutral-basis-children-20260923/manifest.json)
pins each parent and intermediate basis tensor hash, the basis axis and
direction, each projection, cleanup count, and final tensor hash. Replay
rebuilds the original portfolio and Strassen-composed parents, checks the
basis variant's complete GF(2) tensor identity, compares each deletion to
an independent bit-grid projector, verifies the final full tensor, and
runs the Ruby full-tensor checker. Generated MFW1 tensors remain outside
the repository.

The external comparison digest was created 2026-09-18T17:17:29 with
SHA-256 `a77c4286cd7ad9b5212b679d9e1e21672c7519a41124a3d71079d68bf0878213`.
These are exact GF(2) upper bounds, not claims of optimality, cross-field
validity, or worldwide novelty. The screen is bounded to six one-axis
basis settings per source and depth three.

From the repository root:

```sh
python3 bits/tungsten-metaflip/tools/screen_neutral_basis_children.py \
  --digest PATH/TO/fmm_sota.json --depth 3 \
  --output-dir /tmp/metaflip-neutral-basis-screen
python3 bits/tungsten-metaflip/tools/screen_neutral_basis_children.py \
  --replay-manifest bits/tungsten-metaflip/tools/certificates/neutral-basis-children-20260923/manifest.json \
  --output-dir /tmp/metaflip-neutral-basis-replay
python3 bits/tungsten-metaflip/spec/neutral_basis_children_test.py
```
