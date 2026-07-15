# Bounded five-changed-term rank-one circuit exchange.
#
# Each candidate changes exactly one factor of one live rank-one term by an
# arbitrary nonzero XOR mask.  The resulting tensor delta is rank one, so five
# candidates form an exact atomic move precisely when their delta tensors XOR
# to zero.  This module builds a bounded candidate reservoir and uses a 2+3
# linear-sketch join.  Every sketch hit is checked over all tensor coordinates;
# only minimal five-circuits on five distinct live terms are materialized.
#
# The move generator includes:
#   * every one-bit toggle;
#   * collapse of a multi-bit factor to each live singleton;
#   * XOR by, and transplant to, the three closest live factors on that axis.
#
# This is offline/reference code until a real beyond-span endpoint earns a
# production lane.  A caller starting from a matrix-multiplication scheme must
# rebuild and full-gate the complete tensor before publishing an endpoint.

use flipfleet_matroid_circuit

-> ffmc5_column_sketch(us, vs, ws, term, axis, delta_mask, width) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  result = 0 ## i64
  u = us[term] ## i64
  v = vs[term] ## i64
  w = ws[term] ## i64
  ui = 0 ## i64
  while ui < width
    u_live = ((u >> ui) & 1) == 1 ## bool
    if axis == 0
      u_live = ((delta_mask >> ui) & 1) == 1
    if u_live
      vi = 0 ## i64
      while vi < width
        v_live = ((v >> vi) & 1) == 1 ## bool
        if axis == 1
          v_live = ((delta_mask >> vi) & 1) == 1
        if v_live
          wi = 0 ## i64
          while wi < width
            w_live = ((w >> wi) & 1) == 1 ## bool
            if axis == 2
              w_live = ((delta_mask >> wi) & 1) == 1
            if w_live
              result = result ^ ffmc_cell_hash((ui * width + vi) * width + wi)
            wi += 1
        vi += 1
    ui += 1
  result

-> ffmc5_move_cell(us, vs, ws, terms, axes, masks, move, ui, vi, wi) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64) i64
  term = terms[move] ## i64
  axis = axes[move] ## i64
  live = 1 ## i64
  if axis == 0
    if ((masks[move] >> ui) & 1) == 0
      live = 0
  if axis != 0
    if ((us[term] >> ui) & 1) == 0
      live = 0
  if axis == 1
    if ((masks[move] >> vi) & 1) == 0
      live = 0
  if axis != 1
    if ((vs[term] >> vi) & 1) == 0
      live = 0
  if axis == 2
    if ((masks[move] >> wi) & 1) == 0
      live = 0
  if axis != 2
    if ((ws[term] >> wi) & 1) == 0
      live = 0
  live

-> ffmc5_circuit_exact(us, vs, ws, terms, axes, masks, moves, count, width) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64) i64
  if count < 2 || count > 8
    return 0
  i = 0 ## i64
  while i < count
    if moves[i] < 0 || masks[moves[i]] == 0
      return 0
    j = i + 1 ## i64
    while j < count
      if terms[moves[i]] == terms[moves[j]]
        return 0
      j += 1
    i += 1
  ui = 0 ## i64
  while ui < width
    vi = 0 ## i64
    while vi < width
      wi = 0 ## i64
      while wi < width
        parity = 0 ## i64
        i = 0
        while i < count
          parity = parity ^ ffmc5_move_cell(us, vs, ws, terms, axes, masks, moves[i], ui, vi, wi)
          i += 1
        if parity != 0
          return 0
        wi += 1
      vi += 1
    ui += 1
  1

-> ffmc5_factor(us, vs, ws, term, axis) (i64[] i64[] i64[] i64 i64) i64
  result = us[term] ## i64
  if axis == 1
    result = vs[term]
  if axis == 2
    result = ws[term]
  result

