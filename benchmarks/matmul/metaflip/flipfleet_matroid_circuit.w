# Bounded rank-one matroid-circuit exchange for exact GF(2) schemes.
#
# An elementary exchange toggles one bit of one factor of one live term.  Its
# tensor delta is still rank one: for example
#
#   (u + e_p) (x) v (x) w + u (x) v (x) w = e_p (x) v (x) w.
#
# The elementary deltas are columns of a binary matroid.  A zero circuit on
# distinct live terms can therefore be applied atomically without exposing
# any of its generally non-exact intermediate states.  This module searches
# all three-column circuits with a linear 63-bit tensor sketch and an exact
# full-coordinate check.  A second bounded MITM pass searches the only
# four-column sign patterns that can improve density: 4 removals and
# 3 removals + 1 insertion.
#
# The sketch is only a filter.  Every reported circuit is checked over all
# `width^3` tensor coordinates, materialized, parity-compacted, and locally
# reverified.  A real-frontier caller must still rebuild and full-gate the
# complete matrix-multiplication tensor before publication.

use flipfleet_kernel_shear

-> ffmc_mix63(value) (i64) i64
  mask = 9223372036854775807 ## i64
  x = (value + 3202034522624059733) & mask ## i64
  x = (x ^ (x >> 29)) & mask
  x = (x * 3935559000370003845) & mask
  x = (x ^ (x >> 31)) & mask
  x = (x * 2862933555777941757) & mask
  (x ^ (x >> 27)) & mask

-> ffmc_cell_hash(cell) (i64) i64
  ffmc_mix63(cell + 1)

-> ffmc_hash_slot(key, mask) (i64 i64) i64
  ffmc_mix63(key ^ (key >> 23)) & mask

-> ffmc_next_power_of_two(wanted) (i64) i64
  result = 1 ## i64
  while result < wanted
    result = result * 2
  result

-> ffmc_column_sketch(us, vs, ws, term, axis, bit, width) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  result = 0 ## i64
  u = us[term] ## i64
  v = vs[term] ## i64
  w = ws[term] ## i64
  ui = 0 ## i64
  while ui < width
    u_live = ((u >> ui) & 1) == 1 ## bool
    if axis == 0
      u_live = ui == bit
    if u_live
      vi = 0 ## i64
      while vi < width
        v_live = ((v >> vi) & 1) == 1 ## bool
        if axis == 1
          v_live = vi == bit
        if v_live
          wi = 0 ## i64
          while wi < width
            w_live = ((w >> wi) & 1) == 1 ## bool
            if axis == 2
              w_live = wi == bit
            if w_live
              cell = (ui * width + vi) * width + wi ## i64
              result = result ^ ffmc_cell_hash(cell)
            wi += 1
        vi += 1
    ui += 1
  result

-> ffmc_column_cell(us, vs, ws, terms, axes, bits, edit, width, ui, vi, wi) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  term = terms[edit] ## i64
  axis = axes[edit] ## i64
  live = 1 ## i64
  if axis == 0
    if ui != bits[edit]
      live = 0
  if axis != 0
    if ((us[term] >> ui) & 1) == 0
      live = 0
  if axis == 1
    if vi != bits[edit]
      live = 0
  if axis != 1
    if ((vs[term] >> vi) & 1) == 0
      live = 0
  if axis == 2
    if wi != bits[edit]
      live = 0
  if axis != 2
    if ((ws[term] >> wi) & 1) == 0
      live = 0
  live

-> ffmc_circuit_exact(us, vs, ws, terms, axes, bits, edits, count, width) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64) i64
  if count < 2 || count > 8
    return 0
  i = 0 ## i64
  while i < count
    if edits[i] < 0
      return 0
    j = i + 1 ## i64
    while j < count
      if terms[edits[i]] == terms[edits[j]]
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
          parity = parity ^ ffmc_column_cell(us, vs, ws, terms, axes, bits, edits[i], width, ui, vi, wi)
          i += 1
        if parity != 0
          return 0
        wi += 1
      vi += 1
    ui += 1
  1

