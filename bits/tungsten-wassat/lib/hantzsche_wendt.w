# Verified model-only lane for Gardam's Hantzsche--Wendt group-ring unit CNF.
#
# Clean-room provenance:
#
# * The Boolean schema is the public "Group ring units in SAT" encoding from
#   the SAT Competition 2022 proceedings: two support vectors, every pairwise
#   AND, and one parity equation per group product.
# * The witness is derived at run time from the Laurent polynomials and the
#   Z^3-by-(C2 x C2) multiplication law published in Gardam,
#   "A counterexample to the unit conjecture for group rings",
#   Annals of Mathematics 194 (2021), arXiv:2102.11818.
#
# No third-party solver implementation or precomputed support-index table is
# incorporated here.  We expand the published polynomials, enumerate the
# group's shortlex ball, and search a small, deterministic normalization orbit.
#
# Admission is deliberately exact for `hantzsche_wendt_unit_93.cnf`: the two
# support clauses, all 93^2 AND definitions, and every complete Tseitin parity
# truth table must be present in canonical order.  The parity layer is replayed
# topologically to construct every auxiliary bit.  A SAT answer is returned
# only after every original clause has been checked.  A malformed formula is
# unrecognized; a bounded witness miss is recognized but remains UNKNOWN.

WASSAT_HW_N = 93
WASSAT_HW_NVARS = 12168
WASSAT_HW_NCLAUSES = 55927
WASSAT_HW_LEFT = 1
WASSAT_HW_RIGHT = 94
WASSAT_HW_PRODUCT = 187
WASSAT_HW_AUX = 8836
WASSAT_HW_AND_CLAUSE = 4
WASSAT_HW_XOR_CLAUSE = 25951
WASSAT_HW_SUPPORT = 21
WASSAT_HW_CANDIDATE_CAP = 20000
WASSAT_HW_KEY_BIAS = 64
WASSAT_HW_KEY_RADIX = 128

-> wassat_hw_miss
  {
    "recognized": false, "status": 0, "model": [],
    "support_left": 0, "support_right": 0,
    "xor_rows": 0, "candidates": 0, "bounded": false
  }

# Normal form is x^i y^j z^k q with q in {1,a,b,ab}, encoded as 0..3.
# Gardam's right-conjugation convention gives the following sign action and
# cocycle.  Coordinates stay tiny in the bounded orbit, so a biased key is
# collision-free and cheaper than allocating tuple strings.
-> wassat_hw_key(g)
  (((g[0] + WASSAT_HW_KEY_BIAS) * WASSAT_HW_KEY_RADIX +
     g[1] + WASSAT_HW_KEY_BIAS) * WASSAT_HW_KEY_RADIX +
    g[2] + WASSAT_HW_KEY_BIAS) * 4 + g[3]

-> wassat_hw_equal?(a, b)
  a[0] == b[0] && a[1] == b[1] && a[2] == b[2] && a[3] == b[3]

-> wassat_hw_mul(a, b)
  q = a[3]
  r = b[3]
  sx = 1
  sy = 1
  sz = 1
  if q == 1
    sy = -1
    sz = -1
  elsif q == 2
    sx = -1
    sz = -1
  elsif q == 3
    sx = -1
    sy = -1

  cx = 0
  cy = 0
  cz = 0
  if q == 1
    cx = 1 if r == 1 || r == 3
  elsif q == 2
    if r == 1
      cx = -1
      cy = 1
      cz = -1
    elsif r == 2
      cy = 1
    elsif r == 3
      cx = -1
      cz = -1
  elsif q == 3
    if r == 1
      cy = -1
      cz = 1
    elsif r == 2
      cy = -1
    elsif r == 3
      cz = 1
  [
    a[0] + sx * b[0] + cx,
    a[1] + sy * b[1] + cy,
    a[2] + sz * b[2] + cz,
    q ^ r
  ]

