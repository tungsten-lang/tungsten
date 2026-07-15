use flipfleet_rect_residual_worm

-> ffrrwt_expect(label, condition)
  if condition == 0
    << "FAIL " + label
    exit(1)
  1

n = 2 ## i64
m = 2 ## i64
p = 5 ## i64
source_rank = 18 ## i64
rank = 17 ## i64
capacity = ffr_default_capacity(n, m, p) ## i64
state = i64[ffr_state_size(capacity)]
path = "benchmarks/matmul/metaflip/matmul_2x2x5_rank18_d84_gf2.txt"
loaded = ffr_load_scheme_cap(state, path, n, m, p, capacity, 225001, 4, 8, 1000, 250) ## i64
z = ffrrwt_expect("load exact d84 source", loaded == source_rank && ffr_verify_current_exact(state, n, m, p) == 1) ## i64
source_u = i64[source_rank]
source_v = i64[source_rank]
source_w = i64[source_rank]
exported = ffw_export_current(state, source_u, source_v, source_w) ## i64
z = ffrrwt_expect("export source", exported == source_rank)

# Synthetic planted control: the target is the tensor of the first seventeen
# source terms.  Damage one U bit and require the exact residual machinery to
# recover the planted rank-17 presentation.
truth_u = i64[rank]
truth_v = i64[rank]
truth_w = i64[rank]
z = ffrrw_copy_terms(source_u, source_v, source_w, truth_u, truth_v, truth_w, rank)
target = i64[ffrrw_tensor_words(n, m, p)]
z = ffrrwt_expect("build planted target", ffrrw_build_term_target(truth_u, truth_v, truth_w, rank, n, m, p, target) == target.size())
damaged_u = i64[rank]
damaged_v = i64[rank]
damaged_w = i64[rank]
z = ffrrw_copy_terms(truth_u, truth_v, truth_w, damaged_u, damaged_v, damaged_w, rank)
damaged_u[0] = damaged_u[0] ^ 1
z = ffrrwt_expect("planted damage remains nonzero", damaged_u[0] != 0)
carrier = i64[target.size()]
damaged_weight = ffrrw_build_residual(damaged_u, damaged_v, damaged_w, rank, n, m, p, target, carrier) ## i64
expected_weight = ffw_popcount(damaged_v[0]) * ffw_popcount(damaged_w[0]) ## i64
z = ffrrwt_expect("planted residual exact weight", damaged_weight == expected_weight && damaged_weight > 0)
structure = i64[8]
z = ffrrw_structure(carrier, n, m, p, structure)
z = ffrrwt_expect("rank-one defect flattenings", structure[3] == 1 && structure[4] == 1 && structure[5] == 1)

# Direct apply and undo exercise the incremental S XOR G invariant.
saved = i64[carrier.size()]
z = ffrrw_copy(carrier, saved, carrier.size())
repaired_weight = ffrrw_apply_factor_change(carrier, damaged_u, damaged_v, damaged_w, 0, 0, truth_u[0], n, m, p, damaged_weight) ## i64
z = ffrrwt_expect("incremental planted repair", repaired_weight == 0 && ffrrw_weight(carrier, carrier.size()) == 0)
undo_weight = ffrrw_apply_factor_change(carrier, damaged_u, damaged_v, damaged_w, 0, 0, truth_u[0] ^ 1, n, m, p, repaired_weight) ## i64
z = ffrrwt_expect("incremental undo", undo_weight == damaged_weight && ffrrw_equal(carrier, saved, carrier.size()) == 1)

out_u = i64[rank]
out_v = i64[rank]
out_w = i64[rank]
walk_meta = i64[21]
planted_floor = i64[target.size()]
planted = ffrrw_walk_target(damaged_u, damaged_v, damaged_w, rank, n, m, p, target, 4096, 225101, out_u, out_v, out_w, planted_floor, walk_meta) ## i64
z = ffrrwt_expect("planted worm exact hit", planted == 0 && walk_meta[9] == 1)
check = i64[target.size()]
z = ffrrwt_expect("planted output residual zero", ffrrw_build_residual(out_u, out_v, out_w, rank, n, m, p, target, check) == 0)

# The offline archive entry point must materialize the initial unit-floor term
# state exactly while the legacy walk signature above remains unchanged.
unit_drop = 0 ## i64
while unit_drop < source_rank && ffw_popcount(source_u[unit_drop]) * ffw_popcount(source_v[unit_drop]) * ffw_popcount(source_w[unit_drop]) != 1
  unit_drop += 1
z = ffrrwt_expect("find unit deletion", unit_drop < source_rank)
floor_start_u = i64[rank]
floor_start_v = i64[rank]
floor_start_w = i64[rank]
at = 0 ## i64
i = 0 ## i64
while i < source_rank
  if i != unit_drop
    floor_start_u[at] = source_u[i]
    floor_start_v[at] = source_v[i]
    floor_start_w[at] = source_w[i]
    at += 1
  i += 1
mmt = i64[target.size()]
z = ffrrwt_expect("build real target", ffrrw_build_mmt_target(mmt, n, m, p) == mmt.size())
archive_u = i64[64 * rank]
archive_v = i64[64 * rank]
archive_w = i64[64 * rank]
archive_count = i64[1]
archive_floor = i64[target.size()]
archive_meta = i64[21]
archived_weight = ffrrw_walk_target_floor_states(floor_start_u, floor_start_v, floor_start_w, rank, n, m, p, mmt, 1, 225151, out_u, out_v, out_w, archive_floor, archive_u, archive_v, archive_w, 64, archive_count, archive_meta) ## i64
z = ffrrwt_expect("unit-floor state archived", archived_weight >= 1 && archive_count[0] >= 1 && ffrrw_floor_state_equal(archive_u, archive_v, archive_w, 0, floor_start_u, floor_start_v, floor_start_w, rank) == 1)

# Tight real smoke: all eighteen deletion doors remain exactly seventeen
# nonzero terms, the carrier never beats zero without the independent gate,
# and the weight-one floor is recognized.
real_u = i64[rank]
real_v = i64[rank]
real_w = i64[rank]
real_meta = i64[25]
real_weight = ffrrw_search_rank_minus_one(source_u, source_v, source_w, source_rank, n, m, p, 1800, 225201, real_u, real_v, real_w, real_meta) ## i64
z = ffrrwt_expect("real bounded search valid", real_weight >= 0 && real_meta[0] == 1800 && real_meta[1] == source_rank)
z = ffrrwt_expect("real one-cell floor", real_meta[2] == 1 && real_weight <= real_meta[2])
i = 0 ## i64
while i < rank
  z = ffrrwt_expect("real output nonzero", real_u[i] != 0 && real_v[i] != 0 && real_w[i] != 0)
  i += 1
if real_weight == 0
  z = ffrrwt_expect("real exact hit independently gated", real_meta[18] == 1)

<< "PASS flipfleet rectangular residual worm planted_weight=" + damaged_weight.to_s() + " real_best=" + real_weight.to_s() + " floor_cells=" + real_meta[9].to_s() + " archived_floor_states=" + archive_count[0].to_s()
