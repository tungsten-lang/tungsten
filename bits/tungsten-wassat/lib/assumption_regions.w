# Optional preparation for repeated, proof-free assumption queries on a parsed
# DIMACS formula. Boundary variables describe the cut; callers may still
# assume any original variable. The ordinary CDCL solver owns models and cores.
use solver
use preprocess

-> wassat_region_query_solver(formula, boundary)
  formula = wassat_region_flat_input(formula)
  facts = wassat_region_flat_facts(formula, boundary)
  nv = formula["nvars"]
  solver = Wassat.from_flat(nv, wassat_raw_artifact(formula, nv), 0)
  facts.each -> (clause)
    solver.add_input_clause(clause)
  solver

# An interior component has at most six variables, so one bit represents
# each complete interior assignment. Boundary rows use up to four variables.
-> wassat_region_root(parent, v) (i32[] i64) i64
  while parent[v] > 0
    ancestor = parent[v] ## i64
    parent[v] = parent[ancestor] if parent[ancestor] > 0
    v = ancestor
  v

# A root stores one minus its component size. A positive entry points to a
# parent. The clause lists use 1-based links so zero can terminate a list.
-> wassat_region_components(lits, offsets, lengths, nc, pins, parent, heads, links) (i64[] i64[] i64[] i64 i8[] i32[] i32[] i32[]) i64
  ci = 0 ## i64
  while ci < nc
    root = 0 ## i64
    j = offsets[ci] ## i64
    stop = j + lengths[ci] ## i64
    while j < stop
      v = lits[j] ## i64
      v = 0 - v if v < 0
      if pins[v] == 0
        a = wassat_region_root(parent, v) ## i64
        if root == 0
          root = a
        elsif root != a
          if parent[a] < parent[root]
            swap = a
            a = root
            root = swap
          parent[root] += parent[a] - 1
          parent[a] = root
      j += 1
    links[ci] = root
    ci += 1
  ci = 0
  while ci < nc
    v = links[ci] ## i64
    if v != 0
      root = wassat_region_root(parent, v)
      links[ci] = heads[root]
      heads[root] = ci + 1
    ci += 1
  0

# Local bits 0..5 denote interior variables, 6..9 denote boundary variables.
-> wassat_region_encode(lits, offsets, lengths, pins, links, head, ids, pos, neg, shape) (i64[] i64[] i64[] i8[] i32[] i64 i32[] i64[] i64[] i64[]) i64
  ni = 0 ## i64
  nb = 0 ## i64
  count = 0 ## i64
  one = 1 ## i64
  while head > 0
    return 0 if count == pos.size
    ci = head - 1 ## i64
    p = 0 ## i64
    n = 0 ## i64
    j = offsets[ci] ## i64
    stop = j + lengths[ci] ## i64
    while j < stop
      lit = lits[j] ## i64
      v = lit ## i64
      v = 0 - v if v < 0
      lo = 0 ## i64
      hi = ni ## i64
      if pins[v] != 0
        lo = 6
        hi = 6 + nb
      k = lo ## i64
      while k < hi && ids[k] != v
        k += 1
      if k == hi
        if lo == 6
          return 0 if nb == 4
          nb += 1
        else
          return 0 if ni == 6
          ni += 1
        ids[k] = v
      bit = one << k ## i64
      if lit < 0
        n |= bit
      else
        p |= bit
      j += 1
    if (p & n) == 0
      pos[count] = p
      neg[count] = n
      count += 1
    head = links[ci]
  shape[0] = ni
  shape[1] = nb
  count

# Propagate the ordinary local clauses once at build time. Cache only facts
# which unit propagation from this boundary row does not already discover.
-> wassat_region_bcp(pos, neg, nc, yes, no) (i64[] i64[] i64 i64 i64) i64
  old = -1 ## i64
  while old != (yes | no)
    old = yes | no
    c = 0 ## i64
    while c < nc
      p = pos[c] ## i64
      n = neg[c] ## i64
      if ((p & yes) | (n & no)) == 0
        free = (p | n) & ((yes | no) ^ -1) ## i64
        return -1 if free == 0
        if (free & (free - 1)) == 0
          yes |= p & free
          no |= n & free
      c += 1
  yes | no

-> wassat_region_clause(ids, fixed, row, consequent) (i32[] i64 i64 i64)
  clause = []
  todo = fixed ## i64
  while todo != 0
    j = cttz(todo) ## i64
    lit = ids[6 + j] ## i64
    lit = 0 - lit if ((row >> j) & 1) != 0
    clause.push(lit)
    todo &= todo - 1
  clause.push(consequent) if consequent != 0
  clause

# Keep a minimal impossible tuple if at least one of its unit consequences
# is missing from ordinary propagation on the corresponding relaxed tuple.
-> wassat_region_new_conflict(table, closure, fixed, row) (i64[] i64[] i64 i64) bool
  return closure[0] >= 0 if fixed == 0
  todo = fixed ## i64
  useful = false
  while todo != 0
    bit = todo & (0 - todo) ## i64
    rest = fixed ^ bit ## i64
    parent = (rest << 4) + (row & rest) ## i64
    return false if table[parent] == 0
    useful = true if (closure[parent] & (bit << 6)) == 0
    todo ^= bit
  useful

# The opposite value must have no witness, and relaxing any one boundary
# literal must restore a witness. This avoids storing supersets of a reason.
-> wassat_region_forced(table, models, fixed, row, opposite, v) (i64[] i64 i64 i64 i64 i64) i64
  if (models & opposite) == 0
    v = 0 - v
  else
    opposite ^= -1
    return 0 if (models & opposite) != 0
  todo = fixed ## i64
  while todo != 0
    bit = todo & (0 - todo) ## i64
    rest = fixed ^ bit ## i64
    parent = (rest << 4) + (row & rest) ## i64
    return 0 if (table[parent] & opposite) == 0
    todo ^= bit
  v

