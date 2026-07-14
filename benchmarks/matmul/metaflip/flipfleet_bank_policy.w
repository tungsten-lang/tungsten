# Native structural-diversity and Pareto policies for FlipFleet.
#
# This is the pure-Tungsten counterpart of the useful runtime policy from the
# historical Python coordinator: shoulder banks enforce factor-reuse-family
# quotas and least-used replay, while the GPU novelty bank is genuinely
# nondominated over density, ordinary-flip connectivity, and term-set novelty.

use metaflip_worker
use flipfleet_basin_identity

-> ffbp_term_in(state, u, v, w) (i64[] i64 i64 i64) i64
  found = 0 ## i64
  rank = ffw_best_rank(state) ## i64
  i = 0 ## i64
  while i < rank
    if ffw_read_best_u(state, i) == u && ffw_read_best_v(state, i) == v && ffw_read_best_w(state, i) == w
      found = 1
      i = rank
    else
      i += 1
  found

-> ffbp_distance(left, right) (i64[] i64[]) i64
  if ffbi_best_id(left) == ffbi_best_id(right)
    return 0
  left_rank = ffw_best_rank(left) ## i64
  right_rank = ffw_best_rank(right) ## i64
  common = 0 ## i64
  i = 0 ## i64
  while i < left_rank
    common += ffbp_term_in(right, ffw_read_best_u(left, i), ffw_read_best_v(left, i), ffw_read_best_w(left, i))
    i += 1
  left_rank + right_rank - common - common

-> ffbp_min_distance(items)
  result = 0 - 1 ## i64
  if items.size() > 1
    result = 999999999
    i = 0 ## i64
    while i < items.size()
      j = i + 1 ## i64
      while j < items.size()
        distance = ffbp_distance(items[i], items[j]) ## i64
        if distance < result
          result = distance
        j += 1
      i += 1
  result

-> ffbp_replacement_min_distance(items, replace, candidate)
  result = 0 - 1 ## i64
  if items.size() > 1
    result = 999999999
    i = 0 ## i64
    while i < items.size()
      left = items[i]
      if i == replace
        left = candidate
      j = i + 1 ## i64
      while j < items.size()
        right = items[j]
        if j == replace
          right = candidate
        distance = ffbp_distance(left, right) ## i64
        if distance < result
          result = distance
        j += 1
      i += 1
  result

-> ffbp_flip_pairs(state) (i64[]) i64
  pairs = 0 ## i64
  rank = ffw_best_rank(state) ## i64
  left = 0 ## i64
  while left < rank
    right = left + 1 ## i64
    while right < rank
      if ffw_read_best_u(state, left) == ffw_read_best_u(state, right)
        pairs += 1
      if ffw_read_best_v(state, left) == ffw_read_best_v(state, right)
        pairs += 1
      if ffw_read_best_w(state, left) == ffw_read_best_w(state, right)
        pairs += 1
      right += 1
    left += 1
  pairs

# Hash the three descending multisets of factor-bucket sizes.  Factor labels do
# not enter the hash, so coordinate relabelings with the same ordinary-flip
# connectivity share a structural family.  Collisions only make the quota more
# conservative; exactness and novelty are gated separately.
-> ffbp_structural_signature_scratch(state, values, counts, axis_signatures) (i64[] i64[] i64[] i64[]) i64
  rank = ffw_best_rank(state) ## i64
  axis = 0 ## i64
  while axis < 3
    unique = 0 ## i64
    i = 0 ## i64
    while i < rank
      value = ffw_read_best_u(state, i) ## i64
      if axis == 1
        value = ffw_read_best_v(state, i)
      if axis == 2
        value = ffw_read_best_w(state, i)
      found = 0 - 1 ## i64
      j = 0 ## i64
      while j < unique
        if values[j] == value
          found = j
          j = unique
        else
          j += 1
      if found < 0
        values[unique] = value
        counts[unique] = 1
        unique += 1
      else
        counts[found] = counts[found] + 1
      i += 1
    i = 1
    while i < unique
      count = counts[i] ## i64
      j = i ## i64
      while j > 0 && counts[j - 1] < count
        counts[j] = counts[j - 1]
        j -= 1
      counts[j] = count
      i += 1
    signature = (17 * 1000003 + unique) % 2147483647 ## i64
    i = 0
    while i < unique
      signature = (signature * 1000003 + counts[i]) % 2147483647
      i += 1
    axis_signatures[axis] = signature
    axis += 1
  i = 1
  while i < 3
    value = axis_signatures[i] ## i64
    j = i ## i64
    while j > 0 && axis_signatures[j - 1] > value
      axis_signatures[j] = axis_signatures[j - 1]
      j -= 1
    axis_signatures[j] = value
    i += 1
  signature = 17 ## i64
  axis = 0
  while axis < 3
    signature = (signature * 1000003 + axis_signatures[axis]) % 2147483647
    axis += 1
  signature