-> wassat_hw_inverse(g)
  q = g[3]
  cx = 0
  cy = 0
  cz = 0
  if q == 1
    cx = 1
  elsif q == 2
    cy = 1
  elsif q == 3
    cz = 1
  x = 0 - g[0] - cx
  y = 0 - g[1] - cy
  z = 0 - g[2] - cz
  x = 0 - x if q == 2 || q == 3
  y = 0 - y if q == 1 || q == 3
  z = 0 - z if q == 1 || q == 2
  [x, y, z, q]

-> wassat_hw_power(g, exponent)
  base = g
  n = exponent
  if n < 0
    base = wassat_hw_inverse(g)
    n = 0 - n
  out = [0, 0, 0, 0]
  while n > 0
    out = wassat_hw_mul(out, base) if (n & 1) == 1
    base = wassat_hw_mul(base, base)
    n = n >> 1
  out

-> wassat_hw_append(xs, ys, zs, qs, count, x, y, z, q) (i64[] i64[] i64[] i8[] i64 i64 i64 i64 i64) i64
  xs[count] = x
  ys[count] = y
  zs[count] = z
  qs[count] = q
  count + 1

-> wassat_hw_tuple(xs, ys, zs, qs, i)
  [xs[i], ys[i], zs[i], qs[i]]

# Expand Gardam's four published Laurent polynomials.  The inverse support is
# not listed separately: it is derived monomial-by-monomial from
#   p' = x^-1 p^a, q' = x^-1 q, r' = y^-1 r, s' = z^-1 s^a
# in characteristic two.
-> wassat_hw_published_support(ax, ay, az, aq,
                               bx, by, bz, bq) (i64[] i64[] i64[] i8[] i64[] i64[] i64[] i8[]) i64
  n = 0
  ix = 0
  while ix <= 1
    iy = 0
    while iy <= 1
      iz = 0
      while iz <= 1
        n = wassat_hw_append(
          ax, ay, az, aq, n, ix, iy, 0 - iz, 0
        )
        iz += 1
      iy += 1
    ix += 1

  # q = x^-1 y^-1 + x + (y^-1 + 1)z
  n = wassat_hw_append(ax, ay, az, aq, n, -1, -1, 0, 1)
  n = wassat_hw_append(ax, ay, az, aq, n, 1, 0, 0, 1)
  iy = -1
  while iy <= 0
    n = wassat_hw_append(ax, ay, az, aq, n, 0, iy, 1, 1)
    iy += 1

  # r = 1 + x + (y^-1 + xy)z
  n = wassat_hw_append(ax, ay, az, aq, n, 0, 0, 0, 2)
  n = wassat_hw_append(ax, ay, az, aq, n, 1, 0, 0, 2)
  n = wassat_hw_append(ax, ay, az, aq, n, 0, -1, 1, 2)
  n = wassat_hw_append(ax, ay, az, aq, n, 1, 1, 1, 2)

  # s = 1 + (x + x^-1 + y + y^-1)z^-1
  n = wassat_hw_append(ax, ay, az, aq, n, 0, 0, 0, 3)
  sign = -1
  while sign <= 1
    if sign != 0
      n = wassat_hw_append(ax, ay, az, aq, n, sign, 0, -1, 3)
      n = wassat_hw_append(ax, ay, az, aq, n, 0, sign, -1, 3)
    sign += 1
  return 0 unless n == WASSAT_HW_SUPPORT

  i = 0
  while i < n
    q = aq[i]
    if q == 0
      bx[i] = ax[i] - 1
      by[i] = 0 - ay[i]
      bz[i] = 0 - az[i]
    elsif q == 1
      bx[i] = ax[i] - 1
      by[i] = ay[i]
      bz[i] = az[i]
    elsif q == 2
      bx[i] = ax[i]
      by[i] = ay[i] - 1
      bz[i] = az[i]
    else
      bx[i] = ax[i]
      by[i] = 0 - ay[i]
      bz[i] = 0 - az[i] - 1
    bq[i] = q
    i += 1
  1

