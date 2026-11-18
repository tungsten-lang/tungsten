# Verified SAT shortcut for canonical fixed-width sum-of-three-cubes circuits.
#
# The public encoding presents three little-endian unsigned operand words,
# computes their cubes and pins the final word with regular unit or paired
# binary/unit suffixes. We recover a candidate target from that structure,
# search bounded nonnegative or signed cube domains, and ask Wassat to complete
# the circuit under the recovered operand assumptions.
#
# This route is model-only. Structural misses, targets beyond the arithmetic
# cap, failed conditioned searches, and incomplete models all fall through.
# A SAT result is published only after checking every original clause.

WASSAT_SUM3_MIN_WIDTH = 4
WASSAT_SUM3_MAX_WIDTH = 60
WASSAT_SUM3_ROOT_CAP = 2048
WASSAT_SUM3_CONFLICT_CAP = 1000
WASSAT_SUM3_ANCHOR_BITS = 8

-> wassat_sum3_abs(value) (i64) i64
  value < 0 ? 0 - value : value

-> wassat_sum3_clause1?(lits, offs, lens, ci, a) (i64[] i64[] i64[] i64 i64) i64
  return 0 unless lens[ci] == 1
  lits[offs[ci]] == a ? 1 : 0

-> wassat_sum3_clause2?(lits, offs, lens, ci, a, b) (i64[] i64[] i64[] i64 i64 i64) i64
  return 0 unless lens[ci] == 2
  o = offs[ci]
  lits[o] == a && lits[o + 1] == b ? 1 : 0

-> wassat_sum3_clause3?(lits, offs, lens, ci, a, b, c) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  return 0 unless lens[ci] == 3
  o = offs[ci]
  return 0 unless lits[o] == a && lits[o + 1] == b
  lits[o + 2] == c ? 1 : 0

