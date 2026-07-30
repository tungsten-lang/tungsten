# Exact SCC-prefix solver for ordered directed-kernel encodings.
#
# For each variable v, the accepted clause block is:
#
#   -v -a1
#   -v -a2
#   ...
#    v  a1 a2 ... ak
#
# Thus v is selected exactly when none of its attackers is selected.  The
# block and attacker order are part of this intentionally narrow recognizer;
# any mismatch or resource limit falls through to ordinary Wassat.
#
# Components are considered source-to-sink.  A local assignment is committed
# only after the sparse conflict-cover engine has proved it unique.  A local
# UNSAT result under uniquely fixed predecessors refutes the whole formula;
# multiple models or a node-cap miss merely block that descendant subtree.

WASSAT_DIRECTED_MAX_VARS = 100000
WASSAT_DIRECTED_MAX_CLAUSES = 5000000
WASSAT_DIRECTED_MAX_ATTACKS = 4000000
WASSAT_DIRECTED_MAX_COMPONENTS = 4096
WASSAT_DIRECTED_MAX_COMPONENT_VARS = 1024
WASSAT_DIRECTED_MAX_LOCAL_ROW = 4096
WASSAT_DIRECTED_MAX_LOCAL_CLAUSES = 200000
WASSAT_DIRECTED_MAX_LOCAL_LITS = 1000000
WASSAT_DIRECTED_NODE_CAP = 500000
WASSAT_DIRECTED_COMPONENT_NODE_CAP = 100000
WASSAT_DIRECTED_DENSE_SINGLE_SCC_MIN_VARS = 128
WASSAT_DIRECTED_DENSE_SINGLE_SCC_MIN_AVG_IN = 32

# A single SCC has no unique-prefix decomposition to exploit.  On a large,
# dense component the local conflict-cover search merely spends its full
# model-counting effort before the ordinary SLS/CDCL race gets a turn
# (n320/n384: one SCC, average indegree 95/114, then MULTI).  Sparse cycles
# remain excellent exact-solver inputs, and multi-SCC formulas retain the
# prefix reasoning that makes the crusti family decisive.
-> wassat_directed_defer_dense_single_scc?(nv, ncomp, nattacks)
  ncomp == 1 && nv >= WASSAT_DIRECTED_DENSE_SINGLE_SCC_MIN_VARS && nattacks >= nv * WASSAT_DIRECTED_DENSE_SINGLE_SCC_MIN_AVG_IN

# Retain each positive row's attacker slice while checking the complete
# ordered grammar. state[0] receives the attack count and state[1] the maximum
# indegree.
-> wassat_directed_recognize(lits, offs, lens, ncl, nv,
                             row_off, row_len, state) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[]) i64
  ci = 0
  v = 1
  attacks = 0
  max_in = 0
  while v <= nv
    first_edge = ci
    nin = 0
    while ci < ncl && lens[ci] == 2 && lits[offs[ci]] == 0 - v
      a = lits[offs[ci] + 1]
      return 0 if a >= 0
      a = 0 - a
      return 0 if a < 1 || a > nv
      nin += 1
      attacks += 1
      return 0 if attacks > WASSAT_DIRECTED_MAX_ATTACKS
      ci += 1
    return 0 if ci >= ncl
    poff = offs[ci]
    plen = lens[ci]
    return 0 unless plen == nin + 1
    return 0 unless lits[poff] == v
    j = 0
    while j < nin
      a = lits[poff + j + 1]
      return 0 if a < 1 || a > nv
      return 0 unless a == 0 - lits[offs[first_edge + j] + 1]
      j += 1
    row_off[v] = poff + 1
    row_len[v] = nin
    max_in = nin if nin > max_in
    ci += 1
    v += 1
  return 0 unless ci == ncl
  state[0] = attacks
  state[1] = max_in
  1

# Materialize attacker -> target adjacency for the first Kosaraju pass.
-> wassat_directed_build_graph(lits, row_off, row_len, nv,
                               degree, out_off, cursor, out_adj) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  v = 1
  while v <= nv
    j = 0
    while j < row_len[v]
      a = lits[row_off[v] + j]
      degree[a] += 1
      j += 1
    v += 1
  v = 1
  while v <= nv
    out_off[v + 1] = out_off[v] + degree[v]
    cursor[v] = out_off[v]
    v += 1
  v = 1
  while v <= nv
    j = 0
    while j < row_len[v]
      a = lits[row_off[v] + j]
      out_adj[cursor[a]] = v
      cursor[a] += 1
      j += 1
    v += 1
  0

