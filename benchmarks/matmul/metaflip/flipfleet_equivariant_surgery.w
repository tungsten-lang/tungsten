# Equivariant orbit surgery on C3-invariant presentations (move 5 intake,
# lane prefix ffes_).
#
# EXACT CONTENT.  The campaign's cyclic axis rotation
#   rho(u, v, w) = (v, transpose(w), transpose(u))
# (the ffbi_transform_term / flipfleet_sym_anneal convention, rho^3 = id) is
# an automorphism of the <n,n,n> matmul tensor.  A presentation whose term
# set is rho-closed splits into free orbits {t, rho(t), rho^2(t)} plus fixed
# cubes rho(t) = t, i.e. v = u and w = transpose(u).  Excising whole orbits
# and/or cubes leaves a rho-INVARIANT residual tensor D (the XOR of the
# excised rank-one tensors), and this lane solves for a rho-invariant
# replacement with the in-process CDCL solver (flipfleet_sat_cdcl):
#
#   unknowns  = want_j orbit-representative triples (3*n^2 bits each) plus
#               want_c cube generators (n^2 bits each: the cube is
#               (x, x, transpose(x)), so only x is free);
#   wiring    = the three images of a representative share its variables
#               through constant position maps -- for cell (a, b, c):
#                 p0 = u[a] & v[b] & w[c]
#                 p1 = v[a] & w[T(b)] & u[T(c)]
#                 p2 = w[T(a)] & u[b] & v[T(c)]
#               (T = the transpose position map on n^2 bit indices), and a
#               cube contributes p = x[a] & x[b] & x[T(c)];
#   rows      = one XOR row per ambient cell (a, b, c): the XOR of all
#               product variables equals bit (a, b, c) of D.  ALL n^6 cells
#               are constrained -- no window compression, no row quotient --
#               so a model reproduces D exactly, by construction.  (The
#               orbit quotient of rows is a size optimization deliberately
#               NOT taken: correctness first; the equivariance already lives
#               in the shared-variable wiring, which is what shrinks the
#               search space from 3jk unknown terms to jk representatives.)
#
# Degeneracy guards: every representative factor and every cube generator
# carries an at-least-one-bit clause.  A model may still collide with live
# terms or self-cancel; the toggle application is collision-aware and the
# full exhaustive verifier decides admission, so a degenerate model can only
# produce a VERIFIED lower-rank scheme or be rolled back -- never a wrong
# one.
#
# ADMISSION.  ffes_apply toggles the excised terms out and the expanded
# replacement in, requires ffw_verify_current_exact, and rolls back through
# the self-inverse XOR toggles on any failure.  The driver publishes only
# through dump -> re-parse -> re-gate (the fffsp_run_engine discipline).

use metaflip_worker
use flipfleet_escape
use flipfleet_sat_cdcl

# ---------------------------------------------------------------------------
# rho action and orbit census

-> ffes_rho_u(u, v, w, n) (i64 i64 i64 i64) i64
  v

-> ffes_rho_v(u, v, w, n) (i64 i64 i64 i64) i64
  ffe_transpose(w, n)

-> ffes_rho_w(u, v, w, n) (i64 i64 i64 i64) i64
  ffe_transpose(u, n)

-> ffes_is_cube(u, v, w, n) (i64 i64 i64 i64) i64
  if v == u && w == ffe_transpose(u, n)
    return 1
  0

-> ffes_find_term(us, vs, ws, rank, u, v, w) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < rank
    if us[i] == u && vs[i] == v && ws[i] == w
      return i
    i += 1
  0 - 1

