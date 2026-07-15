# Deterministically materialize three exact, quotient-novel 7x7 frontier seeds
# discovered by the complete partial-automorphism nullspace audit.
#
# The three objectives are intentionally different:
#   * maximum audited source distance (swap I:4<->5, weight 171);
#   * minimum density (shear I:4->1, weight 20, density tied at 3098);
#   * minimum audited subset weight above the bounded 2/3/4-term engine
#     (shear I:3->5, weight 19).
#
# Re-running this program from the repository root reproduces the files and
# prints the exact generator, subset weight, quotient distances, and density.

use flipfleet_partial_automorphism_nullspace

-> ffpanp_expect(label, condition) (String bool) i64
  if !condition
    << "PARTIAL_AUTOMORPHISM_PUBLISH_FAIL " + label
    exit(1)
  1

-> ffpanp_density(us, vs, ws, rank) (i64[] i64[] i64[] i64) i64
  density = 0 ## i64
  i = 0 ## i64
  while i < rank
    density += ffw_popcount(us[i]) + ffw_popcount(vs[i]) + ffw_popcount(ws[i])
    i += 1
  density

-> ffpanp_emit(label, path, us, vs, ws, rank, n, capacity, workspace, nonce, min_weight, expected_weight, expected_operation, expected_domain, expected_source, expected_target, out_u, out_v, out_w) (String String i64[] i64[] i64[] i64 i64 i64 FFPANWorkspace i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[]) i64
  meta = i64[18]
  started = ccall("__w_clock_ms") ## i64
  found = ffpan_find_elementary_escape(us, vs, ws, rank, n, capacity, nonce, min_weight, workspace, out_u, out_v, out_w, meta) ## i64
  finder_ms = ccall("__w_clock_ms") - started ## i64
  ffpanp_expect(label + " found", found == rank && meta[6] == 1 && meta[15] == 0)
  ffpanp_expect(label + " provenance", meta[7] == expected_weight && meta[8] == expected_operation && meta[9] == expected_domain && meta[10] == expected_source && meta[11] == expected_target)
  ffpanp_expect(label + " quotient", meta[12] > 0 && meta[13] > 0)
  state = i64[ffw_state_size(capacity)]
  loaded = ffw_init_terms_cap(state, out_u, out_v, out_w, found, n, capacity, 910001 + nonce, 0, 1, 1, 1) ## i64
  ffpanp_expect(label + " exhaustive gate", loaded == found && ffw_verify_best_exact(state, n) == 1)
  dumped = ffw_dump_best(state, path) ## i64
  ffpanp_expect(label + " dump", dumped == found)
  density = ffpanp_density(out_u, out_v, out_w, found) ## i64
  << "PARTIAL_AUTOMORPHISM_PUBLISHED objective=" + label + " path=" + path + " rank=" + found.to_s() + " density=" + density.to_s() + " subset_weight=" + meta[7].to_s() + " generator=" + meta[8].to_s() + ":" + meta[9].to_s() + ":" + meta[10].to_s() + ">" + meta[11].to_s() + " source_distance=" + meta[12].to_s() + " global_distance=" + meta[13].to_s() + " operations_scanned=" + meta[0].to_s() + " finder_ms=" + finder_ms.to_s()
  found

n = 7 ## i64
capacity = ffw_default_capacity(n) ## i64
source = i64[ffw_state_size(capacity)]
source_path = "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_global_isotropy_gf2.txt"
rank = ffw_load_scheme_cap(source, source_path, n, capacity, 900001, 0, 1, 1, 1) ## i64
ffpanp_expect("source exact", rank == 247 && ffw_verify_best_exact(source, n) == 1)
us = i64[capacity]
vs = i64[capacity]
ws = i64[capacity]
ffpanp_expect("source export", ffw_export_best(source, us, vs, ws) == rank)
workspace = FFPANWorkspace.new(rank, n, capacity)

far_u = i64[capacity]
far_v = i64[capacity]
far_w = i64[capacity]
far_path = "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_partial_auto_max_distance_gf2.txt"
far_rank = ffpanp_emit("max-distance", far_path, us, vs, ws, rank, n, capacity, workspace, 18, 171, 171, 0, 0, 4, 5, far_u, far_v, far_w) ## i64

dense_u = i64[capacity]
dense_v = i64[capacity]
dense_w = i64[capacity]
dense_path = "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3098_partial_auto_min_density_gf2.txt"
dense_rank = ffpanp_emit("min-density", dense_path, us, vs, ws, rank, n, capacity, workspace, 88, 5, 20, 1, 0, 4, 1, dense_u, dense_v, dense_w) ## i64

light_u = i64[capacity]
light_v = i64[capacity]
light_w = i64[capacity]
light_path = "benchmarks/matmul/metaflip/matmul_7x7_rank247_d3142_partial_auto_min_weight_gf2.txt"
light_rank = ffpanp_emit("min-weight-gt4", light_path, us, vs, ws, rank, n, capacity, workspace, 85, 5, 19, 1, 0, 3, 5, light_u, light_v, light_w) ## i64

ffpanp_expect("three distinct endpoints", ffpan_term_set_distance_unique(far_u, far_v, far_w, far_rank, dense_u, dense_v, dense_w, dense_rank) > 0 && ffpan_term_set_distance_unique(far_u, far_v, far_w, far_rank, light_u, light_v, light_w, light_rank) > 0 && ffpan_term_set_distance_unique(dense_u, dense_v, dense_w, dense_rank, light_u, light_v, light_w, light_rank) > 0)
<< "flipfleet_partial_automorphism_nullspace_publish: three exact quotient-novel endpoints written"
