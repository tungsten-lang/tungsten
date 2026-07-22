# Small persisted near-door archive for rectangular portfolio children.
#
# Eight independent exact scheme files sit beside the durable best checkpoint.
# There is deliberately no manifest or mutable index: every slot is loaded
# through the full rectangular reconstruction gate, and every replacement is
# a temp-file + rename.  A partial process stop can therefore leave a mixture
# of old and new slots, but never an unverified seed.

use ../rect

-> ffrda_cap() i64
  8

-> ffrda_path(best_path, slot) (String i64)
  best_path + ".side-door-" + slot.to_s() + ".txt"

-> ffrda_atomic_write(path, body, run_tag, nonce) (String String String i64) i64
  tmp = path + ".tmp." + run_tag + "." + nonce.to_s()
  wrote = write_file(tmp, body)
  if wrote
    moved = ccall("__w_rename", tmp, path)
    if moved
      return 1
  0

-> ffrda_dump_atomic(state, path, run_tag, nonce) (i64[] String String i64) i64
  tmp = path + ".tmp." + run_tag + "." + nonce.to_s()
  rank = ffr_dump_best(state, tmp) ## i64
  if rank > 0
    moved = ccall("__w_rename", tmp, path)
    if moved
      return rank
  0 - 1

# Order-independent fingerprint used as a cheap duplicate prefilter and stable
# selector key. Equality is confirmed term-by-term below, so a collision never
# discards a distinct door.
-> ffrda_best_fingerprint(state) (i64[]) i64
  rank = ffr_best_rank(state) ## i64
  xor_digest = 0 ## i64
  sum_digest = 0 ## i64
  i = 0 ## i64
  while i < rank
    term_digest = ffw_term_zobrist(state[state[47] + i], state[state[48] + i], state[state[49] + i]) ## i64
    xor_digest = xor_digest ^ term_digest
    sum_digest = (sum_digest + term_digest) & 9223372036854775807
    i += 1
  (xor_digest ^ (sum_digest >> 1) ^ (rank * 65537)) & 9223372036854775807

-> ffrda_same_best(left, right) (i64[] i64[]) i64
  rank = ffr_best_rank(left) ## i64
  if rank != ffr_best_rank(right)
    return 0
  if ffr_best_bits(left) != ffr_best_bits(right)
    return 0
  if ffrda_best_fingerprint(left) != ffrda_best_fingerprint(right)
    return 0
  i = 0 ## i64
  while i < rank
    found = 0 ## i64
    j = 0 ## i64
    while j < rank && found == 0
      if left[left[47] + i] == right[right[47] + j] && left[left[48] + i] == right[right[48] + j] && left[left[49] + i] == right[right[49] + j]
        found = 1
      j += 1
    if found == 0
      return 0
    i += 1
  1

# Materialize the live endpoint as a fresh state whose best equals that exact
# current scheme.  This preserves the shoulder where an island actually
# stopped, rather than only its monotonic local best.
-> ffrda_clone_current_exact(src, n, m, p, capacity, seed, dslack, cycles, workq, wanderq) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64)
  if ffr_verify_current_exact(src, n, m, p) != 1
    return nil
  rank = ffr_current_rank(src) ## i64
  if rank < 1 || rank > capacity
    return nil
  us = i64[capacity]
  vs = i64[capacity]
  ws = i64[capacity]
  exported = ffw_export_current(src, us, vs, ws) ## i64
  if exported != rank
    return nil
  dst = i64[ffr_state_size(capacity)]
  loaded = ffr_init_terms_cap(dst, us, vs, ws, rank, n, m, p, capacity, seed, dslack, cycles, workq, wanderq) ## i64
  if loaded != rank || ffr_verify_best_exact(dst, n, m, p) != 1
    return nil
  dst

