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
# construction.  Whole-matmul solves additionally expose two fixed-cell
# rank-two consequences; arbitrary residual solves do not.  Emission order:
# products/guards/symmetry first, XOR rows last (ffcdcl_add_xor auxiliaries
# land above the fixed numbering).
#
# Strassen itself is psi-symmetric with two conjugate pairs and three fixed
# terms, so the (c=2, f=3) rank-7 cell for <2,2,2> carries a planted witness.
# The fixed-cell rank consequence closes (c=3, f=1); rank 6 at (c=3, f=0)
# is the independent planted UNSAT.
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

# Variable at block position `pos` after applying psi to one pair
# representative.  The block order is u|v|w and the returned identifier is
# one-based, like `base`.
-> ffpsi_pair_psi_var(base, pos, n, m) (i64 i64 i64 i64) i64
  p = n ## i64
  um = n * m ## i64
  vm = m * p ## i64
  if pos < um
    i = pos / m ## i64
    j = pos % m ## i64
    return base + um + j * p + i
  if pos < um + vm
    b = pos - um ## i64
    j = b / p ## i64
    k = b % p ## i64
    return base + k * m + j
  cc = pos - um - vm ## i64
  i = cc / p ## i64
  k = cc % p ## i64
  base + um + vm + k * p + i

# A full X <= psi(X) comparison only needs the earlier endpoint of every
# nontrivial two-cycle.  Fixed coordinates and later endpoints cannot be the
# first difference.  There are n*m u<->v^T cycles and n*(n-1)/2 off-diagonal
# w<->w^T cycles.
-> ffpsi_pair_orientation_width(n, m) (i64 i64) i64
  n * m + (n * (n - 1)) / 2

# Chained lexicographic ordering over two caller-provided variable lists.
# This is the permuted-block counterpart of ffpsi_lex_chain.  The leading
# clause first exposes primary variables to ffcdcl_top_var; in production all
# structural/XOR variables are already present, and every auxiliary therefore
# stacks freshly above them and above prior chains.
-> ffpsi_lex_vars(sat, left, right, width) (i64[] i64[] i64[] i64) i64
  lits = i64[5]
  if width < 1
    return 1
  lits[0] = 2 * left[0] + 1
  lits[1] = 2 * right[0]
  if ffcdcl_add_clause(sat, lits, 2) != 1
    return 0
  if width == 1
    return 1
  e = ffcdcl_top_var(sat) ## i64
  i = 1 ## i64
  while i < width
    ev = e + i ## i64
    prev = e + i - 1 ## i64
    a = left[i - 1] ## i64
    b = right[i - 1] ## i64
    if i == 1
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
    lits[0] = 2 * ev + 1
    lits[1] = 2 * left[i] + 1
    lits[2] = 2 * right[i]
    if ffcdcl_add_clause(sat, lits, 3) != 1
      return 0
    i += 1
  1

# Choose the canonical orientation X <= psi(X) of one unordered conjugate
# pair.  Comparing only earlier two-cycle endpoints is exactly equivalent to
# comparing the complete u|v|w blocks.
-> ffpsi_encode_pair_orientation(sat, base, n, m) (i64[] i64 i64 i64) i64
  full_width = 2 * n * m + n * n ## i64
  width = ffpsi_pair_orientation_width(n, m) ## i64
  if width < 1
    return 1
  left = i64[width]
  right = i64[width]
  pos = 0 ## i64
  coord = 0 ## i64
  while pos < full_width
    mapped = ffpsi_pair_psi_var(base, pos, n, m) ## i64
    if base + pos < mapped
      left[coord] = base + pos
      right[coord] = mapped
      coord += 1
    pos += 1
  if coord != width
    return 0
  ffpsi_lex_vars(sat, left, right, width)

-> ffpsi_lex_aux_count(width) (i64) i64
  if width <= 1
    return 0
  width - 1

