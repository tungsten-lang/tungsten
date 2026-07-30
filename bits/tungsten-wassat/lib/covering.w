# Exact solver for conflict-constrained covering formulas.
#
# A recognized formula consists entirely of:
#
#   * positive clauses of width at least three, each requiring one selected
#     variable; and
#   * negative binary clauses, each forbidding a pair of selected variables.
#
# It is therefore exactly the problem of finding an independent set that hits
# every positive row.  The bounded search below maintains each uncovered
# row's number of available variables incrementally.  Selecting a variable
# covers all of its rows and excludes its conflict neighbours; a row with one
# remaining variable forces that selection.
#
# Recognition is deliberately strict and the search is one-sided on resource
# exhaustion: malformed shapes and a node-cap miss both fall through to normal
# Wassat.  A SAT answer is checked against the original formula by the caller;
# UNSAT is returned only after the exhaustive branch partition finishes.

WASSAT_COVER_MAX_VARS = 2048
WASSAT_COVER_MAX_ROWS = 20000
WASSAT_COVER_MAX_EDGES = 200000
WASSAT_COVER_MAX_ROW = 64
WASSAT_COVER_MAX_LITS = 500000
WASSAT_COVER_NODE_CAP = 64000

# Trail entries share one typed array:
#   1..nvars                         variable assignment changed
#   var_base..count_base-1           row became covered
#   count_base..count_base+nrows-1   row availability decremented
#
# `meta[0]` is the trail size.  Counts need no snapshot: every decrement has
# exactly one trail entry and undo walks the entries in reverse.
-> wassat_cover_undo(status, covered, counts, trail, meta,
                     nvars, nrows, mark) (i8[] i8[] i64[] i64[] i64[] i64 i64 i64) i64
  cover_base = nvars + 1
  count_base = cover_base + nrows
  while meta[0] > mark
    meta[0] -= 1
    item = trail[meta[0]]
    if item < cover_base
      status[item] = 0
    elsif item < count_base
      covered[item - cover_base] = 0
    else
      r = item - count_base
      counts[r] = counts[r] + 1
  0

# Exclude one still-available variable.  For uncovered rows, maintain the
# exact number of remaining candidates and enqueue newly unit rows.
-> wassat_cover_exclude(status, covered, counts, occ_off, occ_rows,
                        trail, meta, queue, qmeta,
                        nvars, nrows, v) (i8[] i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64) i64
  return 1 if status[v] < 0
  return 0 if status[v] > 0

  cover_base = nvars + 1
  count_base = cover_base + nrows
  status[v] = -1
  trail[meta[0]] = v
  meta[0] += 1

  p = occ_off[v]
  stop = occ_off[v + 1]
  while p < stop
    r = occ_rows[p]
    if covered[r] == 0
      counts[r] = counts[r] - 1
      trail[meta[0]] = count_base + r
      meta[0] += 1
      return 0 if counts[r] == 0
      if counts[r] == 1
        queue[qmeta[0]] = r
        qmeta[0] += 1
    p += 1
  1

# Select one variable, cover its positive rows, then exclude every conflict
# neighbour.  Partial work is left on the trail when a contradiction is found
# so the caller can restore its checkpoint normally.
-> wassat_cover_select(status, covered, counts, occ_off, occ_rows,
                       adj_off, adj, trail, meta, queue, qmeta,
                       nvars, nrows, v) (i8[] i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64) i64
  return 0 if status[v] < 0
  unless status[v] > 0
    status[v] = 1
    trail[meta[0]] = v
    meta[0] += 1

    cover_base = nvars + 1
    p = occ_off[v]
    stop = occ_off[v + 1]
    while p < stop
      r = occ_rows[p]
      if covered[r] == 0
        covered[r] = 1
        trail[meta[0]] = cover_base + r
        meta[0] += 1
      p += 1

  p = adj_off[v]
  stop = adj_off[v + 1]
  while p < stop
    return 0 unless wassat_cover_exclude(
      status, covered, counts, occ_off, occ_rows, trail, meta, queue, qmeta,
      nvars, nrows, adj[p]
    ) == 1
    p += 1
  1

