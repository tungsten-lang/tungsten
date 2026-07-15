use flipfleet_partial_automorphism_nullspace
use flipfleet_global_isotropy

-> ffpanblt_expect(label, condition) (String bool) i64
  if !condition
    << "PARTIAL_AUTOMORPHISM_BEAM_TEST_FAIL " + label
    exit(1)
  1

-> ffpanblt_load(path, n, capacity, seed, state, us, vs, ws) (String i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  rank = ffw_load_scheme_cap(state, path, n, capacity, seed, 0, 1, 1, 1) ## i64
  if rank > 0 && ffw_verify_best_exact(state, n) == 1
    if ffw_export_best(state, us, vs, ws) == rank
      return rank
  0

n = 7 ## i64
capacity = ffw_default_capacity(n) ## i64
root_state = i64[ffw_state_size(capacity)]
dense_state = i64[ffw_state_size(capacity)]
far_state = i64[ffw_state_size(capacity)]
root_u = i64[capacity]
root_v = i64[capacity]
root_w = i64[capacity]
dense_u = i64[capacity]
dense_v = i64[capacity]
dense_w = i64[capacity]
far_u = i64[capacity]
far_v = i64[capacity]
far_w = i64[capacity]

root_rank = ffpanblt_load("benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_global_isotropy_gf2.txt", n, capacity, 991001, root_state, root_u, root_v, root_w) ## i64
dense_rank = ffpanblt_load("benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_partial_auto_beam_dense_gf2.txt", n, capacity, 991003, dense_state, dense_u, dense_v, dense_w) ## i64
far_rank = ffpanblt_load("benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_partial_auto_beam_far_gf2.txt", n, capacity, 991007, far_state, far_u, far_v, far_w) ## i64
ffpanblt_expect("three exact rank-247 schemes", root_rank == 247 && dense_rank == 247 && far_rank == 247)
ffpanblt_expect("densities", ffgir_density(root_u, root_v, root_w, root_rank) == 3098 && ffgir_density(dense_u, dense_v, dense_w, dense_rank) == 3098 && ffgir_density(far_u, far_v, far_w, far_rank) == 3098)

dense_source_distance = ffgir_term_set_distance(root_u, root_v, root_w, root_rank, dense_u, dense_v, dense_w, dense_rank) ## i64
far_source_distance = ffgir_term_set_distance(root_u, root_v, root_w, root_rank, far_u, far_v, far_w, far_rank) ## i64
peer_distance = ffgir_term_set_distance(dense_u, dense_v, dense_w, dense_rank, far_u, far_v, far_w, far_rank) ## i64
ffpanblt_expect("dense endpoint is source-disjoint", dense_source_distance == 494)
ffpanblt_expect("far endpoint is source-disjoint", far_source_distance == 494)
ffpanblt_expect("beam endpoints are distinct", peer_distance > 0)
ffpanblt_expect("beam endpoints have distinct basin telemetry", ffbi_best_id(dense_state) != ffbi_best_id(far_state))

<< "flipfleet_partial_automorphism_nullspace_beam_test: all checks passed source_distance=" + dense_source_distance.to_s() + "/" + far_source_distance.to_s() + " peer_distance=" + peer_distance.to_s()
