# Top-two projection beam, 2026-09-23

The previous [near-best screen](DIVERSE-PROJECTION-CHILDREN-2026-09-23.md)
followed alternatives only for sixteen already-promising first-step shapes.
This screen starts from every one-coordinate deletion of all 81 exact GF(2)
structured-parent tensors: 4,279 projections covering 229 shapes. It keeps
at most two distinct full representations per shape, ordered by cleaned rank
and tensor hash. A first-step representation is explored when its rank is at
most 50 above the lower of the current local composition price and the dated
[Lille table](https://fmm.univ-lille.fr/) entry. That leaves 211
intermediates and 10,521 second-coordinate projections.

| Shape | Previous local rank | New GF(2) rank | Lille entry | Route |
| --- | ---: | ---: | ---: | --- |
| 8×13×16 | 1068 | 1044 | 1054 | 8×15×16 → 8×14×16:1129 → 8×13×16 |
| 14×20×27 | 4551 | 4423 | 4454 | 15×20×28 → 14×20×28:4506 → 14×20×27 |
| 15×16×22 | 3071 | 3069 | 3168 | 15×16×24 → 15×16×23:3168 → 15×16×22 |
| 16×26×32 | 7388 | 7308 | 7378 | 8×13×16:1044 ⊗ 2×2×2:7 |

The first route is especially instructive: its rank-1129 intermediate is
*above* Lille's 1104 for 8×14×16, yet its child beats Lille's 1054 for
8×13×16. Filtering out every above-table intermediate would miss it. The
third route improves a local tensor already well below the table. The exact
composition closure of these three seeds also crosses the table at
16×26×32; the full 7,308-term tensor was materialized and checked.

The [manifest](certificates/top-two-projection-children-20260923/manifest.json)
pins parent schemes, both projection steps, intermediate/final cleanup
counts and tensor hashes, and the exact rank-7 Strassen source. Focused replay
checks both deletions with an independent bit-grid projector, verifies full
GF(2) tensor identity after each cleanup and after the Kronecker product,
and runs the Ruby full-tensor verifier on each final MFW1 file. The generated
tensors are not stored in this repository.

Numerical comparisons use external `fmm_sota.json` created
2026-09-18T17:17:29, SHA-256
`a77c4286cd7ad9b5212b679d9e1e21672c7519a41124a3d71079d68bf0878213`.
The Lille table was checked again on 2026-09-23. These constructions are
exact GF(2) upper bounds, not claims of optimality, cross-field validity,
or worldwide novelty. This is a bounded top-two, 50-rank beam, not an
exhaustive search over every possible intermediate representation.

From the repository root, repeat the finite screen with a local digest or
rebuild all four pinned tensors into a new output directory:

```sh
python3 bits/tungsten-metaflip/tools/screen_top_two_projection_children.py \
  --digest PATH/TO/fmm_sota.json \
  --output-dir /tmp/metaflip-top-two-screen
python3 bits/tungsten-metaflip/tools/screen_top_two_projection_children.py \
  --replay-manifest bits/tungsten-metaflip/tools/certificates/top-two-projection-children-20260923/manifest.json \
  --output-dir /tmp/metaflip-top-two-replay
python3 bits/tungsten-metaflip/spec/top_two_projection_children_test.py
```

An additional 151 one-coordinate projections of the three improved direct
tensors found no further below-table child under the current local closure.
Projecting the *composed* 16×26×32 tensor did yield a further three-step
[exact chain](COMPOSED-PARENT-CHILDREN-2026-09-23.md).