# Exact number of prefix variables added by ffpsi_encode_sbps.  This is used
# for solver capacity and as a regression invariant for fresh, nonoverlapping
# auxiliary ranges.
-> ffpsi_sbp_aux_count(n, m, c, f) (i64 i64 i64 i64) i64
  pair_width = 2 * n * m + n * n ## i64
  fixed_width = n * m + n * n ## i64
  pair_chains = c - 1 ## i64
  fixed_chains = f - 1 ## i64
  if pair_chains < 0
    pair_chains = 0
  if fixed_chains < 0
    fixed_chains = 0
  c * ffpsi_lex_aux_count(ffpsi_pair_orientation_width(n, m)) + pair_chains * ffpsi_lex_aux_count(pair_width) + fixed_chains * ffpsi_lex_aux_count(fixed_width)

# Normalize each pair orientation, then lex-order interchangeable pair
# representatives over u|v|w and fixed generators over u|w.  This is sound
# for arbitrary psi-invariant targets, including descent residuals.  Emit
# AFTER the XOR rows so auxiliaries stack above everything.
-> ffpsi_encode_sbps(sat, n, m, c, f) (i64[] i64 i64 i64 i64) i64
  p = n ## i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  k = 0 ## i64
  while k < c
    if ffpsi_encode_pair_orientation(sat, ffpsi_pair_base(k, um, vm, wm), n, m) != 1
      return 0
    k += 1
  k = 0
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

# Whole-matmul coordinate-orbit anchor.  Simultaneous outer/inner index
# permutations commute with psi and act transitively on fixed-generator U
# coordinates.  Every fixed U is nonzero; after fixed blocks are sorted, a
# coordinate permutation can therefore put a supported U(0,0) bit in the
# last block.  This is not sound for an arbitrary descent residual, so it is
# intentionally separate from ffpsi_encode_sbps.
-> ffpsi_encode_matmul_anchor(sat, n, m, c, f) (i64[] i64 i64 i64 i64) i64
  if f < 1
    return 1
  p = n ## i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  anchor = ffpsi_fixed_base(c, f - 1, um, vm, wm) ## i64
  unit = i64[1]
  unit[0] = 2 * anchor
  ffcdcl_add_clause(sat, unit, 1)

# Whole-matmul fixed-cell rank consequences.  On psi-fixed coefficient cells,
# conjugate pairs cancel and fixed generator q contributes
#
#   U_q(i,j) * D_q(i2),
#
# where D_q is the diagonal of its symmetric W factor.  For n=2 this product
# must equal [i == i2].  Hence the D rows span rank two, and for every inner
# coordinate j the two f-bit U row vectors are both nonzero and unequal.  The
# full coefficient system already implies all of these clauses; stating them
# directly is sound only for the whole matmul target, not a descent residual.
-> ffpsi_encode_matmul_rank_consequences(sat, n, m, c, f) (i64[] i64 i64 i64 i64) i64
  if n != 2 || f < 1
    return 1
  p = n ## i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  lits = i64[f + 2]
  diff = i64[f + 2]
  # Both fixed-W diagonal columns are nonzero.
  diag = 0 ## i64
  while diag < 2
    q = 0 ## i64
    while q < f
      base = ffpsi_fixed_base(c, q, um, vm, wm) ## i64
      lits[q] = 2 * (base + um + diag * n + diag)
      q += 1
    if ffcdcl_add_clause(sat, lits, f) != 1
      return 0
    diag += 1
  # Some fixed-W diagonal row differs across its two coordinates.
  q = 0
  while q < f
    base = ffpsi_fixed_base(c, q, um, vm, wm) ## i64
    a = base + um ## i64
    b = base + um + n + 1 ## i64
    d = ffcdcl_top_var(sat) + 1 ## i64
    if ffcdcl_add_xor3(sat, a, b, d) != 1
      return 0
    diff[q] = 2 * d
    q += 1
  if ffcdcl_add_clause(sat, diff, f) != 1
    return 0
  # For each inner coordinate, both outer U rows are nonzero and distinct.
  j = 0 ## i64
  while j < m
    q = 0
    while q < f
      base = ffpsi_fixed_base(c, q, um, vm, wm) ## i64
      lits[q] = 2 * (base + j)
      q += 1
    if ffcdcl_add_clause(sat, lits, f) != 1
      return 0
    q = 0
    while q < f
      base = ffpsi_fixed_base(c, q, um, vm, wm) ## i64
      lits[q] = 2 * (base + m + j)
      q += 1
    if ffcdcl_add_clause(sat, lits, f) != 1
      return 0
    q = 0
    while q < f
      base = ffpsi_fixed_base(c, q, um, vm, wm) ## i64
      a = base + j ## i64
      b = base + m + j ## i64
      d = ffcdcl_top_var(sat) + 1 ## i64
      if ffcdcl_add_xor3(sat, a, b, d) != 1
        return 0
      diff[q] = 2 * d
      q += 1
    if ffcdcl_add_clause(sat, diff, f) != 1
      return 0
    j += 1
  1

