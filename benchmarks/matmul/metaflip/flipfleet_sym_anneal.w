# Symmetry-defect annealed walk (move 9 intake).
#
# Walker state = (exact GF(2) scheme, lock pattern).  Live terms are
# partitioned into LOCKED C3-orbits — triples closed under the campaign's
# cyclic axis rotation rho(u, v, w) = (v, transpose(w), transpose(u))
# (the ffbi_transform_term / ffe_is_c3 convention, rho^3 = identity) —
# plus FREE terms.  Locked orbits move only as wholes: the representative
# move is replicated through rho and rho^2, which keeps every edge an exact
# tensor identity because rho is an automorphism of the matmul tensor and a
# toggle list T ++ rho(T) ++ rho^2(T) has tensor-zero content whenever T does.
# Toggle collisions (an image annihilating an existing term) are legal over
# GF(2) and auto-unlock any locked orbit they touch, so the invariant
# "every locked orbit is exactly rho-closed" holds at all times.
#
# Edges:
#   free flip / free split      ordinary walker moves restricted to FREE terms
#   orbit-flip / orbit-split    representative move replicated through rho;
#                               orbit-reduction emerges when a replicated
#                               flip factor vanishes or an image annihilates
#   UNLOCK                      dissolve one locked orbit into free terms
#                               (bookkeeping only, rank-neutral, always legal)
#   LOCK                        bind 3 free terms forming an exact rho-orbit
#                               (verified exactly); fixed cubes (u, u, u^T
#                               with u = u^T, i.e. rho(t) = t) become
#                               singleton locked orbits
#   repair-LOCK                 bind a NEAR-orbit triple by toggling in the
#                               bounded exact difference terms
#                               t2 + rho(t1) = (a2^a)xb2xc2 + ax(b2^b)xc2
#                                              + axbx(c2^c)  (GF(2) identity),
#                               budgeted as a rank +<=4 escape and counted
#                               separately (header cell 7)
#   singleton auto-unlock       any orbit move touching a fixed cube
#                               dissolves it first (the sym_gen2
#                               singleton-leakage lesson)
#
# Acceptance is lex(rank, density) with a per-representative density slack
# (scaled by the replication factor for orbit moves) and a best+band split
# allowance.  The anneal schedule raises the UNLOCK probability linearly over
# the walk and on stall (no accepted move for k_stall proposals).
#
# Admission contract: nothing leaves this lane without ffw_init_terms_cap +
# ffw_verify_best_exact on a fresh worker state; the engine additionally
# publishes via dump -> re-parse -> re-gate exactly like fffsp_run_engine.

use metaflip_worker
use flipfleet_escape

# ---------------------------------------------------------------------------
# State layout: one flat i64[] of size 32 + 7 * capacity.
#   header cells:
#     0 n            1 capacity      2 current rank   3 current density
#     4 next orbit id 5 rng state    6 density slack  7 repair corrections
#     8 best rank    9 best density 10 accepted      11 rejected
#    12 stall       13 band         14 orbit moves   15 free moves
#    16 unlocks     17 locks made   18 repair locks  19 singleton auto-unlocks
#    20 rank drops  21 collision auto-unlocks        22 gate failures
#    23 proposals   24 last replication factor       25 locked term count
#    26 best updates 27..31 reserved
#   arrays (each capacity words):
#     U at 32, V at 32+c, W at 32+2c, LOCK at 32+3c,
#     BEST U/V/W at 32+4c / 32+5c / 32+6c (dense 0..best_rank-1).

-> ffsa_state_size(capacity) (i64) i64
  32 + capacity * 7

-> ffsa_n(sa) (i64[]) i64
  sa[0]

-> ffsa_capacity(sa) (i64[]) i64
  sa[1]

-> ffsa_rank(sa) (i64[]) i64
  sa[2]

-> ffsa_density(sa) (i64[]) i64
  sa[3]

-> ffsa_best_rank(sa) (i64[]) i64
  sa[8]

-> ffsa_best_density(sa) (i64[]) i64
  sa[9]

-> ffsa_locked_terms(sa) (i64[]) i64
  sa[25]

-> ffsa_repair_spent(sa) (i64[]) i64
  sa[7]

-> ffsa_next(sa) (i64[]) i64
  value = (sa[5] * 6364136223846793005 + 1442695040888963407) & 9223372036854775807 ## i64
  sa[5] = value
  (value >> 32) & 2147483647

-> ffsa_term_bits(u, v, w) (i64 i64 i64) i64
  ffw_popcount(u) + ffw_popcount(v) + ffw_popcount(w)

-> ffsa_read_u(sa, index) (i64[] i64) i64
  sa[32 + index]

-> ffsa_read_v(sa, index) (i64[] i64) i64
  sa[32 + sa[1] + index]

-> ffsa_read_w(sa, index) (i64[] i64) i64
  sa[32 + sa[1] * 2 + index]

-> ffsa_read_lock(sa, index) (i64[] i64) i64
  sa[32 + sa[1] * 3 + index]

# Fixed cube = size-1 rho-orbit: rho(u,v,w) = (v, w^T, u^T) = (u,v,w).
-> ffsa_is_fixed(u, v, w, n) (i64 i64 i64 i64) i64
  ok = 0 ## i64
  if u == v
    if w == ffe_transpose(u, n)
      ok = 1
  ok

-> ffsa_find(sa, u, v, w) (i64[] i64 i64 i64) i64
  cap = sa[1] ## i64
  rank = sa[2] ## i64
  uo = 32 ## i64
  vo = uo + cap ## i64
  wo = vo + cap ## i64
  found = 0 - 1 ## i64
  i = 0 ## i64
  while i < rank
    if sa[uo + i] == u && sa[vo + i] == v && sa[wo + i] == w
      found = i
      i = rank
    else
      i += 1
  found

-> ffsa_orbit_size(sa, orbit) (i64[] i64) i64
  cap = sa[1] ## i64
  rank = sa[2] ## i64
  lo = 32 + cap * 3 ## i64
  count = 0 ## i64
  i = 0 ## i64
  while i < rank
    if sa[lo + i] == orbit
      count += 1
    i += 1
  count

# Dissolve one locked orbit into free terms.  Bookkeeping only.
-> ffsa_dissolve(sa, orbit) (i64[] i64) i64
  if orbit == 0
    return 0
  cap = sa[1] ## i64
  rank = sa[2] ## i64
  lo = 32 + cap * 3 ## i64
  freed = 0 ## i64
  i = 0 ## i64
  while i < rank
    if sa[lo + i] == orbit
      sa[lo + i] = 0
      freed += 1
    i += 1
  sa[25] = sa[25] - freed
  freed

