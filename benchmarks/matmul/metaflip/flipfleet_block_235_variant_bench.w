use flipfleet_block_leaf_pool

# Compare every checked-in rank-25 <2,3,5> presentation inside two balanced
# block records which use that leaf 39 and 47 times.  Prepending the variant
# deliberately overrides the stable d160 tie without changing formula scoring.

-> ffb235_expect(label, condition)
  if condition != 0
    return 1
  << "BLOCK_235_VARIANT_FAIL " + label
  exit(1)
  0

root = "benchmarks/matmul/metaflip/"
outer = ffbc_load_exact(root + "matmul_4x4_rank47_d450_gf2.txt", 4, 4, 4, 128)
stable = ffbcp_stable_2_to_8(root)
ffb235_expect("pool", outer != nil && stable.size() == 84)

paths = [
  "matmul_2x3x5_rank25_d160_fleet_gf2.txt",
  "matmul_2x3x5_rank25_d170_fleet_gf2.txt",
  "matmul_2x3x5_rank25_d173_alphatensor_zt_mod2_gf2.txt",
  "matmul_2x3x5_rank25_d210_fleet_gf2.txt",
  "matmul_2x3x5_rank25_d278_fleet_gf2.txt"
]
tns = i64[2]
tms = i64[2]
tps = i64[2]
tns[0] = 8
tms[0] = 11
tps[0] = 20
tns[1] = 8
tms[1] = 12
tps[1] = 20

ti = 0 ## i64
while ti < 2
  recipe = ffbc_best_oriented_balanced_recipe(outer, tns[ti], tms[ti], tps[ti], stable)
  ffb235_expect("recipe", recipe != nil)
  vi = 0 ## i64
  while vi < paths.size()
    variant = ffbc_load_exact(root + paths[vi], 2, 3, 5, 64)
    ffb235_expect("variant", variant != nil && variant.rank() == 25)
    leaves = [variant]
    i = 0 ## i64
    while i < stable.size()
      leaves.push(stable[i])
      i += 1
    result = ffbc_compose_oriented_recipe(outer, tns[ti], tms[ti], tps[ti], leaves, recipe)
    ffb235_expect("composition", result != nil && ffbc_verify_exact(result) == 1)
    << "BLOCK_235_VARIANT target=" + tns[ti].to_s() + "x" + tms[ti].to_s() + "x" + tps[ti].to_s() + " leaf=" + paths[vi] + " formula=" + recipe[3].to_s() + " exact=" + result.rank().to_s()
    vi += 1
  ti += 1
