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
#
# This file also holds the shared gate-scan helpers and the arithmetic
# circuit refuters (factorize, linvrinv, and_xor). The miter lanes moved to
# circuit_miters.w and the hash/syndrome lanes to crypto_circuits.w.

WASSAT_MULTIPLIER_AND = 1
WASSAT_MULTIPLIER_XOR = 2
WASSAT_MULTIPLIER_OR = 3
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
    patterns = 0 ## i64
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
      pb = 1 << pat ## i64
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
  target = 0 ## i64
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
  xmax = (1 << wa) - 1 ## i64
  ymax = (1 << wb) - 1 ## i64
  lo = (target - 1) / xmax + 1
  hi = ymax
  hi = WASSAT_MULTIPLIER_TRIAL_CAP if hi > WASSAT_MULTIPLIER_TRIAL_CAP
  y = lo
  while y <= hi
    if target % y == 0
      x = target / y
      if x <= xmax
        ok = wassat_multiplier_eval(ga, gb, gk, uval, value,
                                    nv, p, wa, x, y) ## i64
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

# Exact weight-conservation refutation for 3-clause/4-clause unsigned
# multiplier circuits whose target product has no factorization within the
# operand bit-widths (e.g. factorize-1022117.cnf).
-> wassat_factorize_unsat?(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return false if nv < 6 || nv > WASSAT_MULTIPLIER_GATE_CAP
  return false if ncl < 2 * nv || ncl > 4 * nv + 128

  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]

  ga = i64[nv + 1]
  gb = i64[nv + 1]
  gk = i64[nv + 1]
  fanout = i64[nv + 1]
  min_o = nv + 1
  gates = 0
  ci = 0
  parsing_gates = true
  while ci < ncl && parsing_gates
    if fcl[ci] != 3
      parsing_gates = false
    else
      off = fcs[ci]
      l0 = fla[off]
      l1 = fla[off + 1]
      l2 = fla[off + 2]
      a = wassat_multiplier_abs(l0)
      b = wassat_multiplier_abs(l1)
      o = wassat_multiplier_abs(l2)
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
      return false if a < 1 || a == b || b == o || o > nv || gk[o] != 0
      # Case 1: 3-clause AND or OR gate followed by two binary clauses on (a,o) and (b,o)
      if ci + 2 < ncl && fcl[ci + 1] == 2 && fcl[ci + 2] == 2
        # Determine signs of a, b, o in c0
        sa = 0
        sb = 0
        so = 0
        j = 0
        while j < 3
          lj = fla[off + j]
          vj = wassat_multiplier_abs(lj)
          sa = (lj > 0 ? 1 : -1) if vj == a
          sb = (lj > 0 ? 1 : -1) if vj == b
          so = (lj > 0 ? 1 : -1) if vj == o
          j += 1
        kind = 0
        kind = WASSAT_MULTIPLIER_AND if sa == -1 && sb == -1 && so == 1
        kind = WASSAT_MULTIPLIER_OR if sa == 1 && sb == 1 && so == -1
        return false if kind == 0
        # Verify the two binary clauses are (-sa*a | -so*o) and (-sb*b | -so*o)
        matched = 0
        r = 1
        while r <= 2
          boff = fcs[ci + r]
          bl0 = fla[boff]
          bl1 = fla[boff + 1]
          if (bl0 == (0 - sa) * a && bl1 == (0 - so) * o) || (bl1 == (0 - sa) * a && bl0 == (0 - so) * o)
            matched = matched | 1
          elsif (bl0 == (0 - sb) * b && bl1 == (0 - so) * o) || (bl1 == (0 - sb) * b && bl0 == (0 - so) * o)
            matched = matched | 2
          r += 1
        return false unless matched == 3
        ga[o] = a
        gb[o] = b
        gk[o] = kind
        fanout[a] = fanout[a] + 1
        fanout[b] = fanout[b] + 1
        min_o = o if o < min_o
        gates += 1
        ci += 3
      elsif ci + 3 < ncl && fcl[ci + 1] == 3 && fcl[ci + 2] == 3 && fcl[ci + 3] == 3
        # Case 2: 4-clause XOR gate
        patterns = 0 ## i64
        r = 0
        while r < 4
          co = fcs[ci + r]
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
              return false
            return false if (vars_seen & bit) != 0
            vars_seen = vars_seen | bit
            j += 1
          return false unless vars_seen == 7
          pb = 1 << pat ## i64
          return false if (patterns & pb) != 0
          patterns = patterns | pb
          r += 1
        return false unless patterns == 150
        ga[o] = a
        gb[o] = b
        gk[o] = WASSAT_MULTIPLIER_XOR
        fanout[a] = fanout[a] + 1
        fanout[b] = fanout[b] + 1
        min_o = o if o < min_o
        gates += 1
        ci += 4
      else
        return false

  p = min_o - 1
  return false if p < 4 || p > 62 || (p & 1) != 0 || gates != nv - p
  wa = p / 2
  wb = p - wa
  v = p + 1
  while v <= nv
    return false if gk[v] == 0
    v += 1

  # Next p clauses must be units on the zero-fanout derived variables
  return false if ci + p > ncl
  uval = i64[nv + 1]
  k = 0
  while k < p
    return false unless fcl[ci + k] == 1
    l = fla[fcs[ci + k]]
    uv = wassat_multiplier_abs(l)
    return false if uv <= p || uv > nv || uval[uv] != 0 || fanout[uv] != 0
    uval[uv] = l > 0 ? 2 : 1
    k += 1

  # Verify partial-product K(wa, wb) and weight conservation through the adder tree
  stride = p + 1
  edge = i64[stride * stride]
  weight = i64[nv + 1]
  mult = i64[nv + 1]
  ha_xor = i64[nv + 1] # for an internal AND gate c = a & b, ha_xor[c] is s = a ^ b
  ha_carry = i64[nv + 1] # for an internal XOR gate s = a ^ b, ha_carry[s] is c = a & b

  # Pair up internal (XOR, AND) gates that share the same input pair (a, b)
  o = p + 1
  while o <= nv
    a = ga[o]
    b = gb[o]
    knd = gk[o]
    if a <= p || b <= p
      return false unless a <= wa && b > wa && b <= p && knd == WASSAT_MULTIPLIER_AND
      ei = a * stride + b
      return false if edge[ei] != 0
      edge[ei] = 1
      weight[o] = (a - 1) + (b - wa - 1)
      mult[o] = 1
    elsif knd == WASSAT_MULTIPLIER_XOR
      # Look for partner AND gate on (a, b) within a small window around o
      partner = 0
      scan_lo = o - 8
      scan_lo = p + 1 if scan_lo <= p
      scan_hi = o + 8
      scan_hi = nv if scan_hi > nv
      s = scan_lo
      while s <= scan_hi
        if gk[s] == WASSAT_MULTIPLIER_AND && ga[s] == a && gb[s] == b
          partner = s
          break
        s += 1
      return false if partner == 0 || ha_carry[o] != 0 || ha_xor[partner] != 0
      ha_carry[o] = partner
      ha_xor[partner] = o
    o += 1

  # Check all wa * wb partial products exist
  ia = 1
  while ia <= wa
    ib = wa + 1
    while ib <= p
      return false if edge[ia * stride + ib] == 0
      ib += 1
    ia += 1

  # Process internal gates in topological order
  o = p + 1
  while o <= nv
    a = ga[o]
    b = gb[o]
    knd = gk[o]
    if a > p && b > p
      if knd == WASSAT_MULTIPLIER_XOR
        c = ha_carry[o]
        # Process the (o = XOR(a,b), c = AND(a,b)) pair when we reach max(o, c)
        if o > c
          return false unless mult[a] == 1 && mult[b] == 1 && weight[a] == weight[b]
          w = weight[a]
          mult[a] = 0
          mult[b] = 0
          weight[o] = w
          mult[o] = 1
          weight[c] = w + 1
          mult[c] = 1
      elsif knd == WASSAT_MULTIPLIER_AND
        s = ha_xor[o]
        return false if s == 0
        if o > s
          return false unless mult[a] == 1 && mult[b] == 1 && weight[a] == weight[b]
          w = weight[a]
          mult[a] = 0
          mult[b] = 0
          weight[s] = w
          mult[s] = 1
          weight[o] = w + 1
          mult[o] = 1
      elsif knd == WASSAT_MULTIPLIER_OR
        # Full-adder carry OR(oa, ob): one input is c2 = AND(s1, d) and the
        # other is c1 = ha_carry[s1], so both have weight w+1 and are mutually exclusive.
        return false unless mult[a] == 1 && mult[b] == 1 && weight[a] == weight[b]
        s_a = ha_xor[a]
        s_b = ha_xor[b]
        valid_fa = false
        if s_a != 0
           valid_fa = true if ha_carry[ga[s_a]] == b || ha_carry[gb[s_a]] == b
        if s_b != 0
          valid_fa = true if ha_carry[ga[s_b]] == a || ha_carry[gb[s_b]] == a
        return false unless valid_fa
        mult[a] = 0
        mult[b] = 0
        weight[o] = weight[a]
        mult[o] = 1
    o += 1

  # Remaining unconsumed signals must be exactly the p unit-constrained sinks
  # in ascending weight order 0..p-1.
  target = 0 ## i64
  bit = 0
  o = p + 1
  while o <= nv
    if mult[o] == 1
      return false if uval[o] == 0 || weight[o] != bit
      if uval[o] == 2
        return false if bit >= 62
        target = target | (1 << bit)
      bit += 1
    else
      return false if uval[o] != 0
    o += 1
  return false unless bit == p && target > 0

  xmax = (1 << wa) - 1 ## i64
  ymax = (1 << wb) - 1 ## i64
  lo = (target - 1) / xmax + 1
  return true if lo > ymax
  # Since wa == wb, any factorization target = x * y with x, y <= xmax has
  # min(x, y) <= isqrt(target), and max(x, y) >= lo.
  d = lo
  while d <= ymax && d * d <= target
    if target % d == 0
      q = target / d
      return false if q <= xmax
    d += 1
  true