# Drain the unit-row queue.  Stale entries are harmless: a later selection can
# cover the row, and several exclusions can enqueue work before it is visited.
-> wassat_cover_propagate(status, covered, counts, row_lits, row_off, row_len,
                          occ_off, occ_rows, adj_off, adj, trail, meta,
                          queue, qmeta, nvars, nrows) (i8[] i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64) i64
  head = 0
  while head < qmeta[0]
    r = queue[head]
    head += 1
    if covered[r] == 0 && counts[r] == 1
      sole = 0
      p = row_off[r]
      stop = p + row_len[r]
      while p < stop && sole == 0
        v = row_lits[p]
        sole = v if status[v] == 0
        p += 1
      return 0 if sole == 0
      meta[3] += 1
      return 0 unless wassat_cover_select(
        status, covered, counts, occ_off, occ_rows, adj_off, adj,
        trail, meta, queue, qmeta, nvars, nrows, sole
      ) == 1
  1

# Prefer a candidate that covers many still-open tight rows.  This dynamic
# residual-cover score is cheap on the sparse occurrence lists and reduced the
# SCPC reference search from roughly 51k to 23k nodes.
-> wassat_cover_score(v, covered, counts,
                      occ_off, occ_rows) (i64 i8[] i64[] i64[] i64[]) i64
  score = 0
  p = occ_off[v]
  stop = occ_off[v + 1]
  while p < stop
    r = occ_rows[p]
    score += 64 / counts[r] if covered[r] == 0 && counts[r] > 0
    p += 1
  score

