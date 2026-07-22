# Native-XOR exporter shared by the <2,5,2> psi campaign and its focused
# regression.  Primitive variables retain the ffpsi_* numbering.  Product
# variables are compacted over one representative of each coefficient-cell
# orbit: a psi-invariant term set has equal coefficients on the two cells in
# an orbit, and the matrix-multiplication target is psi-invariant too.  On a
# fixed cell the two products from every conjugate term pair are identical and
# cancel over GF(2), so only fixed-generator products are materialized there.
# The XNF parity rows need no Tseitin auxiliaries; lex-leader auxiliaries are
# allocated contiguously immediately above the compact products.

use flipfleet_psi_quotient

# A <= B over two equal-width Boolean blocks.  This is the textual DIMACS
# form of ffpsi_lex_chain: e_i means that positions [0, i) are equal, and the
# ordering clause at i is active only under that equal prefix.
-> ffpx_lex_chain_text(base_a, base_b, width, first_aux) (i64 i64 i64 i64)
  if width < 1
    return ""
  out = "-" + base_a.to_s() + " " + base_b.to_s() + " 0\n" ## String
  i = 1 ## i64
  while i < width
    ev = first_aux + i - 1 ## i64
    prev = ev - 1 ## i64
    a = base_a + i - 1 ## i64
    b = base_b + i - 1 ## i64
    if i == 1
      out = out + "-" + ev.to_s() + " -" + a.to_s() + " " + b.to_s() + " 0\n"
      out = out + "-" + ev.to_s() + " " + a.to_s() + " -" + b.to_s() + " 0\n"
      out = out + ev.to_s() + " " + a.to_s() + " " + b.to_s() + " 0\n"
      out = out + ev.to_s() + " -" + a.to_s() + " -" + b.to_s() + " 0\n"
    else
      out = out + "-" + ev.to_s() + " " + prev.to_s() + " 0\n"
      out = out + "-" + ev.to_s() + " -" + a.to_s() + " " + b.to_s() + " 0\n"
      out = out + "-" + ev.to_s() + " " + a.to_s() + " -" + b.to_s() + " 0\n"
      out = out + ev.to_s() + " -" + prev.to_s() + " " + a.to_s() + " " + b.to_s() + " 0\n"
      out = out + ev.to_s() + " -" + prev.to_s() + " -" + a.to_s() + " -" + b.to_s() + " 0\n"
    out = out + "-" + ev.to_s() + " -" + (base_a + i).to_s() + " " + (base_b + i).to_s() + " 0\n"
    i += 1
  out

-> ffpx_lex_aux_count(width) (i64) i64
  if width <= 1
    return 0
  width - 1

-> ffpx_lex_clause_count(width) (i64) i64
  if width < 1
    return 0
  if width == 1
    return 1
  # One leading order clause, five clauses at i=1, and six thereafter.
  6 * (width - 1)

# Variable at block position `pos` after applying psi to one pair
# representative.  The block order is u|v|w and the returned identifier is
# one-based DIMACS, like `base`.
-> ffpx_pair_psi_var(base, pos, n, m) (i64 i64 i64 i64) i64
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

# Number of nontrivial two-cycles in the psi position involution.  Fixed
# coordinates and the later endpoint of a two-cycle can never be the first
# difference between X and psi(X), so the orientation comparator needs only
# the earlier endpoint of each cycle, in block order.
-> ffpx_pair_orientation_width(n, m) (i64 i64) i64
  n * m + (n * (n - 1)) / 2

