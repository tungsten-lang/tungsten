# Compact GF(2) structured-parent portfolio

`manifest.json` records 81 exact matrix-multiplication tensor constructions.
Each uses a checked-in, independently verified GF(2) parent, an integral scale,
and a deterministic pure-axis grouping with verified recursive leaves. The
expanded tensors are generated on demand, not stored in the repository.

The 81 ranks are strictly below the closure obtained from the verified F2
schemes in [matmulcatalog revision 54fa5d24](https://github.com/solven-eu/matmulcatalog/tree/54fa5d24f2b26299574bb044bd3e4b2c676cadf6)
using block splits and Kronecker products. The catalog index SHA-256 is
`1a43aedc346bae47458dafe053fcff6ec78934ffc7124b8c046960b9891a2719`.
This is a precisely scoped comparison, **not** a claim that all 81 ranks are
new world records. Other fields can have smaller ranks; for example, the
catalog has characteristic-not-2 schemes below our ranks for 5×9×20 and
10×24×25.

Two representative constructions are 5×9×20 at rank 624 (catalog GF(2)
recursive closure: 629) and 10×24×25 at rank 3,500 (closure: 3,564). Ten
additional scale-7/8 constructions were checked after the original 71; all
ten remain below the catalog closure even after adding the earlier portfolio
and verified local checkpoints. They lower the pinned catalog-plus-earlier
portfolio closure on 32 shapes through dimension 32 (aggregate rank gain 788),
but no square shape. Every generated tensor was also checked by
the separate Python full-parity verifier, with no tensor mismatch.

Five of the new GF(2) ranks are numerically below the [Lille table](https://fmm.univ-lille.fr/)
(version `2b71762f906bef43f0ce25d31a9b8e5ad28a23db`, checked 2026-09-22):
12×25×28: 4,708 vs 4,784; 14×18×25: 3,681 vs 3,694; 15×16×28:
3,815 vs 3,843; 15×20×28: 4,700 vs 4,734; and 16×25×32: 7,055 vs
7,096. These are **GF(2)-only** certificates; the numerical comparison does
not establish an all-field or non-commutative record.

From the repository root:

```sh
ruby bits/tungsten-metaflip/tools/replay_structured_parent_portfolio.rb \
  --output /tmp/metaflip-structured-parent-replay
python3 bits/tungsten-metaflip/spec/structured_parent_portfolio_test.py
python3 bits/tungsten-metaflip/tools/check_structured_parent_catalog.py \
  /path/to/pinned/docs/catalog.json
```

The replay command requires a new or empty output directory and checks each
parent hash, formula rank, generated tensor hash, and complete recipe replay.
The focused Python test independently expands all 81 tensors. The catalog
checker requires the pinned index because the large external catalog is not
vendored here.
