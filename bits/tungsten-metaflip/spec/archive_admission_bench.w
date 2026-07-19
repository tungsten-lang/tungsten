use ../lib/metaflip/fleet/archive

-> archive_bench_exhaustive(archive, candidate, capacity, min_distance) i64
  duplicate = 0 ## i64
  closest = 999999999 ## i64
  i = 0 ## i64
  while i < archive.size()
    distance = ffn_distance(archive[i], candidate) ## i64
    if distance == 0
      duplicate = 1
    if distance < closest
      closest = distance
    i += 1
  if duplicate == 0 && closest >= min_distance && archive.size() >= capacity
    current_min = ffn_archive_min_distance(archive) ## i64
    replace = 0 - 1 ## i64
    best_min = current_min ## i64
    i = 0
    while i < archive.size()
      trial_min = ffn_replacement_min_distance(archive, i, candidate) ## i64
      if trial_min > best_min
        best_min = trial_min
        replace = i
      i += 1
    if replace >= 0
      return replace + 2
  0

root = __DIR__ + "/../lib/metaflip/seeds/gf2/"
paths = []
paths.push("matmul_7x7_rank247_d3096_dynamic_syzygy_gf2.txt")
paths.push("matmul_7x7_rank247_d3096_affine_code_cuda_epoch3306_gf2.txt")
paths.push("matmul_7x7_rank247_d3098_global_isotropy_gf2.txt")
paths.push("matmul_7x7_rank247_d3098_odd_parent3_gf2.txt")
paths.push("matmul_7x7_rank247_d3098_partial_auto_beam_dense_gf2.txt")
paths.push("matmul_7x7_rank247_d3096_partial_auto_beam_far_cuda_epoch1849_gf2.txt")
paths.push("matmul_7x7_rank247_d3098_partial_auto_max_distance_gf2.txt")
paths.push("matmul_7x7_rank247_d3098_partial_auto_min_density_gf2.txt")
paths.push("matmul_7x7_rank247_d3142_partial_auto_min_weight_gf2.txt")
paths.push("matmul_7x7_rank247_d3554_d3_partial_nullspace_s7_gf2.txt")
paths.push("matmul_7x7_rank247_d3554_d3_partial_nullspace_s9_gf2.txt")
paths.push("matmul_7x7_rank247_d3554_outer_isotropy_c013_m7_gf2.txt")
paths.push("matmul_7x7_rank247_d3554_outer_isotropy_c021_m4_gf2.txt")
paths.push("matmul_7x7_rank247_d3554_outer_isotropy_c024_m0_gf2.txt")
paths.push("matmul_7x7_rank247_d3554_outer_isotropy_gf2.txt")
paths.push("matmul_7x7_rank248_d2952_sedoglavic_gf2.txt")
paths.push("matmul_7x7_rank248_d2958_sedoglavic_gf2.txt")
paths.push("matmul_7x7_rank248_d2967_leaf_canonical_gf2.txt")
paths.push("matmul_7x7_rank248_d3015_connectivity_sedoglavic_gf2.txt")

unique = []
ids = []
i = 0 ## i64
while i < paths.size()
  state = i64[ffw_state_size(320)]
  loaded = ffw_load_scheme_cap(state, root + paths[i], 7, 320, 7001 + i, 0, 1, 1, 1) ## i64
  if loaded < 247 || loaded > 248 || ffw_verify_best_exact(state, 7) == 0
    << "FAIL archive benchmark load " + paths[i]
    exit(1)
  identity = ffbi_best_id(state) ## i64
  seen = 0 ## i64
  j = 0 ## i64
  while j < ids.size()
    if ids[j] == identity
      seen = 1
    j += 1
  if seen == 0
    unique.push(state)
    ids.push(identity)
  i += 1

if unique.size() < 17
  << "FAIL archive benchmark needs 17 distinct real 7x7 basin identities, got " + unique.size().to_s()
  exit(1)

archive = []
i = 0
while i < 16
  archive.push(unique[i])
  i += 1
candidate = unique[16]

# Warm both paths, then time one full rejection/admission decision each. The
# candidate has a distinct basin identity, so both execute their replacement
# scans rather than taking the duplicate fast rejection.
warm_new = ffn_archive_admission_action(archive, candidate, 16, 0) ## i64
started = ccall_nobox("__w_clock_ns_raw") ## i64
old_action = archive_bench_exhaustive(archive, candidate, 16, 0) ## i64
old_ns = ccall_nobox("__w_clock_ns_raw") - started ## i64
started = ccall_nobox("__w_clock_ns_raw")
new_action = ffn_archive_admission_action(archive, candidate, 16, 0) ## i64
new_ns = ccall_nobox("__w_clock_ns_raw") - started ## i64

if old_action != new_action || warm_new != new_action
  << "FAIL archive benchmark semantic mismatch old=" + old_action.to_s() + " new=" + new_action.to_s()
  exit(1)
if old_ns < 1
  old_ns = 1
if new_ns < 1
  new_ns = 1

speedup_milli = old_ns * 1000 / new_ns ## i64
<< "ARCHIVE_ADMISSION_BENCH tensor=7x7 archive=16 exhaustive_distance_calls=2056 bounded_distance_calls=256 old_ns=" + old_ns.to_s() + " new_ns=" + new_ns.to_s() + " speedup_milli=" + speedup_milli.to_s() + " action=" + new_action.to_s()
