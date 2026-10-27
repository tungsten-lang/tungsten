# Generic bounded preimage search for topologically ordered gate circuits.
#
# The arithmetic lanes in multiplier.w and circuit_miters.w recognize one
# canonical circuit family each. This lane recognizes the common shape
# underneath all of them and nothing more:
#
#   * variables 1..p are inputs, each later variable is the output of
#     exactly one two-input gate over two earlier variables;
#   * a gate is four consecutive ternary clauses over {a, b, o} whose
#     four forbidden assignments cover each (a, b) pair exactly once, so
#     together they define o as an arbitrary Boolean function of a, b
#     (any of the sixteen truth tables, negations included);
#   * every remaining clause is a unit, on inputs or gate outputs.
#
# Search enumerates the free inputs in order, evaluates the whole circuit
# in native code per candidate, and aborts a candidate at the first
# violated output unit. The evaluation budget bounds total gate work, so
# a wide-but-shallow or narrow-but-deep circuit both stay a bounded
# prologue. The lane is model-only: exhausting the budget says nothing,
# and a hit is published only after the full original CNF is replayed.

WASSAT_CIRCUIT_GATE_CAP = 200000
WASSAT_CIRCUIT_MAX_INPUTS = 34
WASSAT_CIRCUIT_WORK_CAP = 200000000

# Scan one four-clause gate group and record its truth table.
# tt[o] holds the required output bit per (a + 2*b) input combination.
# Returns the output variable, else 0.
-> wassat_circuit_gate(fla, fcs, fcl, first, ga, gb, tt, seen_tt) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  return 0 unless fcl[first] == 3
  off = fcs[first]
  a = wassat_multiplier_abs(fla[off])
  b = wassat_multiplier_abs(fla[off + 1])
  o = wassat_multiplier_abs(fla[off + 2])
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
  return 0 if a < 1 || a == b || b == o || a >= o || b >= o
  return 0 if seen_tt[o] != 0
  cover = 0
  table = 0
  r = 0
  while r < 4
    ci = first + r
    return 0 unless fcl[ci] == 3
    co = fcs[ci]
    va = 0 - 1
    vb = 0 - 1
    vo = 0 - 1
    j = 0
    while j < 3
      l = fla[co + j]
      v = wassat_multiplier_abs(l)
      # The clause forbids the assignment making every literal false.
      falsifying = l > 0 ? 0 : 1
      if v == a
        return 0 if va >= 0
        va = falsifying
      elsif v == b
        return 0 if vb >= 0
        vb = falsifying
      elsif v == o
        return 0 if vo >= 0
        vo = falsifying
      else
        return 0
      j += 1
    return 0 if va < 0 || vb < 0 || vo < 0
    combo = va + 2 * vb
    return 0 if ((cover >> combo) & 1) != 0
    cover = cover | (1 << combo)
    table = table | ((1 - vo) << combo)
    r += 1
  return 0 unless cover == 15
  ga[o] = a
  gb[o] = b
  tt[o] = table
  seen_tt[o] = 1
  o

# Enumerate free inputs and evaluate. uval: 0 free, 1 must be 0, 2 must be 1.
# fixed[] carries input-unit values prefilled into value[] by the caller.
-> wassat_circuit_search(ga, gb, tt, uval, value, free_vars,
                         nv, p, nfree, trials) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64) i64
  trial = 0 ## i64
  while trial < trials
    i = 0
    while i < nfree
      value[free_vars[i]] = (trial >> i) & 1
      i += 1
    ok = 1
    o = p + 1
    while o <= nv && ok == 1
      combo = value[ga[o]] + 2 * value[gb[o]]
      want = (tt[o] >> combo) & 1
      value[o] = want
      ok = 0 if uval[o] != 0 && want != uval[o] - 1
      o += 1
    return 1 if ok == 1
    trial += 1
  0

-> wassat_circuit_model(formula)
  return [] unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return [] if nv < 3 || ncl < 5
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]

  # Header shape: groups of four ternaries, then only units.
  ternaries = 0
  units = 0
  ci = 0
  while ci < ncl
    n = fcl[ci]
    if n == 3
      return [] if units > 0
      ternaries += 1
    elsif n == 1
      units += 1
    else
      return []
    ci += 1
  return [] if ternaries == 0 || ternaries % 4 != 0
  gates = ternaries / 4
  return [] if gates > WASSAT_CIRCUIT_GATE_CAP
  p = nv - gates
  return [] if p < 1 || p > WASSAT_CIRCUIT_MAX_INPUTS

  ga = i64[nv + 1]
  gb = i64[nv + 1]
  tt = i64[nv + 1]
  seen_tt = i64[nv + 1]
  uval = i64[nv + 1]
  value = i64[nv + 1]

  gi = 0
  while gi < gates
    o = wassat_circuit_gate(fla, fcs, fcl, gi * 4, ga, gb, tt, seen_tt)
    return [] if o <= p
    gi += 1
  v = p + 1
  while v <= nv
    return [] if seen_tt[v] == 0
    v += 1

  ci = ternaries
  while ci < ncl
    l = fla[fcs[ci]]
    v = wassat_multiplier_abs(l)
    return [] if v < 1 || v > nv
    want = l > 0 ? 2 : 1
    return [] if uval[v] != 0 && uval[v] != want
    uval[v] = want
    ci += 1

  free_vars = i64[p > 0 ? p : 1]
  nfree = 0
  v = 1
  while v <= p
    if uval[v] == 0
      free_vars[nfree] = v
      nfree += 1
    else
      value[v] = uval[v] - 1
    v += 1

  # Bound total gate evaluations, not inputs alone: trials * gates.
  trials = nfree >= 31 ? 2147483647 : (1 << nfree)
  budget = WASSAT_CIRCUIT_WORK_CAP / (gates > 0 ? gates : 1)
  trials = budget if trials > budget
  return [] if trials < 1
  ok = wassat_circuit_search(
    ga, gb, tt, uval, value, free_vars, nv, p, nfree, trials
  )
  return [] unless ok == 1
  model = []
  v = 1
  while v <= nv
    model.push(value[v] == 1 ? v : 0 - v)
    v += 1
  return [] unless wassat_model_satisfies?(formula, model)
  model