# Iterative Kosaraju.  The second pass walks the reverse graph in descending
# finish order, so component ids are source-to-sink.
-> wassat_directed_scc(lits, row_off, row_len, out_off, out_adj, nv,
                       seen, comp, order, stack, cursor, state) (i64[] i64[] i64[] i64[] i64[] i64 i8[] i64[] i64[] i64[] i64[] i64[]) i64
  osize = 0
  root = 1
  while root <= nv
    if seen[root] == 0
      sp = 1
      stack[0] = root
      seen[root] = 1
      cursor[root] = out_off[root]
      while sp > 0
        x = stack[sp - 1]
        p = cursor[x]
        if p < out_off[x + 1]
          y = out_adj[p]
          cursor[x] = p + 1
          if seen[y] == 0
            seen[y] = 1
            cursor[y] = out_off[y]
            stack[sp] = y
            sp += 1
        else
          sp -= 1
          order[osize] = x
          osize += 1
    root += 1

  cid = 0
  oi = osize
  while oi > 0
    oi -= 1
    root = order[oi]
    if comp[root] == 0
      cid += 1
      sp = 1
      stack[0] = root
      comp[root] = cid
      while sp > 0
        sp -= 1
        x = stack[sp]
        j = 0
        while j < row_len[x]
          y = lits[row_off[x] + j]
          if comp[y] == 0
            comp[y] = cid
            stack[sp] = y
            sp += 1
          j += 1
  state[0] = cid
  0

# Defend the one-pass component traversal against a numbering mistake.
-> wassat_directed_topological?(lits, row_off, row_len, comp, nv) (i64[] i64[] i64[] i64[] i64) i64
  v = 1
  while v <= nv
    cv = comp[v]
    j = 0
    while j < row_len[v]
      a = lits[row_off[v] + j]
      ca = comp[a]
      return 0 if ca != cv && ca >= cv
      j += 1
    v += 1
  1

# Group global variables by component. Returns the largest component size.
-> wassat_directed_layout(comp, nv, ncomp, comp_size, comp_off,
                          cursor, comp_vars) (i64[] i64 i64 i64[] i64[] i64[] i64[]) i64
  v = 1
  while v <= nv
    comp_size[comp[v]] += 1
    v += 1
  max_size = 0
  c = 1
  while c <= ncomp
    comp_off[c + 1] = comp_off[c] + comp_size[c]
    cursor[c] = comp_off[c]
    max_size = comp_size[c] if comp_size[c] > max_size
    c += 1
  v = 1
  while v <= nv
    c = comp[v]
    comp_vars[cursor[c]] = v
    cursor[c] += 1
    v += 1
  max_size

# A component is ready only when all cross-component attackers have a
# uniquely proved assignment.
-> wassat_directed_ready?(c, lits, row_off, row_len, comp,
                          comp_off, comp_vars, comp_state) (i64 i64[] i64[] i64[] i64[] i64[] i64[] i8[]) i64
  i = comp_off[c]
  while i < comp_off[c + 1]
    v = comp_vars[i]
    j = 0
    while j < row_len[v]
      a = lits[row_off[v] + j]
      ca = comp[a]
      return 0 if ca != c && comp_state[ca] != 1
      j += 1
    i += 1
  1