# Prefer ffbp_structural_signature_scratch with caller-owned buffers.  This
# fallback still allocates once per call and is only safe on cold paths; hot
# admission must use scratch (see ffn_near_add_if_admitted).
-> ffbp_structural_signature(state) (i64[]) i64
  rank = ffw_best_rank(state) ## i64
  if rank < 1
    rank = 1
  values = i64[rank]
  counts = i64[rank]
  axis_signatures = i64[3]
  ffbp_structural_signature_scratch(state, values, counts, axis_signatures)

-> ffbp_remove_at(items, index)
  i = index ## i64
  while i + 1 < items.size()
    items[i] = items[i + 1]
    i += 1
  z = items.pop
  1

-> ffbp_nearest_for(items, index) i64
  nearest = 999999999 ## i64
  if items.size() <= 1
    return nearest
  i = 0 ## i64
  while i < items.size()
    if i != index
      distance = ffbp_distance(items[index], items[i]) ## i64
      if distance < nearest
        nearest = distance
    i += 1
  nearest

# Return 0 for rejection, 1 for append, or victim+2 for replacement. Counters:
# admitted, evicted, novelty-rejected, duplicate, signature-rejected.
-> ffbp_near_admission_action(bank, signatures, candidate, capacity, signature_quota, min_distance, counters, signature) i64
  if capacity < 1 || signature_quota < 1
    counters[2] = counters[2] + 1
    return 0
  closest = 999999999 ## i64
  signature_count = 0 ## i64
  i = 0 ## i64
  while i < bank.size()
    distance = ffbp_distance(bank[i], candidate) ## i64
    if distance == 0
      counters[3] = counters[3] + 1
      return 0
    if distance < closest
      closest = distance
    if signatures[i] == signature
      signature_count += 1
    i += 1

  if bank.size() < capacity && signature_count < signature_quota && closest >= min_distance
    return 1

  victim = 0 - 1 ## i64
  if signature_count >= signature_quota
    worst_nearest = 999999999 ## i64
    worst_bits = 0 - 1 ## i64
    i = 0
    while i < bank.size()
      if signatures[i] == signature
        nearest = ffbp_nearest_for(bank, i) ## i64
        bits = ffw_best_bits(bank[i]) ## i64
        if nearest < worst_nearest || (nearest == worst_nearest && bits > worst_bits)
          victim = i
          worst_nearest = nearest
          worst_bits = bits
      i += 1
  else
    if bank.size() >= capacity
      closest_distance = 999999999 ## i64
      left_victim = 0 - 1 ## i64
      right_victim = 0 - 1 ## i64
      left = 0 ## i64
      while left < bank.size()
        right = left + 1 ## i64
        while right < bank.size()
          distance = ffbp_distance(bank[left], bank[right]) ## i64
          if distance < closest_distance
            closest_distance = distance
            left_victim = left
            right_victim = right
          right += 1
        left += 1
      victim = left_victim
      if right_victim >= 0
        if ffw_best_bits(bank[right_victim]) > ffw_best_bits(bank[left_victim])
          victim = right_victim

  if victim < 0
    if signature_count >= signature_quota
      counters[4] = counters[4] + 1
    else
      counters[2] = counters[2] + 1
    return 0

  current_min = ffbp_min_distance(bank) ## i64
  trial_min = ffbp_replacement_min_distance(bank, victim, candidate) ## i64
  improves = 0 ## i64
  if trial_min > current_min && closest >= min_distance
    improves = 1
  if trial_min == current_min && closest >= min_distance
    if ffw_best_bits(candidate) < ffw_best_bits(bank[victim])
      improves = 1
  if improves == 0
    if signature_count >= signature_quota
      counters[4] = counters[4] + 1
    else
      counters[2] = counters[2] + 1
    return 0

  victim + 2

