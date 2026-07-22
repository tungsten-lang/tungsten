use ../lib/metaflip/fleet/archive
use ../lib/metaflip/seeds/catalog

# Regression for promoted 7x7 exact artifacts, including cloud and CPU tunnels.
# The production verifier is support-major; this coefficient-major oracle is
# intentionally independent so a shared indexing defect cannot admit a seed.

failures = 0 ## i64

-> ff7csp_expect(label, condition) (String bool) i64
  if !condition
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

-> ff7csp_archive_contains(archive, wanted) i64
  found = 0 ## i64
  i = 0 ## i64
  while i < archive.size()
    if ffn_distance(archive[i], wanted) == 0
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
affine_child_name = "matmul_7x7_rank247_d3094_affine_code_cuda_epoch257_gf2.txt"
affine_parent_name = "matmul_7x7_rank247_d3096_affine_code_cuda_epoch3306_gf2.txt"
affine_root_name = "matmul_7x7_rank247_d3098_affine_code_gf2.txt"
default_name = "matmul_7x7_rank247_d3094_three_flip_density_gf2.txt"
promoted_name = "matmul_7x7_rank247_d3486_c013_runpod_epoch1965_continuation_gf2.txt"
former_name = "matmul_7x7_rank247_d3492_outer_isotropy_c013_cuda_epoch67_gf2.txt"
low_source_name = "matmul_7x7_rank247_d3542_c013_runpod_cuda_epoch1965_g6417_gf2.txt"
old_low_name = "matmul_7x7_rank247_d3538_peterson_2026_runpod_cuda_epoch27_novelty_gf2.txt"
c013_name = "matmul_7x7_rank247_d3554_outer_isotropy_c013_m7_gf2.txt"
pocket_name = "matmul_7x7_rank247_d3546_autonomous_flip_pocket_gf2.txt"
closure_name = "matmul_7x7_rank247_d3496_fixed_rank_pocket_greedy_closure_gf2.txt"
d3_s7_name = "matmul_7x7_rank247_d3554_d3_partial_nullspace_s7_gf2.txt"

beam_child = i64[state_size]
beam_parent = i64[state_size]
beam_dense = i64[state_size]
affine_child = i64[state_size]
affine_parent = i64[state_size]
affine_root = i64[state_size]
default_seed = i64[state_size]
promoted = i64[state_size]
former = i64[state_size]
low_source = i64[state_size]
c013 = i64[state_size]
pocket = i64[state_size]
closure = i64[state_size]
d3_s7 = i64[state_size]

beam_rank = ffw_load_scheme_cap(beam_child, root + beam_child_name, 7, capacity, 77101, 0, 1, 1, 1) ## i64
beam_parent_rank = ffw_load_scheme_cap(beam_parent, root + beam_parent_name, 7, capacity, 77103, 0, 1, 1, 1) ## i64
beam_dense_rank = ffw_load_scheme_cap(beam_dense, root + beam_dense_name, 7, capacity, 77105, 0, 1, 1, 1) ## i64
affine_rank = ffw_load_scheme_cap(affine_child, root + affine_child_name, 7, capacity, 77107, 0, 1, 1, 1) ## i64
affine_parent_rank = ffw_load_scheme_cap(affine_parent, root + affine_parent_name, 7, capacity, 77109, 0, 1, 1, 1) ## i64
affine_root_rank = ffw_load_scheme_cap(affine_root, root + affine_root_name, 7, capacity, 77111, 0, 1, 1, 1) ## i64
default_rank = ffw_load_scheme_cap(default_seed, root + default_name, 7, capacity, 77113, 0, 1, 1, 1) ## i64
promoted_rank = ffw_load_scheme_cap(promoted, root + promoted_name, 7, capacity, 77115, 0, 1, 1, 1) ## i64
former_rank = ffw_load_scheme_cap(former, root + former_name, 7, capacity, 77116, 0, 1, 1, 1) ## i64
low_source_rank = ffw_load_scheme_cap(low_source, root + low_source_name, 7, capacity, 77118, 0, 1, 1, 1) ## i64
c013_rank = ffw_load_scheme_cap(c013, root + c013_name, 7, capacity, 77117, 0, 1, 1, 1) ## i64
pocket_rank = ffw_load_scheme_cap(pocket, root + pocket_name, 7, capacity, 77119, 0, 1, 1, 1) ## i64
closure_rank = ffw_load_scheme_cap(closure, root + closure_name, 7, capacity, 77121, 0, 1, 1, 1) ## i64
d3_s7_rank = ffw_load_scheme_cap(d3_s7, root + d3_s7_name, 7, capacity, 77123, 0, 1, 1, 1) ## i64