-> ffmc5_move_present(terms, axes, masks, start, count, term, axis, delta_mask) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  i = start ## i64
  while i < count
    if terms[i] == term && axes[i] == axis && masks[i] == delta_mask
      return 1
    i += 1
  0

-> ffmc5_add_move(us, vs, ws, term, axis, delta_mask, width, start, count, capacity, terms, axes, masks, sketches, density_deltas) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if delta_mask == 0 || count >= capacity
    return count
  factor = ffmc5_factor(us, vs, ws, term, axis) ## i64
  changed = factor ^ delta_mask ## i64
  if changed == 0 || (delta_mask >> width) != 0
    return count
  if ffmc5_move_present(terms, axes, masks, start, count, term, axis, delta_mask) == 1
    return count
  terms[count] = term
  axes[count] = axis
  masks[count] = delta_mask
  sketches[count] = ffmc5_column_sketch(us, vs, ws, term, axis, delta_mask, width)
  density_deltas[count] = ffw_popcount(changed) - ffw_popcount(factor)
  count + 1

-> ffmc5_insert_nearest(values, distances, value, distance) (i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < 3
    if values[i] == value
      return 0
    i += 1
  position = 0 - 1 ## i64
  i = 0
  while i < 3 && position < 0
    if distance < distances[i]
      position = i
    i += 1
  if position >= 0
    i = 2
    while i > position
      values[i] = values[i - 1]
      distances[i] = distances[i - 1]
      i -= 1
    values[position] = value
    distances[position] = distance
    return 1
  0

# Worst-case capacity is rank * 3 * (2*width + 6).
-> ffmc5_build_moves(us, vs, ws, rank, width, capacity, terms, axes, masks, sketches, density_deltas) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if rank < 1 || width < 1 || width > 49 || capacity < rank * 3 * width
    return 0
  count = 0 ## i64
  term = 0 ## i64
  while term < rank
    axis = 0 ## i64
    while axis < 3
      start = count ## i64
      factor = ffmc5_factor(us, vs, ws, term, axis) ## i64
      if factor <= 0 || (factor >> width) != 0
        return 0
      bit = 0 ## i64
      while bit < width
        count = ffmc5_add_move(us, vs, ws, term, axis, 1 << bit, width, start, count, capacity, terms, axes, masks, sketches, density_deltas)
        bit += 1
      # Collapsing a factor of weight two is already one singleton removal.
      # For larger factors it is a genuinely multi-bit density move.
      if ffw_popcount(factor) > 2
        bit = 0
        while bit < width
          if ((factor >> bit) & 1) == 1
            count = ffmc5_add_move(us, vs, ws, term, axis, factor ^ (1 << bit), width, start, count, capacity, terms, axes, masks, sketches, density_deltas)
          bit += 1
      near_values = i64[3]
      near_distances = i64[3]
      near_distances[0] = 999999999
      near_distances[1] = 999999999
      near_distances[2] = 999999999
      other = 0 ## i64
      while other < rank
        value = ffmc5_factor(us, vs, ws, other, axis) ## i64
        if value != factor && value != 0
          z = ffmc5_insert_nearest(near_values, near_distances, value, ffw_popcount(factor ^ value)) ## i64
        other += 1
      near = 0 ## i64
      while near < 3
        value = near_values[near]
        if value != 0
          # XOR by a nearby live factor and transplant directly to it.
          count = ffmc5_add_move(us, vs, ws, term, axis, value, width, start, count, capacity, terms, axes, masks, sketches, density_deltas)
          count = ffmc5_add_move(us, vs, ws, term, axis, factor ^ value, width, start, count, capacity, terms, axes, masks, sketches, density_deltas)
        near += 1
      axis += 1
    term += 1
  count

-> ffmc5_toggle_move(us, vs, ws, terms, axes, masks, move, out_u, out_v, out_w) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  term = terms[move] ## i64
  if axes[move] == 0
    out_u[term] = out_u[term] ^ masks[move]
  if axes[move] == 1
    out_v[term] = out_v[term] ^ masks[move]
  if axes[move] == 2
    out_w[term] = out_w[term] ^ masks[move]
  if out_u[term] == 0 || out_v[term] == 0 || out_w[term] == 0
    return 0
  1

-> ffmc5_materialize(us, vs, ws, rank, terms, axes, masks, moves, count, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  raw_u = i64[rank]
  raw_v = i64[rank]
  raw_w = i64[rank]
  z = fftc_copy_terms(us, vs, ws, rank, raw_u, raw_v, raw_w) ## i64
  i = 0 ## i64
  while i < count
    if ffmc5_toggle_move(us, vs, ws, terms, axes, masks, moves[i], raw_u, raw_v, raw_w) == 0
      return 0
    i += 1
  ffmc_compact_terms(raw_u, raw_v, raw_w, rank, out_u, out_v, out_w)

-> ffmc5_capture_exchange(us, vs, ws, terms, axes, masks, moves, count, old_u, old_v, old_w, new_u, new_v, new_w) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < count
    move = moves[i] ## i64
    term = terms[move] ## i64
    old_u[i] = us[term]
    old_v[i] = vs[term]
    old_w[i] = ws[term]
    new_u[i] = old_u[i]
    new_v[i] = old_v[i]
    new_w[i] = old_w[i]
    if axes[move] == 0
      new_u[i] = new_u[i] ^ masks[move]
    if axes[move] == 1
      new_v[i] = new_v[i] ^ masks[move]
    if axes[move] == 2
      new_w[i] = new_w[i] ^ masks[move]
    i += 1
  count

-> ffmc5_reservoir(density_deltas, move_count, wanted, class_id, nonce, selected, offset) (i64[] i64 i64 i64 i64 i64[] i64) i64
  if wanted < 1
    return 0
  seen = 0 ## i64
  count = 0 ## i64
  move = 0 ## i64
  while move < move_count
    eligible = 0 ## i64
    if class_id == 0 && density_deltas[move] < 0
      eligible = 1
    if class_id == 1 && density_deltas[move] >= 0
      eligible = 1
    if eligible == 1
      seen += 1
      if count < wanted
        selected[offset + count] = move
        count += 1
      if count >= wanted && seen > wanted
        slot = ffmc_mix63(nonce + move * 3935559000370003845 + seen * 1442695040888963407) % seen ## i64
        if slot < wanted
          selected[offset + slot] = move
    move += 1
  count

# Policies 0..4 select negative-only, 2/3 negative, balanced, 1/3 negative,
# and nonnegative-only candidate reservoirs respectively.
-> ffmc5_select_pool(density_deltas, move_count, wanted, policy, nonce, selected, counts) (i64[] i64 i64 i64 i64 i64[] i64[]) i64
  if wanted < 5 || wanted > 2048 || policy < 0 || policy > 4
    return 0
  negative_wanted = wanted / 2 ## i64
  if policy == 0
    negative_wanted = wanted
  if policy == 1
    negative_wanted = (wanted * 2) / 3
  if policy == 3
    negative_wanted = wanted / 3
  if policy == 4
    negative_wanted = 0
  nonnegative_wanted = wanted - negative_wanted ## i64
  negative_count = ffmc5_reservoir(density_deltas, move_count, negative_wanted, 0, nonce ^ 2862933555777941757, selected, 0) ## i64
  nonnegative_count = ffmc5_reservoir(density_deltas, move_count, nonnegative_wanted, 1, nonce ^ 6364136223846793005, selected, negative_count) ## i64
  counts[0] = negative_count
  counts[1] = nonnegative_count
  negative_count + nonnegative_count

# Reject a zero sum containing a proper two- or three-column zero subset.
# Because the full five-sum is zero, this also rejects complementary
# three- and two-subsets; a four-subset cannot be zero unless its remaining
# nonzero column is zero.
-> ffmc5_circuit_minimal(us, vs, ws, terms, axes, masks, sketches, moves, width) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < 5
    j = i + 1 ## i64
    while j < 5
      if (sketches[moves[i]] ^ sketches[moves[j]]) == 0
        subset = i64[2]
        subset[0] = moves[i]
        subset[1] = moves[j]
        if ffmc5_circuit_exact(us, vs, ws, terms, axes, masks, subset, 2, width) == 1
          return 0
      j += 1
    i += 1
  i = 0
  while i < 3
    j = i + 1
    while j < 4
      k = j + 1 ## i64
      while k < 5
        if (sketches[moves[i]] ^ sketches[moves[j]] ^ sketches[moves[k]]) == 0
          subset = i64[3]
          subset[0] = moves[i]
          subset[1] = moves[j]
          subset[2] = moves[k]
          if ffmc5_circuit_exact(us, vs, ws, terms, axes, masks, subset, 3, width) == 1
            return 0
        k += 1
      j += 1
    i += 1
  1

# Bounded 2+3 tensor-syndrome join.
#
# meta: generated moves, selected moves, pair table entries, triples visited,
# sketch matches, exact five-sums, minimal circuits, valid endpoints,
# one-flip endpoints, span-5 endpoints, direct-distance-five endpoints,
# rank-drop endpoints, best density delta, output rank, selected negative,
# selected nonnegative, status, pair-table capacity.
-> ffmc5_search_bounded(us, vs, ws, rank, width, pool_wanted, policy, nonce, triple_cap, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  if meta.size() < 18
    return 0
  m = 0 ## i64
  while m < 18
    meta[m] = 0
    m += 1
  if rank < 5 || width < 1 || width > 49 || pool_wanted < 5 || pool_wanted > 2048 || policy < 0 || policy > 4 || nonce < 0 || triple_cap < 0
    meta[16] = 0 - 1
    return 0
  move_capacity = rank * 3 * (width * 2 + 6) ## i64
  terms = i64[move_capacity]
  axes = i64[move_capacity]
  masks = i64[move_capacity]
  sketches = i64[move_capacity]
  density_deltas = i64[move_capacity]
  move_count = ffmc5_build_moves(us, vs, ws, rank, width, move_capacity, terms, axes, masks, sketches, density_deltas) ## i64
  meta[0] = move_count
  selected = i64[pool_wanted]
  selected_counts = i64[2]
  selected_count = ffmc5_select_pool(density_deltas, move_count, pool_wanted, policy, nonce, selected, selected_counts) ## i64
  meta[1] = selected_count
  meta[14] = selected_counts[0]
  meta[15] = selected_counts[1]
  if selected_count < 5
    return 0

  pair_bound = selected_count * (selected_count - 1) / 2 ## i64
  table_capacity = ffmc_next_power_of_two(pair_bound * 2 + 1) ## i64
  meta[17] = table_capacity
  table_mask = table_capacity - 1 ## i64
  used = i64[table_capacity]
  keys = i64[table_capacity]
  lefts = i64[table_capacity]
  rights = i64[table_capacity]
  i = 0 ## i64
  while i < selected_count - 1
    j = i + 1 ## i64
    while j < selected_count
      first = selected[i] ## i64
      second = selected[j] ## i64
      if terms[first] != terms[second]
        key = sketches[first] ^ sketches[second] ## i64
        slot = ffmc_hash_slot(key, table_mask)
        while used[slot] != 0
          slot = (slot + 1) & table_mask
        used[slot] = 1
        keys[slot] = key
        lefts[slot] = i
        rights[slot] = j
        meta[2] = meta[2] + 1
      j += 1
    i += 1

  source_density = fftc_density(us, vs, ws, rank) ## i64
  best_rank = rank + 1 ## i64
  best_density = 9223372036854775807 ## i64
  stop = 0 ## i64
  i = 2
  while i < selected_count - 2 && stop == 0
    j = i + 1
    while j < selected_count - 1 && stop == 0
      first = selected[i]
      second = selected[j]
      if terms[first] != terms[second]
        k = j + 1 ## i64
        while k < selected_count && stop == 0
          third = selected[k] ## i64
          if terms[third] != terms[first] && terms[third] != terms[second]
            if triple_cap > 0 && meta[3] >= triple_cap
              stop = 1
            if stop == 0
              meta[3] = meta[3] + 1
              wanted = sketches[first] ^ sketches[second] ^ sketches[third] ## i64
              slot = ffmc_hash_slot(wanted, table_mask)
              scanned = 0 ## i64
              while scanned < table_capacity && used[slot] != 0
                if keys[slot] == wanted
                  left_position = lefts[slot] ## i64
                  right_position = rights[slot] ## i64
                  # The unique canonical 2+3 partition uses the two smallest
                  # selected positions as the stored pair.
                  if right_position < i
                    fourth = selected[left_position] ## i64
                    fifth = selected[right_position] ## i64
                    if terms[fourth] != terms[first] && terms[fourth] != terms[second] && terms[fourth] != terms[third] && terms[fifth] != terms[first] && terms[fifth] != terms[second] && terms[fifth] != terms[third] && terms[fourth] != terms[fifth]
                      meta[4] = meta[4] + 1
                      circuit = i64[5]
                      circuit[0] = fourth
                      circuit[1] = fifth
                      circuit[2] = first
                      circuit[3] = second
                      circuit[4] = third
                      if ffmc5_circuit_exact(us, vs, ws, terms, axes, masks, circuit, 5, width) == 1
                        meta[5] = meta[5] + 1
                        if ffmc5_circuit_minimal(us, vs, ws, terms, axes, masks, sketches, circuit, width) == 1
                          meta[6] = meta[6] + 1
                          candidate_u = i64[rank]
                          candidate_v = i64[rank]
                          candidate_w = i64[rank]
                          candidate_rank = ffmc5_materialize(us, vs, ws, rank, terms, axes, masks, circuit, 5, candidate_u, candidate_v, candidate_w) ## i64
                          if candidate_rank > 0
                            old_u = i64[5]
                            old_v = i64[5]
                            old_w = i64[5]
                            new_u = i64[5]
                            new_v = i64[5]
                            new_w = i64[5]
                            z = ffmc5_capture_exchange(us, vs, ws, terms, axes, masks, circuit, 5, old_u, old_v, old_w, new_u, new_v, new_w) ## i64
                            if fftc_local_exact(old_u, old_v, old_w, 5, new_u, new_v, new_w, 5) == 1
                              meta[7] = meta[7] + 1
                              set_delta = ffks_term_set_delta(old_u, old_v, old_w, 5, new_u, new_v, new_w) ## i64
                              one_flip = 0 ## i64
                              if set_delta <= 2
                                one_flip = ffks_is_one_flip(old_u, old_v, old_w, 5, new_u, new_v, new_w)
                              if one_flip == 1
                                meta[8] = meta[8] + 1
                              if ffmc_span_duplicate(old_u, old_v, old_w, new_u, new_v, new_w, 5) == 1
                                meta[9] = meta[9] + 1
                              if set_delta == 5 && candidate_rank == rank
                                meta[10] = meta[10] + 1
                              if candidate_rank < rank
                                meta[11] = meta[11] + 1
                              candidate_density = fftc_density(candidate_u, candidate_v, candidate_w, candidate_rank) ## i64
                              if candidate_rank < best_rank || (candidate_rank == best_rank && candidate_density < best_density)
                                best_rank = candidate_rank
                                best_density = candidate_density
                                z = fftc_copy_terms(candidate_u, candidate_v, candidate_w, candidate_rank, out_u, out_v, out_w)
                slot = (slot + 1) & table_mask
                scanned += 1
          k += 1
      j += 1
    i += 1
  if best_rank <= rank
    meta[12] = best_density - source_density
    meta[13] = best_rank
    meta[16] = 1
    return best_rank
  meta[16] = 0
  0