-> ffbp_near_commit(bank, signatures, uses, successes, candidate, signature, action, counters) i64
  if action == 1
    bank.push(candidate)
    signatures.push(signature)
    uses.push(0)
    successes.push(0)
    counters[0] = counters[0] + 1
    return 1
  if action >= 2
    # Reseed into the victim so the previous full state is not orphaned under
    # the campaign-lifetime allocator (reference overwrite was an OOM path).
    victim = action - 2 ## i64
    if victim < 0 || victim >= bank.size()
      return 0
    loaded = ffw_reseed_from(bank[victim], candidate, 1) ## i64
    if loaded < 1
      # Fallback only when layouts are incompatible: keep prior behavior.
      bank[victim] = candidate
    signatures[victim] = signature
    uses[victim] = 0
    successes[victim] = 0
    counters[0] = counters[0] + 1
    counters[1] = counters[1] + 1
    return 1
  0

# Scratch form: no per-call signature allocations.  values/counts need at least
# ffw_best_rank(candidate) slots; axis_signatures needs 3.
-> ffbp_near_add_scratch(bank, signatures, uses, successes, candidate, capacity, signature_quota, min_distance, counters, values, counts, axis_signatures)
  signature = ffbp_structural_signature_scratch(candidate, values, counts, axis_signatures) ## i64
  action = ffbp_near_admission_action(bank, signatures, candidate, capacity, signature_quota, min_distance, counters, signature) ## i64
  ffbp_near_commit(bank, signatures, uses, successes, candidate, signature, action, counters)

-> ffbp_near_add(bank, signatures, uses, successes, candidate, capacity, signature_quota, min_distance, counters)
  # Cold-path wrapper.  Allocates rank-sized scratch once; prefer
  # ffbp_near_add_scratch on the campaign hot path.
  rank = ffw_best_rank(candidate) ## i64
  if rank < 1
    rank = 1
  values = i64[rank]
  counts = i64[rank]
  axis_signatures = i64[3]
  ffbp_near_add_scratch(bank, signatures, uses, successes, candidate, capacity, signature_quota, min_distance, counters, values, counts, axis_signatures)

-> ffbp_select_least_used(bank, uses, stable_key) i64
  if bank.size() == 0
    return 0 - 1
  start = stable_key % bank.size() ## i64
  best = start ## i64
  offset = 1 ## i64
  while offset < bank.size()
    index = (start + offset) % bank.size() ## i64
    if uses[index] < uses[best]
      best = index
    offset += 1
  uses[best] = uses[best] + 1
  best

-> ffbp_mark_success(bank, successes, seed) i64
  if seed == nil
    return 0
  i = 0 ## i64
  while i < bank.size()
    if ffbp_distance(bank[i], seed) == 0
      successes[i] = successes[i] + 1
      return 1
    i += 1
  0

-> ffbp_find_state(states, candidate) i64
  i = 0 ## i64
  while i < states.size()
    if ffbp_distance(states[i], candidate) == 0
      return i
    i += 1
  0 - 1

-> ffbp_dominates(left_bits, left_pairs, left_novelty, right_bits, right_pairs, right_novelty) (i64 i64 i64 i64 i64 i64) i64
  no_worse = 0 ## i64
  if left_bits <= right_bits && left_pairs >= right_pairs && left_novelty >= right_novelty
    no_worse = 1
  strict = 0 ## i64
  if left_bits < right_bits || left_pairs > right_pairs || left_novelty > right_novelty
    strict = 1
  no_worse * strict

-> ffbp_pareto_remove(states, ranks, bits, pairs, novelties, roles, uses, index)
  z = ffbp_remove_at(states, index) ## i64
  z = ffbp_remove_at(ranks, index)
  z = ffbp_remove_at(bits, index)
  z = ffbp_remove_at(pairs, index)
  z = ffbp_remove_at(novelties, index)
  z = ffbp_remove_at(roles, index)
  z = ffbp_remove_at(uses, index)
  1