rediscovery_checked = 0 ## i64
if ARGV.size() > 0
  rediscovery = i64[state_size]
  rediscovery_rank = ffw_load_scheme_cap(rediscovery, ARGV[0], 7, capacity, 77125, 0, 1, 1, 1) ## i64
  failures += ff7csp_expect("rediscovery rank/density", rediscovery_rank == 247 && ffw_best_bits(rediscovery) == 3486)
  if rediscovery_rank == 247
    failures += ff7csp_expect("rediscovery support-major exact", ffw_verify_best_exact(rediscovery, 7) == 1)
    failures += ff7csp_expect("rediscovery coefficient-major exact", ff7csp_coefficient_error(rediscovery, rediscovery_rank, 7) == 0)
    failures += ff7csp_expect("rediscovery repeats epoch1965 endpoint support", ffn_distance(rediscovery, promoted) == 0)
  rediscovery_checked = 1

failures += ff7csp_expect("epoch1849 rank/density", beam_rank == 247 && ffw_best_bits(beam_child) == 3096)
failures += ff7csp_expect("epoch1849 support-major exact", ffw_verify_best_exact(beam_child, 7) == 1)
failures += ff7csp_expect("epoch1849 coefficient-major exact", ff7csp_coefficient_error(beam_child, beam_rank, 7) == 0)
failures += ff7csp_expect("epoch257 rank/density", affine_rank == 247 && ffw_best_bits(affine_child) == 3094)
failures += ff7csp_expect("epoch257 support-major exact", ffw_verify_best_exact(affine_child, 7) == 1)
failures += ff7csp_expect("epoch257 coefficient-major exact", ff7csp_coefficient_error(affine_child, affine_rank, 7) == 0)

