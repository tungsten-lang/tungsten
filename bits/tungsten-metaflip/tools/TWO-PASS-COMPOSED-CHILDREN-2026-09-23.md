# Two-pass basis gains from the composed chain, 2026-09-23

The existing native wide transform queue offers twelve two-pass basis modes
(6–17). Applying them to six pinned tensors in the composed-parent/neutral
chain, then deleting at most one coordinate and running exact cleanup, gives
three improved GF(2) matrix-multiplication tensors:

| Shape | Previous local | New rank | Live Lille index |
| --- | ---: | ---: | ---: |
| 16×23×31 | 6381 | 6380 | 6384 |
| 16×24×31 | 6487 | 6484 | 6549 |
| 16×25×31 | 6903 | 6888 | 6914 |

The finite screen checked 72 basis contexts and 5,148 one-coordinate
projections. Its retained outputs have complete GF(2) tensor expansion checks,
independent bit-grid projection checks where applicable, Ruby full-tensor
checks, and native basis-mode byte parity. A second-generation screen from
these three outputs checked 36 contexts and 2,556 projections; it retained
no further gain. Adding the three ranks as seeds lowers 43 numerical local
block/Kronecker closure prices over sorted triples in `[2,32]³`; none of the
additional price drops newly crosses the Lille table. These prices are not
independently expanded tensor certificates.

The [manifest](certificates/two-pass-composed-children-20260923/manifest.json)
pins each source, basis, and output digest. Replay rebuilds the original
portfolio/Strassen-composed and neutral-basis parents before applying the
two-pass modes. Large `.mfw` files are generated outside the repository.
The comparison digest was created 2026-09-18T17:17:29 with SHA-256
`a77c4286cd7ad9b5212b679d9e1e21672c7519a41124a3d71079d68bf0878213`;
the [live Lille index](https://fmm.univ-lille.fr/) was checked on 2026-09-23.
These are exact GF(2) upper bounds against that index, not claims of
optimality, cross-field validity, or worldwide novelty.

From the repository root, choose fresh output directories:

```sh
python3 -B bits/tungsten-metaflip/tools/screen_two_pass_basis_children.py \
  --replay-manifest bits/tungsten-metaflip/tools/certificates/two-pass-composed-children-20260923/manifest.json \
  --output-dir /tmp/metaflip-two-pass-composed-replay
tungsten compile bits/tungsten-metaflip/spec/wide_transform_queue_test.w \
  --out /tmp/metaflip-wide-transform-probe --release --native
python3 -B bits/tungsten-metaflip/spec/two_pass_composed_children_test.py \
  --native /tmp/metaflip-wide-transform-probe
python3 -B bits/tungsten-metaflip/tools/screen_two_pass_basis_children.py \
  --digest PATH/TO/fmm_sota.json --parent-set composed-chain
python3 -B bits/tungsten-metaflip/tools/screen_two_pass_basis_children.py \
  --digest PATH/TO/fmm_sota.json --parent-set composed-descendants
```

The modes were already automatic for wide parents admitted to the queue;
this certificate does not yet make the offline composed parents live fleet
seeds.
