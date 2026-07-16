# Shared in-process incremental CDCL SAT solver for FlipFleet SAT lanes.
#
# The existing SAT stack (flipfleet_sat_destroy_repair) is one-shot: it
# formats DIMACS text, spawns an external solver per query, and re-encodes the
# whole window every attempt.  Five planned SAT lanes hammering short epochs
# pay process + string + re-encode costs on every query and cannot narrow
# incrementally.  This module is the in-process replacement surface: a
# conflict-driven clause-learning solver over one flat i64[] state, with
# two-watched-literal propagation, first-UIP learning with backjumping,
# integer VSIDS activities with phase saving, Luby restarts, assumption
# solving with failed-assumption core extraction, conflict budgets instead of
# wall clocks, and clause-mark push/pop for reusable Brent skeletons.
#
# ABI (all functions are free functions over the state array):
#   ffcdcl_state_size(max_vars, max_clause_words) -> words to allocate
#   ffcdcl_init(st, max_vars, seed)               -> 1 ok / 0 bad plan
#   ffcdcl_add_clause(st, lits, count)            -> 1 ok / 0 immediate
#                        top-level conflict (empty clause) / <0 malformed or
#                        arena exhausted (-2 arena, -3 malformed literal)
#   ffcdcl_add_xor(st, vars, count, rhs)          -> same codes; Tseitin
#                        chains allocate fresh aux variables (see below)
#   ffcdcl_solve(st, assumptions, count, budget)  -> 1 SAT / -1 UNSAT /
#                        -2 conflict budget or clause arena exhausted /
#                        -3 malformed input.  budget < 1 means unlimited.
#   ffcdcl_value(st, var)                         -> 1/0 (valid after SAT,
#                        until the next add/solve/reset/release call)
#   ffcdcl_failed_assumptions(st, out_vars, cap)  -> core size; copies the
#                        subset of assumption VARS in the final conflict
#   ffcdcl_reset(st)                              -> clears trail/assignments,
#                        keeps the clause DB, learnt clauses and activities
#   ffcdcl_mark(st) / ffcdcl_release(st, mark)    -> clause-DB push/pop
#
# Literal encoding: variables are 1-based (1..max_vars).  Positive literal of
# var v is 2*v, negated literal is 2*v + 1; negation is lit ^ 1.
#
# Aux-variable policy for ffcdcl_add_xor: an XOR of arity m >= 3 allocates
# m - 2 fresh auxiliary variables directly above the highest variable
# referenced so far (including the XOR's own vars).  Callers must size
# max_vars with that headroom and should reference their own variables (via
# clauses or the XOR itself) before relying on where aux vars land.
#
# Mark/release limitations (deactivate-by-flag implementation): release
# deactivates every clause stored at or after the mark, including learnt
# clauses derived after that point (arena order is derivation order, so any
# learnt clause stored before the mark is implied by pre-mark clauses only
# and is sound to keep).  Arena words of released clauses are NOT reclaimed;
# released clauses are unlinked from watch lists lazily during propagation.
# A mark must be a value previously returned by ffcdcl_mark.
#
# Header slots:
#   0 magic 1179010884 ("FFCD")   1 version        2 max_vars
#   3 arena capacity (words)      4 top_var        5 arena_used
#   6 stored clauses              7 trail size     8 qhead
#   9 decision level             10 rng state     11 reserved
#  12 lifetime conflicts         13 var activity increment
#  14 lifetime restarts          15 last solve status
#  16 heap size                  17 failed-assumption core size
#  18 learnt clauses             19 propagations  20 decisions
#  21 conflicts in current solve 22 assumption count
#  23 analyze scratch size       24 solve calls
#  32..46 region offsets: assign level reason activity phase seen heappos
#  heap trail traillim watch analyze core assume arena
#
# Clause layout in the arena (absolute st index c):
#   st[c] = size, st[c+1] = flags (bit0 learnt, bit1 released),
#   st[c+2]/st[c+3] = next-watcher refs for watch slots 0/1 (ref encoding
#   c*2 + slot, 0-1 terminates), st[c+4..] = literals.  Positions 0 and 1
#   are the watched literals for size >= 2; size-1 clauses are re-enqueued
#   from an arena scan at every solve start, so root units survive reset and
#   release without a separate unit list.

