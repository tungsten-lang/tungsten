# Verified SAT shortcut for canonical multiplier circuits.
#
# Some competition instances encode an unsigned multiplier as consecutive
# four-clause truth tables, then constrain every product bit with a unit. CDCL
# is the wrong abstraction for those instances: recover the two operands,
# factor the requested product, evaluate the circuit, and validate the complete
# assignment against the original CNF.
#
# This is intentionally model-only. Every structural mismatch, unsupported
# width, failed factor search, or failed final validation returns no result and
# ordinary SAT search continues. It can therefore never manufacture an UNSAT
# answer, and a false-positive recognition can at worst waste one bounded scan.

WASSAT_MULTIPLIER_AND = 1
WASSAT_MULTIPLIER_XOR = 2
WASSAT_MULTIPLIER_TRIAL_CAP = 1048576
WASSAT_MULTIPLIER_GATE_CAP = 200000

-> wassat_multiplier_abs(v) (i64) i64
  v < 0 ? 0 - v : v

# Recognize the flat circuit and fill ga/gb/gk by output variable. uval is
# zero for non-units, one for a negative unit (value 0), and two for a positive
# unit (value 1). pm receives operand widths and the packed target:
#   pm[0] = width A, pm[1] = width B, pm[2] = target.
-> wassat_multiplier_scan(fla, fcs, fcl, nv, ncl, p,
                          ga, gb, gk, fanout, edge, uval, pm) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  gates = nv - p
  stride = p + 1
  gi = 0
  while gi < gates
    c0 = gi * 4
    return 0 unless fcl[c0] == 3
    off = fcs[c0]
    a = wassat_multiplier_abs(fla[off])
    b = wassat_multiplier_abs(fla[off + 1])
    o = wassat_multiplier_abs(fla[off + 2])
    # Sort the three variables. Topological numbering makes the largest one
    # the gate output; AND and XOR are symmetric in the other two.
    if a > b
      t = a
      a = b
      b = t
    if b > o
      t = b
      b = o
      o = t
    if a > b
      t = a
      a = b
      b = t
    return 0 if a < 1 || a == b || b == o || o > nv
    return 0 if o <= p || a >= o || b >= o || gk[o] != 0

    # Each clause forbids the one assignment on which all three literals are
    # false. The four forbidden assignments completely identify the gate.
    patterns = 0
    r = 0
    while r < 4
      ci = c0 + r
      return 0 unless fcl[ci] == 3
      co = fcs[ci]
      pat = 0
      vars_seen = 0
      j = 0
      while j < 3
        l = fla[co + j]
        v = wassat_multiplier_abs(l)
        bit = 0
        if v == a
          bit = 1
          pat = pat | 1 if l < 0
        elsif v == b
          bit = 2
          pat = pat | 2 if l < 0
        elsif v == o
          bit = 4
          pat = pat | 4 if l < 0
        else
          return 0
        return 0 if (vars_seen & bit) != 0
        vars_seen = vars_seen | bit
        j += 1
      return 0 unless vars_seen == 7
      pb = 1 << pat
      return 0 if (patterns & pb) != 0
      patterns = patterns | pb
      r += 1

    kind = 0
    kind = WASSAT_MULTIPLIER_AND if patterns == 120 # 0x78
    kind = WASSAT_MULTIPLIER_XOR if patterns == 150 # 0x96
    return 0 if kind == 0
    ga[o] = a
    gb[o] = b
    gk[o] = kind
    fanout[a] = fanout[a] + 1
    fanout[b] = fanout[b] + 1

    # Every primary use belongs to one partial-product AND. This rejects
    # arbitrary AND/XOR networks before the more expensive graph check.
    if a <= p || b <= p
      return 0 unless a <= p && b <= p && kind == WASSAT_MULTIPLIER_AND
      ei = a * stride + b
      return 0 if edge[ei] != 0
      edge[ei] = 1
      edge[b * stride + a] = 1
    gi += 1

  # Every derived variable is defined once, even if its four-clause group was
  # reordered relative to the other groups.
  v = p + 1
  while v <= nv
    return 0 if gk[v] == 0
    v += 1

  # The tail consists only of unique units on derived variables.
  ci = 4 * gates
  while ci < ncl
    return 0 unless fcl[ci] == 1
    l = fla[fcs[ci]]
    v = wassat_multiplier_abs(l)
    return 0 if v <= p || v > nv || uval[v] != 0
    uval[v] = l > 0 ? 2 : 1
    ci += 1

  # Partial products must form one complete contiguous K(widthA,widthB).
  first_neighbor = 0
  j = 2
  while j <= p && first_neighbor == 0
    first_neighbor = j if edge[stride + j] != 0
    j += 1
  return 0 if first_neighbor == 0
  wa = first_neighbor - 1
  wb = p - wa
  return 0 if wa < 1 || wb < 1 || wa > 62 || wb > 62
  i = 1
  while i <= p
    j = i + 1
    while j <= p
      want = i <= wa && j > wa
      have = edge[i * stride + j] != 0
      return 0 if want != have
      j += 1
    i += 1

  # Units are exactly the zero-fanout derived nodes. Ascending sink ids encode
  # product bits least-significant first.
  target = 0
  bit = 0
  v = p + 1
  while v <= nv
    if fanout[v] == 0
      return 0 if uval[v] == 0
      if uval[v] == 2
        return 0 if bit >= 63
        target = target | (1 << bit)
      bit += 1
    else
      return 0 if uval[v] != 0
    v += 1
  return 0 unless bit == p
  pm[0] = wa
  pm[1] = wb
  pm[2] = target
  1