# A toggle touched a locked term: the whole orbit unlocks first.
-> ffsa_auto_unlock(sa, orbit) (i64[] i64) i64
  freed = ffsa_dissolve(sa, orbit) ## i64
  sa[21] = sa[21] + 1
  if freed == 1
    sa[19] = sa[19] + 1
  freed

# XOR-toggle one term.  Removal swaps-with-last across all four parallel
# arrays; removal of a locked term auto-unlocks its orbit first.  Appended
# terms enter FREE.  Zero factors are no-ops.  Returns the new rank, or the
# negative sentinel -rank-1 when capacity is exhausted (caller must restore).
-> ffsa_toggle(sa, u, v, w) (i64[] i64 i64 i64) i64
  if u == 0 || v == 0 || w == 0
    return sa[2]
  cap = sa[1] ## i64
  uo = 32 ## i64
  vo = uo + cap ## i64
  wo = vo + cap ## i64
  lo = wo + cap ## i64
  idx = ffsa_find(sa, u, v, w) ## i64
  if idx >= 0
    g = sa[lo + idx] ## i64
    if g != 0
      z = ffsa_auto_unlock(sa, g)
    last = sa[2] - 1 ## i64
    sa[uo + idx] = sa[uo + last]
    sa[vo + idx] = sa[vo + last]
    sa[wo + idx] = sa[wo + last]
    sa[lo + idx] = sa[lo + last]
    sa[2] = last
    sa[3] = sa[3] - ffsa_term_bits(u, v, w)
    return last
  rank = sa[2] ## i64
  if rank >= cap
    return 0 - rank - 1
  sa[uo + rank] = u
  sa[vo + rank] = v
  sa[wo + rank] = w
  sa[lo + rank] = 0
  sa[2] = rank + 1
  sa[3] = sa[3] + ffsa_term_bits(u, v, w)
  rank + 1

# Apply a toggle program.  1 = applied; -1 = capacity sentinel hit mid-way
# (the state is a partial application — the caller MUST restore a snapshot).
-> ffsa_apply_program(sa, tu, tv, tw, count) (i64[] i64[] i64[] i64[] i64) i64
  ok = 1 ## i64
  i = 0 ## i64
  while i < count
    r = ffsa_toggle(sa, tu[i], tv[i], tw[i]) ## i64
    if r < 0
      ok = 0 - 1
      i = count
    else
      i += 1
  ok

# Append the rho and rho^2 images of program entries [0, count) in place;
# returns 3 * count.  Caller guarantees the arrays hold 3 * count entries.
-> ffsa_replicate_program(tu, tv, tw, count, n) (i64[] i64[] i64[] i64 i64) i64
  i = 0 ## i64
  while i < count
    u1 = tv[i] ## i64
    v1 = ffe_transpose(tw[i], n) ## i64
    w1 = ffe_transpose(tu[i], n) ## i64
    tu[count + i] = u1
    tv[count + i] = v1
    tw[count + i] = w1
    tu[count * 2 + i] = v1
    tv[count * 2 + i] = ffe_transpose(w1, n)
    tw[count * 2 + i] = ffe_transpose(u1, n)
    i += 1
  count * 3

# ---------------------------------------------------------------------------
# Construction / snapshots / export / gates

-> ffsa_init_terms(sa, us, vs, ws, rank, n, capacity, seed) (i64[] i64[] i64[] i64[] i64 i64 i64 i64) i64
  if n < 2 || n > 7 || rank < 1 || capacity < rank + 8 || sa.size() < ffsa_state_size(capacity)
    return 0 - 1
  limit = (1 << (n * n)) - 1 ## i64
  i = 0 ## i64
  while i < rank
    if us[i] < 1 || vs[i] < 1 || ws[i] < 1 || (us[i] & limit) != us[i] || (vs[i] & limit) != vs[i] || (ws[i] & limit) != ws[i]
      return 0 - 1
    j = i + 1 ## i64
    while j < rank
      if us[i] == us[j] && vs[i] == vs[j] && ws[i] == ws[j]
        return 0 - 1
      j += 1
    i += 1
  i = 0
  while i < 32
    sa[i] = 0
    i += 1
  sa[0] = n
  sa[1] = capacity
  sa[2] = rank
  sa[4] = 1
  sa[5] = (seed * 2862933555777941757 + 3037000493) & 9223372036854775807
  sa[6] = 2
  sa[13] = 4
  sa[24] = 1
  uo = 32 ## i64
  vo = uo + capacity ## i64
  wo = vo + capacity ## i64
  lo = wo + capacity ## i64
  bits = 0 ## i64
  i = 0
  while i < rank
    sa[uo + i] = us[i]
    sa[vo + i] = vs[i]
    sa[wo + i] = ws[i]
    sa[lo + i] = 0
    bits = bits + ffsa_term_bits(us[i], vs[i], ws[i])
    i += 1
  sa[3] = bits
  z = ffsa_adopt_best(sa)
  rank

-> ffsa_adopt_best(sa) (i64[]) i64
  cap = sa[1] ## i64
  rank = sa[2] ## i64
  uo = 32 ## i64
  vo = uo + cap ## i64
  wo = vo + cap ## i64
  buo = 32 + cap * 4 ## i64
  bvo = 32 + cap * 5 ## i64
  bwo = 32 + cap * 6 ## i64
  i = 0 ## i64
  while i < rank
    sa[buo + i] = sa[uo + i]
    sa[bvo + i] = sa[vo + i]
    sa[bwo + i] = sa[wo + i]
    i += 1
  sa[8] = rank
  sa[9] = sa[3]
  sa[26] = sa[26] + 1
  rank

# The naive scheme u = e_ik, v = e_kj, w = e_ij is C3-closed: rho maps the
# (i,k,j) term to the (k,j,i) term, so orbits are the n diagonal fixed cubes
# (i,i,i) plus (n^3 - n) / 3 three-term orbits.
-> ffsa_init_naive(sa, n, capacity, seed) (i64[] i64 i64 i64) i64
  count = n * n * n ## i64
  us = i64[count]
  vs = i64[count]
  ws = i64[count]
  t = 0 ## i64
  i = 0 ## i64
  while i < n
    k = 0 ## i64
    while k < n
      j = 0 ## i64
      while j < n
        us[t] = 1 << (i * n + k)
        vs[t] = 1 << (k * n + j)
        ws[t] = 1 << (i * n + j)
        t += 1
        j += 1
      k += 1
    i += 1
  ffsa_init_terms(sa, us, vs, ws, count, n, capacity, seed)

