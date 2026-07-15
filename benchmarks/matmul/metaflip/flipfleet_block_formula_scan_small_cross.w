use flipfleet_block_leaf_pool

# Deterministic balanced scan of the seam omitted by the historical 12--32
# block audit: one sorted target dimension is 8--11 while either remaining
# dimension may reach 32.  A complete exact 2--8 leaf pool is required because
# the rank-47 outer induces every 2xa xb orientation in this band.

root = "benchmarks/matmul/metaflip/"
outer = ffbc_load_exact(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 128)
if outer == nil
  << "invalid or missing rank-47 outer"
  exit(1)
leaves = ffbcp_stable_2_to_8(root)
if leaves.size() != 84
  << "incomplete stable 2--8 leaf pool: " + leaves.size().to_s()
  exit(1)

<< "target\tformula_rank\talloc_n\talloc_m\talloc_p\tsource\ts3_code"
n = 8 ## i64
while n <= 11
  m = n ## i64
  while m <= 32
    p = m ## i64
    while p <= 32
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
