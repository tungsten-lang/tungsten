# Middle-basis shear projection, 2026-09-23

An exact GF(2) tensor for 16×23×31 has rank **6,376**. The previous local
witness had rank 6,380; the [Lille index](https://fmm.univ-lille.fr/) listed
6,384 when checked on 2026-09-23. This is an upper bound relative to that
index, not a claim of optimality, cross-field validity, or catalog acceptance.

The source is the pinned rank-6,484 tensor for 16×24×31 from the
[two-pass composed chain](certificates/two-pass-composed-children-20260923/manifest.json).
For middle coordinate `a=12` and rows `S={0,6,18}`, change every term by
`A[i,a] ^= A[i,b]` and `B[b,j] ^= B[a,j]` for each `b` in `S`; leave the output
factor alone. This involutive change preserves the matrix-multiplication
tensor. Delete middle coordinate 12, then apply exact matrix cleanup. The
projection has 6,457 terms before cleanup; 55 cleanup steps leave 6,376.

The bounded screen first checked all 552 ordered one-row middle shears and
selected the deleted coordinate. At that coordinate it checked the empty mask
and every two- and three-row mask (singletons were already in the first
phase): 2,577 logical contexts total. The selected mask is `262209`. A
separate one-toggle walk from it found no further drop; that is local search
evidence, not an exhaustive statement about larger masks or other deleted
coordinates. The [manifest](certificates/middle-shear-children-20260923/manifest.json)
pins the source, operation, and result hashes. Replay rebuilds the entire
source chain; its final witness passes Python tensor expansion, independent
bit-grid projection, and Ruby full-tensor verification. Large `.mfw` witnesses
are generated outside the repository.

Adding this rank to the local block/Kronecker price library lowers 15 prices
on sorted triples in `[2,32]³`. None of the other price drops newly crosses
the Lille index, and those prices are not separate expanded certificates.
The composed-descendant screen baseline reads this certificate, so subsequent
screens do not rediscover the superseded rank 6,380. The shear screen currently
runs as an offline exact tool, not the live native transform queue; automatic
runtime scheduling needs a matched cost/benefit check on more parents.

From the repository root, use fresh output directories:

```sh
python3 -B bits/tungsten-metaflip/spec/middle_shear_children_test.py
python3 -B bits/tungsten-metaflip/tools/screen_middle_shear_children.py \
  --screen-source-sha256 011e5a1d36803c97824958c95a5dd9aab4ee6768824d244fcc65af3a7f10b34f
python3 -B bits/tungsten-metaflip/tools/screen_middle_shear_children.py \
  --replay-manifest bits/tungsten-metaflip/tools/certificates/middle-shear-children-20260923/manifest.json \
  --output-dir /tmp/metaflip-middle-shear-replay
```
