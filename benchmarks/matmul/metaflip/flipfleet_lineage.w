# Delayed GPU -> basin -> CPU descendant attribution.

use metaflip_worker
use flipfleet_basin_identity

-> ffl_gpu_source(role, pool_mode) (i64 i64) i64
  if pool_mode >= 0
    return 1000 + pool_mode
  10 + role

-> ffl_rect_source(component) (i64) i64
  2000 + component

-> ffl_source_role(source) (i64) i64
  if source >= 10 && source <= 20
    return source - 10
  if source >= 1000 && source < 2000
    return 10
  if source >= 2000 && source < 2100
    return 10
  0 - 1

-> ffl_source_pool_mode(source) (i64) i64
  if source >= 1000 && source < 2000
    return source - 1000
  0 - 1

# Find the provenance of a seed even after it has been copied into a shoulder
# bank. Canonical IDs make D3/reversal-equivalent copies retain the lineage.
-> ffl_find_source(seed, map_states, map_sources) i64
  identity = ffbi_best_id(seed) ## i64
  i = map_states.size() - 1 ## i64
  while i >= 0
    if ffbi_best_id(map_states[i]) == identity
      return map_sources[i]
    i -= 1
  0 - 1

-> ffl_registry_find(seed, identities, sources) i64
  identity = ffbi_best_id(seed) ## i64
  i = identities.size() - 1 ## i64
  while i >= 0
    if identities[i] == identity
      return sources[i]
    i -= 1
  0 - 1

-> ffl_registry_add(identities, sources, state, source, capacity) i64
  if ffl_source_role(source) < 0 || capacity < 1
    return 0
  identity = ffbi_best_id(state) ## i64
  i = 0 ## i64
  while i < identities.size()
    if identities[i] == identity
      sources[i] = source
      return 2
    i += 1
  if identities.size() >= capacity
    i = 1
    while i < identities.size()
      identities[i - 1] = identities[i]
      sources[i - 1] = sources[i]
      i += 1
    identities.pop
    sources.pop
  identities.push(identity)
  sources.push(source)
  1

-> ffl_delayed_reward(start_rank, start_bits, end_rank, end_bits, novel_basin) (i64 i64 i64 i64 i64) i64
  reward = 0 ## i64
  if end_rank < start_rank
    reward += (start_rank - end_rank) * 10000
  if end_rank == start_rank && end_bits < start_bits && start_bits > 0
    density = (start_bits - end_bits) * 2000 / start_bits ## i64
    if density < 1
      density = 1
    reward += density
  if novel_basin != 0
    reward += 250
  reward

-> ffl_returned_to_origin(state, origin_identity) (i64[] i64) i64
  returned = 0 ## i64
  if origin_identity > 0 && ffbi_current_id(state) == origin_identity
    returned = 1
  returned
