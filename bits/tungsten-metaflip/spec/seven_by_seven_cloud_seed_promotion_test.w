use ../lib/metaflip/fleet/archive
use ../lib/metaflip/seeds/catalog

# Regression for exact artifacts harvested from the fd25c71 Runpod campaign.
# The production verifier is support-major; this coefficient-major oracle is
# intentionally independent so a shared indexing defect cannot admit a seed.

failures = 0 ## i64

-> ff7csp_expect(label, condition) (String bool) i64
  if condition == 0
    << "FAIL 7x7 cloud seed promotion: " + label
    return 1
  0

-> ff7csp_contains(paths, wanted)
  found = 0 ## i64
  i = 0 ## i64
  while i < paths.size()
    if paths[i] == wanted
      found = 1
    i += 1
  found

-> ff7csp_coefficient_error(st, rank, n) (i64[] i64 i64) i64
  uo = st[47] ## i64
  vo = st[48] ## i64
  wo = st[49] ## i64
  width = n * n ## i64
  ai = 0 ## i64
  while ai < width
    bi = 0 ## i64
    while bi < width
      ci = 0 ## i64
      while ci < width
        got = 0 ## i64
        term = 0 ## i64
        while term < rank
          if ((st[uo + term] >> ai) & 1) != 0 && ((st[vo + term] >> bi) & 1) != 0 && ((st[wo + term] >> ci) & 1) != 0
            got = got ^ 1
          term += 1
        arow = ai / n ## i64
        acol = ai % n ## i64
        brow = bi / n ## i64
        bcol = bi % n ## i64
        crow = ci / n ## i64
        ccol = ci % n ## i64
        want = 0 ## i64
        if acol == brow && arow == crow && bcol == ccol
          want = 1
        if got != want
          return 1 + (ai * width + bi) * width + ci
        ci += 1
      bi += 1
    ai += 1
  0

runtime_root = __DIR__ + "/../lib/metaflip/"
root = runtime_root + "seeds/gf2/"
prefix = "seeds/gf2/"
capacity = 320 ## i64
state_size = ffw_state_size(capacity) ## i64

beam_child_name = "matmul_7x7_rank247_d3096_partial_auto_beam_far_cuda_epoch1849_gf2.txt"
beam_parent_name = "matmul_7x7_rank247_d3098_partial_auto_beam_far_gf2.txt"
beam_dense_name = "matmul_7x7_rank247_d3098_partial_auto_beam_dense_gf2.txt"
affine_child_name = "matmul_7x7_rank247_d3096_affine_code_cuda_epoch3306_gf2.txt"
affine_parent_name = "matmul_7x7_rank247_d3098_affine_code_gf2.txt"
default_name = "matmul_7x7_rank247_d3094_three_flip_density_gf2.txt"
experimental_name = "matmul_7x7_rank247_d3492_outer_isotropy_c013_cuda_epoch67_experimental_gf2.txt"
c013_name = "matmul_7x7_rank247_d3554_outer_isotropy_c013_m7_gf2.txt"
d3_s7_name = "matmul_7x7_rank247_d3554_d3_partial_nullspace_s7_gf2.txt"

beam_child = i64[state_size]
beam_parent = i64[state_size]
beam_dense = i64[state_size]
affine_child = i64[state_size]
affine_parent = i64[state_size]
default_seed = i64[state_size]
experimental = i64[state_size]
c013 = i64[state_size]
d3_s7 = i64[state_size]