failures += ff7csp_expect("provenance roots still exact", beam_parent_rank == 247 && affine_parent_rank == 247 && affine_root_rank == 247 && ffw_verify_best_exact(beam_parent, 7) == 1 && ffw_verify_best_exact(affine_parent, 7) == 1 && ffw_verify_best_exact(affine_root, 7) == 1)
failures += ff7csp_expect("epoch1849 is a three-term exchange", ffn_distance(beam_child, beam_parent) == 6)
failures += ff7csp_expect("epoch1849 retains beam-dense relation", beam_dense_rank == 247 && ffn_distance(beam_child, beam_dense) == 316)
failures += ff7csp_expect("epoch257 is a three-term exchange from epoch3306", ffn_distance(affine_child, affine_parent) == 6)
failures += ff7csp_expect("epoch257 remains in the affine-code lineage", ffn_distance(affine_parent, affine_root) == 6 && ffn_distance(affine_child, affine_root) == 12)
failures += ff7csp_expect("promoted children remain independent", ffn_distance(beam_child, affine_child) == 494)
failures += ff7csp_expect("beam child remains outside default", default_rank == 247 && ffn_distance(beam_child, default_seed) == 494)
failures += ff7csp_expect("affine child ties the default from a distant support", ffn_distance(affine_child, default_seed) == 396 && ffw_best_bits(affine_child) == ffw_best_bits(default_seed))
failures += ff7csp_expect("autonomous pocket rank/density", pocket_rank == 247 && ffw_best_bits(pocket) == 3546)
failures += ff7csp_expect("autonomous pocket dual exact", ffw_verify_best_exact(pocket, 7) == 1 && ff7csp_coefficient_error(pocket, pocket_rank, 7) == 0)
failures += ff7csp_expect("autonomous pocket is a three-term exchange", c013_rank == 247 && ffn_distance(pocket, c013) == 6)
failures += ff7csp_expect("autonomous pocket remains outside default", ffn_distance(pocket, default_seed) == 494)
failures += ff7csp_expect("greedy pocket rank/density", closure_rank == 247 && ffw_best_bits(closure) == 3496)
failures += ff7csp_expect("greedy pocket dual exact", ffw_verify_best_exact(closure, 7) == 1 && ff7csp_coefficient_error(closure, closure_rank, 7) == 0)
failures += ff7csp_expect("greedy pocket provenance distances", ffn_distance(closure, c013) == 28 && ffn_distance(closure, pocket) == 26 && ffn_distance(closure, default_seed) == 494)
failures += ff7csp_expect("epoch1965 endpoint rank/density", promoted_rank == 247 && ffw_best_bits(promoted) == 3486)
failures += ff7csp_expect("epoch1965 endpoint dual exact", ffw_verify_best_exact(promoted, 7) == 1 && ff7csp_coefficient_error(promoted, promoted_rank, 7) == 0)
failures += ff7csp_expect("epoch1965 source rank/density", low_source_rank == 247 && ffw_best_bits(low_source) == 3542)
failures += ff7csp_expect("epoch1965 source dual exact", ffw_verify_best_exact(low_source, 7) == 1 && ff7csp_coefficient_error(low_source, low_source_rank, 7) == 0)
failures += ff7csp_expect("former epoch67 endpoint remains exact", former_rank == 247 && ffw_best_bits(former) == 3492 && ffw_verify_best_exact(former, 7) == 1 && ff7csp_coefficient_error(former, former_rank, 7) == 0)
failures += ff7csp_expect("epoch1965 continuation provenance", ffn_distance(promoted, low_source) == 42 && ffn_distance(low_source, former) == 62 && ffn_distance(promoted, former) == 20)
failures += ff7csp_expect("epoch1965 extends the pocket branch", c013_rank == 247 && ffn_distance(promoted, c013) == 40 && ffn_distance(promoted, pocket) == 38 && ffn_distance(promoted, closure) == 24)
failures += ff7csp_expect("epoch1965 distinct from d3-s7", d3_s7_rank == 247 && ffn_distance(promoted, d3_s7) == 254)
failures += ff7csp_expect("epoch1965 outside density leader", ffn_distance(promoted, default_seed) == 494)
failures += ff7csp_expect("former epoch67 provenance relationships", ffn_distance(former, c013) == 32 && ffn_distance(former, closure) == 4 && ffn_distance(former, d3_s7) == 246 && ffn_distance(former, default_seed) == 494)

frontier = ffp_frontier_seed_paths(7)
failures += ff7csp_expect("frontier promotes d3486 and retains replay child", frontier.size() == 18 && ff7csp_contains(frontier, prefix + promoted_name) == 1 && ff7csp_contains(frontier, prefix + pocket_name) == 1)
failures += ff7csp_expect("epoch1849 active", ff7csp_contains(frontier, prefix + beam_child_name) == 1)
failures += ff7csp_expect("epoch257 active", ff7csp_contains(frontier, prefix + affine_child_name) == 1)
failures += ff7csp_expect("beam provenance parent inactive", ff7csp_contains(frontier, prefix + beam_parent_name) == 0)
failures += ff7csp_expect("affine provenance parent inactive", ff7csp_contains(frontier, prefix + affine_parent_name) == 0)
failures += ff7csp_expect("affine provenance root inactive", ff7csp_contains(frontier, prefix + affine_root_name) == 0)
failures += ff7csp_expect("dominated pocket closure not automatically active", ff7csp_contains(frontier, prefix + closure_name) == 0)
failures += ff7csp_expect("former C013 endpoint not automatically active", ff7csp_contains(frontier, prefix + former_name) == 0)
failures += ff7csp_expect("epoch1965 source stays in cold quota", ff7csp_contains(frontier, prefix + low_source_name) == 0 && ffp_low_quota_seed_paths(7).size() == 1 && ffp_low_quota_seed_paths(7)[0] == prefix + low_source_name)

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
expected_paths.push(prefix + promoted_name)
expected_paths.push(prefix + pocket_name)
expected_paths.push(prefix + "matmul_7x7_rank247_d3554_outer_isotropy_c021_m4_gf2.txt")
expected_paths.push(prefix + "matmul_7x7_rank247_d3554_outer_isotropy_c024_m0_gf2.txt")
expected_paths.push(prefix + d3_s7_name)
expected_paths.push(prefix + "matmul_7x7_rank247_d3554_d3_partial_nullspace_s9_gf2.txt")
expected_paths.push(prefix + "matmul_7x7_rank247_d3098_odd_parent3_gf2.txt")
expected_paths.push(prefix + affine_child_name)