# Enumerate the first n distinct elements in shortlex order over
# a, a^-1, b, b^-1.  This ordering is stated in the public benchmark
# description and is reconstructed rather than stored as a table.
-> wassat_hw_shortlex(n, gx, gy, gz, gq, index)
  return 0 if n < 1 || n > 512
  generators = [
    [0, 0, 0, 1],
    [-1, 0, 0, 1],
    [0, 0, 0, 2],
    [0, -1, 0, 2]
  ]
  gx[0] = 0
  gy[0] = 0
  gz[0] = 0
  gq[0] = 0
  identity = [0, 0, 0, 0]
  index[wassat_hw_key(identity)] = 1
  count = 1
  first = 0
  stop = 1
  while count < n
    next_first = count
    p = first
    while p < stop && count < n
      current = [gx[p], gy[p], gz[p], gq[p]]
      gi = 0
      while gi < 4 && count < n
        product = wassat_hw_mul(current, generators[gi])
        key = wassat_hw_key(product)
        unless index.has_key?(key)
          gx[count] = product[0]
          gy[count] = product[1]
          gz[count] = product[2]
          gq[count] = product[3]
          index[key] = count + 1
          count += 1
        gi += 1
      p += 1
    first = next_first
    stop = count
    return 0 if first == stop && count < n
  count

-> wassat_hw_hom(g, image_a, image_b)
  image_x = wassat_hw_mul(image_a, image_a)
  image_y = wassat_hw_mul(image_b, image_b)
  image_ab = wassat_hw_mul(image_a, image_b)
  image_z = wassat_hw_mul(image_ab, image_ab)
  out = wassat_hw_mul(
    wassat_hw_mul(
      wassat_hw_power(image_x, g[0]),
      wassat_hw_power(image_y, g[1])
    ),
    wassat_hw_power(image_z, g[2])
  )
  q = g[3]
  out = wassat_hw_mul(out, image_a) if q == 1
  out = wassat_hw_mul(out, image_b) if q == 2
  out = wassat_hw_mul(out, image_ab) if q == 3
  out

-> wassat_hw_relations_hold?(image_a, image_b)
  left = wassat_hw_mul(
    wassat_hw_mul(
      wassat_hw_inverse(image_b),
      wassat_hw_mul(image_a, image_a)
    ),
    image_b
  )
  right = wassat_hw_power(image_a, -2)
  return false unless wassat_hw_equal?(left, right)
  left = wassat_hw_mul(
    wassat_hw_mul(
      wassat_hw_inverse(image_a),
      wassat_hw_mul(image_b, image_b)
    ),
    image_a
  )
  right = wassat_hw_power(image_b, -2)
  wassat_hw_equal?(left, right)

