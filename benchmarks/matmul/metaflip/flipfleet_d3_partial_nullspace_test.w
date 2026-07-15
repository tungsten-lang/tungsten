use flipfleet_d3_partial_nullspace
use flipfleet_profiles

-> ffd3nst_expect(label, condition) (String bool) i64
  if !condition
    << "D3_PARTIAL_NULLSPACE_FAIL " + label
    exit(1)
  1

-> ffd3nst_published_id(path, n, expected_rank) (String i64 i64) i64
  capacity = ffw_default_capacity(n) ## i64
  state = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(state, path, n, capacity, 95201 + n, 0, 1, 1, 1) ## i64
  ffd3nst_expect("published reload rank", rank == expected_rank)
  ffd3nst_expect("published full gate", ffw_verify_best_exact(state, n) == 1)
  identity = ffbi_best_id(state) ## i64
  paths = ffp_frontier_seed_paths(n)
  index = 0 ## i64
  while index < paths.size()
    if paths[index] != path
      other = i64[ffw_state_size(capacity)]
      other_rank = ffw_load_scheme_cap(other, paths[index], n, capacity, 95301 + index, 0, 1, 1, 1) ## i64
      ffd3nst_expect("archive source exact", other_rank == expected_rank && ffw_verify_best_exact(other, n) == 1)
      ffd3nst_expect("published D3 archive novelty", ffbi_best_id(other) != identity)
    index += 1
  identity

-> ffd3nst_source_distance(source_path, endpoint_path, n, expected_rank) (String String i64 i64) i64
  capacity = ffw_default_capacity(n) ## i64
  state_size = ffw_state_size(capacity) ## i64
  source = i64[state_size]
  endpoint = i64[state_size]
  ffd3nst_expect("distance source load", ffw_load_scheme_cap(source, source_path, n, capacity, 95401 + n, 0, 1, 1, 1) == expected_rank)
  ffd3nst_expect("distance endpoint load", ffw_load_scheme_cap(endpoint, endpoint_path, n, capacity, 95501 + n, 0, 1, 1, 1) == expected_rank)
  source_u = i64[capacity]
  source_v = i64[capacity]
  source_w = i64[capacity]
  endpoint_u = i64[capacity]
  endpoint_v = i64[capacity]
  endpoint_w = i64[capacity]
  ffd3nst_expect("distance source export", ffw_export_best(source, source_u, source_v, source_w) == expected_rank)
  ffd3nst_expect("distance endpoint export", ffw_export_best(endpoint, endpoint_u, endpoint_v, endpoint_w) == expected_rank)
  ffpan_term_set_distance_unique(source_u, source_v, source_w, expected_rank, endpoint_u, endpoint_v, endpoint_w, expected_rank)

# Exhaustive combination closure of an independent three-direction basis.
effective = i64[3]
effective[0] = 1
effective[1] = 2
effective[2] = 4
combos = i64[7]
combo_meta = i64[8]
combo_count = ffd3ns_build_combos(effective, 3, 1, 7, 12, combos, combo_meta) ## i64
ffd3nst_expect("three-dimensional closure", combo_count == 7 && combo_meta[0] == 7 && combo_meta[2] == 1)
seen = i64[8]
i = 0 ## i64
while i < combo_count
  ffd3nst_expect("unique exhaustive mask", combos[i] > 0 && combos[i] < 8 && seen[combos[i]] == 0)
  seen[combos[i]] = 1
  i += 1

# A capped kernel keeps sparse local relations but reserves half of the
# post-pair budget for reproducible full-width selectors.
dense_effective = i64[13]
i = 0
while i < 13
  dense_effective[i] = 1 << i
  i += 1
dense_combos = i64[128]
dense_meta = i64[8]
dense_count = ffd3ns_build_combos_mixed(dense_effective, 13, 1, 128, 12, dense_combos, dense_meta) ## i64
ffd3nst_expect("bounded dense closure", dense_count == 128 && dense_meta[2] == 0 && dense_meta[7] > 0)
dense_seen = i64[8192]
i = 0
while i < dense_count
  ffd3nst_expect("bounded selector nonzero", dense_combos[i] > 0 && dense_combos[i] < 8192)
  ffd3nst_expect("bounded selector unique", dense_seen[dense_combos[i]] == 0)
  dense_seen[dense_combos[i]] = 1
  i += 1