# Generate every nonzero one-bit perturbation.  `deltas` is -1 when the bit
# is removed and +1 when it is inserted, exactly matching the density change.
-> ffmc_build_edits(us, vs, ws, rank, width, terms, axes, bits, sketches, deltas) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  if rank < 1 || width < 1 || width > 49
    return 0
  count = 0 ## i64
  term = 0 ## i64
  while term < rank
    axis = 0 ## i64
    while axis < 3
      factor = us[term] ## i64
      if axis == 1
        factor = vs[term]
      if axis == 2
        factor = ws[term]
      if factor <= 0 || (factor >> width) != 0
        return 0
      bit = 0 ## i64
      while bit < width
        # Removing the sole live bit would make a zero rank-one factor.
        if factor != (1 << bit)
          terms[count] = term
          axes[count] = axis
          bits[count] = bit
          sketches[count] = ffmc_column_sketch(us, vs, ws, term, axis, bit, width)
          delta = 1 ## i64
          if ((factor >> bit) & 1) == 1
            delta = 0 - 1
          deltas[count] = delta
          count += 1
        bit += 1
      axis += 1
    term += 1
  count

-> ffmc_toggle_edit(us, vs, ws, terms, axes, bits, edit, out_u, out_v, out_w) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  term = terms[edit] ## i64
  bit_mask = 1 << bits[edit] ## i64
  if axes[edit] == 0
    out_u[term] = out_u[term] ^ bit_mask
  if axes[edit] == 1
    out_v[term] = out_v[term] ^ bit_mask
  if axes[edit] == 2
    out_w[term] = out_w[term] ^ bit_mask
  if out_u[term] == 0 || out_v[term] == 0 || out_w[term] == 0
    return 0
  1

