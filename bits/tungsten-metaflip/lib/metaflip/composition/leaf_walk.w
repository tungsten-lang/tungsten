# Replay a bounded native continuation of a verified projected 2x4x4 seed.
# This cold construction does not widen the live campaign/GPU allowlist.
use ../fleet/refinement_artifacts

-> ffbc_walk_leaf4(root, work, capacity, rank, parity) (String i64[] i64 i64 i64[]) i64
  if rank != 27 || ffrf_exact(work, capacity, rank, 2, 4, 4, parity) != 1
    return 0-1
  z = ffrf_sort(work, capacity, rank) ## i64
  cap = ffr_default_capacity(2, 4, 4) ## i64
  state = i64[ffr_state_size(cap)]
  if ffw_prepare(state, 2, cap, 19, 8, 4, 1000, 500) != 1
    return 0-1
  state[3] = ffr_pack_shape(2, 4, 4)
  current = 0 ## i64
  i = 0 ## i64
  while i < rank
    current = ffw_toggle(state, work[i], work[capacity+i], work[2*capacity+i], current)
    i += 1
  state[6] = current
  z = ffw_copy_current_to_best(state)
  state[10] = 2
  state[40] = 2
  # Trial four of the independently audited scout, truncated to eight chunks.
  # Observe current states, just as bud_parent_walk does (not an RNG proxy).
  best_rank = rank ## i64
  best_bits = 1000000 ## i64
  chunk = 0 ## i64
  while chunk < 8
    state[13] = chunk*65536
    z = ffw_seed_rng(state, 19+4*104729+chunk*8191)
    step = 0 ## i64
    while step < 16
      if File.exists?(root + "/stop")
        return 0-1
      z = ffr_wander(state, 4096)
      current = state[6]
      bits = ffr_current_bits(state) ## i64
      if current < best_rank || (current == best_rank && bits < best_bits)
        best_rank = current
        best_bits = bits
        i = 0
        while i < current
          slot = state[state[50]+i] ## i64
          work[i] = state[state[44]+slot]
          work[capacity+i] = state[state[45]+slot]
          work[2*capacity+i] = state[state[46]+slot]
          i += 1
        if ffrf_exact(work, capacity, current, 2, 4, 4, parity) != 1
          return 0-1
      step += 1
    chunk += 1
  if best_rank != 26
    return 0-1
  best_rank
