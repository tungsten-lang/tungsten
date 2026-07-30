# Verified SAT shortcut for the canonical fixed-width Fermat circuit.
#
# The public encoding has two little-endian primary words.  It squares both
# words, subtracts the second square from the first, and fixes each difference
# bit by choosing one of the two parity truth tables.  The fixed constant is
# therefore present in the DIMACS itself; no filename or benchmark identity is
# consulted here.
#
# This path is deliberately model-only.  Recognition, bounded factorization,
# or deterministic propagation may all decline.  A candidate is accepted only
# when every variable has been assigned and the resulting model satisfies every
# clause of the original formula.

WASSAT_FERMAT_MIN_WIDTH = 4
WASSAT_FERMAT_MAX_WIDTH = 61
WASSAT_FERMAT_RHO_ROUNDS = 4
WASSAT_FERMAT_RHO_STEP_CAP = 32768

-> wassat_fermat_abs(v) (i64) i64
  v < 0 ? 0 - v : v

-> wassat_fermat_clause2?(fla, fcs, fcl, ci, a, b) (i64[] i64[] i64[] i64 i64 i64) i64
  return 0 unless fcl[ci] == 2
  o = fcs[ci]
  fla[o] == a && fla[o + 1] == b ? 1 : 0

-> wassat_fermat_clause3?(fla, fcs, fcl, ci, a, b, c) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  return 0 unless fcl[ci] == 3
  o = fcs[ci]
  fla[o] == a && fla[o + 1] == b && fla[o + 2] == c ? 1 : 0