# Complete DFS.  Return 1 for SAT, -1 for an exhaustively UNSAT subtree, and
# zero when the deterministic node cap is exhausted.
-> wassat_cover_dfs(status, covered, counts, row_lits, row_off, row_len,
                    nrows, occ_off, occ_rows, adj_off, adj, trail, meta,
                    queue, qmeta, candidates, scores, first_model,
                    solution_limit, max_row, nvars, depth) (i8[] i8[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i8[] i64 i64 i64 i64) i64
  meta[1] += 1
  if meta[1] > meta[2]
    meta[4] = 1
    return 0

  # Unit propagation guarantees every remaining open row has at least two
  # candidates.  Stop the minimum-row scan as soon as that lower bound is met.
  best = -1
  # Directed-kernel rows intentionally preserve duplicate attackers, so a
  # syntactically exact row can be wider than the component's variable count.
  best_count = max_row + 1
  r = 0
  while r < nrows
    if covered[r] == 0 && counts[r] < best_count
      best = r
      best_count = counts[r]
      r = nrows if best_count <= 2
    r += 1
  if best < 0
    # Ordinary solving stops at one model.  Count-to-two is used only by the
    # directed-kernel decomposition to prove local uniqueness; every variable
    # must then be fixed by the closed kernel equations.  If an arbitrary
    # covering formula leaves an optional variable free, decline uniqueness
    # rather than silently counting only its canonical false completion.
    if solution_limit > 1
      v = 1
      while v <= nvars
        if status[v] == 0
          meta[6] = 1
          return 0
        v += 1
    meta[5] += 1
    if meta[5] == 1
      v = 1
      while v <= nvars
        first_model[v] = status[v] == 1 ? 1 : -1
        v += 1
    return 1 if meta[5] >= solution_limit
    # One solution found while uniqueness is requested: keep searching.  A
    # completely exhausted root with meta[5] == 1 is the uniqueness proof.
    return -1
  return -1 if best_count <= 0

  base = depth * max_row
  ncand = 0
  p = row_off[best]
  stop = p + row_len[best]
  while p < stop
    v = row_lits[p]
    if status[v] == 0
      score = wassat_cover_score(v, covered, counts, occ_off, occ_rows)
      at = ncand
      while at > 0 && scores[base + at - 1] < score
        candidates[base + at] = candidates[base + at - 1]
        scores[base + at] = scores[base + at - 1]
        at -= 1
      candidates[base + at] = v
      scores[base + at] = score
      ncand += 1
    p += 1

  # Exact partition by the first selected candidate in the chosen row:
  # v0=true; v0=false,v1=true; ... .  Propagation after each cumulative false
  # assignment is retained for subsequent siblings and undone at `base_mark`.
  base_mark = meta[0]
  i = 0
  while i < ncand
    branch_mark = meta[0]
    qmeta[0] = 0
    v = candidates[base + i]
    if wassat_cover_select(
      status, covered, counts, occ_off, occ_rows, adj_off, adj,
      trail, meta, queue, qmeta, nvars, nrows, v
    ) == 1 && wassat_cover_propagate(
      status, covered, counts, row_lits, row_off, row_len,
      occ_off, occ_rows, adj_off, adj, trail, meta, queue, qmeta,
      nvars, nrows
    ) == 1
      child = wassat_cover_dfs(
        status, covered, counts, row_lits, row_off, row_len, nrows,
        occ_off, occ_rows, adj_off, adj, trail, meta, queue, qmeta,
        candidates, scores, first_model, solution_limit,
        max_row, nvars, depth + 1
      )
      return 1 if child == 1
      if child == 0
        wassat_cover_undo(
          status, covered, counts, trail, meta, nvars, nrows, base_mark
        )
        return 0
    wassat_cover_undo(
      status, covered, counts, trail, meta, nvars, nrows, branch_mark
    )
    return 0 if meta[4] == 1

    # Retain this false branch while considering later candidates.  If it
    # contradicts, every remaining partition is impossible.
    qmeta[0] = 0
    unless wassat_cover_exclude(
      status, covered, counts, occ_off, occ_rows, trail, meta, queue, qmeta,
      nvars, nrows, v
    ) == 1 && wassat_cover_propagate(
      status, covered, counts, row_lits, row_off, row_len,
      occ_off, occ_rows, adj_off, adj, trail, meta, queue, qmeta,
      nvars, nrows
    ) == 1
      wassat_cover_undo(
        status, covered, counts, trail, meta, nvars, nrows, base_mark
      )
      return -1
    i += 1

  wassat_cover_undo(
    status, covered, counts, trail, meta, nvars, nrows, base_mark
  )
  -1

# Run the sparse search on already constructed covering arrays.  This is the
# shared engine used by the standalone recognizer and by conditioned
# directed-kernel SCCs.
#
# `solution_limit == 1` is ordinary SAT/UNSAT search.  A limit of two counts
# just far enough to distinguish UNSAT, UNIQUE, and MULTI; it refuses to make
# that distinction if a satisfying leaf leaves any variable unassigned.
-> wassat_cover_run_arrays(row_lits, row_off, row_len, nrows,
                           occ_off, occ_rows, adj_off, adj,
                           nvars, max_row, initial_excluded, nexcluded,
                           node_cap, solution_limit) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64 i64 i64[] i64 i64 i64)
  nlits = occ_off[nvars + 1]
  status = i8[nvars + 1]
  covered = i8[nrows]
  counts = i64[nrows]
  r = 0
  while r < nrows
    counts[r] = row_len[r]
    r += 1

  # Along one monotone search path, each variable changes once, each row is
  # covered once, and each occurrence count is decremented at most once.
  trail = i64[nvars + nrows + nlits + 8]
  queue = i64[nrows + 8]
  qmeta = i64[1]
  # trail size, nodes, cap, forced selections, cap-exhausted, solutions,
  # unsafe-free-variable witness
  meta = i64[7]
  meta[2] = node_cap
  candidate_width = max_row
  candidate_width = 1 if candidate_width < 1
  candidates = i64[(nvars + 1) * candidate_width]
  scores = i64[(nvars + 1) * candidate_width]
  first_model = i8[nvars + 1]

  ok = 1
  # Conditioned directed-kernel components can contain positive unit rows.
  # Seed them before applying external exclusions; later duplicate queue
  # entries are harmless because propagation rechecks the live row count.
  r = 0
  while r < nrows && ok == 1
    ok = 0 if counts[r] == 0
    if counts[r] == 1
      queue[qmeta[0]] = r
      qmeta[0] += 1
    r += 1
  i = 0
  while i < nexcluded && ok == 1
    ok = wassat_cover_exclude(
      status, covered, counts, occ_off, occ_rows, trail, meta, queue, qmeta,
      nvars, nrows, initial_excluded[i]
    )
    i += 1
  if ok == 1
    ok = wassat_cover_propagate(
      status, covered, counts, row_lits, row_off, row_len,
      occ_off, occ_rows, adj_off, adj, trail, meta, queue, qmeta,
      nvars, nrows
    )

  search_code = -1
  if ok == 1
    search_code = wassat_cover_dfs(
      status, covered, counts, row_lits, row_off, row_len, nrows,
      occ_off, occ_rows, adj_off, adj, trail, meta, queue, qmeta,
      candidates, scores, first_model, solution_limit,
      candidate_width, nvars, 0
    )

  result_status = 0
  if search_code != 0
    result_status = meta[5] > 0 ? 1 : -1
  model = []
  if meta[5] > 0
    v = 1
    while v <= nvars
      model.push(first_model[v] == 1 ? v : 0 - v)
      v += 1
  {
    "status": result_status, "model": model,
    "solutions": meta[5], "unique": search_code == -1 && meta[5] == 1,
    "multi": meta[5] >= 2, "nodes": meta[1], "forced": meta[3],
    "unsafe_free": meta[6] == 1
  }