-> ffpsi_encode_matmul_sbps(sat, n, m, c, f) (i64[] i64 i64 i64 i64) i64
  if ffpsi_encode_matmul_rank_consequences(sat, n, m, c, f) != 1
    return 0
  if ffpsi_encode_sbps(sat, n, m, c, f) != 1
    return 0
  ffpsi_encode_matmul_anchor(sat, n, m, c, f)

# Bit of a dense cell-indexed GF(2) target (cell = (a*vm + b)*wm + cc).
-> ffpsi_target_bit(target, cell) (i64[] i64) i64
  (target[cell / 64] >> (cell % 64)) & 1

# Induced psi involution on coefficient cells.  A cell indexes
# u(i,j) * v(j2,k) * w(i2,k2); psi sends it to
# u(k,j2) * v(j,i) * w(k2,i2).  This is shared by the compact whole-matmul
# encoder below and independently checked against the full-row encoder.
-> ffpsi_cell_mate(cell, n, m) (i64 i64 i64) i64
  p = n ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  cc = cell % wm ## i64
  rest = cell / wm ## i64
  b = rest % vm ## i64
  a = rest / vm ## i64
  i = a / m ## i64
  j = a % m ## i64
  j2 = b / p ## i64
  k = b % p ## i64
  i2 = cc / p ## i64
  k2 = cc % p ## i64
  mate_a = k * m + j2 ## i64
  mate_b = j * p + i ## i64
  mate_c = k2 * p + i2 ## i64
  (mate_a * vm + mate_b) * wm + mate_c

-> ffpsi_cell_orbit_count(n, m) (i64 i64) i64
  p = n ## i64
  cells = (n * m) * (m * p) * (n * p) ## i64
  count = 0 ## i64
  cell = 0 ## i64
  while cell < cells
    if cell <= ffpsi_cell_mate(cell, n, m)
      count += 1
    cell += 1
  count

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

