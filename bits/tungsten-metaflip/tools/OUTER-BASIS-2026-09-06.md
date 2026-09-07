# Exact outer-basis screening

`outer_basis_products.rb` adds a reusable offline construction search with
GL(2,2)^3 outer images, positive unequal block allocations, exact leaf
witnesses, and replayable recipes. It reuses the existing contracted-index
isotropy construction; it is not a new primitive flip move.

The complete 680-shape screen (dimensions 2 through 16) evaluated
62,208,000 formulas and materialized 71,660 exact candidates. It produced
27 constructions below the pinned explicit-F2 catalog entries, including
7×7×8 rank 274, 7×7×9 rank 313, and 13×16×16 rank 2006. These are
reference-relative candidate records, not confirmed world-record claims.

See the [retained audit](../../../benchmarks/matmul/metaflip/outer_basis_audit_2026_09_06/README.md)
for all ranks, leaf/parent/result snapshots, source field checks, exact
verification, and limits. The raw comparator JSON is kept outside the
distributable bit. No canonical record or seed promotion occurred.

```sh
ruby bits/tungsten-metaflip/tools/outer_basis_products.rb \
  --parent bits/tungsten-metaflip/lib/metaflip/seeds/gf2/matmul_2x2_rank7_strassen_gf2.txt \
  --library /path/to/exact/matmul-witnesses \
  --targets 7x7x8,7x7x9 --maximum 15 --slack 2 \
  --materializations 256 --output /new/output
ruby bits/tungsten-metaflip/tools/outer_basis_products.rb \
  --replay /new/output/7x7x8.recipe.json
ruby bits/tungsten-metaflip/spec/outer_basis_products_test.rb
```

The tool deduplicates 216 action words into 36 exact term-multiset images.
Formula screening and exact materialization are separate APIs, allowing
bounded admission without confusing a cheap formula with an exact result.
The wide driver considers at most 256 recipes within two units of the best
formula, and only when that formula is within two of the fixed incumbent.
This does not exhaust higher-formula cancellations or arbitrary tensor rank.

The earlier four elementary-group candidates were not improved by this
family. A separate 109,736-triple XOR census also found no improvement on
6×9×9 rank 338. Both negative controls are retained rather than omitted.

Useful next checks are recursive reuse of the new witnesses and a stronger
complete known-GF(2) witness library. Neither numerical table entries without
coefficients nor non-bilinear/other-field formulas should be admitted as
leaf witnesses. The production CPU/GPU fleet is unchanged by these tools.

## Complete-library and leaf-portfolio follow-up

The complete verified library rescan improves 13x13x16 from 1711 to 1702,
13x14x16 from 1815 to 1810, and 15x15x15 from 2057 to 2055. A separate exact
leaf-portfolio search also reaches the last rank and improves coefficient
density on all 27 tested candidates. These are verified GF(2) bounds, not
confirmed world records or integer-field algorithms.

`outer_leaf_portfolio.rb` supplies exact leaf variants, incremental term-set
XOR scoring, bounded single/paired descent, and elementary-shear walks. The
eight-round 15x15x15 walk kept rank 2055 while reducing coefficient density to
56,050; it reached its round limit while still improving.

`outer_basis_products.rb --screen-before-verify` optionally screens proposals
before fully verifying the selected winner. Default admission is unchanged.
Six matched 64-proposal ABBA cases produced identical witnesses/histograms and
observed 2.05x to 3.02x faster offline materialization. This is not a production
flips/s measurement. The selected winner is always fully checked, including
in this faster mode.

See the [follow-up audit](../../../benchmarks/matmul/metaflip/outer_leaf_audit_2026_09_06/README.md)
for all limits, frozen sources, recipes, and independent verification of 1,041
retained tensors. No canonical seed promotion or publication occurred.

## Targeted long-word follow-up

`outer_representation_walk.rb` now exposes bounded `shear`, `swap`, `both`,
and `kernel` representation walks. The kernel mode targets clipped leaf axes
with canonical invertible basis words, fully verifies the resulting leaves,
and replays every admitted history. It does not require each intermediate
elementary shear to improve the score.

This finds **13x13x16 rank 1701 over GF(2)**, improving 1702. One four-move word
makes a third nominal term vanish after clipping. Subsequent polishing keeps
1701 and lowers coefficient density to 37,241. The final witness and both
independent verification routes are retained in the
[recursive/kernel audit](../../../benchmarks/matmul/metaflip/recursive_kernel_audit_2026_09_06/README.md).

The same audit completes the earlier 36,968-proposal cutoff remainder without
another gain, and checks recursive reuse through dimension 32. Derived local
improvements are kept separate from new direct ranks and external record
claims. The production CPU/GPU search remains unchanged.

The [screened and paired-kernel follow-up](KERNEL-REPRESENTATION-2026-09-06.md)
adds cheaper exact admission, matched timing evidence, bounded two-axis
kernel words, and independently replayed intermediate tensors. It keeps
additional density improvements separate from new rank claims.