beam_distances = i64[18]
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
beam_distances[16] = 494
beam_distances[17] = 494

affine_distances = i64[18]
affine_distances[0] = 396
affine_distances[1] = 398
affine_distances[2] = 402
affine_distances[3] = 68
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
affine_distances[14] = 494
affine_distances[15] = 494
affine_distances[16] = 68
affine_distances[17] = 0

failures += ff7csp_expect("distance fixtures cover every active root", expected_paths.size() == frontier.size() && beam_distances.size() == frontier.size() && affine_distances.size() == frontier.size())
startup_archive = []
startup_default = i64[state_size]
startup_default_rank = ffw_reseed_from(startup_default, default_seed, 77301) ## i64
failures += ff7csp_expect("startup archive default clone", startup_default_rank == 247)
startup_archive.push(startup_default)
startup_archive_counters = i64[3]
i = 0 ## i64
while i < frontier.size()
  failures += ff7csp_expect("active root order " + i.to_s(), frontier[i] == expected_paths[i])
  active = i64[state_size]
  active_rank = ffw_load_scheme_cap(active, runtime_root + frontier[i], 7, capacity, 77201 + i, 0, 1, 1, 1) ## i64
  failures += ff7csp_expect("active root exact " + i.to_s(), active_rank == 247 && ffw_verify_best_exact(active, 7) == 1)
  failures += ff7csp_expect("epoch1849 distance to active root " + i.to_s(), ffn_distance(beam_child, active) == beam_distances[i])
  failures += ff7csp_expect("epoch257 distance to active root " + i.to_s(), ffn_distance(affine_child, active) == affine_distances[i])
  z = ffn_archive_add(startup_archive, active, 16, 4, startup_archive_counters) ## i64
  i += 1
failures += ff7csp_expect("complete vectors pin child-child distance", beam_distances[17] == 494 && affine_distances[7] == 494 && ffn_distance(beam_child, affine_child) == 494)
failures += ff7csp_expect("default startup archive retains strongest pocket", startup_archive.size() == 16 && ff7csp_archive_contains(startup_archive, promoted) == 1)

experimental_paths = ffp_experimental_seed_paths(7)
failures += ff7csp_expect("four explicit 7x7 parent replays", experimental_paths.size() == 4 && ff7csp_contains(experimental_paths, prefix + closure_name) == 1 && ff7csp_contains(experimental_paths, prefix + former_name) == 1 && ff7csp_contains(experimental_paths, prefix + old_low_name) == 1 && ff7csp_contains(experimental_paths, prefix + affine_parent_name) == 1)

if failures > 0
  exit(1)
<< "PASS 7x7 cloud seed promotion roots=18 active-d3486=1 low-d3542=1 active-affine-d3094=1 explicit-parents=4 source-gap=42 former-gap=20 rediscovery-checked=" + rediscovery_checked.to_s() + " beam_parent_d=6 affine_parent_d=6 incumbent_d=396 cross_d=494"
