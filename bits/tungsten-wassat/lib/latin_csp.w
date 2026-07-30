# Exact solver for compact four-value Latin CSP encodings.
#
# A recognized formula is a partition of every Boolean variable into positive
# width-four domain clauses, followed (in any clause order) only by negative
# ternary nogoods.  Each nogood scope contains three distinct domains, exactly
# 48 of its 64 value triples are forbidden, and the 16 allowed triples form a
# Latin relation: any two values determine the third uniquely.
#
# No explicit at-most-one clauses are needed.  From any Boolean model choose
# one true value in each positive domain row and turn the other values false.
# Positive rows retain a witness and all-negative clauses are downward-closed,
# so the one-hot projection is still a model.  Exhaustively refuting the
# resulting finite-domain CSP therefore refutes the CNF.
#
# Latin propagation is unusually strong on sparse generated instances.  A
# greedy structural closure chooses seed domains until repeated "two known
# endpoints determine the third" covers the whole hypergraph.  The exact DFS
# branches only on those seeds and propagates every other value natively.

WASSAT_LATIN_MIN_VARS = 64
WASSAT_LATIN_MAX_VARS = 4096
WASSAT_LATIN_MIN_CLAUSES = 1000
WASSAT_LATIN_MAX_CLAUSES = 100000
WASSAT_LATIN_MAX_GROUPS = 1024
WASSAT_LATIN_MAX_CONSTRAINTS = 4096
WASSAT_LATIN_MAX_SEEDS = 12
WASSAT_LATIN_NODE_CAP = 500000
WASSAT_LATIN_STRUCTURAL_CAP = 50000000
WASSAT_LATIN_CHECK_CAP = 200000000
WASSAT_LATIN_HASH_CAP = 8192

-> wassat_latin_miss
  { "recognized": false, "status": 0, "groups": 0, "constraints": 0,
    "seeds": 0, "nodes": 0, "checks": 0, "model": [] }

# The tuple index is a*16 + b*4 + c. Two 32-bit words avoid relying on the
# sign bit of a boxed/native integer while keeping the hot membership test
# branch-free apart from the word choice.
-> wassat_latin_bad(bad0, bad1, ci, tuple) (i64[] i64[] i64 i64) i64
  if tuple < 32
    (bad0[ci] & (1 << tuple)) == 0 ? 0 : 1
  else
    (bad1[ci] & (1 << (tuple - 32))) == 0 ? 0 : 1

# Close a structural known-domain set under ternary "two imply the third".
# Incidence-queue closure touches each hyperedge endpoint once instead of
# repeatedly sweeping every constraint to a fixed point.
-> wassat_latin_close(scope0, scope1, scope2, inc_off, inc, ncon, ngroups,
                      known, rel_count, queue, work) (i64[] i64[] i64[] i64[] i64[] i64 i64 i8[] i8[] i64[] i64[]) i64
  ci = 0
  while ci < ncon
    rel_count[ci] = 0
    ci += 1
  head = 0
  tail = 0
  g = 0
  while g < ngroups
    if known[g] != 0
      queue[tail] = g
      tail += 1
    g += 1
  while head < tail
    g = queue[head]
    head += 1
    p = inc_off[g]
    while p < inc_off[g + 1]
      work[0] += 1
      return -1 if work[0] > WASSAT_LATIN_STRUCTURAL_CAP
      ci = inc[p]
      rel_count[ci] += 1
      if rel_count[ci] == 2
        target = -1
        target = scope0[ci] if known[scope0[ci]] == 0
        target = scope1[ci] if known[scope1[ci]] == 0
        target = scope2[ci] if known[scope2[ci]] == 0
        if target >= 0
          known[target] = 1
          queue[tail] = target
          tail += 1
      p += 1
  0