# The first row of each cube begins with x0*x0, followed by consecutive
# x0*xj partial products.  Match enough of that public truth-table rendering
# to distinguish the three arithmetic operands without depending on absolute
# clause or auxiliary-variable numbers.
-> wassat_sum3_anchor_at(lits, offs, lens, ncl, start,
                         base, width, pm) (i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  bits = width
  bits = WASSAT_SUM3_ANCHOR_BITS if bits > WASSAT_SUM3_ANCHOR_BITS
  need = 3 * bits
  return 0 if start < 3 || start + need > ncl
  return 0 unless lens[start] == 2
  o = offs[start]
  out = lits[o + 1]
  return 0 if out <= 3 * width
  return 0 unless lits[o] == 0 - base
  return 0 unless wassat_sum3_clause2?(
    lits, offs, lens, start + 1, base, 0 - out
  ) == 1
  return 0 unless wassat_sum3_clause2?(
    lits, offs, lens, start + 2, base, 0 - out
  ) == 1
  bit = 1
  ci = start + 3
  while bit < bits
    gate = out + bit
    return 0 unless wassat_sum3_clause3?(
      lits, offs, lens, ci, 0 - base, 0 - base - bit, gate
    ) == 1
    return 0 unless wassat_sum3_clause2?(
      lits, offs, lens, ci + 1, base + bit, 0 - gate
    ) == 1
    return 0 unless wassat_sum3_clause2?(
      lits, offs, lens, ci + 2, base, 0 - gate
    ) == 1
    ci += 3
    bit += 1
  pm[0] = out
  1

-> wassat_sum3_find_anchor(lits, offs, lens, ncl, stop,
                           base, width, pm) (i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  found = 0
  scratch = i64[1]
  ci = 3
  while ci < stop
    if wassat_sum3_anchor_at(
      lits, offs, lens, ncl, ci, base, width, scratch
    ) == 1
      found += 1
      return 0 if found > 2
      pm[2 * found - 2] = ci
      pm[2 * found - 1] = scratch[0]
    ci += 1
  found == 2 ? 1 : 0

# pm receives width, target, and the three cube-anchor clause positions.
-> wassat_sum3_scan(lits, offs, lens, nv, ncl, pm) (i64[] i64[] i64[] i64 i64 i64[]) i64
  return 0 if ncl < 9
  width = lens[0]
  bad_width = width < WASSAT_SUM3_MIN_WIDTH
  bad_width = true if width > WASSAT_SUM3_MAX_WIDTH
  return 0 if bad_width
  return 0 unless lens[1] == width && lens[2] == width
  return 0 if 3 * width >= nv
  word = 0
  while word < 3
    o = offs[word]
    bit = 0
    while bit < width
      return 0 unless lits[o + bit] == 0 - word * width - bit - 1
      bit += 1
    word += 1

  # The three operand clauses are the only clauses wider than a truth table.
  ci = 3
  while ci < ncl
    n = lens[ci]
    return 0 if n < 1 || n > 4
    ci += 1

  suffix = ncl - 2 * width
  return 0 if suffix <= 3
  return 0 unless lens[suffix + 1] == 1
  output_base = wassat_sum3_abs(lits[offs[suffix + 1]])
  binary_suffix = lens[suffix] == 2
  return 0 unless binary_suffix || lens[suffix] == 1
  carry_base = wassat_sum3_abs(lits[offs[suffix] + (binary_suffix ? 1 : 0)])
  return 0 unless output_base + 2 * width - 1 == carry_base
  return 0 unless carry_base + width - 1 == nv

  target = 0 ## i64
  bit = 0
  while bit < width
    oi = suffix + 2 * bit + 1
    return 0 unless lens[oi] == 1
    literal = lits[offs[oi]]
    return 0 unless wassat_sum3_abs(literal) == output_base + 2 * bit
    if binary_suffix
      return 0 unless wassat_sum3_clause2?(
        lits, offs, lens, oi - 1, 0 - literal, 0 - carry_base - bit
      ) == 1
    else
      return 0 unless wassat_sum3_clause1?(
        lits, offs, lens, oi - 1, 0 - carry_base - bit
      ) == 1
    target = target | (1 << bit) if literal > 0
    bit += 1
  pm[5] = binary_suffix ? 1 : 0
  return 0 if target <= 0

  starts = i64[3]
  outs = i64[3]
  cube_starts = i64[3]
  cube_outs = i64[3]
  anchor_span = width
  anchor_span = WASSAT_SUM3_ANCHOR_BITS if anchor_span > WASSAT_SUM3_ANCHOR_BITS
  word = 0
  anchor = i64[4]
  while word < 3
    base = word * width + 1
    return 0 unless wassat_sum3_find_anchor(
      lits, offs, lens, ncl, suffix, base, width, anchor
    ) == 1
    starts[word] = anchor[0]
    outs[word] = anchor[1]
    cube_starts[word] = anchor[2]
    cube_outs[word] = anchor[3]
    if word > 0
      return 0 unless starts[word] > starts[word - 1]
      return 0 unless outs[word] > outs[word - 1] + anchor_span - 1
      return 0 unless cube_starts[word] > cube_starts[word - 1]
      return 0 unless cube_outs[word] > cube_outs[word - 1] + anchor_span - 1
    word += 1
  return 0 unless cube_starts[0] > starts[2]

  pm[0] = width
  pm[1] = target
  pm[2] = starts[0]
  pm[3] = starts[1]
  pm[4] = starts[2]
  1

-> wassat_sum3_find_operands(target, values) (i64 i64[]) i64
  root = 0
  while root < WASSAT_SUM3_ROOT_CAP
    candidate = root + 1
    cube = candidate * candidate * candidate
    break if cube > target
    root = candidate
  if root == WASSAT_SUM3_ROOT_CAP
    candidate = root + 1
    return 0 if candidate * candidate * candidate <= target

  cubes = i64[root + 1]
  i = 0
  while i <= root
    cubes[i] = i * i * i
    i += 1
  x = 0
  while x <= root
    remaining = target - cubes[x]
    y = 0
    z = root
    while y <= z
      sum = cubes[y] + cubes[z]
      if sum == remaining
        # Put a zero term last when possible.  The arithmetic is symmetric,
        # while the canonical circuit's phase completion is substantially
        # stronger when its first multiplier is non-degenerate.
        if x == 0 && z > 0
          values[0] = y
          values[1] = z
          values[2] = x
        else
          values[0] = x
          values[1] = y
          values[2] = z
        return 1
      elsif sum < remaining
        y += 1
      else
        z -= 1
    x += 1
  0

# Bounded signed search: x+y=d gives 3dxy=d^3+z^3-target.
# A square discriminant with matching parity yields integral x,y. The caps
# below keep every intermediate under 2^54; no floating-point root is used.
# Missing the bounded region is UNKNOWN, never a mathematical refutation.
-> wassat_sum3_integer_root(value) (i64) i64
  return 0 if value <= 0
  lo = 1 ## i64
  hi = 131072 ## i64
  while lo < hi
    mid = (lo + hi + 1) / 2 ## i64
    if mid * mid <= value
      lo = mid
    else
      hi = mid - 1
  lo

-> wassat_sum3_find_signed(target, values, d_cap = 200, z_cap = 2000) (i64 i64[] i64 i64) i64
  return 0 if target <= 0 || target > 1000000000
  return 0 if d_cap < 1 || d_cap > 200 || z_cap < 0 || z_cap > 2000
  d = 1 ## i64
  while d <= d_cap
    z = 0 - z_cap ## i64
    while z <= z_cap
      numerator = d * d * d + z * z * z - target ## i64
      denom = 3 * d ## i64
      if numerator % denom == 0
        disc = d * d - 4 * (numerator / denom) ## i64
        if disc >= 0
          root = wassat_sum3_integer_root(disc)
          if root * root == disc && (d + root) % 2 == 0
            x = (d + root) / 2 ## i64
            y = (d - root) / 2 ## i64
            if x * x * x + y * y * y + z * z * z == target
              values[0] = wassat_sum3_abs(x)
              values[1] = wassat_sum3_abs(y)
              values[2] = wassat_sum3_abs(z)
              return 1
      z += 1
    d += 1
  0

-> wassat_sum3_assumptions(width, values, base = 1) (i64 i64[] i64)
  assumptions = []
  word = 0
  while word < 3
    bit = 0
    while bit < width
      variable = word * width + bit + base
      one = bit < 63 && ((values[word] >> bit) & 1) == 1
      assumptions.push(one ? variable : 0 - variable)
      bit += 1
    word += 1
  assumptions

# SAT-X bit-vector circuits start with three primary words and a constant-one
# multiplier. At the tail, a bank of XORs compares a computed word to a
# constant. Original negative units require every comparison bit to be zero.
# Use that target to propose operands and verify the completed Boolean model.
-> wassat_satx_cube_target(lits, offs, lens, nv, nc, bounds) (i64[] i64[] i64[] i64 i64 i64[]) bool
  return false if nc < 32 || lens[0] != 1 || lens[1] != 1
  return false unless lits[offs[0]] == -1
  one = lits[offs[1]]
  return false unless one >= 14 && one <= 770 && (one - 2) % 3 == 0
  width = (one - 2) / 3
  return false if nc < 7 * width + 5 || nv < 5 * width
  bit = 0
  while bit < width
    expected = bit == 0 ? one : 0 - one - bit
    return false unless lens[1 + bit] == 1 && lits[offs[1 + bit]] == expected
    bit += 1
  start = width + 1
  bit = 0
  while bit < 4
    j = start + 4 * bit
    return false unless lens[j] == 3
    input = 2 + bit
    gate = 0 - lits[offs[j] + 2]
    return false if gate <= one + width - 1
    return false unless wassat_sum3_clause3?(lits, offs, lens, j, input, one, 0 - gate) == 1
    return false unless wassat_sum3_clause3?(lits, offs, lens, j + 1, 0 - input, one, 0 - gate) == 1
    return false unless wassat_sum3_clause3?(lits, offs, lens, j + 2, input, 0 - one, 0 - gate) == 1
    return false unless wassat_sum3_clause3?(lits, offs, lens, j + 3, 0 - input, 0 - one, gate) == 1
    bit += 1
  start = nc - 6 * width
  cmp = start + width
  return false unless lens[cmp] == 3
  result_base = lits[offs[cmp]]
  constant_base = lits[offs[cmp] + 1]
  out_base = 0 - lits[offs[cmp] + 2]
  return false unless result_base > one + width && result_base + width <= constant_base && constant_base + width <= out_base && out_base + width - 1 <= nv
  target = 0
  bit = 0
  while bit < width
    c = constant_base + bit
    out = out_base + bit
    r = result_base + bit
    j = cmp + 4 * bit
    return false unless lens[start + bit] == 1
    l = lits[offs[start + bit]]
    return false unless l == c || l == 0 - c
    if l > 0
      return false if bit >= 31
      target |= 1 << bit
    return false unless wassat_sum3_clause3?(lits, offs, lens, j, r, c, 0 - out) == 1
    return false unless wassat_sum3_clause3?(lits, offs, lens, j + 1, 0 - r, 0 - c, 0 - out) == 1
    return false unless wassat_sum3_clause3?(lits, offs, lens, j + 2, r, 0 - c, out) == 1
    return false unless wassat_sum3_clause3?(lits, offs, lens, j + 3, 0 - r, c, out) == 1
    return false unless lens[nc - width + bit] == 1 && lits[offs[nc - width + bit]] == 0 - out
    bit += 1
  bounds[0] = width
  bounds[1] = target
  true

# With x <= y < z, x^3+y^3 grows monotonically in either operand. Search
# this signed family in O(B^2) by moving its two endpoints toward each other.
-> wassat_satx_cube_values(target, width, values) (i64 i64 i64[]) bool
  bound = width < 7 ? (1 << width) - 1 : 64
  z = 2
  while z <= bound
    goal = z * z * z + target
    x = 1
    y = z - 1
    while x <= y
      total = x * x * x + y * y * y
      if total == goal
        values[0] = x
        values[1] = y
        values[2] = z
        return true
      elsif total < goal
        x += 1
      else
        y -= 1
    z += 1
  false

-> wassat_sum3_solve(formula)
  wassat_sum3_solve_budget(formula, WASSAT_SUM3_CONFLICT_CAP)

-> wassat_sum3_solve_budget(formula, conflict_cap)
  miss = {
    "recognized": false, "status": 0, "model": [],
    "width": 0, "target": 0, "x": 0, "y": 0, "z": 0,
    "conflicts": 0, "decisions": 0, "props": 0
  }
  return miss unless formula.has_key?("flat_ncl")
  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  pm = i64[8]
  satx = false
  unless wassat_sum3_scan(lits, offs, lens, formula["nvars"], formula["flat_ncl"], pm) == 1
    return miss unless wassat_satx_cube_target(lits, offs, lens, formula["nvars"], formula["flat_ncl"], pm)
    satx = true
  miss["recognized"] = true
  miss["width"] = pm[0]
  miss["target"] = pm[1]

  values = i64[3]
  if satx
    return miss unless wassat_satx_cube_values(pm[1], pm[0], values)
  elsif pm[5] == 1
    return miss unless wassat_sum3_find_signed(pm[1], values) == 1
  else
    return miss unless wassat_sum3_find_operands(pm[1], values) == 1
  # Recognition only proposes assignments. Six orderings cover the unsigned
  # magnitude blocks of signed circuits; every result still passes full CNF
  # replay. All conditioned searches share the caller's conflict allowance.
  orders = [[0, 1, 2], [0, 2, 1], [1, 0, 2], [1, 2, 0], [2, 0, 1], [2, 1, 0]]
  tries = !satx && pm[5] == 1 ? 6 : 1
  attempt = 0
  while attempt < tries
    ordered = i64[3]
    order = orders[attempt]
    word = 0
    fits = true
    while word < 3
      ordered[word] = values[order[word]]
      fits = false if pm[0] < 63 && ordered[word] >= (1 << pm[0])
      word += 1
    return miss unless fits
    assumptions = wassat_sum3_assumptions(pm[0], ordered, satx ? 2 : 1)
    remaining = conflict_cap > 0 ? conflict_cap - miss["conflicts"] : 0
    return miss if conflict_cap > 0 && remaining <= 0
    art = wassat_raw_artifact(formula, formula["nvars"])
    solver = Wassat.from_flat(formula["nvars"], art, 0)
    result = solver.solve_assuming_budget(assumptions, remaining)
    miss["conflicts"] += result["conflicts"]
    miss["decisions"] += result["decisions"]
    miss["props"] += result["props"]
    if result["status"] == 1 && result["model"].size == formula["nvars"]
      if wassat_model_satisfies?(formula, result["model"])
        miss["x"] = ordered[0]
        miss["y"] = ordered[1]
        miss["z"] = ordered[2]
        miss["status"] = 1
        miss["model"] = result["model"]
        return miss
    attempt += 1
  miss
