# Divisor-matched cyclic-sandwich ansatz (move 3 intake, lane prefix
# ffsan_).
#
# EXACT CONTENT.  A shift triple g = (shift^a on I, shift^b on the inner
# index, shift^c on J) generates a cyclic sandwich subgroup of the <n,n,n>
# isotropy group (the flipfleet_sandwich_quotient action; g permutes naive
# terms, so it is an exact automorphism).  This lane solves the EXISTENCE
# question for g-invariant schemes directly: for PRIME group order d, term
# orbits have size d or 1, so a rank-r invariant scheme decomposes as
# r = d*k + f into k free-orbit representatives plus f fixed terms whose
# factors are constrained to the fixed space of the position action
# (bit-orbit equality chains -- the circulant structure).
#
# ENCODING (in-process CDCL, one instance per (g, k, f) cell): k
# representative triples whose d images share the representative's
# variables through constant position maps (image t reads bit position
# (i, j) from (i - t*a, j - t*b) modulo n on the u block, and the matching
# shifted positions on v and w), plus f fixed triples with the bit-orbit
# equality clauses; one XOR row per tensor coefficient cell over all
# d*k + f Tseitin products, rhs the matmul coefficient.  ALL n^6 cells are
# constrained -- no orbit quotient of rows, correctness first -- so any
# model expands to an exact scheme by construction.  Emission order:
# products and guards first, XOR rows last (add_xor auxiliaries land above
# the fixed numbering).
#
# A SAT model is expanded, parity-compacted, and exhaustively gated; an
# UNSAT is a certified closure of ONE (g, k, f) cell -- the g-invariant
# class at rank r is closed only when every divisor partition of r has
# been refuted, which the driver reports cell by cell and never
# aggregates silently.
#
# Position conventions: u bit (i, j) = i*n + j with i in I, j inner;
# v bit (j, k) = j*n + k; w bit (i, k) = i*n + k (the repository packing).
# g maps u(i, j) -> u'(i + a, j + b), v(j, k) -> v'(j + b, k + c),
# w(i, k) -> w'(i + a, k + c), all modulo n.

use metaflip_worker
use flipfleet_sat_cdcl

# ---------------------------------------------------------------------------
# Position maps

-> ffsan_mod(x, n) (i64 i64) i64
  ((x % n) + n) % n

# Source bit position that image t of a representative reads, for an
# axis-pair shifted by (da, db) per step: position (i, j) pulls from
# (i - t*da, j - t*db).
-> ffsan_src_pos(pos, n, t, da, db) (i64 i64 i64 i64 i64) i64
  i = pos / n ## i64
  j = pos % n ## i64
  ffsan_mod(i - t * da, n) * n + ffsan_mod(j - t * db, n)

# Group order of the shift triple (the lcm of the three shift orders on
# Z_n; each shift^s has order n / gcd(n, s)).
-> ffsan_gcd(x, y) (i64 i64) i64
  a = x ## i64
  b = y ## i64
  while b != 0
    t = a % b ## i64
    a = b
    b = t
  a

-> ffsan_order(n, a, b, c) (i64 i64 i64 i64) i64
  oa = n / ffsan_gcd(n, ffsan_mod(a, n)) ## i64
  if ffsan_mod(a, n) == 0
    oa = 1
  ob = n / ffsan_gcd(n, ffsan_mod(b, n)) ## i64
  if ffsan_mod(b, n) == 0
    ob = 1
  oc = n / ffsan_gcd(n, ffsan_mod(c, n)) ## i64
  if ffsan_mod(c, n) == 0
    oc = 1
  l = (oa * ob) / ffsan_gcd(oa, ob) ## i64
  (l * oc) / ffsan_gcd(l, oc)

# Apply g^t to a full term (mask level, for expansion and census).
-> ffsan_shift_mask(mask, n, t, da, db) (i64 i64 i64 i64 i64) i64
  out = 0 ## i64
  pos = 0 ## i64
  while pos < n * n
    if ((mask >> ffsan_src_pos(pos, n, t, da, db)) & 1) == 1
      out = out | (1 << pos)
    pos += 1
  out

# ---------------------------------------------------------------------------
# Variable map: k reps (3 blocks of n^2), then f fixed (3 blocks of n^2),
# then products; XOR auxiliaries above.

-> ffsan_rep_var(slot_term, axis, pos, nn) (i64 i64 i64 i64) i64
  1 + slot_term * 3 * nn + axis * nn + pos

-> ffsan_prim(k, f, nn) (i64 i64 i64) i64
  (k + f) * 3 * nn

-> ffsan_product_var(prim, slots, cell, slot) (i64 i64 i64 i64) i64
  prim + 1 + cell * slots + slot

