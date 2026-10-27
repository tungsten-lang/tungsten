# Generic exact-one block-CSP engine.
#
# Many generated CNFs are finite-domain CSPs in disguise: the variables
# partition into disjoint blocks (one positive clause per block), every
# block carries its complete at-most-one binary set, and the remaining
# clauses express binary exclusions and arbitrary residual constraints
# over block choices. Graph coloring, Sudoku-like grids, permutation and
# Hamiltonian encodings, subgraph isomorphism, and quasigroup-style
# tables all have this shape, with different generators behind them.
#
# Recognition is strict: every variable in exactly one block, block
# sizes 2..24, complete in-block at-most-one sets (so each block chooses
# exactly one true variable in any model), and every other clause is
# carried as a residual check clause evaluated exactly under the
# exact-one assignment. The solver is a bounded DFS over blocks with
# singleton propagation through the binary exclusions and MRV branch
# choice. It returns SAT only with a model the caller re-checks against
# the original CNF, and UNSAT only after exhaustive search inside the
# node cap (fast-only; proof modes fall through).

WASSAT_BLOCK_MAX_VARS = 10000
WASSAT_BLOCK_MAX_CLAUSES = 400000
WASSAT_BLOCK_MAX_BLOCKS = 300
WASSAT_BLOCK_MAX_SIZE = 24
WASSAT_BLOCK_MAX_OTHER = 20000
WASSAT_BLOCK_MAX_OTHER_LITS = 200000
WASSAT_BLOCK_NODE_CAP = 200000

fn wassat_block_pop64(x) (i64) i64
  ccall_nobox("__w_bit_ctpop_u64", x) ## i64

fn wassat_block_ctz64(x) (i64) i64
  ccall_nobox("__w_bit_cttz_u64", x) ## i64

# Evaluate one residual clause under the current choices.
# Returns 1 satisfied, 0 undecided, -1 falsified.
-> wassat_block_clause_state(fla, fcs, fcl, ci, var_block, var_bit, choice, base) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64) i64
  off = fcs[ci]
  n = fcl[ci]
  undecided = 0
  j = 0
  while j < n
    l = fla[off + j]
    v = l < 0 ? 0 - l : l
    b = var_block[v] - 1
    ch = choice[base + b]
    if ch < 0
      undecided = 1
    else
      picked = ch == var_bit[v]
      return 1 if (l > 0 && picked) || (l < 0 && !picked)
    j += 1
  undecided == 1 ? 0 : 0 - 1

# Check every residual clause touching block b. False on a falsified clause.
-> wassat_block_check_touching(fla, fcs, fcl, var_block, var_bit, choice, base, touch_off, touch_list, b) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[] i64) bool
  i = touch_off[b]
  stop = touch_off[b + 1]
  while i < stop
    ci = touch_list[i]
    return false if wassat_block_clause_state(
      fla, fcs, fcl, ci, var_block, var_bit, choice, base
    ) < 0
    i += 1
  true

