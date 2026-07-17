# Transpose-involution quotient for equal-outer-dimension shapes <n,m,n>
# (move 4 intake, lane prefix ffpsi_).
#
# EXACT CONTENT.  For the trilinear form trace(A B C) with A n x m,
# B m x n, C n x n (w packed output-side as bit i*n + k), the involution
#   psi(A, B, C) = (B^T, A^T, C^T)
# fixes the matmul tensor: trace(ABC) = trace((ABC)^T) = trace(C^T B^T A^T).
# On factor masks the action is
#   new_u(i, j) = v(j, i),   new_v(j, k) = u(k, j),   new_w(i, k) = w(k, i),
# which this lane verifies numerically on exact schemes (the automorphism
# check is a test invariant, not an assumption).  A psi-invariant scheme of
# rank r = 2c + f is c conjugate pairs {t, psi(t)} plus f fixed terms
# (v = u^T and w symmetric), so f is congruent to r mod 2 -- rank 17 for
# <2,5,2> forces at least one fixed term in any symmetric witness.
#
# QUOTIENT EXISTENCE SAT (in-process CDCL): unknowns are c pair
# representatives (full u/v/w bit blocks) and f fixed generators (u block +
# symmetric w block; the v block is WIRED to u through the transpose
# position map, not allocated).  A pair's second image shares the
# representative's variables through the psi position maps, so rank-r
# existence collapses to c + f unknown generators.  One XOR row per
# coefficient cell over all 2c + f Tseitin products equals the matmul
# coefficient; all cells are constrained (no orbit quotient of rows --
# correctness first), so any model expands to an exact scheme by
# construction.  Emission order: products/guards/symmetry first, XOR rows
# last (ffcdcl_add_xor auxiliaries land above the fixed numbering).
#
# Strassen itself is psi-symmetric ((9,9,9) fixed + three pairs), so the
# (c=3, f=1) rank-7 cell for <2,2,2> carries a planted witness; rank 6 at
# (c=3, f=0) is a planted UNSAT.
#
# ADMISSION.  Models expand to full term lists, parity-compact, and gate
# through the lane's own exhaustive rectangular Brent verifier (shapes like
# <2,5,2> are outside the ffr allowlist); square shapes are cross-gated
# with the ffw worker as well by the tests.

use metaflip_worker
use flipfleet_sat_cdcl

# ---------------------------------------------------------------------------
# psi action and census

-> ffpsi_apply_u(u, v, w, n, m) (i64 i64 i64 i64 i64) i64
  out = 0 ## i64
  i = 0 ## i64
  while i < n
    j = 0 ## i64
    while j < m
      if ((v >> (j * n + i)) & 1) == 1
        out = out | (1 << (i * m + j))
      j += 1
    i += 1
  out

-> ffpsi_apply_v(u, v, w, n, m) (i64 i64 i64 i64 i64) i64
  out = 0 ## i64
  j = 0 ## i64
  while j < m
    k = 0 ## i64
    while k < n
      if ((u >> (k * m + j)) & 1) == 1
        out = out | (1 << (j * n + k))
      k += 1
    j += 1
  out

-> ffpsi_apply_w(u, v, w, n, m) (i64 i64 i64 i64 i64) i64
  out = 0 ## i64
  i = 0 ## i64
  while i < n
    k = 0 ## i64
    while k < n
      if ((w >> (k * n + i)) & 1) == 1
        out = out | (1 << (i * n + k))
      k += 1
    i += 1
  out

-> ffpsi_is_fixed(u, v, w, n, m) (i64 i64 i64 i64 i64) i64
  if ffpsi_apply_u(u, v, w, n, m) == u && ffpsi_apply_v(u, v, w, n, m) == v && ffpsi_apply_w(u, v, w, n, m) == w
    return 1
  0