# Recognize and solve with an explicit solution limit.  Keeping the public
# one-model wrapper separate avoids imposing enumeration semantics on ordinary
# callers.  The returned status follows Wassat's convention: 1 SAT, -1 UNSAT,
# 0 unrecognized or node-cap miss.
-> wassat_covering_solve_limit(formula, node_cap, solution_limit)
  miss = {
    "recognized": false, "status": 0, "model": [],
    "nodes": 0, "forced": 0, "solutions": 0,
    "unique": false, "multi": false, "unsafe_free": false
  }
  return miss unless formula.has_key?("flat_ncl")
  nvars = formula["nvars"]
  ncl = formula["flat_ncl"]
  return miss if nvars < 1 || nvars > WASSAT_COVER_MAX_VARS
  return miss if ncl < 2 || node_cap < 1
  return miss unless solution_limit == 1 || solution_limit == 2

  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  seen = i64[nvars + 1]
  occ_count = i64[nvars + 2]
  degree = i64[nvars + 2]
  nrows = 0
  nedges = 0
  nlits = 0
  max_row = 0
  stamp = 0

  # Strict shape and resource census.
  ci = 0
  while ci < ncl
    off = fcs[ci]
    n = fcl[ci]
    stamp += 1
    if n >= 3
      return miss if n > WASSAT_COVER_MAX_ROW
      j = 0
      while j < n
        v = fla[off + j]
        return miss if v < 1 || v > nvars || seen[v] == stamp
        seen[v] = stamp
        occ_count[v] += 1
        j += 1
      nrows += 1
      nlits += n
      max_row = n if n > max_row
      return miss if nrows > WASSAT_COVER_MAX_ROWS || nlits > WASSAT_COVER_MAX_LITS
    elsif n == 2
      a = fla[off]
      b = fla[off + 1]
      return miss unless a < 0 && b < 0
      a = 0 - a
      b = 0 - b
      return miss if a < 1 || a > nvars || b < 1 || b > nvars || a == b
      degree[a] += 1
      degree[b] += 1
      nedges += 1
      return miss if nedges > WASSAT_COVER_MAX_EDGES
    else
      return miss
    ci += 1
  return miss if nrows == 0 || nedges == 0

  row_lits = i64[nlits]
  row_off = i64[nrows + 1]
  row_len = i64[nrows]
  occ_off = i64[nvars + 2]
  adj_off = i64[nvars + 2]
  occ_cursor = i64[nvars + 1]
  adj_cursor = i64[nvars + 1]
  v = 1
  while v <= nvars
    occ_off[v + 1] = occ_off[v] + occ_count[v]
    adj_off[v + 1] = adj_off[v] + degree[v]
    occ_cursor[v] = occ_off[v]
    adj_cursor[v] = adj_off[v]
    v += 1
  occ_rows = i64[nlits]
  adj = i64[2 * nedges]

  # Materialize compact positive rows plus variable-to-row and conflict
  # adjacency lists.  Search never touches boxed clause objects.
  ri = 0
  lp = 0
  ci = 0
  while ci < ncl
    off = fcs[ci]
    n = fcl[ci]
    if n >= 3
      row_off[ri] = lp
      row_len[ri] = n
      j = 0
      while j < n
        v = fla[off + j]
        row_lits[lp] = v
        lp += 1
        occ_rows[occ_cursor[v]] = ri
        occ_cursor[v] += 1
        j += 1
      ri += 1
    else
      a = 0 - fla[off]
      b = 0 - fla[off + 1]
      adj[adj_cursor[a]] = b
      adj_cursor[a] += 1
      adj[adj_cursor[b]] = a
      adj_cursor[b] += 1
    ci += 1
  row_off[nrows] = nlits

  initial = i64[1]
  result = wassat_cover_run_arrays(
    row_lits, row_off, row_len, nrows, occ_off, occ_rows, adj_off, adj,
    nvars, max_row, initial, 0, node_cap, solution_limit
  )
  {
    "recognized": true, "status": result["status"],
    "model": result["model"], "nodes": result["nodes"],
    "forced": result["forced"], "solutions": result["solutions"],
    "unique": result["unique"], "multi": result["multi"],
    "unsafe_free": result["unsafe_free"]
  }

-> wassat_covering_solve(formula, node_cap = WASSAT_COVER_NODE_CAP)
  wassat_covering_solve_limit(formula, node_cap, 1)