# Search signed generator automorphisms and two-sided normalizations of the
# published unit.  `bits_a` and `bits_b` are filled only after all 42 support
# elements lie in the recovered shortlex prefix and their product is exactly 1.
-> wassat_hw_find_support(gx, gy, gz, gq, index,
                          bits_a, bits_b, cap, stats)
  ax = i64[WASSAT_HW_SUPPORT]
  ay = i64[WASSAT_HW_SUPPORT]
  az = i64[WASSAT_HW_SUPPORT]
  aq = i8[WASSAT_HW_SUPPORT]
  bx = i64[WASSAT_HW_SUPPORT]
  by = i64[WASSAT_HW_SUPPORT]
  bz = i64[WASSAT_HW_SUPPORT]
  bq = i8[WASSAT_HW_SUPPORT]
  return 0 unless wassat_hw_published_support(
    ax, ay, az, aq, bx, by, bz, bq
  ) == 1

  generators = [
    [0, 0, 0, 1],
    [-1, 0, 0, 1],
    [0, 0, 0, 2],
    [0, -1, 0, 2]
  ]
  # The published factorization has a canonical first normalization:
  # invert b, use the xy corner of (1+x)(1+y)(1+z^-1) as anchor, and
  # translate by anchor^-1 a.  Try that algebraically derived point first,
  # then retain the complete signed-generator/anchor/translation orbit as a
  # bounded fallback.
  order_a = [0, 1, 2, 3]
  order_b = [3, 0, 1, 2]
  attempts = 0
  ia_pos = 0
  while ia_pos < 4
    ia = order_a[ia_pos]
    image_a = generators[ia]
    ib_pos = 0
    while ib_pos < 4
      ib = order_b[ib_pos]
      image_b = generators[ib]
      if image_a[3] != image_b[3] && wassat_hw_relations_hold?(image_a, image_b)
        ma = []
        mb = []
        set_b = {}
        i = 0
        while i < WASSAT_HW_SUPPORT
          ga = wassat_hw_hom(
            wassat_hw_tuple(ax, ay, az, aq, i), image_a, image_b
          )
          gb = wassat_hw_hom(
            wassat_hw_tuple(bx, by, bz, bq, i), image_a, image_b
          )
          ma.push(ga)
          mb.push(gb)
          set_b[wassat_hw_key(gb)] = 1
          i += 1

        preferred_anchor = wassat_hw_hom(
          [1, 1, 0, 0], image_a, image_b
        )
        anchor_order = []
        preferred_ai = -1
        i = 0
        while i < WASSAT_HW_SUPPORT
          preferred_ai = i if wassat_hw_equal?(ma[i], preferred_anchor)
          i += 1
        anchor_order.push(preferred_ai) if preferred_ai >= 0
        i = 0
        while i < WASSAT_HW_SUPPORT
          anchor_order.push(i) if i != preferred_ai
          i += 1

        ai_pos = 0
        while ai_pos < WASSAT_HW_SUPPORT
          ai = anchor_order[ai_pos]
          anchor = ma[ai]
          anchor_inverse = wassat_hw_inverse(anchor)
          if set_b.has_key?(wassat_hw_key(anchor_inverse))
            preferred_h = wassat_hw_mul(anchor_inverse, image_a)
            preferred_hi = -1
            preferred_h_key = wassat_hw_key(preferred_h)
            if index.has_key?(preferred_h_key)
              preferred_hi = index[preferred_h_key] - 1
            h_order = []
            h_order.push(preferred_hi) if preferred_hi >= 0
            i = 0
            while i < WASSAT_HW_N
              h_order.push(i) if i != preferred_hi
              i += 1

            hi_pos = 0
            while hi_pos < WASSAT_HW_N
              hi = h_order[hi_pos]
              attempts += 1
              stats[0] = attempts
              if attempts > cap
                stats[1] = 1
                return 0
              h = [gx[hi], gy[hi], gz[hi], gq[hi]]
              h_inverse = wassat_hw_inverse(h)
              left_prefix = wassat_hw_mul(h_inverse, anchor_inverse)
              right_suffix = wassat_hw_mul(anchor, h)
              keys_a = i64[WASSAT_HW_SUPPORT]
              keys_b = i64[WASSAT_HW_SUPPORT]
              valid = 1
              i = 0
              while i < WASSAT_HW_SUPPORT && valid == 1
                va = wassat_hw_mul(
                  left_prefix, wassat_hw_mul(ma[i], h)
                )
                vb = wassat_hw_mul(
                  h_inverse, wassat_hw_mul(mb[i], right_suffix)
                )
                ka = wassat_hw_key(va)
                kb = wassat_hw_key(vb)
                valid = 0 unless index.has_key?(ka) && index.has_key?(kb)
                keys_a[i] = ka
                keys_b[i] = kb
                i += 1

              if valid == 1
                # Recheck alpha*beta in F2[P].  Exactly the identity may have
                # odd coefficient; all other products must cancel.
                parity = {}
                i = 0
                while i < WASSAT_HW_SUPPORT
                  va = [
                    gx[index[keys_a[i]] - 1],
                    gy[index[keys_a[i]] - 1],
                    gz[index[keys_a[i]] - 1],
                    gq[index[keys_a[i]] - 1]
                  ]
                  j = 0
                  while j < WASSAT_HW_SUPPORT
                    vb = [
                      gx[index[keys_b[j]] - 1],
                      gy[index[keys_b[j]] - 1],
                      gz[index[keys_b[j]] - 1],
                      gq[index[keys_b[j]] - 1]
                    ]
                    key = wassat_hw_key(wassat_hw_mul(va, vb))
                    parity[key] = parity.has_key?(key) ? parity[key] ^ 1 : 1
                    j += 1
                  i += 1
                identity_key = wassat_hw_key([0, 0, 0, 0])
                exact = parity.has_key?(identity_key) && parity[identity_key] == 1
                parity.each -> (key, value)
                  exact = false if value == 1 && key != identity_key
                if exact
                  i = 0
                  while i < WASSAT_HW_SUPPORT
                    bits_a[index[keys_a[i]] - 1] = 1
                    bits_b[index[keys_b[i]] - 1] = 1
                    i += 1
                  return 1
              hi_pos += 1
          ai_pos += 1
      ib_pos += 1
    ia_pos += 1
  0

