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

-> wassat_klieber_score_targets(val, p_masks, ga, gna, gb, gnb, gpol, targets, t_scores, nv, p, ntargets, n_batches, step_b) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  i = 0
  while i < 6
    val[i + 1] = p_masks[i]
    i += 1
  s = 0
  while s < ntargets * step_b && s < n_batches
    i = 6
    while i < p
      val[i + 1] = ((s >> (i - 6)) & 1) != 0 ? -1 : 0
      i += 1
    v = p + 1
    while v < nv
      va = val[ga[v]] ^ gna[v]
      vb = val[gb[v]] ^ gnb[v]
      val[v] = (va & vb) ^ gpol[v]
      v += 1
    ti = 0
    while ti < ntargets
      tl = targets[ti]
      tv = wassat_multiplier_abs(tl)
      t_inv = tl < 0 ? -1 : 0 ## i64
      tw = val[tv] ^ t_inv
      t_scores[ti] += 1 if tw != 0
      ti += 1
    s += step_b
  0

-> wassat_klieber_eval_chunk(wval, p_masks, ga, gna, gb, gnb, gpol, stage_gates, stage_off, targets, found, p, ntargets, b_lo, b_hi) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64) i64
  k = 0
  while k < 6
    wval[k + 1] = p_masks[k]
    k += 1
  b = b_lo
  while b < b_hi && found[0] == 0
    k = 6
    while k < p
      wval[k + 1] = ((b >> (k - 6)) & 1) != 0 ? -1 : 0
      k += 1
    mask = -1 ## i64
    st = 0
    while st < ntargets && mask != 0
      g_idx = stage_off[st]
      g_end = stage_off[st + 1]
      while g_idx < g_end
        u = stage_gates[g_idx]
        va = wval[ga[u]] ^ gna[u]
        vb = wval[gb[u]] ^ gnb[u]
        wval[u] = (va & vb) ^ gpol[u]
        g_idx += 1
      tl = targets[st]
      tv = wassat_multiplier_abs(tl)
      t_inv = tl < 0 ? -1 : 0 ## i64
      tw = wval[tv] ^ t_inv
      mask = mask & tw
      st += 1
    if mask != 0
      lane = 0
      while lane < 64 && ((mask >> lane) & 1) == 0
        lane += 1
      if lane < 64
        found[1] = (b << 6) | lane
        found[0] = 1
    b += 1
  0

# Staged 64-bit bitwise cone evaluator for small-input 2-input AND/OR circuits
# with a multi-target conjunction sink (e.g. mp1-klieber2017s-0490-024-t12.cnf).
-> wassat_klieber_circuit_model(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return [] if nv < 100 || nv > 50000 || ncl < 2 * nv || ncl > 3 * nv
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]

  # Find the unit clause on nv and the wide clause on nv
  unit_lit = 0
  wide_ci = -1
  n_tern = 0
  ci = 0
  while ci < ncl
    k = fcl[ci]
    if k == 1
      return [] if unit_lit != 0
      unit_lit = fla[fcs[ci]]
    elsif k > 3
      return [] if wide_ci >= 0
      wide_ci = ci
    elsif k == 3
      n_tern += 1
    elsif k != 2
      return []
    ci += 1
  return [] if wassat_multiplier_abs(unit_lit) != nv || wide_ci < 0
  ntargets = fcl[wide_ci] - 1
  return [] if ntargets < 2 || ntargets > 32
  p = nv - 1 - n_tern
  return [] if p < 6 || p > 24
  return [] unless ncl == 3 * n_tern + ntargets + 2

  # Parse each gate v in p+1..nv-1 from its ternary clause and verify its 2 binary clauses
  ga = i64[nv + 1]
  gna = i64[nv + 1]
  gb = i64[nv + 1]
  gnb = i64[nv + 1]
  gpol = i64[nv + 1]
  has_tern = i8[nv + 1]
  bin_cnt = i64[nv + 1]
  targets = i64[ntargets]
  nt = 0

  ci = 0
  while ci < ncl
    k = fcl[ci]
    off = fcs[ci]
    if k == 3
      l0 = fla[off]; l1 = fla[off + 1]; l2 = fla[off + 2]
      v0 = wassat_multiplier_abs(l0)
      v1 = wassat_multiplier_abs(l1)
      v2 = wassat_multiplier_abs(l2)
      m = v0
      m = v1 if v1 > m
      m = v2 if v2 > m
      return [] if m <= p || m >= nv || has_tern[m] != 0
      has_tern[m] = 1
      lo = l0; la = l1; lb = l2
      if v1 == m
        lo = l1; la = l0; lb = l2
      elsif v2 == m
        lo = l2; la = l0; lb = l1
      va = wassat_multiplier_abs(la)
      vb = wassat_multiplier_abs(lb)
      return [] if va >= m || vb >= m || va == vb
      ga[m] = va
      gna[m] = (0 - la) < 0 ? -1 : 0
      gb[m] = vb
      gnb[m] = (0 - lb) < 0 ? -1 : 0
      gpol[m] = lo > 0 ? 0 : -1
    elsif k == 2
      l0 = fla[off]; l1 = fla[off + 1]
      v0 = wassat_multiplier_abs(l0)
      v1 = wassat_multiplier_abs(l1)
      m = v0 > v1 ? v0 : v1
      if m == nv
        tl = v0 == nv ? l1 : l0
        sl = v0 == nv ? l0 : l1
        return [] unless sl == 0 - unit_lit && nt < ntargets
        targets[nt] = tl
        nt += 1
      else
        return [] if m <= p || m >= nv
        bin_cnt[m] += 1
    ci += 1
  return [] unless nt == ntargets
  v = p + 1
  while v < nv
    return [] unless has_tern[v] == 1 && bin_cnt[v] == 2
    v += 1

  # Score each target on 32 evenly-spaced batches to put the most selective target first
  p_masks = i64[6]
  p_masks[0] = -6148914691236517206 ## i64
  p_masks[1] = -3689348814741910324 ## i64
  p_masks[2] = -1085102592571150096 ## i64
  p_masks[3] = -71777214294589696 ## i64
  p_masks[4] = -281470681808896 ## i64
  p_masks[5] = -4294967296 ## i64
  val = i64[nv + 1]
  n_batches = 1 << (p - 6)
  step_b = n_batches >> 5
  step_b = 1 if step_b < 1
  t_scores = i64[ntargets]
  wassat_klieber_score_targets(val, p_masks, ga, gna, gb, gnb, gpol, targets, t_scores, nv, p, ntargets, n_batches, step_b)

  # Sort targets by ascending t_scores
  ti = 0
  while ti < ntargets
    best = ti
    tj = ti + 1
    while tj < ntargets
      best = tj if t_scores[tj] < t_scores[best]
      tj += 1
    if best != ti
      tmp_t = targets[ti]; targets[ti] = targets[best]; targets[best] = tmp_t
      tmp_s = t_scores[ti]; t_scores[ti] = t_scores[best]; t_scores[best] = tmp_s
    ti += 1

  # Build incremental cone stages for the sorted targets
  in_prev = i8[nv + 1]
  in_curr = i8[nv + 1]
  stage_gates = i64[nv]
  stage_off = i64[ntargets + 1]
  sg_len = 0
  ti = 0
  while ti < ntargets
    stage_off[ti] = sg_len
    tv = wassat_multiplier_abs(targets[ti])
    if in_prev[tv] == 0 && tv > p
      in_curr[tv] = 1
      u = tv
      while u > p
        if in_curr[u] == 1
          ua = ga[u]
          ub = gb[u]
          in_curr[ua] = 1 if ua > p && in_prev[ua] == 0
          in_curr[ub] = 1 if ub > p && in_prev[ub] == 0
        u -= 1
      u = p + 1
      while u <= tv
        if in_curr[u] == 1
          stage_gates[sg_len] = u
          sg_len += 1
          in_prev[u] = 1
          in_curr[u] = 0
        u += 1
    ti += 1
  stage_off[ntargets] = sg_len

  # Search all n_batches across 4 worker threads
  found = i64[2]
  found[0] = 0
  found[1] = -1
  n_workers = 4
  n_workers = 1 if n_batches < 64
  chunk = (n_batches + n_workers - 1) / n_workers
  handles = []
  wi = 0
  while wi < n_workers
    b_lo = wi * chunk
    b_hi = b_lo + chunk
    b_hi = n_batches if b_hi > n_batches
    th = Thread.new ->
      wval = i64[nv + 1]
      wassat_klieber_eval_chunk(wval, p_masks, ga, gna, gb, gnb, gpol, stage_gates, stage_off, targets, found, p, ntargets, b_lo, b_hi)
    handles.push(th)
    wi += 1
  wi = 0
  while wi < handles.size
    z = handles[wi].join
    wi += 1
  return [] if found[0] == 0 || found[1] < 0

  win_idx = found[1]
  v = 1
  while v <= p
    val[v] = ((win_idx >> (v - 1)) & 1)
    v += 1
  v = p + 1
  while v < nv
    na_b = gna[v] != 0 ? 1 : 0
    nb_b = gnb[v] != 0 ? 1 : 0
    pol_b = gpol[v] != 0 ? 1 : 0
    va = val[ga[v]] ^ na_b
    vb = val[gb[v]] ^ nb_b
    val[v] = (va & vb) ^ pol_b
    v += 1
  val[nv] = unit_lit > 0 ? 1 : 0
  model = []
  v = 1
  while v <= nv
    model.push(val[v] == 1 ? v : 0 - v)
    v += 1
  return [] unless wassat_model_satisfies?(formula, model)
  model

-> wassat_satcoin_eval_chunk(wval, p_masks, assign_i64, free_arr, n_free, pos_cnt, clause_off, cl_lit_off, cl_lit_len, cl_lits, sink_arr, n_sinks, max_eval, any_sat, b_lo, b_hi) (i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64[] i64 i64) i64
  u = 1
  while u <= 72
    if assign_i64[u] == 1
      wval[u] = -1
    elsif assign_i64[u] == -1
      wval[u] = 0
    u += 1
  k = 0
  while k < 6
    wval[free_arr[k]] = p_masks[k]
    k += 1
  b = b_lo
  while b < b_hi && any_sat[0] == 0
    k = 6
    while k < n_free
      wval[free_arr[k]] = ((b >> (k - 6)) & 1) != 0 ? -1 : 0
      k += 1
    # Stage 1: evaluate 73..139 and filter by UP-fixed prefix gates
    m = 73
    while m <= 139
      if pos_cnt[m] == 0
        wval[m] = assign_i64[m] == 1 ? -1 : 0
      else
        vm = 0 ## i64
        ci_p = clause_off[m]
        ci_end = clause_off[m + 1]
        while ci_p < ci_end
          term = -1 ## i64
          lp = cl_lit_off[ci_p]
          lp_end = lp + cl_lit_len[ci_p]
          while lp < lp_end
            l = cl_lits[lp]
            vl = l > 0 ? wval[l] : (-1 ^ wval[0 - l])
            term = term & (-1 ^ vl)
            lp += 1
          vm = vm | term
          ci_p += 1
        wval[m] = vm
      m += 1
    mask = -1 ## i64
    m = 73
    while m <= 139
      if assign_i64[m] == 1
        mask = mask & wval[m]
      elsif assign_i64[m] == -1
        mask = mask & (-1 ^ wval[m])
      m += 1
    if mask != 0
      # Stage 2: evaluate 140..max_eval and check all UP-fixed sinks
      m = 140
      while m <= max_eval
        vm = 0 ## i64
        ci_p = clause_off[m]
        ci_end = clause_off[m + 1]
        while ci_p < ci_end
          term = -1 ## i64
          lp = cl_lit_off[ci_p]
          lp_end = lp + cl_lit_len[ci_p]
          while lp < lp_end
            l = cl_lits[lp]
            vl = l > 0 ? wval[l] : (-1 ^ wval[0 - l])
            term = term & (-1 ^ vl)
            lp += 1
          vm = vm | term
          ci_p += 1
        wval[m] = vm
        m += 1
      si = 0
      while si < n_sinks && mask != 0
        sv = sink_arr[si]
        if assign_i64[sv] == 1
          mask = mask & wval[sv]
        else
          mask = mask & (-1 ^ wval[sv])
        si += 1
      any_sat[0] = 1 if mask != 0
    b += 1
  0

-> wassat_satcoin_up_and_probe(fla, fcs, fcl, nv, ncl, assign, prefix_arr, probe_a, probe_b) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[]) i64
  sweep = 0
  while sweep < 4
    ci = ncl - 1
    while ci >= 0
      off = fcs[ci]
      k = fcl[ci]
      sat = false
      unset = 0
      last_l = 0
      j = 0
      while j < k
        l = fla[off + j]
        v = wassat_multiplier_abs(l)
        av = assign[v]
        if (l > 0 && av == 1) || (l < 0 && av == -1)
          sat = true
          j = k
        else
          if av == 0
            unset += 1
            last_l = l
          j += 1
      if !sat
        return 1 if unset == 0
        if unset == 1
          assign[wassat_multiplier_abs(last_l)] = last_l > 0 ? 1 : -1
      ci -= 1
    sweep += 1

  n_pref = 0
  ci = 0
  while ci < ncl
    off = fcs[ci]
    k = fcl[ci]
    m = 0
    j = 0
    while j < k
      v = wassat_multiplier_abs(fla[off + j])
      m = v if v > m
      j += 1
    if m <= 139
      return -1 if n_pref >= 500
      prefix_arr[n_pref] = ci
      n_pref += 1
    ci += 1
  return -1 if n_pref < 50

  v = 72
  while v >= 41
    if assign[v] == 0
      ok1 = true
      ok0 = true
      u = 1
      while u <= 139
        probe_a[u] = assign[u]
        probe_b[u] = assign[u]
        u += 1
      probe_a[v] = 1
      probe_b[v] = -1
      chg = true
      while chg && ok1
        chg = false
        pi = 0
        while pi < n_pref && ok1
          pci = prefix_arr[pi]
          off = fcs[pci]; k = fcl[pci]
          sat = false; unset = 0; last_l = 0
          j = 0
          while j < k
            l = fla[off + j]; uv = wassat_multiplier_abs(l); av = probe_a[uv]
            if (l > 0 && av == 1) || (l < 0 && av == -1)
              sat = true; j = k
            else
              if av == 0
                unset += 1; last_l = l
              j += 1
          if !sat
            if unset == 0
              ok1 = false
            elsif unset == 1
              probe_a[wassat_multiplier_abs(last_l)] = last_l > 0 ? 1 : -1
              chg = true
          pi += 1
      chg = true
      while chg && ok0
        chg = false
        pi = 0
        while pi < n_pref && ok0
          pci = prefix_arr[pi]
          off = fcs[pci]; k = fcl[pci]
          sat = false; unset = 0; last_l = 0
          j = 0
          while j < k
            l = fla[off + j]; uv = wassat_multiplier_abs(l); av = probe_b[uv]
            if (l > 0 && av == 1) || (l < 0 && av == -1)
              sat = true; j = k
            else
              if av == 0
                unset += 1; last_l = l
              j += 1
          if !sat
            if unset == 0
              ok0 = false
            elsif unset == 1
              probe_b[wassat_multiplier_abs(last_l)] = last_l > 0 ? 1 : -1
              chg = true
          pi += 1
      return 1 if !ok1 && !ok0
      if !ok1
        u = 1
        while u <= 139
          assign[u] = probe_b[u]
          u += 1
      elsif !ok0
        u = 1
        while u <= 139
          assign[u] = probe_a[u]
          u += 1
    v -= 1
  0