# Return 1 when admitted, 0 for an exact but out-of-band/duplicate/full
# candidate, and -1 when the candidate itself fails exact reconstruction.
-> ffrda_add_unique(bank, candidate, leader, capacity_limit, n, m, p)
  if candidate == nil || ffr_verify_best_exact(candidate, n, m, p) != 1
    return 0 - 1
  if leader == nil || ffr_verify_best_exact(leader, n, m, p) != 1
    return 0 - 1
  rank = ffr_best_rank(candidate) ## i64
  leader_rank = ffr_best_rank(leader) ## i64
  if rank < leader_rank || rank > leader_rank + 2
    return 0
  if ffrda_same_best(candidate, leader) == 1
    return 0
  i = 0 ## i64
  while i < bank.size()
    if ffrda_same_best(candidate, bank[i]) == 1
      return 0
    i += 1
  if bank.size() >= capacity_limit
    return 0
  bank.push(candidate)
  1

# Exit collection must not inherit the eight-slot persistence cap. Admit every
# exact, distinct R..R+2 shoulder first; the selector below decides which eight
# survive only after it has seen current endpoints, island bests, and old
# archive slots together.
-> ffrda_collect_unique(bank, candidate, leader, n, m, p)
  if candidate == nil || ffr_verify_best_exact(candidate, n, m, p) != 1
    return 0 - 1
  # The campaign leader was exact-gated at adoption and checkpoint publish;
  # avoid reconstructing that same tensor once per exit candidate.
  if leader == nil
    return 0 - 1
  rank = ffr_best_rank(candidate) ## i64
  leader_rank = ffr_best_rank(leader) ## i64
  if rank < leader_rank || rank > leader_rank + 2
    return 0
  if ffrda_same_best(candidate, leader) == 1
    return 0
  i = 0 ## i64
  while i < bank.size()
    if ffrda_same_best(candidate, bank[i]) == 1
      return 0
    i += 1
  bank.push(candidate)
  1

-> ffrda_best_contains(state, u, v, w) (i64[] i64 i64 i64) i64
  rank = ffr_best_rank(state) ## i64
  i = 0 ## i64
  while i < rank
    if state[state[47] + i] == u && state[state[48] + i] == v && state[state[49] + i] == w
      return 1
    i += 1
  0

# Exact symmetric-difference distance between two best term sets.  This is an
# exit-only cold path, so use the transparent O(R^2) scan rather than adding a
# second persistent hash table to every rectangular island.
-> ffrda_best_distance(left, right) (i64[] i64[]) i64
  left_rank = ffr_best_rank(left) ## i64
  right_rank = ffr_best_rank(right) ## i64
  common = 0 ## i64
  i = 0 ## i64
  while i < left_rank
    common += ffrda_best_contains(right, left[left[47] + i], left[left[48] + i], left[left[49] + i])
    i += 1
  left_rank + right_rank - common - common

# Cold-path structural fingerprint for side-door selection.  Unlike the exact
# term-set fingerprint above, this intentionally forgets the numeric names of
# factor masks.  It starts each factor at (axis, term degree, observed XOR-
# triangle degree), then color-refines the tripartite term-incidence graph.
# Independent linear coordinate changes therefore keep the fingerprint while
# presentations with genuinely different factor-sharing structure normally do
# not.  This is only a diversity preference: collisions never reject a door,
# and the selector always falls back to exact term-set distance.
-> ffrda_factor_search(values, offset, count, wanted) (i64[] i64 i64 i64) i64
  low = 0 ## i64
  high = count ## i64
  while low < high
    middle = low + (high - low) / 2 ## i64
    value = values[offset + middle] ## i64
    if value < wanted
      low = middle + 1
    if value >= wanted
      high = middle
  if low < count && values[offset + low] == wanted
    return low
  0 - 1

-> ffrda_structural_hash(a, b, c) (i64 i64 i64) i64
  ffw_term_zobrist(a ^ 7046029254386353131, b ^ 3202034522624059733, c ^ 1442695040888963407)

