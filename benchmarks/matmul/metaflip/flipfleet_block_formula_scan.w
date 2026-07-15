use flipfleet_block_composer

# Deterministic formula-only scan for the complete 3--5 GF(2) leaf pool.
# It emits one TSV row for every sorted target 12 <= n <= m <= p <= 20.
# `ffbc_best_oriented_balanced_recipe` scans every unique S3 target ordering;
# materialisation may subsequently remove zero or duplicate products.
#
# Build and run from the repository root:
#   bin/tungsten compile --release --lto -o /tmp/ffbc-formula-scan \
#     benchmarks/matmul/metaflip/flipfleet_block_formula_scan.w
#   /tmp/ffbc-formula-scan > /tmp/ffbc_formula_scan.tsv

-> ffbc_formula_scan_add(root, path, n, m, p, leaves)
  full = root + path
  leaf = ffbc_load_exact(full, n, m, p, 4096)
  if leaf == nil
    << "invalid or missing scan leaf: " + full
    exit(1)
  leaves.push(leaf)
  0

root = "benchmarks/matmul/metaflip/"
outer = ffbc_load_exact(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 128)
if outer == nil
  << "invalid or missing rank-47 outer"
  exit(1)

leaves = []
ffbc_formula_scan_add(root, "matmul_3x3_rank23_d139_gf2.txt", 3, 3, 3, leaves)
ffbc_formula_scan_add(root, "matmul_3x3x4_rank29_gf2.txt", 3, 3, 4, leaves)
ffbc_formula_scan_add(root, "matmul_3x3x5_rank36_gf2.txt", 3, 3, 5, leaves)
ffbc_formula_scan_add(root, "matmul_3x4x4_rank38_gf2.txt", 3, 4, 4, leaves)
ffbc_formula_scan_add(root, "matmul_3x4x5_rank47_gf2.txt", 3, 4, 5, leaves)
ffbc_formula_scan_add(root, "matmul_3x5x5_rank58_gf2.txt", 3, 5, 5, leaves)
ffbc_formula_scan_add(root, "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, leaves)
ffbc_formula_scan_add(root, "matmul_4x4x5_rank60_catalog_gf2.txt", 4, 4, 5, leaves)
ffbc_formula_scan_add(root, "matmul_4x5x5_rank76_catalog_gf2.txt", 4, 5, 5, leaves)
ffbc_formula_scan_add(root, "matmul_5x5_rank93_catalog_alphaevolve_gf2.txt", 5, 5, 5, leaves)

<< "target\tformula_rank\talloc_n\talloc_m\talloc_p\tsource\ts3_code"
n = 12 ## i64
while n <= 20
  m = n ## i64
  while m <= 20
    p = m ## i64
    while p <= 20
      recipe = ffbc_best_oriented_balanced_recipe(outer, n, m, p, leaves)
      if recipe == nil
        << "no balanced recipe for " + n.to_s() + "x" + m.to_s() + "x" + p.to_s()
        exit(1)
      row = n.to_s() + "x" + m.to_s() + "x" + p.to_s()
      row = row + "\t" + recipe[3].to_s()
      row = row + "\t" + recipe[0].join(",") + "\t" + recipe[1].join(",") + "\t" + recipe[2].join(",")
      row = row + "\t" + recipe[4].to_s() + "x" + recipe[5].to_s() + "x" + recipe[6].to_s()
      << row + "\t" + recipe[7].to_s()
      p += 1
    m += 1
  n += 1