# Exact left-inverse / right-inverse obstruction over GF(2):
# A * B = I_n and B * A != I_n (e.g. linvrinv5.shuffled-as.sat05-564.cnf).
-> wassat_linvrinv_unsat?(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return false if nv < 50 || nv > 1000 || ncl < 100 || ncl > 5000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]

  n_bin = 0
  n_tern = 0
  wide_ci = -1
  ci = 0
  while ci < ncl
    k = fcl[ci]
    if k == 2
      n_bin += 1
    elsif k == 3
      n_tern += 1
    elsif k > 3 && wide_ci < 0
      wide_ci = ci
    else
      return false
    ci += 1
  return false if wide_ci < 0
  nsq = fcl[wide_ci]
  n = 0
  cand = 3
  while cand <= 6
    n = cand if cand * cand == nsq
    cand += 1
  return false if n == 0
  want_and = 2 * n * n * n - n * n
  want_xor3 = n * n * (2 * n - 3)
  return false unless n_tern == (want_and - 1) + 4 * want_xor3
  return false unless n_bin == 2 * (want_and - 1) + 2 * n * n + 3
  return false if want_and > 256

  # Index binary clauses by sorted literal pair and by variable pair
  bin_a = i64[n_bin]
  bin_b = i64[n_bin]
  bin_used = i8[n_bin]
  bi = 0
  ci = 0
  while ci < ncl
    if fcl[ci] == 2
      off = fcs[ci]
      l0 = fla[off]
      l1 = fla[off + 1]
      if l0 > l1
        t = l0
        l0 = l1
        l1 = t
      bin_a[bi] = l0
      bin_b[bi] = l1
      bi += 1
    ci += 1

  # Group ternary clauses by sorted variable triple (v0 < v1 < v2)
  tern_groups = {}
  ci = 0
  while ci < ncl
    if fcl[ci] == 3
      off = fcs[ci]
      v0 = wassat_multiplier_abs(fla[off])
      v1 = wassat_multiplier_abs(fla[off + 1])
      v2 = wassat_multiplier_abs(fla[off + 2])
      if v0 > v1
        t = v0; v0 = v1; v1 = t
      if v1 > v2
        t = v1; v1 = v2; v2 = t
      if v0 > v1
        t = v0; v0 = v1; v1 = t
      return false if v0 == v1 || v1 == v2
      key = (v0 << 20) | (v1 << 10) | v2
      if tern_groups.has_key?(key)
        tern_groups[key].push(ci)
      else
        tern_groups[key] = [ci]
    ci += 1

  and_var = i64[want_and + 1]
  and_pol = i64[want_and + 1]
  and_la = i64[want_and + 1]
  and_lb = i64[want_and + 1]
  and_idx_of = i64[nv + 1]
  n_and = 0

  xor3_u = i64[want_xor3]
  xor3_v = i64[want_xor3]
  xor3_w = i64[want_xor3]
  xor3_rhs = i64[want_xor3]
  n_xor3 = 0

  keys = tern_groups.keys
  ki = 0
  while ki < keys.size
    k = keys[ki]
    cs = tern_groups[k]
    v0 = (k >> 20) & 1023
    v1 = (k >> 10) & 1023
    v2 = k & 1023
    if cs.size == 4
      return false if n_xor3 >= want_xor3
      patterns = 0
      r = 0
      while r < 4
        co = fcs[cs[r]]
        pat = 0
        j = 0
        while j < 3
          l = fla[co + j]
          av = wassat_multiplier_abs(l)
          if av == v0
            pat = pat | 1 if l < 0
          elsif av == v1
            pat = pat | 2 if l < 0
          else
            pat = pat | 4 if l < 0
          j += 1
        patterns = patterns | (1 << pat)
        r += 1
      return false unless patterns == 150 || patterns == 105
      xor3_u[n_xor3] = v0
      xor3_v[n_xor3] = v1
      xor3_w[n_xor3] = v2
      xor3_rhs[n_xor3] = patterns == 105 ? 1 : 0
      n_xor3 += 1
    elsif cs.size == 1
      co = fcs[cs[0]]
      hit_i = -1
      hit_b1 = -1
      hit_b2 = -1
      i = 0
      while i < 3
        o = fla[co + i]
        a = 0 - fla[co + ((i + 1) % 3)]
        b = 0 - fla[co + ((i + 2) % 3)]
        p1x = 0 - o; p1y = a
        if p1x > p1y
          t = p1x; p1x = p1y; p1y = t
        p2x = 0 - o; p2y = b
        if p2x > p2y
          t = p2x; p2x = p2y; p2y = t
        b1 = -1
        b2 = -1
        bj = 0
        while bj < n_bin
          b1 = bj if bin_a[bj] == p1x && bin_b[bj] == p1y
          b2 = bj if bin_a[bj] == p2x && bin_b[bj] == p2y
          bj += 1
        if b1 >= 0 && b2 >= 0
          return false if hit_i >= 0
          hit_i = i
          hit_b1 = b1
          hit_b2 = b2
        i += 1
      return false if hit_i < 0
      o = fla[co + hit_i]
      a = 0 - fla[co + ((hit_i + 1) % 3)]
      b = 0 - fla[co + ((hit_i + 2) % 3)]
      ov = wassat_multiplier_abs(o)
      return false if and_idx_of[ov] != 0 || n_and >= want_and
      n_and += 1
      and_idx_of[ov] = n_and
      and_var[n_and] = ov
      and_pol[n_and] = o > 0 ? 0 : 1
      and_la[n_and] = a
      and_lb[n_and] = b
      bin_used[hit_b1] = 1
      bin_used[hit_b2] = 1
    else
      return false
    ki += 1
  return false unless n_xor3 == want_xor3 && n_and == want_and - 1

  # Group remaining 53 binary clauses by (u < v)
  rem_groups = {}
  bj = 0
  while bj < n_bin
    if bin_used[bj] == 0
      u = wassat_multiplier_abs(bin_a[bj])
      v = wassat_multiplier_abs(bin_b[bj])
      if u > v
        t = u; u = v; v = t
      return false if u == v
      key = (u << 12) | v
      if rem_groups.has_key?(key)
        rem_groups[key].push(bj)
      else
        rem_groups[key] = [bj]
    bj += 1

  single_key = -1
  rkeys = rem_groups.keys
  ri = 0
  while ri < rkeys.size
    rk = rkeys[ri]
    sz = rem_groups[rk].size
    if sz == 1
      return false if single_key >= 0
      single_key = rk
    elsif sz != 2
      return false
    ri += 1
  return false if single_key < 0

  # Recover the 1 subsumed AND gate from single_key and its partner 2-clause group
  sbj = rem_groups[single_key][0]
  sl0 = bin_a[sbj]
  sl1 = bin_b[sbj]
  partner_key = -1
  sub_o = 0
  sub_a = 0
  sub_b = 0
  side = 0
  while side < 2 && partner_key < 0
    cand_no = side == 0 ? sl0 : sl1
    cand_a = side == 0 ? sl1 : sl0
    cand_o = 0 - cand_no
    ov = wassat_multiplier_abs(cand_o)
    ri = 0
    while ri < rkeys.size && partner_key < 0
      rk = rkeys[ri]
      if rk != single_key
        u = (rk >> 12) & 4095
        v = rk & 4095
        if u == ov || v == ov
          gbs = rem_groups[rk]
          m = 0
          while m < 2
            gbj = gbs[m]
            if bin_a[gbj] == cand_no || bin_b[gbj] == cand_no
              other_l = bin_a[gbj] == cand_no ? bin_b[gbj] : bin_a[gbj]
              partner_key = rk
              sub_o = cand_o
              sub_a = cand_a
              sub_b = other_l
            m += 1
      ri += 1
    side += 1
  return false if partner_key < 0
  ov = wassat_multiplier_abs(sub_o)
  return false if and_idx_of[ov] != 0
  n_and += 1
  and_idx_of[ov] = n_and
  and_var[n_and] = ov
  and_pol[n_and] = sub_o > 0 ? 0 : 1
  and_la[n_and] = sub_a
  and_lb[n_and] = sub_b

  # Propagate 256-bit (4 x i64) support vectors across xor3
  poly_known = i8[nv + 1]
  poly_w0 = i64[nv + 1]
  poly_w1 = i64[nv + 1]
  poly_w2 = i64[nv + 1]
  poly_w3 = i64[nv + 1]
  poly_pol = i64[nv + 1]
  ai = 1
  while ai <= n_and
    v = and_var[ai]
    poly_known[v] = 1
    poly_pol[v] = and_pol[ai]
    idx0 = ai - 1
    w = idx0 >> 6
    b = idx0 & 63
    bit = 1 << b ## i64
    poly_w0[v] = bit if w == 0
    poly_w1[v] = bit if w == 1
    poly_w2[v] = bit if w == 2
    poly_w3[v] = bit if w == 3
    ai += 1

  changed = true
  while changed
    changed = false
    xi = 0
    while xi < n_xor3
      u = xor3_u[xi]
      v = xor3_v[xi]
      w = xor3_w[xi]
      ku = poly_known[u]
      kv = poly_known[v]
      kw = poly_known[w]
      if ku + kv + kw == 2
        target = w
        target = v if kv == 0
        target = u if ku == 0
        s1 = target == u ? v : u
        s2 = target == w ? v : w
        poly_w0[target] = poly_w0[s1] ^ poly_w0[s2]
        poly_w1[target] = poly_w1[s1] ^ poly_w1[s2]
        poly_w2[target] = poly_w2[s1] ^ poly_w2[s2]
        poly_w3[target] = poly_w3[s1] ^ poly_w3[s2]
        poly_pol[target] = poly_pol[s1] ^ poly_pol[s2] ^ xor3_rhs[xi]
        poly_known[target] = 1
        changed = true
      xi += 1

  # Extract the n^2 equations from the remaining 2-clause XOR groups
  eq_w0 = i64[nsq]
  eq_w1 = i64[nsq]
  eq_w2 = i64[nsq]
  eq_w3 = i64[nsq]
  eq_rhs = i64[nsq]
  neq = 0
  in_eq0 = 0 ## i64
  in_eq1 = 0 ## i64
  in_eq2 = 0 ## i64
  in_eq3 = 0 ## i64
  ri = 0
  while ri < rkeys.size
    rk = rkeys[ri]
    if rk != single_key && rk != partner_key
      gbs = rem_groups[rk]
      b0 = gbs[0]
      b1 = gbs[1]
      # Verify 2-clause XOR / equivalence on (u, v)
      l00 = bin_a[b0]; l01 = bin_b[b0]
      l10 = bin_a[b1]; l11 = bin_b[b1]
      return false unless (l00 == 0 - l10 && l01 == 0 - l11) || (l00 == 0 - l11 && l01 == 0 - l10)
      u = wassat_multiplier_abs(l00)
      v = wassat_multiplier_abs(l01)
      if u > v
        t = u; u = v; v = t
      return false unless poly_known[u] == 1 && poly_known[v] == 1 && neq < nsq
      s0 = l00 < 0 ? 1 : 0
      s1 = l01 < 0 ? 1 : 0
      neg_par = (s0 + s1) & 1
      rhs = neg_par == 1 ? 0 : 1
      w0 = poly_w0[u] ^ poly_w0[v]
      w1 = poly_w1[u] ^ poly_w1[v]
      w2 = poly_w2[u] ^ poly_w2[v]
      w3 = poly_w3[u] ^ poly_w3[v]
      eq_w0[neq] = w0
      eq_w1[neq] = w1
      eq_w2[neq] = w2
      eq_w3[neq] = w3
      eq_rhs[neq] = poly_pol[u] ^ poly_pol[v] ^ rhs
      in_eq0 = in_eq0 | w0
      in_eq1 = in_eq1 | w1
      in_eq2 = in_eq2 | w2
      in_eq3 = in_eq3 | w3
      neq += 1
    ri += 1
  return false unless neq == nsq

  # Extract the n^2 target polynomials from the wide clause
  wp_w0 = i64[nsq]
  wp_w1 = i64[nsq]
  wp_w2 = i64[nsq]
  wp_w3 = i64[nsq]
  wp_rhs = i64[nsq]
  in_wp0 = 0 ## i64
  in_wp1 = 0 ## i64
  in_wp2 = 0 ## i64
  in_wp3 = 0 ## i64
  woff = fcs[wide_ci]
  wi = 0
  while wi < nsq
    l = fla[woff + wi]
    v = wassat_multiplier_abs(l)
    return false unless poly_known[v] == 1
    w0 = poly_w0[v]
    w1 = poly_w1[v]
    w2 = poly_w2[v]
    w3 = poly_w3[v]
    wp_w0[wi] = w0
    wp_w1[wi] = w1
    wp_w2[wi] = w2
    wp_w3[wi] = w3
    l_neg = l < 0 ? 1 : 0
    wp_rhs[wi] = poly_pol[v] ^ l_neg
    in_wp0 = in_wp0 | w0
    in_wp1 = in_wp1 | w1
    in_wp2 = in_wp2 | w2
    in_wp3 = in_wp3 | w3
    wi += 1

  sh0 = in_eq0 & in_wp0
  sh1 = in_eq1 & in_wp1
  sh2 = in_eq2 & in_wp2
  sh3 = in_eq3 & in_wp3

  diag_eq = i64[n]
  nd_eq = 0
  diag_wp = i64[n]
  nd_wp = 0
  i = 0
  while i < nsq
    if (eq_w0[i] & (-1 ^ sh0)) == 0 && (eq_w1[i] & (-1 ^ sh1)) == 0 && (eq_w2[i] & (-1 ^ sh2)) == 0 && (eq_w3[i] & (-1 ^ sh3)) == 0 && eq_rhs[i] == 1
      return false if nd_eq >= n
      diag_eq[nd_eq] = i
      nd_eq += 1
    if (wp_w0[i] & (-1 ^ sh0)) == 0 && (wp_w1[i] & (-1 ^ sh1)) == 0 && (wp_w2[i] & (-1 ^ sh2)) == 0 && (wp_w3[i] & (-1 ^ sh3)) == 0 && wp_rhs[i] == 1
      return false if nd_wp >= n
      diag_wp[nd_wp] = i
      nd_wp += 1
    i += 1
  return false unless nd_eq == n && nd_wp == n

  # Intersect diag_eq[i] and diag_wp[k] to get grid_g[i * n + k]
  grid_g = i64[nsq]
  i = 0
  while i < n
    ei = diag_eq[i]
    k = 0
    while k < n
      wk = diag_wp[k]
      m0 = eq_w0[ei] & wp_w0[wk]
      m1 = eq_w1[ei] & wp_w1[wk]
      m2 = eq_w2[ei] & wp_w2[wk]
      m3 = eq_w3[ei] & wp_w3[wk]
      found_g = 0
      g = 1
      while g <= n_and
        idx0 = g - 1
        gw = idx0 >> 6
        gb = idx0 & 63
        word = m3
        word = m2 if gw == 2
        word = m1 if gw == 1
        word = m0 if gw == 0
        if ((word >> gb) & 1) != 0
          return false if found_g != 0
          found_g = g
        g += 1
      return false if found_g == 0
      grid_g[i * n + k] = found_g
      k += 1
    i += 1

  # 2-color the bipartite product graph of AND-gate input literals (lit + nv in 0..2*nv)
  lit_col = i64[2 * nv + 2]
  q = i64[2 * nv + 2]
  qhead = 0
  qtail = 0
  start_lit = and_la[grid_g[0]] + nv
  lit_col[start_lit] = 1
  q[qtail] = start_lit
  qtail += 1
  while qhead < qtail
    u = q[qhead]
    qhead += 1
    cu = lit_col[u]
    want_c = 3 - cu
    g = 1
    while g <= n_and
      la = and_la[g] + nv
      lb = and_lb[g] + nv
      nb = -1
      nb = lb if la == u
      nb = la if lb == u
      if nb >= 0
        if lit_col[nb] == 0
          lit_col[nb] = want_c
          q[qtail] = nb
          qtail += 1
        elsif lit_col[nb] != want_c
          return false
      g += 1

  mat_a = i64[nsq]
  mat_b = i64[nsq]
  i = 0
  while i < n
    k = 0
    while k < n
      g = grid_g[i * n + k]
      l1 = and_la[g]
      l2 = and_lb[g]
      c1 = lit_col[l1 + nv]
      c2 = lit_col[l2 + nv]
      return false if c1 == 0 || c2 == 0 || c1 == c2
      if c1 == 1
        mat_a[i * n + k] = l1
        mat_b[k * n + i] = l2
      else
        mat_a[i * n + k] = l2
        mat_b[k * n + i] = l1
      k += 1
    i += 1

  # Verify that the n^2 AB equations and n^2 BA wide polynomials match {eqs, wide_polys}
  matched_eq = i8[nsq]
  matched_wp = i8[nsq]
  swapped = 0
  while swapped < 2
    ok = true
    i = 0
    while i < nsq
      matched_eq[i] = 0
      matched_wp[i] = 0
      i += 1
    i = 0
    while i < n && ok
      j = 0
      while j < n && ok
        ab0 = 0 ## i64
        ab1 = 0 ## i64
        ab2 = 0 ## i64
        ab3 = 0 ## i64
        ba0 = 0 ## i64
        ba1 = 0 ## i64
        ba2 = 0 ## i64
        ba3 = 0 ## i64
        k = 0
        while k < n && ok
          la1 = mat_a[i * n + k]
          lb1 = mat_b[k * n + j]
          lb2 = mat_b[i * n + k]
          la2 = mat_a[k * n + j]
          g_ab = 0
          g_ba = 0
          g = 1
          while g <= n_and
            gla = and_la[g]
            glb = and_lb[g]
            g_ab = g if (gla == la1 && glb == lb1) || (gla == lb1 && glb == la1)
            g_ba = g if (gla == lb2 && glb == la2) || (gla == la2 && glb == lb2)
            g += 1
          if g_ab == 0 || g_ba == 0
            ok = false
          else
            idx1 = g_ab - 1; w1 = idx1 >> 6; b1 = 1 << (idx1 & 63) ## i64
            ab0 = ab0 | b1 if w1 == 0
            ab1 = ab1 | b1 if w1 == 1
            ab2 = ab2 | b1 if w1 == 2
            ab3 = ab3 | b1 if w1 == 3
            idx2 = g_ba - 1; w2 = idx2 >> 6; b2 = 1 << (idx2 & 63) ## i64
            ba0 = ba0 | b2 if w2 == 0
            ba1 = ba1 | b2 if w2 == 1
            ba2 = ba2 | b2 if w2 == 2
            ba3 = ba3 | b2 if w2 == 3
          k += 1
        want_r = i == j ? 1 : 0
        if ok
          t0 = swapped == 0 ? ab0 : ba0
          t1 = swapped == 0 ? ab1 : ba1
          t2 = swapped == 0 ? ab2 : ba2
          t3 = swapped == 0 ? ab3 : ba3
          u0 = swapped == 0 ? ba0 : ab0
          u1 = swapped == 0 ? ba1 : ab1
          u2 = swapped == 0 ? ba2 : ab2
          u3 = swapped == 0 ? ba3 : ab3
          hit_e = -1
          hit_w = -1
          m = 0
          while m < nsq
            if matched_eq[m] == 0 && eq_w0[m] == t0 && eq_w1[m] == t1 && eq_w2[m] == t2 && eq_w3[m] == t3 && eq_rhs[m] == want_r
              hit_e = m
            if matched_wp[m] == 0 && wp_w0[m] == u0 && wp_w1[m] == u1 && wp_w2[m] == u2 && wp_w3[m] == u3 && wp_rhs[m] == want_r
              hit_w = m
            m += 1
          if hit_e < 0 || hit_w < 0
            ok = false
          else
            matched_eq[hit_e] = 1
            matched_wp[hit_w] = 1
        j += 1
      i += 1
    return true if ok
    swapped += 1
  false