-> wassat_block_csp_dfs(fla, fcs, fcl, var_block, var_bit, block_vars, forbid,
                        touch_off, touch_list, dom_stack, choice_stack, applied_stack,
                        sol, pm, nb, depth) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i8[] i64[] i64[] i64 i64) bool
  pm[0] += 1
  if pm[0] > pm[1]
    pm[2] = 1
    return false
  one = 1 ## i64
  base = depth * nb
  assigned = 0
  b = 0
  while b < nb
    assigned += 1 if choice_stack[base + b] >= 0
    b += 1
  changed = true
  while changed
    changed = false
    b = 0
    while b < nb
      if choice_stack[base + b] < 0
        d = dom_stack[base + b]
        return false if d == 0
        if (d & (d - one)) == 0
          choice_stack[base + b] = wassat_block_ctz64(d)
          assigned += 1
      if choice_stack[base + b] >= 0 && applied_stack[base + b] == 0
        applied_stack[base + b] = 1
        changed = true
        u = block_vars[b * WASSAT_BLOCK_MAX_SIZE + choice_stack[base + b]]
        bj = 0
        while bj < nb
          if bj != b
            mask = forbid[u * nb + bj]
            if mask != 0
              if choice_stack[base + bj] >= 0
                return false if ((mask >> choice_stack[base + bj]) & one) != 0
              else
                dj = dom_stack[base + bj]
                ndj = dj & (dj ^ (dj & mask))
                return false if ndj == 0
                dom_stack[base + bj] = ndj
          bj += 1
        return false unless wassat_block_check_touching(
          fla, fcs, fcl, var_block, var_bit, choice_stack, base, touch_off, touch_list, b
        )
      b += 1
  if assigned == nb
    b = 0
    while b < nb
      sol[b] = choice_stack[base + b]
      b += 1
    return true
  # MRV: branch on the unassigned block with the smallest live domain.
  best = 0 - 1
  best_size = 100
  b = 0
  while b < nb
    if choice_stack[base + b] < 0
      sz = wassat_block_pop64(dom_stack[base + b])
      if sz < best_size
        best_size = sz
        best = b
    b += 1
  return false if best < 0
  next_base = (depth + 1) * nb
  d = dom_stack[base + best]
  while d != 0
    bit = wassat_block_ctz64(d)
    d = d & (d - one)
    b = 0
    while b < nb
      dom_stack[next_base + b] = dom_stack[base + b]
      choice_stack[next_base + b] = choice_stack[base + b]
      applied_stack[next_base + b] = applied_stack[base + b]
      b += 1
    dom_stack[next_base + best] = one << bit
    choice_stack[next_base + best] = bit
    if wassat_block_csp_dfs(
      fla, fcs, fcl, var_block, var_bit, block_vars, forbid,
      touch_off, touch_list, dom_stack, choice_stack, applied_stack,
      sol, pm, nb, depth + 1
    )
      return true
    return false if pm[2] != 0
  false

-> wassat_block_csp_miss
  { "recognized": false, "status": 0, "blocks": 0, "nodes": 0, "model": [] }