# Snapshot / restore for propose-then-decide.  Only state-coupled cells are
# restored (rank, density, next orbit id, locked count) so a rejected move
# never rewinds the RNG (which would re-propose the same rejected move
# forever) and telemetry counters stay live.
-> ffsa_snapshot(sa, snap) (i64[] i64[]) i64
  cap = sa[1] ## i64
  rank = sa[2] ## i64
  i = 0 ## i64
  while i < 32
    snap[i] = sa[i]
    i += 1
  base = 32 ## i64
  words = cap * 4 ## i64
  i = 0
  while i < rank
    snap[base + i] = sa[base + i]
    snap[base + cap + i] = sa[base + cap + i]
    snap[base + cap * 2 + i] = sa[base + cap * 2 + i]
    snap[base + cap * 3 + i] = sa[base + cap * 3 + i]
    i += 1
  rank

-> ffsa_restore(sa, snap) (i64[] i64[]) i64
  cap = sa[1] ## i64
  rank = snap[2] ## i64
  sa[2] = snap[2]
  sa[3] = snap[3]
  sa[4] = snap[4]
  sa[25] = snap[25]
  base = 32 ## i64
  i = 0 ## i64
  while i < rank
    sa[base + i] = snap[base + i]
    sa[base + cap + i] = snap[base + cap + i]
    sa[base + cap * 2 + i] = snap[base + cap * 2 + i]
    sa[base + cap * 3 + i] = snap[base + cap * 3 + i]
    i += 1
  rank

-> ffsa_export(sa, eu, ev, ew) (i64[] i64[] i64[] i64[]) i64
  cap = sa[1] ## i64
  rank = sa[2] ## i64
  uo = 32 ## i64
  i = 0 ## i64
  while i < rank
    eu[i] = sa[uo + i]
    ev[i] = sa[uo + cap + i]
    ew[i] = sa[uo + cap * 2 + i]
    i += 1
  rank

-> ffsa_export_best(sa, eu, ev, ew) (i64[] i64[] i64[] i64[]) i64
  cap = sa[1] ## i64
  rank = sa[8] ## i64
  buo = 32 + cap * 4 ## i64
  i = 0 ## i64
  while i < rank
    eu[i] = sa[buo + i]
    ev[i] = sa[buo + cap + i]
    ew[i] = sa[buo + cap * 2 + i]
    i += 1
  rank

# Set-equality of the live terms against an explicit term array (schemes are
# duplicate-free XOR sets, so equal count + one-direction membership is
# equality).  Compiled Array == is identity, so tests use this instead.
-> ffsa_terms_match(sa, eu, ev, ew, count) (i64[] i64[] i64[] i64[] i64) i64
  if sa[2] != count
    return 0
  ok = 1 ## i64
  i = 0 ## i64
  while i < count
    if ffsa_find(sa, eu[i], ev[i], ew[i]) < 0
      ok = 0
      i = count
    else
      i += 1
  ok

# Recompute density from scratch (tests cross-check the incremental cell).
-> ffsa_compute_density(sa) (i64[]) i64
  cap = sa[1] ## i64
  rank = sa[2] ## i64
  uo = 32 ## i64
  bits = 0 ## i64
  i = 0 ## i64
  while i < rank
    bits = bits + ffsa_term_bits(sa[uo + i], sa[uo + cap + i], sa[uo + cap * 2 + i])
    i += 1
  bits

# Full n^6 exact gate on the CURRENT term set via a fresh worker state.
# gate_state must be i64[ffw_state_size(sa capacity)]; eu/ev/ew i64[capacity].
-> ffsa_gate_current(sa, eu, ev, ew, gate_state, seed) (i64[] i64[] i64[] i64[] i64[] i64) i64
  rank = ffsa_export(sa, eu, ev, ew) ## i64
  loaded = ffw_init_terms_cap(gate_state, eu, ev, ew, rank, sa[0], sa[1], seed, 0, 1, 1, 1) ## i64
  if loaded != rank
    return 0
  ffw_verify_best_exact(gate_state, sa[0])

-> ffsa_gate_best(sa, eu, ev, ew, gate_state, seed) (i64[] i64[] i64[] i64[] i64[] i64) i64
  rank = ffsa_export_best(sa, eu, ev, ew) ## i64
  loaded = ffw_init_terms_cap(gate_state, eu, ev, ew, rank, sa[0], sa[1], seed, 0, 1, 1, 1) ## i64
  if loaded != rank
    return 0
  ffw_verify_best_exact(gate_state, sa[0])

# ---------------------------------------------------------------------------
# Locking

# Try to lock the exact rho-orbit of term `index`.  Fixed cubes become
# singleton locked orbits; otherwise all three images must be live, FREE and
# distinct.  Returns the orbit size locked (1 or 3) or 0.
-> ffsa_lock_index(sa, index) (i64[] i64) i64
  cap = sa[1] ## i64
  n = sa[0] ## i64
  lo = 32 + cap * 3 ## i64
  if index < 0 || index >= sa[2]
    return 0
  if sa[lo + index] != 0
    return 0
  u = ffsa_read_u(sa, index) ## i64
  v = ffsa_read_v(sa, index) ## i64
  w = ffsa_read_w(sa, index) ## i64
  if ffsa_is_fixed(u, v, w, n) == 1
    orbit = sa[4] ## i64
    sa[4] = orbit + 1
    sa[lo + index] = orbit
    sa[25] = sa[25] + 1
    sa[17] = sa[17] + 1
    return 1
  r1u = v ## i64
  r1v = ffe_transpose(w, n) ## i64
  r1w = ffe_transpose(u, n) ## i64
  r2u = r1v ## i64
  r2v = ffe_transpose(r1w, n) ## i64
  r2w = ffe_transpose(r1u, n) ## i64
  j = ffsa_find(sa, r1u, r1v, r1w) ## i64
  k = ffsa_find(sa, r2u, r2v, r2w) ## i64
  if j < 0 || k < 0 || j == index || k == index || j == k
    return 0
  if sa[lo + j] != 0 || sa[lo + k] != 0
    return 0
  orbit = sa[4] ## i64
  sa[4] = orbit + 1
  sa[lo + index] = orbit
  sa[lo + j] = orbit
  sa[lo + k] = orbit
  sa[25] = sa[25] + 3
  sa[17] = sa[17] + 1
  3

