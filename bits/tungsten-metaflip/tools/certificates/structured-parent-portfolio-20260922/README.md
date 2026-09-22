# Compact GF(2) structured-parent portfolio

`manifest.json` records 71 exact matrix-multiplication tensor constructions.
Each uses a checked-in, independently verified GF(2) parent, an integral scale,
and a deterministic pure-axis grouping with verified recursive leaves. The
expanded tensors are generated on demand, not stored in the repository.

The 71 ranks are strictly below the closure obtained from the verified F2
schemes in [matmulcatalog revision 54fa5d24](https://github.com/solven-eu/matmulcatalog/tree/54fa5d24f2b26299574bb044bd3e4b2c676cadf6)
using block splits and Kronecker products. The catalog index SHA-256 is
`1a43aedc346bae47458dafe053fcff6ec78934ffc7124b8c046960b9891a2719`.
This is a precisely scoped comparison, **not** a claim that all 71 ranks are
new world records. Other fields can have smaller ranks; for example, the
catalog has characteristic-not-2 schemes below our ranks for 5×9×20 and
10×24×25.

Two representative constructions are 5×9×20 at rank 624 (catalog GF(2)
recursive closure: 629) and 10×24×25 at rank 3,500 (closure: 3,564). Every
generated tensor was also checked by the separate Python full-parity verifier:
71 certificates and 20,564,085 term-pair XORs, with no tensor mismatch.

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
The focused Python test independently expands all 71 tensors. The catalog
checker requires the pinned index because the large external catalog is not
vendored here.