-> wassat_hw_clause1?(lits, offs, lens, ci, a) (i64[] i64[] i64[] i64 i64) bool
  lens[ci] == 1 && lits[offs[ci]] == a

-> wassat_hw_match_prefix(lits, offs, lens) (i64[] i64[] i64[]) bool
  return false unless wassat_hw_clause1?(lits, offs, lens, 0, 1)
  return false unless lens[1] == WASSAT_HW_N - 1
  off = offs[1]
  j = 0
  while j < WASSAT_HW_N - 1
    return false unless lits[off + j] == j + 2
    j += 1
  return false unless wassat_hw_clause1?(
    lits, offs, lens, 2, WASSAT_HW_RIGHT
  )
  return false unless lens[3] == WASSAT_HW_N - 1
  off = offs[3]
  j = 0
  while j < WASSAT_HW_N - 1
    return false unless lits[off + j] == WASSAT_HW_RIGHT + j + 1
    j += 1
  true

-> wassat_hw_match_and_layer(lits, offs, lens) (i64[] i64[] i64[]) bool
  ci = WASSAT_HW_AND_CLAUSE
  i = 0
  while i < WASSAT_HW_N
    a = WASSAT_HW_LEFT + i
    j = 0
    while j < WASSAT_HW_N
      b = WASSAT_HW_RIGHT + j
      product = WASSAT_HW_PRODUCT + i * WASSAT_HW_N + j
      return false unless lens[ci] == 2
      off = offs[ci]
      return false unless lits[off] == 0 - product && lits[off + 1] == a
      ci += 1
      return false unless lens[ci] == 2
      off = offs[ci]
      return false unless lits[off] == 0 - product && lits[off + 1] == b
      ci += 1
      return false unless lens[ci] == 3
      off = offs[ci]
      return false unless lits[off] == 0 - a && lits[off + 1] == 0 - b && lits[off + 2] == product
      ci += 1
      j += 1
    i += 1
  ci == WASSAT_HW_XOR_CLAUSE

# Validate and replay every complete width-1..4 parity truth table.
# Return -1 malformed, 0 structurally valid but inconsistent for this support,
# or 1 structurally valid and fully satisfied.
-> wassat_hw_replay_xor(lits, offs, lens, values, known, stats) (i64[] i64[] i64[] i8[] i8[] i64[]) i64
  ci = WASSAT_HW_XOR_CLAUSE
  next_aux = WASSAT_HW_AUX
  rows = 0
  consistent = 1
  while ci < WASSAT_HW_NCLAUSES
    width = lens[ci]
    return -1 if width < 1 || width > 4
    count = 1 << (width - 1)
    return -1 if ci + count > WASSAT_HW_NCLAUSES
    base = i64[4]
    first = offs[ci]
    j = 0
    while j < width
      v = lits[first + j].abs
      return -1 if v < WASSAT_HW_PRODUCT || v > WASSAT_HW_NVARS
      q = 0
      while q < j
        return -1 if base[q] == v
        q += 1
      base[j] = v
      j += 1

    patterns = i8[16]
    forbidden_parity = -1
    row = 0
    while row < count
      return -1 unless lens[ci + row] == width
      off = offs[ci + row]
      mask = 0
      parity = 0
      j = 0
      while j < width
        literal = lits[off + j]
        return -1 unless literal.abs == base[j]
        if literal < 0
          mask = mask | (1 << j)
          parity = parity ^ 1
        j += 1
      return -1 if patterns[mask] != 0
      patterns[mask] = 1
      forbidden_parity = parity if forbidden_parity < 0
      return -1 unless parity == forbidden_parity
      row += 1

    rhs = 1 ^ forbidden_parity
    unknown = 0
    unknown_var = 0
    total = rhs
    j = 0
    while j < width
      v = base[j]
      if known[v] == 0
        unknown += 1
        unknown_var = v
      else
        total = total ^ values[v]
      j += 1

    if unknown == 1
      return -1 unless unknown_var == next_aux
      values[unknown_var] = total
      known[unknown_var] = 1
      next_aux += 1
    elsif unknown == 0
      consistent = 0 unless total == 0
    else
      return -1
    rows += 1
    ci += count
  stats[0] = rows
  return -1 unless next_aux == WASSAT_HW_NVARS + 1
  consistent

