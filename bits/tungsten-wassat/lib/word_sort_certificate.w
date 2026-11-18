# Semantic checks for the word abstraction used by the sorting-miter lane.
# Counts locate candidate groups; only these checks authorize substitution.
use solver

-> wassat_word_sort_xor_group?(lits, offs, lens, clauses, group_start, count, a, b, output) (i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64) bool
  return false if count != 4 || a == output || b == output
  row = 0
  while row < 8
    av = row & 1; bv = (row >> 1) & 1; ov = (row >> 2) & 1
    if a != b || av == bv
      allowed = true
      ci = 0
      while ci < count
        clause = clauses[group_start + ci]
        return false if lens[clause] != 3
        satisfied = false
        j = 0
        while j < 3
          lit = lits[offs[clause] + j]
          v = lit < 0 ? 0 - lit : lit
          bit = 0
          if v == a
            bit = av
          elsif v == b
            bit = bv
          elsif v == output
            bit = ov
          else
            return false
          satisfied = true if (lit > 0 && bit == 1) || (lit < 0 && bit == 0)
          j += 1
        allowed = false unless satisfied
        ci += 1
      return false if allowed != (ov == (av ^ bv))
    row += 1
  true

-> wassat_word_sort_or_group?(lits, offs, lens, clauses, group_start, count, first, width, output) (i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64) bool
  return false if width < 2 || width > 16 || count != width + 1
  binary = 0; wide = 0; i = 0
  full = (1 << width) - 1
  while i < count
    ci = clauses[group_start + i]; off = offs[ci]; n = lens[ci]
    if n == 2
      x = lits[off]; y = lits[off + 1]
      input = x == output ? y : x
      return false unless (x == output || y == output) && input <= 0 - first && input > 0 - (first + width)
      bit = 1 << ((0 - input) - first)
      return false if (binary & bit) != 0
      binary = binary | bit
    elsif n == width + 1
      return false if wide != 0
      inputs = 0; outputs = 0; j = 0
      while j < n
        lit = lits[off + j]
        if lit == 0 - output
          outputs += 1
        else
          return false if lit < first || lit >= first + width
          bit = 1 << (lit - first)
          return false if (inputs & bit) != 0
          inputs = inputs | bit
        j += 1
      return false unless outputs == 1 && inputs == full
      wide = 1
    else
      return false
    i += 1
  wide == 1 && binary == full

-> wassat_word_sort_comparator_literal(lit, a, b, first, width, length) (i64 i64 i64 i64 i64 i64) i64
  v = lit < 0 ? 0 - lit : lit
  local = 0
  if v >= a && v < a + width
    local = v - a + 1
  elsif v >= b && v < b + width
    local = width + v - b + 1
  elsif v >= first && v < first + length
    local = 2 * width + v - first + 1
  return 0 if local == 0
  lit < 0 ? 0 - local : local

-> wassat_word_sort_owned_row(owner, rows, row)
  wassat_query_keep(owner, row, 8 * row.size)
  rows.push(row)

# Prove that the ENTIRE original macro implies unsigned a>b. The reference
# relation is built from its three-input truth table, independently of the
# original triangular implementation. Restrictions on inputs are harmless:
# dropping them enlarges the abstract domain, so cannot invent a refutation.
-> wassat_word_sort_comparator?(lits, offs, lens, clauses, starts, counts, a, b, first, width, length, cap = 4096)
  return false if width < 1 || width > 16 || length < 1 || cap < 1
  owner = wassat_query_storage()
  begin
    wassat_word_sort_comparator_owned?(owner, lits, offs, lens, clauses, starts, counts, a, b, first, width, length, cap)
  ensure
    z = wassat_query_destroy(owner)

-> wassat_word_sort_comparator_owned?(owner, lits, offs, lens, clauses, starts, counts, a, b, first, width, length, cap)
  rows = wassat_query_box(owner)
  v = first
  while v < first + length
    i = 0
    while i < counts[v]
      ci = clauses[starts[v] + i]
      row = wassat_query_box(owner)
      j = 0
      while j < lens[ci]
        local = wassat_word_sort_comparator_literal(lits[offs[ci] + j], a, b, first, width, length)
        return false if local == 0
        row.push(local)
        j += 1
      rows.push(row)
      i += 1
    v += 1
  zero = 2 * width + length + 1
  wassat_word_sort_owned_row(owner, rows, [0 - zero])
  prev = zero; bit = 0
  while bit < width
    x = wassat_word_sort_comparator_literal(a + bit, a, b, first, width, length)
    y = wassat_word_sort_comparator_literal(b + bit, a, b, first, width, length)
    output = zero + bit + 1
    assignment = 0
    while assignment < 8
      av = assignment & 1; bv = (assignment >> 1) & 1; pv = (assignment >> 2) & 1
      want = av > bv || (av == bv && pv == 1)
      wassat_word_sort_owned_row(owner, rows,
        [av == 1 ? 0 - x : x, bv == 1 ? 0 - y : y, pv == 1 ? 0 - prev : prev, want ? output : 0 - output])
      assignment += 1
    prev = output
    bit += 1
  actual = 2 * width + length
  solver = Wassat.new(zero + width, rows, WASSAT_PROOF_DRAT, 0, false, owner)
  wassat_query_keep(owner, solver, 0)
  left = solver.solve_assuming_budget([actual, 0 - prev], cap)
  return false unless left["status"] == -1 && left["conflicts"] < cap
  right = solver.solve_assuming_budget([0 - actual, prev], cap - left["conflicts"])
  right["status"] == -1