-> ffrda_structural_signature(state) (i64[]) i64
  rank = ffr_best_rank(state) ## i64
  if rank < 1
    return 0
  mask = 9223372036854775807 ## i64
  values = i64[rank * 3]
  counts = i64[3]
  axis = 0 ## i64
  while axis < 3
    offset = axis * rank ## i64
    i = 0 ## i64
    while i < rank
      value = state[state[47 + axis] + i] ## i64
      found = 0 ## i64
      j = 0 ## i64
      while j < counts[axis]
        if values[offset + j] == value
          found = 1
        j += 1
      if found == 0
        values[offset + counts[axis]] = value
        counts[axis] += 1
      i += 1

    # A sorted factor support makes XOR-triangle membership O(log R) rather
    # than a cubic scan.  Arrival order and internal term order disappear.
    i = 1
    while i < counts[axis]
      value = values[offset + i]
      j = i
      while j > 0 && values[offset + j - 1] > value
        values[offset + j] = values[offset + j - 1]
        j -= 1
      values[offset + j] = value
      i += 1
    axis += 1

  degrees = i64[rank * 3]
  xor_degrees = i64[rank * 3]
  term_nodes = i64[rank * 3]
  axis = 0
  while axis < 3
    offset = axis * rank ## i64
    i = 0
    while i < rank
      value = state[state[47 + axis] + i] ## i64
      local = ffrda_factor_search(values, offset, counts[axis], value) ## i64
      if local < 0
        return 0
      node = offset + local ## i64
      term_nodes[offset + i] = node
      degrees[node] += 1
      i += 1
    a = 0 ## i64
    while a < counts[axis]
      b = a + 1 ## i64
      while b < counts[axis]
        completing = values[offset + a] ^ values[offset + b] ## i64
        c = ffrda_factor_search(values, offset, counts[axis], completing) ## i64
        # Sorted a<b<c records every nonzero XOR triple exactly once.
        if c > b
          xor_degrees[offset + a] += 1
          xor_degrees[offset + b] += 1
          xor_degrees[offset + c] += 1
        b += 1
      a += 1
    axis += 1

  colors = i64[rank * 3]
  next_colors = i64[rank * 3]
  total_nodes = counts[0] + counts[1] + counts[2] ## i64
  axis = 0
  while axis < 3
    offset = axis * rank ## i64
    i = 0
    while i < counts[axis]
      node = offset + i ## i64
      colors[node] = ffrda_structural_hash(axis + 1, degrees[node], xor_degrees[node])
      i += 1
    axis += 1

  term_colors = i64[rank]
  incident_xor = i64[rank * 3]
  incident_sum = i64[rank * 3]
  iteration = 0 ## i64
  while iteration < 6
    axis = 0
    while axis < 3
      offset = axis * rank ## i64
      i = 0
      while i < counts[axis]
        incident_xor[offset + i] = 0
        incident_sum[offset + i] = 0
        i += 1
      axis += 1
    i = 0
    while i < rank
      unode = term_nodes[i] ## i64
      vnode = term_nodes[rank + i] ## i64
      wnode = term_nodes[rank * 2 + i] ## i64
      color = ffrda_structural_hash(colors[unode], colors[vnode], colors[wnode]) ## i64
      term_colors[i] = color
      incident_xor[unode] = incident_xor[unode] ^ color
      incident_xor[vnode] = incident_xor[vnode] ^ color
      incident_xor[wnode] = incident_xor[wnode] ^ color
      incident_sum[unode] = (incident_sum[unode] + color) & mask
      incident_sum[vnode] = (incident_sum[vnode] + color) & mask
      incident_sum[wnode] = (incident_sum[wnode] + color) & mask
      i += 1
    axis = 0
    while axis < 3
      offset = axis * rank ## i64
      i = 0
      while i < counts[axis]
        node = offset + i ## i64
        base = ffrda_structural_hash(colors[node], degrees[node], xor_degrees[node]) ## i64
        next_colors[node] = ffrda_structural_hash(base, incident_xor[node], incident_sum[node])
        i += 1
      axis += 1
    old = colors
    colors = next_colors
    next_colors = old
    iteration += 1

  signature = ffrda_structural_hash(rank, counts[0] + counts[1] * 1024 + counts[2] * 1048576, total_nodes) ## i64
  axis = 0
  while axis < 3
    offset = axis * rank ## i64
    color_xor = 0 ## i64
    color_sum = 0 ## i64
    i = 0
    while i < counts[axis]
      color_xor = color_xor ^ colors[offset + i]
      color_sum = (color_sum + colors[offset + i]) & mask
      i += 1
    axis_signature = ffrda_structural_hash(axis + 11, color_xor, color_sum) ## i64
    signature = ffrda_structural_hash(signature, axis_signature, counts[axis])
    axis += 1
  term_xor = 0 ## i64
  term_sum = 0 ## i64
  i = 0
  while i < rank
    term_xor = term_xor ^ term_colors[i]
    term_sum = (term_sum + term_colors[i]) & mask
    i += 1
  ffrda_structural_hash(signature, term_xor, term_sum)