beam_rank = ffw_load_scheme_cap(beam_child, root + beam_child_name, 7, capacity, 77101, 0, 1, 1, 1) ## i64
beam_parent_rank = ffw_load_scheme_cap(beam_parent, root + beam_parent_name, 7, capacity, 77103, 0, 1, 1, 1) ## i64
beam_dense_rank = ffw_load_scheme_cap(beam_dense, root + beam_dense_name, 7, capacity, 77105, 0, 1, 1, 1) ## i64
affine_rank = ffw_load_scheme_cap(affine_child, root + affine_child_name, 7, capacity, 77107, 0, 1, 1, 1) ## i64
affine_parent_rank = ffw_load_scheme_cap(affine_parent, root + affine_parent_name, 7, capacity, 77109, 0, 1, 1, 1) ## i64
default_rank = ffw_load_scheme_cap(default_seed, root + default_name, 7, capacity, 77111, 0, 1, 1, 1) ## i64
experimental_rank = ffw_load_scheme_cap(experimental, root + experimental_name, 7, capacity, 77113, 0, 1, 1, 1) ## i64
c013_rank = ffw_load_scheme_cap(c013, root + c013_name, 7, capacity, 77115, 0, 1, 1, 1) ## i64
d3_s7_rank = ffw_load_scheme_cap(d3_s7, root + d3_s7_name, 7, capacity, 77117, 0, 1, 1, 1) ## i64

failures += ff7csp_expect("epoch1849 rank/density", beam_rank == 247 && ffw_best_bits(beam_child) == 3096)
failures += ff7csp_expect("epoch1849 support-major exact", ffw_verify_best_exact(beam_child, 7) == 1)
failures += ff7csp_expect("epoch1849 coefficient-major exact", ff7csp_coefficient_error(beam_child, beam_rank, 7) == 0)
failures += ff7csp_expect("epoch3306 rank/density", affine_rank == 247 && ffw_best_bits(affine_child) == 3096)
failures += ff7csp_expect("epoch3306 support-major exact", ffw_verify_best_exact(affine_child, 7) == 1)
failures += ff7csp_expect("epoch3306 coefficient-major exact", ff7csp_coefficient_error(affine_child, affine_rank, 7) == 0)

failures += ff7csp_expect("provenance roots still exact", beam_parent_rank == 247 && affine_parent_rank == 247 && ffw_verify_best_exact(beam_parent, 7) == 1 && ffw_verify_best_exact(affine_parent, 7) == 1)
failures += ff7csp_expect("epoch1849 is a three-term exchange", ffn_distance(beam_child, beam_parent) == 6)
failures += ff7csp_expect("epoch1849 retains beam-dense relation", beam_dense_rank == 247 && ffn_distance(beam_child, beam_dense) == 316)
failures += ff7csp_expect("epoch3306 is a three-term exchange", ffn_distance(affine_child, affine_parent) == 6)
failures += ff7csp_expect("promoted children remain independent", ffn_distance(beam_child, affine_child) == 494)
failures += ff7csp_expect("beam child remains outside default", default_rank == 247 && ffn_distance(beam_child, default_seed) == 494)
failures += ff7csp_expect("affine child retains distant default relation", ffn_distance(affine_child, default_seed) == 398)

frontier = ffp_frontier_seed_paths(7)
failures += ff7csp_expect("frontier width unchanged", frontier.size() == 16)
failures += ff7csp_expect("epoch1849 active", ff7csp_contains(frontier, prefix + beam_child_name) == 1)
failures += ff7csp_expect("epoch3306 active", ff7csp_contains(frontier, prefix + affine_child_name) == 1)
failures += ff7csp_expect("beam provenance parent inactive", ff7csp_contains(frontier, prefix + beam_parent_name) == 0)
failures += ff7csp_expect("affine provenance parent inactive", ff7csp_contains(frontier, prefix + affine_parent_name) == 0)
failures += ff7csp_expect("experimental child not automatically active", ff7csp_contains(frontier, prefix + experimental_name) == 0)

# Pin the complete active-root distance vectors, not just selected examples.
# This catches a near-duplicate silently entering another slot as well as a
# future reorder that invalidates the documented provenance relationships.
expected_paths = []
expected_paths.push(prefix + default_name)
expected_paths.push(prefix + "matmul_7x7_rank247_d3096_dynamic_syzygy_gf2.txt")
expected_paths.push(prefix + "matmul_7x7_rank247_d3098_global_isotropy_gf2.txt")
expected_paths.push(prefix + "matmul_7x7_rank247_d3098_partial_auto_max_distance_gf2.txt")
expected_paths.push(prefix + "matmul_7x7_rank247_d3098_partial_auto_min_density_gf2.txt")
expected_paths.push(prefix + "matmul_7x7_rank247_d3142_partial_auto_min_weight_gf2.txt")
expected_paths.push(prefix + beam_dense_name)
expected_paths.push(prefix + beam_child_name)
expected_paths.push(prefix + "matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt")
expected_paths.push(prefix + c013_name)
expected_paths.push(prefix + "matmul_7x7_rank247_d3554_outer_isotropy_c021_m4_gf2.txt")
expected_paths.push(prefix + "matmul_7x7_rank247_d3554_outer_isotropy_c024_m0_gf2.txt")
expected_paths.push(prefix + d3_s7_name)
expected_paths.push(prefix + "matmul_7x7_rank247_d3554_d3_partial_nullspace_s9_gf2.txt")
expected_paths.push(prefix + "matmul_7x7_rank247_d3098_odd_parent3_gf2.txt")
expected_paths.push(prefix + affine_child_name)

