# Exact-equivalent square-frontier archive admission.
#
# A full archive admits a candidate only when replacing one slot strictly
# raises its minimum pair distance.  If (a,b) is any pair attaining the
# current minimum, replacing a slot outside {a,b} leaves that pair untouched
# and therefore cannot improve the minimum.  The optimized action evaluates
# only a and b, in ascending slot order.  A second pair-distance pass computes
# both endpoints' unaffected minima together; candidate distances are reused
# from the admission scan via their two smallest values.  This remains exact
# when several pairs attain the minimum: a replacement succeeds only if it
# removes every such pair.

use ../scheme
use basins

-> ffn_term_in(state, u, v, w) (i64[] i64 i64 i64) i64
  found = 0 ## i64
  rank = ffw_best_rank(state) ## i64
  i = 0 ## i64
  while i < rank
    if ffw_read_best_u(state, i) == u
      if ffw_read_best_v(state, i) == v
        if ffw_read_best_w(state, i) == w
          found = 1
          i = rank
        else
          i += 1
      else
        i += 1
    else
      i += 1
  found

-> ffn_distance(a, b) (i64[] i64[]) i64
  if ffbi_best_id(a) == ffbi_best_id(b)
    return 0
  arank = ffw_best_rank(a) ## i64
  brank = ffw_best_rank(b) ## i64
  common = 0 ## i64
  i = 0 ## i64
  while i < arank
    common += ffn_term_in(b, ffw_read_best_u(a, i), ffw_read_best_v(a, i), ffw_read_best_w(a, i))
    i += 1
  arank + brank - common - common

# Retained for the shoulder banks and as the exhaustive test oracle's scalar
# primitive.  The frontier archive action below no longer calls it once per
# slot.
-> ffn_replacement_min_distance(items, replace, candidate)
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
        d = ffn_distance(left, right) ## i64
        if d < result
          result = d
        j += 1
      i += 1
  result

-> ffn_archive_admission_action(archive, candidate, capacity, min_distance) i64
  duplicate = 0 ## i64
  closest = 999999999 ## i64
  closest_slot = 0 - 1 ## i64
  second_closest = 999999999 ## i64
  i = 0 ## i64
  while i < archive.size()
    distance = ffn_distance(archive[i], candidate) ## i64
    if distance == 0
      duplicate = 1
    if distance < closest
      second_closest = closest
      closest = distance
      closest_slot = i
    else
      if distance < second_closest
        second_closest = distance
    i += 1
  if archive.size() == 0
    closest = 999999999
  if duplicate != 0 || closest < min_distance
    return 0
  if archive.size() < capacity
    return 1

  # The exhaustive algorithm cannot replace the sole member of a capacity-1
  # archive: both its old and trial minima are -1. Preserve that edge case.
  if archive.size() < 2
    return 0

  # Pass one: deterministically choose the first current-minimum pair.
  current_min = 999999999 ## i64
  min_left = 0 - 1 ## i64
  min_right = 0 - 1 ## i64
  i = 0
  while i < archive.size()
    j = i + 1 ## i64
    while j < archive.size()
      distance = ffn_distance(archive[i], archive[j]) ## i64
      if distance < current_min
        current_min = distance
        min_left = i
        min_right = j
      j += 1
    i += 1

  # Pass two: one shared scan finds the old-pair minima that survive replacing
  # either endpoint. No per-admission scratch arrays are allocated.
  without_left = 999999999 ## i64
  without_right = 999999999 ## i64
  i = 0
  while i < archive.size()
    j = i + 1
    while j < archive.size()
      distance = ffn_distance(archive[i], archive[j]) ## i64
      if i != min_left && j != min_left
        if distance < without_left
          without_left = distance
      if i != min_right && j != min_right
        if distance < without_right
          without_right = distance
      j += 1
    i += 1

  candidate_without_left = closest ## i64
  if closest_slot == min_left
    candidate_without_left = second_closest
  candidate_without_right = closest ## i64
  if closest_slot == min_right
    candidate_without_right = second_closest

  trial_left = without_left ## i64
  if candidate_without_left < trial_left
    trial_left = candidate_without_left
  trial_right = without_right ## i64
  if candidate_without_right < trial_right
    trial_right = candidate_without_right

  # min_left < min_right by construction. Strict comparison reproduces the
  # exhaustive algorithm's deterministic ascending-slot tie break.
  replace = 0 - 1 ## i64
  best_min = current_min ## i64
  if trial_left > best_min
    best_min = trial_left
    replace = min_left
  if trial_right > best_min
    replace = min_right
  if replace >= 0
    return replace + 2
  0

-> ffn_archive_add(archive, candidate, capacity, min_distance, counters)
  action = ffn_archive_admission_action(archive, candidate, capacity, min_distance) ## i64
  if action == 1
    archive.push(candidate)
  if action >= 2
    slot = action - 2 ## i64
    # Prefer reseed so a displaced archive state is not retained forever.
    loaded = ffw_reseed_from(archive[slot], candidate, 1) ## i64
    if loaded < 1
      archive[slot] = candidate
    counters[1] = counters[1] + 1
  if action > 0
    counters[0] = counters[0] + 1
    return 1
  if action == 0
    counters[2] = counters[2] + 1
  0

# Hot CPU candidates are copied into archive-owned storage only after the
# allocation-free admission plan succeeds. Appends allocate at most capacity
# slots; replacements reuse the selected slot in place.
-> ffn_archive_add_copy(archive, candidate, capacity, min_distance, counters, state_size, seed) i64
  action = ffn_archive_admission_action(archive, candidate, capacity, min_distance) ## i64
  if action == 0
    counters[2] = counters[2] + 1
    return 0
  if action == 1
    stored = i64[state_size]
    loaded = ffw_reseed_from(stored, candidate, seed) ## i64
    if loaded < 1
      counters[2] = counters[2] + 1
      return 0
    archive.push(stored)
  if action >= 2
    slot = action - 2 ## i64
    loaded = ffw_reseed_from(archive[slot], candidate, seed) ## i64
    if loaded < 1
      counters[2] = counters[2] + 1
      return 0
    counters[1] = counters[1] + 1
  counters[0] = counters[0] + 1
  1

-> ffn_archive_min_distance(archive)
  result = 0 - 1 ## i64
  if archive.size() > 1
    result = 999999999
    i = 0 ## i64
    while i < archive.size()
      j = i + 1 ## i64
      while j < archive.size()
        d = ffn_distance(archive[i], archive[j]) ## i64
        if d < result
          result = d
        j += 1
      i += 1
  result