# Opportunistic LOCK pass: bind up to max_orbits exact orbits among the free
# terms (max_orbits < 1 = unlimited).  Returns the number of orbits bound.
-> ffsa_lock_pass(sa, max_orbits) (i64[] i64) i64
  made = 0 ## i64
  i = 0 ## i64
  while i < sa[2]
    if ffsa_read_lock(sa, i) == 0
      locked = ffsa_lock_index(sa, i) ## i64
      if locked > 0
        made += 1
        if max_orbits > 0 && made >= max_orbits
          i = sa[2]
    i += 1
  made

# Lock invariant checker (tests): every locked orbit id groups exactly one
# fixed cube or exactly three live terms forming an exact rho-orbit.
-> ffsa_verify_locks(sa) (i64[]) i64
  cap = sa[1] ## i64
  n = sa[0] ## i64
  rank = sa[2] ## i64
  lo = 32 + cap * 3 ## i64
  counted = 0 ## i64
  i = 0 ## i64
  while i < rank
    g = sa[lo + i] ## i64
    if g != 0
      counted += 1
      u = ffsa_read_u(sa, i) ## i64
      v = ffsa_read_v(sa, i) ## i64
      w = ffsa_read_w(sa, i) ## i64
      size = ffsa_orbit_size(sa, g) ## i64
      if ffsa_is_fixed(u, v, w, n) == 1
        if size != 1
          return 0
      else
        if size != 3
          return 0
        j = ffsa_find(sa, v, ffe_transpose(w, n), ffe_transpose(u, n)) ## i64
        if j < 0
          return 0
        if sa[lo + j] != g
          return 0
    i += 1
  if counted != sa[25]
    return 0
  1

-> ffsa_locked_orbit_count(sa) (i64[]) i64
  cap = sa[1] ## i64
  rank = sa[2] ## i64
  lo = 32 + cap * 3 ## i64
  count = 0 ## i64
  i = 0 ## i64
  while i < rank
    g = sa[lo + i] ## i64
    if g != 0
      first = 1 ## i64
      j = 0 ## i64
      while j < i
        if sa[lo + j] == g
          first = 0
          j = i
        else
          j += 1
      if first == 1
        count += 1
    i += 1
  count

# ---------------------------------------------------------------------------
# Random pickers

-> ffsa_pick_free(sa) (i64[]) i64
  rank = sa[2] ## i64
  if rank < 1
    return 0 - 1
  start = ffsa_next(sa) % rank ## i64
  k = 0 ## i64
  found = 0 - 1 ## i64
  while k < rank
    i = (start + k) % rank ## i64
    if ffsa_read_lock(sa, i) == 0
      found = i
      k = rank
    else
      k += 1
  found

-> ffsa_pick_locked(sa) (i64[]) i64
  rank = sa[2] ## i64
  if rank < 1
    return 0 - 1
  start = ffsa_next(sa) % rank ## i64
  k = 0 ## i64
  found = 0 - 1 ## i64
  while k < rank
    i = (start + k) % rank ## i64
    if ffsa_read_lock(sa, i) != 0
      found = i
      k = rank
    else
      k += 1
  found

# UNLOCK move: dissolve one random locked orbit.  Always legal, rank-neutral.
-> ffsa_unlock_random(sa) (i64[]) i64
  i = ffsa_pick_locked(sa) ## i64
  if i < 0
    return 0
  freed = ffsa_dissolve(sa, ffsa_read_lock(sa, i)) ## i64
  sa[16] = sa[16] + 1
  freed

# ---------------------------------------------------------------------------
# Flip / split programs (exact tensor identities as toggle lists)

-> ffsa_axis_value(sa, index, axis) (i64[] i64 i64) i64
  if axis == 0
    return ffsa_read_u(sa, index)
  if axis == 1
    return ffsa_read_v(sa, index)
  ffsa_read_w(sa, index)

# Standard flip on terms i, j sharing the `axis` factor: the two terms are
# replaced by two terms whose rank-one tensors XOR to the same sum.  Writes 4
# program entries (2 removals first, then 2 additions); returns 4, or 0 when
# the terms do not share the axis factor.
-> ffsa_flip_program(sa, i, j, axis, orient, tu, tv, tw) (i64[] i64 i64 i64 i64 i64[] i64[] i64[]) i64
  if i == j
    return 0
  ui = ffsa_read_u(sa, i) ## i64
  vi = ffsa_read_v(sa, i) ## i64
  wi = ffsa_read_w(sa, i) ## i64
  uj = ffsa_read_u(sa, j) ## i64
  vj = ffsa_read_v(sa, j) ## i64
  wj = ffsa_read_w(sa, j) ## i64
  shared = 0 ## i64
  if axis == 0 && ui == uj
    shared = 1
  if axis == 1 && vi == vj
    shared = 1
  if axis == 2 && wi == wj
    shared = 1
  if shared == 0
    return 0
  tu[0] = ui
  tv[0] = vi
  tw[0] = wi
  tu[1] = uj
  tv[1] = vj
  tw[1] = wj
  if axis == 0
    if orient == 0
      tu[2] = ui
      tv[2] = vi ^ vj
      tw[2] = wi
      tu[3] = uj
      tv[3] = vj
      tw[3] = wi ^ wj
    else
      tu[2] = ui
      tv[2] = vi
      tw[2] = wi ^ wj
      tu[3] = uj
      tv[3] = vi ^ vj
      tw[3] = wj
  if axis == 1
    if orient == 0
      tu[2] = ui ^ uj
      tv[2] = vi
      tw[2] = wi
      tu[3] = uj
      tv[3] = vj
      tw[3] = wi ^ wj
    else
      tu[2] = ui
      tv[2] = vi
      tw[2] = wi ^ wj
      tu[3] = ui ^ uj
      tv[3] = vj
      tw[3] = wj
  if axis == 2
    if orient == 0
      tu[2] = ui ^ uj
      tv[2] = vi
      tw[2] = wi
      tu[3] = uj
      tv[3] = vi ^ vj
      tw[3] = wj
    else
      tu[2] = ui
      tv[2] = vi ^ vj
      tw[2] = wi
      tu[3] = ui ^ uj
      tv[3] = vj
      tw[3] = wj
  4