# Partition a term set into rho-orbits and cubes.  orbit_ids[i] receives a
# 1-based group id shared by orbit members (cubes get their own id).
# profile (i64[4]): [0] free orbit count, [1] cube count, [2] closure flag,
# [3] n.  Returns the total group count, or -1 when the set is not
# rho-closed.
-> ffes_partition(us, vs, ws, rank, n, orbit_ids, profile) (i64[] i64[] i64[] i64 i64 i64[] i64[]) i64
  profile[0] = 0
  profile[1] = 0
  profile[2] = 0
  profile[3] = n
  i = 0 ## i64
  while i < rank
    orbit_ids[i] = 0
    i += 1
  groups = 0 ## i64
  i = 0
  while i < rank
    if orbit_ids[i] == 0
      u = us[i] ## i64
      v = vs[i] ## i64
      w = ws[i] ## i64
      if ffes_is_cube(u, v, w, n) == 1
        groups += 1
        orbit_ids[i] = groups
        profile[1] = profile[1] + 1
      else
        u1 = ffes_rho_u(u, v, w, n) ## i64
        v1 = ffes_rho_v(u, v, w, n) ## i64
        w1 = ffes_rho_w(u, v, w, n) ## i64
        u2 = ffes_rho_u(u1, v1, w1, n) ## i64
        v2 = ffes_rho_v(u1, v1, w1, n) ## i64
        w2 = ffes_rho_w(u1, v1, w1, n) ## i64
        j1 = ffes_find_term(us, vs, ws, rank, u1, v1, w1) ## i64
        j2 = ffes_find_term(us, vs, ws, rank, u2, v2, w2) ## i64
        if j1 < 0 || j2 < 0 || j1 == i || j2 == i || j1 == j2
          return 0 - 1
        if orbit_ids[j1] != 0 || orbit_ids[j2] != 0
          return 0 - 1
        groups += 1
        orbit_ids[i] = groups
        orbit_ids[j1] = groups
        orbit_ids[j2] = groups
        profile[0] = profile[0] + 1
    i += 1
  profile[2] = 1
  groups

-> ffes_verify_c3(us, vs, ws, rank, n, profile) (i64[] i64[] i64[] i64 i64 i64[]) i64
  ids = i64[rank + 1]
  groups = ffes_partition(us, vs, ws, rank, n, ids, profile) ## i64
  if groups < 0
    return 0
  1

# ---------------------------------------------------------------------------
# Dense residual tensor

-> ffes_cells(n) (i64) i64
  nn = n * n ## i64
  nn * nn * nn

-> ffes_tensor_words(n) (i64) i64
  (ffes_cells(n) + 63) / 64

-> ffes_bit(target, cell) (i64[] i64) i64
  (target[cell / 64] >> (cell % 64)) & 1

-> ffes_xor_outer(target, u, v, w, nn) (i64[] i64 i64 i64 i64) i64
  a = 0 ## i64
  while a < nn
    if ((u >> a) & 1) == 1
      b = 0 ## i64
      while b < nn
        if ((v >> b) & 1) == 1
          c = 0 ## i64
          while c < nn
            if ((w >> c) & 1) == 1
              cell = (a * nn + b) * nn + c ## i64
              target[cell / 64] = target[cell / 64] ^ (1 << (cell % 64))
            c += 1
        b += 1
    a += 1
  1

# ---------------------------------------------------------------------------
# CDCL encoding

# Transpose position map on n^2 bit indices: i*n + j -> j*n + i.
-> ffes_tpos(pos, n) (i64 i64) i64
  (pos % n) * n + (pos / n)

# Variable map.  Representatives first (3*nn vars each: u, v, w blocks),
# then cube generators (nn vars each), then product vars (cell-major,
# slot-minor), then add_xor auxiliaries above everything.
-> ffes_prim_count(wj, wc, nn) (i64 i64 i64) i64
  wj * 3 * nn + wc * nn

-> ffes_rep_var(k, axis, pos, nn) (i64 i64 i64 i64) i64
  1 + k * 3 * nn + axis * nn + pos

-> ffes_cube_var(wj, q, pos, nn) (i64 i64 i64 i64) i64
  1 + wj * 3 * nn + q * nn + pos

