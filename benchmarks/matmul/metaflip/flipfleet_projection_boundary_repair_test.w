use flipfleet_projection_boundary_repair

-> ffpbrt_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

# A canonical exact 3x3x2 scheme for roundtrip and planted repair controls.
n = 3 ## i64
m = 3 ## i64
p = 2 ## i64
capacity = 128 ## i64
rect_u = i64[capacity]
rect_v = i64[capacity]
rect_w = i64[capacity]
rect_rank = 0 ## i64
i = 0 ## i64
while i < n
  k = 0 ## i64
  while k < m
    j = 0 ## i64
    while j < p
      rect_u[rect_rank] = 1 << (i * m + k)
      rect_v[rect_rank] = 1 << (k * p + j)
      rect_w[rect_rank] = 1 << (i * p + j)
      rect_rank += 1
      j += 1
    k += 1
  i += 1
z = ffpbrt_expect("rectangular naive exact", rect_rank == 18 && ffpbr_verify_exact(rect_u, rect_v, rect_w, rect_rank, n, m, p) == 1) ## i64
round_u = i64[capacity]
round_v = i64[capacity]
round_w = i64[capacity]
round_rank = ffpbr_embed_project_roundtrip(rect_u, rect_v, rect_w, rect_rank, n, m, p, 4, round_u, round_v, round_w, capacity) ## i64
z = ffpbrt_expect("zero-pad/project roundtrip", round_rank == rect_rank && ffpbr_same_term_sets(rect_u, rect_v, rect_w, rect_rank, round_u, round_v, round_w, round_rank) == 1)

# Plant a one-axis split in the projected rectangular scheme.  Mark the two
# split terms and an unrelated carrier as boundary; complete 3->2 span MITM
# must recover an exact rank-18 scheme.
shoulder_u = i64[capacity]
shoulder_v = i64[capacity]
shoulder_w = i64[capacity]
original_u = rect_u[0] ## i64
original_v = rect_v[0] ## i64
original_w = rect_w[0] ## i64
shoulder_rank = 0 ## i64
i = 1
while i < rect_rank
  shoulder_u[shoulder_rank] = rect_u[i]
  shoulder_v[shoulder_rank] = rect_v[i]
  shoulder_w[shoulder_rank] = rect_w[i]
  shoulder_rank += 1
  i += 1
split_a = shoulder_rank ## i64
shoulder_u[shoulder_rank] = original_u
shoulder_v[shoulder_rank] = original_v
shoulder_w[shoulder_rank] = original_w ^ 2
shoulder_rank += 1
split_b = shoulder_rank ## i64
shoulder_u[shoulder_rank] = original_u
shoulder_v[shoulder_rank] = original_v
shoulder_w[shoulder_rank] = 2
shoulder_rank += 1
z = ffpbrt_expect("planted projected shoulder exact", shoulder_rank == 19 && ffpbr_verify_exact(shoulder_u, shoulder_v, shoulder_w, shoulder_rank, n, m, p) == 1)
flags = i64[capacity]
selected = i64[4]
selected[0] = split_a
selected[1] = split_b
selected[2] = 0
flags[split_a] = 1
flags[split_b] = 1
flags[0] = 1
repair_u = i64[capacity]
repair_v = i64[capacity]
repair_w = i64[capacity]
repair_meta = i64[8]
repaired = ffpbr_repair_boundary(shoulder_u, shoulder_v, shoulder_w, shoulder_rank, n, m, p, flags, selected, 3, repair_u, repair_v, repair_w, capacity, repair_meta) ## i64
z = ffpbrt_expect("planted cheaper boundary repair", repaired == 18 && repair_meta[6] == 1 && repair_meta[7] == 1 && ffpbr_verify_exact(repair_u, repair_v, repair_w, repaired, n, m, p) == 1)