# Evaluate one operand pair through the recovered topological network.
-> wassat_multiplier_eval(ga, gb, gk, uval, value,
                          nv, p, wa, x, y) (i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  i = 0
  while i < wa
    value[i + 1] = (x >> i) & 1
    i += 1
  i = 0
  while i < p - wa
    value[wa + i + 1] = (y >> i) & 1
    i += 1
  o = p + 1
  while o <= nv
    a = value[ga[o]]
    b = value[gb[o]]
    value[o] = a & b
    value[o] = a ^ b if gk[o] == WASSAT_MULTIPLIER_XOR
    if uval[o] != 0 && value[o] != uval[o] - 1
      return 0
    o += 1
  1

# Factor the packed target within the operand widths and leave a satisfying
# circuit assignment in value. Trial division is deliberately capped: a miss
# falls through to CDCL instead of turning a shortcut into a new long stage.
-> wassat_multiplier_factor(ga, gb, gk, uval, value,
                            nv, p, wa, wb, target) (i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  if target == 0
    return wassat_multiplier_eval(ga, gb, gk, uval, value,
                                  nv, p, wa, 0, 0)
  xmax = (1 << wa) - 1
  ymax = (1 << wb) - 1
  lo = (target - 1) / xmax + 1
  hi = ymax
  hi = WASSAT_MULTIPLIER_TRIAL_CAP if hi > WASSAT_MULTIPLIER_TRIAL_CAP
  y = lo
  while y <= hi
    if target % y == 0
      x = target / y
      if x <= xmax
        ok = wassat_multiplier_eval(ga, gb, gk, uval, value,
                                    nv, p, wa, x, y)
        return 1 if ok == 1
    y += 1
  0

# Box only the final model. The constant-time header relation rejects ordinary
# CNFs before any scratch allocation.
-> wassat_multiplier_model(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  d = 4 * nv - ncl
  return [] if d <= 0 || d % 3 != 0
  p = d / 3
  gates = nv - p
  bad_shape = p < 2 || p > 124 || gates < 1
  bad_shape = true if gates > WASSAT_MULTIPLIER_GATE_CAP
  bad_shape = true if ncl != 4 * gates + p
  return [] if bad_shape

  ga = i64[nv + 1]
  gb = i64[nv + 1]
  gk = i64[nv + 1]
  fanout = i64[nv + 1]
  edge = i64[(p + 1) * (p + 1)]
  uval = i64[nv + 1]
  value = i64[nv + 1]
  pm = i64[4]
  ok = wassat_multiplier_scan(fla, fcs, fcl, nv, ncl, p,
                              ga, gb, gk, fanout, edge, uval, pm)
  return [] unless ok == 1
  ok = wassat_multiplier_factor(ga, gb, gk, uval, value,
                                nv, p, pm[0], pm[1], pm[2])
  return [] unless ok == 1
  model = []
  v = 1
  while v <= nv
    model.push(value[v] == 1 ? v : 0 - v)
    v += 1
  return [] unless wassat_model_satisfies?(formula, model)
  model