# Split of term i on `axis` with subspace `part`: -t, +t[axis=part],
# +t[axis=old^part].  Rank +1.  Returns 3 or 0 on a degenerate part.
-> ffsa_split_program(sa, i, axis, part, tu, tv, tw) (i64[] i64 i64 i64 i64[] i64[] i64[]) i64
  n = sa[0] ## i64
  limit = (1 << (n * n)) - 1 ## i64
  old = ffsa_axis_value(sa, i, axis) ## i64
  if part < 1 || part == old || (part & limit) != part
    return 0
  u = ffsa_read_u(sa, i) ## i64
  v = ffsa_read_v(sa, i) ## i64
  w = ffsa_read_w(sa, i) ## i64
  tu[0] = u
  tv[0] = v
  tw[0] = w
  tu[1] = u
  tv[1] = v
  tw[1] = w
  tu[2] = u
  tv[2] = v
  tw[2] = w
  if axis == 0
    tu[1] = part
    tu[2] = old ^ part
  if axis == 1
    tv[1] = part
    tv[2] = old ^ part
  if axis == 2
    tw[1] = part
    tw[2] = old ^ part
  3

# Borrow a split part from another term's same-axis factor (creates shared
# factors for future flips); deterministic fallback keeps the part nonzero.
-> ffsa_pick_part(sa, i, axis) (i64[] i64 i64) i64
  rank = sa[2] ## i64
  old = ffsa_axis_value(sa, i, axis) ## i64
  part = 0 ## i64
  start = ffsa_next(sa) % rank ## i64
  k = 0 ## i64
  while k < rank
    j = (start + k) % rank ## i64
    candidate = ffsa_axis_value(sa, j, axis) ## i64
    if j != i && candidate != 0 && candidate != old
      part = candidate
      k = rank
    else
      k += 1
  if part == 0
    part = old ^ 1
    if part == 0
      part = old ^ 2
  part

# ---------------------------------------------------------------------------
# Free moves

-> ffsa_move_free_flip(sa, tu, tv, tw) (i64[] i64[] i64[] i64[]) i64
  i = ffsa_pick_free(sa) ## i64
  if i < 0
    return 0
  rank = sa[2] ## i64
  axis = ffsa_next(sa) % 3 ## i64
  orient = ffsa_next(sa) & 1 ## i64
  want = ffsa_axis_value(sa, i, axis) ## i64
  j = 0 - 1 ## i64
  start = ffsa_next(sa) % rank ## i64
  k = 0 ## i64
  while k < rank
    c = (start + k) % rank ## i64
    if c != i && ffsa_read_lock(sa, c) == 0 && ffsa_axis_value(sa, c, axis) == want
      j = c
      k = rank
    else
      k += 1
  if j < 0
    return 0
  count = ffsa_flip_program(sa, i, j, axis, orient, tu, tv, tw) ## i64
  if count == 0
    return 0
  applied = ffsa_apply_program(sa, tu, tv, tw, count) ## i64
  if applied < 0
    return 0 - 1
  sa[15] = sa[15] + 1
  sa[24] = 1
  1

-> ffsa_move_free_split(sa, tu, tv, tw) (i64[] i64[] i64[] i64[]) i64
  if sa[2] + 2 > sa[1]
    return 0
  i = ffsa_pick_free(sa) ## i64
  if i < 0
    return 0
  axis = ffsa_next(sa) % 3 ## i64
  part = ffsa_pick_part(sa, i, axis) ## i64
  count = ffsa_split_program(sa, i, axis, part, tu, tv, tw) ## i64
  if count == 0
    return 0
  applied = ffsa_apply_program(sa, tu, tv, tw, count) ## i64
  if applied < 0
    return 0 - 1
  sa[15] = sa[15] + 1
  sa[24] = 1
  1

# ---------------------------------------------------------------------------
# Orbit moves (representative move replicated through rho and rho^2)

# Deterministic orbit-flip: i, j must be locked members of size-3 orbits
# sharing the axis factor.  The 4-entry representative flip is replicated to
# 12 toggles; the two intended new orbits are re-locked when their images
# survive the toggles.  Returns 1 fired, 0 not applicable, -1 capacity.
-> ffsa_orbit_flip_at(sa, i, j, axis, orient, tu, tv, tw) (i64[] i64 i64 i64 i64 i64[] i64[] i64[]) i64
  n = sa[0] ## i64
  if ffsa_read_lock(sa, i) == 0 || ffsa_read_lock(sa, j) == 0
    return 0
  if ffsa_is_fixed(ffsa_read_u(sa, i), ffsa_read_v(sa, i), ffsa_read_w(sa, i), n) == 1
    return 0
  if ffsa_is_fixed(ffsa_read_u(sa, j), ffsa_read_v(sa, j), ffsa_read_w(sa, j), n) == 1
    return 0
  count = ffsa_flip_program(sa, i, j, axis, orient, tu, tv, tw) ## i64
  if count == 0
    return 0
  total = ffsa_replicate_program(tu, tv, tw, count, n) ## i64
  n1u = tu[2] ## i64
  n1v = tv[2] ## i64
  n1w = tw[2] ## i64
  n2u = tu[3] ## i64
  n2v = tv[3] ## i64
  n2w = tw[3] ## i64
  applied = ffsa_apply_program(sa, tu, tv, tw, total) ## i64
  if applied < 0
    return 0 - 1
  idx = ffsa_find(sa, n1u, n1v, n1w) ## i64
  if idx >= 0
    z = ffsa_lock_index(sa, idx)
  idx = ffsa_find(sa, n2u, n2v, n2w)
  if idx >= 0
    z = ffsa_lock_index(sa, idx)
  sa[14] = sa[14] + 1
  sa[24] = 3
  1