-> ffcdcl_state_size(max_vars, max_clause_words) (i64 i64) i64
  if max_vars < 1 || max_clause_words < 1
    return 0
  64 + (max_vars + 1) * 12 + (max_vars + 2) + (2 * max_vars + 2) + max_clause_words

-> ffcdcl_valid(st) (i64[]) i64
  if st.size() < 96
    return 0
  if st[0] != 1179010884 || st[1] != 1 || st[2] < 1
    return 0
  1

-> ffcdcl_next_random(st) (i64[]) i64
  st[10] = (st[10] * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
  st[10]

# --- variable order heap (max activity on top) ---

-> ffcdcl_heap_swap(st, a, b) (i64[] i64 i64) i64
  heap = st[39] ## i64
  pos = st[38] ## i64
  va = st[heap + a] ## i64
  vb = st[heap + b] ## i64
  st[heap + a] = vb
  st[heap + b] = va
  st[pos + va] = b
  st[pos + vb] = a
  1

-> ffcdcl_heap_up(st, index) (i64[] i64) i64
  heap = st[39] ## i64
  act = st[35] ## i64
  i = index ## i64
  while i > 0
    parent = (i - 1) / 2 ## i64
    if st[act + st[heap + i]] <= st[act + st[heap + parent]]
      return i
    z = ffcdcl_heap_swap(st, i, parent) ## i64
    i = parent
  i

-> ffcdcl_heap_down(st, index) (i64[] i64) i64
  heap = st[39] ## i64
  act = st[35] ## i64
  i = index ## i64
  while 0 < 1
    left = 2 * i + 1 ## i64
    if left >= st[16]
      return i
    best = left ## i64
    right = left + 1 ## i64
    if right < st[16] && st[act + st[heap + right]] > st[act + st[heap + left]]
      best = right
    if st[act + st[heap + best]] <= st[act + st[heap + i]]
      return i
    z = ffcdcl_heap_swap(st, i, best) ## i64
    i = best

-> ffcdcl_heap_insert(st, v) (i64[] i64) i64
  if st[st[38] + v] >= 0
    return 0
  index = st[16] ## i64
  st[st[39] + index] = v
  st[st[38] + v] = index
  st[16] = index + 1
  z = ffcdcl_heap_up(st, index) ## i64
  1

-> ffcdcl_heap_pop(st) (i64[]) i64
  size = st[16] ## i64
  if size < 1
    return 0
  heap = st[39] ## i64
  pos = st[38] ## i64
  top = st[heap] ## i64
  last = st[heap + size - 1] ## i64
  st[16] = size - 1
  st[pos + top] = 0 - 1
  if size > 1
    st[heap] = last
    st[pos + last] = 0
    z = ffcdcl_heap_down(st, 0) ## i64
  top

-> ffcdcl_rescale(st) (i64[]) i64
  act = st[35] ## i64
  v = 1 ## i64
  while v <= st[2]
    st[act + v] = st[act + v] >> 32
    v += 1
  st[13] = st[13] >> 32
  if st[13] < 32
    st[13] = 32
  1

-> ffcdcl_bump(st, v) (i64[] i64) i64
  act = st[35] ## i64
  st[act + v] = st[act + v] + st[13]
  if st[act + v] > 4503599627370496
    z = ffcdcl_rescale(st) ## i64
  if st[st[38] + v] >= 0
    z = ffcdcl_heap_up(st, st[st[38] + v]) ## i64
  1

-> ffcdcl_init(st, max_vars, seed) (i64[] i64 i64) i64
  if max_vars < 1
    return 0
  fixed = 64 + (max_vars + 1) * 12 + (max_vars + 2) + (2 * max_vars + 2) ## i64
  if st.size() < fixed + 16
    return 0
  total = st.size() ## i64
  i = 0 ## i64
  while i < total
    st[i] = 0
    i += 1
  st[0] = 1179010884
  st[1] = 1
  st[2] = max_vars
  st[3] = total - fixed
  st[10] = (seed & 9223372036854775807) | 1
  st[13] = 32
  st[32] = 64
  st[33] = st[32] + max_vars + 1
  st[34] = st[33] + max_vars + 1
  st[35] = st[34] + max_vars + 1
  st[36] = st[35] + max_vars + 1
  st[37] = st[36] + max_vars + 1
  st[38] = st[37] + max_vars + 1
  st[39] = st[38] + max_vars + 1
  st[40] = st[39] + max_vars + 1
  st[41] = st[40] + max_vars + 1
  st[42] = st[41] + max_vars + 2
  st[43] = st[42] + 2 * max_vars + 2
  st[44] = st[43] + max_vars + 1
  st[45] = st[44] + max_vars + 1
  st[46] = st[45] + max_vars + 1
  i = 0
  while i < 2 * max_vars + 2
    st[st[42] + i] = 0 - 1
    i += 1
  v = 1 ## i64
  while v <= max_vars
    st[st[34] + v] = 0 - 1
    st[st[38] + v] = 0 - 1
    st[st[35] + v] = ffcdcl_next_random(st) % 16
    v += 1
  v = 1
  while v <= max_vars
    z = ffcdcl_heap_insert(st, v) ## i64
    v += 1
  1

# --- assignment / trail ---

-> ffcdcl_lit_value(st, lit) (i64[] i64) i64
  a = st[st[32] + lit / 2] ## i64
  if a == 0
    return 0
  if (lit & 1) == 0
    return a
  3 - a

-> ffcdcl_enqueue(st, lit, reason) (i64[] i64 i64) i64
  v = lit / 2 ## i64
  st[st[32] + v] = 2 - (lit & 1)
  st[st[33] + v] = st[9]
  st[st[34] + v] = reason
  st[st[40] + st[7]] = lit
  st[7] = st[7] + 1
  1

-> ffcdcl_cancel_until(st, lvl) (i64[] i64) i64
  if st[9] <= lvl
    return 1
  bound = st[st[41] + lvl] ## i64
  i = st[7] - 1 ## i64
  while i >= bound
    lit = st[st[40] + i] ## i64
    v = lit / 2 ## i64
    st[st[36] + v] = 1 - (lit & 1)
    st[st[32] + v] = 0
    st[st[34] + v] = 0 - 1
    if st[st[38] + v] < 0
      z = ffcdcl_heap_insert(st, v) ## i64
    i -= 1
  st[7] = bound
  st[8] = bound
  st[9] = lvl
  1

-> ffcdcl_clear_trail(st) (i64[]) i64
  i = st[7] - 1 ## i64
  while i >= 0
    lit = st[st[40] + i] ## i64
    v = lit / 2 ## i64
    st[st[36] + v] = 1 - (lit & 1)
    st[st[32] + v] = 0
    st[st[34] + v] = 0 - 1
    if st[st[38] + v] < 0
      z = ffcdcl_heap_insert(st, v) ## i64
    i -= 1
  st[7] = 0
  st[8] = 0
  st[9] = 0
  1

# --- clause storage + watches ---

-> ffcdcl_attach(st, c) (i64[] i64) i64
  wh = st[42] ## i64
  lit0 = st[c + 4] ## i64
  st[c + 2] = st[wh + lit0]
  st[wh + lit0] = c * 2
  lit1 = st[c + 5] ## i64
  st[c + 3] = st[wh + lit1]
  st[wh + lit1] = c * 2 + 1
  1

# source may be st itself (learnt clauses are staged in the analyze region).
-> ffcdcl_store(st, source, offset, count, learnt) (i64[] i64[] i64 i64 i64) i64
  need = 4 + count ## i64
  if st[5] + need > st[3]
    return 0 - 1
  c = st[46] + st[5] ## i64
  st[5] = st[5] + need
  st[c] = count
  st[c + 1] = learnt
  st[c + 2] = 0 - 1
  st[c + 3] = 0 - 1
  i = 0 ## i64
  while i < count
    lit = source[offset + i] ## i64
    st[c + 4 + i] = lit
    if lit / 2 > st[4]
      st[4] = lit / 2
    i += 1
  st[6] = st[6] + 1
  if learnt == 1
    st[18] = st[18] + 1
  if count >= 2
    z = ffcdcl_attach(st, c) ## i64
  c

-> ffcdcl_add_clause_run(st, lits, offset, count) (i64[] i64[] i64 i64) i64
  if ffcdcl_valid(st) != 1 || count < 0
    return 0 - 3
  buf = st[43] ## i64
  m = 0 ## i64
  i = 0 ## i64
  while i < count
    lit = lits[offset + i] ## i64
    if lit < 2 || lit / 2 > st[2]
      return 0 - 3
    duplicate = 0 ## i64
    j = 0 ## i64
    while j < m
      if st[buf + j] == lit
        duplicate = 1
      if st[buf + j] == (lit ^ 1)
        duplicate = 2
      j += 1
    if duplicate == 2
      return 1
    if duplicate == 0
      st[buf + m] = lit
      m += 1
    i += 1
  c = ffcdcl_store(st, st, buf, m, 0) ## i64
  if c < 0
    return 0 - 2
  if m == 0
    return 0
  1

-> ffcdcl_add_clause(st, lits, count) (i64[] i64[] i64) i64
  ffcdcl_add_clause_run(st, lits, 0, count)

# Consume a (len, lit...) run buffer, e.g. from ffsdr_emit_clauses.
-> ffcdcl_add_runs(st, runs, words) (i64[] i64[] i64) i64
  i = 0 ## i64
  while i < words
    len = runs[i] ## i64
    if len < 0 || i + 1 + len > words
      return 0 - 3
    r = ffcdcl_add_clause_run(st, runs, i + 1, len) ## i64
    if r < 1
      return r
    i = i + 1 + len
  1

# --- XOR ingestion (Tseitin chains; see aux policy in the header) ---

-> ffcdcl_add_xor2(st, a, b, rhs) (i64[] i64 i64 i64) i64
  pair = i64[2]
  if rhs == 1
    pair[0] = 2 * a
    pair[1] = 2 * b
    r = ffcdcl_add_clause(st, pair, 2) ## i64
    if r < 1
      return r
    pair[0] = 2 * a + 1
    pair[1] = 2 * b + 1
    return ffcdcl_add_clause(st, pair, 2)
  pair[0] = 2 * a
  pair[1] = 2 * b + 1
  r = ffcdcl_add_clause(st, pair, 2) ## i64
  if r < 1
    return r
  pair[0] = 2 * a + 1
  pair[1] = 2 * b
  ffcdcl_add_clause(st, pair, 2)

# t = a ^ b: forbid the four odd-parity assignments of a ^ b ^ t.
-> ffcdcl_add_xor3(st, a, b, t) (i64[] i64 i64 i64) i64
  triple = i64[3]
  triple[0] = 2 * a + 1
  triple[1] = 2 * b
  triple[2] = 2 * t
  r = ffcdcl_add_clause(st, triple, 3) ## i64
  if r < 1
    return r
  triple[0] = 2 * a
  triple[1] = 2 * b + 1
  triple[2] = 2 * t
  r = ffcdcl_add_clause(st, triple, 3)
  if r < 1
    return r
  triple[0] = 2 * a
  triple[1] = 2 * b
  triple[2] = 2 * t + 1
  r = ffcdcl_add_clause(st, triple, 3)
  if r < 1
    return r
  triple[0] = 2 * a + 1
  triple[1] = 2 * b + 1
  triple[2] = 2 * t + 1
  ffcdcl_add_clause(st, triple, 3)

-> ffcdcl_add_xor(st, vars, count, rhs) (i64[] i64[] i64 i64) i64
  if ffcdcl_valid(st) != 1 || count < 0 || rhs < 0 || rhs > 1
    return 0 - 3
  i = 0 ## i64
  while i < count
    if vars[i] < 1 || vars[i] > st[2]
      return 0 - 3
    if vars[i] > st[4]
      st[4] = vars[i]
    i += 1
  if count == 0
    if rhs == 0
      return 1
    empty = i64[1]
    return ffcdcl_add_clause(st, empty, 0)
  if count == 1
    unit = i64[1]
    unit[0] = 2 * vars[0] + 1 - rhs
    return ffcdcl_add_clause(st, unit, 1)
  if count == 2
    return ffcdcl_add_xor2(st, vars[0], vars[1], rhs)
  acc = vars[0] ## i64
  i = 1
  while i < count - 1
    aux = st[4] + 1 ## i64
    if aux > st[2]
      return 0 - 2
    st[4] = aux
    r = ffcdcl_add_xor3(st, acc, vars[i], aux) ## i64
    if r < 1
      return r
    acc = aux
    i += 1
  ffcdcl_add_xor2(st, acc, vars[count - 1], rhs)

# --- propagation ---

# Returns the conflicting clause offset, or -1 when the queue drains cleanly.
-> ffcdcl_propagate(st) (i64[]) i64
  wh = st[42] ## i64
  while st[8] < st[7]
    p = st[st[40] + st[8]] ## i64
    st[8] = st[8] + 1
    st[19] = st[19] + 1
    fl = p ^ 1 ## i64
    prev = 0 - 1 ## i64
    ref = st[wh + fl] ## i64
    while ref >= 0
      c = ref / 2 ## i64
      slot = ref % 2 ## i64
      nxt = st[c + 2 + slot] ## i64
      if (st[c + 1] & 2) != 0
        # released clause: unlink lazily
        if prev < 0
          st[wh + fl] = nxt
        else
          st[prev / 2 + 2 + (prev % 2)] = nxt
        ref = nxt
      else
        other = st[c + 4 + (1 - slot)] ## i64
        oval = ffcdcl_lit_value(st, other) ## i64
        if oval == 2
          prev = ref
          ref = nxt
        else
          size = st[c] ## i64
          found = 0 ## i64
          i = 2 ## i64
          while found == 0 && i < size
            q = st[c + 4 + i] ## i64
            if ffcdcl_lit_value(st, q) != 1
              st[c + 4 + slot] = q
              st[c + 4 + i] = fl
              if prev < 0
                st[wh + fl] = nxt
              else
                st[prev / 2 + 2 + (prev % 2)] = nxt
              st[c + 2 + slot] = st[wh + q]
              st[wh + q] = ref
              found = 1
            i += 1
          if found == 1
            ref = nxt
          else
            if oval == 1
              return c
            z = ffcdcl_enqueue(st, other, c) ## i64
            prev = ref
            ref = nxt
  0 - 1

# --- first-UIP conflict analysis ---

# Fills the analyze region with the learnt clause (asserting literal first,
# highest-level remaining literal second), sets st[23] to its size, and
# returns the backjump level.
-> ffcdcl_analyze(st, confl) (i64[] i64) i64
  seen = st[37] ## i64
  levels = st[33] ## i64
  reasons = st[34] ## i64
  trail = st[40] ## i64
  buf = st[43] ## i64
  current = st[9] ## i64
  learnt_size = 1 ## i64
  pathc = 0 ## i64
  p = 0 - 1 ## i64
  index = st[7] - 1 ## i64
  c = confl ## i64
  going = 1 ## i64
  while going == 1
    size = st[c] ## i64
    i = 0 ## i64
    while i < size
      q = st[c + 4 + i] ## i64
      if p < 0 || q != p
        vq = q / 2 ## i64
        if st[seen + vq] == 0 && st[levels + vq] > 0
          st[seen + vq] = 1
          z = ffcdcl_bump(st, vq) ## i64
          if st[levels + vq] >= current
            pathc += 1
          else
            st[buf + learnt_size] = q
            learnt_size += 1
      i += 1
    while st[seen + st[trail + index] / 2] == 0
      index -= 1
    p = st[trail + index]
    index -= 1
    st[seen + p / 2] = 0
    c = st[reasons + p / 2]
    pathc -= 1
    if pathc < 1
      going = 0
  st[buf] = p ^ 1
  st[23] = learnt_size
  if learnt_size == 1
    return 0
  max_i = 1 ## i64
  i = 2 ## i64
  while i < learnt_size
    if st[levels + st[buf + i] / 2] > st[levels + st[buf + max_i] / 2]
      max_i = i
    i += 1
  swap = st[buf + 1] ## i64
  st[buf + 1] = st[buf + max_i]
  st[buf + max_i] = swap
  bt = st[levels + st[buf + 1] / 2] ## i64
  i = 1
  while i < learnt_size
    st[seen + st[buf + i] / 2] = 0
    i += 1
  bt

# Assumption-core extraction (MiniSat analyzeFinal): p is the assumption
# literal found false.  Fills the core region with assumption VARS.
-> ffcdcl_analyze_final(st, p) (i64[] i64) i64
  seen = st[37] ## i64
  levels = st[33] ## i64
  reasons = st[34] ## i64
  trail = st[40] ## i64
  core = st[44] ## i64
  count = 0 ## i64
  st[core + count] = p / 2
  count += 1
  if st[9] > 0
    st[seen + p / 2] = 1
    bound = st[st[41]] ## i64
    i = st[7] - 1 ## i64
    while i >= bound
      lit = st[trail + i] ## i64
      v = lit / 2 ## i64
      if st[seen + v] == 1
        r = st[reasons + v] ## i64
        if r < 0
          already = 0 ## i64
          j = 0 ## i64
          while j < count
            if st[core + j] == v
              already = 1
            j += 1
          if already == 0
            st[core + count] = v
            count += 1
        else
          size = st[r] ## i64
          j = 0
          while j < size
            q = st[r + 4 + j] ## i64
            if st[levels + q / 2] > 0
              st[seen + q / 2] = 1
            j += 1
        st[seen + v] = 0
      i -= 1
    st[seen + p / 2] = 0
  st[17] = count
  count

# --- search ---

-> ffcdcl_luby(index) (i64) i64
  i = index ## i64
  while 0 < 1
    k = 1 ## i64
    while ((1 << k) - 1) < i
      k += 1
    if ((1 << k) - 1) == i
      return 1 << (k - 1)
    i = i - ((1 << (k - 1)) - 1)

# One restart round.  Returns 1 SAT / -1 UNSAT / -2 budget or arena
# exhausted / 0 restart requested.
-> ffcdcl_search(st, restart_limit, budget) (i64[] i64 i64) i64
  local = 0 ## i64
  while 0 < 1
    confl = ffcdcl_propagate(st) ## i64
    if confl >= 0
      st[12] = st[12] + 1
      st[21] = st[21] + 1
      local += 1
      if st[9] == 0
        st[17] = 0
        return 0 - 1
      bt = ffcdcl_analyze(st, confl) ## i64
      z = ffcdcl_cancel_until(st, bt) ## i64
      c = ffcdcl_store(st, st, st[43], st[23], 1) ## i64
      if c < 0
        return 0 - 2
      z = ffcdcl_enqueue(st, st[st[43]], c)
      st[13] = st[13] + st[13] / 16
      if budget > 0 && st[21] >= budget
        return 0 - 2
      if local >= restart_limit
        st[14] = st[14] + 1
        z = ffcdcl_cancel_until(st, 0)
        return 0
    else
      if st[9] < st[22]
        # establish the next assumption on its own level
        p = st[st[45] + st[9]] ## i64
        pv = ffcdcl_lit_value(st, p) ## i64
        if pv == 1
          z = ffcdcl_analyze_final(st, p) ## i64
          return 0 - 1
        st[st[41] + st[9]] = st[7]
        st[9] = st[9] + 1
        if pv == 0
          z = ffcdcl_enqueue(st, p, 0 - 1)
      else
        v = 0 ## i64
        while v == 0 && st[16] > 0
          cand = ffcdcl_heap_pop(st) ## i64
          if cand > 0 && st[st[32] + cand] == 0
            v = cand
        if v == 0
          return 1
        st[20] = st[20] + 1
        st[st[41] + st[9]] = st[7]
        st[9] = st[9] + 1
        z = ffcdcl_enqueue(st, 2 * v + 1 - st[st[36] + v], 0 - 1)

-> ffcdcl_solve(st, assumptions, count, conflict_budget) (i64[] i64[] i64 i64) i64
  if ffcdcl_valid(st) != 1 || count < 0 || count > st[2]
    return 0 - 3
  z = ffcdcl_clear_trail(st) ## i64
  st[15] = 0
  st[17] = 0
  st[21] = 0
  st[22] = 0
  st[24] = st[24] + 1
  i = 0 ## i64
  while i < count
    lit = assumptions[i] ## i64
    if lit < 2 || lit / 2 > st[2]
      return 0 - 3
    st[st[45] + i] = lit
    i += 1
  st[22] = count
  # Re-enqueue root facts from the arena (units survive reset/release here).
  base = st[46] ## i64
  off = 0 ## i64
  while off < st[5]
    c = base + off ## i64
    size = st[c] ## i64
    if (st[c + 1] & 2) == 0
      if size == 0
        st[15] = 0 - 1
        return 0 - 1
      if size == 1
        lv = ffcdcl_lit_value(st, st[c + 4]) ## i64
        if lv == 1
          st[15] = 0 - 1
          return 0 - 1
        if lv == 0
          z = ffcdcl_enqueue(st, st[c + 4], c)
    off = off + 4 + size
  status = 0 ## i64
  round = 1 ## i64
  while status == 0
    status = ffcdcl_search(st, ffcdcl_luby(round) * 256, conflict_budget)
    round += 1
  if status != 1
    z = ffcdcl_cancel_until(st, 0)
  st[15] = status
  status

# --- results ---

-> ffcdcl_value(st, v) (i64[] i64) i64
  if v < 1 || v > st[2]
    return 0
  if st[st[32] + v] == 2
    return 1
  0

-> ffcdcl_failed_assumptions(st, out_vars, capacity) (i64[] i64[] i64) i64
  count = st[17] ## i64
  i = 0 ## i64
  while i < count && i < capacity
    out_vars[i] = st[st[44] + i]
    i += 1
  count

# --- reuse across attempts ---

-> ffcdcl_reset(st) (i64[]) i64
  if ffcdcl_valid(st) != 1
    return 0
  z = ffcdcl_clear_trail(st) ## i64
  st[15] = 0
  st[17] = 0
  st[21] = 0
  st[22] = 0
  1

-> ffcdcl_mark(st) (i64[]) i64
  if ffcdcl_valid(st) != 1
    return 0 - 1
  st[5]

-> ffcdcl_release(st, mark) (i64[] i64) i64
  if ffcdcl_valid(st) != 1 || mark < 0 || mark > st[5]
    return 0
  base = st[46] ## i64
  off = 0 ## i64
  while off < mark
    off = off + 4 + st[base + off]
  if off != mark
    return 0
  while off < st[5]
    c = base + off ## i64
    st[c + 1] = st[c + 1] | 2
    off = off + 4 + st[c]
  z = ffcdcl_clear_trail(st) ## i64
  st[15] = 0
  st[17] = 0
  st[22] = 0
  1

# --- telemetry accessors ---

-> ffcdcl_top_var(st) (i64[]) i64
  st[4]

-> ffcdcl_conflicts(st) (i64[]) i64
  st[21]

-> ffcdcl_clause_count(st) (i64[]) i64
  st[6]

-> ffcdcl_learnt_count(st) (i64[]) i64
  st[18]

# Dump the ROOT clause database (learnt and released clauses excluded) as
# plain DIMACS for an external industrial solver (cross-checking verdicts
# and attacking cells that outgrow the in-process arena).  XOR rows were
# Tseitin-encoded at ingestion, so plain DIMACS is exact.  Returns the
# clause count written, or -1 on I/O failure.
-> ffcdcl_dump_dimacs(st, path) (i64[] String) i64
  base = st[46] ## i64
  used = st[5] ## i64
  body = "" ## String
  chunk = "" ## String
  in_chunk = 0 ## i64
  count = 0 ## i64
  c = base ## i64
  while c < base + used
    size = st[c] ## i64
    flags = st[c + 1] ## i64
    if (flags & 3) == 0
      line = "" ## String
      i = 0 ## i64
      while i < size
        lit = st[c + 4 + i] ## i64
        v = lit / 2 ## i64
        if (lit & 1) == 1
          line = line + "-"
        line = line + v.to_s() + " "
        i += 1
      chunk = chunk + line + "0\n"
      in_chunk += 1
      count += 1
      if in_chunk >= 256
        body = body + chunk
        chunk = ""
        in_chunk = 0
    c = c + 4 + size
  if in_chunk > 0
    body = body + chunk
  header = "p cnf " + st[4].to_s() + " " + count.to_s() + "\n" ## String
  if write_file(path, header + body)
    return count
  0 - 1