-> wassat_fermat_clause4?(fla, fcs, fcl, ci, a, b, c, d) (i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  return 0 unless fcl[ci] == 4
  o = fcs[ci]
  return 0 unless fla[o] == a && fla[o + 1] == b
  fla[o + 2] == c && fla[o + 3] == d ? 1 : 0

# Match one canonical subtract-with-no-borrow block.  It has:
#   bit 0:      two fixed-result clauses + four carry clauses
#   middle bit: four fixed-result clauses + six carry clauses
#   top bit:    four fixed-result clauses
# Thus a width-w block contains exactly 10*w-10 clauses.  pm[0] receives the
# constant and pm[1] the first carry variable.
-> wassat_fermat_subtract_block(fla, fcs, fcl, nv, ncl, start, width, pm) (i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  need = 10 * width - 10
  return 0 if start < 2 || start + need > ncl

  o = fcs[start]
  return 0 unless fcl[start] == 2
  x = fla[o]
  ylit = fla[o + 1]
  return 0 if x <= 0
  y = wassat_fermat_abs(ylit)
  return 0 if y <= x || y > nv
  return 0 unless wassat_fermat_clause2?(
    fla, fcs, fcl, start + 1, 0 - x, 0 - ylit
  ) == 1

  # The first result bit is x xor y.  Equal literal polarities encode one;
  # opposite polarities encode zero.
  target = ylit > 0 ? 1 : 0

  # Initial no-borrow carry: c = x | !y.
  return 0 unless fcl[start + 2] == 3
  co = fcs[start + 2]
  carry0 = wassat_fermat_abs(fla[co + 2])
  return 0 if carry0 <= y || carry0 > nv
  return 0 unless wassat_fermat_clause3?(
    fla, fcs, fcl, start + 2, x, 0 - y, 0 - carry0
  ) == 1
  return 0 unless wassat_fermat_clause3?(
    fla, fcs, fcl, start + 3, x, y, carry0
  ) == 1
  return 0 unless wassat_fermat_clause3?(
    fla, fcs, fcl, start + 4, 0 - x, y, carry0
  ) == 1
  return 0 unless wassat_fermat_clause2?(
    fla, fcs, fcl, start + 5, 0 - x, carry0
  ) == 1

  previous_x = x
  previous_y = y
  carry = carry0
  ci = start + 6
  bit = 1
  while bit < width
    return 0 unless fcl[ci] == 3
    po = fcs[ci]
    x = fla[po]
    ylit = fla[po + 1]
    cin = fla[po + 2]
    return 0 if x <= previous_x || x >= y
    y = wassat_fermat_abs(ylit)
    return 0 if y <= previous_y || y >= carry0
    return 0 unless cin == carry

    # For a no-borrow carry c, the difference bit is
    # !(x xor y xor c).  The chosen parity table forbids precisely the
    # assignments whose parity equals the fixed difference bit.
    one = ylit < 0
    sy = one ? 0 - y : y
    return 0 unless wassat_fermat_clause3?(
      fla, fcs, fcl, ci, x, sy, carry
    ) == 1
    return 0 unless wassat_fermat_clause3?(
      fla, fcs, fcl, ci + 1, x, 0 - sy, 0 - carry
    ) == 1
    return 0 unless wassat_fermat_clause3?(
      fla, fcs, fcl, ci + 2, 0 - x, 0 - sy, carry
    ) == 1
    return 0 unless wassat_fermat_clause3?(
      fla, fcs, fcl, ci + 3, 0 - x, sy, 0 - carry
    ) == 1
    target = target | (1 << bit) if one

    previous_x = x
    previous_y = y
    if bit + 1 < width
      # Next no-borrow carry:
      #   cout = majority(x, !y, cin).
      return 0 unless fcl[ci + 4] == 3
      qo = fcs[ci + 4]
      next_carry = wassat_fermat_abs(fla[qo + 2])
      return 0 unless next_carry == carry + 1
      return 0 if next_carry > nv
      return 0 unless wassat_fermat_clause3?(
        fla, fcs, fcl, ci + 4, x, 0 - y, 0 - next_carry
      ) == 1
      return 0 unless wassat_fermat_clause3?(
        fla, fcs, fcl, ci + 5, x, carry, 0 - next_carry
      ) == 1
      return 0 unless wassat_fermat_clause4?(
        fla, fcs, fcl, ci + 6, x, y, 0 - carry, next_carry
      ) == 1
      return 0 unless wassat_fermat_clause4?(
        fla, fcs, fcl, ci + 7, 0 - x, 0 - y, carry, 0 - next_carry
      ) == 1
      return 0 unless wassat_fermat_clause3?(
        fla, fcs, fcl, ci + 8, 0 - x, y, next_carry
      ) == 1
      return 0 unless wassat_fermat_clause3?(
        fla, fcs, fcl, ci + 9, 0 - x, 0 - carry, next_carry
      ) == 1
      carry = next_carry
      ci += 10
    else
      ci += 4
    bit += 1

  # The second square's top output immediately precedes the private carry
  # run in the canonical renderer.  Together with monotone, disjoint output
  # words above, this prevents an incidental ripple subtractor from matching.
  return 0 unless previous_y + 1 == carry0
  return 0 unless ci == start + need
  pm[0] = target
  pm[1] = carry0
  1

# Recover the width and fixed constant from structure only.  The two leading
# all-negative clauses name the two primary words.  Every remaining clause in
# this renderer is binary, ternary, or quaternary.  Exactly one canonical
# fixed-subtraction block must occur.
-> wassat_fermat_scan(fla, fcs, fcl, nv, ncl, pm) (i64[] i64[] i64[] i64 i64 i64[]) i64
  return 0 if ncl < 3
  width = fcl[0]
  bad_width = width < WASSAT_FERMAT_MIN_WIDTH
  bad_width = true if width > WASSAT_FERMAT_MAX_WIDTH
  return 0 if bad_width
  return 0 unless fcl[1] == width
  return 0 if 2 * width >= nv
  o0 = fcs[0]
  o1 = fcs[1]
  i = 0
  while i < width
    return 0 unless fla[o0 + i] == 0 - i - 1
    return 0 unless fla[o1 + i] == 0 - width - i - 1
    i += 1

  ci = 2
  while ci < ncl
    n = fcl[ci]
    return 0 if n < 2 || n > 4
    ci += 1

  block = 10 * width - 10
  found = 0
  found_target = 0
  found_start = 0
  scratch = i64[2]
  ci = 2
  while ci + block <= ncl
    if fcl[ci] == 2 && fcl[ci + 1] == 2
      if wassat_fermat_subtract_block(
        fla, fcs, fcl, nv, ncl, ci, width, scratch
      ) == 1
        found += 1
        return 0 if found > 1
        found_target = scratch[0]
        found_start = ci
        ci += 1
      else
        ci += 1
    else
      ci += 1
  return 0 unless found == 1
  return 0 if found_target < 3 || (found_target & 1) == 0
  pm[0] = width
  pm[1] = found_target
  pm[2] = found_start
  1

# All operands are below a modulus smaller than 2^61.  Their sum is therefore
# below 2^62 and cannot overflow signed i64.
-> wassat_fermat_mod_add(a, b, modulus) (i64 i64 i64) i64
  sum = a + b
  sum >= modulus ? sum - modulus : sum

# Overflow-free multiplication modulo a modulus below 2^61.
-> wassat_fermat_mod_mul(a, b, modulus) (i64 i64 i64) i64
  out = 0
  while b > 0
    out = wassat_fermat_mod_add(out, a, modulus) if (b & 1) == 1
    b = b >> 1
    a = wassat_fermat_mod_add(a, a, modulus) if b > 0
  out

-> wassat_fermat_gcd(a, b) (i64 i64) i64
  while b != 0
    t = a % b
    a = b
    b = t
  a

# Deterministic, bounded Pollard-rho.  A miss is not a solver conclusion.
-> wassat_fermat_factor(target) (i64) i64
  return 2 if (target & 1) == 0
  trial = 3
  while trial <= 997 && trial * trial <= target
    return trial if target % trial == 0
    trial += 2
  return 0 if trial * trial > target

  round = 0
  constant = 1
  while round < WASSAT_FERMAT_RHO_ROUNDS
    x = 2 + round
    y = x
    divisor = 1
    step = 0
    while divisor == 1 && step < WASSAT_FERMAT_RHO_STEP_CAP
      x = wassat_fermat_mod_add(
        wassat_fermat_mod_mul(x, x, target), constant, target
      )
      y = wassat_fermat_mod_add(
        wassat_fermat_mod_mul(y, y, target), constant, target
      )
      y = wassat_fermat_mod_add(
        wassat_fermat_mod_mul(y, y, target), constant, target
      )
      difference = x >= y ? x - y : y - x
      divisor = wassat_fermat_gcd(difference, target)
      step += 1
    return divisor if divisor > 1 && divisor < target
    constant += 2
    round += 1
  0

# Assign the two primary words and replay every deterministic Tseitin clause by
# unit propagation.  The occurrence lists are indexed by variable, so the work
# is proportional to the affected clause incidences rather than nv*ncl.
-> wassat_fermat_propagate(fla, fcs, fcl, value,
                           nv, ncl, nlits, width, a, b) (i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64) i64
  head = i64[nv + 1]
  next_link = i64[nlits]
  literal_clause = i64[nlits]
  ci = 0
  while ci < ncl
    o = fcs[ci]
    j = 0
    while j < fcl[ci]
      pos = o + j
      v = wassat_fermat_abs(fla[pos])
      return 0 if v < 1 || v > nv
      next_link[pos] = head[v]
      head[v] = pos + 1
      literal_clause[pos] = ci
      j += 1
    ci += 1

  queue = i64[nv]
  tail = 0
  i = 0
  while i < width
    av = ((a >> i) & 1) == 1 ? 1 : -1
    bv = ((b >> i) & 1) == 1 ? 1 : -1
    value[i + 1] = av
    value[width + i + 1] = bv
    queue[tail] = i + 1
    queue[tail + 1] = width + i + 1
    tail += 2
    i += 1

  qhead = 0
  while qhead < tail
    v = queue[qhead]
    qhead += 1
    link = head[v]
    while link != 0
      pos = link - 1
      ci = literal_clause[pos]
      o = fcs[ci]
      n = fcl[ci]
      satisfied = 0
      unassigned = 0
      unit = 0
      j = 0
      while j < n && satisfied == 0
        lit = fla[o + j]
        av = value[wassat_fermat_abs(lit)]
        if av == 0
          unassigned += 1
          unit = lit
        elsif (av > 0 && lit > 0) || (av < 0 && lit < 0)
          satisfied = 1
        j += 1
      if satisfied == 0
        return 0 if unassigned == 0
        if unassigned == 1
          uv = wassat_fermat_abs(unit)
          want = unit > 0 ? 1 : -1
          return 0 if value[uv] != 0 && value[uv] != want
          if value[uv] == 0
            return 0 if tail >= nv
            value[uv] = want
            queue[tail] = uv
            tail += 1
      link = next_link[pos]

  # A model certificate must assign every declared variable.
  v = 1
  while v <= nv
    return 0 if value[v] == 0
    v += 1
  1

-> wassat_fermat_model(formula)
  return [] unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  pm = i64[4]
  return [] unless wassat_fermat_scan(fla, fcs, fcl, nv, ncl, pm) == 1

  width = pm[0]
  target = pm[1]
  factor = wassat_fermat_factor(target)
  return [] if factor <= 1 || factor >= target
  return [] unless target % factor == 0
  other = target / factor
  lo = factor < other ? factor : other
  hi = factor < other ? other : factor
  return [] if (lo & 1) == 0 || (hi & 1) == 0
  a = (lo + hi) / 2
  b = (hi - lo) / 2
  return [] if (a >> width) != 0 || (b >> width) != 0

  value = i64[nv + 1]
  return [] unless wassat_fermat_propagate(
    fla, fcs, fcl, value, nv, ncl, formula["flat_nlits"], width, a, b
  ) == 1
  model = []
  v = 1
  while v <= nv
    model.push(value[v] > 0 ? v : 0 - v)
    v += 1
  return [] unless wassat_model_satisfies?(formula, model)
  model
