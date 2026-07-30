# Verified SAT shortcut for canonical fixed-width sum-of-three-cubes circuits.
#
# The public encoding presents three little-endian unsigned operand words,
# computes their cubes, adds them, and pins the final word with a regular unit
# suffix.  We recover that target from DIMACS structure, search a bounded
# non-negative cube domain, and ask an ordinary Wassat instance to complete
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
  return 0 unless lens[suffix] == 1 && lens[suffix + 1] == 1
  carry_base = wassat_sum3_abs(lits[offs[suffix]])
  output_base = wassat_sum3_abs(lits[offs[suffix + 1]])
  return 0 unless lits[offs[suffix]] == 0 - carry_base
  return 0 unless output_base + 2 * width - 1 == carry_base
  return 0 unless carry_base + width - 1 == nv

  target = 0
  bit = 0
  while bit < width
    return 0 unless wassat_sum3_clause1?(
      lits, offs, lens, suffix + 2 * bit, 0 - carry_base - bit
    ) == 1
    oi = suffix + 2 * bit + 1
    return 0 unless lens[oi] == 1
    literal = lits[offs[oi]]
    return 0 unless wassat_sum3_abs(literal) == output_base + 2 * bit
    target = target | (1 << bit) if literal > 0
    bit += 1
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

-> wassat_sum3_assumptions(width, values) (i64 i64[])
  assumptions = []
  word = 0
  while word < 3
    bit = 0
    while bit < width
      variable = word * width + bit + 1
      one = ((values[word] >> bit) & 1) == 1
      assumptions.push(one ? variable : 0 - variable)
      bit += 1
    word += 1
  assumptions

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
  return miss unless wassat_sum3_scan(
    lits, offs, lens,
    formula["nvars"], formula["flat_ncl"], pm
  ) == 1
  miss["recognized"] = true
  miss["width"] = pm[0]
  miss["target"] = pm[1]

  values = i64[3]
  return miss unless wassat_sum3_find_operands(pm[1], values) == 1
  miss["x"] = values[0]
  miss["y"] = values[1]
  miss["z"] = values[2]
  assumptions = wassat_sum3_assumptions(pm[0], values)
  art = wassat_raw_artifact(formula, formula["nvars"])
  solver = Wassat.from_flat(formula["nvars"], art, 0)
  result = solver.solve_assuming_budget(
    assumptions, conflict_cap
  )
  miss["conflicts"] = result["conflicts"]
  miss["decisions"] = result["decisions"]
  miss["props"] = result["props"]
  return miss unless result["status"] == 1
  return miss unless result["model"].size == formula["nvars"]
  return miss unless wassat_model_satisfies?(formula, result["model"])
  miss["status"] = 1
  miss["model"] = result["model"]
  miss