# Greedily add the domain whose structural closure reaches the most currently
# unknown domains. Return -1 when the configured seed ceiling cannot cover the
# hypergraph; the caller then falls through to ordinary CDCL.
-> wassat_latin_seeds(scope0, scope1, scope2, inc_off, inc, ncon, ngroups,
                      max_seeds, seeds, known, trial, rel_count, queue,
                      work) (i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64[] i8[] i8[] i8[] i64[] i64[]) i64
  nknown = 0
  nseeds = 0
  while nknown < ngroups
    return -1 if nseeds >= max_seeds
    best = -1
    best_count = -1
    g = 0
    while g < ngroups
      if known[g] == 0
        i = 0
        while i < ngroups
          trial[i] = known[i]
          i += 1
        trial[g] = 1
        z = wassat_latin_close(
          scope0, scope1, scope2, inc_off, inc, ncon, ngroups,
          trial, rel_count, queue, work
        )
        return -1 if z < 0
        count = 0
        i = 0
        while i < ngroups
          count += 1 if trial[i] != 0
          i += 1
        if count > best_count
          best = g
          best_count = count
      g += 1
    return -1 if best < 0
    seeds[nseeds] = best
    nseeds += 1
    known[best] = 1
    z = wassat_latin_close(
      scope0, scope1, scope2, inc_off, inc, ncon, ngroups,
      known, rel_count, queue, work
    )
    return -1 if z < 0
    nknown = 0
    g = 0
    while g < ngroups
      nknown += 1 if known[g] != 0
      g += 1
  nseeds

# Assign one seed value and drain the incident-constraint queue. Values are
# 0=unassigned and 1..4=domain value. Along a branch each group is assigned
# once, so the assignment trail and total queue traffic are linearly bounded.
#
# meta: [0] trail size [1] DFS nodes [2] node cap [3] constraint checks
#       [4] queue generation [5] cap exhausted [6] structural error
#       [7] constraint-check cap
-> wassat_latin_propagate(values, scope0, scope1, scope2, funcs,
                          inc_off, inc, trail, queue, qstamp, meta,
                          ngroups, ncon, group, value) (i8[] i64[] i64[] i64[] i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64) i64
  if values[group] != 0
    return values[group] == value ? 1 : 0

  values[group] = value
  trail[meta[0]] = group
  meta[0] += 1

  meta[4] += 1
  stamp = meta[4]
  head = 0
  tail = 0
  p = inc_off[group]
  while p < inc_off[group + 1]
    ci = inc[p]
    if qstamp[ci] != stamp
      qstamp[ci] = stamp
      queue[tail] = ci
      tail += 1
    p += 1

  while head < tail
    ci = queue[head]
    head += 1
    qstamp[ci] = 0
    meta[3] += 1

    ga = scope0[ci]
    gb = scope1[ci]
    gc = scope2[ci]
    va = values[ga]
    vb = values[gb]
    vc = values[gc]
    target = -1
    missing = 0
    key = 0
    if va != 0 && vb != 0
      if vc != 0
        want = funcs[(ci * 3 + 2) * 16 + (va - 1) * 4 + vb - 1]
        return 0 if want != vc
      else
        missing = 2
        key = (va - 1) * 4 + vb - 1
        target = gc
    elsif va != 0 && vc != 0
      missing = 1
      key = (va - 1) * 4 + vc - 1
      target = gb
    elsif vb != 0 && vc != 0
      missing = 0
      key = (vb - 1) * 4 + vc - 1
      target = ga
    if target >= 0
      want = funcs[(ci * 3 + missing) * 16 + key]
      if want <= 0 || want > 4
        meta[6] = 1
        return 0
      values[target] = want
      trail[meta[0]] = target
      meta[0] += 1
      p = inc_off[target]
      while p < inc_off[target + 1]
        cj = inc[p]
        if qstamp[cj] != stamp
          qstamp[cj] = stamp
          queue[tail] = cj
          tail += 1
        p += 1
  1

# Exhaustive DFS over the structural seed set. Return 1 SAT, -1 exhaustively
# UNSAT, or 0 on the deterministic node cap / internal conservative fallback.
-> wassat_latin_dfs(values, scope0, scope1, scope2, funcs,
                    inc_off, inc, seeds, solution, trail, queue, qstamp, meta,
                    ngroups, ncon, nseeds, depth) (i8[] i64[] i64[] i64[] i8[] i64[] i64[] i64[] i8[] i64[] i64[] i64[] i64[] i64 i64 i64 i64) i64
  meta[1] += 1
  if meta[1] > meta[2]
    meta[5] = 1
    return 0
  if meta[3] > meta[7]
    meta[5] = 1
    return 0

  if depth >= nseeds
    g = 0
    while g < ngroups
      if values[g] == 0
        meta[6] = 1
        return 0
      solution[g] = values[g]
      g += 1
    return 1

  group = seeds[depth]
  if values[group] != 0
    return wassat_latin_dfs(
      values, scope0, scope1, scope2, funcs,
      inc_off, inc, seeds, solution, trail, queue, qstamp, meta,
      ngroups, ncon, nseeds, depth + 1
    )

  mark = meta[0]
  value = 1
  while value <= 4
    if wassat_latin_propagate(
      values, scope0, scope1, scope2, funcs,
      inc_off, inc, trail, queue, qstamp, meta,
      ngroups, ncon, group, value
    ) == 1
      child = wassat_latin_dfs(
        values, scope0, scope1, scope2, funcs,
        inc_off, inc, seeds, solution, trail, queue, qstamp, meta,
        ngroups, ncon, nseeds, depth + 1
      )
      return 1 if child == 1
      if child == 0
        while meta[0] > mark
          meta[0] -= 1
          values[trail[meta[0]]] = 0
        return 0
    while meta[0] > mark
      meta[0] -= 1
      values[trail[meta[0]]] = 0
    if meta[3] > meta[7]
      meta[5] = 1
      return 0
    return 0 if meta[5] != 0 || meta[6] != 0
    value += 1
  -1