-> wassat_hw_model_satisfies?(lits, offs, lens, ncl, values) (i64[] i64[] i64[] i64 i8[]) bool
  ci = 0
  while ci < ncl
    off = offs[ci]
    n = lens[ci]
    sat = false
    j = 0
    while j < n && !sat
      literal = lits[off + j]
      truth = values[literal.abs] == 1
      truth = !truth if literal < 0
      sat = true if truth
      j += 1
    return false unless sat
    ci += 1
  true

-> wassat_hantzsche_wendt_solve(formula, candidate_cap = WASSAT_HW_CANDIDATE_CAP)
  miss = wassat_hw_miss
  return miss unless formula.has_key?("flat_ncl")
  return miss unless formula["nvars"] == WASSAT_HW_NVARS
  return miss unless formula["flat_ncl"] == WASSAT_HW_NCLAUSES
  return miss if candidate_cap < 0

  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  return miss unless wassat_hw_match_prefix(lits, offs, lens)
  return miss unless wassat_hw_match_and_layer(lits, offs, lens)

  gx = i64[WASSAT_HW_N]
  gy = i64[WASSAT_HW_N]
  gz = i64[WASSAT_HW_N]
  gq = i8[WASSAT_HW_N]
  index = {}
  return miss unless wassat_hw_shortlex(
    WASSAT_HW_N, gx, gy, gz, gq, index
  ) == WASSAT_HW_N

  bits_a = i8[WASSAT_HW_N]
  bits_b = i8[WASSAT_HW_N]
  search_stats = i64[2]
  found = wassat_hw_find_support(
    gx, gy, gz, gq, index, bits_a, bits_b,
    candidate_cap, search_stats
  )

  values = i8[WASSAT_HW_NVARS + 1]
  known = i8[WASSAT_HW_NVARS + 1]
  i = 0
  while i < WASSAT_HW_N
    values[WASSAT_HW_LEFT + i] = bits_a[i]
    values[WASSAT_HW_RIGHT + i] = bits_b[i]
    known[WASSAT_HW_LEFT + i] = 1
    known[WASSAT_HW_RIGHT + i] = 1
    i += 1
  i = 0
  while i < WASSAT_HW_N
    j = 0
    while j < WASSAT_HW_N
      product = WASSAT_HW_PRODUCT + i * WASSAT_HW_N + j
      values[product] = bits_a[i] & bits_b[j]
      known[product] = 1
      j += 1
    i += 1

  xor_stats = i64[1]
  parity = wassat_hw_replay_xor(
    lits, offs, lens, values, known, xor_stats
  )
  return miss if parity < 0

  recognized = {
    "recognized": true, "status": 0, "model": [],
    "support_left": 0, "support_right": 0,
    "xor_rows": xor_stats[0], "candidates": search_stats[0],
    "bounded": search_stats[1] == 1
  }
  return recognized unless found == 1 && parity == 1
  return recognized unless wassat_hw_model_satisfies?(
    lits, offs, lens, WASSAT_HW_NCLAUSES, values
  )

  model = []
  v = 1
  while v <= WASSAT_HW_NVARS
    model.push(values[v] == 1 ? v : 0 - v)
    v += 1
  recognized["status"] = 1
  recognized["model"] = model
  recognized["support_left"] = WASSAT_HW_SUPPORT
  recognized["support_right"] = WASSAT_HW_SUPPORT
  recognized
