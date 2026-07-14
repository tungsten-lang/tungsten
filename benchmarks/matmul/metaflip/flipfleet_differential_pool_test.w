use metaflip_worker
use flipfleet_mitm_lane_lib
use flipfleet_differential_pool_lib

-> ffpdt_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)

-> ffpdt_parent(base, n, cap, size, uset, v, w, seed)
  us = i64[cap]
  vs = i64[cap]
  ws = i64[cap]
  rank = ffw_export_best(base, us, vs, ws) ## i64
  i = 0 ## i64
  while i < uset.size()
    rank = ffm_toggle_plain(us, vs, ws, rank, cap, uset[i], v, w)
    i += 1
  state = i64[size]
  loaded = ffw_init_terms_cap(state, us, vs, ws, rank, n, cap, seed, 0, 1, 1, 1) ## i64
  if loaded != rank || ffw_verify_best_exact(state, n) != 1
    return nil
  state

n = 3 ## i64
cap = ffw_default_capacity(n) ## i64
size = ffw_state_size(cap) ## i64
base = i64[size]
rank = ffw_init_naive_cap(base, n, cap, 17, 0, 1, 1, 1) ## i64
ffpdt_expect("naive exact", rank == 27 && ffw_verify_best_exact(base, n) == 1)

# Each parent carries a different primitive five-circuit.  Their symmetric
# difference has distance ten, and removing parent A's circuit produces a
# third exact state rather than copying parent B.
parent_a = ffpdt_parent(base, n, cap, size, [1, 2, 4, 8, 15], 3, 5, 19)
parent_b = ffpdt_parent(base, n, cap, size, [16, 32, 64, 128, 240], 6, 10, 23)
ffpdt_expect("parents exact", parent_a != nil && parent_b != nil)
ffpdt_expect("parents rank", ffw_best_rank(parent_a) == 32 && ffw_best_rank(parent_b) == 32)
path_a = "/tmp/ffpd_parent_a.txt"
path_b = "/tmp/ffpd_parent_b.txt"
output = "/tmp/ffpd_output.txt"
z = ffw_dump_best(parent_a, path_a) ## i64
z = ffw_dump_best(parent_b, path_b)

# The exact nullspace strategy is primary when the full difference fits the
# bound.  The synthetic parents have two independent five-circuit directions.
direct_hit = ffpd_try_nullspace(parent_a, parent_b, output, n, cap, 16, 10) ## i64
ffpdt_expect("primary exact nullspace hit", direct_hit == 27)
direct_candidate = i64[size]
direct_loaded = ffw_load_scheme_cap(direct_candidate, output, n, cap, 27, 0, 1, 1, 1) ## i64
ffpdt_expect("primary nullspace output exact", direct_loaded == 27 && ffw_verify_best_exact(direct_candidate, n) == 1)

hit = ffpd_search(path_a, path_b, output, n, 16, 0, 8) ## i64
ffpdt_expect("differential hit", hit == 27)
candidate = i64[size]
loaded = ffw_load_scheme_cap(candidate, output, n, cap, 29, 0, 1, 1, 1) ## i64
ffpdt_expect("output exact", loaded == 27 && ffw_verify_best_exact(candidate, n) == 1)
ffpdt_expect("output is hybrid", read_file(output) != read_file(path_a) && read_file(output) != read_file(path_b))

# If the complete difference exceeds the elimination bound, the legacy
# primitive-five window remains available as a real fallback.
fallback = ffpd_search(path_a, path_b, output, n, 5, 0, 8) ## i64
ffpdt_expect("primitive-five fallback", fallback == 27)
fallback_candidate = i64[size]
fallback_loaded = ffw_load_scheme_cap(fallback_candidate, output, n, cap, 31, 0, 1, 1, 1) ## i64
ffpdt_expect("fallback output exact", fallback_loaded == 27 && ffw_verify_best_exact(fallback_candidate, n) == 1)

# Identical or too-close parents are a clean miss, never malformed output.
miss = ffpd_search(path_a, path_a, output, n, 16, 0, 8) ## i64
ffpdt_expect("identical parents miss", miss == 0)

# Production-record regression: nullspace elimination over the 16-term
# difference between these two 5x5 records emits the exact rank-93/density-1165
# hybrid used as a new archive basin.
n5 = 5 ## i64
cap5 = ffw_default_capacity(n5) ## i64
size5 = ffw_state_size(cap5) ## i64
real_output = "/tmp/ffpd_real_5x5.txt"
real_hit = ffpd_search("benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt", "benchmarks/matmul/metaflip/matmul_5x5_rank93_d1168_gf2.txt", real_output, n5, 96, 0, 12) ## i64
ffpdt_expect("real 5x5 nullspace worker hit", real_hit == 93)
real_candidate = i64[size5]
real_loaded = ffw_load_scheme_cap(real_candidate, real_output, n5, cap5, 37, 0, 1, 1, 1) ## i64
real_density = ffw_view_bits(real_candidate, real_candidate[47], real_candidate[48], real_candidate[49], 0 - 1, real_loaded) ## i64
ffpdt_expect("real 5x5 hybrid exact", real_loaded == 93 && real_density == 1165 && ffw_verify_best_exact(real_candidate, n5) == 1)

cmd = ffpd_epoch_command("/repo root", "/tmp/diff worker", path_a, path_b, output, n, 64, 7, 12)
ffpdt_expect("native command", cmd.include?("'/tmp/diff worker'") && !cmd.include?("python"))
ffpdt_expect("build command", ffpd_build_command("/repo root", "/tmp/diff worker").include?("flipfleet_differential_pool.w"))

<< "flipfleet_differential_pool_test: all checks passed"