# Census of a psi-closed term set.  profile (i64[4]): [0] pairs, [1] fixed,
# [2] closure flag, [3] reserved.  Returns pairs + fixed group count, or -1
# when the set is not psi-closed.
-> ffpsi_census(us, vs, ws, rank, n, m, profile) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  profile[0] = 0
  profile[1] = 0
  profile[2] = 0
  profile[3] = 0
  seen = i64[rank + 1]
  groups = 0 ## i64
  i = 0 ## i64
  while i < rank
    if seen[i] == 0
      pu = ffpsi_apply_u(us[i], vs[i], ws[i], n, m) ## i64
      pv = ffpsi_apply_v(us[i], vs[i], ws[i], n, m) ## i64
      pw = ffpsi_apply_w(us[i], vs[i], ws[i], n, m) ## i64
      if pu == us[i] && pv == vs[i] && pw == ws[i]
        seen[i] = 1
        profile[1] = profile[1] + 1
        groups += 1
      else
        j = 0 ## i64
        partner = 0 - 1 ## i64
        while j < rank
          if seen[j] == 0 && j != i && us[j] == pu && vs[j] == pv && ws[j] == pw
            partner = j
            j = rank
          j += 1
        if partner < 0
          return 0 - 1
        seen[i] = 1
        seen[partner] = 1
        profile[0] = profile[0] + 1
        groups += 1
    i += 1
  profile[2] = 1
  groups

# ---------------------------------------------------------------------------
# Exhaustive rectangular Brent verifier (the lane's own gate; <n,m,n> with
# arbitrary small dims, independent of the ffr allowlist).

-> ffpsi_verify_rect(us, vs, ws, count, n, m, p) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  a = 0 ## i64
  while a < um
    b = 0 ## i64
    while b < vm
      c = 0 ## i64
      while c < wm
        acc = 0 ## i64
        t = 0 ## i64
        while t < count
          acc = acc ^ (((us[t] >> a) & 1) & ((vs[t] >> b) & 1) & ((ws[t] >> c) & 1))
          t += 1
        i = a / m ## i64
        j = a % m ## i64
        j2 = b / p ## i64
        k = b % p ## i64
        i2 = c / p ## i64
        k2 = c % p ## i64
        want = 0 ## i64
        if j == j2 && i == i2 && k == k2
          want = 1
        if acc != want
          return 0
        c += 1
      b += 1
    a += 1
  1

# ---------------------------------------------------------------------------
# Variable map

-> ffpsi_pair_base(k, um, vm, wm) (i64 i64 i64 i64) i64
  1 + k * (um + vm + wm)

# Fixed generators carry u (um bits) + w (wm bits); the v block is wired
# to u through the transpose position map and is never allocated.
-> ffpsi_fixed_base(c, q, um, vm, wm) (i64 i64 i64 i64 i64) i64
  1 + c * (um + vm + wm) + q * (um + wm)

-> ffpsi_prim(c, f, um, vm, wm) (i64 i64 i64 i64 i64) i64
  c * (um + vm + wm) + f * (um + wm)

-> ffpsi_product_var(prim, slots, cell, slot) (i64 i64 i64 i64) i64
  prim + 1 + cell * slots + slot

# The three literal-encoded variable inputs for product slot `slot` at cell
# (a, b, cc), written into vars[0..2].  Slots 0..2c-1 are pair images
# (even = representative, odd = psi image); slots 2c.. are fixed terms.
-> ffpsi_slot_inputs(slot, c, n, m, um, vm, wm, a, b, cc, vars) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[]) i64
  p = n ## i64
  if slot < 2 * c
    k = slot / 2 ## i64
    base = ffpsi_pair_base(k, um, vm, wm) ## i64
    if slot % 2 == 0
      vars[0] = base + a
      vars[1] = base + um + b
      vars[2] = base + um + vm + cc
    else
      i = a / m ## i64
      j = a % m ## i64
      vars[0] = base + um + j * p + i
      j2 = b / p ## i64
      k2 = b % p ## i64
      vars[1] = base + k2 * m + j2
      i2 = cc / p ## i64
      kk = cc % p ## i64
      vars[2] = base + um + vm + kk * p + i2
    return 1
  q = slot - 2 * c ## i64
  base = ffpsi_fixed_base(c, q, um, vm, wm) ## i64
  vars[0] = base + a
  j2 = b / p ## i64
  k2 = b % p ## i64
  vars[1] = base + k2 * m + j2
  vars[2] = base + um + cc
  1