# Product slot layout: k*d rep images first (rep r image t = slot r*d + t),
# then f fixed products.
-> ffsan_slot_inputs(slot, k, d, n, nn, a, b, c, da, db, dc, vars) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  if slot < k * d
    r = slot / d ## i64
    t = slot % d ## i64
    vars[0] = ffsan_rep_var(r, 0, ffsan_src_pos(a, n, t, da, db), nn)
    vars[1] = ffsan_rep_var(r, 1, ffsan_src_pos(b, n, t, db, dc), nn)
    vars[2] = ffsan_rep_var(r, 2, ffsan_src_pos(c, n, t, da, dc), nn)
    return 1
  q = k + (slot - k * d) ## i64
  vars[0] = ffsan_rep_var(q, 0, a, nn)
  vars[1] = ffsan_rep_var(q, 1, b, nn)
  vars[2] = ffsan_rep_var(q, 2, c, nn)
  1

# Encode one (g, k, f) cell.  Returns 1, or 0 on arena failure.
-> ffsan_encode(sat, n, da, db, dc, d, k, f) (i64[] i64 i64 i64 i64 i64 i64 i64) i64
  nn = n * n ## i64
  cells = nn * nn * nn ## i64
  slots = k * d + f ## i64
  prim = ffsan_prim(k, f, nn) ## i64
  lits = i64[nn + 4]
  vars = i64[4]
  xvars = i64[slots + 2]
  # Nonzero guards for every factor block of every term slot.
  s = 0 ## i64
  while s < k + f
    axis = 0 ## i64
    while axis < 3
      pos = 0 ## i64
      while pos < nn
        lits[pos] = 2 * ffsan_rep_var(s, axis, pos, nn)
        pos += 1
      if ffcdcl_add_clause(sat, lits, nn) != 1
        return 0
      axis += 1
    s += 1
  # Fixed-space equality chains: a fixed term's factor bit equals its image
  # under one generator step, per axis with the matching shift pair.
  q = 0 ## i64
  while q < f
    s = k + q ## i64
    axis = 0
    while axis < 3
      pa = da ## i64
      pb = db ## i64
      if axis == 1
        pa = db
        pb = dc
      if axis == 2
        pa = da
        pb = dc
      pos = 0
      while pos < nn
        src = ffsan_src_pos(pos, n, 1, pa, pb) ## i64
        if src != pos
          va = ffsan_rep_var(s, axis, pos, nn) ## i64
          vb = ffsan_rep_var(s, axis, src, nn) ## i64
          lits[0] = 2 * va + 1
          lits[1] = 2 * vb
          if ffcdcl_add_clause(sat, lits, 2) != 1
            return 0
          lits[0] = 2 * va
          lits[1] = 2 * vb + 1
          if ffcdcl_add_clause(sat, lits, 2) != 1
            return 0
        pos += 1
      axis += 1
    q += 1
  # Pass 1: Tseitin products (fixed numbering).
  cell = 0 ## i64
  while cell < cells
    c = cell % nn ## i64
    rest = cell / nn ## i64
    b = rest % nn ## i64
    a = rest / nn ## i64
    slot = 0 ## i64
    while slot < slots
      p = ffsan_product_var(prim, slots, cell, slot) ## i64
      z = ffsan_slot_inputs(slot, k, d, n, nn, a, b, c, da, db, dc, vars) ## i64
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
  # Pass 2: one XOR row per coefficient cell.
  cell = 0
  while cell < cells
    c = cell % nn ## i64
    rest = cell / nn ## i64
    b = rest % nn ## i64
    a = rest / nn ## i64
    slot = 0
    while slot < slots
      xvars[slot] = ffsan_product_var(prim, slots, cell, slot)
      slot += 1
    i = a / n ## i64
    j = a % n ## i64
    j2 = b / n ## i64
    kk = b % n ## i64
    i2 = c / n ## i64
    k2 = c % n ## i64
    want = 0 ## i64
    if j == j2 && i == i2 && kk == k2
      want = 1
    if ffcdcl_add_xor(sat, xvars, slots, want) != 1
      return 0
    cell += 1
  1