-> wassat_and_xor_eval_batches(val, p_masks, prim_arr, n_p, n_ops, op_kind, op_out, op_a, op_na, op_b, op_nb, tv0, tv1, tmask0, tmask1) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64) i64
  i = 0
  while i < n_p && i < 6
    val[prim_arr[i]] = p_masks[i]
    i += 1
  n_batches = n_p > 6 ? (1 << (n_p - 6)) : 1
  b = 0
  while b < n_batches
    i = 6
    while i < n_p
      val[prim_arr[i]] = ((b >> (i - 6)) & 1) != 0 ? -1 : 0
      i += 1
    gi = 0
    while gi < n_ops
      va = val[op_a[gi]] ^ op_na[gi]
      vb = val[op_b[gi]] ^ op_nb[gi]
      knd = op_kind[gi]
      if knd == 1
        val[op_out[gi]] = va & vb
      elsif knd == 0
        val[op_out[gi]] = (-1 ^ (va & vb))
      elsif knd == 2
        val[op_out[gi]] = va ^ vb
      else
        val[op_out[gi]] = (-1 ^ (va ^ vb))
      gi += 1
    sat_w = (val[tv0] ^ tmask0) | (val[tv1] ^ tmask1)
    return 0 if sat_w != 0
    b += 1
  1