# Counters: admitted, evicted, rejected, duplicate.
-> ffbp_pareto_add(states, ranks, bits, pairs, novelties, roles, uses, candidate, best, capacity, role, counters)
  candidate_rank = ffw_best_rank(candidate) ## i64
  candidate_bits = ffw_best_bits(candidate) ## i64
  candidate_pairs = ffbp_flip_pairs(candidate) ## i64
  candidate_novelty = candidate_rank + candidate_rank ## i64
  if ffw_best_rank(best) == candidate_rank
    candidate_novelty = ffbp_distance(candidate, best)
  if candidate_novelty == 0
    counters[3] = counters[3] + 1
    return 0

  lowest_rank = candidate_rank ## i64
  if ranks.size() > 0
    lowest_rank = ranks[0]
    i = 1 ## i64
    while i < ranks.size()
      if ranks[i] < lowest_rank
        lowest_rank = ranks[i]
      i += 1
    if candidate_rank > lowest_rank
      counters[2] = counters[2] + 1
      return 0
    if candidate_rank < lowest_rank
      while states.size() > 0
        z = ffbp_pareto_remove(states, ranks, bits, pairs, novelties, roles, uses, states.size() - 1) ## i64
        counters[1] = counters[1] + 1

  i = 0
  while i < states.size()
    distance = ffbp_distance(candidate, states[i]) ## i64
    if distance == 0
      counters[3] = counters[3] + 1
      return 0
    if distance < candidate_novelty
      candidate_novelty = distance
    i += 1

  i = 0
  while i < states.size()
    if ffbp_dominates(bits[i], pairs[i], novelties[i], candidate_bits, candidate_pairs, candidate_novelty) == 1
      counters[2] = counters[2] + 1
      return 0
    i += 1

  i = states.size() - 1 ## i64
  while i >= 0
    if ffbp_dominates(candidate_bits, candidate_pairs, candidate_novelty, bits[i], pairs[i], novelties[i]) == 1
      z = ffbp_pareto_remove(states, ranks, bits, pairs, novelties, roles, uses, i) ## i64
      counters[1] = counters[1] + 1
    i -= 1

  if states.size() < capacity
    states.push(candidate)
    ranks.push(candidate_rank)
    bits.push(candidate_bits)
    pairs.push(candidate_pairs)
    novelties.push(candidate_novelty)
    roles.push(role)
    uses.push(0)
    counters[0] = counters[0] + 1
    return 1

  # At capacity: reseed the worst victim in place instead of push+pop, which
  # orphaned a full state every admission under the campaign allocator.
  victim = 0 ## i64
  i = 1
  while i < states.size()
    worse = 0 ## i64
    if novelties[i] < novelties[victim]
      worse = 1
    if novelties[i] == novelties[victim]
      if bits[i] > bits[victim]
        worse = 1
      if bits[i] == bits[victim] && pairs[i] < pairs[victim]
        worse = 1
    if worse == 1
      victim = i
    i += 1
  # Only replace if candidate is not worse than the victim on the eviction key.
  if novelties[victim] > candidate_novelty
    counters[2] = counters[2] + 1
    return 0
  if novelties[victim] == candidate_novelty
    if bits[victim] < candidate_bits
      counters[2] = counters[2] + 1
      return 0
    if bits[victim] == candidate_bits && pairs[victim] > candidate_pairs
      counters[2] = counters[2] + 1
      return 0
  loaded = ffw_reseed_from(states[victim], candidate, 1) ## i64
  if loaded < 1
    states[victim] = candidate
  ranks[victim] = candidate_rank
  bits[victim] = candidate_bits
  pairs[victim] = candidate_pairs
  novelties[victim] = candidate_novelty
  roles[victim] = role
  uses[victim] = 0
  counters[0] = counters[0] + 1
  counters[1] = counters[1] + 1
  1

-> ffbp_pareto_select(states, bits, pairs, novelties, uses, stable_key) i64
  if states.size() == 0
    return 0 - 1
  start = stable_key % states.size() ## i64
  best = start ## i64
  offset = 1 ## i64
  while offset < states.size()
    index = (start + offset) % states.size() ## i64
    better = 0 ## i64
    if uses[index] < uses[best]
      better = 1
    if uses[index] == uses[best]
      if novelties[index] > novelties[best]
        better = 1
      if novelties[index] == novelties[best]
        if bits[index] < bits[best]
          better = 1
        if bits[index] == bits[best] && pairs[index] > pairs[best]
          better = 1
    if better == 1
      best = index
    offset += 1
  uses[best] = uses[best] + 1
  best
