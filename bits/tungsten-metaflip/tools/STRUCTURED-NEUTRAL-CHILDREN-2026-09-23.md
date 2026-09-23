# Neutral-basis children of structured projections, 2026-09-23

The earlier [neutral-basis screen](NEUTRAL-BASIS-CHILDREN-2026-09-23.md)
found that a rank-tied matrix basis can expose a better coordinate
projection. This screen applies the same exact operation to all 24 pinned
structured-projection tensors: 16 direct children, one block extension,
and seven recursive descendants.

| Shape | Previous local rank | New GF(2) rank | Dated Lille entry | Source |
| --- | ---: | ---: | ---: | --- |
| 8×22×25 | 2677 | 2676 | 2686 | basis rewrite of 8×23×25:2752 |
| 10×20×22 | 2672 | 2671 | 2673 | basis rewrite of 20×23×10:2743 |

The bounded three-generation screen checked 152 changed basis variants
and 7,914 coordinate deletions. Its second generation found no further
gain. These two seeds lower five numerical entries in the local
composition closure; only the direct two cross the dated comparison.
For contrast, a separate exact screen of 19 block/portfolio-composed
parents checked 112 basis variants and 6,574 deletions with no gain.
This is evidence for targeting projection-derived representations, not
a proof that other composition parents are unproductive.

The [manifest](certificates/structured-neutral-children-20260923/manifest.json)
pins full source, basis, and output tensor hashes. Replay rebuilds all 24
parents from certified portfolio inputs, checks tensor identity before
and after the basis change, compares coordinate deletion against an
independent bit-grid projector, then runs the Ruby full-tensor verifier.
The MFW1 output files are generated outside the repository.

The external comparison digest was created 2026-09-18T17:17:29 with
SHA-256 `a77c4286cd7ad9b5212b679d9e1e21672c7519a41124a3d71079d68bf0878213`.
These are exact GF(2) upper bounds, not claims of optimality, cross-field
validity, or worldwide novelty.

From the repository root:

```sh
python3 bits/tungsten-metaflip/tools/screen_neutral_basis_children.py \
  --digest PATH/TO/fmm_sota.json --parent-set structured-projections \
  --depth 3 --output-dir /tmp/metaflip-structured-neutral-screen
python3 bits/tungsten-metaflip/tools/screen_neutral_basis_children.py \
  --replay-manifest bits/tungsten-metaflip/tools/certificates/structured-neutral-children-20260923/manifest.json \
  --output-dir /tmp/metaflip-structured-neutral-replay
python3 bits/tungsten-metaflip/spec/structured_neutral_children_test.py
```