# Build one conditioned SCC as conflict-cover arrays and count solutions only
# far enough to distinguish UNSAT, UNIQUE, and MULTI.
# kind: -2 resource rejection, -1 UNSAT, 0 cap/unsafe, 1 UNIQUE, 2 MULTI.
-> wassat_directed_local(c, lits, row_off, row_len, comp, comp_off,
                         comp_vars, global_assign, local_of, node_cap) (i64 i64[] i64[] i64[] i64[] i64[] i64[] i8[] i64[] i64)
  begin_at = comp_off[c]
  stop_at = comp_off[c + 1]
  k = stop_at - begin_at
  i = begin_at
  while i < stop_at
    local_of[comp_vars[i]] = i - begin_at + 1
    i += 1

  occ_count = i64[k + 2]
  degree = i64[k + 2]
  initial = i64[k + 1]
  nexcluded = 0
  nrows = 0
  nedges = 0
  nlits = 0
  max_row = 0

  # First pass sizes the compact arrays.  An externally selected attacker
  # both satisfies v's row and forces v false.
  i = begin_at
  while i < stop_at
    v = comp_vars[i]
    lv = local_of[v]
    row_satisfied = false
    width = 1
    j = 0
    while j < row_len[v]
      a = lits[row_off[v] + j]
      if comp[a] == c
        la = local_of[a]
        width += 1
        degree[lv] += 1
        degree[la] += 1
        nedges += 1
      elsif global_assign[a] == 1
        row_satisfied = true
      j += 1
    if row_satisfied
      initial[nexcluded] = lv
      nexcluded += 1
    else
      if width > WASSAT_DIRECTED_MAX_LOCAL_ROW
        return { "kind": -2, "nodes": 0, "forced": 0, "model": [] }
      nrows += 1
      nlits += width
      max_row = width if width > max_row
      occ_count[lv] += 1
      j = 0
      while j < row_len[v]
        a = lits[row_off[v] + j]
        occ_count[local_of[a]] += 1 if comp[a] == c
        j += 1
    if nrows + nedges > WASSAT_DIRECTED_MAX_LOCAL_CLAUSES || nlits + 2 * nedges > WASSAT_DIRECTED_MAX_LOCAL_LITS
      return { "kind": -2, "nodes": 0, "forced": 0, "model": [] }
    i += 1

  row_lits = i64[nlits]
  rows_off = i64[nrows + 1]
  rows_len = i64[nrows]
  occ_off = i64[k + 2]
  adj_off = i64[k + 2]
  occ_cursor = i64[k + 1]
  adj_cursor = i64[k + 1]
  lv = 1
  while lv <= k
    occ_off[lv + 1] = occ_off[lv] + occ_count[lv]
    adj_off[lv + 1] = adj_off[lv] + degree[lv]
    occ_cursor[lv] = occ_off[lv]
    adj_cursor[lv] = adj_off[lv]
    lv += 1
  occ_rows = i64[nlits]
  adj = i64[2 * nedges]

  # Second pass fills rows, occurrence lists, and undirected conflict
  # adjacency.  Duplicate or self attacks remain exact: the sparse engine
  # treats their repeated literals and edges with the same multiplicity.
  ri = 0
  lp = 0
  i = begin_at
  while i < stop_at
    v = comp_vars[i]
    lv = local_of[v]
    row_satisfied = false
    j = 0
    while j < row_len[v]
      a = lits[row_off[v] + j]
      row_satisfied = true if comp[a] != c && global_assign[a] == 1
      j += 1
    unless row_satisfied
      rows_off[ri] = lp
      row_start = lp
      row_lits[lp] = lv
      occ_rows[occ_cursor[lv]] = ri
      occ_cursor[lv] += 1
      lp += 1
      j = 0
      while j < row_len[v]
        a = lits[row_off[v] + j]
        if comp[a] == c
          la = local_of[a]
          row_lits[lp] = la
          occ_rows[occ_cursor[la]] = ri
          occ_cursor[la] += 1
          lp += 1
        j += 1
      rows_len[ri] = lp - row_start
      ri += 1
    j = 0
    while j < row_len[v]
      a = lits[row_off[v] + j]
      if comp[a] == c
        la = local_of[a]
        adj[adj_cursor[lv]] = la
        adj_cursor[lv] += 1
        adj[adj_cursor[la]] = lv
        adj_cursor[la] += 1
      j += 1
    i += 1
  rows_off[nrows] = nlits

  result = wassat_cover_run_arrays(
    row_lits, rows_off, rows_len, nrows, occ_off, occ_rows, adj_off, adj,
    k, max_row, initial, nexcluded, node_cap, 2
  )
  if result["status"] == -1
    return {
      "kind": -1, "nodes": result["nodes"],
      "forced": result["forced"] + nexcluded, "model": []
    }
  if result["unique"] == true
    return {
      "kind": 1, "nodes": result["nodes"],
      "forced": result["forced"] + nexcluded, "model": result["model"]
    }
  if result["multi"] == true
    return {
      "kind": 2, "nodes": result["nodes"],
      "forced": result["forced"] + nexcluded, "model": []
    }
  {
    "kind": 0, "nodes": result["nodes"],
    "forced": result["forced"] + nexcluded, "model": []
  }

