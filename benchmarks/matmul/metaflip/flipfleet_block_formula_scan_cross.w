use flipfleet_block_composer

# Deterministic formula scan for the previously uncovered 12--32 cross-band:
# sorted targets with at least one dimension <= 20 and one dimension >= 21.
#
# The pool is deliberately identical to the production block-composition CLI:
# one checked-in exact GF(2) certificate for every sorted block shape 3--8.
# Consequently every balanced cross-band target is supported and every emitted
# recipe can be materialised without an inferred or zero-padded leaf.

-> ffbc_cross_scan_add(root, path, n, m, p, leaves)
  leaf = ffbc_load_exact(root + path, n, m, p, 4096)
  if leaf == nil
    << "invalid or missing cross-scan leaf: " + root + path
    exit(1)
  leaves.push(leaf)
  0

root = "benchmarks/matmul/metaflip/"
outer = ffbc_load_exact(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 128)
if outer == nil
  << "invalid or missing rank-47 outer"
  exit(1)

leaves = []
ffbc_cross_scan_add(root, "matmul_3x3_rank23_d139_gf2.txt", 3, 3, 3, leaves)
ffbc_cross_scan_add(root, "matmul_3x3x4_rank29_gf2.txt", 3, 3, 4, leaves)
ffbc_cross_scan_add(root, "matmul_3x3x5_rank36_gf2.txt", 3, 3, 5, leaves)
ffbc_cross_scan_add(root, "matmul_3x4x4_rank38_gf2.txt", 3, 4, 4, leaves)
ffbc_cross_scan_add(root, "matmul_3x4x5_rank47_gf2.txt", 3, 4, 5, leaves)
ffbc_cross_scan_add(root, "matmul_3x5x5_rank58_gf2.txt", 3, 5, 5, leaves)
ffbc_cross_scan_add(root, "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, leaves)
ffbc_cross_scan_add(root, "matmul_4x4x5_rank60_catalog_gf2.txt", 4, 4, 5, leaves)
ffbc_cross_scan_add(root, "matmul_4x5x5_rank76_catalog_gf2.txt", 4, 5, 5, leaves)
ffbc_cross_scan_add(root, "matmul_5x5_rank93_catalog_perminov_c843_gf2.txt", 5, 5, 5, leaves)
ffbc_cross_scan_add(root, "matmul_3x3x6_rank42_catalog_gf2.txt", 3, 3, 6, leaves)
ffbc_cross_scan_add(root, "matmul_3x3x7_rank49_catalog_gf2.txt", 3, 3, 7, leaves)
ffbc_cross_scan_add(root, "matmul_3x3x8_rank56_catalog_gf2.txt", 3, 3, 8, leaves)
ffbc_cross_scan_add(root, "matmul_3x4x6_rank54_catalog_gf2.txt", 3, 4, 6, leaves)
ffbc_cross_scan_add(root, "matmul_3x4x7_rank64_catalog_gf2.txt", 3, 4, 7, leaves)
ffbc_cross_scan_add(root, "matmul_3x4x8_rank73_catalog_gf2.txt", 3, 4, 8, leaves)
ffbc_cross_scan_add(root, "matmul_3x5x6_rank68_catalog_gf2.txt", 3, 5, 6, leaves)
ffbc_cross_scan_add(root, "matmul_3x5x7_rank79_catalog_gf2.txt", 3, 5, 7, leaves)
ffbc_cross_scan_add(root, "matmul_3x5x8_rank90_catalog_gf2.txt", 3, 5, 8, leaves)
ffbc_cross_scan_add(root, "matmul_3x6x6_rank82_catalog_gf2.txt", 3, 6, 6, leaves)
ffbc_cross_scan_add(root, "matmul_3x6x7_rank96_catalog_gf2.txt", 3, 6, 7, leaves)
ffbc_cross_scan_add(root, "matmul_3x6x8_rank108_catalog_gf2.txt", 3, 6, 8, leaves)
ffbc_cross_scan_add(root, "matmul_3x7x7_rank111_catalog_gf2.txt", 3, 7, 7, leaves)
ffbc_cross_scan_add(root, "matmul_3x7x8_rank128_catalog_gf2.txt", 3, 7, 8, leaves)
ffbc_cross_scan_add(root, "matmul_3x8x8_rank146_catalog_gf2.txt", 3, 8, 8, leaves)
ffbc_cross_scan_add(root, "matmul_4x4x6_rank73_catalog_gf2.txt", 4, 4, 6, leaves)
ffbc_cross_scan_add(root, "matmul_4x4x7_rank85_catalog_gf2.txt", 4, 4, 7, leaves)
ffbc_cross_scan_add(root, "matmul_4x4x8_rank96_catalog_gf2.txt", 4, 4, 8, leaves)
ffbc_cross_scan_add(root, "matmul_4x5x6_rank90_catalog_gf2.txt", 4, 5, 6, leaves)
ffbc_cross_scan_add(root, "matmul_4x5x7_rank104_catalog_gf2.txt", 4, 5, 7, leaves)
ffbc_cross_scan_add(root, "matmul_4x5x8_rank118_catalog_gf2.txt", 4, 5, 8, leaves)
ffbc_cross_scan_add(root, "matmul_4x6x6_rank105_catalog_gf2.txt", 4, 6, 6, leaves)
ffbc_cross_scan_add(root, "matmul_4x6x7_rank123_catalog_gf2.txt", 4, 6, 7, leaves)
ffbc_cross_scan_add(root, "matmul_4x6x8_rank140_catalog_gf2.txt", 4, 6, 8, leaves)
ffbc_cross_scan_add(root, "matmul_4x7x7_rank144_catalog_gf2.txt", 4, 7, 7, leaves)
ffbc_cross_scan_add(root, "matmul_4x7x8_rank161_catalog_gf2.txt", 4, 7, 8, leaves)
ffbc_cross_scan_add(root, "matmul_4x8x8_rank180_catalog_gf2.txt", 4, 8, 8, leaves)
ffbc_cross_scan_add(root, "matmul_5x5x6_rank110_catalog_gf2.txt", 5, 5, 6, leaves)
ffbc_cross_scan_add(root, "matmul_5x5x7_rank127_catalog_gf2.txt", 5, 5, 7, leaves)
ffbc_cross_scan_add(root, "matmul_5x5x8_rank144_catalog_gf2.txt", 5, 5, 8, leaves)
ffbc_cross_scan_add(root, "matmul_5x6x6_rank130_catalog_gf2.txt", 5, 6, 6, leaves)
ffbc_cross_scan_add(root, "matmul_5x6x7_rank150_catalog_gf2.txt", 5, 6, 7, leaves)
ffbc_cross_scan_add(root, "matmul_5x6x8_rank170_catalog_gf2.txt", 5, 6, 8, leaves)
ffbc_cross_scan_add(root, "matmul_5x7x7_rank176_catalog_gf2.txt", 5, 7, 7, leaves)
ffbc_cross_scan_add(root, "matmul_5x7x8_rank204_catalog_gf2.txt", 5, 7, 8, leaves)
ffbc_cross_scan_add(root, "matmul_5x8x8_rank230_catalog_gf2.txt", 5, 8, 8, leaves)
ffbc_cross_scan_add(root, "matmul_6x6_rank153_catalog_gf2.txt", 6, 6, 6, leaves)
ffbc_cross_scan_add(root, "matmul_6x6x7_rank183_catalog_gf2.txt", 6, 6, 7, leaves)
ffbc_cross_scan_add(root, "matmul_6x6x8_rank203_catalog_gf2.txt", 6, 6, 8, leaves)
ffbc_cross_scan_add(root, "matmul_6x7x7_rank212_catalog_gf2.txt", 6, 7, 7, leaves)
ffbc_cross_scan_add(root, "matmul_6x7x8_rank238_catalog_gf2.txt", 6, 7, 8, leaves)
ffbc_cross_scan_add(root, "matmul_6x8x8_rank266_catalog_gf2.txt", 6, 8, 8, leaves)
ffbc_cross_scan_add(root, "matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt", 7, 7, 7, leaves)
ffbc_cross_scan_add(root, "matmul_7x7x8_rank278_catalog_gf2.txt", 7, 7, 8, leaves)
ffbc_cross_scan_add(root, "matmul_7x8x8_rank310_catalog_gf2.txt", 7, 8, 8, leaves)
ffbc_cross_scan_add(root, "matmul_8x8_rank329_catalog_gf2.txt", 8, 8, 8, leaves)

<< "target\tformula_rank\talloc_n\talloc_m\talloc_p\tsource\ts3_code"
n = 12 ## i64
while n <= 20
  m = n ## i64
  while m <= 32
    p = m ## i64
    if p < 21
      p = 21
    while p <= 32
      recipe = ffbc_best_oriented_balanced_recipe(outer, n, m, p, leaves)
      if recipe != nil
        row = n.to_s() + "x" + m.to_s() + "x" + p.to_s()
        row = row + "\t" + recipe[3].to_s()
        row = row + "\t" + recipe[0].join(",") + "\t" + recipe[1].join(",") + "\t" + recipe[2].join(",")
        row = row + "\t" + recipe[4].to_s() + "x" + recipe[5].to_s() + "x" + recipe[6].to_s()
        << row + "\t" + recipe[7].to_s()
      p += 1
    m += 1
  n += 1