-> wassat_region_compile(pos, neg, nc, ids, ni, nb, truth, clause_models, table, closure, extra) (i64[] i64[] i64 i32[] i64 i64 i64[] i64[] i64[] i64[] Array) i64
  c = 0 ## i64
  while c < nc
    choices = 0 ## i64
    j = 0 ## i64
    while j < ni
      choices |= truth[j] if ((pos[c] >> j) & 1) != 0
      choices |= truth[j] ^ -1 if ((neg[c] >> j) & 1) != 0
      j += 1
    clause_models[c] = choices
    c += 1
  one = 1 ## i64
  rows = one << nb ## i64
  full = rows - 1 ## i64
  r = 0 ## i64
  while r < rows
    yes = r << 6 ## i64
    no = (full ^ r) << 6 ## i64
    models = -1 ## i64
    c = 0
    while c < nc && models != 0
      models &= clause_models[c] if ((pos[c] & yes) | (neg[c] & no)) == 0
      c += 1
    table[(full << 4) + r] = models
    r += 1

  # Union the two extensions of a partial assignment. Each bit of the
  # result denotes a jointly feasible interior assignment.
  fixed = full ## i64
  while fixed >= 0
    row = fixed ## i64
    while row >= 0
      key = (fixed << 4) + row ## i64
      if fixed != full
        free = full ^ fixed ## i64
        bit = free & (0 - free) ## i64
        child = ((fixed | bit) << 4) + row ## i64
        table[key] = table[child] | table[child + bit]
      closure[key] = wassat_region_bcp(pos, neg, nc, row << 6, (fixed ^ row) << 6)
      break if row == 0
      row = (row - 1) & fixed
    fixed -= 1

  fixed = 0
  while fixed <= full
    row = fixed ## i64
    while row >= 0
      key = (fixed << 4) + row ## i64
      models = table[key] ## i64
      assigned = closure[key] ## i64
      if models == 0
        if wassat_region_new_conflict(table, closure, fixed, row)
          extra.push(wassat_region_clause(ids, fixed, row, 0))
      else
        j = 0
        while j < ni
          if ((assigned >> j) & 1) == 0
            v = wassat_region_forced(table, models, fixed, row, truth[j], (ids[j] ## i64))
            extra.push(wassat_region_clause(ids, fixed, row, v)) if v != 0
          j += 1
      break if row == 0
      row = (row - 1) & fixed
    fixed += 1
  0

# Both DIMACS parsers validate their input. The native parser already
# supplies flat buffers, so the normal preparation path shares its storage.
-> wassat_region_flat_input(formula)
  raise "region preparation requires the original DIMACS buffers" if formula["flat_lits_bits"] == 32
  return formula if formula.has_key?("flat_ncl")
  clauses = formula["clauses"]
  offsets = i64[clauses.size]
  lengths = i64[clauses.size]
  count = 0 ## i64
  clauses.each_with_index -> (clause, i)
    offsets[i] = count
    lengths[i] = clause.size
    count += clause.size
  lits = i64[count]
  next_lit = 0 ## i64
  clauses.each -> (clause)
    clause.each -> (lit)
      lits[next_lit] = lit
      next_lit += 1
  { "nvars": formula["nvars"], "clauses": clauses, "boxed": true,
    "flat_ncl": clauses.size, "flat_nlits": count, "flat_lits": lits,
    "flat_offs": offsets, "flat_lens": lengths }

-> wassat_region_query_facts(formula, boundary)
  wassat_region_flat_facts(wassat_region_flat_input(formula), boundary)

-> wassat_region_flat_facts(formula, boundary)
  nv = formula["nvars"] ## i64
  nc = formula["flat_ncl"] ## i64
  raise "region variable IDs exceed signed 32-bit storage" if nv > WASSAT_MAX_VARIABLE_INDEX
  raise "region clause links exceed signed 32-bit storage" if nc > WASSAT_MAX_CLAUSE_INDEX
  lits = formula["flat_lits"] ## i64[]
  offsets = formula["flat_offs"] ## i64[]
  lengths = formula["flat_lens"] ## i64[]
  pins = i8[nv + 1]
  boundary.each -> (v)
    raise "boundary must contain variable IDs in 1..nvars" unless v.is_a?(Integer) && v >= 1 && v <= nv
    pins[v] = 1
  parent = i32[nv + 1]
  heads = i32[nv + 1]
  links = i32[nc]
  ignored = wassat_region_components(lits, offsets, lengths, nc, pins, parent, heads, links)
  ids = i32[10]
  pos = i64[64]
  neg = i64[64]
  shape = i64[2]
  table = i64[256]
  closure = i64[256]
  truth = i64[6]
  clause_models = i64[64]
  one = 1 ## i64
  j = 0 ## i64
  while j < 6
    a = 0 ## i64
    pattern = 0 ## i64
    while a < 64
      pattern |= one << a if ((a >> j) & 1) != 0
      a += 1
    truth[j] = pattern
    j += 1
  extra = []
  root = 1 ## i64
  while root <= nv
    if heads[root] > 0 && parent[root] >= -5
      h = heads[root] ## i64
      count = wassat_region_encode(lits, offsets, lengths, pins, links, h, ids, pos, neg, shape)
      if count > 1
        ignored = wassat_region_compile(pos, neg, count, ids, shape[0], shape[1], truth, clause_models, table, closure, extra)
    root += 1
  extra
