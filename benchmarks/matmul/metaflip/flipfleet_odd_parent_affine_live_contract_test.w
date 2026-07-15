use flipfleet_odd_parent_affine_splice
use flipfleet_global_isotropy
use flipfleet_profiles

-> ffoasct_expect(label, condition) (String bool) i64
  if !condition
    << "ODD_PARENT_AFFINE_CONTRACT_FAIL " + label
    exit(1)
  1

-> ffoasct_profile_contains(n, needle) (i64 String) i64
  paths = ffp_frontier_seed_paths(n)
  i = 0 ## i64
  while i < paths.size()
    if paths[i].include?(needle)
      return 1
    i += 1
  0

-> ffoasct_check(label, output_path, n, parent_paths, expected_rank, expected_density, expected_min_distance, expected_max_distance) (String String i64 Array i64 i64 i64 i64) i64
  parent_count = parent_paths.size() ## i64
  stride = parent_count * expected_rank ## i64
  if stride < expected_rank + 1
    stride = expected_rank + 1
  bank_u = i64[parent_count * stride]
  bank_v = i64[parent_count * stride]
  bank_w = i64[parent_count * stride]
  ranks = i64[parent_count]
  load_state = i64[ffw_state_size(stride)]
  raw_u = i64[stride]
  raw_v = i64[stride]
  raw_w = i64[stride]
  canonical_u = i64[stride]
  canonical_v = i64[stride]
  canonical_w = i64[stride]
  parent = 0 ## i64
  while parent < parent_count
    loaded = ffw_load_scheme_cap(load_state, parent_paths[parent], n, stride, 950001 + n * 1009 + parent * 17, 0, 1, 1, 1) ## i64
    ffoasct_expect(label + " parent load", loaded == expected_rank && ffw_verify_current_exact(load_state, n) == 1)
    exported = ffw_export_current(load_state, raw_u, raw_v, raw_w) ## i64
    canonical_rank = ffoas_canonicalize(raw_u, raw_v, raw_w, exported, canonical_u, canonical_v, canonical_w) ## i64
    ffoasct_expect(label + " parent canonical", canonical_rank == expected_rank)
    ranks[parent] = canonical_rank
    ffoas_copy_slot(canonical_u, canonical_v, canonical_w, 0, bank_u, bank_v, bank_w, parent * stride, canonical_rank)
    parent += 1

  output_state = i64[ffw_state_size(stride)]
  output_rank = ffw_load_scheme_cap(output_state, output_path, n, stride, 950101 + n, 0, 1, 1, 1) ## i64
  ffoasct_expect(label + " output full gate", output_rank == expected_rank && ffw_verify_current_exact(output_state, n) == 1)
  output_u = i64[stride]
  output_v = i64[stride]
  output_w = i64[stride]
  ffw_export_current(output_state, raw_u, raw_v, raw_w)
  canonical_output_rank = ffoas_canonicalize(raw_u, raw_v, raw_w, output_rank, output_u, output_v, output_w) ## i64
  ffoasct_expect(label + " output density", canonical_output_rank == expected_rank && ffgir_density(output_u, output_v, output_w, output_rank) == expected_density)

  ids = i64[parent_count]
  parent = 0
  while parent < parent_count
    ids[parent] = parent
    parent += 1
  splice_raw_u = i64[stride]
  splice_raw_v = i64[stride]
  splice_raw_w = i64[stride]
  splice_u = i64[stride]
  splice_v = i64[stride]
  splice_w = i64[stride]
  splice_rank = ffoas_materialize(bank_u, bank_v, bank_w, stride, ranks, ids, parent_count, splice_raw_u, splice_raw_v, splice_raw_w, splice_u, splice_v, splice_w) ## i64
  ffoasct_expect(label + " deterministic replay", splice_rank == output_rank && ffoas_equal_slot(output_u, output_v, output_w, 0, output_rank, splice_u, splice_v, splice_w, splice_rank) == 1)
  replay_state = i64[ffw_state_size(stride)]
  replay_loaded = ffw_init_terms_cap(replay_state, splice_u, splice_v, splice_w, splice_rank, n, stride, 950201 + n, 0, 1, 1, 1) ## i64
  ffoasct_expect(label + " replay full gate", replay_loaded == splice_rank && ffw_verify_current_exact(replay_state, n) == 1)
  min_distance = 9223372036854775807 ## i64
  max_distance = 0 ## i64
  parent = 0
  while parent < parent_count
    distance = ffoas_distance_slot(bank_u, bank_v, bank_w, parent * stride, ranks[parent], splice_u, splice_v, splice_w, splice_rank) ## i64
    if distance < min_distance
      min_distance = distance
    if distance > max_distance
      max_distance = distance
    parent += 1
  ffoasct_expect(label + " parent distances", min_distance == expected_min_distance && max_distance == expected_max_distance)
  1

