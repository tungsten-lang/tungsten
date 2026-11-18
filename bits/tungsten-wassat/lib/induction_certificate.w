# A pair of literals can name a conjunction. If assuming that conjunction
# forces one of two previously excluded predecessor conjunctions, the new
# pair is excluded too. Each step below is an original-variable RUP clause.
use solver
use preprocess

-> wassat_induction_pair(a, b, nv)
  lo = a < b ? a : b
  hi = a < b ? b : a
  (lo+nv)*(2*nv+1)+hi+nv

-> wassat_induction_rup(out, lits)
  out.append("rup")
  lits.each -> (lit)
    if lit < 0
      out.append(" 1 ~x[0-lit]")
    else
      out.append(" 1 x[lit]")
  out.append(" >= 1 ;\n")

# With guard G false, each residual is a unit or a binary. If (p OR r) and
# (p OR s) occur, the proved clause (-r OR -s) forces p under the guard.
-> wassat_induction_units(residuals, known, buckets, nv)
  units = []
  i = 0
  while i < residuals.size
    row = residuals[i]
    if row.size == 1
      units.push([row[0], -1])
    else
      j = 0
      while j < i
        other = residuals[j]
        if other.size == 2
          side = 0
          while side < 2
            p = row[side]; r = row[1-side]; s = 0
            s = other[1] if other[0] == p
            s = other[0] if other[1] == p
            if s != 0 && r != s
              dep = r == 0-s ? -1 : wassat_induction_pair(0-r, 0-s, nv)
              units.push([p, dep]) if dep < 0 || known.has_key?(dep) || buckets.has_key?(dep)
            side += 1
        j += 1
    i += 1
  units

-> wassat_induction_proof(formula)
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  return nil if nv < 2 || nv > 8192 || nc < 3 || nc > 25000
  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  wide = 0; ci = 0
  while ci < nc
    return nil if lens[ci] < 1 || lens[ci] > 4
    wide += 1 if lens[ci] > 2
    ci += 1
  return nil if wide == nc || 2*wide < nc
  buckets = {}; known = {}; close_vars = []; seen = {}
  ci = 0
  while ci < nc
    n = lens[ci]; at = offs[ci]
    if n == 2
      known[wassat_induction_pair(lits[at], lits[at+1], nv)] = true
      j = 0
      while j < 2 && close_vars.size < 128
        v = lits[at+j].abs
        unless seen.has_key?(v)
          seen[v] = true; close_vars.push(v)
        j += 1
    elsif n > 2
      i = 0
      while i < n
        j = i+1
        while j < n
          a = lits[at+i]; b = lits[at+j]
          if a.abs != b.abs
            guard = wassat_induction_pair(a, b, nv)
            buckets[guard] = [] unless buckets.has_key?(guard)
            rows = buckets[guard]
            if rows.size <= 16
              rest = []; k = 0
              while k < n
                rest.push(lits[at+k]) unless k == i || k == j
                k += 1
              rows.push(rest)
          j += 1
        i += 1
    ci += 1

  candidates = []
  buckets.keys.each -> (guard)
    rows = buckets[guard]
    if !known.has_key?(guard) && rows.size >= 2 && rows.size <= 16
      units = wassat_induction_units(rows, known, buckets, nv)
      candidates.push([guard, units]) if units.size >= 2
  return nil if candidates.empty?

  # A fact enters the closure only after both predecessors are available.
  # Cycles with no base case supply no fact. All derived clauses are replayable
  # even if a coincidental pair outside the intended encoding enters a bucket.
  out = StringBuffer(); out.append("pseudo-Boolean proof version 3.0\n")
  derived = []; changed = true; work = 0
  while changed
    changed = false; i = 0
    while i < candidates.size
      guard = candidates[i][0]; units = candidates[i][1]
      if !known.has_key?(guard)
        work += units.size*units.size
        return nil if work > 4000000
        left = 0
        while left < units.size && !known.has_key?(guard)
          u = units[left]; right = 0
          if u[1] < 0 || known.has_key?(u[1])
            while right < left && !known.has_key?(guard)
              v = units[right]; p = u[0]; q = v[0]
              if p != q && (v[1] < 0 || known.has_key?(v[1])) && (p == 0-q || known.has_key?(wassat_induction_pair(0-p, 0-q, nv)))
                a = guard / (2*nv+1) - nv; b = guard % (2*nv+1) - nv
                wassat_induction_rup(out, [a,b,p]); wassat_induction_rup(out, [a,b,q])
                wassat_induction_rup(out, [a,b]); derived.push([a,b])
                known[guard] = true; changed = true
              right += 1
          left += 1
      i += 1
  return nil if derived.empty?
  # Finish only when the original formula plus proved clauses propagates a
  # conflict, possibly after splitting on one literal of a target clause.
  solver = Wassat.from_flat(nv, wassat_raw_artifact(formula, nv), WASSAT_PROOF_NONE)
  derived.each -> (row)
    solver.add_input_clause(row)
  values = i8[nv+1]; counters = i64[4]
  closed = solver.propagation_snapshot([], values, counters) == -1
  i = 0
  while !closed && i < close_vars.size
    v = close_vars[i]
    if solver.propagation_snapshot([v], values, counters) == -1 && solver.propagation_snapshot([0-v], values, counters) == -1
      wassat_induction_rup(out, [0-v])
      closed = true
    i += 1
  return nil unless closed
  wassat_induction_rup(out, [])
  out.append("output NONE ;\nconclusion UNSAT : -1 ;\nend pseudo-Boolean proof ;\n")
  out.to_s
