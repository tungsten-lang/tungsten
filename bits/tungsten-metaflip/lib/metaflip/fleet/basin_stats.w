use archive

-> ffn_current_term_in(state, u, v, w) (i64[] i64 i64 i64) i64
  # Live states already maintain an exact three-factor hash index. Basin
  # telemetry runs at the status heartbeat, so use it instead of rescanning a
  # peer's complete term set for every term in every island pair.
  if ffw_find_term(state, u, v, w) >= 0
    return 1
  0

# Raw term-set distance between two live working states. Unlike the personal
# best rank shown historically by the TUI, this distinguishes active basins.
-> ffn_current_distance_raw(left, right) (i64[] i64[]) i64
  left_rank = ffw_current_rank(left) ## i64
  right_rank = ffw_current_rank(right) ## i64
  common = 0 ## i64
  i = 0 ## i64
  while i < left_rank
    common += ffn_current_term_in(right, ffw_read_current_u(left, i), ffw_read_current_v(left, i), ffw_read_current_w(left, i))
    i += 1
  left_rank + right_rank - common - common

-> ffn_current_distance(left, right) (i64[] i64[]) i64
  if ffbi_current_id(left) == ffbi_current_id(right)
    return 0
  ffn_current_distance_raw(left, right)

-> ffn_current_to_best_distance(state, best) (i64[] i64[]) i64
  ffn_current_to_best_distance_known_ids(state, best, ffbi_current_id(state), ffbi_best_id(best))

-> ffn_current_to_best_distance_known_ids(state, best, current_id, best_id) (i64[] i64[] i64 i64) i64
  if current_id == best_id
    return 0
  current_rank = ffw_current_rank(state) ## i64
  best_rank = ffw_best_rank(best) ## i64
  common = 0 ## i64
  i = 0 ## i64
  while i < current_rank
    common += ffn_term_in(best, ffw_read_current_u(state, i), ffw_read_current_v(state, i), ffw_read_current_w(state, i))
    i += 1
  current_rank + best_rank - common - common

-> ffn_best_to_current_distance(candidate, active) (i64[] i64[]) i64
  if ffbi_best_id(candidate) == ffbi_current_id(active)
    return 0
  candidate_rank = ffw_best_rank(candidate) ## i64
  active_rank = ffw_current_rank(active) ## i64
  common = 0 ## i64
  i = 0 ## i64
  while i < candidate_rank
    common += ffn_current_term_in(active, ffw_read_best_u(candidate, i), ffw_read_best_v(candidate, i), ffw_read_best_w(candidate, i))
    i += 1
  candidate_rank + active_rank - common - common

# Order-independent digest of the live term set. It is telemetry and a seed
# selection aid, never an exactness or equality proof.
-> ffn_current_basin_id(state) (i64[]) i64
  ffbi_current_id(state)

# Caller-owned snapshot: four summary words, then J current identities and
# J leader distances. Recompute on every call, never cache across mutations.
# The coordinator reads quiescent snapshots, not the workers' private states.
-> ffn_basin_stats_words(count) (i64) i64
  4 + 2 * count

# stats: unique live digests, minimum pair distance, states exactly on the
# fleet leader term set, mean distance from the fleet leader.
-> ffn_active_basin_stats(states, best, stats)
  count = states.size() ## i64
  unique = 0 ## i64
  on_leader = 0 ## i64
  distance_sum = 0 ## i64
  min_distance = 0 - 1 ## i64
  if count > 1
    min_distance = 999999999
  leader_id = ffbi_best_id(best) ## i64
  i = 0 ## i64
  while i < count
    stats[4 + i] = ffbi_current_id(states[i])
    i += 1
  i = 0
  while i < count
    id_i = stats[4 + i] ## i64
    seen = 0 ## i64
    j = 0 ## i64
    while j < i
      id_j = stats[4 + j] ## i64
      pair_distance = 0 ## i64
      if id_i != id_j
        pair_distance = ffn_current_distance_raw(states[i], states[j])
      if pair_distance < min_distance
        min_distance = pair_distance
      if pair_distance == 0
        seen = 1
      j += 1
    if seen == 0
      unique += 1
    distance = ffn_current_to_best_distance_known_ids(states[i], best, id_i, leader_id) ## i64
    stats[4 + count + i] = distance
    if distance == 0
      on_leader += 1
    distance_sum += distance
    i += 1
  stats[0] = unique
  stats[1] = min_distance
  stats[2] = on_leader
  stats[3] = 0
  if count > 0
    stats[3] = distance_sum / count
  unique