-> wassat_latin_csp_solve_limits(formula, node_cap, min_vars, min_clauses)
  miss = wassat_latin_miss
  return miss unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return miss if nv < min_vars || nv > WASSAT_LATIN_MAX_VARS
  return miss if ncl < min_clauses || ncl > WASSAT_LATIN_MAX_CLAUSES
  return miss unless nv % 4 == 0
  return miss if node_cap < 1

  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  var_group = i64[nv + 1]
  var_value = i64[nv + 1]
  ngroups = 0

  # First pass: collect a disjoint partition of positive width-four domains
  # while rejecting every syntax outside the two-clause grammar.
  ci = 0
  while ci < ncl
    st = offs[ci]
    n = lens[ci]
    positive = n == 4
    negative = n == 3
    j = 0
    while j < n
      lit = lits[st + j]
      positive = false if lit <= 0
      negative = false if lit >= 0
      j += 1
    return miss unless positive || negative
    if positive
      return miss if ngroups >= WASSAT_LATIN_MAX_GROUPS
      j = 0
      while j < 4
        v = lits[st + j]
        return miss if v < 1 || v > nv || var_group[v] != 0
        var_group[v] = ngroups + 1
        var_value[v] = j
        j += 1
      ngroups += 1
    ci += 1
  return miss unless ngroups * 4 == nv
  v = 1
  while v <= nv
    return miss if var_group[v] == 0
    v += 1

  scope0 = i64[WASSAT_LATIN_MAX_CONSTRAINTS]
  scope1 = i64[WASSAT_LATIN_MAX_CONSTRAINTS]
  scope2 = i64[WASSAT_LATIN_MAX_CONSTRAINTS]
  bad0 = i64[WASSAT_LATIN_MAX_CONSTRAINTS]
  bad1 = i64[WASSAT_LATIN_MAX_CONSTRAINTS]
  bad_count = i64[WASSAT_LATIN_MAX_CONSTRAINTS]
  hash_key = i64[WASSAT_LATIN_HASH_CAP]
  hash_value = i64[WASSAT_LATIN_HASH_CAP]
  ncon = 0

  # Second pass: canonicalize each scope and record its unique forbidden
  # tuple in two packed words.
  ci = 0
  while ci < ncl
    if lens[ci] == 3
      st = offs[ci]
      x0 = 0 - lits[st]
      x1 = 0 - lits[st + 1]
      x2 = 0 - lits[st + 2]
      return miss if x0 < 1 || x0 > nv || x1 < 1 || x1 > nv || x2 < 1 || x2 > nv
      g0 = var_group[x0] - 1
      g1 = var_group[x1] - 1
      g2 = var_group[x2] - 1
      u0 = var_value[x0]
      u1 = var_value[x1]
      u2 = var_value[x2]
      return miss if g0 == g1 || g0 == g2 || g1 == g2
      if g0 > g1
        t = g0
        g0 = g1
        g1 = t
        t = u0
        u0 = u1
        u1 = t
      if g1 > g2
        t = g1
        g1 = g2
        g2 = t
        t = u1
        u1 = u2
        u2 = t
      if g0 > g1
        t = g0
        g0 = g1
        g1 = t
        t = u0
        u0 = u1
        u1 = t

      key = (g0 * ngroups + g1) * ngroups + g2
      slot = key & (WASSAT_LATIN_HASH_CAP - 1)
      while hash_key[slot] != 0 && hash_key[slot] != key + 1
        slot = (slot + 1) & (WASSAT_LATIN_HASH_CAP - 1)
      if hash_key[slot] == 0
        return miss if ncon >= WASSAT_LATIN_MAX_CONSTRAINTS
        hash_key[slot] = key + 1
        hash_value[slot] = ncon + 1
        scope0[ncon] = g0
        scope1[ncon] = g1
        scope2[ncon] = g2
        ncon += 1
      k = hash_value[slot] - 1
      tuple = u0 * 16 + u1 * 4 + u2
      bit = 1 << (tuple & 31)
      if tuple < 32
        return miss unless (bad0[k] & bit) == 0
        bad0[k] = bad0[k] | bit
      else
        return miss unless (bad1[k] & bit) == 0
        bad1[k] = bad1[k] | bit
      bad_count[k] += 1
      return miss if bad_count[k] > 48
    ci += 1
  return miss if ncon == 0

  # Complete every Latin lookup table. Each coordinate pair must have one and
  # only one allowed completion; this also proves exactly 16 allowed tuples.
  funcs = i8[ncon * 48]
  k = 0
  while k < ncon
    return miss unless bad_count[k] == 48
    missing = 0
    while missing < 3
      a = 0
      while a < 4
        b = 0
        while b < 4
          count = 0
          want = -1
          candidate = 0
          while candidate < 4
            if missing == 0
              tuple = candidate * 16 + a * 4 + b
            elsif missing == 1
              tuple = a * 16 + candidate * 4 + b
            else
              tuple = a * 16 + b * 4 + candidate
            if wassat_latin_bad(bad0, bad1, k, tuple) == 0
              count += 1
              want = candidate + 1
            candidate += 1
          return miss unless count == 1
          funcs[(k * 3 + missing) * 16 + a * 4 + b] = want
          b += 1
        a += 1
      missing += 1
    k += 1

  degree = i64[ngroups]
  k = 0
  while k < ncon
    degree[scope0[k]] += 1
    degree[scope1[k]] += 1
    degree[scope2[k]] += 1
    k += 1
  inc_off = i64[ngroups + 1]
  cursor = i64[ngroups]
  g = 0
  while g < ngroups
    inc_off[g + 1] = inc_off[g] + degree[g]
    cursor[g] = inc_off[g]
    g += 1
  inc = i64[3 * ncon]
  k = 0
  while k < ncon
    g = scope0[k]
    inc[cursor[g]] = k
    cursor[g] += 1
    g = scope1[k]
    inc[cursor[g]] = k
    cursor[g] += 1
    g = scope2[k]
    inc[cursor[g]] = k
    cursor[g] += 1
    k += 1

  seeds = i64[WASSAT_LATIN_MAX_SEEDS]
  known = i8[ngroups]
  trial = i8[ngroups]
  seed_rel_count = i8[ncon]
  seed_queue = i64[ngroups]
  seed_work = i64[1]
  nseeds = wassat_latin_seeds(
    scope0, scope1, scope2, inc_off, inc, ncon, ngroups,
    WASSAT_LATIN_MAX_SEEDS, seeds, known, trial, seed_rel_count,
    seed_queue, seed_work
  )
  recognized = { "recognized": true, "status": 0, "groups": ngroups,
    "constraints": ncon, "seeds": nseeds < 0 ? 0 : nseeds,
    "nodes": 0, "checks": 0, "model": [] }
  return recognized if nseeds < 0

  values = i8[ngroups]
  solution = i8[ngroups]
  trail = i64[ngroups + 1]
  queue = i64[3 * ncon + 1]
  qstamp = i64[ncon]
  meta = i64[8]
  meta[2] = node_cap
  meta[7] = WASSAT_LATIN_CHECK_CAP
  status = wassat_latin_dfs(
    values, scope0, scope1, scope2, funcs,
    inc_off, inc, seeds, solution, trail, queue, qstamp, meta,
    ngroups, ncon, nseeds, 0
  )
  status = 0 if meta[5] != 0 || meta[6] != 0
  recognized["status"] = status
  recognized["nodes"] = meta[1]
  recognized["checks"] = meta[3]
  if status == 1
    model = []
    v = 1
    while v <= nv
      g = var_group[v] - 1
      chosen = solution[g] - 1
      model.push(var_value[v] == chosen ? v : 0 - v)
      v += 1
    recognized["model"] = model
  recognized

-> wassat_latin_csp_solve(formula, node_cap = WASSAT_LATIN_NODE_CAP)
  wassat_latin_csp_solve_limits(
    formula, node_cap, WASSAT_LATIN_MIN_VARS, WASSAT_LATIN_MIN_CLAUSES
  )
