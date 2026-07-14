# Bounded MAP-Elites archive for exact FlipFleet states.

use metaflip_worker
use flipfleet_escape
use flipfleet_bank_policy
use flipfleet_basin_identity

-> ffme_descriptor(state, frontier_rank, n) (i64[] i64 i64) i64
  rank = ffw_best_rank(state) ## i64
  debt = rank - frontier_rank ## i64
  if debt < 0
    debt = 0
  if debt > 3
    debt = 3
  bits_per_term = 0 ## i64
  if rank > 0
    bits_per_term = ffw_best_bits(state) / rank
  density_bin = bits_per_term / 3 ## i64
  if density_bin > 31
    density_bin = 31
  pairs = ffbp_flip_pairs(state) ## i64
  connectivity_bin = 0 ## i64
  if rank > 0
    connectivity_bin = pairs / rank
  if connectivity_bin > 31
    connectivity_bin = 31
  symmetry = ffbi_state_is_c3(state, n, 0) ## i64
  # Canonical orbit ID prevents a cyclic/reflected/reversed copy from
  # occupying a second MAP niche under a merely relabeled signature.
  structure = ffbi_best_id(state) % 23 ## i64
  debt * 1000000 + symmetry * 500000 + density_bin * 10000 + connectivity_bin * 100 + structure

-> ffme_find(keys, key) i64
  i = 0 ## i64
  while i < keys.size()
    if keys[i] == key
      return i
    i += 1
  0 - 1

-> ffme_admission_action(states, keys, uses, candidate, key, capacity) i64
  if capacity < 1
    return 0
  existing = ffme_find(keys, key) ## i64
  if existing >= 0
    better = 0 ## i64
    if ffw_best_rank(candidate) < ffw_best_rank(states[existing])
      better = 1
    if ffw_best_rank(candidate) == ffw_best_rank(states[existing])
      if ffw_best_bits(candidate) < ffw_best_bits(states[existing])
        better = 1
      if ffw_best_bits(candidate) == ffw_best_bits(states[existing])
        if ffbp_flip_pairs(candidate) > ffbp_flip_pairs(states[existing])
          better = 1
    if better == 1
      return existing + 2
    return 0
  if states.size() < capacity
    return 1
  # Sacrifice the most-used, densest elite; protected rare niches therefore
  # survive ordinary leader churn.
  victim = 0 ## i64
  i = 1 ## i64
  while i < states.size()
    if uses[i] > uses[victim]
      victim = i
    if uses[i] == uses[victim] && ffw_best_bits(states[i]) > ffw_best_bits(states[victim])
      victim = i
    i += 1
  victim + 2

-> ffme_commit_reference(states, keys, uses, sources, candidate, key, action, source) i64
  if action == 1
    states.push(candidate)
    keys.push(key)
    uses.push(0)
    sources.push(source)
    return 1
  if action >= 2
    slot = action - 2 ## i64
    states[slot] = candidate
    keys[slot] = key
    uses[slot] = 0
    sources[slot] = source
    return 2
  0

-> ffme_add(states, keys, uses, sources, candidate, frontier_rank, n, capacity, source)
  key = ffme_descriptor(candidate, frontier_rank, n) ## i64
  action = ffme_admission_action(states, keys, uses, candidate, key, capacity) ## i64
  ffme_commit_reference(states, keys, uses, sources, candidate, key, action, source)

# Coordinator-owned MAP storage. Appends allocate at most `capacity` states;
# replacements reseed an existing slot in place. This lets a live CPU state or
# reusable GPU input buffer resume mutation immediately after admission.
-> ffme_add_copy(states, keys, uses, sources, candidate, frontier_rank, n, capacity, source, state_size, seed)
  key = ffme_descriptor(candidate, frontier_rank, n) ## i64
  action = ffme_admission_action(states, keys, uses, candidate, key, capacity) ## i64
  if action == 0
    return 0
  if action == 1
    stored = i64[state_size]
    loaded = ffw_reseed_from(stored, candidate, seed) ## i64
    if loaded < 1
      return 0
    states.push(stored)
    keys.push(key)
    uses.push(0)
    sources.push(source)
    return 1
  slot = action - 2 ## i64
  loaded = ffw_reseed_from(states[slot], candidate, seed) ## i64
  if loaded < 1
    return 0
  keys[slot] = key
  uses[slot] = 0
  sources[slot] = source
  2

-> ffme_select(states, uses, epoch) i64
  if states.size() == 0
    return 0 - 1
  start = epoch % states.size() ## i64
  best = start ## i64
  offset = 1 ## i64
  while offset < states.size()
    index = (start + offset) % states.size() ## i64
    if uses[index] < uses[best]
      best = index
    offset += 1
  uses[best] = uses[best] + 1
  best
