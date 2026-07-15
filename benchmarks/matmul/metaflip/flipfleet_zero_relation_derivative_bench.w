# Finite-difference localization of archive zero relations.
#
# For a linear factor map g and zero relation Z:
#
#   Delta_g Z = Z XOR g(Z) = 0,
#   Delta_h Delta_g Z = Delta_g Z XOR h(Delta_g Z) = 0.
#
# Stable terms cancel from the first derivative; terms not touched by both
# maps cancel from the second.  We test all support-guided maps over the top
# four relation coordinates and four deterministic support-map h samples per
# first derivative.  Only the best scored candidate is tensor-zero checked,
# materialized, and n^6-gated.
#
# Usage: flipfleet_zero_relation_derivative_bench [only_n=0] [top=4]
#                                                     [h_samples=4]

use flipfleet_zero_relation_image
use flipfleet_profiles
use flipfleet_global_isotropy

-> ffzrid_expect(label, condition) (String bool) i64
  if !condition
    << "ZERO_RELATION_DERIVATIVE_FAIL " + label
    exit(1)
  1

-> ffzrid_copy(source_u, source_v, source_w, target_u, target_v, target_w, count) (i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < count
    target_u[i] = source_u[i]
    target_v[i] = source_v[i]
    target_w[i] = source_w[i]
    i += 1
  count

-> ffzrid_build_maps(z_u, z_v, z_w, z_rank, n, top_count, map_factor, map_operation, map_source, map_target) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  count = 0 ## i64
  factor = 0 ## i64
  while factor < 3
    selected = i64[top_count]
    selected_count = ffzri_top_coordinates(z_u, z_v, z_w, z_rank, factor, n * n, top_count, selected) ## i64
    s = 0 ## i64
    while s < selected_count
      source = selected[s] ## i64
      map_factor[count] = factor
      map_operation[count] = 2
      map_source[count] = source
      map_target[count] = 0
      count += 1
      t = 0 ## i64
      while t < selected_count
        target = selected[t] ## i64
        if target != source
          map_factor[count] = factor
          map_operation[count] = 1
          map_source[count] = source
          map_target[count] = target
          count += 1
          map_factor[count] = factor
          map_operation[count] = 3
          map_source[count] = source
          map_target[count] = target
          count += 1
        t += 1
      s += 1
    factor += 1
  count

# Score and possibly retain one derivative. stats indices:
# 0 first derivatives, 1 second derivatives, 2 first terms, 3 second terms,
# 4 zero images, 5 duplicate cancellations, 6 rank wins, 7 density wins,
# 8 neutral changed, 9 best rank, 10 best density, 11 best distance,
# 12 best order, 13 parent, 14 g map, 15 h map, 16 best relation rank.
-> ffzrid_consider(leader_u, leader_v, leader_w, leader_rank, leader_density, relation_u, relation_v, relation_w, relation_rank, order, parent, g_map, h_map, best_u, best_v, best_w, stats) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  score = i64[4]
  ffzri_score(leader_u, leader_v, leader_w, leader_rank, leader_density, relation_u, relation_v, relation_w, relation_rank, score)
  if order == 1
    stats[0] = stats[0] + 1
    stats[2] = stats[2] + relation_rank
  if order == 2
    stats[1] = stats[1] + 1
    stats[3] = stats[3] + relation_rank
  if score[0] < leader_rank
    stats[6] = stats[6] + 1
  if score[0] == leader_rank && score[1] < leader_density
    stats[7] = stats[7] + 1
  if score[0] == leader_rank && score[2] > 0
    stats[8] = stats[8] + 1
  better = 0 ## i64
  if score[0] < stats[9]
    better = 1
  if score[0] == stats[9] && score[1] < stats[10]
    better = 1
  if score[0] == stats[9] && score[1] == stats[10] && score[2] > stats[11]
    better = 1
  if better == 1
    stats[9] = score[0]
    stats[10] = score[1]
    stats[11] = score[2]
    stats[12] = order
    stats[13] = parent
    stats[14] = g_map
    stats[15] = h_map
    stats[16] = relation_rank
    ffzrid_copy(relation_u, relation_v, relation_w, best_u, best_v, best_w, relation_rank)
  better

-> ffzrid_run(n, top_count, h_samples) (i64 i64 i64) i64
  paths = ffp_frontier_seed_paths(n)
  capacity = ffw_default_capacity(n) ## i64
  leader_state = i64[ffw_state_size(capacity)]
  leader_rank = ffw_load_scheme_cap(leader_state, paths[0], n, capacity, 993001 + n, 0, 1, 1, 1) ## i64
  ffzrid_expect("leader exact", leader_rank == ffp_record(n) && ffw_verify_current_exact(leader_state, n) == 1)
  leader_u = i64[capacity]
  leader_v = i64[capacity]
  leader_w = i64[capacity]
  ffzrid_expect("leader export", ffw_export_current(leader_state, leader_u, leader_v, leader_w) == leader_rank)
  leader_density = ffgir_density(leader_u, leader_v, leader_w, leader_rank) ## i64

  relation_u = i64[capacity * 2]
  relation_v = i64[capacity * 2]
  relation_w = i64[capacity * 2]
  g_image_u = i64[capacity * 2]
  g_image_v = i64[capacity * 2]
  g_image_w = i64[capacity * 2]
  derivative1_u = i64[capacity * 4]
  derivative1_v = i64[capacity * 4]
  derivative1_w = i64[capacity * 4]
  h_image_u = i64[capacity * 4]
  h_image_v = i64[capacity * 4]
  h_image_w = i64[capacity * 4]
  derivative2_u = i64[capacity * 8]
  derivative2_v = i64[capacity * 8]
  derivative2_w = i64[capacity * 8]
  best_u = i64[capacity * 8]
  best_v = i64[capacity * 8]
  best_w = i64[capacity * 8]
  raw_u = i64[capacity * 10]
  raw_v = i64[capacity * 10]
  raw_w = i64[capacity * 10]
  candidate_u = i64[capacity * 10]
  candidate_v = i64[capacity * 10]
  candidate_w = i64[capacity * 10]
  other_u = i64[capacity]
  other_v = i64[capacity]
  other_w = i64[capacity]
  compact_meta = i64[2]
  max_maps = 3 * top_count * (1 + 2 * (top_count - 1)) ## i64
  map_factor = i64[max_maps]
  map_operation = i64[max_maps]
  map_source = i64[max_maps]
  map_target = i64[max_maps]
  stats = i64[20]
  stats[9] = leader_rank
  stats[10] = leader_density
  stats[13] = 0 - 1
  stats[14] = 0 - 1
  stats[15] = 0 - 1
  started = ccall("__w_clock_ms") ## i64

  parent = 1 ## i64
  while parent < paths.size()
    other_state = i64[ffw_state_size(capacity)]
    other_rank = ffw_load_scheme_cap(other_state, paths[parent], n, capacity, 994001 + n * 1009 + parent, 0, 1, 1, 1) ## i64
    ffzrid_expect("parent exact", other_rank == leader_rank && ffw_verify_current_exact(other_state, n) == 1)
    ffzrid_expect("parent export", ffw_export_current(other_state, other_u, other_v, other_w) == other_rank)
    relation_rank = ffzri_relation(leader_u, leader_v, leader_w, leader_rank, other_u, other_v, other_w, other_rank, raw_u, raw_v, raw_w, relation_u, relation_v, relation_w, compact_meta) ## i64
    ffzrid_expect("parent relation zero", relation_rank > 0 && ffzri_zero_tensor(relation_u, relation_v, relation_w, relation_rank, n) == 1)
    map_count = ffzrid_build_maps(relation_u, relation_v, relation_w, relation_rank, n, top_count, map_factor, map_operation, map_source, map_target) ## i64
    g = 0 ## i64
    while g < map_count
      g_rank = ffzri_map_relation(relation_u, relation_v, relation_w, relation_rank, map_factor[g], map_operation[g], map_source[g], map_target[g], raw_u, raw_v, raw_w, g_image_u, g_image_v, g_image_w, compact_meta) ## i64
      stats[4] = stats[4] + compact_meta[0]
      stats[5] = stats[5] + compact_meta[1]
      derivative1_rank = ffzri_relation(relation_u, relation_v, relation_w, relation_rank, g_image_u, g_image_v, g_image_w, g_rank, raw_u, raw_v, raw_w, derivative1_u, derivative1_v, derivative1_w, compact_meta) ## i64
      stats[4] = stats[4] + compact_meta[0]
      stats[5] = stats[5] + compact_meta[1]
      ffzrid_consider(leader_u, leader_v, leader_w, leader_rank, leader_density, derivative1_u, derivative1_v, derivative1_w, derivative1_rank, 1, parent, g, 0 - 1, best_u, best_v, best_w, stats)
      sample = 0 ## i64
      while sample < h_samples && map_count > 1
        h = (g + 1 + sample * (map_count / h_samples + 1)) % map_count ## i64
        if h == g
          h = (h + 1) % map_count
        h_rank = ffzri_map_relation(derivative1_u, derivative1_v, derivative1_w, derivative1_rank, map_factor[h], map_operation[h], map_source[h], map_target[h], raw_u, raw_v, raw_w, h_image_u, h_image_v, h_image_w, compact_meta) ## i64
        stats[4] = stats[4] + compact_meta[0]
        stats[5] = stats[5] + compact_meta[1]
        derivative2_rank = ffzri_relation(derivative1_u, derivative1_v, derivative1_w, derivative1_rank, h_image_u, h_image_v, h_image_w, h_rank, raw_u, raw_v, raw_w, derivative2_u, derivative2_v, derivative2_w, compact_meta) ## i64
        stats[4] = stats[4] + compact_meta[0]
        stats[5] = stats[5] + compact_meta[1]
        ffzrid_consider(leader_u, leader_v, leader_w, leader_rank, leader_density, derivative2_u, derivative2_v, derivative2_w, derivative2_rank, 2, parent, g, h, best_u, best_v, best_w, stats)
        sample += 1
      g += 1
    parent += 1

  candidate_rank = leader_rank ## i64
  if stats[13] >= 0
    candidate_rank = ffzri_toggle_image(leader_u, leader_v, leader_w, leader_rank, best_u, best_v, best_w, stats[16], raw_u, raw_v, raw_w, candidate_u, candidate_v, candidate_w, compact_meta)
  if stats[13] < 0
    ffzrid_copy(leader_u, leader_v, leader_w, candidate_u, candidate_v, candidate_w, leader_rank)
  ffzrid_expect("winner score rank", candidate_rank == stats[9])
  best_zero = 1 ## i64
  if stats[13] >= 0
    best_zero = ffzri_zero_tensor(best_u, best_v, best_w, stats[16], n)
  gate_capacity = capacity ## i64
  if candidate_rank > gate_capacity
    gate_capacity = candidate_rank + 8
  gate = i64[ffw_state_size(gate_capacity)]
  loaded = ffw_init_terms_cap(gate, candidate_u, candidate_v, candidate_w, candidate_rank, n, gate_capacity, 995001 + n, 0, 1, 1, 1) ## i64
  full_exact = 0 ## i64
  if loaded == candidate_rank && ffw_verify_current_exact(gate, n) == 1
    full_exact = 1
  ffzrid_expect("best derivative zero", best_zero == 1)
  ffzrid_expect("winner full gate", full_exact == 1)
  elapsed = ccall("__w_clock_ms") - started ## i64
  objective_win = 0 ## i64
  if stats[9] < leader_rank || (stats[9] == leader_rank && stats[10] < leader_density)
    objective_win = 1
  first_average = 0 ## i64
  second_average = 0 ## i64
  if stats[0] > 0
    first_average = stats[2] * 1000 / stats[0]
  if stats[1] > 0
    second_average = stats[3] * 1000 / stats[1]
  << "ZERO_RELATION_DERIVATIVE_SUMMARY tensor=" + n.to_s() + "x" + n.to_s() + " source=r" + leader_rank.to_s() + "/d" + leader_density.to_s() + " archive=" + paths.size().to_s() + " first=" + stats[0].to_s() + " first_terms_avg_milli=" + first_average.to_s() + " second=" + stats[1].to_s() + " second_terms_avg_milli=" + second_average.to_s() + " zero_terms=" + stats[4].to_s() + " duplicate_cancellations=" + stats[5].to_s() + " rank_wins=" + stats[6].to_s() + " density_wins=" + stats[7].to_s() + " neutral_changed=" + stats[8].to_s() + " best=r" + stats[9].to_s() + "/d" + stats[10].to_s() + " distance=" + stats[11].to_s() + " derivative_order=" + stats[12].to_s() + " relation_rank=" + stats[16].to_s() + " provenance=parent" + stats[13].to_s() + ":g" + stats[14].to_s() + ":h" + stats[15].to_s() + " best_zero=" + best_zero.to_s() + " full_exact=" + full_exact.to_s() + " objective_win=" + objective_win.to_s() + " elapsed_ms=" + elapsed.to_s()
  objective_win

args = argv()
only_n = 0 ## i64
top_count = 4 ## i64
h_samples = 4 ## i64
if args.size() > 0
  only_n = args[0].to_i()
if args.size() > 1
  top_count = args[1].to_i()
if args.size() > 2
  h_samples = args[2].to_i()
ffzrid_expect("arguments", (only_n == 0 || only_n == 6 || only_n == 7) && top_count >= 2 && top_count <= 8 && h_samples >= 1 && h_samples <= 16)
wins = 0 ## i64
n = 6 ## i64
while n <= 7
  if only_n == 0 || only_n == n
    wins += ffzrid_run(n, top_count, h_samples)
  n += 1
<< "flipfleet_zero_relation_derivative_bench: done wins=" + wins.to_s()