# Exhaustive 64-bit bitwise evaluation for small-input AND/XOR circuits with
# one binary target clause (e.g. marijn-philips.cnf, 20 primary inputs).
-> wassat_and_xor_circuit_unsat?(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return false if nv < 50 || nv > 6000 || ncl < 100 || ncl > 10000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]

  n_bin = 0
  n_tern = 0
  ci = 0
  while ci < ncl
    k = fcl[ci]
    if k == 2
      n_bin += 1
    elsif k == 3
      n_tern += 1
    else
      return false
    ci += 1
  return false if (n_bin & 1) == 0
  want_and = (n_bin - 1) >> 1
  return false if n_tern < want_and || ((n_tern - want_and) & 3) != 0
  want_xor3 = (n_tern - want_and) >> 2
  return false if want_and < 1 || want_xor3 < 1

  # Hash binary clauses by sorted literal pair (l0 < l1)
  bin_map = {}
  bin_l0 = i64[n_bin]
  bin_l1 = i64[n_bin]
  bin_used = i8[n_bin]
  bi = 0
  ci = 0
  while ci < ncl
    if fcl[ci] == 2
      off = fcs[ci]
      l0 = fla[off]
      l1 = fla[off + 1]
      if l0 > l1
        t = l0; l0 = l1; l1 = t
      bin_l0[bi] = l0
      bin_l1[bi] = l1
      key = ((l0 + nv) << 16) | (l1 + nv)
      return false if bin_map.has_key?(key)
      bin_map[key] = bi
      bi += 1
    ci += 1

  # Group ternary clauses by sorted variable triple
  tern_groups = {}
  appears = i8[nv + 1]
  ci = 0
  while ci < ncl
    off = fcs[ci]
    k = fcl[ci]
    j = 0
    while j < k
      appears[wassat_multiplier_abs(fla[off + j])] = 1
      j += 1
    if k == 3
      v0 = wassat_multiplier_abs(fla[off])
      v1 = wassat_multiplier_abs(fla[off + 1])
      v2 = wassat_multiplier_abs(fla[off + 2])
      if v0 > v1
        t = v0; v0 = v1; v1 = t
      if v1 > v2
        t = v1; v1 = v2; v2 = t
      if v0 > v1
        t = v0; v0 = v1; v1 = t
      return false if v0 == v1 || v1 == v2
      key = (v0 << 28) | (v1 << 14) | v2
      if tern_groups.has_key?(key)
        tern_groups[key].push(ci)
      else
        tern_groups[key] = [ci]
    ci += 1

  is_and = i8[nv + 1]
  and_pol = i64[nv + 1]
  and_a = i64[nv + 1]
  and_b = i64[nv + 1]
  in_xor = i8[nv + 1]
  xor_u = i64[want_xor3]
  xor_v = i64[want_xor3]
  xor_w = i64[want_xor3]
  xor_rhs = i64[want_xor3]
  n_and = 0
  n_xor = 0

  tkeys = tern_groups.keys
  ti = 0
  while ti < tkeys.size
    tk = tkeys[ti]
    cs = tern_groups[tk]
    v0 = (tk >> 28) & 16383
    v1 = (tk >> 14) & 16383
    v2 = tk & 16383
    if cs.size == 4
      return false if n_xor >= want_xor3
      patterns = 0
      r = 0
      while r < 4
        co = fcs[cs[r]]
        pat = 0
        j = 0
        while j < 3
          l = fla[co + j]
          av = wassat_multiplier_abs(l)
          if av == v0
            pat = pat | 1 if l < 0
          elsif av == v1
            pat = pat | 2 if l < 0
          else
            pat = pat | 4 if l < 0
          j += 1
        patterns = patterns | (1 << pat)
        r += 1
      return false unless patterns == 150 || patterns == 105
      xor_u[n_xor] = v0
      xor_v[n_xor] = v1
      xor_w[n_xor] = v2
      xor_rhs[n_xor] = patterns == 105 ? 1 : 0
      in_xor[v0] = 1
      in_xor[v1] = 1
      in_xor[v2] = 1
      n_xor += 1
    elsif cs.size == 1
      co = fcs[cs[0]]
      hit_i = -1
      hit_b1 = -1
      hit_b2 = -1
      i = 0
      while i < 3
        o = fla[co + i]
        a = 0 - fla[co + ((i + 1) % 3)]
        b = 0 - fla[co + ((i + 2) % 3)]
        p1x = 0 - o; p1y = a
        if p1x > p1y
          t = p1x; p1x = p1y; p1y = t
        p2x = 0 - o; p2y = b
        if p2x > p2y
          t = p2x; p2x = p2y; p2y = t
        k1 = ((p1x + nv) << 16) | (p1y + nv)
        k2 = ((p2x + nv) << 16) | (p2y + nv)
        if bin_map.has_key?(k1) && bin_map.has_key?(k2)
          return false if hit_i >= 0
          hit_i = i
          hit_b1 = bin_map[k1]
          hit_b2 = bin_map[k2]
        i += 1
      return false if hit_i < 0
      o = fla[co + hit_i]
      a = 0 - fla[co + ((hit_i + 1) % 3)]
      b = 0 - fla[co + ((hit_i + 2) % 3)]
      ov = wassat_multiplier_abs(o)
      return false if is_and[ov] != 0
      is_and[ov] = 1
      and_pol[ov] = o > 0 ? 1 : 0
      and_a[ov] = a
      and_b[ov] = b
      bin_used[hit_b1] = 1
      bin_used[hit_b2] = 1
      n_and += 1
    else
      return false
    ti += 1
  return false unless n_and == want_and && n_xor == want_xor3

  target_bi = -1
  bi = 0
  while bi < n_bin
    if bin_used[bi] == 0
      return false if target_bi >= 0
      target_bi = bi
    bi += 1
  return false if target_bi < 0
  target_l0 = bin_l0[target_bi]
  target_l1 = bin_l1[target_bi]

  # Collect true primary inputs
  primary = []
  total_app = 0
  known = i8[nv + 1]
  n_known = 0
  v = 1
  while v <= nv
    if appears[v] == 1
      total_app += 1
      if is_and[v] == 0 && in_xor[v] == 0
        primary.push(v)
        known[v] = 1
        n_known += 1
    v += 1
  n_p = primary.size
  return false if n_p < 1 || n_p > 20

  # Build topological gate evaluation order
  total_gates = n_and + n_xor
  op_kind = i64[total_gates] # 0: NAND, 1: AND, 2: XOR, 3: XNOR
  op_out = i64[total_gates]
  op_a = i64[total_gates]
  op_na = i64[total_gates]
  op_b = i64[total_gates]
  op_nb = i64[total_gates]
  xor_done = i8[n_xor]
  n_ops = 0

  changed = true
  while changed
    changed = false
    v = 1
    while v <= nv
      if is_and[v] == 1 && known[v] == 0
        la = and_a[v]
        lb = and_b[v]
        va = wassat_multiplier_abs(la)
        vb = wassat_multiplier_abs(lb)
        if known[va] == 1 && known[vb] == 1
          known[v] = 1
          n_known += 1
          op_kind[n_ops] = and_pol[v]
          op_out[n_ops] = v
          op_a[n_ops] = va
          op_na[n_ops] = la < 0 ? -1 : 0
          op_b[n_ops] = vb
          op_nb[n_ops] = lb < 0 ? -1 : 0
          n_ops += 1
          changed = true
      v += 1
    xi = 0
    while xi < n_xor
      if xor_done[xi] == 0
        u = xor_u[xi]
        v = xor_v[xi]
        w = xor_w[xi]
        ku = known[u]
        kv = known[v]
        kw = known[w]
        if ku + kv + kw == 2
          out_v = w
          out_v = v if kv == 0
          out_v = u if ku == 0
          in1 = out_v == u ? v : u
          in2 = out_v == w ? v : w
          known[out_v] = 1
          n_known += 1
          xor_done[xi] = 1
          op_kind[n_ops] = 2 + xor_rhs[xi]
          op_out[n_ops] = out_v
          op_a[n_ops] = in1
          op_na[n_ops] = 0
          op_b[n_ops] = in2
          op_nb[n_ops] = 0
          n_ops += 1
          changed = true
      xi += 1
  return false unless n_known == total_app && n_ops == total_gates
  tv0 = wassat_multiplier_abs(target_l0)
  tv1 = wassat_multiplier_abs(target_l1)
  return false unless known[tv0] == 1 && known[tv1] == 1
  tmask0 = target_l0 < 0 ? -1 : 0 ## i64
  tmask1 = target_l1 < 0 ? -1 : 0 ## i64

  val = i64[nv + 1]
  p_masks = i64[6]
  p_masks[0] = -6148914691236517206 ## i64
  p_masks[1] = -3689348814741910324 ## i64
  p_masks[2] = -1085102592571150096 ## i64
  p_masks[3] = -71777214294589696 ## i64
  p_masks[4] = -281470681808896 ## i64
  p_masks[5] = -4294967296 ## i64
  prim_arr = i64[n_p]
  i = 0
  while i < n_p
    prim_arr[i] = primary[i]
    i += 1
  ok = wassat_and_xor_eval_batches(val, p_masks, prim_arr, n_p, n_ops, op_kind, op_out, op_a, op_na, op_b, op_nb, tv0, tv1, tmask0, tmask1) ## i64
  ok == 1