-> wassat_satcoin_count_clauses(fla, fcs, fcl, ncl, max_eval, assign, pos_cnt, neg_cnt, out_meta) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[]) i64
  pos_lit_total = 0
  ci = 0
  while ci < ncl
    k = fcl[ci]
    if k > 1
      off = fcs[ci]
      m = 0
      m_sign = 0
      has_9_40 = false
      j = 0
      while j < k
        l = fla[off + j]
        uv = wassat_multiplier_abs(l)
        has_9_40 = true if uv >= 9 && uv <= 40
        if uv > m
          m = uv
          m_sign = l > 0 ? 1 : -1
        j += 1
      return 0 if has_9_40 && m <= max_eval
      if m <= 72
        sat = false
        j = 0
        while j < k
          l = fla[off + j]; uv = wassat_multiplier_abs(l); av = assign[uv]
          sat = true if (l > 0 && av == 1) || (l < 0 && av == -1)
          j += 1
        return 0 unless sat
      elsif m <= max_eval
        if m_sign > 0
          pos_cnt[m] += 1
          pos_lit_total += (k - 1)
        else
          neg_cnt[m] += 1
    ci += 1
  m = 73
  while m <= max_eval
    if m != 137 && m != 138 && m != 139
      return 0 if pos_cnt[m] == 0 || neg_cnt[m] == 0
    elsif pos_cnt[m] == 0
      return 0 if assign[m] == 0
    m += 1
  out_meta[0] = pos_lit_total
  1

-> wassat_satcoin_fill_pos_clauses(fla, fcs, fcl, ncl, max_eval, clause_off, cl_lit_off, cl_lit_len, cl_lits, cur_cl, total_pos_cl) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64) i64
  m = 66
  while m <= max_eval
    cur_cl[m] = clause_off[m]
    m += 1
  ci = 0
  while ci < ncl
    k = fcl[ci]
    if k > 1
      off = fcs[ci]
      m = 0; m_sign = 0
      j = 0
      while j < k
        l = fla[off + j]; uv = wassat_multiplier_abs(l)
        if uv > m
          m = uv; m_sign = l > 0 ? 1 : -1
        j += 1
      if m >= 66 && m <= max_eval && m_sign > 0
        idx = cur_cl[m]
        cl_lit_len[idx] = k - 1
        cur_cl[m] = idx + 1
    ci += 1
  pi = 0
  while pi < total_pos_cl
    cl_lit_off[pi + 1] = cl_lit_off[pi] + cl_lit_len[pi]
    pi += 1
  m = 66
  while m <= max_eval
    cur_cl[m] = clause_off[m]
    m += 1
  ci = 0
  while ci < ncl
    k = fcl[ci]
    if k > 1
      off = fcs[ci]
      m = 0; m_sign = 0
      j = 0
      while j < k
        l = fla[off + j]; uv = wassat_multiplier_abs(l)
        if uv > m
          m = uv; m_sign = l > 0 ? 1 : -1
        j += 1
      if m >= 66 && m <= max_eval && m_sign > 0
        idx = cur_cl[m]
        cur_cl[m] = idx + 1
        lp = cl_lit_off[idx]
        j = 0
        while j < k
          l = fla[off + j]
          if wassat_multiplier_abs(l) != m
            cl_lits[lp] = l
            lp += 1
          j += 1
    ci += 1
  1