# Chained lexicographic ordering A <= B over two equal-width variable
# blocks (standard SBP: prefix-equality auxiliaries allocated above the
# current top variable).  Sound for interchangeable slots: any model
# permutes into lex order, and UNSAT under the ordering still certifies
# class UNSAT.  Returns 1, or 0 on arena failure.
-> ffpsi_lex_chain(sat, base_a, base_b, width) (i64[] i64 i64 i64) i64
  lits = i64[5]
  if width < 1
    return 1
  lits[0] = 2 * (base_a + 0) + 1
  lits[1] = 2 * (base_b + 0)
  if ffcdcl_add_clause(sat, lits, 2) != 1
    return 0
  if width == 1
    return 1
  e = ffcdcl_top_var(sat) ## i64
  i = 1 ## i64
  while i < width
    ev = e + i ## i64
    prev = e + i - 1 ## i64
    a = base_a + i - 1 ## i64
    b = base_b + i - 1 ## i64
    # e_1 hangs off position 0 directly; deeper links chain.
    if i == 1
      # e_1 -> (A_0 == B_0); (A_0 == B_0) -> e_1.
      lits[0] = 2 * ev + 1
      lits[1] = 2 * a + 1
      lits[2] = 2 * b
      if ffcdcl_add_clause(sat, lits, 3) != 1
        return 0
      lits[0] = 2 * ev + 1
      lits[1] = 2 * a
      lits[2] = 2 * b + 1
      if ffcdcl_add_clause(sat, lits, 3) != 1
        return 0
      lits[0] = 2 * ev
      lits[1] = 2 * a
      lits[2] = 2 * b
      if ffcdcl_add_clause(sat, lits, 3) != 1
        return 0
      lits[0] = 2 * ev
      lits[1] = 2 * a + 1
      lits[2] = 2 * b + 1
      if ffcdcl_add_clause(sat, lits, 3) != 1
        return 0
    else
      # e_i <-> e_{i-1} and (A_{i-1} == B_{i-1}).
      lits[0] = 2 * ev + 1
      lits[1] = 2 * prev
      if ffcdcl_add_clause(sat, lits, 2) != 1
        return 0
      lits[0] = 2 * ev + 1
      lits[1] = 2 * a + 1
      lits[2] = 2 * b
      if ffcdcl_add_clause(sat, lits, 3) != 1
        return 0
      lits[0] = 2 * ev + 1
      lits[1] = 2 * a
      lits[2] = 2 * b + 1
      if ffcdcl_add_clause(sat, lits, 3) != 1
        return 0
      lits[0] = 2 * ev
      lits[1] = 2 * prev + 1
      lits[2] = 2 * a
      lits[3] = 2 * b
      if ffcdcl_add_clause(sat, lits, 4) != 1
        return 0
      lits[0] = 2 * ev
      lits[1] = 2 * prev + 1
      lits[2] = 2 * a + 1
      lits[3] = 2 * b + 1
      if ffcdcl_add_clause(sat, lits, 4) != 1
        return 0
    # Given prefix equality, A_i <= B_i.
    lits[0] = 2 * ev + 1
    lits[1] = 2 * (base_a + i) + 1
    lits[2] = 2 * (base_b + i)
    if ffcdcl_add_clause(sat, lits, 3) != 1
      return 0
    i += 1
  1

# Lex-order the interchangeable slots: consecutive pair representatives
# over their full u|v|w blocks, consecutive fixed generators over u|w.
# Emit AFTER the XOR rows (auxiliaries stack above everything).
-> ffpsi_encode_sbps(sat, n, m, c, f) (i64[] i64 i64 i64 i64) i64
  p = n ## i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  k = 0 ## i64
  while k + 1 < c
    if ffpsi_lex_chain(sat, ffpsi_pair_base(k, um, vm, wm), ffpsi_pair_base(k + 1, um, vm, wm), um + vm + wm) != 1
      return 0
    k += 1
  q = 0 ## i64
  while q + 1 < f
    if ffpsi_lex_chain(sat, ffpsi_fixed_base(c, q, um, vm, wm), ffpsi_fixed_base(c, q + 1, um, vm, wm), um + wm) != 1
      return 0
    q += 1
  1

