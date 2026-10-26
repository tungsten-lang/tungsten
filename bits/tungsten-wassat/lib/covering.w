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
WASSAT_COVER_MAX_ROW = 160
WASSAT_COVER_MAX_LITS = 500000
WASSAT_COVER_NODE_CAP = 200000

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
                      occ_off, occ_rows, max_row) (i64 i8[] i64[] i64[] i64[] i64) i64
  score = 0
  num = 64 ## i64
  num = 1024 if max_row > 64
  p = occ_off[v]
  stop = occ_off[v + 1]
  while p < stop
    r = occ_rows[p]
    score += num / counts[r] if covered[r] == 0 && counts[r] > 0
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
      score = wassat_cover_score(v, covered, counts, occ_off, occ_rows, max_row)
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

fn wassat_cover_pop64(x) (i64) i64
  ccall_nobox("__w_bit_ctpop_u64", x) ## i64

fn wassat_cover_ctz64(x) (i64) i64
  ccall_nobox("__w_bit_cttz_u64", x) ## i64

fn wassat_af_bitset_dfs(dom, out_att, conf, und_stack, need_stack, in_stack,
                        cand_stack, score_stack, sol_in, meta, depth) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  meta[0] += 1
  if meta[0] > meta[1]
    meta[2] = 1
    return 0 ## i64
  full32 = 4294967295 ## i64
  one = 1 ## i64
  four = 4 ## i64
  five = 5 ## i64
  t31 = 31 ## i64
  base16 = depth << four
  tz = 0 ## i64
  v = 0 ## i64
  v16 = 0 ## i64
  c = 0 ## i64
  k = 0 ## i64
  u = 0 ## i64
  x = 0 ## i64
  utz = 0 ## i64
  uw = 0 ## i64
  ub = 0 ## i64
  u16 = 0 ## i64
  cbase = 0 ## i64
  ncand = 0 ## i64
  bv16 = 0 ## i64
  m = 0 ## i64
  out_c = 0 ## i64
  conf_c = 0 ## i64
  sc = 0 ## i64
  at = 0 ## i64
  next16 = 0 ## i64
  ci = 0 ## i64
  child = 0 ## i64
  rem_c = 0 ## i64
  while true
    changed = false
    best_v = -1 ## i64
    best_cnt = 999999 ## i64
    i = 0 ## i64
    while i < 16 && !changed
      mask = need_stack[base16 + i]
      while mask != 0 && !changed
        tz = wassat_cover_ctz64(mask)
        v = (i << five) + tz
        mask = mask & (mask - one)
        v16 = v << four
        c = 0 ## i64
        k = 0 ## i64
        while k < 16
          c += wassat_cover_pop64(und_stack[base16 + k] & dom[v16 + k])
          k += one
        return -1 ## i64 if c == 0
        if c == 1
          u = -1 ## i64
          k = 0 ## i64
          while k < 16 && u < 0
            x = und_stack[base16 + k] & dom[v16 + k]
            if x != 0
              utz = wassat_cover_ctz64(x)
              u = (k << five) + utz
            k += one
          return -1 ## i64 if u < 0
          uw = u >> five
          ub = one << (u & t31)
          in_stack[base16 + uw] = in_stack[base16 + uw] | ub
          und_stack[base16 + uw] = und_stack[base16 + uw] & (ub ^ full32)
          need_stack[base16 + uw] = need_stack[base16 + uw] & (ub ^ full32)
          u16 = u << four
          k = 0 ## i64
          while k < 16
            und_stack[base16 + k] = und_stack[base16 + k] & (conf[u16 + k] ^ full32)
            need_stack[base16 + k] = need_stack[base16 + k] & (out_att[u16 + k] ^ full32)
            k += one
          changed = true
          meta[3] += 1
        elsif c < best_cnt
          best_cnt = c
          best_v = v
      i += one
    if !changed
      any_need = false
      k = 0 ## i64
      while k < 16
        if need_stack[base16 + k] != 0
          any_need = true
          k = 16 ## i64
        else
          k += one
      unless any_need
        k = 0 ## i64
        while k < 16
          sol_in[k] = in_stack[base16 + k]
          k += one
        return 1 ## i64
      return -1 ## i64 if best_v < 0
      cbase = depth * (160 ## i64)
      ncand = 0 ## i64
      bv16 = best_v << four
      i = 0 ## i64
      while i < 16
        m = dom[bv16 + i] & und_stack[base16 + i]
        while m != 0
          utz = wassat_cover_ctz64(m)
          u = (i << five) + utz
          m = m & (m - one)
          u16 = u << four
          out_c = 0 ## i64
          conf_c = 0 ## i64
          k = 0 ## i64
          while k < 16
            out_c += wassat_cover_pop64(need_stack[base16 + k] & out_att[u16 + k])
            conf_c += wassat_cover_pop64(und_stack[base16 + k] & conf[u16 + k])
            k += one
          sc = (out_c << four) + conf_c
          at = ncand
          while at > 0 && score_stack[cbase + at - one] < sc
            cand_stack[cbase + at] = cand_stack[cbase + at - one]
            score_stack[cbase + at] = score_stack[cbase + at - one]
            at -= one
          cand_stack[cbase + at] = u
          score_stack[cbase + at] = sc
          ncand += one
        i += one
      next16 = (depth + one) << four
      ci = 0 ## i64
      while ci < ncand
        u = cand_stack[cbase + ci]
        u16 = u << four
        uw = u >> five
        ub = one << (u & t31)
        k = 0 ## i64
        while k < 16
          in_stack[next16 + k] = in_stack[base16 + k]
          und_stack[next16 + k] = und_stack[base16 + k] & (conf[u16 + k] ^ full32)
          need_stack[next16 + k] = need_stack[base16 + k] & (out_att[u16 + k] ^ full32)
          k += one
        in_stack[next16 + uw] = in_stack[next16 + uw] | ub
        und_stack[next16 + uw] = und_stack[next16 + uw] & (ub ^ full32)
        need_stack[next16 + uw] = need_stack[next16 + uw] & (ub ^ full32)
        child = wassat_af_bitset_dfs(
          dom, out_att, conf, und_stack, need_stack, in_stack,
          cand_stack, score_stack, sol_in, meta, depth + one
        )
        return 1 ## i64 if child == 1
        return 0 ## i64 if child == 0
        und_stack[base16 + uw] = und_stack[base16 + uw] & (ub ^ full32)
        rem_c = 0 ## i64
        k = 0 ## i64
        while k < 16
          rem_c += wassat_cover_pop64(und_stack[base16 + k] & dom[bv16 + k])
          k += one
        ci = ncand if rem_c <= 1
        ci += one
      rem_c = 0 ## i64
      k = 0 ## i64
      while k < 16
        rem_c += wassat_cover_pop64(und_stack[base16 + k] & dom[bv16 + k])
        k += one
      return -1 ## i64 if rem_c == 0
  -1 ## i64

-> wassat_af_bitset_solve(fla, fcs, fcl, ncl, nvars, node_cap) (i64[] i64[] i64[] i64 i64 i64)
  full32 = 4294967295 ## i64
  one = 1 ## i64
  in_att = i64[512 * 16]
  out_att = i64[512 * 16]
  conf = i64[512 * 16]
  dom = i64[512 * 16]
  self_att = i8[512]
  pos_seen = i8[512]
  ci = 0
  while ci < ncl
    off = fcs[ci]
    n = fcl[ci]
    if n >= 3
      v = fla[off] - 1
      if v < 0 || v >= nvars || pos_seen[v] != 0
        return {"recognized": false, "status": 0, "model": [], "nodes": 0, "forced": 0, "solutions": 0, "unique": false, "multi": false, "unsafe_free": false}
      pos_seen[v] = 1
      v16 = v << 4
      dom[v16 + (v >> 5)] = dom[v16 + (v >> 5)] | (one << (v & 31))
      j = 1
      while j < n
        a = fla[off + j] - 1
        in_att[v16 + (a >> 5)] = in_att[v16 + (a >> 5)] | (one << (a & 31))
        out_att[(a << 4) + (v >> 5)] = out_att[(a << 4) + (v >> 5)] | (one << (v & 31))
        dom[v16 + (a >> 5)] = dom[v16 + (a >> 5)] | (one << (a & 31))
        j += 1
    else
      u = (0 - fla[off]) - 1
      v = (0 - fla[off + 1]) - 1
      if u == v
        self_att[u] = 1
      else
        conf[(u << 4) + (v >> 5)] = conf[(u << 4) + (v >> 5)] | (one << (v & 31))
        conf[(v << 4) + (u >> 5)] = conf[(v << 4) + (u >> 5)] | (one << (u & 31))
    ci += 1
  v = 0
  while v < nvars
    v16 = v << 4
    k = 0
    while k < 16
      conf[v16 + k] = conf[v16 + k] | in_att[v16 + k] | out_att[v16 + k]
      k += 1
    vw = v >> 5
    vb = one << (v & 31)
    if (conf[v16 + vw] & vb) != 0
      self_att[v] = 1
      conf[v16 + vw] = conf[v16 + vw] & (vb ^ full32)
      dom[v16 + vw] = dom[v16 + vw] & (vb ^ full32)
    v += 1
  und_stack = i64[514 * 16]
  need_stack = i64[514 * 16]
  in_stack = i64[514 * 16]
  cand_stack = i64[514 * 160]
  score_stack = i64[514 * 160]
  sol_in = i64[16]
  meta = i64[4]
  meta[1] = node_cap
  v = 0
  while v < nvars
    vw = v >> 5
    vb = one << (v & 31)
    need_stack[vw] = need_stack[vw] | vb
    und_stack[vw] = und_stack[vw] | vb if self_att[v] == 0
    v += 1
  rc = wassat_af_bitset_dfs(
    dom, out_att, conf, und_stack, need_stack, in_stack,
    cand_stack, score_stack, sol_in, meta, 0
  )
  model = []
  if rc == 1
    v = 0
    while v < nvars
      bit = (sol_in[v >> 5] >> (v & 31)) & 1
      model.push(bit == 1 ? (v + 1) : (0 - (v + 1)))
      v += 1
  {
    "recognized": true, "status": rc, "model": model,
    "nodes": meta[0], "forced": meta[3], "solutions": rc == 1 ? 1 : 0,
    "unique": false, "multi": false, "unsafe_free": false
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
  if nvars >= 350 && nedges >= nvars * 20
    if nvars <= 512 && nrows == nvars && solution_limit == 1
      return wassat_af_bitset_solve(fla, fcs, fcl, ncl, nvars, 600000)
    return miss

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

# Strip redundant 1-step resolvent mixed clauses [-v, b_1, ..., b_m] from
# stable-extension / Argumentation Framework encodings where both the binary
# attack clause [-v, -a] and the positive defence clause [a, b_1, ..., b_m]
# are already present in the formula.
-> wassat_try_strip_af_resolvents(formula)
  return false unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return false if nv < 32 || nv > 2048 || ncl <= nv * 3 || ncl > 250000
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  n_pos = 0
  n_bin_neg = 0
  n_mixed = 0
  ci = 0
  while ci < ncl
    off = fcs[ci]
    n = fcl[ci]
    return false if n < 1
    if n == 2 && fla[off] < 0 && fla[off + 1] < 0
      n_bin_neg += 1
    else
      neg_cnt = 0
      j = 0
      while j < n
        neg_cnt += 1 if fla[off + j] < 0
        j += 1
      if neg_cnt == 0
        n_pos += 1
      elsif neg_cnt == 1 && n >= 2
        n_mixed += 1
      else
        return false
    ci += 1
  return false unless n_pos == nv && n_bin_neg >= nv && n_mixed >= nv

  stride = nv + 1
  bin_adj = i8[stride * stride]
  pos_ci = i64[nv + 1]
  pos_tail_len = i64[nv + 1]
  pos_tail_sum = i64[nv + 1]
  head = i64[1024]
  next_a = i64[nv + 1]
  ci = 0
  while ci < ncl
    off = fcs[ci]
    n = fcl[ci]
    if n == 2 && fla[off] < 0 && fla[off + 1] < 0
      u = 0 - fla[off]
      v = 0 - fla[off + 1]
      if u >= 1 && u <= nv && v >= 1 && v <= nv
        bin_adj[u * stride + v] = 1
        bin_adj[v * stride + u] = 1
    else
      neg_cnt = 0
      j = 0
      while j < n
        neg_cnt += 1 if fla[off + j] < 0
        j += 1
      if neg_cnt == 0
        a = fla[off]
        return false if a < 1 || a > nv || pos_ci[a] != 0
        pos_ci[a] = ci + 1
        pos_tail_len[a] = n - 1
        tsum = 0
        j = 1
        while j < n
          tsum += fla[off + j]
          j += 1
        pos_tail_sum[a] = tsum
        b = tsum & 1023
        next_a[a] = head[b]
        head[b] = a
    ci += 1

  drop = i8[ncl]
  seen = i64[nv + 1]
  stamp = 0
  ndropped = 0
  ci = 0
  while ci < ncl
    off = fcs[ci]
    n = fcl[ci]
    if !(n == 2 && fla[off] < 0 && fla[off + 1] < 0)
      neg_lit = 0
      neg_cnt = 0
      msum = 0
      stamp += 1
      j = 0
      while j < n
        lit = fla[off + j]
        if lit < 0
          neg_lit = lit
          neg_cnt += 1
        else
          msum += lit
          seen[lit] = stamp if lit >= 1 && lit <= nv
        j += 1
      if neg_cnt == 1
        v = 0 - neg_lit
        m = n - 1
        a = head[msum & 1023]
        matched = false
        while a > 0 && !matched
          if pos_tail_len[a] == m && pos_tail_sum[a] == msum && bin_adj[v * stride + a] == 1 && seen[a] != stamp && seen[v] != stamp
            pci = pos_ci[a] - 1
            poff = fcs[pci]
            plen = fcl[pci]
            all_in = true
            k = 1
            while k < plen
              p = fla[poff + k]
              if p < 1 || p > nv || seen[p] != stamp
                all_in = false
                break
              k += 1
            matched = true if all_in
          a = next_a[a]
        if matched
          drop[ci] = 1
          ndropped += 1
    ci += 1
  return false if ndropped == 0

  new_ncl = ncl - ndropped
  new_offs = i64[new_ncl]
  new_lens = i64[new_ncl]
  new_nlits = 0
  ci = 0
  while ci < ncl
    new_nlits += fcl[ci] if drop[ci] == 0
    ci += 1
  new_lits = i64[new_nlits]
  wi = 0
  wp = 0
  ci = 0
  while ci < ncl
    if drop[ci] == 0
      off = fcs[ci]
      n = fcl[ci]
      new_offs[wi] = wp
      new_lens[wi] = n
      j = 0
      while j < n
        new_lits[wp] = fla[off + j]
        wp += 1
        j += 1
      wi += 1
    ci += 1
  formula["clauses"] = []
  formula["boxed"] = false
  formula["nclauses"] = new_ncl
  formula["flat_lits"] = new_lits
  formula["flat_offs"] = new_offs
  formula["flat_lens"] = new_lens
  formula["flat_ncl"] = new_ncl
  formula["flat_nlits"] = new_nlits
  true