-> wassat_block_csp_solve(formula)
  miss = wassat_block_csp_miss
  return miss unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return miss if nv < 4 || nv > WASSAT_BLOCK_MAX_VARS
  return miss if ncl < 4 || ncl > WASSAT_BLOCK_MAX_CLAUSES
  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]
  one = 1 ## i64

  # Tentative blocks: all-positive clauses over still-unclaimed variables.
  block_len = i64[WASSAT_BLOCK_MAX_BLOCKS]
  block_vars = i64[WASSAT_BLOCK_MAX_BLOCKS * WASSAT_BLOCK_MAX_SIZE]
  block_clause = i64[WASSAT_BLOCK_MAX_BLOCKS]
  var_block = i64[nv + 1]
  var_bit = i64[nv + 1]
  is_block_clause = i8[ncl]
  nb = 0
  covered = 0
  ci = 0
  while ci < ncl
    n = fcl[ci]
    if n >= 2 && n <= WASSAT_BLOCK_MAX_SIZE && nb < WASSAT_BLOCK_MAX_BLOCKS
      off = fcs[ci]
      ok = true
      j = 0
      while j < n && ok
        v = fla[off + j]
        ok = false if v < 1 || v > nv || var_block[v] != 0
        j += 1
      if ok
        j = 0
        while j < n && ok
          ok = false if j > 0 && fla[off + j] == fla[off + j - 1]
          j += 1
      if ok
        block_len[nb] = n
        block_clause[nb] = ci
        is_block_clause[ci] = 1
        j = 0
        while j < n
          v = fla[off + j]
          block_vars[nb * WASSAT_BLOCK_MAX_SIZE + j] = v
          var_block[v] = nb + 1
          var_bit[v] = j
          j += 1
        covered += n
        nb += 1
    ci += 1
  return miss if nb < 4 || covered != nv

  # Binaries: in-block at-most-one sets and cross-block forbids. Anything
  # else is a residual check clause.
  amo_mask = i64[nv + 1]
  forbid = i64[(nv + 1) * nb]
  dom0 = i64[nb]
  b = 0
  while b < nb
    dom0[b] = (one << block_len[b]) - one
    b += 1
  other = []
  other_lits = 0
  ci = 0
  while ci < ncl
    n = fcl[ci]
    off = fcs[ci]
    if is_block_clause[ci] == 1
      ci += 1
      next
    if n == 1
      l = fla[off]
      v = l < 0 ? 0 - l : l
      return miss if v < 1 || v > nv
      bv = var_block[v] - 1
      if l > 0
        dom0[bv] = dom0[bv] & (one << var_bit[v])
      else
        d = dom0[bv]
        dom0[bv] = d & (d ^ (d & (one << var_bit[v])))
    elsif n == 2 && fla[off] < 0 && fla[off + 1] < 0
      u = 0 - fla[off]
      v = 0 - fla[off + 1]
      return miss if u < 1 || u > nv || v < 1 || v > nv
      if u != v
        bu = var_block[u] - 1
        bv = var_block[v] - 1
        if bu == bv
          amo_mask[u] = amo_mask[u] | (one << var_bit[v])
          amo_mask[v] = amo_mask[v] | (one << var_bit[u])
        else
          forbid[u * nb + bv] = forbid[u * nb + bv] | (one << var_bit[v])
          forbid[v * nb + bu] = forbid[v * nb + bu] | (one << var_bit[u])
    else
      other.push(ci)
      other_lits += n
      return miss if other.size > WASSAT_BLOCK_MAX_OTHER
      return miss if other_lits > WASSAT_BLOCK_MAX_OTHER_LITS
    ci += 1

  # Complete at-most-one inside every block, or the exact-one reading is
  # not forced by the clauses and a CSP refutation would not lift.
  b = 0
  while b < nb
    full = (one << block_len[b]) - one
    j = 0
    while j < block_len[b]
      v = block_vars[b * WASSAT_BLOCK_MAX_SIZE + j]
      return miss unless amo_mask[v] == (full ^ (one << j))
      j += 1
    b += 1

  # Residual-clause touch lists per block (unique blocks per clause).
  touch_off = i64[nb + 1]
  oi = 0
  while oi < other.size
    ci = other[oi] ## i64
    off = fcs[ci]
    n = fcl[ci]
    j = 0
    while j < n
      l = fla[off + j]
      v = l < 0 ? 0 - l : l
      return miss if v < 1 || v > nv
      bv = var_block[v] - 1
      dup = false
      k = 0
      while k < j && !dup
        l2 = fla[off + k]
        v2 = l2 < 0 ? 0 - l2 : l2
        dup = true if var_block[v2] - 1 == bv
        k += 1
      touch_off[bv + 1] += 1 unless dup
      j += 1
    oi += 1
  b = 0
  while b < nb
    touch_off[b + 1] += touch_off[b]
    b += 1
  touch_list = i64[touch_off[nb] > 0 ? touch_off[nb] : 1]
  cursor = i64[nb]
  b = 0
  while b < nb
    cursor[b] = touch_off[b]
    b += 1
  oi = 0
  while oi < other.size
    ci = other[oi] ## i64
    off = fcs[ci]
    n = fcl[ci]
    j = 0
    while j < n
      l = fla[off + j]
      v = l < 0 ? 0 - l : l
      bv = var_block[v] - 1
      dup = false
      k = 0
      while k < j && !dup
        l2 = fla[off + k]
        v2 = l2 < 0 ? 0 - l2 : l2
        dup = true if var_block[v2] - 1 == bv
        k += 1
      unless dup
        touch_list[cursor[bv]] = ci
        cursor[bv] += 1
      j += 1
    oi += 1

  dom_stack = i64[(nb + 1) * nb]
  choice_stack = i64[(nb + 1) * nb]
  applied_stack = i8[(nb + 1) * nb]
  sol = i64[nb]
  pm = i64[3]
  pm[1] = WASSAT_BLOCK_NODE_CAP
  b = 0
  while b < nb
    dom_stack[b] = dom0[b]
    choice_stack[b] = 0 - 1
    b += 1
  found = wassat_block_csp_dfs(
    fla, fcs, fcl, var_block, var_bit, block_vars, forbid,
    touch_off, touch_list, dom_stack, choice_stack, applied_stack,
    sol, pm, nb, 0
  )
  if found
    model = i64[nv]
    v = 1
    while v <= nv
      bv = var_block[v] - 1
      chosen = block_vars[bv * WASSAT_BLOCK_MAX_SIZE + sol[bv]]
      model[v - 1] = v == chosen ? v : 0 - v
      v += 1
    return miss unless wassat_model_satisfies?(formula, model)
    { "recognized": true, "status": 1, "blocks": nb,
      "nodes": pm[0], "model": model }
  elsif pm[2] == 0
    { "recognized": true, "status": -1, "blocks": nb,
      "nodes": pm[0], "model": [] }
  else
    miss