# Bit of a dense cell-indexed GF(2) target (cell = (a*vm + b)*wm + cc).
-> ffpsi_target_bit(target, cell) (i64[] i64) i64
  (target[cell / 64] >> (cell % 64)) & 1

# XOR a rank-one tensor into a dense cell-indexed target.
-> ffpsi_xor_outer(target, u, v, w, um, vm, wm) (i64[] i64 i64 i64 i64 i64 i64) i64
  a = 0 ## i64
  while a < um
    if ((u >> a) & 1) == 1
      b = 0 ## i64
      while b < vm
        if ((v >> b) & 1) == 1
          cc = 0 ## i64
          while cc < wm
            if ((w >> cc) & 1) == 1
              cell = (a * vm + b) * wm + cc ## i64
              target[cell / 64] = target[cell / 64] ^ (1 << (cell % 64))
            cc += 1
        b += 1
    a += 1
  1

# Guards, symmetry, and Tseitin products (everything except the rows).
-> ffpsi_encode_structure(sat, n, m, c, f) (i64[] i64 i64 i64 i64) i64
  p = n ## i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  cells = um * vm * wm ## i64
  prim = ffpsi_prim(c, f, um, vm, wm) ## i64
  slots = 2 * c + f ## i64
  lits = i64[um + vm + wm + 4]
  vars = i64[4]
  xvars = i64[slots + 2]
  # Nonzero guards: every pair factor block, every fixed u and w block.
  k = 0 ## i64
  while k < c
    base = ffpsi_pair_base(k, um, vm, wm) ## i64
    pos = 0 ## i64
    while pos < um
      lits[pos] = 2 * (base + pos)
      pos += 1
    if ffcdcl_add_clause(sat, lits, um) != 1
      return 0
    pos = 0
    while pos < vm
      lits[pos] = 2 * (base + um + pos)
      pos += 1
    if ffcdcl_add_clause(sat, lits, vm) != 1
      return 0
    pos = 0
    while pos < wm
      lits[pos] = 2 * (base + um + vm + pos)
      pos += 1
    if ffcdcl_add_clause(sat, lits, wm) != 1
      return 0
    k += 1
  q = 0 ## i64
  while q < f
    base = ffpsi_fixed_base(c, q, um, vm, wm) ## i64
    pos = 0 ## i64
    while pos < um
      lits[pos] = 2 * (base + pos)
      pos += 1
    if ffcdcl_add_clause(sat, lits, um) != 1
      return 0
    pos = 0
    while pos < wm
      lits[pos] = 2 * (base + um + pos)
      pos += 1
    if ffcdcl_add_clause(sat, lits, wm) != 1
      return 0
    # Symmetry of the fixed w block: w(i,k) == w(k,i).
    i = 0 ## i64
    while i < n
      kk = i + 1 ## i64
      while kk < n
        wa = base + um + i * p + kk ## i64
        wb = base + um + kk * p + i ## i64
        lits[0] = 2 * wa + 1
        lits[1] = 2 * wb
        if ffcdcl_add_clause(sat, lits, 2) != 1
          return 0
        lits[0] = 2 * wa
        lits[1] = 2 * wb + 1
        if ffcdcl_add_clause(sat, lits, 2) != 1
          return 0
        kk += 1
      i += 1
    q += 1
  # Pass 1: Tseitin products (fixed numbering).
  cell = 0 ## i64
  while cell < cells
    cc = cell % wm ## i64
    rest = cell / wm ## i64
    b = rest % vm ## i64
    a = rest / vm ## i64
    slot = 0 ## i64
    while slot < slots
      pv = ffpsi_product_var(prim, slots, cell, slot) ## i64
      z = ffpsi_slot_inputs(slot, c, n, m, um, vm, wm, a, b, cc, vars) ## i64
      lits[0] = 2 * pv + 1
      lits[1] = 2 * vars[0]
      if ffcdcl_add_clause(sat, lits, 2) != 1
        return 0
      lits[1] = 2 * vars[1]
      if ffcdcl_add_clause(sat, lits, 2) != 1
        return 0
      lits[1] = 2 * vars[2]
      if ffcdcl_add_clause(sat, lits, 2) != 1
        return 0
      lits[0] = 2 * pv
      lits[1] = 2 * vars[0] + 1
      lits[2] = 2 * vars[1] + 1
      lits[3] = 2 * vars[2] + 1
      if ffcdcl_add_clause(sat, lits, 4) != 1
        return 0
      slot += 1
    cell += 1
  1