# Random orbit-flip driver.  Landing on a fixed cube auto-unlocks it first
# (returns 2: bookkeeping move, kept without an acceptance test).
-> ffsa_move_orbit_flip(sa, tu, tv, tw) (i64[] i64[] i64[] i64[]) i64
  n = sa[0] ## i64
  i = ffsa_pick_locked(sa) ## i64
  if i < 0
    return 0
  if ffsa_is_fixed(ffsa_read_u(sa, i), ffsa_read_v(sa, i), ffsa_read_w(sa, i), n) == 1
    z = ffsa_dissolve(sa, ffsa_read_lock(sa, i))
    sa[19] = sa[19] + 1
    return 2
  rank = sa[2] ## i64
  axis = ffsa_next(sa) % 3 ## i64
  orient = ffsa_next(sa) & 1 ## i64
  want = ffsa_axis_value(sa, i, axis) ## i64
  j = 0 - 1 ## i64
  start = ffsa_next(sa) % rank ## i64
  k = 0 ## i64
  while k < rank
    c = (start + k) % rank ## i64
    if c != i && ffsa_read_lock(sa, c) != 0 && ffsa_axis_value(sa, c, axis) == want
      if ffsa_is_fixed(ffsa_read_u(sa, c), ffsa_read_v(sa, c), ffsa_read_w(sa, c), n) == 0
        j = c
        k = rank
      else
        k += 1
    else
      k += 1
  if j < 0
    return 0
  ffsa_orbit_flip_at(sa, i, j, axis, orient, tu, tv, tw)

# Deterministic orbit-split.  On a singleton (fixed cube) the move
# auto-unlocks it and returns 2 — the sym_gen2 singleton-leakage rule: no
# orbit move ever edits a fixed cube while it is locked.
-> ffsa_orbit_split_at(sa, i, axis, part, tu, tv, tw) (i64[] i64 i64 i64 i64[] i64[] i64[]) i64
  n = sa[0] ## i64
  if ffsa_read_lock(sa, i) == 0
    return 0
  if ffsa_is_fixed(ffsa_read_u(sa, i), ffsa_read_v(sa, i), ffsa_read_w(sa, i), n) == 1
    z = ffsa_dissolve(sa, ffsa_read_lock(sa, i))
    sa[19] = sa[19] + 1
    return 2
  count = ffsa_split_program(sa, i, axis, part, tu, tv, tw) ## i64
  if count == 0
    return 0
  total = ffsa_replicate_program(tu, tv, tw, count, n) ## i64
  n1u = tu[1] ## i64
  n1v = tv[1] ## i64
  n1w = tw[1] ## i64
  n2u = tu[2] ## i64
  n2v = tv[2] ## i64
  n2w = tw[2] ## i64
  applied = ffsa_apply_program(sa, tu, tv, tw, total) ## i64
  if applied < 0
    return 0 - 1
  idx = ffsa_find(sa, n1u, n1v, n1w) ## i64
  if idx >= 0
    z = ffsa_lock_index(sa, idx)
  idx = ffsa_find(sa, n2u, n2v, n2w)
  if idx >= 0
    z = ffsa_lock_index(sa, idx)
  sa[14] = sa[14] + 1
  sa[24] = 3
  1

-> ffsa_move_orbit_split(sa, tu, tv, tw) (i64[] i64[] i64[] i64[]) i64
  if sa[2] + 6 > sa[1]
    return 0
  i = ffsa_pick_locked(sa) ## i64
  if i < 0
    return 0
  axis = ffsa_next(sa) % 3 ## i64
  part = ffsa_pick_part(sa, i, axis) ## i64
  ffsa_orbit_split_at(sa, i, axis, part, tu, tv, tw)

# ---------------------------------------------------------------------------
# repair-LOCK: bind a NEAR-orbit triple through a bounded exact correction

-> ffsa_diff_cost(au, av, aw, bu, bv, bw) (i64 i64 i64 i64 i64 i64) i64
  cost = 0 ## i64
  if au != bu
    cost += 1
  if av != bv
    cost += 1
  if aw != bw
    cost += 1
  cost

# One repair leg replacing candidate c by target r:
#   c + r = (cu^ru) x cv x cw  +  ru x (cv^rv) x cw  +  ru x rv x (cw^rw)
# over GF(2) — so toggling {c, r, the three correction terms} is exact.
# Zero-factor corrections vanish inside the toggle.  Writes 5 entries at
# `base`; returns base + 5.
-> ffsa_repair_leg(tu, tv, tw, base, cu, cv, cw, ru, rv, rw) (i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64) i64
  tu[base] = cu
  tv[base] = cv
  tw[base] = cw
  tu[base + 1] = ru
  tv[base + 1] = rv
  tw[base + 1] = rw
  tu[base + 2] = cu ^ ru
  tv[base + 2] = cv
  tw[base + 2] = cw
  tu[base + 3] = ru
  tv[base + 3] = cv ^ rv
  tw[base + 3] = cw
  tu[base + 4] = ru
  tv[base + 4] = rv
  tw[base + 4] = cw ^ rw
  base + 5

# Scan the free terms (excluding up to three indices) for the candidate with
# the fewest differing factors against (ru, rv, rw).  Returns the index or -1;
# writes the cost into cost_out[0].
-> ffsa_nearest_free(sa, ru, rv, rw, skip1, skip2, skip3, cost_out) (i64[] i64 i64 i64 i64 i64 i64 i64[]) i64
  rank = sa[2] ## i64
  best = 0 - 1 ## i64
  best_cost = 4 ## i64
  i = 0 ## i64
  while i < rank
    if i != skip1 && i != skip2 && i != skip3 && ffsa_read_lock(sa, i) == 0
      cost = ffsa_diff_cost(ffsa_read_u(sa, i), ffsa_read_v(sa, i), ffsa_read_w(sa, i), ru, rv, rw) ## i64
      if cost < best_cost
        best_cost = cost
        best = i
    i += 1
  cost_out[0] = best_cost
  best