# Choose one orientation of the unordered conjugate pair {X, psi(X)}.  This
# removes an independent two-way symmetry for every pair generator.  The
# clause template is the same prefix lex leader as ffpx_lex_chain_text, but
# its coordinates are the nontrivial psi two-cycles rather than all block
# positions.  Comparing only those earlier endpoints is exactly equivalent
# to comparing the complete X and psi(X) bit strings.
-> ffpx_pair_orientation_text(base, n, m, first_aux) (i64 i64 i64 i64)
  full_width = 2 * n * m + n * n ## i64
  width = ffpx_pair_orientation_width(n, m) ## i64
  if width < 1
    return ""
  left = i64[width]
  right = i64[width]
  pos = 0 ## i64
  coord = 0 ## i64
  while pos < full_width
    mapped = ffpx_pair_psi_var(base, pos, n, m) ## i64
    if base + pos < mapped
      left[coord] = base + pos
      right[coord] = mapped
      coord += 1
    pos += 1
  a0 = left[0] ## i64
  b0 = right[0] ## i64
  out = "-" + a0.to_s() + " " + b0.to_s() + " 0\n" ## String
  i = 1 ## i64
  while i < width
    ev = first_aux + i - 1 ## i64
    prev = ev - 1 ## i64
    a = left[i - 1] ## i64
    b = right[i - 1] ## i64
    if i == 1
      out = out + "-" + ev.to_s() + " -" + a.to_s() + " " + b.to_s() + " 0\n"
      out = out + "-" + ev.to_s() + " " + a.to_s() + " -" + b.to_s() + " 0\n"
      out = out + ev.to_s() + " " + a.to_s() + " " + b.to_s() + " 0\n"
      out = out + ev.to_s() + " -" + a.to_s() + " -" + b.to_s() + " 0\n"
    else
      out = out + "-" + ev.to_s() + " " + prev.to_s() + " 0\n"
      out = out + "-" + ev.to_s() + " -" + a.to_s() + " " + b.to_s() + " 0\n"
      out = out + "-" + ev.to_s() + " " + a.to_s() + " -" + b.to_s() + " 0\n"
      out = out + ev.to_s() + " -" + prev.to_s() + " " + a.to_s() + " " + b.to_s() + " 0\n"
      out = out + ev.to_s() + " -" + prev.to_s() + " -" + a.to_s() + " -" + b.to_s() + " 0\n"
    out = out + "-" + ev.to_s() + " -" + left[i].to_s() + " " + right[i].to_s() + " 0\n"
    i += 1
  out

-> ffpx_sbp_aux_count(n, m, c, f) (i64 i64 i64 i64) i64
  pair_width = 2 * n * m + n * n ## i64
  orientation_width = ffpx_pair_orientation_width(n, m) ## i64
  fixed_width = n * m + n * n ## i64
  pair_chains = c - 1 ## i64
  fixed_chains = f - 1 ## i64
  if pair_chains < 0
    pair_chains = 0
  if fixed_chains < 0
    fixed_chains = 0
  # Each conjugate pair also has an independent X <-> psi(X) orientation.
  c * ffpx_lex_aux_count(orientation_width) + pair_chains * ffpx_lex_aux_count(pair_width) + fixed_chains * ffpx_lex_aux_count(fixed_width)

-> ffpx_sbp_clause_count(n, m, c, f) (i64 i64 i64 i64) i64
  pair_width = 2 * n * m + n * n ## i64
  orientation_width = ffpx_pair_orientation_width(n, m) ## i64
  fixed_width = n * m + n * n ## i64
  pair_chains = c - 1 ## i64
  fixed_chains = f - 1 ## i64
  if pair_chains < 0
    pair_chains = 0
  if fixed_chains < 0
    fixed_chains = 0
  c * ffpx_lex_clause_count(orientation_width) + pair_chains * ffpx_lex_clause_count(pair_width) + fixed_chains * ffpx_lex_clause_count(fixed_width)

