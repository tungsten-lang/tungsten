use flipfleet_rank_ladder

-> ffrlt_expect(name, condition)
  if !condition
    << "FAIL " + name
    exit(1)
  1

n = 3 ## i64
capacity = ffw_default_capacity(n) ## i64
state_size = ffw_state_size(capacity) ## i64
origin = i64[state_size]
origin_rank = ffw_init_naive_cap(origin, n, capacity, 7001, 0, 1, 1, 1) ## i64
z = ffrlt_expect("naive origin exact", origin_rank == 27 && ffw_verify_current_exact(origin, n) == 1) ## i64

# Two disjoint explicit splits must measure exactly +2 after parity toggles.
opened = i64[state_size]
identities = i64[18]
open_meta = i64[8]
opened_rank = ffrl_open2(origin, 0, 0, 2, 1, 1, 4, opened, identities, open_meta) ## i64
z = ffrlt_expect("measured +2 opener", opened_rank == 29 && open_meta[0] == 27 && open_meta[1] == 28 && open_meta[2] == 29 && open_meta[3] == 2 && open_meta[7] == 1)
z = ffrlt_expect("opened state full exact", ffw_verify_current_exact(opened, n) == 1)

# Each recorded three-term identity independently reconstructs its parent.
i = 0 ## i64
while i < 2
  offset = i * 9 ## i64
  parent_u = i64[1]
  parent_v = i64[1]
  parent_w = i64[1]
  child_u = i64[2]
  child_v = i64[2]
  child_w = i64[2]
  parent_u[0] = identities[offset]
  parent_v[0] = identities[offset + 1]
  parent_w[0] = identities[offset + 2]
  child_u[0] = identities[offset + 3]
  child_v[0] = identities[offset + 4]
  child_w[0] = identities[offset + 5]
  child_u[1] = identities[offset + 6]
  child_v[1] = identities[offset + 7]
  child_w[1] = identities[offset + 8]
  z = ffrlt_expect("recorded split identity " + i.to_s(), fftc_local_exact(parent_u, parent_v, parent_w, 1, child_u, child_v, child_w, 2) == 1)
  i += 1

forbidden0 = i64[state_size]
forbidden1 = i64[state_size]
f0_rank = ffrl_make_forbidden(opened, identities, 0, forbidden0, 7101) ## i64
f1_rank = ffrl_make_forbidden(opened, identities, 9, forbidden1, 7102) ## i64
z = ffrlt_expect("single reversals exact R+1", f0_rank == 28 && f1_rank == 28 && ffw_verify_current_exact(forbidden0, n) == 1 && ffw_verify_current_exact(forbidden1, n) == 1)
z = ffrlt_expect("single reversals differ", ffrl_same_state(forbidden0, forbidden1) == 0)

stats = i64[32]
z = ffrl_stats_init(stats, origin_rank) ## i64
z = ffrlt_expect("immediate reversal blocked", ffrl_admit_candidate(origin, opened, opened, forbidden0, forbidden0, forbidden1, stats) == 0 && stats[7] == 1)
z = ffrlt_expect("exact origin blocked", ffrl_admit_candidate(origin, opened, forbidden0, origin, forbidden0, forbidden1, stats) == 0 && stats[8] == 1)

# A third exact split is a valid tensor decomposition but illegal during the
# closure phase because it raises debt above the parent and opened ceiling.
opened_u = i64[capacity]
opened_v = i64[capacity]
opened_w = i64[capacity]
z = ffw_export_current(opened, opened_u, opened_v, opened_w) ## i64
third_source = 5 ## i64
third_axis = 2 ## i64
third_part = ffrl_choose_part(opened_u, opened_v, opened_w, opened_rank, third_source, third_axis, 3) ## i64
third_meta = i64[8]
debt_rank = ffe_split_with_part(opened_u, opened_v, opened_w, opened_rank, capacity, third_source, third_axis, third_part, third_meta) ## i64
debt_state = i64[state_size]
debt_loaded = ffw_init_terms_cap(debt_state, opened_u, opened_v, opened_w, debt_rank, n, capacity, 7201, 0, 1, 1, 1) ## i64
z = ffrlt_expect("third split exact", debt_rank == 30 && debt_loaded == 30 && ffw_verify_current_exact(debt_state, n) == 1)
z = ffrlt_expect("further debt blocked", ffrl_admit_candidate(origin, opened, opened, debt_state, forbidden0, forbidden1, stats) == 0 && stats[6] == 1)