# Parity compact a raw term multiset.  This intentionally permits a circuit
# endpoint to expose a rank drop through collision with an untouched term.
-> ffmc_compact_terms(raw_u, raw_v, raw_w, raw_count, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  count = 0 ## i64
  i = 0 ## i64
  while i < raw_count
    if raw_u[i] == 0 || raw_v[i] == 0 || raw_w[i] == 0
      return 0
    found = 0 - 1 ## i64
    j = 0 ## i64
    while j < count && found < 0
      if fftc_same_term(raw_u[i], raw_v[i], raw_w[i], out_u[j], out_v[j], out_w[j]) == 1
        found = j
      j += 1
    if found >= 0
      count -= 1
      if found < count
        out_u[found] = out_u[count]
        out_v[found] = out_v[count]
        out_w[found] = out_w[count]
    if found < 0
      out_u[count] = raw_u[i]
      out_v[count] = raw_v[i]
      out_w[count] = raw_w[i]
      count += 1
    i += 1
  count

-> ffmc_materialize(us, vs, ws, rank, terms, axes, bits, edits, count, out_u, out_v, out_w) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  raw_u = i64[rank]
  raw_v = i64[rank]
  raw_w = i64[rank]
  z = fftc_copy_terms(us, vs, ws, rank, raw_u, raw_v, raw_w) ## i64
  i = 0 ## i64
  while i < count
    if ffmc_toggle_edit(us, vs, ws, terms, axes, bits, edits[i], raw_u, raw_v, raw_w) == 0
      return 0
    i += 1
  ffmc_compact_terms(raw_u, raw_v, raw_w, rank, out_u, out_v, out_w)

-> ffmc_in_span(values, count, wanted) (i64[] i64 i64) i64
  combo = 0 ## i64
  limit = 1 << count ## i64
  while combo < limit
    made = 0 ## i64
    i = 0 ## i64
    while i < count
      if ((combo >> i) & 1) == 1
        made = made ^ values[i]
      i += 1
    if made == wanted
      return 1
    combo += 1
  0

# Complete span-k duplication classifier for k <= 8.  The existing production
# span lane is complete only for k=3 and k=4; larger k remains useful as a
# descriptive invariant in offline experiments.
-> ffmc_span_duplicate(old_u, old_v, old_w, new_u, new_v, new_w, count) (i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  if count < 1 || count > 8
    return 0
  if fftc_local_exact(old_u, old_v, old_w, count, new_u, new_v, new_w, count) == 0
    return 0
  i = 0 ## i64
  while i < count
    if ffmc_in_span(old_u, count, new_u[i]) == 0 || ffmc_in_span(old_v, count, new_v[i]) == 0 || ffmc_in_span(old_w, count, new_w[i]) == 0
      return 0
    i += 1
  1

-> ffmc_capture_exchange(us, vs, ws, terms, axes, bits, edits, count, old_u, old_v, old_w, new_u, new_v, new_w) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < count
    edit = edits[i] ## i64
    term = terms[edit] ## i64
    old_u[i] = us[term]
    old_v[i] = vs[term]
    old_w[i] = ws[term]
    new_u[i] = old_u[i]
    new_v[i] = old_v[i]
    new_w[i] = old_w[i]
    if axes[edit] == 0
      new_u[i] = new_u[i] ^ (1 << bits[edit])
    if axes[edit] == 1
      new_v[i] = new_v[i] ^ (1 << bits[edit])
    if axes[edit] == 2
      new_w[i] = new_w[i] ^ (1 << bits[edit])
    i += 1
  count

# Exhaustive 2+1 sketch/MITM for elementary three-column circuits.
#
# meta: edits, pairs visited, sketch matches, exact circuits, valid endpoints,
# one-flip duplicates, span-3 duplicates, beyond-span-3 endpoints, best
# density delta, output rank, negative edits, positive edits, status.
-> ffmc_search3_bounded(us, vs, ws, rank, width, pair_cap, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  if meta.size() < 13
    return 0
  m = 0 ## i64
  while m < 13
    meta[m] = 0
    m += 1
  if rank < 3 || width < 1 || width > 49 || pair_cap < 0
    meta[12] = 0 - 1
    return 0
  capacity = rank * width * 3 ## i64
  terms = i64[capacity]
  axes = i64[capacity]
  bits = i64[capacity]
  sketches = i64[capacity]
  deltas = i64[capacity]
  edit_count = ffmc_build_edits(us, vs, ws, rank, width, terms, axes, bits, sketches, deltas) ## i64
  meta[0] = edit_count
  if edit_count < 3
    return 0
  i = 0
  while i < edit_count
    if deltas[i] < 0
      meta[10] = meta[10] + 1
    if deltas[i] > 0
      meta[11] = meta[11] + 1
    i += 1
  table_capacity = ffmc_next_power_of_two(edit_count * 4 + 1) ## i64
  table_mask = table_capacity - 1 ## i64
  used = i64[table_capacity]
  keys = i64[table_capacity]
  ids = i64[table_capacity]
  i = 0
  while i < edit_count
    slot = ffmc_hash_slot(sketches[i], table_mask) ## i64
    while used[slot] != 0
      slot = (slot + 1) & table_mask
    used[slot] = 1
    keys[slot] = sketches[i]
    ids[slot] = i
    i += 1

  source_density = fftc_density(us, vs, ws, rank) ## i64
  best_rank = rank + 1 ## i64
  best_density = 9223372036854775807 ## i64
  stop = 0 ## i64
  i = 0
  while i < edit_count - 1 && stop == 0
    j = i + 1 ## i64
    while j < edit_count && stop == 0
      if terms[i] != terms[j]
        if pair_cap > 0 && meta[1] >= pair_cap
          stop = 1
        if stop == 0
          meta[1] = meta[1] + 1
          wanted = sketches[i] ^ sketches[j] ## i64
          slot = ffmc_hash_slot(wanted, table_mask)
          scanned = 0 ## i64
          while scanned < table_capacity && used[slot] != 0
            if keys[slot] == wanted
              k = ids[slot] ## i64
              if k > j && terms[k] != terms[i] && terms[k] != terms[j]
                meta[2] = meta[2] + 1
                circuit = i64[3]
                circuit[0] = i
                circuit[1] = j
                circuit[2] = k
                if ffmc_circuit_exact(us, vs, ws, terms, axes, bits, circuit, 3, width) == 1
                  meta[3] = meta[3] + 1
                  candidate_u = i64[rank]
                  candidate_v = i64[rank]
                  candidate_w = i64[rank]
                  candidate_rank = ffmc_materialize(us, vs, ws, rank, terms, axes, bits, circuit, 3, candidate_u, candidate_v, candidate_w) ## i64
                  if candidate_rank > 0
                    old_u = i64[3]
                    old_v = i64[3]
                    old_w = i64[3]
                    new_u = i64[3]
                    new_v = i64[3]
                    new_w = i64[3]
                    z = ffmc_capture_exchange(us, vs, ws, terms, axes, bits, circuit, 3, old_u, old_v, old_w, new_u, new_v, new_w) ## i64
                    if fftc_local_exact(old_u, old_v, old_w, 3, new_u, new_v, new_w, 3) == 1
                      meta[4] = meta[4] + 1
                      one_flip = ffks_is_one_flip(old_u, old_v, old_w, 3, new_u, new_v, new_w) ## i64
                      span3 = ffmc_span_duplicate(old_u, old_v, old_w, new_u, new_v, new_w, 3) ## i64
                      if one_flip == 1
                        meta[5] = meta[5] + 1
                      if span3 == 1
                        meta[6] = meta[6] + 1
                      if span3 == 0
                        meta[7] = meta[7] + 1
                      candidate_density = fftc_density(candidate_u, candidate_v, candidate_w, candidate_rank) ## i64
                      if candidate_rank < best_rank || (candidate_rank == best_rank && candidate_density < best_density)
                        best_rank = candidate_rank
                        best_density = candidate_density
                        z = fftc_copy_terms(candidate_u, candidate_v, candidate_w, candidate_rank, out_u, out_v, out_w)
            slot = (slot + 1) & table_mask
            scanned += 1
      j += 1
    i += 1
  if best_rank <= rank
    meta[8] = best_density - source_density
    meta[9] = best_rank
    meta[12] = 1
    return best_rank
  meta[12] = 0
  0

# Bounded density-improving four-column pass.  The table stores negative +
# negative pairs.  Equal stored pairs give a -4 circuit; probing a negative +
# positive pair gives a -2 circuit.  Therefore no non-improving pair families
# consume the bounded table or probe budget.
#
# meta: edits, negative edits, positive edits, stored NN pairs, NP probes,
# sketch matches, exact circuits, valid endpoints, span-4 duplicates,
# beyond-span-4 endpoints, best density delta, output rank, status.
-> ffmc_search4_improving_bounded(us, vs, ws, rank, width, pair_limit, probe_limit, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  if meta.size() < 13
    return 0
  m = 0 ## i64
  while m < 13
    meta[m] = 0
    m += 1
  if rank < 4 || width < 1 || width > 49 || pair_limit < 1 || probe_limit < 0
    meta[12] = 0 - 1
    return 0
  capacity = rank * width * 3 ## i64
  terms = i64[capacity]
  axes = i64[capacity]
  bits = i64[capacity]
  sketches = i64[capacity]
  deltas = i64[capacity]
  edit_count = ffmc_build_edits(us, vs, ws, rank, width, terms, axes, bits, sketches, deltas) ## i64
  meta[0] = edit_count
  negative = i64[edit_count]
  positive = i64[edit_count]
  i = 0 ## i64
  while i < edit_count
    if deltas[i] < 0
      negative[meta[1]] = i
      meta[1] = meta[1] + 1
    if deltas[i] > 0
      positive[meta[2]] = i
      meta[2] = meta[2] + 1
    i += 1
  if meta[1] < 3
    return 0
  table_capacity = ffmc_next_power_of_two(pair_limit * 2 + 1) ## i64
  table_mask = table_capacity - 1 ## i64
  used = i64[table_capacity]
  keys = i64[table_capacity]
  lefts = i64[table_capacity]
  rights = i64[table_capacity]
  source_density = fftc_density(us, vs, ws, rank) ## i64
  best_rank = rank + 1 ## i64
  best_density = 9223372036854775807 ## i64

  # Insert bounded NN pairs, checking equal prior pairs for 4N circuits.
  stop = 0 ## i64
  ni = 0 ## i64
  while ni < meta[1] - 1 && stop == 0
    nj = ni + 1 ## i64
    while nj < meta[1] && stop == 0
      first = negative[ni] ## i64
      second = negative[nj] ## i64
      if terms[first] != terms[second]
        if meta[3] >= pair_limit
          stop = 1
        if stop == 0
          key = sketches[first] ^ sketches[second] ## i64
          slot = ffmc_hash_slot(key, table_mask)
          scanned = 0 ## i64
          while scanned < table_capacity && used[slot] != 0
            if keys[slot] == key
              other_first = lefts[slot] ## i64
              other_second = rights[slot] ## i64
              if terms[first] != terms[other_first] && terms[first] != terms[other_second] && terms[second] != terms[other_first] && terms[second] != terms[other_second]
                meta[5] = meta[5] + 1
                circuit = i64[4]
                circuit[0] = other_first
                circuit[1] = other_second
                circuit[2] = first
                circuit[3] = second
                if ffmc_circuit_exact(us, vs, ws, terms, axes, bits, circuit, 4, width) == 1
                  meta[6] = meta[6] + 1
                  candidate_u = i64[rank]
                  candidate_v = i64[rank]
                  candidate_w = i64[rank]
                  candidate_rank = ffmc_materialize(us, vs, ws, rank, terms, axes, bits, circuit, 4, candidate_u, candidate_v, candidate_w) ## i64
                  if candidate_rank > 0
                    meta[7] = meta[7] + 1
                    old_u = i64[4]
                    old_v = i64[4]
                    old_w = i64[4]
                    new_u = i64[4]
                    new_v = i64[4]
                    new_w = i64[4]
                    z = ffmc_capture_exchange(us, vs, ws, terms, axes, bits, circuit, 4, old_u, old_v, old_w, new_u, new_v, new_w) ## i64
                    span4 = ffmc_span_duplicate(old_u, old_v, old_w, new_u, new_v, new_w, 4) ## i64
                    if span4 == 1
                      meta[8] = meta[8] + 1
                    if span4 == 0
                      meta[9] = meta[9] + 1
                    candidate_density = fftc_density(candidate_u, candidate_v, candidate_w, candidate_rank) ## i64
                    if candidate_rank < best_rank || (candidate_rank == best_rank && candidate_density < best_density)
                      best_rank = candidate_rank
                      best_density = candidate_density
                      z = fftc_copy_terms(candidate_u, candidate_v, candidate_w, candidate_rank, out_u, out_v, out_w)
            slot = (slot + 1) & table_mask
            scanned += 1
          if scanned < table_capacity
            used[slot] = 1
            keys[slot] = key
            lefts[slot] = first
            rights[slot] = second
            meta[3] = meta[3] + 1
      nj += 1
    ni += 1

  # Probe N+P against the NN table for 3N+1P circuits.
  stop = 0
  ni = 0
  while ni < meta[1] && stop == 0
    pi = 0 ## i64
    while pi < meta[2] && stop == 0
      first = negative[ni]
      second = positive[pi] ## i64
      if terms[first] != terms[second]
        if probe_limit > 0 && meta[4] >= probe_limit
          stop = 1
        if stop == 0
          meta[4] = meta[4] + 1
          key = sketches[first] ^ sketches[second]
          slot = ffmc_hash_slot(key, table_mask)
          scanned = 0
          while scanned < table_capacity && used[slot] != 0
            if keys[slot] == key
              other_first = lefts[slot]
              other_second = rights[slot]
              if terms[first] != terms[other_first] && terms[first] != terms[other_second] && terms[second] != terms[other_first] && terms[second] != terms[other_second]
                meta[5] = meta[5] + 1
                circuit = i64[4]
                circuit[0] = other_first
                circuit[1] = other_second
                circuit[2] = first
                circuit[3] = second
                if ffmc_circuit_exact(us, vs, ws, terms, axes, bits, circuit, 4, width) == 1
                  meta[6] = meta[6] + 1
                  candidate_u = i64[rank]
                  candidate_v = i64[rank]
                  candidate_w = i64[rank]
                  candidate_rank = ffmc_materialize(us, vs, ws, rank, terms, axes, bits, circuit, 4, candidate_u, candidate_v, candidate_w)
                  if candidate_rank > 0
                    meta[7] = meta[7] + 1
                    old_u = i64[4]
                    old_v = i64[4]
                    old_w = i64[4]
                    new_u = i64[4]
                    new_v = i64[4]
                    new_w = i64[4]
                    z = ffmc_capture_exchange(us, vs, ws, terms, axes, bits, circuit, 4, old_u, old_v, old_w, new_u, new_v, new_w)
                    span4 = ffmc_span_duplicate(old_u, old_v, old_w, new_u, new_v, new_w, 4)
                    if span4 == 1
                      meta[8] = meta[8] + 1
                    if span4 == 0
                      meta[9] = meta[9] + 1
                    candidate_density = fftc_density(candidate_u, candidate_v, candidate_w, candidate_rank)
                    if candidate_rank < best_rank || (candidate_rank == best_rank && candidate_density < best_density)
                      best_rank = candidate_rank
                      best_density = candidate_density
                      z = fftc_copy_terms(candidate_u, candidate_v, candidate_w, candidate_rank, out_u, out_v, out_w)
            slot = (slot + 1) & table_mask
            scanned += 1
      pi += 1
    ni += 1
  if best_rank <= rank
    meta[10] = best_density - source_density
    meta[11] = best_rank
    meta[12] = 1
    return best_rank
  meta[12] = 0
  0