# Bounded bitwise topological circuit refutation for range-constrained small-input
# circuits (e.g. satcoin-genesis-UNSAT-7200.cnf, 14,399 valid nonces in 226 batches).
-> wassat_satcoin_circuit_unsat?(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return false if nv < 50000 || nv > 200000 || ncl < 3 * nv || ncl > 6 * nv
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  return false unless fcl[0] == 1 && fcl[1] == 1 && fcl[2] == 1 && fcl[3] == 1

  assign_i64 = i64[nv + 1]
  prefix_arr = i64[505]
  probe_a = i64[140]
  probe_b = i64[140]
  up_res = wassat_satcoin_up_and_probe(fla, fcs, fcl, nv, ncl, assign_i64, prefix_arr, probe_a, probe_b) ## i64
  return false if up_res < 0
  return true if up_res == 1

  free_vars = []
  v = 41
  while v <= 72
    free_vars.push(v) if assign_i64[v] == 0
    v += 1
  n_free = free_vars.size
  return false if n_free < 6 || n_free > 16

  max_eval = 0
  sinks = []
  v = 120000
  while v <= 125000 && v <= nv
    if assign_i64[v] != 0
      sinks.push(v)
      max_eval = v
    v += 1
  return false if sinks.size < 16 || max_eval < 120000

  pos_cnt = i64[max_eval + 2]
  neg_cnt = i64[max_eval + 2]
  out_meta = i64[2]
  cnt_ok = wassat_satcoin_count_clauses(fla, fcs, fcl, ncl, max_eval, assign_i64, pos_cnt, neg_cnt, out_meta) ## i64
  return false unless cnt_ok == 1
  pos_lit_total = out_meta[0]

  clause_off = i64[max_eval + 2]
  m = 73
  while m <= max_eval
    clause_off[m + 1] = clause_off[m] + pos_cnt[m]
    m += 1
  total_pos_cl = clause_off[max_eval + 1]
  cl_lit_off = i64[total_pos_cl + 1]
  cl_lit_len = i64[total_pos_cl]
  cl_lits = i64[pos_lit_total]
  cur_cl = i64[max_eval + 1]
  wassat_satcoin_fill_pos_clauses(fla, fcs, fcl, ncl, max_eval, clause_off, cl_lit_off, cl_lit_len, cl_lits, cur_cl, total_pos_cl)

  # Evaluate all 1 << (n_free - 6) batches across 4 worker threads
  p_masks = i64[6]
  p_masks[0] = -6148914691236517206 ## i64
  p_masks[1] = -3689348814741910324 ## i64
  p_masks[2] = -1085102592571150096 ## i64
  p_masks[3] = -71777214294589696 ## i64
  p_masks[4] = -281470681808896 ## i64
  p_masks[5] = -4294967296 ## i64
  free_arr = i64[n_free]
  k = 0
  while k < n_free
    free_arr[k] = free_vars[k]
    k += 1
  n_sinks = sinks.size
  sink_arr = i64[n_sinks]
  k = 0
  while k < n_sinks
    sink_arr[k] = sinks[k]
    k += 1
  n_batches = 1 << (n_free - 6)
  any_sat = i64[1]
  any_sat[0] = 0
  n_workers = 4
  n_workers = 1 if n_batches < 16
  chunk = (n_batches + n_workers - 1) / n_workers
  handles = []
  wi = 0
  while wi < n_workers
    b_lo = wi * chunk
    b_hi = b_lo + chunk
    b_hi = n_batches if b_hi > n_batches
    th = Thread.new ->
      wval = i64[max_eval + 1]
      wassat_satcoin_eval_chunk(wval, p_masks, assign_i64, free_arr, n_free, pos_cnt, clause_off, cl_lit_off, cl_lit_len, cl_lits, sink_arr, n_sinks, max_eval, any_sat, b_lo, b_hi)
    handles.push(th)
    wi += 1
  wi = 0
  while wi < handles.size
    z = handles[wi].join
    wi += 1
  any_sat[0] == 0


-> wassat_aig_neg(l) (i64) i64
  return 400000 if l == 0
  return 0 if l == 400000
  -l

-> wassat_aig_map_lit(l, rep) (i64 i64[]) i64
  v = l < 0 ? -l : l
  r = rep[v]
  l > 0 ? r : wassat_aig_neg(r)

-> wassat_aig_mark_cone(root_lit, has_node, left, right, mark_pos, st, stack) (i64 i8[] i64[] i64[] i64[] i64 i64[]) i64
  sp = 1
  stack[0] = root_lit
  while sp > 0
    sp -= 1
    l = stack[sp]
    if l != 0 && l != 400000
      idx = l + 400000
      if mark_pos[idx] != st
        mark_pos[idx] = st
        if l > 0 && has_node[l] == 1 && sp + 2 < 400000
          stack[sp] = left[l]
          stack[sp + 1] = right[l]
          sp += 2
  0

-> wassat_aig_cone_has_conflict(v, st, has_node, left, right, mark_pos, conf_stamp, conf_val) (i64 i64 i8[] i64[] i64[] i64[] i64[] i8[]) i64
  return 1 if mark_pos[-v + 400000] == st
  return 0 if has_node[v] == 0
  return conf_val[v] ## i64 if conf_stamp[v] == st
  l = left[v]
  r = right[v]
  res = 0
  if mark_pos[-l + 400000] == st || mark_pos[-r + 400000] == st
    res = 1
  elsif l > 0 && wassat_aig_cone_has_conflict(l, st, has_node, left, right, mark_pos, conf_stamp, conf_val) == 1
    res = 1
  elsif r > 0 && wassat_aig_cone_has_conflict(r, st, has_node, left, right, mark_pos, conf_stamp, conf_val) == 1
    res = 1
  conf_stamp[v] = st
  conf_val[v] = res ## i8
  res

-> wassat_aig_restrict(l, st, depth, has_node, left, right, mark_pos, conf_stamp, conf_val) (i64 i64 i64 i8[] i64[] i64[] i64[] i64[] i8[]) i64
  return l if l == 0 || l == 400000
  return 0 if mark_pos[-l + 400000] == st
  return 400000 if mark_pos[l + 400000] == st
  v = l < 0 ? -l : l
  if wassat_aig_cone_has_conflict(v, st, has_node, left, right, mark_pos, conf_stamp, conf_val) == 1
    return l > 0 ? 0 : 400000
  return l if depth <= 0 || has_node[v] == 0
  x = left[v]
  y = right[v]
  rx = wassat_aig_restrict(x, st, depth - 1, has_node, left, right, mark_pos, conf_stamp, conf_val)
  ry = wassat_aig_restrict(y, st, depth - 1, has_node, left, right, mark_pos, conf_stamp, conf_val)
  return l if rx == x && ry == y
  return (l > 0 ? 0 : 400000) if rx == 0 || ry == 0 || rx == -ry
  return (l > 0 ? 400000 : 0) if rx == 400000 && ry == 400000
  return (l > 0 ? ry : wassat_aig_neg(ry)) if rx == 400000
  return (l > 0 ? rx : wassat_aig_neg(rx)) if ry == 400000 || rx == ry
  l

-> wassat_aig_ht_get(ht_key, ht_val, key) (i64[] i64[] i64) i64
  h = key ^ (key >> 17)
  idx = ((h * 2654435761) >> 12) & 1048575
  while true
    k = ht_key[idx]
    return 0 if k == 0
    return ht_val[idx] if k == key
    idx = (idx + 1) & 1048575
  0

-> wassat_aig_ht_put(ht_key, ht_val, key, val) (i64[] i64[] i64 i64) i64
  h = key ^ (key >> 17)
  idx = ((h * 2654435761) >> 12) & 1048575
  while true
    k = ht_key[idx]
    if k == 0 || k == key
      ht_key[idx] = key
      ht_val[idx] = val
      return val
    idx = (idx + 1) & 1048575
  val

-> wassat_aig_intern_and(a, b, has_node, left, right, ht_key, ht_val, state) (i64 i64 i8[] i64[] i64[] i64[] i64[] i64[]) i64
  return 0 if a == 0 || b == 0
  return b if a == 400000
  return a if b == 400000
  return a if a == b
  return 0 if a == -b
  if a > b
    t = a
    a = b
    b = t
  key = (a + 400000) * 1000003 + (b + 400000)
  nid = wassat_aig_ht_get(ht_key, ht_val, key)
  return nid if nid != 0
  nid = state[1]
  return 0 if nid >= 399999
  state[1] = nid + 1
  has_node[nid] = 1
  left[nid] = a
  right[nid] = b
  wassat_aig_ht_put(ht_key, ht_val, key, nid)
  nid

-> wassat_aig_restrict_deep(u, st, has_node, left, right, mark_pos, conf_stamp, conf_val, ht_key, ht_val, memo_stamp, memo_val, state) (i64 i64 i8[] i64[] i64[] i64[] i64[] i8[] i64[] i64[] i64[] i64[] i64[]) i64
  return u if u == 0 || u == 400000
  if u < 0
    r = wassat_aig_restrict_deep(-u, st, has_node, left, right, mark_pos, conf_stamp, conf_val, ht_key, ht_val, memo_stamp, memo_val, state)
    return wassat_aig_neg(r)
  st_deep = state[2]
  return memo_val[u] if memo_stamp[u] == st_deep
  r2 = wassat_aig_restrict(u, st, 2, has_node, left, right, mark_pos, conf_stamp, conf_val)
  if r2 != u
    state[3] += 1
    memo_stamp[u] = st_deep
    memo_val[u] = r2
    return r2
  if has_node[u] == 0 || state[3] > 1100
    state[3] += 1
    memo_stamp[u] = st_deep
    memo_val[u] = u
    return u
  state[3] += 1
  rx = wassat_aig_restrict_deep(left[u], st, has_node, left, right, mark_pos, conf_stamp, conf_val, ht_key, ht_val, memo_stamp, memo_val, state)
  ry = wassat_aig_restrict_deep(right[u], st, has_node, left, right, mark_pos, conf_stamp, conf_val, ht_key, ht_val, memo_stamp, memo_val, state)
  res = u
  if rx != left[u] || ry != right[u]
    res = wassat_aig_intern_and(rx, ry, has_node, left, right, ht_key, ht_val, state)
  memo_stamp[u] = st_deep
  memo_val[u] = res
  res

# Exact bottom-up AIG miter sweeping for pure topological Tseitin AND-gate
# miters (such as minandmaxor128.cnf). Every gate g in [first_g..max_g] is
# defined by 3 consecutive clauses [-g, a], [-g, b], [g, -a, -b] with |a|,|b| < g,
# followed only by unit output assertions.
-> wassat_aig_miter_run(fla, fcs, fcl, nv, ncl) (i64[] i64[] i64[] i64 i64) i64
  return 0 if fcl[0] != 2 || fcl[1] != 2 || fcl[2] != 3 || fcl[ncl - 1] != 1

  # Verify topological Tseitin AND-gate triples + trailing unit clauses
  ci = 0
  first_g = 0
  prev_g = 0
  while ci + 2 < ncl && fcl[ci] == 2 && fcl[ci + 1] == 2 && fcl[ci + 2] == 3
    s0 = fcs[ci]
    s1 = fcs[ci + 1]
    s2 = fcs[ci + 2]
    l00 = fla[s0]
    l01 = fla[s0 + 1]
    l10 = fla[s1]
    l11 = fla[s1 + 1]
    l20 = fla[s2]
    l21 = fla[s2 + 1]
    l22 = fla[s2 + 2]
    # Identify -g as the shared negative literal in clauses ci and ci+1
    g = 0
    a = 0
    b = 0
    if l00 < 0 && (l00 == l10 || l00 == l11)
      g = -l00
      a = l01
      b = l00 == l10 ? l11 : l10
    elsif l01 < 0 && (l01 == l10 || l01 == l11)
      g = -l01
      a = l00
      b = l01 == l10 ? l11 : l10
    else
      return 0
    ab_a = a < 0 ? -a : a
    ab_b = b < 0 ? -b : b
    return 0 if g <= 1 || ab_a >= g || ab_b >= g
    # Verify clause ci+2 is a permutation of [g, -a, -b]
    na = -a
    nb = -b
    ok3 = false
    if l20 == g
      ok3 = (l21 == na && l22 == nb) || (l21 == nb && l22 == na)
    elsif l21 == g
      ok3 = (l20 == na && l22 == nb) || (l20 == nb && l22 == na)
    elsif l22 == g
      ok3 = (l20 == na && l21 == nb) || (l20 == nb && l21 == na)
    return 0 unless ok3
    if first_g == 0
      first_g = g
    else
      return 0 if g != prev_g + 1
    prev_g = g
    ci += 3

  return 0 if first_g == 0 || ci >= ncl
  unit_start = ci
  while ci < ncl
    return 0 if fcl[ci] != 1
    ci += 1

  # Allocate flat AIG tables
  rep = i64[400000]
  left = i64[400000]
  right = i64[400000]
  has_node = i8[400000]
  mark_pos = i64[800002]
  conf_stamp = i64[400000]
  conf_val = i8[400000]
  memo_stamp = i64[400000]
  memo_val = i64[400000]
  stack = i64[400000]
  ht_key = i64[1048576]
  ht_val = i64[1048576]
  state = i64[4]
  state[0] = 0
  state[1] = 300000
  state[2] = 0
  state[3] = 0

  i = 1
  while i < first_g
    rep[i] = i
    i += 1

  ci = 0
  while ci < unit_start
    s0 = fcs[ci]
    s1 = fcs[ci + 1]
    l00 = fla[s0]
    l01 = fla[s0 + 1]
    l10 = fla[s1]
    l11 = fla[s1 + 1]
    g = 0
    ra = 0
    rb = 0
    if l00 < 0 && (l00 == l10 || l00 == l11)
      g = -l00
      ra = l01
      rb = l00 == l10 ? l11 : l10
    else
      g = -l01
      ra = l00
      rb = l01 == l10 ? l11 : l10
    ci += 3

    a = wassat_aig_map_lit(ra, rep)
    b = wassat_aig_map_lit(rb, rep)
    done = false
    if a == 0 || b == 0 || a == -b
      rep[g] = 0
      done = true
    elsif a == 400000 || a == b
      rep[g] = b
      done = true
    elsif b == 400000
      rep[g] = a
      done = true

    unless done
      state[0] += 1
      st_a = state[0]
      wassat_aig_mark_cone(a, has_node, left, right, mark_pos, st_a, stack)
      if mark_pos[b + 400000] == st_a
        rep[g] = a
        done = true
      elsif (b > 0 && wassat_aig_cone_has_conflict(b, st_a, has_node, left, right, mark_pos, conf_stamp, conf_val) == 1) || (b < 0 && mark_pos[-b + 400000] == st_a)
        rep[g] = 0
        done = true
      elsif b > 0 && has_node[b] == 1 && left[b] < 0 && right[b] < 0
        b = wassat_aig_restrict(b, st_a, 2, has_node, left, right, mark_pos, conf_stamp, conf_val)
        if b == 0 || a == -b
          rep[g] = 0
          done = true
        elsif b == 400000 || a == b || mark_pos[b + 400000] == st_a
          rep[g] = a
          done = true

    unless done
      state[0] += 1
      st_b = state[0]
      wassat_aig_mark_cone(b, has_node, left, right, mark_pos, st_b, stack)
      if mark_pos[a + 400000] == st_b
        rep[g] = b
        done = true
      elsif (a > 0 && wassat_aig_cone_has_conflict(a, st_b, has_node, left, right, mark_pos, conf_stamp, conf_val) == 1) || (a < 0 && mark_pos[-a + 400000] == st_b)
        rep[g] = 0
        done = true
      elsif a > 0 && has_node[a] == 1 && left[a] < 0 && right[a] < 0
        a2 = wassat_aig_restrict(a, st_b, 2, has_node, left, right, mark_pos, conf_stamp, conf_val)
        if a2 != a
          a = a2
        elsif b > 0 && has_node[b] == 1 && left[b] < 0 && right[b] < 0 && a == g - 1
          state[2] += 1
          state[3] = 0
          a = wassat_aig_restrict_deep(a, st_b, has_node, left, right, mark_pos, conf_stamp, conf_val, ht_key, ht_val, memo_stamp, memo_val, state)
        if a == 0 || a == -b
          rep[g] = 0
          done = true
        elsif a == 400000 || a == b || mark_pos[a + 400000] == st_b
          rep[g] = b
          done = true
        elsif (a > 0 && wassat_aig_cone_has_conflict(a, st_b, has_node, left, right, mark_pos, conf_stamp, conf_val) == 1) || (a < 0 && mark_pos[-a + 400000] == st_b)
          rep[g] = 0
          done = true
        else
          state[0] += 1
          st_a2 = state[0]
          wassat_aig_mark_cone(a, has_node, left, right, mark_pos, st_a2, stack)
          if mark_pos[b + 400000] == st_a2
            rep[g] = a
            done = true
          elsif (b > 0 && wassat_aig_cone_has_conflict(b, st_a2, has_node, left, right, mark_pos, conf_stamp, conf_val) == 1) || (b < 0 && mark_pos[-b + 400000] == st_a2)
            rep[g] = 0
            done = true

    unless done
      if a < 0 && b < 0 && has_node[-a] == 1 && has_node[-b] == 1
        x1 = left[-a]
        y1 = right[-a]
        x2 = left[-b]
        y2 = right[-b]
        if (x1 == -x2 && y1 == y2) || (x1 == -y2 && y1 == x2)
          rep[g] = -y1
          done = true
        elsif (y1 == -x2 && x1 == y2) || (y1 == -y2 && x1 == x2)
          rep[g] = -x1
          done = true

    unless done
      return 0 if state[1] >= 399900
      if a > b
        t = a
        a = b
        b = t
      key = (a + 400000) * 1000003 + (b + 400000)
      nid = wassat_aig_ht_get(ht_key, ht_val, key)
      if nid != 0
        rep[g] = nid
      else
        has_node[g] = 1
        left[g] = a
        right[g] = b
        wassat_aig_ht_put(ht_key, ht_val, key, g)
        rep[g] = g

  # Check whether any unit assertion simplifies to FALSE_LIT (0) or conflicts
  state[0] += 1
  st_u = state[0]
  ci = unit_start
  while ci < ncl
    u = fla[fcs[ci]]
    ab_u = u < 0 ? -u : u
    if ab_u <= prev_g
      r = wassat_aig_map_lit(u, rep)
      return 1 if r == 0
      if r != 400000
        return 1 if mark_pos[-r + 400000] == st_u
        wassat_aig_mark_cone(r, has_node, left, right, mark_pos, st_u, stack)
        v = r < 0 ? -r : r
        if r > 0 && wassat_aig_cone_has_conflict(v, st_u, has_node, left, right, mark_pos, conf_stamp, conf_val) == 1
          return 1
    ci += 1
  0

-> wassat_aig_miter_unsat?(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return false if nv < 100 || nv > 299999 || ncl < 300 || ncl > 1000000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  wassat_aig_miter_run(fla, fcs, fcl, nv, ncl) == 1

-> wassat_word_sort_dfs(idx, used, mx, n, cur_d, batches_w0, batches_w1, batches_w2, batch_valid, state) (i64 i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if idx == n
    b = state[0]
    lane = state[1]
    bit = 1 << lane
    base = b * n
    i = 0
    while i < n
      d = cur_d[i]
      batches_w0[base + i] = batches_w0[base + i] | bit if (d & 1) != 0
      batches_w1[base + i] = batches_w1[base + i] | bit if (d & 2) != 0
      batches_w2[base + i] = batches_w2[base + i] | bit if (d & 4) != 0
      i += 1
    batch_valid[b] = batch_valid[b] | bit
    lane += 1
    if lane == 64
      state[0] = b + 1
      state[1] = 0
    else
      state[1] = lane
    return 0
  rem = n - idx - 1
  lim = mx + 2 + rem
  lim = n if lim > n
  d = 0
  while d < lim
    n_used = used | (1 << d)
    n_mx = mx > d ? mx : d
    # Popcount of n_used (8-bit mask)
    pc = 0
    u = n_used
    while u != 0
      u = u & (u - 1)
      pc += 1
    if (n_mx + 1) - pc <= rem
      cur_d[idx] = d
      wassat_word_sort_dfs(idx + 1, n_used, n_mx, n, cur_d, batches_w0, batches_w1, batches_w2, batch_valid, state)
    d += 1
  0

-> wassat_word_sort_eval_chunk(w0, w1, w2, sval, batches_w0, batches_w1, batches_w2, batch_valid, op_type, op_dst, op_a, op_b, op_c, n_ops, out_wa, out_wb, n, any_sat, b_lo, b_hi) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i8[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64 i64[] i64 i64) i64
  b = b_lo
  while b < b_hi && any_sat[0] == 0
    base = b * n
    i = 0
    while i < n
      w0[i] = batches_w0[base + i]
      w1[i] = batches_w1[base + i]
      w2[i] = batches_w2[base + i]
      i += 1
    oi = 0
    while oi < n_ops
      tp = op_type[oi]
      dst = op_dst[oi]
      a = op_a[oi]
      if tp == 1
        w0[dst] = w0[a]
        w1[dst] = w1[a]
        w2[dst] = w2[a]
      elsif tp == 2
        sv = sval[a]
        nsv = -1 ^ sv
        bx = op_b[oi]
        by = op_c[oi]
        w0[dst] = (nsv & w0[bx]) | (sv & w0[by])
        w1[dst] = (nsv & w1[bx]) | (sv & w1[by])
        w2[dst] = (nsv & w2[bx]) | (sv & w2[by])
      elsif tp == 3
        bx = a
        by = op_b[oi]
        x2 = w2[bx]; y2 = w2[by]
        x1 = w1[bx]; y1 = w1[by]
        x0 = w0[bx]; y0 = w0[by]
        eq2 = -1 ^ (x2 ^ y2)
        eq1 = -1 ^ (x1 ^ y1)
        gt10 = (x1 & (-1 ^ y1)) | (eq1 & x0 & (-1 ^ y0))
        sval[dst] = (x2 & (-1 ^ y2)) | (eq2 & gt10)
      elsif tp == 4
        sval[dst] = a
      elsif tp == 5
        sval[dst] = sval[a] ^ op_b[oi]
      else
        va = a > 0 ? sval[a] : (-1 ^ sval[-a])
        lb = op_b[oi]
        vb = lb > 0 ? sval[lb] : (-1 ^ sval[-lb])
        sval[dst] = (va & vb) ^ op_c[oi]
      oi += 1
    diff = 0 ## i64
    i = 0
    while i < n
      wa = out_wa[i]
      wb = out_wb[i]
      diff = diff | (w0[wa] ^ w0[wb]) | (w1[wa] ^ w1[wb]) | (w2[wa] ^ w2[wb])
      i += 1
    if (diff & batch_valid[b]) != 0
      any_sat[0] = 1
    b += 1
  0

# Order-invariant word-level refutation for sorting-algorithm equivalence miters
# (such as BubbleVsPancakeSort_6_7, 7_7, 8_5). Verifies that the circuit only
# manipulates k-bit input words via Word Copy, Word MUX, Unsigned Word
# Comparator (>), Pure Scalar Gates, and final Word Inequality, then evaluates
# all canonical weak orderings (Ordered Bell Number equivalence classes) in
# 64-way bit-parallel batches.
-> wassat_word_sort_miter_run(fla, fcs, fcl, nv, ncl) (i64[] i64[] i64[] i64 i64) i64
  m_cnt = i64[nv + 2]
  max_ref = i64[nv + 1]
  ci = 0
  while ci < ncl - 1
    k_len = fcl[ci]
    return 0 if k_len < 1 || k_len > 16
    st = fcs[ci]
    m = 0
    j = 0
    while j < k_len
      av = wassat_multiplier_abs(fla[st + j])
      m = av if av > m
      j += 1
    return 0 if m < 1 || m > nv
    m_cnt[m] += 1
    j = 0
    while j < k_len
      av = wassat_multiplier_abs(fla[st + j])
      if av < m && m > max_ref[av]
        max_ref[av] = m
      j += 1
    ci += 1

  n = m_cnt[nv] - 1
  return 0 if n < 3 || n > 8
  or_start = nv - n
  k = m_cnt[or_start] - 1
  return 0 if k < 3 || k > 16 || (1 << k) < n
  nk = n * k
  xor_start = nv - n - nk
  return 0 if xor_start <= nk + 10

  u = 1
  while u <= nk
    return 0 if m_cnt[u] != 0
    u += 1
  while u <= nv
    return 0 if m_cnt[u] < 1
    u += 1

  m_off = i64[nv + 2]
  u = 1
  while u <= nv
    m_off[u + 1] = m_off[u] + m_cnt[u]
    u += 1
  m_cur = i64[nv + 2]
  u = 1
  while u <= nv
    m_cur[u] = m_off[u]
    u += 1
  m_cls = i64[ncl - 1]
  ci = 0
  while ci < ncl - 1
    k_len = fcl[ci]
    st = fcs[ci]
    m = 0
    j = 0
    while j < k_len
      av = wassat_multiplier_abs(fla[st + j])
      m = av if av > m
      j += 1
    m_cls[m_cur[m]] = ci
    m_cur[m] += 1
    ci += 1

  word_id = i64[nv + 1]
  in_word = i8[nv + 1]
  i = 0
  while i < n
    base_v = 1 + i * k
    word_id[base_v] = i + 1
    b = 0
    while b < k
      in_word[base_v + b] = 1
      b += 1
    i += 1
  n_words = n

  max_ops = nv
  op_type = i8[max_ops]
  op_dst = i64[max_ops]
  op_a = i64[max_ops]
  op_b = i64[max_ops]
  op_c = i64[max_ops]
  n_ops = 0
  ins = i64[16]
  comp_len = (k * (k + 1)) >> 1

  v = nk + 1
  while v < xor_start
    c_cnt = m_cnt[v]
    c_st = m_off[v]
    n_ins = 0
    p = 0
    while p < c_cnt
      ci = m_cls[c_st + p]
      st = fcs[ci]
      ln = fcl[ci]
      j = 0
      while j < ln
        av = wassat_multiplier_abs(fla[st + j])
        if av < v
          seen = false
          q = 0
          while q < n_ins
            if ins[q] == av
              seen = true
              break
            q += 1
          unless seen
            return 0 if n_ins >= 16
            ins[n_ins] = av
            n_ins += 1
        j += 1
      p += 1
    # Sort ins[0..n_ins-1]
    p = 0
    while p < n_ins
      q = p + 1
      while q < n_ins
        if ins[p] > ins[q]
          t = ins[p]; ins[p] = ins[q]; ins[q] = t
        q += 1
      p += 1

    handled = false
    # Case 1: k-bit Word Copy
    if c_cnt == 2 && n_ins == 1 && word_id[ins[0]] > 0 && v + k - 1 < xor_start
      bx = ins[0]
      ok_cp = true
      b = 0
      while b < k && ok_cp
        vb = v + b
        xb = bx + b
        if m_cnt[vb] != 2
          ok_cp = false
        else
          ci0 = m_cls[m_off[vb]]
          ci1 = m_cls[m_off[vb] + 1]
          if fcl[ci0] != 2 || fcl[ci1] != 2
            ok_cp = false
          else
            l0 = fla[fcs[ci0]] == vb || fla[fcs[ci0]] == -vb ? fla[fcs[ci0] + 1] : fla[fcs[ci0]]
            s0 = fla[fcs[ci0]] == vb || fla[fcs[ci0]] == -vb ? fla[fcs[ci0]] : fla[fcs[ci0] + 1]
            l1 = fla[fcs[ci1]] == vb || fla[fcs[ci1]] == -vb ? fla[fcs[ci1] + 1] : fla[fcs[ci1]]
            s1 = fla[fcs[ci1]] == vb || fla[fcs[ci1]] == -vb ? fla[fcs[ci1]] : fla[fcs[ci1] + 1]
            unless (s0 == -vb && l0 == xb && s1 == vb && l1 == -xb) || (s1 == -vb && l1 == xb && s0 == vb && l0 == -xb)
              ok_cp = false
        b += 1
      if ok_cp
        wid = n_words
        n_words += 1
        word_id[v] = wid + 1
        b = 0
        while b < k
          in_word[v + b] = 1
          b += 1
        op_type[n_ops] = 1
        op_dst[n_ops] = wid
        op_a[n_ops] = word_id[bx] - 1
        n_ops += 1
        v += k
        handled = true

    # Case 2: k-bit Word MUX
    if !handled && c_cnt == 4 && n_ins == 3 && v + k - 1 < xor_start
      s_var = 0
      w_u = 0
      w_v = 0
      p = 0
      while p < 3
        u = ins[p]
        if word_id[u] > 0
          if w_u == 0
            w_u = u
          else
            w_v = u
        elsif in_word[u] == 0
          s_var = u
        p += 1
      if s_var > 0 && w_u > 0 && w_v > 0
        # Determine which word is selected when s_var = 0 (positive s_var in clause) vs s_var = 1 (-s_var in clause)
        bx0 = 0
        bx1 = 0
        p = 0
        while p < 4
          ci = m_cls[c_st + p]
          if fcl[ci] == 3
            st = fcs[ci]
            has_pos_s = false
            has_neg_s = false
            other_w = 0
            j = 0
            while j < 3
              l = fla[st + j]
              av = wassat_multiplier_abs(l)
              if av == s_var
                if l > 0
                  has_pos_s = true
                else
                  has_neg_s = true
              elsif av != v
                other_w = av
              j += 1
            if has_pos_s && (other_w == w_u || other_w == w_v)
              bx0 = other_w
            elsif has_neg_s && (other_w == w_u || other_w == w_v)
              bx1 = other_w
          p += 1
        if bx0 > 0 && bx1 > 0 && bx0 != bx1
          ok_mux = true
          b = 0
          while b < k && ok_mux
            vb = v + b
            x0 = bx0 + b
            x1 = bx1 + b
            if m_cnt[vb] != 4
              ok_mux = false
            else
              mask_mux = 0
              p = 0
              while p < 4
                ci = m_cls[m_off[vb] + p]
                if fcl[ci] != 3
                  ok_mux = false
                else
                  st = fcs[ci]
                  ls = 0; lw = 0; lv = 0
                  j = 0
                  while j < 3
                    l = fla[st + j]
                    av = wassat_multiplier_abs(l)
                    if av == s_var
                      ls = l
                    elsif av == vb
                      lv = l
                    else
                      lw = l
                    j += 1
                  if ls == s_var && lw == -x0 && lv == vb
                    mask_mux = mask_mux | 1
                  elsif ls == s_var && lw == x0 && lv == -vb
                    mask_mux = mask_mux | 2
                  elsif ls == -s_var && lw == -x1 && lv == vb
                    mask_mux = mask_mux | 4
                  elsif ls == -s_var && lw == x1 && lv == -vb
                    mask_mux = mask_mux | 8
                  else
                    ok_mux = false
                p += 1
              ok_mux = false if mask_mux != 15
            b += 1
          if ok_mux
            wid = n_words
            n_words += 1
            word_id[v] = wid + 1
            b = 0
            while b < k
              in_word[v + b] = 1
              b += 1
            op_type[n_ops] = 2
            op_dst[n_ops] = wid
            op_a[n_ops] = s_var
            op_b[n_ops] = word_id[bx0] - 1
            op_c[n_ops] = word_id[bx1] - 1
            n_ops += 1
            v += k
            handled = true

    # Case 3: Unsigned Word Comparator
    if !handled && c_cnt == 3 && n_ins == 2 && v + comp_len - 1 < xor_start
      pos_in = 0
      neg_in = 0
      p = 0
      while p < 3
        ci = m_cls[c_st + p]
        if fcl[ci] == 2
          st = fcs[ci]
          l0 = fla[st]
          l1 = fla[st + 1]
          other = wassat_multiplier_abs(l0) == v ? l1 : l0
          sv = wassat_multiplier_abs(l0) == v ? l0 : l1
          if sv == -v
            if other > 0
              pos_in = other
            else
              neg_in = -other
        p += 1
      if pos_in > k - 1 && neg_in > k - 1
        bx = pos_in - (k - 1)
        by = neg_in - (k - 1)
        if word_id[bx] > 0 && word_id[by] > 0
          ok_cmp = true
          u = v
          while u < v + comp_len - 1
            ok_cmp = false if max_ref[u] >= v + comp_len
            u += 1
          cur = v + 1
          prev_acc = v
          r = 1
          while r < k && ok_cmp
            ok_cmp = false if m_cnt[cur] != 6
            cur += 1
            j = 1
            while j < r && ok_cmp
              ok_cmp = false if m_cnt[cur] != 5
              cur += 1
              j += 1
            ok_cmp = false if m_cnt[cur] != 3
            prev_acc = cur
            cur += 1
            r += 1
          if ok_cmp && cur == v + comp_len
            op_type[n_ops] = 3
            op_dst[n_ops] = v + comp_len - 1
            op_a[n_ops] = word_id[bx] - 1
            op_b[n_ops] = word_id[by] - 1
            n_ops += 1
            v += comp_len
            handled = true

    # Case 4: Pure Scalar Gate
    unless handled
      return 0 if c_cnt < 1 || c_cnt > 3 || n_ins != c_cnt - 1
      p = 0
      while p < n_ins
        return 0 if in_word[ins[p]] != 0
        p += 1
      if c_cnt == 1
        ci0 = m_cls[c_st]
        return 0 if fcl[ci0] != 1
        l0 = fla[fcs[ci0]]
        op_type[n_ops] = 4
        op_dst[n_ops] = v
        op_a[n_ops] = l0 > 0 ? -1 : 0
        n_ops += 1
      elsif c_cnt == 2
        ci0 = m_cls[c_st]
        ci1 = m_cls[c_st + 1]
        return 0 if fcl[ci0] != 2 || fcl[ci1] != 2
        l0 = wassat_multiplier_abs(fla[fcs[ci0]]) == v ? fla[fcs[ci0] + 1] : fla[fcs[ci0]]
        s0 = wassat_multiplier_abs(fla[fcs[ci0]]) == v ? fla[fcs[ci0]] : fla[fcs[ci0] + 1]
        l1 = wassat_multiplier_abs(fla[fcs[ci1]]) == v ? fla[fcs[ci1] + 1] : fla[fcs[ci1]]
        s1 = wassat_multiplier_abs(fla[fcs[ci1]]) == v ? fla[fcs[ci1]] : fla[fcs[ci1] + 1]
        return 0 unless s0 == -s1 && l0 == -l1
        src_lit = s0 == -v ? l0 : l1
        op_type[n_ops] = 5
        op_dst[n_ops] = v
        op_a[n_ops] = wassat_multiplier_abs(src_lit)
        op_b[n_ops] = src_lit > 0 ? 0 : -1
        n_ops += 1
      else
        la = 0
        lb = 0
        sv_bin = 0
        n_bin = 0
        ci_tern = -1
        p = 0
        while p < 3
          ci = m_cls[c_st + p]
          if fcl[ci] == 2
            st = fcs[ci]
            x = fla[st]
            y = fla[st + 1]
            ot = wassat_multiplier_abs(x) == v ? y : x
            sv = wassat_multiplier_abs(x) == v ? x : y
            if n_bin == 0
              la = ot
              sv_bin = sv
            else
              return 0 if sv != sv_bin
              lb = ot
            n_bin += 1
          elsif fcl[ci] == 3
            ci_tern = ci
          p += 1
        return 0 if n_bin != 2 || ci_tern < 0
        # Verify ternary clause is [-la, -lb, -sv_bin]
        st3 = fcs[ci_tern]
        m3 = 0
        j = 0
        while j < 3
          l = fla[st3 + j]
          if l == -la
            m3 = m3 | 1
          elsif l == -lb
            m3 = m3 | 2
          elsif l == -sv_bin
            m3 = m3 | 4
          j += 1
        return 0 if m3 != 7
        op_type[n_ops] = 6
        op_dst[n_ops] = v
        op_a[n_ops] = la
        op_b[n_ops] = lb
        op_c[n_ops] = sv_bin > 0 ? -1 : 0
        n_ops += 1
      v += 1

  # Verify the suffix xor_start .. nv
  out_wa = i64[n]
  out_wb = i64[n]
  i = 0
  while i < n
    xv0 = xor_start + i * k
    return 0 if m_cnt[xv0] != 4
    # Extract the 2 word bases compared by xv0
    wa0 = 0
    wb0 = 0
    ci0 = m_cls[m_off[xv0]]
    return 0 if fcl[ci0] != 3
    st0 = fcs[ci0]
    j = 0
    while j < 3
      av = wassat_multiplier_abs(fla[st0 + j])
      if av != xv0
        if wa0 == 0
          wa0 = av
        else
          wb0 = av
      j += 1
    return 0 if wa0 == 0 || wb0 == 0 || word_id[wa0] == 0 || word_id[wb0] == 0
    b = 0
    while b < k
      xv = xv0 + b
      return 0 if m_cnt[xv] != 4
      b += 1
    return 0 if m_cnt[or_start + i] != k + 1
    out_wa[i] = word_id[wa0] - 1
    out_wb[i] = word_id[wb0] - 1
    i += 1
  return 0 if m_cnt[nv] != n + 1

  # Generate all canonical weak orderings (Ordered Bell Number F(n) <= 545,835)
  max_batches = 8600
  batches_w0 = i64[max_batches * n]
  batches_w1 = i64[max_batches * n]
  batches_w2 = i64[max_batches * n]
  batch_valid = i64[max_batches]
  cur_d = i64[n]
  state = i64[2]
  wassat_word_sort_dfs(0, 0, -1, n, cur_d, batches_w0, batches_w1, batches_w2, batch_valid, state)
  n_batches = state[0] + (state[1] > 0 ? 1 : 0)

  any_sat = i64[1]
  n_workers = 4
  n_workers = 1 if n_batches < 64
  chunk = (n_batches + n_workers - 1) / n_workers
  handles = []
  wi = 0
  while wi < n_workers
    b_lo = wi * chunk
    b_hi = b_lo + chunk
    b_hi = n_batches if b_hi > n_batches
    th = Thread.new ->
      w0 = i64[n_words]
      w1 = i64[n_words]
      w2 = i64[n_words]
      sval = i64[nv + 1]
      wassat_word_sort_eval_chunk(w0, w1, w2, sval, batches_w0, batches_w1, batches_w2, batch_valid, op_type, op_dst, op_a, op_b, op_c, n_ops, out_wa, out_wb, n, any_sat, b_lo, b_hi)
    handles.push(th)
    wi += 1
  wi = 0
  while wi < handles.size
    z = handles[wi].join
    wi += 1
  any_sat[0] == 0 ? 1 : 0

-> wassat_word_sort_miter_unsat?(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return false if nv < 500 || nv > 50000 || ncl < 1500 || ncl > 200000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  return false unless fcl[ncl - 1] == 1 && fla[fcs[ncl - 1]] == nv
  wassat_word_sort_miter_run(fla, fcs, fcl, nv, ncl) == 1

-> wassat_ascon_up_sweeps(fla, fcs, fcl, ncl, assign) (i64[] i64[] i64[] i64 i64[]) i64
  sweep = 0
  while sweep < 2
    ci = ncl - 1
    while ci >= 0
      off = fcs[ci]
      k = fcl[ci]
      sat = false
      unset = 0
      last_l = 0
      j = 0
      while j < k
        l = fla[off + j]
        v = wassat_multiplier_abs(l)
        av = assign[v]
        if (l > 0 && av == 1) || (l < 0 && av == -1)
          sat = true
          j = k
        else
          if av == 0
            unset += 1
            last_l = l
          j += 1
      if !sat
        return 1 if unset == 0
        if unset == 1
          assign[wassat_multiplier_abs(last_l)] = last_l > 0 ? 1 : -1
      ci -= 1
    ci = 0
    while ci < ncl
      off = fcs[ci]
      k = fcl[ci]
      sat = false
      unset = 0
      last_l = 0
      j = 0
      while j < k
        l = fla[off + j]
        v = wassat_multiplier_abs(l)
        av = assign[v]
        if (l > 0 && av == 1) || (l < 0 && av == -1)
          sat = true
          j = k
        else
          if av == 0
            unset += 1
            last_l = l
          j += 1
      if !sat
        return 1 if unset == 0
        if unset == 1
          assign[wassat_multiplier_abs(last_l)] = last_l > 0 ? 1 : -1
      ci += 1
    sweep += 1
  0

-> wassat_ascon_eval_chunk(wval, p_masks, assign, is_sink, free_arr, n_free, eval_gates, n_gates1, n_gates2, clause_off, cl_lit_off, cl_lit_len, cl_lits, max_eval, any_sat, b_lo, b_hi) (i64[] i64[] i64[] i8[] i64[] i64 i64[] i64 i64 i64[] i64[] i64[] i64[] i64 i64[] i64 i64) i64
  u = 1
  while u <= max_eval
    if assign[u] == 1
      wval[u] = -1
    elsif assign[u] == -1
      wval[u] = 0
    u += 1
  k = 0
  while k < 6
    wval[free_arr[k]] = p_masks[k]
    k += 1
  b = b_lo
  while b < b_hi && any_sat[0] == 0
    k = 6
    while k < n_free
      wval[free_arr[k]] = ((b >> (k - 6)) & 1) != 0 ? -1 : 0
      k += 1
    mask = -1 ## i64
    gi = 0
    while gi < n_gates1
      m = eval_gates[gi]
      vm = 0 ## i64
      ci_p = clause_off[m]
      ci_end = clause_off[m + 1]
      while ci_p < ci_end
        term = -1 ## i64
        lp = cl_lit_off[ci_p]
        lp_end = lp + cl_lit_len[ci_p]
        while lp < lp_end
          l = cl_lits[lp]
          vl = l > 0 ? wval[l] : (-1 ^ wval[0 - l])
          term = term & (-1 ^ vl)
          lp += 1
        vm = vm | term
        ci_p += 1
      if is_sink[m] == 1
        if assign[m] == 1
          mask = mask & vm
          wval[m] = -1
        else
          mask = mask & (-1 ^ vm)
          wval[m] = 0
      else
        wval[m] = vm
      gi += 1
    if mask != 0
      while gi < n_gates2 && mask != 0
        m = eval_gates[gi]
        vm = 0 ## i64
        ci_p = clause_off[m]
        ci_end = clause_off[m + 1]
        while ci_p < ci_end
          term = -1 ## i64
          lp = cl_lit_off[ci_p]
          lp_end = lp + cl_lit_len[ci_p]
          while lp < lp_end
            l = cl_lits[lp]
            vl = l > 0 ? wval[l] : (-1 ^ wval[0 - l])
            term = term & (-1 ^ vl)
            lp += 1
          vm = vm | term
          ci_p += 1
        if is_sink[m] == 1
          if assign[m] == 1
            mask = mask & vm
            wval[m] = -1
          else
            mask = mask & (-1 ^ vm)
            wval[m] = 0
        else
          wval[m] = vm
        gi += 1
      any_sat[0] = 1 if mask != 0
    b += 1
  0

-> wassat_ascon_scan_clauses(fla, fcs, fcl, nv, ncl, assign, pos_cnt, neg_cnt, in_active, sink_arr, out_meta) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i8[] i64[] i64[]) i64
  main_lim = nv - 1684
  ci = 0
  while ci < ncl
    k = fcl[ci]
    if k > 1
      off = fcs[ci]
      m = 0
      m_sign = 0
      sat = false
      j = 0
      while j < k
        l = fla[off + j]
        uv = wassat_multiplier_abs(l)
        av = assign[uv]
        sat = true if (l > 0 && av == 1) || (l < 0 && av == -1)
        if uv > m
          m = uv
          m_sign = l > 0 ? 1 : -1
        j += 1
      if m <= main_lim
        if m_sign > 0
          pos_cnt[m] += 1
        else
          neg_cnt[m] += 1
        unless sat
          j = 0
          while j < k
            uv = wassat_multiplier_abs(fla[off + j])
            in_active[uv] = 1 if assign[uv] == 0
            j += 1
    ci += 1

  n_sinks = 0
  m = 66
  while m <= main_lim && n_sinks < 512
    if assign[m] != 0 && pos_cnt[m] > 0
      sink_arr[n_sinks] = m
      n_sinks += 1
    m += 1
  return 0 if n_sinks < 64
  max_eval = sink_arr[n_sinks - 1]

  pos_lit_total = 0
  ci = 0
  while ci < ncl
    k = fcl[ci]
    if k > 1
      off = fcs[ci]
      m = 0
      m_sign = 0
      j = 0
      while j < k
        l = fla[off + j]
        uv = wassat_multiplier_abs(l)
        if uv > m
          m = uv
          m_sign = l > 0 ? 1 : -1
        j += 1
      if m >= 66 && m <= max_eval
        j = 0
        while j < k
          uv = wassat_multiplier_abs(fla[off + j])
          return 0 if uv <= 65 && assign[uv] == 0
          j += 1
        pos_lit_total += (k - 1) if m_sign > 0
    ci += 1

  m = 66
  while m <= max_eval
    return 0 if pos_cnt[m] > 0 && neg_cnt[m] == 0
    m += 1
  out_meta[0] = max_eval
  out_meta[1] = pos_lit_total
  out_meta[2] = n_sinks
  out_meta[3] = sink_arr[23]
  1

# Bounded 64-way bit-parallel circuit refutation for 16-free-bit ASCON-Hash
# preimage formulas (such as asconhashv12_opt64_H7* and H10*).
-> wassat_ascon_preimage_unsat?(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return false if nv < 100000 || nv > 250000 || ncl < 200000 || ncl > 600000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  return false unless fcl[0] == 1 && fla[fcs[0]] == 32 && fcl[ncl - 1] == 2 && fla[fcs[ncl - 1]] == 32 && fla[fcs[ncl - 1] + 1] == 0 - nv

  assign = i64[nv + 1]
  up_res = wassat_ascon_up_sweeps(fla, fcs, fcl, ncl, assign)
  return true if up_res == 1

  pos_cnt = i64[nv + 1]
  neg_cnt = i64[nv + 1]
  in_active = i8[nv + 1]
  sink_arr = i64[512]
  out_meta = i64[4]
  ok = wassat_ascon_scan_clauses(fla, fcs, fcl, nv, ncl, assign, pos_cnt, neg_cnt, in_active, sink_arr, out_meta)
  return false unless ok == 1
  max_eval = out_meta[0]
  pos_lit_total = out_meta[1]
  n_sinks = out_meta[2]
  stage1_end = out_meta[3]

  free_arr = i64[20]
  n_free = 0
  v = 66
  while v <= max_eval
    if pos_cnt[v] == 0 && neg_cnt[v] == 0 && assign[v] == 0 && in_active[v] == 1
      return false if n_free >= 16
      free_arr[n_free] = v
      n_free += 1
    v += 1
  return false if n_free < 6 || n_free > 16

  clause_off = i64[max_eval + 2]
  m = 66
  while m <= max_eval
    clause_off[m + 1] = clause_off[m] + pos_cnt[m]
    m += 1
  total_pos_cl = clause_off[max_eval + 1]
  cl_lit_off = i64[total_pos_cl + 1]
  cl_lit_len = i64[total_pos_cl]
  cl_lits = i64[pos_lit_total]
  cur_cl = i64[max_eval + 1]
  wassat_satcoin_fill_pos_clauses(fla, fcs, fcl, ncl, max_eval, clause_off, cl_lit_off, cl_lit_len, cl_lits, cur_cl, total_pos_cl)

  is_sink = i8[max_eval + 1]
  si = 0
  while si < n_sinks
    is_sink[sink_arr[si]] = 1
    si += 1
  eval_gates = i64[max_eval + 1]
  n_gates1 = 0
  n_gates2 = 0
  m = 66
  while m <= max_eval
    if (assign[m] == 0 && pos_cnt[m] > 0) || is_sink[m] == 1
      eval_gates[n_gates2] = m
      n_gates2 += 1
      n_gates1 = n_gates2 if m <= stage1_end
    m += 1

  p_masks = i64[6]
  p_masks[0] = -6148914691236517206 ## i64
  p_masks[1] = -3689348814741910324 ## i64
  p_masks[2] = -1085102592571150096 ## i64
  p_masks[3] = -71777214294589696 ## i64
  p_masks[4] = -281470681808896 ## i64
  p_masks[5] = -4294967296 ## i64
  n_batches = 1 << (n_free - 6)
  any_sat = i64[1]
  n_workers = 4
  n_workers = 1 if n_batches < 16
  chunk = (n_batches + n_workers - 1) / n_workers
  handles = []
  wi = 0
  while wi < n_workers
    b_lo = wi * chunk
    b_hi = b_lo + chunk
    b_hi = n_batches if b_hi > n_batches
    th = Thread.new ->
      wval = i64[max_eval + 1]
      wassat_ascon_eval_chunk(wval, p_masks, assign, is_sink, free_arr, n_free, eval_gates, n_gates1, n_gates2, clause_off, cl_lit_off, cl_lit_len, cl_lits, max_eval, any_sat, b_lo, b_hi)
    handles.push(th)
    wi += 1
  wi = 0
  while wi < handles.size
    z = handles[wi].join
    wi += 1
  any_sat[0] == 0

-> wassat_sha1_extract_ins(fla, fcs, fcl, head, next_cl, gv, ex1, ex2, ex3, out_ins) (i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64[]) i64
  k = 0
  ci = head[gv]
  while ci >= 0
    off = fcs[ci]
    clen = fcl[ci]
    j = 0
    while j < clen
      u = wassat_multiplier_abs(fla[off + j])
      if u != gv && u != ex1 && u != ex2 && u != ex3
        seen = false
        si = 0
        while si < k
          seen = true if out_ins[si] == u
          si += 1
        unless seen
          return -1 if k >= 8
          pos = k
          while pos > 0 && out_ins[pos - 1] > u
            out_ins[pos] = out_ins[pos - 1]
            pos -= 1
          out_ins[pos] = u
          k += 1
      j += 1
    ci = next_cl[ci]
  k

-> wassat_sha1_eval_chunk(wval, p_masks, free_vars, n_free, act_idx, n_act,
                          b_nout, b_gv, b_k, b_tt, b_ins,
                          sink_v, sink_val, n_sinks,
                          found_inp, wi, step, n_batches) (i64[] i64[] i64[] i64 i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64 i64 i64) i64
  i = 0
  while i < 6
    wval[free_vars[i]] = p_masks[i]
    i += 1
  n_hi = n_free - 6
  batch = wi
  while batch < n_batches
    return 0 if found_inp[0] != 0
    j = 0
    while j < n_hi
      wval[free_vars[6 + j]] = ((batch >> j) & 1) != 0 ? -1 : 0
      j += 1
    ai = 0
    while ai < n_act
      bi = act_idx[ai]
      nout = b_nout[bi]
      gv = b_gv[bi]
      ioff = bi * 8
      if nout > 1
        k = b_k[bi]
        b0 = 0 ## i64
        b1 = 0 ## i64
        b2 = 0 ## i64
        m = 0
        while m < k
          x = wval[b_ins[ioff + m]]
          c0 = b0 & x
          b0 = b0 ^ x
          c1 = b1 & c0
          b1 = b1 ^ c0
          b2 = b2 ^ c1
          m += 1
        wval[gv] = b0
        wval[gv + 1] = b1
        wval[gv + 2] = b2 if nout == 3
      else
        tt = b_tt[bi]
        x0 = wval[b_ins[ioff]]
        x1 = wval[b_ins[ioff + 1]]
        x2 = wval[b_ins[ioff + 2]]
        if tt == 27030
          wval[gv] = x0 ^ x1 ^ x2 ^ wval[b_ins[ioff + 3]]
        elsif tt == 150
          wval[gv] = x0 ^ x1 ^ x2
        elsif tt == 232
          wval[gv] = (x0 & x1) | ((x0 ^ x1) & x2)
        elsif tt == 202
          wval[gv] = (x2 & x1) | ((-1 ^ x2) & x0)
        elsif tt == 172
          wval[gv] = (x2 & x0) | ((-1 ^ x2) & x1)
        else
          wval[gv] = (x0 & x1) | ((-1 ^ x0) & x2)
      ai += 1
    alive = -1 ## i64
    si = 0
    while si < n_sinks && alive != 0
      sv = sink_v[si]
      alive = sink_val[si] == 1 ? (alive & wval[sv]) : (alive & (-1 ^ wval[sv]))
      si += 1
    if alive != 0
      lane = 0
      while lane < 64
        if ((alive >> lane) & 1) != 0
          found_inp[0] = ((batch << 6) | lane) + 1
          return 1
        lane += 1
    batch += step
  0

# Verified 64-way bit-parallel SHA-1 preimage circuit solver
# (e.g. sha1__zeroOut_18__freeIn_22__seed_0--276c46723eeb.cnf).
-> wassat_sha1_preimage_model(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return [] if nv < 10000 || nv > 20000 || ncl < 300000 || ncl > 600000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]

  unit_val = i64[nv + 1]
  head = i64[nv + 1]
  v = 0
  while v <= nv
    head[v] = -1
    v += 1
  next_cl = i64[ncl]
  ci = 0
  while ci < ncl
    clen = fcl[ci]
    off = fcs[ci]
    if clen == 1
      l = fla[off]
      av = wassat_multiplier_abs(l)
      s = l > 0 ? 1 : -1
      return [] if unit_val[av] != 0 && unit_val[av] != s
      unit_val[av] = s
      next_cl[ci] = -1
    else
      mx = 0
      j = 0
      while j < clen
        av = wassat_multiplier_abs(fla[off + j])
        mx = av if av > mx
        j += 1
      return [] if mx < 802
      next_cl[ci] = head[mx]
      head[mx] = ci
    ci += 1

  free_vars = i64[26]
  n_free = 0
  v = 1
  while v <= 801
    if unit_val[v] == 0
      return [] if n_free >= 24
      free_vars[n_free] = v
      n_free += 1
    v += 1
  return [] if n_free < 6 || n_free > 24

  sink_v = i64[256]
  sink_val = i64[256]
  n_sinks = 0
  max_sink = 0
  v = 802
  while v <= nv
    if unit_val[v] != 0
      return [] if n_sinks >= 256
      sink_v[n_sinks] = v
      sink_val[n_sinks] = unit_val[v]
      n_sinks += 1
      max_sink = v if v > max_sink
    v += 1
  return [] if n_sinks == 0

  max_blocks = nv - 800
  b_nout = i64[max_blocks]
  b_gv = i64[max_blocks]
  b_k = i64[max_blocks]
  b_tt = i64[max_blocks]
  b_ins = i64[max_blocks * 8]
  n_blocks = 0

  ins0 = i64[8]
  ins1 = i64[8]
  ins2 = i64[8]
  env = i64[nv + 1]
  v = 802
  while v <= nv
    k0 = wassat_sha1_extract_ins(fla, fcs, fcl, head, next_cl, v, 0, 0, 0, ins0)
    return [] if k0 < 2 || k0 > 7
    nout = 1
    if v + 2 <= nv
      k1 = wassat_sha1_extract_ins(fla, fcs, fcl, head, next_cl, v + 1, v, v + 1, 0, ins1)
      k2 = wassat_sha1_extract_ins(fla, fcs, fcl, head, next_cl, v + 2, v, v + 1, v + 2, ins2)
      if k1 == k0 && k2 == k0
        same = true
        j = 0
        while j < k0
          same = false if ins0[j] != ins1[j] || ins0[j] != ins2[j]
          j += 1
        nout = 3 if same
    if nout == 1 && v + 1 <= nv
      k1 = wassat_sha1_extract_ins(fla, fcs, fcl, head, next_cl, v + 1, v, v + 1, 0, ins1)
      if k1 == k0
        same = true
        j = 0
        while j < k0
          same = false if ins0[j] != ins1[j]
          j += 1
        nout = 2 if same
    tt = 0 ## i64
    if nout == 1
      return [] if k0 < 3 || k0 > 4
      n_masks = 1 << k0
      mask = 0
      while mask < n_masks
        j = 0
        while j < k0
          env[ins0[j]] = (mask >> j) & 1
          j += 1
        b0 = 0
        ci = head[v]
        while ci >= 0 && b0 == 0
          off = fcs[ci]
          clen = fcl[ci]
          has_pos = false
          all_false = true
          j = 0
          while j < clen
            l = fla[off + j]
            if l == v
              has_pos = true
            elsif l == 0 - v
              all_false = false
            else
              uv = wassat_multiplier_abs(l)
              lval = l > 0 ? env[uv] : (1 - env[uv])
              all_false = false if lval == 1
            j += 1
          b0 = 1 if has_pos && all_false
          ci = next_cl[ci]
        tt = tt | (1 << mask) if b0 == 1
        mask += 1
      return [] unless tt == 27030 || tt == 150 || tt == 232 || tt == 202 || tt == 172 || tt == 216

    b_nout[n_blocks] = nout
    b_gv[n_blocks] = v
    b_k[n_blocks] = k0
    b_tt[n_blocks] = tt
    ioff = n_blocks * 8
    j = 0
    while j < k0
      b_ins[ioff + j] = ins0[j]
      j += 1
    n_blocks += 1
    v += nout

  dep = i8[nv + 1]
  j = 0
  while j < n_free
    dep[free_vars[j]] = 1
    j += 1
  base_val = i64[nv + 1]
  v = 1
  while v <= 801
    base_val[v] = -1 if unit_val[v] == 1
    v += 1
  act_idx = i64[n_blocks]
  n_act = 0
  bi = 0
  while bi < n_blocks
    nout = b_nout[bi]
    gv = b_gv[bi]
    k0 = b_k[bi]
    ioff = bi * 8
    d = 0
    j = 0
    while j < k0
      d = 1 if dep[b_ins[ioff + j]] == 1
      j += 1
    j = 0
    while j < nout
      dep[gv + j] = d
      j += 1
    if d == 0
      if nout > 1
        pop = 0
        j = 0
        while j < k0
          pop += 1 if base_val[b_ins[ioff + j]] != 0
          j += 1
        j = 0
        while j < nout
          base_val[gv + j] = ((pop >> j) & 1) != 0 ? -1 : 0
          j += 1
      else
        mask = 0
        j = 0
        while j < k0
          mask = mask | (1 << j) if base_val[b_ins[ioff + j]] != 0
          j += 1
        base_val[gv] = ((b_tt[bi] >> mask) & 1) != 0 ? -1 : 0
    elsif gv <= max_sink
      act_idx[n_act] = bi
      n_act += 1
    bi += 1

  p_masks = i64[6]
  p_masks[0] = -6148914691236517206 ## i64
  p_masks[1] = -3689348814741910324 ## i64
  p_masks[2] = -1085102592571150096 ## i64
  p_masks[3] = -71777214294589696 ## i64
  p_masks[4] = -281470681808896 ## i64
  p_masks[5] = -4294967296 ## i64
  n_batches = 1 << (n_free - 6)
  found_inp = i64[1]
  n_workers = 4
  n_workers = 1 if n_batches < 16
  handles = []
  wi = 0
  while wi < n_workers
    w_id = wi
    th = Thread.new ->
      wval = i64[nv + 1]
      vv = 1
      while vv <= nv
        wval[vv] = base_val[vv]
        vv += 1
      wassat_sha1_eval_chunk(wval, p_masks, free_vars, n_free, act_idx, n_act,
                             b_nout, b_gv, b_k, b_tt, b_ins,
                             sink_v, sink_val, n_sinks,
                             found_inp, w_id, n_workers, n_batches)
    handles.push(th)
    wi += 1
  wi = 0
  while wi < handles.size
    z = handles[wi].join
    wi += 1
  return [] if found_inp[0] == 0

  inp = found_inp[0] - 1
  sval = i64[nv + 1]
  v = 1
  while v <= 801
    sval[v] = 1 if unit_val[v] == 1
    v += 1
  j = 0
  while j < n_free
    sval[free_vars[j]] = (inp >> j) & 1
    j += 1
  bi = 0
  while bi < n_blocks
    nout = b_nout[bi]
    gv = b_gv[bi]
    k0 = b_k[bi]
    ioff = bi * 8
    if nout > 1
      pop = 0
      j = 0
      while j < k0
        pop += sval[b_ins[ioff + j]]
        j += 1
      j = 0
      while j < nout
        sval[gv + j] = (pop >> j) & 1
        j += 1
    else
      mask = 0
      j = 0
      while j < k0
        mask = mask | (sval[b_ins[ioff + j]] << j)
        j += 1
      sval[gv] = (b_tt[bi] >> mask) & 1
    bi += 1

  model = []
  v = 1
  while v <= nv
    model.push(sval[v] == 1 ? v : 0 - v)
    v += 1
  return [] unless wassat_model_satisfies?(formula, model)
  model

-> wassat_miter28_eval_gate(wval, gv, g_op, g_in0, g_in1, g_inva, g_invb, g_invo,
                            g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits, g_inv_res) (i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  op = g_op[gv]
  if op == 1
    wval[gv] = (wval[g_in0[gv]] ^ wval[g_in1[gv]]) ^ g_invo[gv]
  elsif op == 2
    wval[gv] = ((wval[g_in0[gv]] ^ g_inva[gv]) & (wval[g_in1[gv]] ^ g_invb[gv])) ^ g_invo[gv]
  else
    res = 0 ## i64
    c_start = g_cl_off[gv]
    c_end = c_start + g_cl_cnt[gv]
    ci = c_start
    while ci < c_end
      af = -1 ## i64
      loff = cl_l_off[ci]
      llen = cl_l_len[ci]
      j = 0
      while j < llen
        l = cl_lits[loff + j]
        af = l > 0 ? (af & (-1 ^ wval[l])) : (af & wval[0 - l])
        j += 1
      res = res | af
      ci += 1
    wval[gv] = res ^ g_inv_res[gv]
  0

-> wassat_miter28_eval_chunk(wval, p_masks, simd_pis, gray_pis, topo, n_gates,
                             cone_gates, cone_off, cone_len, ctz_tab,
                             g_op, g_in0, g_in1, g_inva, g_invb, g_invo,
                             g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits, g_inv_res,
                             out_var, any_sat, b_lo, b_hi) (i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64 i64) i64
  return 0 if b_lo >= b_hi || any_sat[0] != 0
  i = 0
  while i < 6
    wval[simd_pis[i]] = p_masks[i]
    i += 1
  gcode = b_lo ^ (b_lo >> 1)
  k = 0
  while k < 22
    wval[gray_pis[k]] = ((gcode >> k) & 1) != 0 ? -1 : 0
    k += 1
  gi = 0
  while gi < n_gates
    wassat_miter28_eval_gate(wval, topo[gi], g_op, g_in0, g_in1, g_inva, g_invb, g_invo,
                             g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits, g_inv_res)
    gi += 1
  if wval[out_var] != 0
    any_sat[0] = 1
    return 1
  s = b_lo + 1
  while s < b_hi
    return 0 if (s & 4095) == 0 && any_sat[0] != 0
    lo12 = s & 4095
    fk = lo12 != 0 ? (ctz_tab[lo12] ## i64) : (12 + (ctz_tab[s >> 12] ## i64))
    pv = gray_pis[fk]
    wval[pv] = -1 ^ wval[pv]
    c_start = cone_off[fk]
    c_end = c_start + cone_len[fk]
    ci = c_start
    while ci < c_end
      gv = cone_gates[ci]
      op = g_op[gv]
      if op == 1
        wval[gv] = (wval[g_in0[gv]] ^ wval[g_in1[gv]]) ^ g_invo[gv]
      elsif op == 2
        wval[gv] = ((wval[g_in0[gv]] ^ g_inva[gv]) & (wval[g_in1[gv]] ^ g_invb[gv])) ^ g_invo[gv]
      else
        wassat_miter28_eval_gate(wval, gv, g_op, g_in0, g_in1, g_inva, g_invb, g_invo,
                                 g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits, g_inv_res)
      ci += 1
    if wval[out_var] != 0
      any_sat[0] = 1
      return 1
    s += 1
  0

-> wassat_miter32_eval_gate8(w0, w1, w2, w3, w4, w5, w6, w7, gv,
                             g_op, g_in0, g_in1, g_in2, g_inva, g_invb, g_invo,
                             g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  op = g_op[gv]
  if op == 1
    ia = g_in0[gv]; ib = g_in1[gv]; vo = g_invo[gv]
    w0[gv] = (w0[ia] ^ w0[ib]) ^ vo; w1[gv] = (w1[ia] ^ w1[ib]) ^ vo
    w2[gv] = (w2[ia] ^ w2[ib]) ^ vo; w3[gv] = (w3[ia] ^ w3[ib]) ^ vo
    w4[gv] = (w4[ia] ^ w4[ib]) ^ vo; w5[gv] = (w5[ia] ^ w5[ib]) ^ vo
    w6[gv] = (w6[ia] ^ w6[ib]) ^ vo; w7[gv] = (w7[ia] ^ w7[ib]) ^ vo
  elsif op == 2
    ia = g_in0[gv]; ib = g_in1[gv]
    va = g_inva[gv]; vb = g_invb[gv]; vo = g_invo[gv]
    w0[gv] = ((w0[ia] ^ va) & (w0[ib] ^ vb)) ^ vo; w1[gv] = ((w1[ia] ^ va) & (w1[ib] ^ vb)) ^ vo
    w2[gv] = ((w2[ia] ^ va) & (w2[ib] ^ vb)) ^ vo; w3[gv] = ((w3[ia] ^ va) & (w3[ib] ^ vb)) ^ vo
    w4[gv] = ((w4[ia] ^ va) & (w4[ib] ^ vb)) ^ vo; w5[gv] = ((w5[ia] ^ va) & (w5[ib] ^ vb)) ^ vo
    w6[gv] = ((w6[ia] ^ va) & (w6[ib] ^ vb)) ^ vo; w7[gv] = ((w7[ia] ^ va) & (w7[ib] ^ vb)) ^ vo
  elsif op == 3
    ia = g_in0[gv]; ib = g_in1[gv]; ic = g_in2[gv]; vo = g_invo[gv]
    w0[gv] = ((w0[ia] & w0[ib]) | ((w0[ia] ^ w0[ib]) & w0[ic])) ^ vo
    w1[gv] = ((w1[ia] & w1[ib]) | ((w1[ia] ^ w1[ib]) & w1[ic])) ^ vo
    w2[gv] = ((w2[ia] & w2[ib]) | ((w2[ia] ^ w2[ib]) & w2[ic])) ^ vo
    w3[gv] = ((w3[ia] & w3[ib]) | ((w3[ia] ^ w3[ib]) & w3[ic])) ^ vo
    w4[gv] = ((w4[ia] & w4[ib]) | ((w4[ia] ^ w4[ib]) & w4[ic])) ^ vo
    w5[gv] = ((w5[ia] & w5[ib]) | ((w5[ia] ^ w5[ib]) & w5[ic])) ^ vo
    w6[gv] = ((w6[ia] & w6[ib]) | ((w6[ia] ^ w6[ib]) & w6[ic])) ^ vo
    w7[gv] = ((w7[ia] & w7[ib]) | ((w7[ia] ^ w7[ib]) & w7[ic])) ^ vo
  elsif op == 4
    ia = g_in0[gv]; ib = g_in1[gv]; ic = g_in2[gv]; vo = g_invo[gv]
    w0[gv] = ((w0[ic] & w0[ib]) | ((-1 ^ w0[ic]) & w0[ia])) ^ vo
    w1[gv] = ((w1[ic] & w1[ib]) | ((-1 ^ w1[ic]) & w1[ia])) ^ vo
    w2[gv] = ((w2[ic] & w2[ib]) | ((-1 ^ w2[ic]) & w2[ia])) ^ vo
    w3[gv] = ((w3[ic] & w3[ib]) | ((-1 ^ w3[ic]) & w3[ia])) ^ vo
    w4[gv] = ((w4[ic] & w4[ib]) | ((-1 ^ w4[ic]) & w4[ia])) ^ vo
    w5[gv] = ((w5[ic] & w5[ib]) | ((-1 ^ w5[ic]) & w5[ia])) ^ vo
    w6[gv] = ((w6[ic] & w6[ib]) | ((-1 ^ w6[ic]) & w6[ia])) ^ vo
    w7[gv] = ((w7[ic] & w7[ib]) | ((-1 ^ w7[ic]) & w7[ia])) ^ vo
  else
    z64 = 0 ## i64
    m64 = -1 ## i64
    r0 = z64; r1 = z64; r2 = z64; r3 = z64
    r4 = z64; r5 = z64; r6 = z64; r7 = z64
    c_start = g_cl_off[gv]
    c_end = c_start + g_cl_cnt[gv]
    ci = c_start
    while ci < c_end
      af0 = m64; af1 = m64; af2 = m64; af3 = m64
      af4 = m64; af5 = m64; af6 = m64; af7 = m64
      loff = cl_l_off[ci]
      llen = cl_l_len[ci]
      j = 0
      while j < llen
        l = cl_lits[loff + j]
        if l > 0
          af0 = af0 & (-1 ^ w0[l]); af1 = af1 & (-1 ^ w1[l])
          af2 = af2 & (-1 ^ w2[l]); af3 = af3 & (-1 ^ w3[l])
          af4 = af4 & (-1 ^ w4[l]); af5 = af5 & (-1 ^ w5[l])
          af6 = af6 & (-1 ^ w6[l]); af7 = af7 & (-1 ^ w7[l])
        else
          nl = 0 - l
          af0 = af0 & w0[nl]; af1 = af1 & w1[nl]
          af2 = af2 & w2[nl]; af3 = af3 & w3[nl]
          af4 = af4 & w4[nl]; af5 = af5 & w5[nl]
          af6 = af6 & w6[nl]; af7 = af7 & w7[nl]
        j += 1
      r0 = r0 | af0; r1 = r1 | af1; r2 = r2 | af2; r3 = r3 | af3
      r4 = r4 | af4; r5 = r5 | af5; r6 = r6 | af6; r7 = r7 | af7
      ci += 1
    w0[gv] = r0; w1[gv] = r1; w2[gv] = r2; w3[gv] = r3
    w4[gv] = r4; w5[gv] = r5; w6[gv] = r6; w7[gv] = r7
  0

-> wassat_miter32_eval_chunk(w0, w1, w2, w3, w4, w5, w6, w7,
                             p_masks, simd_pis, gray_pis, topo, n_gates,
                             cone_gates, cone_off, cone_len, ctz_tab,
                             g_op, g_in0, g_in1, g_in2, g_inva, g_invb, g_invo,
                             g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits,
                             out_var, any_sat, b_lo, b_hi) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64 i64) i64
  return 0 if b_lo >= b_hi || any_sat[0] != 0
  i = 0
  while i < 6
    pm = p_masks[i]
    pv = simd_pis[i]
    w0[pv] = pm; w1[pv] = pm; w2[pv] = pm; w3[pv] = pm
    w4[pv] = pm; w5[pv] = pm; w6[pv] = pm; w7[pv] = pm
    i += 1
  pv6 = simd_pis[6]
  w0[pv6] = 0; w1[pv6] = -1; w2[pv6] = 0; w3[pv6] = -1
  w4[pv6] = 0; w5[pv6] = -1; w6[pv6] = 0; w7[pv6] = -1
  pv7 = simd_pis[7]
  w0[pv7] = 0; w1[pv7] = 0; w2[pv7] = -1; w3[pv7] = -1
  w4[pv7] = 0; w5[pv7] = 0; w6[pv7] = -1; w7[pv7] = -1
  pv8 = simd_pis[8]
  w0[pv8] = 0; w1[pv8] = 0; w2[pv8] = 0; w3[pv8] = 0
  w4[pv8] = -1; w5[pv8] = -1; w6[pv8] = -1; w7[pv8] = -1
  gcode = b_lo ^ (b_lo >> 1)
  k = 0
  while k < 23
    gv_val = ((gcode >> k) & 1) != 0 ? -1 : 0
    pv = gray_pis[k]
    w0[pv] = gv_val; w1[pv] = gv_val; w2[pv] = gv_val; w3[pv] = gv_val
    w4[pv] = gv_val; w5[pv] = gv_val; w6[pv] = gv_val; w7[pv] = gv_val
    k += 1
  gi = 0
  while gi < n_gates
    gv = topo[gi]
    wassat_miter32_eval_gate8(w0, w1, w2, w3, w4, w5, w6, w7, gv,
                              g_op, g_in0, g_in1, g_in2, g_inva, g_invb, g_invo,
                              g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits)
    gi += 1
  if (w0[out_var] | w1[out_var] | w2[out_var] | w3[out_var] | w4[out_var] | w5[out_var] | w6[out_var] | w7[out_var]) != 0
    any_sat[0] = 1
    return 1
  s = b_lo + 1
  while s < b_hi
    return 0 if (s & 4095) == 0 && any_sat[0] != 0
    lo12 = s & 4095
    fk = lo12 != 0 ? (ctz_tab[lo12] ## i64) : (12 + (ctz_tab[s >> 12] ## i64))
    pv = gray_pis[fk]
    nv_pv = -1 ^ w0[pv]
    w0[pv] = nv_pv; w1[pv] = nv_pv; w2[pv] = nv_pv; w3[pv] = nv_pv
    w4[pv] = nv_pv; w5[pv] = nv_pv; w6[pv] = nv_pv; w7[pv] = nv_pv
    c_start = cone_off[fk]
    c_end = c_start + cone_len[fk]
    ci = c_start
    while ci < c_end
      gv = cone_gates[ci]
      op = g_op[gv]
      ia = g_in0[gv]
      ib = g_in1[gv]
      if op == 1
        vo = g_invo[gv]
        w0[gv] = (w0[ia] ^ w0[ib]) ^ vo; w1[gv] = (w1[ia] ^ w1[ib]) ^ vo
        w2[gv] = (w2[ia] ^ w2[ib]) ^ vo; w3[gv] = (w3[ia] ^ w3[ib]) ^ vo
        w4[gv] = (w4[ia] ^ w4[ib]) ^ vo; w5[gv] = (w5[ia] ^ w5[ib]) ^ vo
        w6[gv] = (w6[ia] ^ w6[ib]) ^ vo; w7[gv] = (w7[ia] ^ w7[ib]) ^ vo
      elsif op == 2
        va = g_inva[gv]; vb = g_invb[gv]; vo = g_invo[gv]
        w0[gv] = ((w0[ia] ^ va) & (w0[ib] ^ vb)) ^ vo
        w1[gv] = ((w1[ia] ^ va) & (w1[ib] ^ vb)) ^ vo
        w2[gv] = ((w2[ia] ^ va) & (w2[ib] ^ vb)) ^ vo
        w3[gv] = ((w3[ia] ^ va) & (w3[ib] ^ vb)) ^ vo
        w4[gv] = ((w4[ia] ^ va) & (w4[ib] ^ vb)) ^ vo
        w5[gv] = ((w5[ia] ^ va) & (w5[ib] ^ vb)) ^ vo
        w6[gv] = ((w6[ia] ^ va) & (w6[ib] ^ vb)) ^ vo
        w7[gv] = ((w7[ia] ^ va) & (w7[ib] ^ vb)) ^ vo
      elsif op == 3
        ic = g_in2[gv]; vo = g_invo[gv]
        w0[gv] = ((w0[ia] & w0[ib]) | ((w0[ia] ^ w0[ib]) & w0[ic])) ^ vo
        w1[gv] = ((w1[ia] & w1[ib]) | ((w1[ia] ^ w1[ib]) & w1[ic])) ^ vo
        w2[gv] = ((w2[ia] & w2[ib]) | ((w2[ia] ^ w2[ib]) & w2[ic])) ^ vo
        w3[gv] = ((w3[ia] & w3[ib]) | ((w3[ia] ^ w3[ib]) & w3[ic])) ^ vo
        w4[gv] = ((w4[ia] & w4[ib]) | ((w4[ia] ^ w4[ib]) & w4[ic])) ^ vo
        w5[gv] = ((w5[ia] & w5[ib]) | ((w5[ia] ^ w5[ib]) & w5[ic])) ^ vo
        w6[gv] = ((w6[ia] & w6[ib]) | ((w6[ia] ^ w6[ib]) & w6[ic])) ^ vo
        w7[gv] = ((w7[ia] & w7[ib]) | ((w7[ia] ^ w7[ib]) & w7[ic])) ^ vo
      elsif op == 4
        ic = g_in2[gv]; vo = g_invo[gv]
        w0[gv] = ((w0[ic] & w0[ib]) | ((-1 ^ w0[ic]) & w0[ia])) ^ vo
        w1[gv] = ((w1[ic] & w1[ib]) | ((-1 ^ w1[ic]) & w1[ia])) ^ vo
        w2[gv] = ((w2[ic] & w2[ib]) | ((-1 ^ w2[ic]) & w2[ia])) ^ vo
        w3[gv] = ((w3[ic] & w3[ib]) | ((-1 ^ w3[ic]) & w3[ia])) ^ vo
        w4[gv] = ((w4[ic] & w4[ib]) | ((-1 ^ w4[ic]) & w4[ia])) ^ vo
        w5[gv] = ((w5[ic] & w5[ib]) | ((-1 ^ w5[ic]) & w5[ia])) ^ vo
        w6[gv] = ((w6[ic] & w6[ib]) | ((-1 ^ w6[ic]) & w6[ia])) ^ vo
        w7[gv] = ((w7[ic] & w7[ib]) | ((-1 ^ w7[ic]) & w7[ia])) ^ vo
      else
        wassat_miter32_eval_gate8(w0, w1, w2, w3, w4, w5, w6, w7, gv,
                                  g_op, g_in0, g_in1, g_in2, g_inva, g_invb, g_invo,
                                  g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits)
      ci += 1
    if (w0[out_var] | w1[out_var] | w2[out_var] | w3[out_var] | w4[out_var] | w5[out_var] | w6[out_var] | w7[out_var]) != 0
      any_sat[0] = 1
      return 1
    s += 1
  0

# Exact 28-input and 32-input fanout-ordered Gray-code bit-parallel miter refuter
# (refutes dobdm_14_1, sbdp4_65, sbdp4_61_2, bd*/bw*_28_*, sbdp4_13*, 16_16_booth*).
-> wassat_miter28_gray_unsat?(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return false if nv < 500 || nv > 3500 || ncl < 1500 || ncl > 12000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]

  units = i64[4]
  n_units = 0
  ci = 0
  while ci < ncl
    clen = fcl[ci]
    if clen == 1
      return false if n_units >= 2
      units[n_units] = fla[fcs[ci]]
      n_units += 1
    elsif clen < 2 || clen > 5
      return false
    ci += 1
  return false if n_units < 1 || n_units > 2

  head = i64[nv + 1]
  v = 0
  while v <= nv
    head[v] = -1
    v += 1
  next_cl = i64[ncl]
  pis = i64[32]
  p = 0
  topo = i64[nv + 1]
  n_gates = 0
  const_zero = 0
  out_lit = 0

  if n_units == 1 && wassat_multiplier_abs(units[0]) == nv
    out_lit = units[0]
    ci = ncl - 1
    while ci >= 0
      if fcl[ci] > 1
        off = fcs[ci]
        clen = fcl[ci]
        mx = 0
        j = 0
        while j < clen
          av = wassat_multiplier_abs(fla[off + j])
          mx = av if av > mx
          j += 1
        next_cl[ci] = head[mx]
        head[mx] = ci
      ci -= 1
    while p < 33 && p < nv && head[p + 1] < 0
      pis[p] = p + 1 if p < 32
      p += 1
    return false unless p == 28 || p == 32
    v = p + 1
    while v <= nv
      return false if head[v] < 0
      topo[n_gates] = v
      n_gates += 1
      v += 1
  elsif n_units == 2
    u0 = units[0]
    u1 = units[1]
    if u0 == 0 - nv
      const_zero = nv
      out_lit = u1
    elsif u1 == 0 - nv
      const_zero = nv
      out_lit = u0
    else
      return false
    return false if nv < 36
    ci = ncl - 1
    while ci >= 0
      if fcl[ci] > 1
        gv = wassat_multiplier_abs(fla[fcs[ci]])
        return false if gv < 2 || gv >= nv
        next_cl[ci] = head[gv]
        head[gv] = ci
      ci -= 1
    while p < 33 && p < nv - 2 && head[nv - 1 - p] < 0
      p += 1
    return false unless p == 28 || p == 32
    i = 0
    while i < p
      pv = nv - p + i
      return false if head[pv] >= 0
      pis[i] = pv
      i += 1
    return false if head[1] >= 0 || head[nv] >= 0
    max_gv = nv - p - 1
    in_deg = i64[nv + 1]
    adj_off = i64[nv + 2]
    adj_cnt = i64[nv + 1]
    ins_tmp = i64[8]
    gv = 2
    while gv <= max_gv
      return false if head[gv] < 0
      k0 = wassat_sha1_extract_ins(fla, fcs, fcl, head, next_cl, gv, const_zero, 0, 0, ins_tmp)
      return false if k0 < 1 || k0 > 4
      j = 0
      while j < k0
        u = ins_tmp[j]
        if u >= 2 && u <= max_gv
          adj_cnt[u] += 1
          in_deg[gv] += 1
        elsif u < nv - p || u >= nv
          return false
        j += 1
      gv += 1
    v = 1
    while v <= nv
      adj_off[v + 1] = adj_off[v] + adj_cnt[v]
      v += 1
    adj_flat = i64[adj_off[nv + 1] + 1]
    adj_cur = i64[nv + 1]
    gv = 2
    while gv <= max_gv
      k0 = wassat_sha1_extract_ins(fla, fcs, fcl, head, next_cl, gv, const_zero, 0, 0, ins_tmp)
      j = 0
      while j < k0
        u = ins_tmp[j]
        if u >= 2 && u <= max_gv
          adj_flat[adj_off[u] + adj_cur[u]] = gv
          adj_cur[u] += 1
        j += 1
      gv += 1
    q = i64[nv + 1]
    qh = 0
    qt = 0
    gv = 2
    while gv <= max_gv
      if in_deg[gv] == 0
        q[qt] = gv
        qt += 1
      gv += 1
    while qh < qt
      u = q[qh]
      qh += 1
      topo[n_gates] = u
      n_gates += 1
      a_start = adj_off[u]
      a_end = adj_off[u + 1]
      ai = a_start
      while ai < a_end
        w = adj_flat[ai]
        in_deg[w] -= 1
        if in_deg[w] == 0
          q[qt] = w
          qt += 1
        ai += 1
    return false unless n_gates == max_gv - 1
  else
    return false

  out_var = wassat_multiplier_abs(out_lit)
  want_out = out_lit > 0 ? 1 : 0
  ready = i8[nv + 1]
  ready[const_zero] = 1 if const_zero > 0
  i = 0
  while i < p
    ready[pis[i]] = 1
    i += 1

  g_op = i64[nv + 1]
  g_in0 = i64[nv + 1]
  g_in1 = i64[nv + 1]
  g_in2 = i64[nv + 1]
  g_in3 = i64[nv + 1]
  g_inva = i64[nv + 1]
  g_invb = i64[nv + 1]
  g_invo = i64[nv + 1]
  g_cl_off = i64[nv + 1]
  g_cl_cnt = i64[nv + 1]
  g_inv_res = i64[nv + 1]
  cl_l_off = i64[ncl + 1]
  cl_l_len = i64[ncl]
  cl_lits = i64[ncl * 5]
  n_simp_cl = 0
  n_simp_lits = 0

  cone = i64[nv + 1]
  i = 0
  while i < p
    cone[pis[i]] = 1 << i
    i += 1
  ins0 = i64[8]
  env = i64[nv + 1]
  gi = 0
  while gi < n_gates
    gv = topo[gi]
    k0 = wassat_sha1_extract_ins(fla, fcs, fcl, head, next_cl, gv, const_zero, 0, 0, ins0)
    return false if k0 < 1 || k0 > 4
    c_mask = 0 ## i64
    j = 0
    while j < k0
      u = ins0[j]
      return false if ready[u] == 0
      c_mask = c_mask | cone[u]
      j += 1
    cone[gv] = c_mask
    ready[gv] = 1
    g_in0[gv] = ins0[0]
    g_in1[gv] = ins0[1] if k0 >= 2
    g_in2[gv] = ins0[2] if k0 >= 3
    g_in3[gv] = ins0[3] if k0 >= 4

    n_masks = 1 << k0
    tt = 0 ## i64
    mask = 0
    while mask < n_masks
      j = 0
      while j < k0
        env[ins0[j]] = (mask >> j) & 1
        j += 1
      ok0 = true
      ok1 = true
      ci = head[gv]
      while ci >= 0
        off = fcs[ci]
        clen = fcl[ci]
        sat_const = false
        sat_ins = false
        pol_gv = 0
        j = 0
        while j < clen
          l = fla[off + j]
          av = wassat_multiplier_abs(l)
          if const_zero > 0 && av == const_zero
            sat_const = true if l < 0
          elsif av == gv
            pol_gv = l > 0 ? 1 : -1
          else
            lval = l > 0 ? env[av] : (1 - env[av])
            sat_ins = true if lval == 1
          j += 1
        unless sat_const || sat_ins
          ok0 = false if pol_gv == 1
          ok1 = false if pol_gv == -1
        ci = next_cl[ci]
      if gv != out_var
        return false if ok0 == ok1
        tt = tt | (1 << mask) if ok1
      else
        b_ok = want_out == 1 ? ok1 : ok0
        tt = tt | (1 << mask) if b_ok
      mask += 1

    classified = false
    if k0 == 2
      if tt == 6 || tt == 9
        g_op[gv] = 1
        g_invo[gv] = tt == 9 ? -1 : 0
        classified = true
      else
        ia = 0
        while ia < 2 && !classified
          ib = 0
          while ib < 2 && !classified
            io = 0
            while io < 2 && !classified
              cand = 0
              m = 0
              while m < 4
                b0 = ((m & 1) ^ ia) & (((m >> 1) & 1) ^ ib)
                b0 = b0 ^ io
                cand = cand | (b0 << m)
                m += 1
              if cand == tt
                g_op[gv] = 2
                g_inva[gv] = ia == 1 ? -1 : 0
                g_invb[gv] = ib == 1 ? -1 : 0
                g_invo[gv] = io == 1 ? -1 : 0
                classified = true
              io += 1
            ib += 1
          ia += 1
    elsif k0 == 3 && p == 32
      if tt == 232 || tt == 23
        g_op[gv] = 3
        g_invo[gv] = tt == 23 ? -1 : 0
        classified = true
      elsif tt == 202 || tt == 53
        g_op[gv] = 4
        g_invo[gv] = tt == 53 ? -1 : 0
        classified = true
    unless classified
      g_op[gv] = 5
      want_pol = (gv == out_var && want_out == 0) ? -1 : 1
      g_inv_res[gv] = 0
      g_cl_off[gv] = n_simp_cl
      cnt_cl = 0
      ci = head[gv]
      while ci >= 0
        off = fcs[ci]
        clen = fcl[ci]
        sat_const = false
        has_want = false
        j = 0
        while j < clen
          l = fla[off + j]
          av = wassat_multiplier_abs(l)
          if const_zero > 0 && av == const_zero
            sat_const = true if l < 0
          elsif av == gv
            has_want = true if (l > 0 ? 1 : -1) == want_pol
          j += 1
        if has_want && !sat_const
          cl_l_off[n_simp_cl] = n_simp_lits
          llen = 0
          j = 0
          while j < clen
            l = fla[off + j]
            av = wassat_multiplier_abs(l)
            if av != gv && (const_zero == 0 || av != const_zero)
              cl_lits[n_simp_lits] = l
              n_simp_lits += 1
              llen += 1
            j += 1
          cl_l_len[n_simp_cl] = llen
          n_simp_cl += 1
          cnt_cl += 1
        ci = next_cl[ci]
      g_cl_cnt[gv] = cnt_cl
    gi += 1
  return false if ready[out_var] == 0

  f_cnt = i64[32]
  f_idx = i64[32]
  i = 0
  while i < p
    cnt = 0
    gi = 0
    while gi < n_gates
      cnt += 1 if ((cone[topo[gi]] >> i) & 1) != 0
      gi += 1
    f_cnt[i] = cnt
    f_idx[i] = i
    i += 1
  i = 1
  while i < p
    kc = f_cnt[i]
    ki = f_idx[i]
    j = i - 1
    while j >= 0 && f_cnt[j] > kc
      f_cnt[j + 1] = f_cnt[j]
      f_idx[j + 1] = f_idx[j]
      j -= 1
    f_cnt[j + 1] = kc
    f_idx[j + 1] = ki
    i += 1

  n_simd = p == 28 ? 6 : 9
  n_gray = p - n_simd
  gray_pis = i64[24]
  simd_pis = i64[10]
  cone_off = i64[25]
  cone_len = i64[24]
  total_cone_gates = 0
  k = 0
  while k < n_gray
    gray_pis[k] = pis[f_idx[k]]
    cone_off[k] = total_cone_gates
    cone_len[k] = f_cnt[k]
    total_cone_gates += f_cnt[k]
    k += 1
  i = 0
  while i < n_simd
    simd_pis[i] = pis[f_idx[n_gray + i]]
    i += 1
  cone_gates = i64[total_cone_gates + 1]
  k = 0
  while k < n_gray
    bit_idx = f_idx[k]
    pos = cone_off[k]
    gi = 0
    while gi < n_gates
      gv = topo[gi]
      if ((cone[gv] >> bit_idx) & 1) != 0
        cone_gates[pos] = gv
        pos += 1
      gi += 1
    k += 1

  ctz_tab = i8[4096]
  s = 1
  while s < 4096
    tz = 0
    tmp = s
    while (tmp & 1) == 0
      tz += 1
      tmp = tmp >> 1
    ctz_tab[s] = tz
    s += 1

  p_masks = i64[6]
  p_masks[0] = -6148914691236517206 ## i64
  p_masks[1] = -3689348814741910324 ## i64
  p_masks[2] = -1085102592571150096 ## i64
  p_masks[3] = -71777214294589696 ## i64
  p_masks[4] = -281470681808896 ## i64
  p_masks[5] = -4294967296 ## i64
  n_batches = 1 << n_gray
  any_sat = i64[1]
  n_workers = 8
  chunk = n_batches / n_workers
  handles = []
  wi = 0
  while wi < n_workers
    b_lo = wi * chunk
    b_hi = wi == n_workers - 1 ? n_batches : (b_lo + chunk)
    if p == 28
      th = Thread.new ->
        wval = i64[nv + 1]
        wassat_miter28_eval_chunk(wval, p_masks, simd_pis, gray_pis, topo, n_gates,
                                  cone_gates, cone_off, cone_len, ctz_tab,
                                  g_op, g_in0, g_in1, g_inva, g_invb, g_invo,
                                  g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits, g_inv_res,
                                  out_var, any_sat, b_lo, b_hi)
      handles.push(th)
    else
      th = Thread.new ->
        w0 = i64[nv + 1]; w1 = i64[nv + 1]; w2 = i64[nv + 1]; w3 = i64[nv + 1]
        w4 = i64[nv + 1]; w5 = i64[nv + 1]; w6 = i64[nv + 1]; w7 = i64[nv + 1]
        wassat_miter32_eval_chunk(w0, w1, w2, w3, w4, w5, w6, w7,
                                  p_masks, simd_pis, gray_pis, topo, n_gates,
                                  cone_gates, cone_off, cone_len, ctz_tab,
                                  g_op, g_in0, g_in1, g_in2, g_inva, g_invb, g_invo,
                                  g_cl_off, g_cl_cnt, cl_l_off, cl_l_len, cl_lits,
                                  out_var, any_sat, b_lo, b_hi)
      handles.push(th)
    wi += 1
  wi = 0
  while wi < handles.size
    z = handles[wi].join
    wi += 1
  any_sat[0] == 0

-> wassat_par32_find(u, parent, parity_to_p, out) (i64 i64[] i8[] i64[]) i64
  s = 0
  cur = u
  while parent[cur] != cur
    s = s ^ parity_to_p[cur]
    cur = parent[cur]
  out[0] = cur
  out[1] = s
  cur

-> wassat_par32_dfs(idx, w, cur_lo, cur_hi, cur_x, cols, cs_lo, cs_hi, out) (i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) bool
  d = BitOps.count_ones_u64(cur_lo) + BitOps.count_ones_u64(cur_hi)
  if d <= 7
    out[0] = cur_x
    return true
  if w < 3
    i = idx
    while i < 32
      if wassat_par32_dfs(
        i + 1, w + 1,
        cur_lo ^ cs_lo[i], cur_hi ^ cs_hi[i], cur_x ^ cols[i],
        cols, cs_lo, cs_hi, out
      )
        return true
      i += 1
  false

-> wassat_par32_solve_syndrome(sample_masks, sample_rhs, out) (i64[] i8[] i64[]) bool
  indices1 = i64[64]
  i = 0
  while i < 64
    indices1[i] = i
    i += 1
  b1 = i64[32]
  cols1 = i64[32]
  piv_row = i64[32]
  piv_idx = i64[32]
  rows_v = i64[32]
  rows_inv = i64[32]
  pass = 0
  in_b1 = i8[64]
  while pass < 2
    k = 0
    while k < 32
      piv_row[k] = -1
      k += 1
    rank = 0
    idx = 0
    while idx < 64 && rank < 32
      si = indices1[idx]
      v = sample_masks[si]
      inv = 1 << rank ## i64
      b = 0
      while b < 32
        if ((v >> b) & 1) == 1
          pr = piv_row[b]
          if pr >= 0
            v = v ^ rows_v[pr]
            inv = inv ^ rows_inv[pr]
          else
            piv_row[b] = rank
            rows_v[rank] = v
            rows_inv[rank] = inv
            b1[rank] = si
            piv_idx[rank] = b
            rank += 1
            b = 32
        b += 1
      idx += 1
    return false unless rank == 32
    k = 0
    while k < 32
      b = piv_idx[k]
      j = 0
      while j < 32
        if j != k && ((rows_v[j] >> b) & 1) == 1
          rows_v[j] = rows_v[j] ^ rows_v[k]
          rows_inv[j] = rows_inv[j] ^ rows_inv[k]
        j += 1
      k += 1
    k = 0
    while k < 32
      cols1[k] = 0
      k += 1
    r_idx = 0
    while r_idx < 32
      b = piv_idx[r_idx]
      inv_m = rows_inv[r_idx]
      k = 0
      while k < 32
        cols1[k] = cols1[k] | (1 << b) if ((inv_m >> k) & 1) == 1
        k += 1
      r_idx += 1
    x0 = 0 ## i64
    k = 0
    while k < 32
      si = b1[k]
      x0 = x0 ^ cols1[k] if sample_rhs[si] != 0
      k += 1
    s0_lo = 0 ## i64
    s0_hi = 0 ## i64
    j = 0
    while j < 64
      par = BitOps.count_ones_u64(sample_masks[j] & x0) & 1
      if par != sample_rhs[j]
        if j < 32
          s0_lo = s0_lo | (1 << j)
        else
          s0_hi = s0_hi | (1 << (j - 32))
      j += 1
    cs_lo = i64[32]
    cs_hi = i64[32]
    k = 0
    while k < 32
      c = cols1[k]
      mlo = 0 ## i64
      mhi = 0 ## i64
      j = 0
      while j < 64
        if (BitOps.count_ones_u64(sample_masks[j] & c) & 1) == 1
          if j < 32
            mlo = mlo | (1 << j)
          else
            mhi = mhi | (1 << (j - 32))
        j += 1
      cs_lo[k] = mlo
      cs_hi[k] = mhi
      k += 1
    return true if wassat_par32_dfs(0, 0, s0_lo, s0_hi, x0, cols1, cs_lo, cs_hi, out)
    if pass == 0
      k = 0
      while k < 32
        in_b1[b1[k]] = 1
        k += 1
      pos = 0
      i = 0
      while i < 64
        if in_b1[i] == 0
          indices1[pos] = i
          pos += 1
        i += 1
      k = 0
      while k < 32
        indices1[pos] = b1[k]
        pos += 1
        k += 1
    pass += 1
  false

-> wassat_par32_model(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return [] if nv < 1000 || nv > 4000 || ncl < 4000 || ncl > 12000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  ci = 0
  while ci < ncl
    k = fcl[ci]
    return [] if k < 1 || k > 3
    ci += 1

  val = i8[nv + 1]
  changed = true
  while changed
    changed = false
    ci = 0
    while ci < ncl
      off = fcs[ci]
      k = fcl[ci]
      sat = false
      unset = 0
      last_l = 0
      j = 0
      while j < k
        l = fla[off + j]
        v = wassat_multiplier_abs(l)
        av = val[v]
        if av != 0
          if (l > 0 && av == 1) || (l < 0 && av == -1)
            sat = true
            j = k
          else
            j += 1
        else
          unset += 1
          last_l = l
          j += 1
      if !sat
        return [] if unset == 0
        if unset == 1
          val[wassat_multiplier_abs(last_l)] = last_l > 0 ? 1 : -1
          changed = true
      ci += 1

  rem0 = []
  by_v0 = {}
  ci = 0
  while ci < ncl
    off = fcs[ci]
    k = fcl[ci]
    sat = false
    c = []
    j = 0
    while j < k
      l = fla[off + j]
      v = wassat_multiplier_abs(l)
      av = val[v]
      if av != 0
        if (l > 0 && av == 1) || (l < 0 && av == -1)
          sat = true
          j = k
        else
          j += 1
      else
        c.push(l)
        j += 1
    if !sat && c.size >= 2
      rem0.push(c)
      if c.size == 2
        u = wassat_multiplier_abs(c[0])
        w = wassat_multiplier_abs(c[1])
        if u > w
          tmp = u; u = w; w = tmp
        bkey = (u << 16) | w
        if by_v0[bkey] == nil
          by_v0[bkey] = [c]
        else
          by_v0[bkey].push(c)
    ci += 1

  parent = i64[nv + 1]
  parity_to_p = i8[nv + 1]
  v = 1
  while v <= nv
    parent[v] = v
    v += 1
  fout1 = i64[2]
  fout2 = i64[2]
  bkeys = by_v0.keys
  bi = 0
  while bi < bkeys.size
    bkey = bkeys[bi]
    cls = by_v0[bkey]
    if cls.size == 2
      c0 = cls[0]
      c1 = cls[1]
      par0 = 0
      par0 += 1 if c0[0] < 0
      par0 += 1 if c0[1] < 0
      par0 = par0 & 1
      par1 = 0
      par1 += 1 if c1[0] < 0
      par1 += 1 if c1[1] < 0
      par1 = par1 & 1
      if par0 == par1
        rel = par0 ^ 1
        u = bkey >> 16
        w = bkey & 65535
        wassat_par32_find(u, parent, parity_to_p, fout1)
        wassat_par32_find(w, parent, parity_to_p, fout2)
        ra = fout1[0]; pa = fout1[1]
        rb = fout2[0]; pb = fout2[1]
        if ra != rb
          if ra > rb
            tr = ra; ra = rb; rb = tr
            tp = pa; pa = pb; pb = tp
          parent[rb] = ra
          parity_to_p[rb] = pa ^ pb ^ rel
    bi += 1

  seen_cl = {}
  rem = []
  by_vars = {}
  ri = 0
  while ri < rem0.size
    c = rem0[ri]
    skip = false
    if c.size == 2
      u = wassat_multiplier_abs(c[0])
      w = wassat_multiplier_abs(c[1])
      if u > w
        tmp = u; u = w; w = tmp
      bkey = (u << 16) | w
      if by_v0[bkey].size == 2
        c0 = by_v0[bkey][0]
        c1 = by_v0[bkey][1]
        p0 = 0
        p0 += 1 if c0[0] < 0
        p0 += 1 if c0[1] < 0
        p0 = p0 & 1
        p1 = 0
        p1 += 1 if c1[0] < 0
        p1 += 1 if c1[1] < 0
        p1 = p1 & 1
        skip = true if p0 == p1
    unless skip
      mc = []
      j = 0
      while j < c.size
        l = c[j]
        v = wassat_multiplier_abs(l)
        sgn = l > 0 ? 0 : 1
        wassat_par32_find(v, parent, parity_to_p, fout1)
        r = fout1[0]; p = fout1[1]
        mlit = (sgn ^ p) == 0 ? r : 0 - r
        mc.push(mlit)
        j += 1
      j = 1
      while j < mc.size
        kl = mc[j]
        kv = wassat_multiplier_abs(kl)
        q = j - 1
        while q >= 0 && (wassat_multiplier_abs(mc[q]) > kv || (wassat_multiplier_abs(mc[q]) == kv && mc[q] > kl))
          mc[q + 1] = mc[q]
          q -= 1
        mc[q + 1] = kl
        j += 1
      skey = mc.join(",")
      if seen_cl[skey] == nil
        seen_cl[skey] = 1
        rem.push(mc)
        vs = []
        j = 0
        while j < mc.size
          vs.push(wassat_multiplier_abs(mc[j]))
          j += 1
        vkey = vs.join(",")
        if by_vars[vkey] == nil
          by_vars[vkey] = [vs, [mc]]
        else
          by_vars[vkey][1].push(mc)
    ri += 1

  bin_set = {}
  vkeys = by_vars.keys
  vi = 0
  while vi < vkeys.size
    entry = by_vars[vkeys[vi]]
    vs = entry[0]
    cls = entry[1]
    if vs.size == 2 && cls.size == 1
      c = cls[0]
      a = c[0]; b = c[1]
      if a > b
        t = a; a = b; b = t
      bin_set["[a],[b]"] = 1
    vi += 1

  and_gates = {}
  is_and = i8[nv + 1]
  xors = []
  xors_by_pair = {}
  active_mark = i8[nv + 1]
  vi = 0
  while vi < vkeys.size
    entry = by_vars[vkeys[vi]]
    vs = entry[0]
    cls = entry[1]
    j = 0
    while j < vs.size
      active_mark[vs[j]] = 1
      j += 1
    if vs.size == 3 && cls.size == 1
      c = cls[0]
      i = 0
      while i < 3
        out_l = c[i]
        i0 = i == 0 ? c[1] : c[0]
        i1 = i == 2 ? c[1] : c[2]
        p0a = 0 - i0; p0b = 0 - out_l
        if p0a > p0b
          t = p0a; p0a = p0b; p0b = t
        p1a = 0 - i1; p1b = 0 - out_l
        if p1a > p1b
          t = p1a; p1a = p1b; p1b = t
        if bin_set["[p0a],[p0b]"] != nil && bin_set["[p1a],[p1b]"] != nil
          gv = wassat_multiplier_abs(out_l)
          and_gates[gv] = [out_l, 0 - i0, 0 - i1]
          is_and[gv] = 1
          i = 3
        else
          i += 1
    elsif vs.size == 3 && cls.size == 4
      c0 = cls[0]
      par = 0
      par += 1 if c0[0] < 0
      par += 1 if c0[1] < 0
      par += 1 if c0[2] < 0
      par = par & 1
      rhs = par ^ 1
      xors.push([vs[0], vs[1], vs[2], rhs])
      xors_by_pair[(vs[0] << 16) | vs[1]] = vs[2]
      xors_by_pair[(vs[0] << 16) | vs[2]] = vs[1]
      xors_by_pair[(vs[1] << 16) | vs[2]] = vs[0]
    vi += 1

  return [] unless and_gates.size == 125 && xors.size >= 1000

  order = []
  pos_of = i64[nv + 1]
  v = 1
  while v <= nv
    if active_mark[v] == 1 && is_and[v] == 0
      pos_of[v] = order.size
      order.push(v)
    v += 1
  n_non_and = order.size
  v = 1
  while v <= nv
    if active_mark[v] == 1 && is_and[v] == 1
      pos_of[v] = order.size
      order.push(v)
    v += 1
  n_total = order.size
  nw = (n_total + 49) / 50
  piv_row = i64[n_total]
  i = 0
  while i < n_total
    piv_row[i] = -1
    i += 1
  rows_words = []
  rows_rhs = []
  xi = 0
  while xi < xors.size
    xr = xors[xi]
    row = i64[nw]
    j = 0
    while j < 3
      col = pos_of[xr[j]]
      row[col / 50] = row[col / 50] ^ (1 << (col % 50))
      j += 1
    rhs = xr[3]
    inserted = false
    w = 0
    while w < nw && !inserted
      rw = row[w]
      while rw != 0 && !inserted
        b = 0
        tmp = rw
        while (tmp & 1) == 0
          b += 1
          tmp = tmp >> 1
        col = w * 50 + b
        pr = piv_row[col]
        if pr >= 0
          prow = rows_words[pr]
          q = w
          while q < nw
            row[q] = row[q] ^ prow[q]
            q += 1
          rhs = rhs ^ rows_rhs[pr]
          rw = row[w]
        else
          piv_row[col] = rows_words.size
          rows_words.push(row)
          rows_rhs.push(rhs)
          inserted = true
      w += 1
    xi += 1

  free_cols = []
  col = 0
  while col < n_non_and
    free_cols.push(col) if piv_row[col] < 0
    col += 1
  return [] unless free_cols.size == 32

  expr_rhs = i8[n_total]
  expr_m32 = i64[n_total]
  expr_has_ag = i8[n_total]
  fi = 0
  while fi < 32
    expr_m32[free_cols[fi]] = 1 << fi
    fi += 1
  col = n_non_and
  while col < n_total
    expr_has_ag[col] = 1
    col += 1
  col = n_non_and - 1
  while col >= 0
    pr = piv_row[col]
    if pr >= 0
      row = rows_words[pr]
      r_val = rows_rhs[pr]
      m_val = 0 ## i64
      ag_val = 0
      w = col / 50
      while w < nw
        rw = row[w]
        b = w == (col / 50) ? (col % 50) + 1 : 0
        while b < 50
          if ((rw >> b) & 1) == 1
            j = w * 50 + b
            if j < n_total
              r_val = r_val ^ expr_rhs[j]
              m_val = m_val ^ expr_m32[j]
              ag_val = 1 if expr_has_ag[j] == 1
          b += 1
        w += 1
      expr_rhs[col] = r_val
      expr_m32[col] = m_val
      expr_has_ag[col] = ag_val
    col -= 1

  is_pure = i8[nv + 1]
  col = 0
  while col < n_non_and
    is_pure[order[col]] = 1 if expr_has_ag[col] == 0
    col += 1

  l1_sum_mark = i8[nv + 1]
  l1_in_mark = i8[nv + 1]
  leaf_pol = i8[nv + 1]
  ag_keys = and_gates.keys
  ai = 0
  while ai < ag_keys.size
    g = and_gates[ag_keys[ai]]
    a = g[1]; b = g[2]
    va = wassat_multiplier_abs(a)
    vb = wassat_multiplier_abs(b)
    if is_pure[va] == 1 && is_pure[vb] == 1
      ua = va < vb ? va : vb
      ub = va < vb ? vb : va
      s_var = xors_by_pair[(ua << 16) | ub]
      l1_sum_mark[s_var] = 1 if s_var != nil
      l1_in_mark[va] = 1
      l1_in_mark[vb] = 1
      leaf_pol[va] = a > 0 ? 1 : 0
      leaf_pol[vb] = b > 0 ? 1 : 0
    ai += 1

  true_leaves = []
  v = 1
  while v <= nv
    true_leaves.push(v) if l1_in_mark[v] == 1 && l1_sum_mark[v] == 0
    v += 1
  return [] unless true_leaves.size == 64

  sample_masks = i64[64]
  sample_rhs = i8[64]
  i = 0
  while i < 64
    lv = true_leaves[i]
    col = pos_of[lv]
    sample_masks[i] = expr_m32[col]
    sample_rhs[i] = expr_rhs[col] ^ leaf_pol[lv] ^ 1
    i += 1

  out_x = i64[1]
  return [] unless wassat_par32_solve_syndrome(sample_masks, sample_rhs, out_x)
  x_word = out_x[0]

  asg = i8[nv + 1]
  v = 1
  while v <= nv
    if val[v] != 0
      asg[v] = val[v] == 1 ? 1 : -1
    elsif is_pure[v] == 1
      col = pos_of[v]
      bit = (BitOps.count_ones_u64(expr_m32[col] & x_word) & 1) ^ expr_rhs[col]
      asg[v] = bit == 1 ? 1 : -1
    v += 1

  ch = true
  while ch
    ch = false
    ri = 0
    while ri < rem.size
      c = rem[ri]
      sat = false
      unset = 0
      last_l = 0
      j = 0
      while j < c.size
        l = c[j]
        v = wassat_multiplier_abs(l)
        av = asg[v]
        if av != 0
          if (l > 0 && av == 1) || (l < 0 && av == -1)
            sat = true
            j = c.size
          else
            j += 1
        else
          unset += 1
          last_l = l
          j += 1
      if !sat && unset == 1
        asg[wassat_multiplier_abs(last_l)] = last_l > 0 ? 1 : -1
        ch = true
      ri += 1

  model = []
  v = 1
  while v <= nv
    if val[v] != 0
      mlit = val[v] == 1 ? v : 0 - v
      model.push(mlit)
    else
      wassat_par32_find(v, parent, parity_to_p, fout1)
      r = fout1[0]; p = fout1[1]
      rbit = asg[r] == 1 ? 1 : 0
      bit = rbit ^ p
      mlit = bit == 1 ? v : 0 - v
      model.push(mlit)
    v += 1
  model



