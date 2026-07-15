# Rank-93 outer-composition audit

This is a complete balanced, support-aware audit of seven exact rank-93
`5x5x5` outer schemes over every sorted target `15 <= n <= m <= p <= 32`.
It tests whether support diversity among same-rank 5x5 presentations can
improve the rectangular formulas produced by the two retained exact rank-47
`4x4x4` outers.

The implementation is
[`flipfleet_block_outer5_scan.w`](flipfleet_block_outer5_scan.w).  It is a
single-threaded pure-Tungsten scanner with no TUI or GPU dependency.  Build and
replay it from the repository root with:

```sh
bin/tungsten compile --release --lto \
  -o /tmp/flipfleet-block-outer5-scan \
  benchmarks/matmul/metaflip/flipfleet_block_outer5_scan.w

/tmp/flipfleet-block-outer5-scan summary 15 32
/tmp/flipfleet-block-outer5-scan target 15x20x30 all
```

`table` in place of `summary` emits all 7,980 formula rows.  A strict formula
win against the effective baseline is materialized, compacted, reconstructed
exactly, and written under `/tmp` only if the exact rank remains a win.

## Exact inputs and comparison frontier

Every outer and leaf is reconstructed exactly while loading.  The leaf pool
contains all 56 sorted shapes with block dimensions 3 through 8; S3
orientation supplies every ordered shape.  The audited outers are:

| label | density | 16x23x31 probe rank | source |
|---|---:|---:|---|
| Perminov c843 | 1,054 | 6,790 | catalog |
| AlphaEvolve | 1,057 | 6,790 | catalog |
| Kauers A | 1,291 | 6,775 | catalog |
| Kauers B | 1,250 | 6,837 | catalog |
| d967 | 967 | 6,807 | FlipFleet four-split continuation |
| d1155 | 1,155 | 6,794 | FlipFleet C3/GPU frontier |
| d1191 | 1,191 | 6,834 | FlipFleet C3 seed |

The public comparison is persisted in
[`block_composition_outer5_public_baseline.tsv`](block_composition_outer5_public_baseline.tsv).
It has one row for each of the 1,140 sorted targets and combines the pinned
FMM-Lille digest, the verified explicit schemes in matmulcatalog, and the
characteristic-zero `fmm-17-32` freeze.  Revisions and input hashes are in
[`block_composition_outer5_public_baseline_sources.tsv`](block_composition_outer5_public_baseline_sources.tsv).
The effective comparison for a target is the minimum of that public rank, the
two rank-47 formulas, and the repository's prior exact block-composition audit
tables.  This deliberately prevents an apparent improvement over one local
formula from being mislabeled as a record when a stronger public construction
already exists.

For speed, the scanner reduces each outer term to six support masks and uses a
constant rank table.  Before any sweep it checks the optimized scorer against
the generic authoritative scorer on the 16x23x31 probe for both rank-47 outers
and all seven rank-93 outers.  The exact composer remains the final gate for a
candidate.

## Result

There are no effective formula wins and therefore no certificates to promote.
Across all seven outers together:

- 11 of 1,140 targets beat the best rank-47 formula, and two tie it;
- zero beat the effective public/local baseline;
- the closest miss is `15x20x30`: rank 5,022 versus effective rank 4,992,
  even though it improves the rank-47 formula by 54 terms;
- the largest rank-47 gain is 89 terms at `20x30x30`, but public rank 9,573
  is another 192 terms lower than the rank-93-outer formula; and
- d1155 gives the useful support-specific ranks 4,890 for `15x19x30` and
  3,840 for `15x15x29`, respectively 51 and 12 below the rank-47 formulas,
  but still 40 and 156 above the effective baselines.

The support variants are not redundant.  Formula ranks differ on 1,080 of
1,140 targets, and the sweep contains 1,125 distinct seven-outer rank vectors.
Unique pointwise wins are split among Kauers A (337 targets), d1155 (317),
d967 (26), AlphaEvolve (17), and Kauers B (2).  Those five outers are the
minimum portfolio reproducing the pointwise best of all seven.  AlphaEvolve
weakly dominates Perminov on this domain, while d1155 weakly dominates d1191.

The complete per-outer summary is machine-readable in
[`block_composition_outer5_audit.tsv`](block_composition_outer5_audit.tsv).
On the audit machine the final pass used one process, 7.84 CPU seconds, 8.54
wall seconds, and a peak resident set of 631,308,288 bytes.  The bounded
negative says that present rank-93 outer support diversity alone is not a
production replacement for the rank-47 outer.  The 30-term `15x20x30` gap is
the best target for revisiting this family after a leaf-rank improvement or a
new rank-92/rank-93 outer with materially different supports.