base = "benchmarks/matmul/metaflip/" ## String
ffoasct_expect("6x6 triple density path registered", ffoasct_profile_contains(6, "d2506_odd_parent3") == 1)
ffoasct_expect("6x6 triple novelty path registered", ffoasct_profile_contains(6, "d2527_odd_parent3_novel") == 1)
ffoasct_expect("6x6 five density path registered", ffoasct_profile_contains(6, "d2522_odd_parent5") == 1)
ffoasct_expect("6x6 five novelty path registered", ffoasct_profile_contains(6, "d2533_odd_parent5_novel") == 1)
ffoasct_expect("7x7 triple path registered", ffoasct_profile_contains(7, "d3098_odd_parent3") == 1)

p6_triple = []
p6_triple.push(base + "matmul_6x6_rank153_d2502_gf2.txt")
p6_triple.push(base + "matmul_6x6_rank153_d2508_gf2.txt")
p6_triple.push(base + "matmul_6x6_rank153_d2512_gf2.txt")
ffoasct_check("6x6 triple density", base + "matmul_6x6_rank153_d2506_odd_parent3_gf2.txt", 6, p6_triple, 153, 2506, 4, 12)

p6_triple_novel = []
p6_triple_novel.push(base + "matmul_6x6_rank153_d2512_gf2.txt")
p6_triple_novel.push(base + "matmul_6x6_rank153_d2512_d3_partial_nullspace_s4_gf2.txt")
p6_triple_novel.push(base + "matmul_6x6_rank153_catalog_gf2.txt")
ffoasct_check("6x6 triple novelty", base + "matmul_6x6_rank153_d2527_odd_parent3_novel_gf2.txt", 6, p6_triple_novel, 153, 2527, 16, 20)

p6_five = []
p6_five.push(base + "matmul_6x6_rank153_d2502_gf2.txt")
p6_five.push(base + "matmul_6x6_rank153_d2508_gf2.txt")
p6_five.push(base + "matmul_6x6_rank153_d2512_gf2.txt")
p6_five.push(base + "matmul_6x6_rank153_d2508_d3_partial_nullspace_s3_gf2.txt")
p6_five.push(base + "matmul_6x6_rank153_d2512_d3_partial_nullspace_s4_gf2.txt")
ffoasct_check("6x6 five density", base + "matmul_6x6_rank153_d2522_odd_parent5_gf2.txt", 6, p6_five, 153, 2522, 12, 24)

p6_five_novel = []
p6_five_novel.push(base + "matmul_6x6_rank153_d2508_gf2.txt")
p6_five_novel.push(base + "matmul_6x6_rank153_d2512_gf2.txt")
p6_five_novel.push(base + "matmul_6x6_rank153_d2508_d3_partial_nullspace_s3_gf2.txt")
p6_five_novel.push(base + "matmul_6x6_rank153_d2512_d3_partial_nullspace_s4_gf2.txt")
p6_five_novel.push(base + "matmul_6x6_rank153_catalog_gf2.txt")
ffoasct_check("6x6 five novelty", base + "matmul_6x6_rank153_d2533_odd_parent5_novel_gf2.txt", 6, p6_five_novel, 153, 2533, 20, 24)

p7_triple = []
p7_triple.push(base + "matmul_7x7_rank247_d3098_global_isotropy_gf2.txt")
p7_triple.push(base + "matmul_7x7_rank247_d3098_partial_auto_max_distance_gf2.txt")
p7_triple.push(base + "matmul_7x7_rank247_d3098_partial_auto_min_density_gf2.txt")
ffoasct_check("7x7 triple", base + "matmul_7x7_rank247_d3098_odd_parent3_gf2.txt", 7, p7_triple, 247, 3098, 40, 382)

<< "flipfleet_odd_parent_affine_live_contract_test: pass replayed=5 profile6=" + ffp_frontier_seed_paths(6).size().to_s() + " profile7=" + ffp_frontier_seed_paths(7).size().to_s()