# Encode a (c, f) psi-invariant instance whose rows equal an ARBITRARY
# psi-invariant target tensor (dense bitset over the cell index
# (a*vm + b)*wm + cc) -- the matmul target for whole-scheme existence, or
# an excision residual for descent surgery.  Returns 1, or 0 on arena
# failure.
-> ffpsi_encode_target(sat, n, m, c, f, target) (i64[] i64 i64 i64 i64 i64[]) i64
  p = n ## i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  cells = um * vm * wm ## i64
  prim = ffpsi_prim(c, f, um, vm, wm) ## i64
  slots = 2 * c + f ## i64
  xvars = i64[slots + 2]
  if ffpsi_encode_structure(sat, n, m, c, f) != 1
    return 0
  cell = 0 ## i64
  while cell < cells
    slot = 0 ## i64
    while slot < slots
      xvars[slot] = ffpsi_product_var(prim, slots, cell, slot)
      slot += 1
    if ffcdcl_add_xor(sat, xvars, slots, ffpsi_target_bit(target, cell)) != 1
      return 0
    cell += 1
  1

# Whole-scheme existence: rows equal the matmul tensor.
-> ffpsi_encode(sat, n, m, c, f) (i64[] i64 i64 i64 i64) i64
  p = n ## i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  cells = um * vm * wm ## i64
  target = i64[cells / 64 + 2]
  cell = 0 ## i64
  while cell < cells
    cc = cell % wm ## i64
    rest = cell / wm ## i64
    b = rest % vm ## i64
    a = rest / vm ## i64
    i = a / m ## i64
    j = a % m ## i64
    j2 = b / p ## i64
    k2 = b % p ## i64
    i2 = cc / p ## i64
    kk = cc % p ## i64
    if j == j2 && i == i2 && k2 == kk
      target[cell / 64] = target[cell / 64] | (1 << (cell % 64))
    cell += 1
  ffpsi_encode_target(sat, n, m, c, f, target)

# Decode a model into the expanded term list (2c + f raw terms; caller
# parity-compacts through toggles or accepts the raw list -- distinct
# nonzero terms are guaranteed only by the gate).  Returns the term count.
-> ffpsi_decode(sat, n, m, c, f, out_u, out_v, out_w) (i64[] i64 i64 i64 i64 i64[] i64[] i64[]) i64
  p = n ## i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  count = 0 ## i64
  k = 0 ## i64
  while k < c
    base = ffpsi_pair_base(k, um, vm, wm) ## i64
    u = 0 ## i64
    v = 0 ## i64
    w = 0 ## i64
    pos = 0 ## i64
    while pos < um
      if ffcdcl_value(sat, base + pos) == 1
        u = u | (1 << pos)
      pos += 1
    pos = 0
    while pos < vm
      if ffcdcl_value(sat, base + um + pos) == 1
        v = v | (1 << pos)
      pos += 1
    pos = 0
    while pos < wm
      if ffcdcl_value(sat, base + um + vm + pos) == 1
        w = w | (1 << pos)
      pos += 1
    out_u[count] = u
    out_v[count] = v
    out_w[count] = w
    count += 1
    out_u[count] = ffpsi_apply_u(u, v, w, n, m)
    out_v[count] = ffpsi_apply_v(u, v, w, n, m)
    out_w[count] = ffpsi_apply_w(u, v, w, n, m)
    count += 1
    k += 1
  q = 0 ## i64
  while q < f
    base = ffpsi_fixed_base(c, q, um, vm, wm) ## i64
    u = 0 ## i64
    w = 0 ## i64
    pos = 0 ## i64
    while pos < um
      if ffcdcl_value(sat, base + pos) == 1
        u = u | (1 << pos)
      pos += 1
    pos = 0
    while pos < wm
      if ffcdcl_value(sat, base + um + pos) == 1
        w = w | (1 << pos)
      pos += 1
    v = 0 ## i64
    j = 0 ## i64
    while j < m
      kk = 0 ## i64
      while kk < p
        if ((u >> (kk * m + j)) & 1) == 1
          v = v | (1 << (j * p + kk))
        kk += 1
      j += 1
    out_u[count] = u
    out_v[count] = v
    out_w[count] = w
    count += 1
    q += 1
  count