-> ffrda_term_less(au, av, aw, bu, bv, bw) (i64 i64 i64 i64 i64 i64) i64
  if au < bu
    return 1
  if au > bu
    return 0
  if av < bv
    return 1
  if av > bv
    return 0
  if aw < bw
    return 1
  0

# Find the lexicographically next best term after a cursor.  Terms are all
# nonzero, so (0,0,0) is a valid cursor before the first term.  This gives the
# selector a total, term-order-independent tie break even in the unlikely case
# that two order-independent fingerprints collide.
-> ffrda_next_best_term(state, after_u, after_v, after_w, out) (i64[] i64 i64 i64 i64[]) i64
  found = 0 ## i64
  rank = ffr_best_rank(state) ## i64
  i = 0 ## i64
  while i < rank
    u = state[state[47] + i] ## i64
    v = state[state[48] + i] ## i64
    w = state[state[49] + i] ## i64
    if ffrda_term_less(after_u, after_v, after_w, u, v, w) == 1
      if found == 0 || ffrda_term_less(u, v, w, out[0], out[1], out[2]) == 1
        out[0] = u
        out[1] = v
        out[2] = w
        found = 1
    i += 1
  found

# Stable total ordering used only when max-min distance ties.  Density is a
# useful secondary preference; the final canonical term-set comparison makes
# the result independent of candidate arrival order and internal term order.
-> ffrda_canonical_before(left, right) (i64[] i64[]) i64
  left_rank = ffr_best_rank(left) ## i64
  right_rank = ffr_best_rank(right) ## i64
  if left_rank < right_rank
    return 1
  if left_rank > right_rank
    return 0
  left_bits = ffr_best_bits(left) ## i64
  right_bits = ffr_best_bits(right) ## i64
  if left_bits < right_bits
    return 1
  if left_bits > right_bits
    return 0
  left_fingerprint = ffrda_best_fingerprint(left) ## i64
  right_fingerprint = ffrda_best_fingerprint(right) ## i64
  if left_fingerprint < right_fingerprint
    return 1
  if left_fingerprint > right_fingerprint
    return 0

  left_term = i64[3]
  right_term = i64[3]
  after_u = 0 ## i64
  after_v = 0 ## i64
  after_w = 0 ## i64
  position = 0 ## i64
  while position < left_rank
    left_found = ffrda_next_best_term(left, after_u, after_v, after_w, left_term) ## i64
    right_found = ffrda_next_best_term(right, after_u, after_v, after_w, right_term) ## i64
    if left_found == 0 || right_found == 0
      return left_found
    if ffrda_term_less(left_term[0], left_term[1], left_term[2], right_term[0], right_term[1], right_term[2]) == 1
      return 1
    if ffrda_term_less(right_term[0], right_term[1], right_term[2], left_term[0], left_term[1], left_term[2]) == 1
      return 0
    after_u = left_term[0]
    after_v = left_term[1]
    after_w = left_term[2]
    position += 1
  0

-> ffrda_already_selected(selected, candidate) i64
  i = 0 ## i64
  while i < selected.size()
    if ffrda_same_best(selected[i], candidate) == 1
      return 1
    i += 1
  0