# Projection removes fixed coefficients and row-reduces duplicate projected
# directions instead of counting them as independent endpoint dimensions.
dependencies = i64[4]
dependencies[0] = 1
dependencies[1] = 6
dependencies[2] = 24
dependencies[3] = 7
stable = i64[6]
stable[0] = 1
projected = i64[6]
project_pivots = i32[6]
project_work = i64[1]
project_meta = i64[2]
dimension = ffd3ns_project_kernel(dependencies, 4, 6, 1, stable, projected, project_pivots, project_work, project_meta) ## i64
ffd3nst_expect("fixed projection rank", dimension == 2 && project_meta[0] == 3 && project_meta[1] == 1)

# Full real-scheme audit across every non-identity D3 x reversal factor map.
n = 4 ## i64
capacity = ffw_default_capacity(n) ## i64
state = i64[ffw_state_size(capacity)]
rank = ffw_load_scheme_cap(state, "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt", n, capacity, 95101, 0, 1, 1, 1) ## i64
ffd3nst_expect("4x4 source exact", rank == 47 && ffw_verify_best_exact(state, n) == 1)
workspace = FFD3NSWorkspace.new(rank, n, capacity, 4096)
meta = i64[28]
maps = 0 ## i64
attempted = 0 ## i64
effective_sum = 0 ## i64
genuine = 0 ## i64
source_d3_novel = 0 ## i64
reverse = 0 ## i64
while reverse < 2
  code = 0 ## i64
  while code < 6
    if code != 0 || reverse != 0
      scanned = ffd3ns_scan_state(state, code, reverse, 12, workspace, meta) ## i64
      ffd3nst_expect("map scan succeeds", scanned >= 0)
      ffd3nst_expect("kernel relations authoritative", meta[7] == 0 && meta[27] == 0)
      ffd3nst_expect("materialized endpoints full-gated", meta[9] == meta[8])
      ffd3nst_expect("combination accounting", scanned == meta[4] && meta[2] <= meta[0])
      maps += 1
      attempted += meta[4]
      effective_sum += meta[2]
      genuine += meta[13]
      source_d3_novel += meta[14]
    code += 1
  reverse += 1
ffd3nst_expect("all nonidentity maps", maps == 11)

# Published representatives are independently reload-gated, D3-distinct from
# every other live frontier seed, and nontrivially far from their exact source.
p5 = "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1291_d3_partial_nullspace_s8_gf2.txt" ## String
p6a = "benchmarks/matmul/metaflip/matmul_6x6_rank153_d2508_d3_partial_nullspace_s3_gf2.txt" ## String
p6b = "benchmarks/matmul/metaflip/matmul_6x6_rank153_d2512_d3_partial_nullspace_s4_gf2.txt" ## String
p7a = "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3554_d3_partial_nullspace_s7_gf2.txt" ## String
p7b = "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3554_d3_partial_nullspace_s9_gf2.txt" ## String
id5 = ffd3nst_published_id(p5, 5, 93) ## i64
id6a = ffd3nst_published_id(p6a, 6, 153) ## i64
id6b = ffd3nst_published_id(p6b, 6, 153) ## i64
id7a = ffd3nst_published_id(p7a, 7, 247) ## i64
id7b = ffd3nst_published_id(p7b, 7, 247) ## i64
ffd3nst_expect("published 6x6 representatives distinct", id6a != id6b)
ffd3nst_expect("published 7x7 representatives distinct", id7a != id7b)
ffd3nst_expect("published 5x5 tunnel distance", ffd3nst_source_distance("benchmarks/matmul/metaflip/matmul_5x5_rank93_catalog_kauers_a_gf2.txt", p5, 5, 93) == 32)
ffd3nst_expect("published 6x6 s3 tunnel distance", ffd3nst_source_distance("benchmarks/matmul/metaflip/matmul_6x6_rank153_d2508_gf2.txt", p6a, 6, 153) == 8)
ffd3nst_expect("published 6x6 s4 tunnel distance", ffd3nst_source_distance("benchmarks/matmul/metaflip/matmul_6x6_rank153_d2512_gf2.txt", p6b, 6, 153) == 16)
ffd3nst_expect("published 7x7 s7 tunnel distance", ffd3nst_source_distance("benchmarks/matmul/metaflip/matmul_7x7_rank247_d3554_outer_isotropy_c013_m7_gf2.txt", p7a, 7, 247) == 216)
ffd3nst_expect("published 7x7 s9 tunnel distance", ffd3nst_source_distance("benchmarks/matmul/metaflip/matmul_7x7_rank247_d3554_outer_isotropy_c024_m0_gf2.txt", p7b, 7, 247) == 216)

<< "flipfleet_d3_partial_nullspace_test: pass maps=" + maps.to_s() + " combos=" + attempted.to_s() + " effective_sum=" + effective_sum.to_s() + " genuine=" + genuine.to_s() + " source_d3_novel=" + source_d3_novel.to_s()