# The admission gate must independently reject an inexact current view.
bad = i64[state_size]
z = ffrl_clone_state(opened, bad, 7301) ## i64
bad_slot = bad[bad[50]] ## i64
bad[bad[44] + bad_slot] = bad[bad[44] + bad_slot] ^ 256
z = ffrlt_expect("inexact candidate blocked", ffrl_admit_candidate(origin, opened, opened, bad, forbidden0, forbidden1, stats) == 0 && stats[10] == 1)

# A same-rank exact flip is a genuine frontier return and must be credited as
# novel rather than mistaken for the blocked origin.
novel_u = i64[capacity]
novel_v = i64[capacity]
novel_w = i64[capacity]
z = ffw_export_current(origin, novel_u, novel_v, novel_w) ## i64
z = ffrlt_expect("planted neutral flip", fftc_apply_flip(novel_u, novel_v, novel_w, origin_rank, 0, 1, 2) == 1)
novel = i64[state_size]
novel_rank = ffw_init_terms_cap(novel, novel_u, novel_v, novel_w, origin_rank, n, capacity, 7401, 0, 1, 1, 1) ## i64
z = ffrlt_expect("novel return exact", novel_rank == origin_rank && ffw_verify_current_exact(novel, n) == 1 && ffrl_distance(origin, novel) > 0)
z = ffrlt_expect("novel return admitted", ffrl_admit_candidate(origin, opened, forbidden0, novel, forbidden0, forbidden1, stats) == 1 && stats[11] == 1 && stats[12] == 1 && stats[13] == 0)

# Actual debt is measured, not inferred from calling the split API.  Splitting
# one child with its sibling as `part` cancels both children and restores the
# parent, so this proposed first opener is -1 and must be rejected.
base_u = i64[capacity]
base_v = i64[capacity]
base_w = i64[capacity]
z = ffw_export_current(origin, base_u, base_v, base_w) ## i64
one_meta = i64[8]
split_rank = ffe_split_with_part(base_u, base_v, base_w, origin_rank, capacity, 0, 0, 2, one_meta) ## i64
split_origin = i64[state_size]
split_loaded = ffw_init_terms_cap(split_origin, base_u, base_v, base_w, split_rank, n, capacity, 7501, 0, 1, 1, 1) ## i64
z = ffrlt_expect("collision fixture exact", split_loaded == 28 && ffw_verify_current_exact(split_origin, n) == 1)
split_u = i64[capacity]
split_v = i64[capacity]
split_w = i64[capacity]
z = ffw_export_current(split_origin, split_u, split_v, split_w) ## i64
child_position = ffrl_find_term(split_u, split_v, split_w, split_rank, 2, 1, 1) ## i64
other_position = 0 ## i64
if other_position == child_position
  other_position = 1
other_part = ffrl_choose_part(split_u, split_v, split_w, split_rank, other_position, 1, 0) ## i64
collision_out = i64[state_size]
collision_ids = i64[18]
collision_meta = i64[8]
collision_open = ffrl_open2(split_origin, child_position, 0, 3, other_position, 1, other_part, collision_out, collision_ids, collision_meta) ## i64
z = ffrlt_expect("parity collision rejects nominal opener", collision_open == 0 && collision_meta[1] == 27 && collision_meta[3] == -1)

# Small end-to-end smoke: all successful output remains exact and no closing
# edge is allowed to increase rank.  A return is optional in this tiny budget.
run_best = i64[state_size]
run_stats = i64[32]
run_rank = ffrl_run_k2(origin, 2, 2, 4, 8, 2, 0, 1, 0, run_best, run_stats) ## i64
z = ffrlt_expect("end-to-end opens", run_stats[0] == 2 && run_stats[1] > 0)
z = ffrlt_expect("end-to-end no debt edge", run_stats[6] == 0)
if run_rank > 0
  z = ffrlt_expect("end-to-end returned exact", run_rank <= origin_rank && ffw_verify_current_exact(run_best, n) == 1 && ffrl_same_state(origin, run_best) == 0)

<< "rank ladder test: opens=" + run_stats[1].to_s() + " proposals=" + run_stats[4].to_s() + " accepted=" + run_stats[5].to_s() + " returns=" + run_stats[11].to_s() + " novel=" + run_stats[12].to_s()
<< "flipfleet_rank_ladder_test: all checks passed"