-> ffrda_min_anchor_distance_anchored(candidate, leader, anchors, selected) i64
  minimum = ffrda_best_distance(candidate, leader) ## i64
  i = 0 ## i64
  while i < anchors.size()
    distance = ffrda_best_distance(candidate, anchors[i]) ## i64
    if distance < minimum
      minimum = distance
    i += 1
  i = 0
  while i < selected.size()
    distance = ffrda_best_distance(candidate, selected[i]) ## i64
    if distance < minimum
      minimum = distance
    i += 1
  minimum

-> ffrda_min_anchor_distance(candidate, leader, selected) i64
  anchors = []
  ffrda_min_anchor_distance_anchored(candidate, leader, anchors, selected)

# Pick the max-min candidate in one rank band. Fixed anchors are checked-in
# frontier doors that remain outside the eight persisted slots. A negative
# delta means any admitted R..R+2 band. Equal distances use canonical order.
-> ffrda_farthest_index_anchored(candidates, leader, anchors, selected, delta) i64
  leader_rank = ffr_best_rank(leader) ## i64
  chosen = 0 - 1 ## i64
  chosen_distance = 0 - 1 ## i64
  i = 0 ## i64
  while i < candidates.size()
    candidate = candidates[i]
    rank = ffr_best_rank(candidate) ## i64
    admitted = 1 ## i64
    if rank < leader_rank || rank > leader_rank + 2
      admitted = 0
    if delta >= 0 && rank != leader_rank + delta
      admitted = 0
    if ffrda_same_best(candidate, leader) == 1 || ffrda_already_selected(anchors, candidate) == 1 || ffrda_already_selected(selected, candidate) == 1
      admitted = 0
    if admitted == 1
      distance = ffrda_min_anchor_distance_anchored(candidate, leader, anchors, selected) ## i64
      better = 0 ## i64
      if chosen < 0 || distance > chosen_distance
        better = 1
      if chosen >= 0 && distance == chosen_distance && ffrda_canonical_before(candidate, candidates[chosen]) == 1
        better = 1
      if better == 1
        chosen = i
        chosen_distance = distance
    i += 1
  chosen

-> ffrda_farthest_index(candidates, leader, selected, delta) i64
  anchors = []
  ffrda_farthest_index_anchored(candidates, leader, anchors, selected, delta)

-> ffrda_structural_seen(rank, signature, represented_ranks, represented_signatures, represented_count) (i64 i64 i64[] i64[] i64) i64
  i = 0 ## i64
  while i < represented_count
    if represented_ranks[i] == rank && represented_signatures[i] == signature
      return 1
    i += 1
  0

# Farthest-first selection restricted to a previously unseen structural class.
# The caller retries without this restriction when no such candidate exists,
# so this helper can influence ordering but can never reduce archive capacity.
-> ffrda_farthest_structural_index_anchored(candidates, candidate_signatures, leader, anchors, selected, represented_ranks, represented_signatures, represented_count, delta, require_novel) i64
  leader_rank = ffr_best_rank(leader) ## i64
  chosen = 0 - 1 ## i64
  chosen_distance = 0 - 1 ## i64
  i = 0 ## i64
  while i < candidates.size()
    candidate = candidates[i]
    rank = ffr_best_rank(candidate) ## i64
    admitted = 1 ## i64
    if rank < leader_rank || rank > leader_rank + 2
      admitted = 0
    if delta >= 0 && rank != leader_rank + delta
      admitted = 0
    if ffrda_same_best(candidate, leader) == 1 || ffrda_already_selected(anchors, candidate) == 1 || ffrda_already_selected(selected, candidate) == 1
      admitted = 0
    if require_novel == 1 && ffrda_structural_seen(rank, candidate_signatures[i], represented_ranks, represented_signatures, represented_count) == 1
      admitted = 0
    if admitted == 1
      distance = ffrda_min_anchor_distance_anchored(candidate, leader, anchors, selected) ## i64
      better = 0 ## i64
      if chosen < 0 || distance > chosen_distance
        better = 1
      if chosen >= 0 && distance == chosen_distance && ffrda_canonical_before(candidate, candidates[chosen]) == 1
        better = 1
      if better == 1
        chosen = i
        chosen_distance = distance
    i += 1
  chosen