beam_distances = i64[16]
beam_distances[0] = 494
beam_distances[1] = 494
beam_distances[2] = 494
beam_distances[3] = 494
beam_distances[4] = 494
beam_distances[5] = 494
beam_distances[6] = 316
beam_distances[7] = 0
beam_distances[8] = 494
beam_distances[9] = 494
beam_distances[10] = 494
beam_distances[11] = 494
beam_distances[12] = 494
beam_distances[13] = 494
beam_distances[14] = 494
beam_distances[15] = 494

affine_distances = i64[16]
affine_distances[0] = 398
affine_distances[1] = 398
affine_distances[2] = 402
affine_distances[3] = 62
affine_distances[4] = 402
affine_distances[5] = 402
affine_distances[6] = 494
affine_distances[7] = 494
affine_distances[8] = 494
affine_distances[9] = 494
affine_distances[10] = 494
affine_distances[11] = 494
affine_distances[12] = 494
affine_distances[13] = 494
affine_distances[14] = 62
affine_distances[15] = 0

failures += ff7csp_expect("distance fixtures cover every active root", expected_paths.size() == frontier.size() && beam_distances.size() == frontier.size() && affine_distances.size() == frontier.size())
i = 0 ## i64
while i < frontier.size()
  failures += ff7csp_expect("active root order " + i.to_s(), frontier[i] == expected_paths[i])
  active = i64[state_size]
  active_rank = ffw_load_scheme_cap(active, runtime_root + frontier[i], 7, capacity, 77201 + i, 0, 1, 1, 1) ## i64
  failures += ff7csp_expect("active root exact " + i.to_s(), active_rank == 247 && ffw_verify_best_exact(active, 7) == 1)
  failures += ff7csp_expect("epoch1849 distance to active root " + i.to_s(), ffn_distance(beam_child, active) == beam_distances[i])
  failures += ff7csp_expect("epoch3306 distance to active root " + i.to_s(), ffn_distance(affine_child, active) == affine_distances[i])
  i += 1
failures += ff7csp_expect("complete vectors pin child-child distance", beam_distances[15] == 494 && affine_distances[7] == 494 && ffn_distance(beam_child, affine_child) == 494)

experimental_paths = ffp_experimental_seed_paths(7)
failures += ff7csp_expect("one explicit 7x7 experiment", experimental_paths.size() == 1 && ff7csp_contains(experimental_paths, prefix + experimental_name) == 1)
failures += ff7csp_expect("epoch67 rank/density", experimental_rank == 247 && ffw_best_bits(experimental) == 3492)
failures += ff7csp_expect("epoch67 dual exact", ffw_verify_best_exact(experimental, 7) == 1 && ff7csp_coefficient_error(experimental, experimental_rank, 7) == 0)
failures += ff7csp_expect("epoch67 c013 descent", c013_rank == 247 && ffn_distance(experimental, c013) == 32)
failures += ff7csp_expect("epoch67 distinct from d3-s7", d3_s7_rank == 247 && ffn_distance(experimental, d3_s7) == 246)
failures += ff7csp_expect("epoch67 outside density leader", ffn_distance(experimental, default_seed) == 494)

if failures > 0
  exit(1)
<< "PASS 7x7 cloud seed promotion roots=16 active=2 experimental=1 beam_parent_d=6 affine_parent_d=6 cross_d=494"
