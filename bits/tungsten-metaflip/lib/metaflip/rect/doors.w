# Small persisted near-door archive for rectangular portfolio children.
#
# Four independent exact scheme files sit beside the durable best checkpoint.
# There is deliberately no manifest or mutable index: every slot is loaded
# through the full rectangular reconstruction gate, and every replacement is
# a temp-file + rename.  A partial process stop can therefore leave a mixture
# of old and new slots, but never an unverified seed.

use ../rect

-> ffrda_cap() i64
  4

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

# Exit collection must not inherit the four-slot persistence cap.  Admit every
# exact, distinct R..R+2 shoulder first; the selector below decides which four
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
# frontier doors that remain outside the four persisted slots. A negative
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

# Deterministic bounded diversity selection from an already exact/unique exit
# pool. First reserve one slot for every present rank band R, R+1, R+2; then
# fill remaining slots by farthest-first max-min distance from the leader,
# checked-in anchors, and all selected doors. The fixed band order plus
# canonical tie break makes contents and order independent of arrival order.
-> ffrda_select_diverse_anchored(candidates, leader, anchors, capacity_limit, selected) i64
  limit = capacity_limit ## i64
  if limit < 0
    limit = 0
  delta = 0 ## i64
  while delta <= 2 && selected.size() < limit
    chosen = ffrda_farthest_index_anchored(candidates, leader, anchors, selected, delta) ## i64
    if chosen >= 0
      selected.push(candidates[chosen])
    delta += 1
  while selected.size() < limit
    chosen = ffrda_farthest_index_anchored(candidates, leader, anchors, selected, 0 - 1) ## i64
    if chosen < 0
      return selected.size()
    selected.push(candidates[chosen])
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