# Decode a model into the expanded term list (k*d + f raw terms).
-> ffsan_decode(sat, n, da, db, dc, d, k, f, out_u, out_v, out_w) (i64[] i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[]) i64
  nn = n * n ## i64
  count = 0 ## i64
  s = 0 ## i64
  while s < k + f
    u = 0 ## i64
    v = 0 ## i64
    w = 0 ## i64
    pos = 0 ## i64
    while pos < nn
      if ffcdcl_value(sat, ffsan_rep_var(s, 0, pos, nn)) == 1
        u = u | (1 << pos)
      if ffcdcl_value(sat, ffsan_rep_var(s, 1, pos, nn)) == 1
        v = v | (1 << pos)
      if ffcdcl_value(sat, ffsan_rep_var(s, 2, pos, nn)) == 1
        w = w | (1 << pos)
      pos += 1
    reps = d ## i64
    if s >= k
      reps = 1
    t = 0 ## i64
    while t < reps
      out_u[count] = ffsan_shift_mask(u, n, t, da, db)
      out_v[count] = ffsan_shift_mask(v, n, t, db, dc)
      out_w[count] = ffsan_shift_mask(w, n, t, da, dc)
      count += 1
      t += 1
    s += 1
  count

# ---------------------------------------------------------------------------
# One existence solve

# Solve the (g = (da, db, dc), k, f) cell for <n,n,n>.  meta (i64[16]):
# [0] group order d  [1] vars  [2] clauses  [3] status  [4] conflicts
# [5] decoded raw terms  [6] compacted rank  [7] gate flag  [8] elapsed ms.
# Returns the gated compacted rank on SAT, 0 on UNSAT/budget, negative on
# structural errors (-1 plan, -2 encode).
-> ffsan_solve(n, da, db, dc, k, f, budget, seed, out_u, out_v, out_w, meta) (i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < 16
    meta[i] = 0
    i += 1
  started = ccall("__w_clock_ms") ## i64
  if n < 2 || n > 4 || k < 0 || f < 0 || k + f < 1
    return 0 - 1
  d = ffsan_order(n, da, db, dc) ## i64
  meta[0] = d
  if d < 2
    return 0 - 1
  nn = n * n ## i64
  cells = nn * nn * nn ## i64
  slots = k * d + f ## i64
  if slots > 40
    return 0 - 1
  prim = ffsan_prim(k, f, nn) ## i64
  aux = cells * (slots + 2) ## i64
  max_vars = prim + cells * slots + aux + 64 ## i64
  learnt_words = budget * 96 ## i64
  if learnt_words > 64000000
    learnt_words = 64000000
  if learnt_words < 0
    learnt_words = 0
  clause_words = cells * slots * 30 + cells * (slots + 2) * 12 + (k + f) * (3 * nn + 8) * 6 + 300000 + learnt_words ## i64
  sat = i64[ffcdcl_state_size(max_vars, clause_words)]
  if ffcdcl_init(sat, max_vars, seed) != 1
    return 0 - 2
  if ffsan_encode(sat, n, da, db, dc, d, k, f) != 1
    return 0 - 2
  meta[1] = ffcdcl_top_var(sat)
  meta[2] = ffcdcl_clause_count(sat)
  assumptions = i64[1]
  status = ffcdcl_solve(sat, assumptions, 0, budget) ## i64
  meta[3] = status
  meta[4] = ffcdcl_conflicts(sat)
  meta[8] = ccall("__w_clock_ms") - started
  if status != 1
    return 0
  raw = ffsan_decode(sat, n, da, db, dc, d, k, f, out_u, out_v, out_w) ## i64
  meta[5] = raw
  compact_u = i64[raw + 1]
  compact_v = i64[raw + 1]
  compact_w = i64[raw + 1]
  kept = 0 ## i64
  i = 0
  while i < raw
    if out_u[i] != 0 && out_v[i] != 0 && out_w[i] != 0
      dup = 0 - 1 ## i64
      j = 0 ## i64
      while j < kept
        if compact_u[j] == out_u[i] && compact_v[j] == out_v[i] && compact_w[j] == out_w[i]
          dup = j
          j = kept
        j += 1
      if dup >= 0
        compact_u[dup] = compact_u[kept - 1]
        compact_v[dup] = compact_v[kept - 1]
        compact_w[dup] = compact_w[kept - 1]
        kept -= 1
      else
        compact_u[kept] = out_u[i]
        compact_v[kept] = out_v[i]
        compact_w[kept] = out_w[i]
        kept += 1
    i += 1
  meta[6] = kept
  if kept < 1
    return 0
  capacity = ffw_default_capacity(n) ## i64
  gate = i64[ffw_state_size(capacity)]
  loaded = ffw_init_terms_cap(gate, compact_u, compact_v, compact_w, kept, n, capacity, 61001 + (seed % 100000), 0, 1, 1, 1) ## i64
  if loaded != kept || ffw_verify_current_exact(gate, n) != 1
    return 0
  meta[7] = 1
  i = 0
  while i < kept
    out_u[i] = compact_u[i]
    out_v[i] = compact_v[i]
    out_w[i] = compact_w[i]
    i += 1
  kept