# Compact whole-matmul encoding over one representative of every coefficient
# orbit.  A psi-closed term set has equal coefficients on a cell and its mate,
# and the matmul target has the same invariance.  On fixed cells the products
# from the two members of each conjugate term pair are identical and cancel
# over GF(2), so only fixed-generator products remain.  This is an exact
# quotient of ffpsi_encode, not a sampled row set.  The full-row encoder stays
# available above as an independent control and for arbitrary targets.
-> ffpsi_encode_matmul_quotient(sat, n, m, c, f) (i64[] i64 i64 i64 i64) i64
  p = n ## i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  cells = um * vm * wm ## i64
  slots = 2 * c + f ## i64
  lits = i64[um + vm + wm + slots + 4]
  vars = i64[4]
  xvars = i64[slots + 2]
  # Nonzero pair factors.
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
  # Nonzero fixed factors and symmetric W blocks.
  q = 0 ## i64
  while q < f
    base = ffpsi_fixed_base(c, q, um, vm, wm) ## i64
    pos = 0
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
  cell = 0 ## i64
  while cell < cells
    mate = ffpsi_cell_mate(cell, n, m) ## i64
    if cell <= mate
      cc = cell % wm ## i64
      rest = cell / wm ## i64
      b = rest % vm ## i64
      a = rest / vm ## i64
      first_slot = 0 ## i64
      if cell == mate
        first_slot = 2 * c
      row_count = slots - first_slot ## i64
      slot = first_slot
      row_pos = 0 ## i64
      while slot < slots
        # Allocate products above the live top because each prior XOR row may
        # have inserted its own chain auxiliaries.
        pv = ffcdcl_top_var(sat) + 1 ## i64
        z = ffpsi_slot_inputs(slot, c, n, m, um, vm, wm, a, b, cc, vars) ## i64
        if slot >= 2 * c && vars[0] == vars[1]
          # Duplicate wired U/V inputs reduce the cubic monomial to U & W.
          lits[0] = 2 * pv + 1
          lits[1] = 2 * vars[0]
          if ffcdcl_add_clause(sat, lits, 2) != 1
            return 0
          lits[1] = 2 * vars[2]
          if ffcdcl_add_clause(sat, lits, 2) != 1
            return 0
          lits[0] = 2 * pv
          lits[1] = 2 * vars[0] + 1
          lits[2] = 2 * vars[2] + 1
          if ffcdcl_add_clause(sat, lits, 3) != 1
            return 0
        else
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
        xvars[row_pos] = pv
        row_pos += 1
        slot += 1
      i2 = cc / p ## i64
      j = a % m ## i64
      i = a / m ## i64
      j2 = b / p ## i64
      k2 = b % p ## i64
      kk = cc % p ## i64
      want = 0 ## i64
      if j == j2 && i == i2 && k2 == kk
        want = 1
      if row_count == 0 && want == 1
        # Preserve an impossible odd empty row as an explicit contradiction
        # without misclassifying normal UNSAT as an arena/encoding failure.
        lits[0] = 2
        if ffcdcl_add_clause(sat, lits, 1) != 1
          return 0
        lits[0] = 3
        if ffcdcl_add_clause(sat, lits, 1) != 1
          return 0
      else
        if ffcdcl_add_xor(sat, xvars, row_count, want) != 1
          return 0
    cell += 1
  1

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
  fixed_cells = n * n * m ## i64
  paired_orbits = (cells - fixed_cells) / 2 ## i64
  orbit_rows = paired_orbits + fixed_cells ## i64
  product_vars = paired_orbits * slots + fixed_cells * f ## i64
  pair_xor_aux = slots - 2 ## i64
  if pair_xor_aux < 0
    pair_xor_aux = 0
  fixed_xor_aux = f - 2 ## i64
  if fixed_xor_aux < 0
    fixed_xor_aux = 0
  xor_aux = paired_orbits * pair_xor_aux + fixed_cells * fixed_xor_aux ## i64
  rank_aux = 0 ## i64
  if n == 2 && f > 0
    rank_aux = f * (m + 1)
  sbp_aux = ffpsi_sbp_aux_count(n, m, c, f) ## i64
  max_vars = prim + product_vars + xor_aux + rank_aux + sbp_aux + 64 ## i64
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
  clause_words = product_vars * 30 + orbit_rows * (slots + 2) * 12 + (c + f) * (um + vm + wm + 8) * 4 + 300000 + learnt_words ## i64
  sat = i64[ffcdcl_state_size(max_vars, clause_words)]
  if ffcdcl_init(sat, max_vars, seed) != 1
    return 0 - 2
  if ffpsi_encode_matmul_quotient(sat, n, m, c, f) != 1
    return 0 - 2
  if ffpsi_encode_matmul_sbps(sat, n, m, c, f) != 1
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