# Deterministic bounded diversity selection from an already exact/unique exit
# pool. First reserve one slot for every present rank band R, R+1, R+2; then
# fill remaining slots by farthest-first max-min distance from the leader,
# checked-in anchors, and all selected doors. Within each rank band, prefer a
# structural signature not yet represented in that band. If none exists, retry
# the exact same choice without the preference. The fixed band order plus
# canonical tie break makes contents and order independent of arrival order.
-> ffrda_select_diverse_anchored(candidates, leader, anchors, capacity_limit, selected) i64
  limit = capacity_limit ## i64
  if limit < 0
    limit = 0
  candidate_capacity = candidates.size() ## i64
  if candidate_capacity < 1
    candidate_capacity = 1
  candidate_signatures = i64[candidate_capacity]
  i = 0 ## i64
  while i < candidates.size()
    candidate_signatures[i] = ffrda_structural_signature(candidates[i])
    i += 1

  represented_capacity = 1 + anchors.size() + selected.size() + limit ## i64
  if represented_capacity < 1
    represented_capacity = 1
  represented_ranks = i64[represented_capacity]
  represented_signatures = i64[represented_capacity]
  represented_count = 0 ## i64
  if leader != nil
    represented_ranks[represented_count] = ffr_best_rank(leader)
    represented_signatures[represented_count] = ffrda_structural_signature(leader)
    represented_count += 1
  i = 0
  while i < anchors.size()
    represented_ranks[represented_count] = ffr_best_rank(anchors[i])
    represented_signatures[represented_count] = ffrda_structural_signature(anchors[i])
    represented_count += 1
    i += 1
  i = 0
  while i < selected.size()
    represented_ranks[represented_count] = ffr_best_rank(selected[i])
    represented_signatures[represented_count] = ffrda_structural_signature(selected[i])
    represented_count += 1
    i += 1

  delta = 0 ## i64
  while delta <= 2 && selected.size() < limit
    chosen = ffrda_farthest_structural_index_anchored(candidates, candidate_signatures, leader, anchors, selected, represented_ranks, represented_signatures, represented_count, delta, 1) ## i64
    if chosen < 0
      chosen = ffrda_farthest_structural_index_anchored(candidates, candidate_signatures, leader, anchors, selected, represented_ranks, represented_signatures, represented_count, delta, 0)
    if chosen >= 0
      selected.push(candidates[chosen])
      represented_ranks[represented_count] = ffr_best_rank(candidates[chosen])
      represented_signatures[represented_count] = candidate_signatures[chosen]
      represented_count += 1
    delta += 1
  while selected.size() < limit
    chosen = ffrda_farthest_structural_index_anchored(candidates, candidate_signatures, leader, anchors, selected, represented_ranks, represented_signatures, represented_count, 0 - 1, 1) ## i64
    if chosen < 0
      chosen = ffrda_farthest_structural_index_anchored(candidates, candidate_signatures, leader, anchors, selected, represented_ranks, represented_signatures, represented_count, 0 - 1, 0)
    if chosen < 0
      return selected.size()
    selected.push(candidates[chosen])
    represented_ranks[represented_count] = ffr_best_rank(candidates[chosen])
    represented_signatures[represented_count] = candidate_signatures[chosen]
    represented_count += 1
  selected.size()

-> ffrda_select_diverse(candidates, leader, capacity_limit, selected) i64
  anchors = []
  ffrda_select_diverse_anchored(candidates, leader, anchors, capacity_limit, selected)

# stats: loaded, rejected, saved, write-failures.
-> ffrda_load_anchored(best_path, leader, anchors, n, m, p, capacity, seed_base, dslack, cycles, workq, wanderq, bank, stats) i64
  slot = 0 ## i64
  while slot < ffrda_cap()
    path = ffrda_path(best_path, slot)
    body = read_file(path)
    if body != nil && body.size() > 0
      candidate = i64[ffr_state_size(capacity)]
      rank = ffr_load_scheme_cap(candidate, path, n, m, p, capacity, seed_base + slot * 131, dslack, cycles, workq, wanderq) ## i64
      action = 0 - 1 ## i64
      if rank > 0
        if ffrda_already_selected(anchors, candidate) == 1
          action = 0
        if ffrda_already_selected(anchors, candidate) == 0
          action = ffrda_add_unique(bank, candidate, leader, ffrda_cap(), n, m, p)
      if action == 1
        stats[0] += 1
      if action != 1
        stats[1] += 1
    slot += 1
  bank.size()

