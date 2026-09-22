# Exact GF(2) 4×12×25 rank-813 construction

This is a compact, reproducible construction, **not a world-record claim**.
The parent is a rank-33 2×4×5 representation found by a bounded
composition-priced walk from the packaged `matmul_2x4x5_rank33_d222_fleet_gf2.txt`
seed. The product uses scale 2×3×5. The packaged parent priced at rank 822;
this parent and recipe produce rank 813.

`4x12x25.recipe.json` records the parent, leaf schemes, grouping, and output
SHA-256. The `inputs/`, `leaves/`, and `candidates/` files are the complete
recipe dependencies and exact output, not a campaign archive. Replay with:

```sh
cd bits/tungsten-metaflip
ruby tools/bud_products.rb --replay tools/certificates/4x12x25-r813-20260922/4x12x25.recipe.json
```

An independent full GF(2) check of the 813 output terms found exactly the
4×12×25 matrix-multiplication tensor (28,577 input-pair XORs). The output
file's SHA-256 is
`0b8e7633030577b5b92caf31ea1f62e075a71a1ddfdef03fd96e27c75defbdc4`.
External best-known status is not established by this certificate.