# Malformed boundary selection is rejected without changing the exact output.
flags[0] = 0
rollback_u = i64[capacity]
rollback_v = i64[capacity]
rollback_w = i64[capacity]
rollback_meta = i64[8]
rolled = ffpbr_repair_boundary(shoulder_u, shoulder_v, shoulder_w, shoulder_rank, n, m, p, flags, selected, 3, rollback_u, rollback_v, rollback_w, capacity, rollback_meta) ## i64
z = ffpbrt_expect("malformed boundary rolls back", rolled == shoulder_rank && ffpbr_same_term_sets(shoulder_u, shoulder_v, shoulder_w, shoulder_rank, rollback_u, rollback_v, rollback_w, rolled) == 1 && ffpbr_verify_exact(rollback_u, rollback_v, rollback_w, rolled, n, m, p) == 1)

# Load a real checked-in rank-47 <4,4,4> certificate, project J from four to
# three, and independently validate both the complete 4x4x3 tensor and the
# explicit core-residual == boundary identity.
square = 4 ## i64
source_capacity = ffw_default_capacity(square) ## i64
source_state = i64[ffw_state_size(source_capacity)]
source_rank = ffw_load_scheme_cap(source_state, "benchmarks/matmul/metaflip/records/444/at_f2.txt", square, source_capacity, 7401, 4, 2, 1000, 250) ## i64
source_u = i64[source_capacity]
source_v = i64[source_capacity]
source_w = i64[source_capacity]
exported = ffw_export_current(source_state, source_u, source_v, source_w) ## i64
z = ffpbrt_expect("real rank-47 source exact", source_rank == 47 && exported == 47 && ffw_verify_current_exact(source_state, square) == 1)
core_u = i64[source_capacity]
core_v = i64[source_capacity]
core_w = i64[source_capacity]
boundary_u = i64[source_capacity]
boundary_v = i64[source_capacity]
boundary_w = i64[source_capacity]
projected_u = i64[source_capacity]
projected_v = i64[source_capacity]
projected_w = i64[source_capacity]
project_meta = i64[8]
projected_rank = ffpbr_project_square(source_u, source_v, source_w, source_rank, square, 4, 4, 3, core_u, core_v, core_w, boundary_u, boundary_v, boundary_w, projected_u, projected_v, projected_w, source_capacity, project_meta) ## i64
z = ffpbrt_expect("real square->rect projection exact", projected_rank > 0 && projected_rank <= source_rank && project_meta[6] == 1 && ffpbr_verify_exact(projected_u, projected_v, projected_w, projected_rank, 4, 4, 3) == 1)
z = ffpbrt_expect("explicit boundary equals core residual", project_meta[1] > 0 && ffpbr_boundary_matches_residual(core_u, core_v, core_w, project_meta[0], boundary_u, boundary_v, boundary_w, project_meta[1], 4, 4, 3) == 1)

# A malformed source tensor cannot borrow validity from projection: the source
# full gate runs before coordinate restriction and returns no candidate.
bad_source_u = i64[source_capacity]
bad_source_v = i64[source_capacity]
bad_source_w = i64[source_capacity]
i = 0
while i < source_rank
  bad_source_u[i] = source_u[i]
  bad_source_v[i] = source_v[i]
  bad_source_w[i] = source_w[i]
  i += 1
bad_source_u[0] = 0
bad_core_u = i64[source_capacity]
bad_core_v = i64[source_capacity]
bad_core_w = i64[source_capacity]
bad_boundary_u = i64[source_capacity]
bad_boundary_v = i64[source_capacity]
bad_boundary_w = i64[source_capacity]
bad_out_u = i64[source_capacity]
bad_out_v = i64[source_capacity]
bad_out_w = i64[source_capacity]
bad_meta = i64[8]
bad_rank = ffpbr_project_square(bad_source_u, bad_source_v, bad_source_w, source_rank, square, 4, 4, 3, bad_core_u, bad_core_v, bad_core_w, bad_boundary_u, bad_boundary_v, bad_boundary_w, bad_out_u, bad_out_v, bad_out_w, source_capacity, bad_meta) ## i64
z = ffpbrt_expect("malformed source projection rejected", bad_rank == 0 && bad_meta[6] == 0)

<< "PASS flipfleet projection boundary repair rank47->" + projected_rank.to_s() + " core=" + project_meta[0].to_s() + " boundary=" + project_meta[1].to_s()