-> ffrda_load(best_path, leader, n, m, p, capacity, seed_base, dslack, cycles, workq, wanderq, bank, stats) i64
  anchors = []
  ffrda_load_anchored(best_path, leader, anchors, n, m, p, capacity, seed_base, dslack, cycles, workq, wanderq, bank, stats)

-> ffrda_save(best_path, bank, run_tag, nonce, stats) i64
  slot = 0 ## i64
  while slot < ffrda_cap()
    path = ffrda_path(best_path, slot)
    ok = 1 ## i64
    if slot < bank.size()
      rank = ffrda_dump_atomic(bank[slot], path, run_tag + "-side", nonce + slot) ## i64
      if rank < 1
        ok = 0
      if rank > 0
        stats[2] += 1
    if slot >= bank.size()
      old = read_file(path)
      if old != nil && old.size() > 0
        ok = ffrda_atomic_write(path, "", run_tag + "-side-clear", nonce + slot)
    if ok == 0
      stats[3] += 1
    slot += 1
  stats[2]

# Persist a barrier-stable view of the live island bests without changing any
# island.  Existing disk slots and the startup bank participate in the same
# anchored max-min selection, so a periodic checkpoint cannot accidentally
# forget an older basin merely because its original island was later rebased.
# Every disk input is reconstructed and every output is independently gated by
# ffr_dump_best before the atomic rename.  Return the selected door count, or
# -1 only when a write failed; malformed candidates are counted and skipped.
-> ffrda_checkpoint_live(best_path, leader, anchors, states, prior, n, m, p, capacity, seed_base, dslack, cycles, workq, wanderq, run_tag, nonce, stats)
  disk = []
  load_stats = i64[4]
  z = ffrda_load_anchored(best_path, leader, anchors, n, m, p, capacity, seed_base, dslack, cycles, workq, wanderq, disk, load_stats) ## i64
  stats[1] += load_stats[1]
  candidates = []
  i = 0 ## i64
  while i < prior.size()
    action = ffrda_collect_unique(candidates, prior[i], leader, n, m, p) ## i64
    if action < 0
      stats[1] += 1
    i += 1
  i = 0
  while i < disk.size()
    action = ffrda_collect_unique(candidates, disk[i], leader, n, m, p)
    if action < 0
      stats[1] += 1
    i += 1
  i = 0
  while i < states.size()
    action = ffrda_collect_unique(candidates, states[i], leader, n, m, p)
    if action < 0
      stats[1] += 1
    i += 1
  selected = []
  z = ffrda_select_diverse_anchored(candidates, leader, anchors, ffrda_cap(), selected)
  failures_before = stats[3] ## i64
  z = ffrda_save(best_path, selected, run_tag, nonce, stats)
  if stats[3] != failures_before
    return 0 - 1
  selected.size()

# Physically invalidate every side slot before publishing a naive checkpoint.
# A reset must remain self-contained across process restarts; an in-memory
# "do not load" flag cannot be the only barrier against stale knowledge.
-> ffrda_clear(best_path, run_tag, nonce) (String String i64) i64
  # Write every empty slot even when read_file cannot inspect the old path.
  # Besides making the reset boundary explicit on disk, this turns a slot
  # that has become a directory or otherwise unwritable into a hard reset
  # failure instead of silently treating it as already empty.
  slot = 0 ## i64
  while slot < ffrda_cap()
    path = ffrda_path(best_path, slot)
    ok = ffrda_atomic_write(path, "", run_tag + "-clear", nonce + slot) ## i64
    if ok == 0
      return 0
    slot += 1
  1