# Strictly recognize and attempt the exact unique-prefix decomposition.
-> wassat_directed_kernel_solve(formula,
                                node_cap = WASSAT_DIRECTED_NODE_CAP)
  miss = {
    "recognized": false, "status": 0, "model": [], "components": 0,
    "checked": 0, "unique": 0, "multi": 0, "nodes": 0, "forced": 0
  }
  return miss unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return miss if nv < 1 || nv > WASSAT_DIRECTED_MAX_VARS
  return miss if ncl < nv || ncl > WASSAT_DIRECTED_MAX_CLAUSES
  return miss if node_cap < 1

  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  row_off = i64[nv + 1]
  row_len = i64[nv + 1]
  scan_state = i64[4]
  return miss if wassat_directed_recognize(
    lits, offs, lens, ncl, nv, row_off, row_len, scan_state
  ) == 0
  nattacks = scan_state[0]

  degree = i64[nv + 2]
  out_off = i64[nv + 2]
  cursor = i64[nv + 2]
  out_adj = i64[nattacks]
  wassat_directed_build_graph(
    lits, row_off, row_len, nv, degree, out_off, cursor, out_adj
  )

  seen = i8[nv + 1]
  comp = i64[nv + 1]
  order = i64[nv]
  stack = i64[nv + 1]
  scc_state = i64[4]
  wassat_directed_scc(
    lits, row_off, row_len, out_off, out_adj, nv, seen,
    comp, order, stack, cursor, scc_state
  )
  ncomp = scc_state[0]
  return miss if ncomp < 1 || ncomp > WASSAT_DIRECTED_MAX_COMPONENTS
  return miss if wassat_directed_topological?(
    lits, row_off, row_len, comp, nv
  ) == 0
  if wassat_directed_defer_dense_single_scc?(nv, ncomp, nattacks)
    return {
      "recognized": true, "status": 0, "model": [],
      "components": ncomp, "checked": 0, "unique": 0,
      "multi": 0, "nodes": 0, "forced": 0
    }

  comp_size = i64[ncomp + 2]
  comp_off = i64[ncomp + 2]
  comp_cursor = i64[ncomp + 2]
  comp_vars = i64[nv]
  max_component = wassat_directed_layout(
    comp, nv, ncomp, comp_size, comp_off, comp_cursor, comp_vars
  )
  return miss if max_component > WASSAT_DIRECTED_MAX_COMPONENT_VARS

  comp_state = i8[ncomp + 1]
  global_assign = i8[nv + 1]
  local_of = i64[nv + 1]
  checked = 0
  unique = 0
  multi = 0
  used = 0
  forced = 0
  c = 1
  while c <= ncomp
    if wassat_directed_ready?(
      c, lits, row_off, row_len, comp, comp_off, comp_vars, comp_state
    ) == 1
      remaining = node_cap - used
      if remaining <= 0
        comp_state[c] = -1
      else
        allowance = WASSAT_DIRECTED_COMPONENT_NODE_CAP
        allowance = remaining if remaining < allowance
        local = wassat_directed_local(
          c, lits, row_off, row_len, comp, comp_off, comp_vars,
          global_assign, local_of, allowance
        )
        checked += 1
        used += local["nodes"]
        forced += local["forced"]
        kind = local["kind"]
        if kind == -1
          return {
            "recognized": true, "status": -1, "model": [],
            "components": ncomp, "checked": checked, "unique": unique,
            "multi": multi, "nodes": used, "forced": forced
          }
        elsif kind == 1
          comp_state[c] = 1
          unique += 1
          local["model"].each -> (lit)
            lv2 = lit.abs
            gv = comp_vars[comp_off[c] + lv2 - 1]
            global_assign[gv] = lit > 0 ? 1 : -1
        else
          comp_state[c] = -1
          multi += 1 if kind == 2
    else
      comp_state[c] = -1
    c += 1

  if unique == ncomp
    model = []
    v = 1
    while v <= nv
      model.push(global_assign[v] == 1 ? v : 0 - v)
      v += 1
    return {
      "recognized": true, "status": 1, "model": model,
      "components": ncomp, "checked": checked, "unique": unique,
      "multi": multi, "nodes": used, "forced": forced
    }
  {
    "recognized": true, "status": 0, "model": [],
    "components": ncomp, "checked": checked, "unique": unique,
    "multi": multi, "nodes": used, "forced": forced
  }