# A cheap symmetry invariant for the interchangeable inner coordinates when
# n=2.  For coordinate j and outer coordinate i, XOR U(i,j) with V(j,i) over
# every pair representative, plus U(i,j) over every fixed generator.
# Reorienting a conjugate pair merely swaps its two inputs, while permuting
# generators does not change the XOR.  A simultaneous outer-index swap swaps
# the two parity bits, so their Hamming weight remains invariant under every
# symmetry already used above.  An inner-coordinate permutation only permutes
# the m weights.  Requiring those weights to be nondecreasing therefore
# selects a representative of every orbit and composes soundly with pair
# orientation, generator sorting, and the remaining outer symmetry.
#
# `first_aux + j*2 + i` is one parity bit.  CryptoMiniSat XNF rows have odd
# literal parity, so negating the first input expresses XOR(inputs, p_ji)=0.
# Four clauses for each adjacent pair forbid weight(j) > weight(j+1), without
# allocating a cardinality network.
-> ffpx_inner_weight_sbp_text(n, m, c, f, first_aux) (i64 i64 i64 i64 i64)
  if n != 2
    return ""
  um = n * m ## i64
  vm = m * n ## i64
  wm = n * n ## i64
  out = "" ## String
  j = 0 ## i64
  while j < m
    i = 0 ## i64
    while i < 2
      line = "x " ## String
      first = 1 ## i64
      k = 0 ## i64
      while k < c
        base = ffpsi_pair_base(k, um, vm, wm) ## i64
        uv = base + i * m + j ## i64
        vv = base + um + j * n + i ## i64
        if first == 1
          line = line + "-" + uv.to_s() + " "
          first = 0
        else
          line = line + uv.to_s() + " "
        line = line + vv.to_s() + " "
        k += 1
      q = 0 ## i64
      while q < f
        base = ffpsi_fixed_base(c, q, um, vm, wm) ## i64
        uv = base + i * m + j ## i64
        if first == 1
          line = line + "-" + uv.to_s() + " "
          first = 0
        else
          line = line + uv.to_s() + " "
        q += 1
      # Every production cell has at least one generator.  Keep the helper
      # total for structural tests with an empty cell as well.
      parity = first_aux + j * 2 + i ## i64
      if first == 1
        out = out + "-" + parity.to_s() + " 0\n"
      else
        out = out + line + parity.to_s() + " 0\n"
      i += 1
    j += 1
  j = 0
  while j + 1 < m
    a0 = first_aux + j * 2 ## i64
    a1 = a0 + 1 ## i64
    b0 = a0 + 2 ## i64
    b1 = a0 + 3 ## i64
    out = out + "-" + a0.to_s() + " " + b0.to_s() + " " + b1.to_s() + " 0\n"
    out = out + "-" + a1.to_s() + " " + b0.to_s() + " " + b1.to_s() + " 0\n"
    out = out + "-" + a0.to_s() + " -" + a1.to_s() + " " + b0.to_s() + " 0\n"
    out = out + "-" + a0.to_s() + " -" + a1.to_s() + " " + b1.to_s() + " 0\n"
    j += 1
  out

-> ffpx_inner_weight_sbp_aux_count(n, m) (i64 i64) i64
  if n != 2 || m < 1
    return 0
  2 * m

-> ffpx_inner_weight_sbp_clause_count(n, m) (i64 i64) i64
  if n != 2 || m < 1
    return 0
  2 * m + 4 * (m - 1)

# Lex-order consecutive pair representatives over u|v|w and consecutive fixed
# generators over u|w.  `first_aux` is one above the last product variable.
-> ffpx_sbp_text(n, m, c, f, first_aux) (i64 i64 i64 i64 i64)
  p = n ## i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  pair_width = um + vm + wm ## i64
  orientation_width = ffpx_pair_orientation_width(n, m) ## i64
  fixed_width = um + wm ## i64
  next_aux = first_aux ## i64
  out = "" ## String
  # Normalize the orientation within each unordered conjugate pair first.
  k = 0 ## i64
  while k < c
    out = out + ffpx_pair_orientation_text(ffpsi_pair_base(k, um, vm, wm), n, m, next_aux)
    next_aux += ffpx_lex_aux_count(orientation_width)
    k += 1
  # Then sort the normalized pair representatives.
  k = 0 ## i64
  while k + 1 < c
    out = out + ffpx_lex_chain_text(ffpsi_pair_base(k, um, vm, wm), ffpsi_pair_base(k + 1, um, vm, wm), pair_width, next_aux)
    next_aux += ffpx_lex_aux_count(pair_width)
    k += 1
  q = 0 ## i64
  while q + 1 < f
    out = out + ffpx_lex_chain_text(ffpsi_fixed_base(c, q, um, vm, wm), ffpsi_fixed_base(c, q + 1, um, vm, wm), fixed_width, next_aux)
    next_aux += ffpx_lex_aux_count(fixed_width)
    q += 1
  out

