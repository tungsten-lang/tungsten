# Exact two-coloring solver for arithmetic/combinatorial hypergraphs.
#
# Van der Waerden, Schur, Pythagorean-triple, and Ramsey encodings all
# render the same decision problem: 2-color a set of elements so that no
# listed scope (an arithmetic progression, an x+y=z triple, a Pythagorean
# triple, a vertex clique's edge set) is monochromatic in a forbidden
# color. Clauses are monochromatic nogoods, either directly over element
# variables (single form) or over one variable per element from an
# exact-one pair partition (paired form).
#
# Recognition extracts the actual scopes from the literal clauses and
# then verifies that EVERY scope has the family's mathematical shape --
# arithmetic progression in element values (or in prime values, for
# Green--Tao style scopes), Schur triple, Pythagorean triple, or clique
# edge set. The decision itself is an exhaustive bounded native search
# over the extracted scopes with monochromatic-threat propagation. No
# extremal constant is ever consulted: an earlier tally-based version of
# this lane declared satisfiable formulas UNSAT from width histograms
# plus known Van der Waerden numbers, and that failure is pinned in
# mdp_spec. SAT models are re-checked against the original CNF by the
# caller; UNSAT is fast-only.

WASSAT_ARITH_MAX_ELEMENTS = 700
WASSAT_ARITH_MAX_SCOPES = 200000
WASSAT_ARITH_MAX_WIDTH = 28
WASSAT_ARITH_NODE_CAP = 2000000
WASSAT_ARITH_DEADLINE_MS = 50

-> wassat_arith_expired(deadline) (i64) i64
  return 1 if deadline > 0 && clock_ms() >= deadline
  0

-> wassat_arith_poll(meta) (i64[]) i64
  if meta[10] > 0
    meta[11] += 1
    if clock_ms() >= meta[10]
      meta[3] = 2
      return 1
  0