# repair-LOCK anchored at free term `anchor`: reconstitute the exact orbit
# {t1, rho(t1), rho^2(t1)} by correcting the nearest free candidates toward
# the missing images, with at most max_cost correction terms in total
# (the rank +<=4 escape budget, tracked separately in header cell 7).
# Returns 1 fired (orbit locked when the images survived), 0 not applicable,
# -1 capacity (caller restores).
-> ffsa_repair_lock_at(sa, anchor, max_cost, tu, tv, tw) (i64[] i64 i64 i64[] i64[] i64[]) i64
  n = sa[0] ## i64
  if anchor < 0 || anchor >= sa[2]
    return 0
  if ffsa_read_lock(sa, anchor) != 0
    return 0
  u = ffsa_read_u(sa, anchor) ## i64
  v = ffsa_read_v(sa, anchor) ## i64
  w = ffsa_read_w(sa, anchor) ## i64
  if ffsa_is_fixed(u, v, w, n) == 1
    return 0
  r1u = v ## i64
  r1v = ffe_transpose(w, n) ## i64
  r1w = ffe_transpose(u, n) ## i64
  r2u = r1v ## i64
  r2v = ffe_transpose(r1w, n) ## i64
  r2w = ffe_transpose(r1u, n) ## i64
  j1 = ffsa_find(sa, r1u, r1v, r1w) ## i64
  j2 = ffsa_find(sa, r2u, r2v, r2w) ## i64
  if j1 >= 0 && ffsa_read_lock(sa, j1) != 0
    return 0
  if j2 >= 0 && ffsa_read_lock(sa, j2) != 0
    return 0
  cost_out = i64[1]
  cand1 = 0 - 1 ## i64
  cost1 = 0 ## i64
  if j1 < 0
    cand1 = ffsa_nearest_free(sa, r1u, r1v, r1w, anchor, j2, 0 - 1, cost_out)
    if cand1 < 0
      return 0
    cost1 = cost_out[0]
  cand2 = 0 - 1 ## i64
  cost2 = 0 ## i64
  if j2 < 0
    cand2 = ffsa_nearest_free(sa, r2u, r2v, r2w, anchor, j1, cand1, cost_out)
    if cand2 < 0
      return 0
    cost2 = cost_out[0]
  if cost1 + cost2 > max_cost
    return 0
  count = 0 ## i64
  if cand1 >= 0
    count = ffsa_repair_leg(tu, tv, tw, count, ffsa_read_u(sa, cand1), ffsa_read_v(sa, cand1), ffsa_read_w(sa, cand1), r1u, r1v, r1w)
  if cand2 >= 0
    count = ffsa_repair_leg(tu, tv, tw, count, ffsa_read_u(sa, cand2), ffsa_read_v(sa, cand2), ffsa_read_w(sa, cand2), r2u, r2v, r2w)
  if count > 0
    applied = ffsa_apply_program(sa, tu, tv, tw, count) ## i64
    if applied < 0
      return 0 - 1
  sa[7] = sa[7] + cost1 + cost2
  idx = ffsa_find(sa, u, v, w) ## i64
  if idx >= 0
    locked = ffsa_lock_index(sa, idx) ## i64
    if locked == 3
      sa[18] = sa[18] + 1
  sa[24] = 1
  1

# Random repair-LOCK driver: bounded anchor probes.
-> ffsa_move_repair_lock(sa, max_cost, tu, tv, tw) (i64[] i64 i64[] i64[] i64[]) i64
  fired = 0 ## i64
  tries = 0 ## i64
  while tries < 8 && fired == 0
    anchor = ffsa_pick_free(sa) ## i64
    if anchor < 0
      tries = 8
    else
      fired = ffsa_repair_lock_at(sa, anchor, max_cost, tu, tv, tw)
      if fired < 0
        tries = 8
      else
        tries += 1
  fired

# ---------------------------------------------------------------------------
# The annealed walk

# cfg layout (i64[12]):
#   0 moves                 1 k_stall (stall window)
#   2 base unlock milli     3 linear unlock ramp milli (over the whole walk)
#   4 stall bonus cap milli 5 repair budget (total correction terms; 0 = off)
#   6 lock cadence          7 split cadence
#   8 repair cadence        9 verify every accepted state (1 = full gate)
#  10 orbit move bias milli (-1 = auto: locked fraction)   11 reserved
#
# Acceptance is lex(rank, density): strict rank drops always accept;
# rank-neutral moves accept within slack sa[6] * replication; rank-raising
# moves accept while rank <= best + band.  Every improvement of
# lex(best rank, best density) passes the full n^6 gate before adoption
# (and with cfg[9] = 1 every accepted state does).
# Returns the best rank; the best view is exported via ffsa_export_best.
-> ffsa_anneal(sa, cfg, snap, tu, tv, tw, gate_state, eu, ev, ew) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  moves = cfg[0] ## i64
  k_stall = cfg[1] ## i64
  if k_stall < 1
    k_stall = 1
  step = 0 ## i64
  while step < moves
    sa[23] = sa[23] + 1
    unlock_milli = cfg[2] + (step * cfg[3]) / moves ## i64
    bonus = (sa[12] / k_stall) * 100 ## i64
    if bonus > cfg[4]
      bonus = cfg[4]
    unlock_milli = unlock_milli + bonus
    choose = ffsa_next(sa) % 1000 ## i64
    handled = 0 ## i64
    if sa[25] > 0 && choose < unlock_milli
      z = ffsa_unlock_random(sa)
      handled = 1
    if handled == 0 && cfg[6] > 0 && step % cfg[6] == cfg[6] - 1
      z = ffsa_lock_pass(sa, 4)
      handled = 1
    if handled == 0
      rank0 = sa[2] ## i64
      dens0 = sa[3] ## i64
      z = ffsa_snapshot(sa, snap)
      bias = cfg[10] ## i64
      if bias < 0
        bias = (sa[25] * 1000) / rank0
      fired = 0 ## i64
      if cfg[8] > 0 && step % cfg[8] == cfg[8] - 1 && cfg[5] > sa[7]
        fired = ffsa_move_repair_lock(sa, 4, tu, tv, tw)
      if fired == 0 && cfg[7] > 0 && step % cfg[7] == cfg[7] - 1
        want_orbit = 0 ## i64
        if sa[25] > 0 && (ffsa_next(sa) % 1000) < bias
          want_orbit = 1
        if want_orbit == 1 && rank0 + 3 <= sa[8] + sa[13]
          fired = ffsa_move_orbit_split(sa, tu, tv, tw)
        if fired == 0 && rank0 + 1 <= sa[8] + sa[13] && sa[25] < rank0
          fired = ffsa_move_free_split(sa, tu, tv, tw)
      if fired == 0
        want_orbit = 0 ## i64
        if sa[25] > 0 && (ffsa_next(sa) % 1000) < bias
          want_orbit = 1
        if want_orbit == 1
          fired = ffsa_move_orbit_flip(sa, tu, tv, tw)
        if fired == 0 && sa[25] < rank0
          fired = ffsa_move_free_flip(sa, tu, tv, tw)
        if fired == 0 && sa[25] > 0
          fired = ffsa_move_orbit_flip(sa, tu, tv, tw)
      if fired == 0
        sa[11] = sa[11] + 1
        sa[12] = sa[12] + 1
      if fired < 0
        z = ffsa_restore(sa, snap)
        sa[11] = sa[11] + 1
        sa[12] = sa[12] + 1
      if fired == 1
        rank1 = sa[2] ## i64
        dens1 = sa[3] ## i64
        accept = 0 ## i64
        if rank1 < rank0
          accept = 1
        if rank1 == rank0 && dens1 <= dens0 + sa[6] * sa[24]
          accept = 1
        if rank1 > rank0 && rank1 <= sa[8] + sa[13]
          accept = 1
        if accept == 1
          improved = 0 ## i64
          if rank1 < sa[8]
            improved = 1
          if rank1 == sa[8] && dens1 < sa[9]
            improved = 1
          if cfg[9] == 1 || improved == 1
            exact = ffsa_gate_current(sa, eu, ev, ew, gate_state, 77003 + step * 13) ## i64
            if exact == 0
              sa[22] = sa[22] + 1
              z = ffsa_restore(sa, snap)
              accept = 0
        if accept == 1
          sa[10] = sa[10] + 1
          sa[12] = 0
          if rank1 < rank0
            sa[20] = sa[20] + 1
          improved = 0 ## i64
          if rank1 < sa[8]
            improved = 1
          if rank1 == sa[8] && dens1 < sa[9]
            improved = 1
          if improved == 1
            z = ffsa_adopt_best(sa)
        else
          z = ffsa_restore(sa, snap)
          sa[11] = sa[11] + 1
          sa[12] = sa[12] + 1
    step += 1
  sa[8]