# Induced psi action on coefficient cells.  A cell indexes
#   u(i,j) * v(j2,k) * w(i2,k2).
# Applying psi to a term changes that monomial to
#   u(k,j2) * v(j,i) * w(k2,i2).
# The map is an involution, so `cell <= mate` selects one complete orbit
# representative without allocating an orbit table.
-> ffpx_cell_mate(cell, n, m) (i64 i64 i64) i64
  p = n ## i64
  um = n * m ## i64
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

-> ffpx_cell_orbit_count(n, m) (i64 i64) i64
  p = n ## i64
  cells = (n * m) * (m * p) * (n * p) ## i64
  count = 0 ## i64
  cell = 0 ## i64
  while cell < cells
    if cell <= ffpx_cell_mate(cell, n, m)
      count += 1
    cell += 1
  count

# Emit a complete native-XOR existence formula for the (c,f) psi-invariant
# cell of <n,m,n>.  Every interchangeable generator class is lex ordered with
# the same sound SBP as ffpsi_encode_sbps.
-> ffpx_cell_text(n, m, c, f) (i64 i64 i64 i64)
  p = n ## i64
  um = n * m ## i64
  vm = m * p ## i64
  wm = n * p ## i64
  cells = um * vm * wm ## i64
  prim = ffpsi_prim(c, f, um, vm, wm) ## i64
  slots = 2 * c + f ## i64
  vars = i64[4]
  body = "" ## String
  chunk = "" ## String
  in_chunk = 0 ## i64
  clauses = 0 ## i64
  # Nonzero guards.
  k = 0 ## i64
  while k < c
    base = ffpsi_pair_base(k, um, vm, wm) ## i64
    axis = 0 ## i64
    while axis < 3
      width = um ## i64
      off = 0 ## i64
      if axis == 1
        width = vm
        off = um
      if axis == 2
        width = wm
        off = um + vm
      line = "" ## String
      pos = 0 ## i64
      while pos < width
        line = line + (base + off + pos).to_s() + " "
        pos += 1
      chunk = chunk + line + "0\n"
      clauses += 1
      axis += 1
    k += 1
  q = 0 ## i64
  while q < f
    base = ffpsi_fixed_base(c, q, um, vm, wm) ## i64
    line = "" ## String
    pos = 0 ## i64
    while pos < um
      line = line + (base + pos).to_s() + " "
      pos += 1
    chunk = chunk + line + "0\n"
    clauses += 1
    line = ""
    pos = 0
    while pos < wm
      line = line + (base + um + pos).to_s() + " "
      pos += 1
    chunk = chunk + line + "0\n"
    clauses += 1
    # w symmetry: w(i,k) == w(k,i).
    i = 0 ## i64
    while i < n
      kk = i + 1 ## i64
      while kk < n
        wa = base + um + i * p + kk ## i64
        wb = base + um + kk * p + i ## i64
        chunk = chunk + "-" + wa.to_s() + " " + wb.to_s() + " 0\n"
        chunk = chunk + wa.to_s() + " -" + wb.to_s() + " 0\n"
        clauses += 2
        kk += 1
      i += 1
    q += 1
  # Coordinate anchor.  Simultaneous outer-index permutations and inner-index
  # permutations commute with psi and act transitively on the U coordinates
  # of every fixed generator.  Since each fixed U is nonzero, some coordinate
  # permutation puts a supported bit at U(0,0).  After the fixed generators
  # are sorted lexicographically, every block whose first bit is one follows
  # every block whose first bit is zero, so the final fixed generator can be
  # required to carry that bit.  This selects a coordinate-orbit representative
  # without excluding any psi-invariant decomposition.
  if f > 0
    anchor = ffpsi_fixed_base(c, f - 1, um, vm, wm) ## i64
    chunk = chunk + anchor.to_s() + " 0\n"
    clauses += 1
  body = body + chunk
  chunk = ""
  # Products + native XOR rows, one coefficient cell per psi orbit.  The
  # encoded term multiset is psi-closed by construction, hence its coefficient
  # function is constant on these orbits.  The target has the same invariance,
  # so omitted partner rows are logical consequences rather than a relaxation.
  orbit = 0 ## i64
  product_cursor = prim + 1 ## i64
  cell = 0 ## i64
  while cell < cells
    mate = ffpx_cell_mate(cell, n, m) ## i64
    if cell <= mate
      cc = cell % wm ## i64
      rest = cell / wm ## i64
      b = rest % vm ## i64
      a = rest / vm ## i64
      xline = "x " ## String
      # At a fixed coefficient cell, products from slots 2k and 2k+1 are
      # equal.  Their XOR contribution is therefore zero; expose that identity
      # directly instead of asking the SAT solver to rediscover it.
      first_slot = 0 ## i64
      if cell == mate
        first_slot = 2 * c
      row_first = product_cursor ## i64
      slot = first_slot ## i64
      while slot < slots
        pv = product_cursor ## i64
        product_cursor += 1
        z = ffpsi_slot_inputs(slot, c, n, m, um, vm, wm, a, b, cc, vars) ## i64
        if slot >= 2 * c && vars[0] == vars[1]
          # Whenever a fixed generator reads the same U variable through U
          # and wired V, its cubic monomial is the quadratic U & W.  This
          # includes every fixed coefficient cell and some nonfixed W cells;
          # the exact two-input Tseitin encoding has only three clauses.
          chunk = chunk + "-" + pv.to_s() + " " + vars[0].to_s() + " 0\n"
          chunk = chunk + "-" + pv.to_s() + " " + vars[2].to_s() + " 0\n"
          chunk = chunk + pv.to_s() + " -" + vars[0].to_s() + " -" + vars[2].to_s() + " 0\n"
          clauses += 3
        else
          chunk = chunk + "-" + pv.to_s() + " " + vars[0].to_s() + " 0\n"
          chunk = chunk + "-" + pv.to_s() + " " + vars[1].to_s() + " 0\n"
          chunk = chunk + "-" + pv.to_s() + " " + vars[2].to_s() + " 0\n"
          chunk = chunk + pv.to_s() + " -" + vars[0].to_s() + " -" + vars[1].to_s() + " -" + vars[2].to_s() + " 0\n"
          clauses += 4
        xline = xline + pv.to_s() + " "
        slot += 1
      i2 = cc / p ## i64
      j = a % m ## i64
      i = a / m ## i64
      j2 = b / p ## i64
      k2 = b % p ## i64
      kk2 = cc % p ## i64
      want = 0 ## i64
      if j == j2 && i == i2 && k2 == kk2
        want = 1
      row_products = slots - first_slot ## i64
      if row_products > 0
        if want == 1
          chunk = chunk + xline + "0\n"
        else
          # CryptoMiniSat XNF rows have odd literal parity.  Negating one
          # literal therefore expresses even variable parity.
          neg = "x -" + row_first.to_s() + " " ## String
          pos = 1 ## i64
          while pos < row_products
            neg = neg + (row_first + pos).to_s() + " "
            pos += 1
          chunk = chunk + neg + "0\n"
        clauses += 1
      if row_products == 0 && want == 1
        # Odd parity of an empty product list is impossible.
        chunk = chunk + "0\n"
        clauses += 1
      in_chunk += 1
      if in_chunk >= 16
        body = body + chunk
        chunk = ""
        in_chunk = 0
      orbit += 1
    cell += 1
  if in_chunk > 0
    body = body + chunk

  product_vars = product_cursor - 1 ## i64
  rank_aux = 0 ## i64
  rank_clauses = 0 ## i64
  # On psi-fixed coefficient cells, conjugate pairs cancel and fixed term q
  # restricts to U_q(i,j) * D_q(i2), where D_q is the diagonal of its
  # symmetric W factor.  For n=2 these rows must span the rank-two target
  # matrix.  Rank(D)=2 is equivalent to: some first diagonal bit, some second
  # diagonal bit, and some row whose two bits differ.  Expose that consequence
  # explicitly; it is implied by the coefficient equations but gives CDCL a
  # compact global view of the fixed-cell subsystem.
  if n == 2 && f > 0
    diag = 0 ## i64
    while diag < 2
      line = "" ## String
      q = 0
      while q < f
        base = ffpsi_fixed_base(c, q, um, vm, wm) ## i64
        line = line + (base + um + diag * n + diag).to_s() + " "
        q += 1
      body = body + line + "0\n"
      rank_clauses += 1
      diag += 1
    diff_line = "" ## String
    q = 0
    while q < f
      base = ffpsi_fixed_base(c, q, um, vm, wm) ## i64
      a = base + um ## i64
      b = base + um + n + 1 ## i64
      d = product_vars + 1 + q ## i64
      # Native XNF rows have odd literal parity: negating `a` expresses
      # a XOR b XOR d = 0, hence d = a XOR b.
      body = body + "x -" + a.to_s() + " " + b.to_s() + " " + d.to_s() + " 0\n"
      diff_line = diff_line + d.to_s() + " "
      rank_clauses += 1
      q += 1
    body = body + diff_line + "0\n"
    rank_clauses += 1
    rank_aux = f
    # The same fixed-cell subsystem also says, for every inner coordinate j,
    #
    #   sum_q U_q(i,j) D_q(i2) = [i == i2].
    #
    # Thus the two f-bit rows (U_q(0,j))_q and (U_q(1,j))_q are both nonzero
    # and unequal: their images through the fixed W diagonals are e_0 and
    # e_1.  Expose that necessary rank-two consequence for every j.  It is
    # redundant with the exact coefficient rows and therefore cannot remove
    # a psi-invariant decomposition, but avoids asking CDCL to rediscover the
    # row separation through f quadratic products per coordinate.
    j = 0 ## i64
    while j < m
      row0 = "" ## String
      row1 = "" ## String
      unequal = "" ## String
      q = 0
      while q < f
        base = ffpsi_fixed_base(c, q, um, vm, wm) ## i64
        u0 = base + j ## i64
        u1 = base + m + j ## i64
        d = product_vars + f + j * f + q + 1 ## i64
        row0 = row0 + u0.to_s() + " "
        row1 = row1 + u1.to_s() + " "
        # d = u0 XOR u1.  Native XNF rows have odd literal parity, so
        # negating u0 expresses u0 XOR u1 XOR d = 0.
        body = body + "x -" + u0.to_s() + " " + u1.to_s() + " " + d.to_s() + " 0\n"
        unequal = unequal + d.to_s() + " "
        rank_clauses += 1
        q += 1
      body = body + row0 + "0\n"
      body = body + row1 + "0\n"
      body = body + unequal + "0\n"
      rank_clauses += 3
      j += 1
    rank_aux += m * f
  # Sort a generator-invariant parity signature of the interchangeable inner
  # coordinates before allocating the ordinary lex-prefix auxiliaries.
  inner_aux = ffpx_inner_weight_sbp_aux_count(n, m) ## i64
  inner_clauses = ffpx_inner_weight_sbp_clause_count(n, m) ## i64
  body = body + ffpx_inner_weight_sbp_text(n, m, c, f, product_vars + rank_aux + 1)
  sbp_aux = ffpx_sbp_aux_count(n, m, c, f) ## i64
  sbp_clauses = ffpx_sbp_clause_count(n, m, c, f) ## i64
  body = body + ffpx_sbp_text(n, m, c, f, product_vars + rank_aux + inner_aux + 1)
  clauses += rank_clauses + inner_clauses + sbp_clauses
  "p cnf " + (product_vars + rank_aux + inner_aux + sbp_aux).to_s() + " " + clauses.to_s() + "\n" + body