# meta: [0] trail size [1] nodes [2] node cap [3] stop reason
#       [4] queue generation [5] propagation calls [6] scope visits
#       [7] examined elements [8] forced colors [9] satisfied scopes
#       [10] optional deadline [11] budget polls [12..13] queue head/tail
#       [14] queue batches. Stop: 1 node cap, 2 deadline.
# Keep the hot queue scan a leaf function. Deadline checks between batches
# avoid imposing call-preserved register allocation on every examined scope.
-> wassat_arith_queue(assign, scope_off, scope_elem, scope_forbid,
                      inc_off, inc, trail, queue, qstamp, meta, quota) (i8[] i64[] i64[] i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  head = meta[12]
  tail = meta[13]
  stamp = meta[4]
  limit = head + quota
  meta[14] += 1
  bound = tail < limit ? tail : limit
  while head < bound
    si = queue[head]
    head += 1
    meta[6] += 1
    qstamp[si] = 0
    forbid = scope_forbid[si]
    unassigned = 0
    last_free = 0 - 1
    safe = 0
    j = scope_off[si]
    while j < scope_off[si + 1]
      e = scope_elem[j]
      j += 1
      if assign[e] < 0
        unassigned += 1
        last_free = e
      elsif assign[e] != forbid
        safe = 1
        break
    meta[7] += j - scope_off[si]
    meta[9] += 1 if safe != 0
    if safe == 0
      if unassigned == 0
        meta[12] = head
        meta[13] = tail
        return 0
      if unassigned == 1
        meta[8] += 1
        forced = 1 - forbid
        assign[last_free] = forced
        trail[meta[0]] = last_free
        meta[0] += 1
        p = inc_off[last_free]
        while p < inc_off[last_free + 1]
          sj = inc[p]
          if qstamp[sj] != stamp
            qstamp[sj] = stamp
            queue[tail] = sj
            tail += 1
          p += 1
        bound = tail < limit ? tail : limit
  meta[12] = head
  meta[13] = tail
  head < tail ? 2 : 1

-> wassat_arith_propagate(assign, scope_off, scope_elem, scope_forbid,
                          inc_off, inc, trail, queue, qstamp, meta,
                          nelem, nscopes, elem, color) (i8[] i64[] i64[] i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64) i64
  meta[5] += 1
  if assign[elem] >= 0
    return assign[elem] == color ? 1 : 0
  assign[elem] = color
  trail[meta[0]] = elem
  meta[0] += 1
  meta[4] += 1
  stamp = meta[4]
  tail = 0
  p = inc_off[elem]
  while p < inc_off[elem + 1]
    si = inc[p]
    if qstamp[si] != stamp
      qstamp[si] = stamp
      queue[tail] = si
      tail += 1
    p += 1
  meta[12] = 0
  meta[13] = tail
  status = 2
  while status == 2
    quota = 32768 - (meta[6] & 32767)
    status = wassat_arith_queue(assign, scope_off, scope_elem, scope_forbid,
      inc_off, inc, trail, queue, qstamp, meta, quota)
    if meta[6] > 0 && (meta[6] & 32767) == 0 && wassat_arith_poll(meta) != 0
      return 0
  status

-> wassat_arith_dfs(assign, scope_off, scope_elem, scope_forbid,
                    inc_off, inc, order, trail, queue, qstamp, meta,
                    nelem, nscopes) (i8[] i64[] i64[] i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64) i64
  meta[1] += 1
  return 0 if (meta[1] & 255) == 1 && wassat_arith_poll(meta) != 0
  if meta[1] > meta[2]
    meta[3] = 1
    return 0
  elem = 0 - 1
  i = 0
  while i < nelem
    if assign[order[i]] < 0
      elem = order[i]
      break
    i += 1
  return 1 if elem < 0
  mark = meta[0]
  color = 0
  while color <= 1
    if wassat_arith_propagate(
      assign, scope_off, scope_elem, scope_forbid,
      inc_off, inc, trail, queue, qstamp, meta,
      nelem, nscopes, elem, color
    ) == 1
      child = wassat_arith_dfs(
        assign, scope_off, scope_elem, scope_forbid,
        inc_off, inc, order, trail, queue, qstamp, meta,
        nelem, nscopes
      )
      return 1 if child == 1
      if child == 0
        while meta[0] > mark
          meta[0] -= 1
          assign[trail[meta[0]]] = 0 - 1
        return 0
    while meta[0] > mark
      meta[0] -= 1
      assign[trail[meta[0]]] = 0 - 1
    return 0 if meta[3] != 0
    color += 1
  0 - 1

-> wassat_arith_miss
  { "recognized": false, "status": 0, "elements": 0, "scopes": 0,
    "nodes": 0, "family": "", "model": [], "work": nil }

# Every scope's sorted elements, read through `values`, form an AP?
-> wassat_arith_all_ap(scope_off, scope_elem, values, nscopes, deadline = 0)
  si = 0
  while si < nscopes
    return false if (si & 255) == 0 && wassat_arith_expired(deadline) != 0
    lo = scope_off[si]
    hi = scope_off[si + 1]
    return false if hi - lo < 3
    d = values[scope_elem[lo + 1]] - values[scope_elem[lo]]
    return false if d <= 0
    j = lo + 1
    while j < hi
      return false unless values[scope_elem[j]] - values[scope_elem[j - 1]] == d
      j += 1
    si += 1
  true

-> wassat_arith_family(scope_off, scope_elem, nelem, nscopes, deadline = 0)
  if wassat_arith_all_ap(scope_off, scope_elem, arith_index_values(nelem), nscopes, deadline)
    return "van-der-waerden"
  if wassat_arith_all_ap(scope_off, scope_elem, arith_prime_values(nelem), nscopes, deadline)
    return "green-tao"
  schur = true
  pythag = true
  si = 0
  while si < nscopes && (schur || pythag)
    return "" if (si & 255) == 0 && wassat_arith_expired(deadline) != 0
    lo = scope_off[si]
    w = scope_off[si + 1] - lo
    if schur
      if w == 3
        a = scope_elem[lo] + 1
        b = scope_elem[lo + 1] + 1
        c = scope_elem[lo + 2] + 1
        schur = false unless a + b == c
      elsif w == 2
        schur = false unless 2 * (scope_elem[lo] + 1) == scope_elem[lo + 1] + 1
      else
        schur = false
    if pythag
      if w != 3
        pythag = false
      else
        a = scope_elem[lo] + 1
        b = scope_elem[lo + 1] + 1
        c = scope_elem[lo + 2] + 1
        pythag = false unless a * a + b * b == c * c
    si += 1
  return "schur" if schur
  return "pythagorean" if pythag
  return "ramsey" if wassat_arith_ramsey?(scope_off, scope_elem, nelem, nscopes, deadline)
  ""

-> arith_index_values(nelem)
  values = i64[nelem]
  i = 0
  while i < nelem
    values[i] = i + 1
    i += 1
  values

-> arith_prime_values(nelem)
  limit = 16000
  sieve = i8[limit + 1]
  values = i64[nelem]
  found = 0
  n = 2
  while n <= limit && found < nelem
    if sieve[n] == 0
      values[found] = n
      found += 1
      m = n + n
      while m <= limit
        sieve[m] = 1
        m += n
    n += 1
  values

# Elements are the edges of K_N in lexicographic order and every scope is
# the complete edge set of some vertex clique (3..8 vertices).
# A simple graph on k vertices has at most k*(k-1)/2 distinct edges.
# If the actual scope contains that many, it is precisely a clique. Track
# endpoints in a native mask and reject duplicate edges with reusable stamps;
# no per-scope vertex Array or repeated edge-presence search is needed.
-> wassat_arith_ramsey_shapes(scope_off, scope_elem, eu, ev, seen, nelem, nscopes, deadline) (i64[] i64[] i64[] i64[] i64[] i64 i64 i64) i64
  si = 0
  while si < nscopes
    return 0 if (si & 63) == 0 && wassat_arith_expired(deadline) != 0
    lo = scope_off[si]
    hi = scope_off[si + 1]
    width = hi - lo
    return 0 if width < 3 || width > 28
    vertices = 0
    mark = si + 1
    j = lo
    while j < hi
      e = scope_elem[j]
      return 0 if e < 0 || e >= nelem || seen[e] == mark
      seen[e] = mark
      vertices |= 1 << eu[e]
      vertices |= 1 << ev[e]
      j += 1
    k = 0
    while vertices != 0
      vertices &= vertices - 1
      k += 1
    return 0 if k < 3 || k > 8 || width != k * (k - 1) / 2
    si += 1
  1

-> wassat_arith_ramsey?(scope_off, scope_elem, nelem, nscopes, deadline = 0)
  nverts = 0
  cand = 3
  while cand <= 40
    nverts = cand if cand * (cand - 1) / 2 == nelem
    cand += 1
  return false if nverts == 0
  eu = i64[nelem]
  ev = i64[nelem]
  seen = i64[nelem]
  idx = 0
  i = 0
  while i < nverts
    j = i + 1
    while j < nverts
      eu[idx] = i
      ev[idx] = j
      idx += 1
      j += 1
    i += 1
  wassat_arith_ramsey_shapes(scope_off, scope_elem, eu, ev, seen, nelem, nscopes, deadline) == 1

# Color complementation is a symmetry only when every extracted scope
# forbids both colors. Check the actual clause scopes, ignoring duplicates;
# a matching family name or width histogram is not enough.
# Width agreement is necessary for color complementation, even with
# duplicate clauses. A mismatch can decline before building scope strings;
# agreement still requires the exact scope-by-scope check below.
-> wassat_arith_widths_match(scope_off, scope_forbid, nscopes, deadline) (i64[] i8[] i64 i64) i64
  zero_widths = 0
  one_widths = 0
  si = 0
  while si < nscopes
    if (si & 255) == 0 && deadline > 0 && clock_ms() >= deadline
      return 0
    width = scope_off[si + 1] - scope_off[si]
    color = scope_forbid[si]
    # Outside the extracted scope contract, leave the exact check in charge.
    return 1 if width < 0 || width > 62 || color < 0 || color > 1
    if color == 0
      zero_widths |= 1 << width
    else
      one_widths |= 1 << width
    si += 1
  zero_widths == one_widths ? 1 : 0

-> wassat_arith_color_symmetric?(scope_off, scope_elem, scope_forbid, nscopes, deadline = 0)
  return false if wassat_arith_widths_match(scope_off, scope_forbid, nscopes, deadline) == 0
  colors = {}
  si = 0
  while si < nscopes
    return false if (si & 63) == 0 && wassat_arith_expired(deadline) != 0
    key = ""
    j = scope_off[si]
    while j < scope_off[si + 1]
      key = key + "[scope_elem[j]],"
      j += 1
    mask = colors[key]
    mask = 0 if mask == nil
    colors[key] = mask | (1 << scope_forbid[si])
    si += 1
  keys = colors.keys
  i = 0
  while i < keys.size
    return false if (i & 63) == 0 && wassat_arith_expired(deadline) != 0
    return false if colors[keys[i]] != 3
    i += 1
  true

-> wassat_arith_coloring_solve(formula, node_cap = WASSAT_ARITH_NODE_CAP, deadline = 0)
  miss = wassat_arith_miss
  return miss unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return miss if nv < 3 || nv > 2 * WASSAT_ARITH_MAX_ELEMENTS
  return miss if ncl < 3 || ncl > 400000
  meta = i64[15]
  meta[2] = node_cap
  meta[10] = deadline
  miss["work"] = meta
  return miss if wassat_arith_poll(meta) != 0
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]

  # Paired form trial: positive binaries partition all variables and each
  # pair also has its negative binary; every binary is one of those.
  paired = nv % 2 == 0
  partner = i64[nv + 1]
  pair_neg = i8[nv + 1]
  ci = 0
  while ci < ncl && paired
    return miss if (ci & 255) == 0 && wassat_arith_poll(meta) != 0
    if fcl[ci] == 2
      off = fcs[ci]
      a = fla[off]
      b = fla[off + 1]
      if a > 0 && b > 0
        if a > nv || b > nv || a == b || partner[a] != 0 || partner[b] != 0
          paired = false
        else
          partner[a] = b
          partner[b] = a
      elsif a < 0 && b < 0
        u = 0 - a
        v = 0 - b
        pair_neg[u < v ? u : v] = 1 if u >= 1 && u <= nv && v >= 1 && v <= nv
      else
        paired = false
    elsif fcl[ci] == 1
      paired = false
    ci += 1
  if paired
    v = 1
    while v <= nv && paired
      paired = false if partner[v] == 0
      paired = false if v < partner[v] && pair_neg[v] == 0
      v += 1
    ci = 0
    while ci < ncl && paired
      return miss if (ci & 255) == 0 && wassat_arith_poll(meta) != 0
      if fcl[ci] == 2
        off = fcs[ci]
        a = fla[off]
        b = fla[off + 1]
        u = a < 0 ? 0 - a : a
        w = b < 0 ? 0 - b : b
        paired = false unless partner[u] == w
      ci += 1

  var_elem = i64[nv + 1]
  var_color = i64[nv + 1]
  elem_lo = i64[WASSAT_ARITH_MAX_ELEMENTS]
  elem_hi = i64[WASSAT_ARITH_MAX_ELEMENTS]
  nelem = 0
  if paired
    v = 1
    while v <= nv
      if v < partner[v]
        var_elem[v] = nelem
        var_color[v] = 1
        var_elem[partner[v]] = nelem
        var_color[partner[v]] = 0
        elem_lo[nelem] = v
        elem_hi[nelem] = partner[v]
        nelem += 1
      v += 1
  else
    nelem = nv
    return miss if nelem > WASSAT_ARITH_MAX_ELEMENTS
    v = 1
    while v <= nv
      var_elem[v] = v - 1
      v += 1

  scope_off = i64[ncl + 1]
  scope_elem = i64[formula["flat_nlits"] > 0 ? formula["flat_nlits"] : 1]
  scope_forbid = i8[ncl > 0 ? ncl : 1]
  scratch = i64[WASSAT_ARITH_MAX_WIDTH]
  nscopes = 0
  total = 0
  ci = 0
  while ci < ncl
    return miss if (ci & 255) == 0 && wassat_arith_poll(meta) != 0
    n = fcl[ci]
    off = fcs[ci]
    if paired && n == 2
      ci += 1
      next
    return miss if n < 2 || n > WASSAT_ARITH_MAX_WIDTH
    return miss if nscopes >= WASSAT_ARITH_MAX_SCOPES
    all_pos = true
    all_neg = true
    j = 0
    while j < n
      all_pos = false if fla[off + j] <= 0
      all_neg = false if fla[off + j] >= 0
      j += 1
    return miss unless all_pos || all_neg
    if paired
      return miss unless all_neg
      forbid = 0 - 1
      j = 0
      while j < n
        v = 0 - fla[off + j]
        return miss if v < 1 || v > nv
        return miss if forbid >= 0 && var_color[v] != forbid
        forbid = var_color[v]
        scratch[j] = var_elem[v]
        j += 1
    else
      forbid = all_neg ? 1 : 0
      j = 0
      while j < n
        l = fla[off + j]
        v = l < 0 ? 0 - l : l
        return miss if v < 1 || v > nv
        scratch[j] = var_elem[v]
        j += 1
    # Insertion-sort the scope and require distinct elements.
    j = 1
    while j < n
      x = scratch[j]
      k = j
      while k > 0 && scratch[k - 1] > x
        scratch[k] = scratch[k - 1]
        k -= 1
      scratch[k] = x
      j += 1
    j = 1
    while j < n
      return miss if scratch[j] == scratch[j - 1]
      j += 1
    scope_off[nscopes] = total
    j = 0
    while j < n
      scope_elem[total] = scratch[j]
      total += 1
      j += 1
    scope_forbid[nscopes] = forbid
    nscopes += 1
    ci += 1
  return miss if nscopes == 0 || nelem < 3
  scope_off[nscopes] = total

  family = wassat_arith_family(scope_off, scope_elem, nelem, nscopes, deadline)
  return miss if wassat_arith_poll(meta) != 0
  return miss if family == ""

  degree = i64[nelem]
  si = 0
  while si < nscopes
    return miss if (si & 255) == 0 && wassat_arith_poll(meta) != 0
    j = scope_off[si]
    while j < scope_off[si + 1]
      degree[scope_elem[j]] += 1
      j += 1
    si += 1
  inc_off = i64[nelem + 1]
  cursor = i64[nelem]
  e = 0
  while e < nelem
    inc_off[e + 1] = inc_off[e] + degree[e]
    cursor[e] = inc_off[e]
    e += 1
  inc = i64[total > 0 ? total : 1]
  si = 0
  while si < nscopes
    return miss if (si & 255) == 0 && wassat_arith_poll(meta) != 0
    j = scope_off[si]
    while j < scope_off[si + 1]
      e = scope_elem[j]
      inc[cursor[e]] = si
      cursor[e] += 1
      j += 1
    si += 1

  order = i64[nelem]
  e = 0
  while e < nelem
    order[e] = e
    e += 1
  i = 0
  while i < nelem
    return miss if (i & 15) == 0 && wassat_arith_poll(meta) != 0
    best = i
    j = i + 1
    while j < nelem
      best = j if degree[order[j]] > degree[order[best]]
      j += 1
    if best != i
      t = order[i]
      order[i] = order[best]
      order[best] = t
    i += 1

  assign = i8[nelem]
  e = 0
  while e < nelem
    assign[e] = 0 - 1
    e += 1
  trail = i64[nelem + 1]
  queue = i64[total + nscopes + 1]
  qstamp = i64[nscopes]
  # If every scope is invariant under swapping colors, each model has a
  # complemented model. Fix one element to color zero before searching;
  # the omitted root branch is exactly the complement of this one.
  symmetric = wassat_arith_color_symmetric?(scope_off, scope_elem, scope_forbid, nscopes, deadline)
  return miss if wassat_arith_poll(meta) != 0
  seed_ok = 1
  if symmetric
    seed_ok = wassat_arith_propagate(
      assign, scope_off, scope_elem, scope_forbid,
      inc_off, inc, trail, queue, qstamp, meta,
      nelem, nscopes, order[0], 0
    )
  status = 0 - 1
  if seed_ok == 1
    status = wassat_arith_dfs(
      assign, scope_off, scope_elem, scope_forbid,
      inc_off, inc, order, trail, queue, qstamp, meta, nelem, nscopes
    )
  status = 0 if meta[3] != 0
  result = { "recognized": true, "status": status, "elements": nelem,
    "scopes": nscopes, "nodes": meta[1], "family": family, "model": [], "work": meta }
  if status == 1
    model = []
    v = 1
    while v <= nv
      truth = paired ? (assign[var_elem[v]] == var_color[v]) : (assign[var_elem[v]] == 1)
      model.push(truth ? v : 0 - v)
      v += 1
    return miss unless wassat_model_satisfies?(formula, model)
    result["model"] = model
  result