# ---------------------------------------------------------------------------
# One-shot engine (publication path mirrors fffsp_run_engine):
# load + gate the seed, lock every exact orbit, anneal, and on a strict rank
# win dump -> re-parse -> re-gate before returning the hit.
# Returns > 0 verified published rank; 0 ordinary miss (nothing published);
# < 0 malformed input (-1), seed rejection (-2), publication error (-4).
# meta (i64[16]): 0 input rank, 1 best rank, 2 best density, 3 locked terms
# at end, 4 locked orbits at end, 5 unlocks, 6 repair corrections, 7 gate
# failures, 8 accepted, 9 proposals, 10 orbit moves, 11 free moves,
# 12 rank drops, 13 singleton auto-unlocks, 14 hit flag, 15 elapsed ms.

-> ffsa_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

-> ffsa_remove(path) (String) i64
  if system("/bin/rm -f " + ffsa_shell_quote(path))
    return 1
  0

-> ffsa_run_engine(seed_path, output_path, n, move_budget, seed, meta) (String String i64 i64 i64 i64[]) i64
  if seed_path.size() < 1 || output_path.size() < 1 || seed_path == output_path
    return 0 - 1
  if n < 3 || n > 7 || move_budget < 1 || seed < 0 || meta.size() < 16
    return 0 - 1
  if ffsa_remove(output_path) == 0
    return 0 - 4
  capacity = ffw_default_capacity(n) ## i64
  loader = i64[ffw_state_size(capacity)]
  input_rank = ffw_load_scheme_cap(loader, seed_path, n, capacity, 83003 + seed * 17, 0, 1, 1, 1) ## i64
  if input_rank < 2 || ffw_verify_best_exact(loader, n) == 0
    return 0 - 2
  eu = i64[capacity]
  ev = i64[capacity]
  ew = i64[capacity]
  exported = ffw_export_best(loader, eu, ev, ew) ## i64
  if exported != input_rank
    return 0 - 2
  sa = i64[ffsa_state_size(capacity)]
  if ffsa_init_terms(sa, eu, ev, ew, input_rank, n, capacity, seed) != input_rank
    return 0 - 2
  z = ffsa_lock_pass(sa, 0 - 1)
  started = ccall("__w_clock_ms") ## i64
  << "SYM_ANNEAL_ENGINE_START n=" + n.to_s() + " rank=" + input_rank.to_s() + " locked_terms=" + sa[25].to_s() + " locked_orbits=" + ffsa_locked_orbit_count(sa).to_s() + " moves=" + move_budget.to_s() + " seed=" + seed.to_s()
  cfg = i64[12]
  cfg[0] = move_budget
  cfg[1] = 400
  cfg[2] = 15
  cfg[3] = 120
  cfg[4] = 300
  cfg[5] = 64
  cfg[6] = 97
  cfg[7] = 23
  cfg[8] = 181
  cfg[9] = 0
  cfg[10] = 0 - 1
  snap = i64[ffsa_state_size(capacity)]
  tu = i64[16]
  tv = i64[16]
  tw = i64[16]
  gate_state = i64[ffw_state_size(capacity)]
  best = ffsa_anneal(sa, cfg, snap, tu, tv, tw, gate_state, eu, ev, ew) ## i64
  elapsed = ccall("__w_clock_ms") - started ## i64
  meta[0] = input_rank
  meta[1] = best
  meta[2] = sa[9]
  meta[3] = sa[25]
  meta[4] = ffsa_locked_orbit_count(sa)
  meta[5] = sa[16]
  meta[6] = sa[7]
  meta[7] = sa[22]
  meta[8] = sa[10]
  meta[9] = sa[23]
  meta[10] = sa[14]
  meta[11] = sa[15]
  meta[12] = sa[20]
  meta[13] = sa[19]
  meta[14] = 0
  meta[15] = elapsed
  if best >= input_rank
    << "SYM_ANNEAL_ENGINE_RESULT n=" + n.to_s() + " rank=" + input_rank.to_s() + " best=" + best.to_s() + " hit=0 elapsed_ms=" + elapsed.to_s()
    return 0
  if ffsa_gate_best(sa, eu, ev, ew, gate_state, 88007 + seed * 19) == 0
    return 0 - 4
  written = ffw_dump_best(gate_state, output_path) ## i64
  if written != best
    z = ffsa_remove(output_path)
    return 0 - 4
  check = i64[ffw_state_size(capacity)]
  checked = ffw_load_scheme_cap(check, output_path, n, capacity, 91009 + seed * 23, 0, 1, 1, 1) ## i64
  if checked != best || ffw_verify_best_exact(check, n) == 0
    z = ffsa_remove(output_path)
    return 0 - 4
  meta[14] = 1
  << "SYM_ANNEAL_ENGINE_RESULT n=" + n.to_s() + " rank=" + input_rank.to_s() + " best=" + best.to_s() + " hit=1 elapsed_ms=" + elapsed.to_s()
  best