# ---------------------------------------------------------------------------
# One existence solve

# Solve the (c, f) psi-invariant existence cell for <n, m, n>.
# meta (i64[16]): [0] vars [1] clauses [2] status [3] conflicts
# [4] decoded terms [5] compacted rank [6] gate flag [7] elapsed ms.
# Returns the gated compacted rank on SAT, 0 on UNSAT/budget, negative on
# structural errors (-1 plan, -2 encode).
-> ffpsi_solve(n, m, c, f, budget, seed, out_u, out_v, out_w, meta) (i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  i = 0 ## i64
  while i < 16
    meta[i] = 0
    i += 1
  started = ccall("__w_clock_ms") ## i64
  if n < 2 || n > 5 || m < 2 || m > 6 || c < 0 || f < 0 || c + f < 1
    return 0 - 1
  p = n ## i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  if um > 60 || vm > 60 || wm > 60
    return 0 - 1
  cells = um * vm * wm ## i64
  slots = 2 * c + f ## i64
  prim = ffpsi_prim(c, f, um, vm, wm) ## i64
  aux = cells * (slots + 2) + (c + f) * (um + vm + wm) + 64 ## i64
  max_vars = prim + cells * slots + aux + 64 ## i64
  # Learnt clauses live in the same arena and are never reclaimed, so deep
  # campaigns must size it with the conflict budget.  Measured on the
  # <2,5,2> rank-17 cells: ~77 words per learnt clause (wide XOR-chain
  # conflicts), so budget * 96 with a 64M-word cap (~512 MB, one instance
  # at a time).
  learnt_words = budget * 96 ## i64
  if learnt_words > 64000000
    learnt_words = 64000000
  if learnt_words < 0
    learnt_words = 0
  clause_words = cells * slots * 30 + cells * (slots + 2) * 12 + (c + f) * (um + vm + wm + 8) * 4 + 300000 + learnt_words ## i64
  sat = i64[ffcdcl_state_size(max_vars, clause_words)]
  if ffcdcl_init(sat, max_vars, seed) != 1
    return 0 - 2
  if ffpsi_encode(sat, n, m, c, f) != 1
    return 0 - 2
  if ffpsi_encode_sbps(sat, n, m, c, f) != 1
    return 0 - 2
  meta[0] = ffcdcl_top_var(sat)
  meta[1] = ffcdcl_clause_count(sat)
  assumptions = i64[1]
  status = ffcdcl_solve(sat, assumptions, 0, budget) ## i64
  meta[2] = status
  meta[3] = ffcdcl_conflicts(sat)
  meta[7] = ccall("__w_clock_ms") - started
  if status != 1
    return 0
  raw = ffpsi_decode(sat, n, m, c, f, out_u, out_v, out_w) ## i64
  meta[4] = raw
  # Parity-compact: equal terms cancel pairwise; zero factors drop.
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
  meta[5] = kept
  if kept < 1 || ffpsi_verify_rect(compact_u, compact_v, compact_w, kept, n, m, p) != 1
    return 0
  meta[6] = 1
  i = 0
  while i < kept
    out_u[i] = compact_u[i]
    out_v[i] = compact_v[i]
    out_w[i] = compact_w[i]
    i += 1
  kept