-> ffes_slot_count(wj, wc) (i64 i64) i64
  wj * 3 + wc

-> ffes_product_var(prim, slots, cell, slot) (i64 i64 i64 i64) i64
  prim + 1 + cell * slots + slot

# The three variable indices whose AND drives product slot `slot` at cell
# (a, b, c), written into vars[0..2].  Slots 0..3*wj-1 are representative
# images; slots 3*wj.. are cubes.
-> ffes_slot_inputs(slot, wj, a, b, c, n, nn, vars) (i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  if slot < wj * 3
    k = slot / 3 ## i64
    image = slot % 3 ## i64
    if image == 0
      vars[0] = ffes_rep_var(k, 0, a, nn)
      vars[1] = ffes_rep_var(k, 1, b, nn)
      vars[2] = ffes_rep_var(k, 2, c, nn)
    if image == 1
      vars[0] = ffes_rep_var(k, 1, a, nn)
      vars[1] = ffes_rep_var(k, 2, ffes_tpos(b, n), nn)
      vars[2] = ffes_rep_var(k, 0, ffes_tpos(c, n), nn)
    if image == 2
      vars[0] = ffes_rep_var(k, 2, ffes_tpos(a, n), nn)
      vars[1] = ffes_rep_var(k, 0, b, nn)
      vars[2] = ffes_rep_var(k, 1, ffes_tpos(c, n), nn)
    return 1
  q = slot - wj * 3 ## i64
  vars[0] = ffes_cube_var(wj, q, a, nn)
  vars[1] = ffes_cube_var(wj, q, b, nn)
  vars[2] = ffes_cube_var(wj, q, ffes_tpos(c, n), nn)
  1

# Encode the full instance into an initialized CDCL state.  Returns 1, or 0
# on any arena/plan failure.
-> ffes_encode(sat, target, n, wj, wc) (i64[] i64[] i64 i64 i64) i64
  nn = n * n ## i64
  cells = ffes_cells(n) ## i64
  prim = ffes_prim_count(wj, wc, nn) ## i64
  slots = ffes_slot_count(wj, wc) ## i64
  lits = i64[nn + 4]
  vars = i64[4]
  xvars = i64[8]
  # At-least-one-bit guards.
  k = 0 ## i64
  while k < wj
    axis = 0 ## i64
    while axis < 3
      pos = 0 ## i64
      while pos < nn
        lits[pos] = 2 * ffes_rep_var(k, axis, pos, nn)
        pos += 1
      if ffcdcl_add_clause(sat, lits, nn) != 1
        return 0
      axis += 1
    k += 1
  q = 0 ## i64
  while q < wc
    pos = 0 ## i64
    while pos < nn
      lits[pos] = 2 * ffes_cube_var(wj, q, pos, nn)
      pos += 1
    if ffcdcl_add_clause(sat, lits, nn) != 1
      return 0
    q += 1
  # Pass 1: every product definition.  This references every product
  # variable before any XOR row runs, so ffcdcl_add_xor's auxiliaries (which
  # land directly above the highest variable referenced so far) cannot
  # collide with the fixed product numbering.
  cell = 0 ## i64
  while cell < cells
    c = cell % nn ## i64
    rest = cell / nn ## i64
    b = rest % nn ## i64
    a = rest / nn ## i64
    slot = 0 ## i64
    while slot < slots
      p = ffes_product_var(prim, slots, cell, slot) ## i64
      z = ffes_slot_inputs(slot, wj, a, b, c, n, nn, vars) ## i64
      lits[0] = 2 * p + 1
      lits[1] = 2 * vars[0]
      if ffcdcl_add_clause(sat, lits, 2) != 1
        return 0
      lits[1] = 2 * vars[1]
      if ffcdcl_add_clause(sat, lits, 2) != 1
        return 0
      lits[1] = 2 * vars[2]
      if ffcdcl_add_clause(sat, lits, 2) != 1
        return 0
      lits[0] = 2 * p
      lits[1] = 2 * vars[0] + 1
      lits[2] = 2 * vars[1] + 1
      lits[3] = 2 * vars[2] + 1
      if ffcdcl_add_clause(sat, lits, 4) != 1
        return 0
      slot += 1
    cell += 1
  # Pass 2: one XOR row per cell.
  cell = 0
  while cell < cells
    slot = 0 ## i64
    while slot < slots
      xvars[slot] = ffes_product_var(prim, slots, cell, slot)
      slot += 1
    if ffcdcl_add_xor(sat, xvars, slots, ffes_bit(target, cell)) != 1
      return 0
    cell += 1
  1

# Decode a SAT model into expanded replacement terms.  Returns the term
# count (3*wj + wc), never compacted here -- application handles collisions.
-> ffes_decode(sat, n, wj, wc, out_u, out_v, out_w) (i64[] i64 i64 i64 i64[] i64[] i64[]) i64
  nn = n * n ## i64
  count = 0 ## i64
  k = 0 ## i64
  while k < wj
    u = 0 ## i64
    v = 0 ## i64
    w = 0 ## i64
    pos = 0 ## i64
    while pos < nn
      if ffcdcl_value(sat, ffes_rep_var(k, 0, pos, nn)) == 1
        u = u | (1 << pos)
      if ffcdcl_value(sat, ffes_rep_var(k, 1, pos, nn)) == 1
        v = v | (1 << pos)
      if ffcdcl_value(sat, ffes_rep_var(k, 2, pos, nn)) == 1
        w = w | (1 << pos)
      pos += 1
    out_u[count] = u
    out_v[count] = v
    out_w[count] = w
    count += 1
    out_u[count] = ffes_rho_u(u, v, w, n)
    out_v[count] = ffes_rho_v(u, v, w, n)
    out_w[count] = ffes_rho_w(u, v, w, n)
    count += 1
    pu = out_u[count - 1] ## i64
    pv = out_v[count - 1] ## i64
    pw = out_w[count - 1] ## i64
    out_u[count] = ffes_rho_u(pu, pv, pw, n)
    out_v[count] = ffes_rho_v(pu, pv, pw, n)
    out_w[count] = ffes_rho_w(pu, pv, pw, n)
    count += 1
    k += 1
  q = 0 ## i64
  while q < wc
    x = 0 ## i64
    pos = 0 ## i64
    while pos < nn
      if ffcdcl_value(sat, ffes_cube_var(wj, q, pos, nn)) == 1
        x = x | (1 << pos)
      pos += 1
    out_u[count] = x
    out_v[count] = x
    out_w[count] = ffe_transpose(x, n)
    count += 1
    q += 1
  count

# ---------------------------------------------------------------------------
# Application with exact rollback

# Toggle excised terms out and replacement terms in; require full exactness;
# roll back (XOR toggles are self-inverse) on any failure.  Returns the new
# rank, or -1 after a clean rollback.
-> ffes_apply(st, n, ex_u, ex_v, ex_w, ex_count, rep_u, rep_v, rep_w, rep_count) (i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  rank = st[6] ## i64
  i = 0 ## i64
  while i < ex_count
    rank = ffw_toggle(st, ex_u[i], ex_v[i], ex_w[i], rank)
    i += 1
  i = 0
  while i < rep_count
    rank = ffw_toggle(st, rep_u[i], rep_v[i], rep_w[i], rank)
    i += 1
  st[6] = rank
  if ffw_verify_current_exact(st, n) == 1
    return rank
  i = rep_count - 1
  while i >= 0
    rank = ffw_toggle(st, rep_u[i], rep_v[i], rep_w[i], rank)
    i -= 1
  i = ex_count - 1
  while i >= 0
    rank = ffw_toggle(st, ex_u[i], ex_v[i], ex_w[i], rank)
    i -= 1
  st[6] = rank
  0 - 1

# ---------------------------------------------------------------------------
# One-shot replacement solve on explicit term arrays

# Excise the listed term indices (which must cover whole groups) from the
# (rho-closed) term set and solve for a (want_j, want_c) invariant
# replacement.  meta (i64[16]):
#   [0] rank  [1] free orbits  [2] cubes  [3] excised terms  [4] variables
#   [5] stored clauses  [6] solver status (1 SAT / -1 UNSAT / -2 budget)
#   [7] conflicts  [8] replacement terms  [9] reserved  [10] reserved
#   [11] elapsed ms
# Returns the replacement term count on SAT, 0 on UNSAT/budget, negative on
# structural errors (-3 bad plan, -4 encode failure).
-> ffes_solve_replacement(us, vs, ws, rank, n, excised, ex_count, want_j, want_c, budget, seed, out_u, out_v, out_w, meta) (i64[] i64[] i64[] i64 i64 i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < 16
    meta[i] = 0
    i += 1
  started = ccall("__w_clock_ms") ## i64
  if n < 2 || n > 5 || rank < 1 || ex_count < 1 || want_j < 0 || want_c < 0
    return 0 - 3
  if want_j + want_c < 1 || want_j * 3 + want_c > 30
    return 0 - 3
  nn = n * n ## i64
  words = ffes_tensor_words(n) ## i64
  target = i64[words + 1]
  i = 0
  while i < ex_count
    idx = excised[i] ## i64
    if idx < 0 || idx >= rank
      return 0 - 3
    z = ffes_xor_outer(target, us[idx], vs[idx], ws[idx], nn)
    i += 1
  cells = ffes_cells(n) ## i64
  prim = ffes_prim_count(want_j, want_c, nn) ## i64
  slots = ffes_slot_count(want_j, want_c) ## i64
  aux = cells * slots ## i64
  max_vars = prim + cells * slots + aux + 64 ## i64
  # Arena sizing: 4 AND clauses of <= 4 lits per (cell, slot) plus the XOR
  # Tseitin chains (~8 words per aux) plus guards and learnt headroom.
  clause_words = cells * slots * 30 + cells * (slots + 2) * 10 + (want_j * 3 + want_c) * (nn + 6) + 200000 ## i64
  sat = i64[ffcdcl_state_size(max_vars, clause_words)]
  if ffcdcl_init(sat, max_vars, seed) != 1
    return 0 - 4
  if ffes_encode(sat, target, n, want_j, want_c) != 1
    return 0 - 4
  meta[0] = rank
  meta[3] = ex_count
  meta[4] = ffcdcl_top_var(sat)
  meta[5] = ffcdcl_clause_count(sat)
  assumptions = i64[1]
  status = ffcdcl_solve(sat, assumptions, 0, budget) ## i64
  meta[6] = status
  meta[7] = ffcdcl_conflicts(sat)
  meta[11] = ccall("__w_clock_ms") - started
  if status != 1
    return 0
  count = ffes_decode(sat, n, want_j, want_c, out_u, out_v, out_w) ## i64
  meta[8] = count
  count

# ---------------------------------------------------------------------------
# Whole-scheme driver

-> ffes_shell_quote(text) (String)
  "'" + text.replace("'", "'\"'\"'") + "'"

# Load a rho-closed scheme, excise `take_j` whole free orbits and `take_c`
# cubes (deterministic selection rotated by seed), solve for a
# (want_j, want_c) replacement, apply, and (out_path != "") publish through
# dump -> re-parse -> re-gate.  meta as in ffes_solve_replacement plus:
#   [9] final rank  [10] applied flag  [12] free orbits  [13] cubes
#   [14] error code
# Returns the final rank on an applied hit, 0 on a miss (UNSAT / budget /
# rollback), negative on structural errors (-1 load, -2 not rho-closed,
# -3 bad plan, -4 encode, -6 publish).
-> ffes_surgery(path, n, take_j, take_c, want_j, want_c, budget, seed, out_path, meta) (String i64 i64 i64 i64 i64 i64 i64 String i64[]) i64
  capacity = ffw_default_capacity(n) ## i64
  st = i64[ffw_state_size(capacity)]
  rank = ffw_load_scheme_cap(st, path, n, capacity, 91201 + (seed % 100000) * 7, 0, 1, 1, 1) ## i64
  if rank < 1 || ffw_verify_current_exact(st, n) != 1
    meta[14] = 0 - 1
    return 0 - 1
  eu = i64[capacity]
  ev = i64[capacity]
  ew = i64[capacity]
  count = ffw_export_current(st, eu, ev, ew) ## i64
  ids = i64[count + 1]
  profile = i64[4]
  groups = ffes_partition(eu, ev, ew, count, n, ids, profile) ## i64
  if groups < 0
    meta[14] = 0 - 2
    return 0 - 2
  meta[12] = profile[0]
  meta[13] = profile[1]
  if take_j > profile[0] || take_c > profile[1] || take_j + take_c < 1
    meta[14] = 0 - 3
    return 0 - 3
  # Deterministic excision: walk groups in id order starting from a
  # seed-rotated offset, taking the first take_j free orbits and take_c
  # cubes encountered.
  excised = i64[take_j * 3 + take_c + 1]
  ex_count = 0 ## i64
  taken_j = 0 ## i64
  taken_c = 0 ## i64
  offset = 0 ## i64
  if groups > 0
    offset = (seed & 32767) % groups
  probe = 0 ## i64
  while probe < groups && (taken_j < take_j || taken_c < take_c)
    g = 1 + ((offset + probe) % groups) ## i64
    size = 0 ## i64
    first = 0 - 1 ## i64
    i = 0 ## i64
    while i < count
      if ids[i] == g
        size += 1
        if first < 0
          first = i
      i += 1
    if size == 3 && taken_j < take_j
      i = 0
      while i < count
        if ids[i] == g
          excised[ex_count] = i
          ex_count += 1
        i += 1
      taken_j += 1
    if size == 1 && taken_c < take_c
      excised[ex_count] = first
      ex_count += 1
      taken_c += 1
    probe += 1
  if taken_j != take_j || taken_c != take_c
    meta[14] = 0 - 3
    return 0 - 3
  rep_u = i64[34]
  rep_v = i64[34]
  rep_w = i64[34]
  solved = ffes_solve_replacement(eu, ev, ew, count, n, excised, ex_count, want_j, want_c, budget, seed, rep_u, rep_v, rep_w, meta) ## i64
  meta[12] = profile[0]
  meta[13] = profile[1]
  if solved < 0
    meta[14] = solved
    return solved
  if solved == 0
    return 0
  ex_u = i64[ex_count + 1]
  ex_v = i64[ex_count + 1]
  ex_w = i64[ex_count + 1]
  i = 0
  while i < ex_count
    ex_u[i] = eu[excised[i]]
    ex_v[i] = ev[excised[i]]
    ex_w[i] = ew[excised[i]]
    i += 1
  applied = ffes_apply(st, n, ex_u, ex_v, ex_w, ex_count, rep_u, rep_v, rep_w, solved) ## i64
  if applied < 0
    return 0
  meta[9] = applied
  meta[10] = 1
  if out_path.size() > 0
    z = system("/bin/rm -f " + ffes_shell_quote(out_path))
    written = ffw_dump_current(st, out_path) ## i64
    if written != applied
      meta[14] = 0 - 6
      return 0 - 6
    replay = i64[ffw_state_size(capacity)]
    reloaded = ffw_load_scheme_cap(replay, out_path, n, capacity, 91411, 0, 1, 1, 1) ## i64
    if reloaded != applied || ffw_verify_current_exact(replay, n) != 1
      z = system("/bin/rm -f " + ffes_shell_quote(out_path))
      meta[14] = 0 - 6
      return 0 - 6
  applied
