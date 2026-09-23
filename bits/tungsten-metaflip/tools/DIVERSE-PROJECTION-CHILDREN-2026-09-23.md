# Near-best projection children, 2026-09-23

The [structured-parent projection screen](STRUCTURED-PARENT-PROJECTIONS-2026-09-23.md)
kept only one best-rank representation of each first-step shape. This bounded
follow-up tested the alternatives with a *slightly worse* first-step rank:
more than the selected rank, but at most 25 higher. Among the same 81 exact
GF(2) portfolio parents and 16 selected first-step shapes, 207 such
intermediates produced 11,266 second-coordinate projections. Each candidate
was cleaned by exact shared-factor matrix operations and compared with the
existing local composition closure and the dated
[Lille table](https://fmm.univ-lille.fr/).

| Shape | Previous GF(2) rank | New GF(2) rank | Lille entry | Intermediate |
| --- | ---: | ---: | ---: | --- |
| 8×22×25 | 2679 | 2677 | 2686 | 8×23×25 at 2756, four above its selected 2752 |
| 13×16×28 | 3389 | 3382 | 3439 | 14×16×28 at 3653, nineteen above its selected 3634 |

This is a concrete benefit of preserving near-best representations: a
rank-only archive would discard both successful intermediates. The
[manifest](certificates/diverse-projection-children-20260923/manifest.json)
pins each parent scheme, both deleted coordinates, intermediate and final
cleanup counts and hashes, and the final full-tensor hashes. Focused replay
checks both projection steps against an independent bit-grid implementation,
checks full GF(2) tensor identity after each cleanup, and runs the Ruby
full-tensor verifier on the final MFW1 files. The generated tensors are kept
outside the repository.

The numerical comparison uses an external `fmm_sota.json` digest created
2026-09-18T17:17:29 with SHA-256
`a77c4286cd7ad9b5212b679d9e1e21672c7519a41124a3d71079d68bf0878213`.
The Lille entries were checked again on 2026-09-23. These are exact GF(2)
upper bounds, not optimality, cross-field, or worldwide novelty claims.
Nor is the 25-rank beam an exhaustive search over every possible
above-table intermediate.

From the repository root, rerun the finite screen using a local digest or
rebuild the pinned witnesses into a new directory:

```sh
python3 bits/tungsten-metaflip/tools/screen_diverse_projection_children.py \
  --digest PATH/TO/fmm_sota.json \
  --output-dir /tmp/metaflip-diverse-screen
python3 bits/tungsten-metaflip/tools/screen_diverse_projection_children.py \
  --replay-manifest bits/tungsten-metaflip/tools/certificates/diverse-projection-children-20260923/manifest.json \
  --output-dir /tmp/metaflip-diverse-replay
python3 bits/tungsten-metaflip/spec/diverse_projection_children_test.py
```

The two stronger outputs have no further below-table one-coordinate child
under the current local closure (112 exact child screens). The broader search
remains open: rank ties, larger temporary rank costs, and other operations
can still lead elsewhere.
