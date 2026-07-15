use metaflip_worker
use flipfleet_basin_identity

-> ffcft_expect(label, condition) (String bool) i64
  if !condition
    << "CATALOG_FRONTIER_FAIL " + label
    exit(1)
  1

n = 5 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
paths = ["benchmarks/matmul/metaflip/matmul_5x5_rank93_d968_global_isotropy_gf2.txt",
         "benchmarks/matmul/metaflip/matmul_5x5_rank93_catalog_kauers_a_gf2.txt",
         "benchmarks/matmul/metaflip/matmul_5x5_rank93_catalog_kauers_b_gf2.txt",
         "benchmarks/matmul/metaflip/matmul_5x5_rank93_catalog_perminov_c843_gf2.txt"]
states = []
ids = i64[4]
i = 0 ## i64
while i < paths.size()
  state = i64[state_size]
  rank = ffw_load_scheme_cap(state, paths[i], n, capacity, 98101 + i, 4, 2, 1000, 250) ## i64
  ffcft_expect("exact seed " + i.to_s(), rank == 93 && ffw_verify_best_exact(state, n) == 1)
  ids[i] = ffbi_best_id(state)
  states.push(state)
  i += 1
i = 0
while i < ids.size()
  j = i + 1 ## i64
  while j < ids.size()
    ffcft_expect("distinct canonical doors " + i.to_s() + "/" + j.to_s(), ids[i] != ids[j])
    j += 1
  i += 1
<< "flipfleet_catalog_frontier_test: all checks passed ids=" + ids[0].to_s() + "," + ids[1].to_s() + "," + ids[2].to_s() + "," + ids[3].to_s()
