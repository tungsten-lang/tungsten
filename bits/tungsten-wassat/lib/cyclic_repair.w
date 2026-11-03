# Bounded exact reassignment of a nearly valid circular graph ordering.
# A restricted UNSAT result is only a failed proposal; never publish it.
use permutation_walk
use solver
use preprocess

-> wassat_cycle_cost(a, b, width, n) (i64 i64 i64 i64) i64
  d = ((a ## i64) - (b ## i64)) ## i64
  d = -d if d < 0
  d = n - d if d > n - d
  d < width ? width - d : 0

WASSAT_CYCLE_REPAIR_FREE = 96
WASSAT_CYCLE_REPAIR_CLAUSES = 262144
WASSAT_CYCLE_REPAIR_LITERALS = 600000
WASSAT_CYCLE_REPAIR_BYTES = 134217728
WASSAT_CYCLE_REPAIR_ROUNDS = 2

# Two bounded solver arenas may remain resident. The bound verifier and these
# repairs are mutually exclusive: repair only runs when its ball check exits
# before allocating any graph/support buffers.
-> wassat_cycle_repair_peak_bytes(n) (i64) i64
  WASSAT_CYCLE_REPAIR_ROUNDS * WASSAT_CYCLE_REPAIR_BYTES + 4 * n + 4096

# Count first, then emit into exactly sized, fixed flat buffers.
# state: clauses, literals, variables, write flag.
-> wassat_cycle_repair_binary(lits, offs, lens, state, a, b) (i64[] i64[] i64[] i64[] i64 i64) i64
  ci = (state[0]) ## i64
  at = (state[1]) ## i64
  return 0 if ci >= WASSAT_CYCLE_REPAIR_CLAUSES || at + 2 > WASSAT_CYCLE_REPAIR_LITERALS
  if state[3] != 0
    offs[ci] = at
    lens[ci] = 2
    lits[at] = a
    lits[at + 1] = b
  state[0] += 1
  state[1] += 2
  1

# The sequential AMO order agrees with the independent reference generator.
-> wassat_cycle_repair_one(lits, offs, lens, state, map, size, row, transpose) (i64[] i64[] i64[] i64[] i32[] i64 i64 i64) i64
  count = (0) ## i64
  col = (0) ## i64
  while col < size
    index = (transpose == 0 ? row * size + col : col * size + row) ## i64
    count += 1 if map[index] != 0
    col += 1
  ci = (state[0]) ## i64
  at = (state[1]) ## i64
  return 0 if ci >= WASSAT_CYCLE_REPAIR_CLAUSES || at + count > WASSAT_CYCLE_REPAIR_LITERALS
  if state[3] != 0
    offs[ci] = at
    lens[ci] = count
  state[0] += 1
  state[1] += count
  seen = (0) ## i64
  previous = (0) ## i64
  col = 0
  while col < size
    index = (transpose == 0 ? row * size + col : col * size + row) ## i64
    x = (map[index]) ## i64
    if x != 0
      lits[at + seen] = x if state[3] != 0
      seen += 1
      if count >= 2
        if seen == count
          return 0 unless wassat_cycle_repair_binary(lits, offs, lens, state, -x, -previous) == 1
        else
          state[2] += 1
          current = (state[2]) ## i64
          return 0 unless wassat_cycle_repair_binary(lits, offs, lens, state, -x, current) == 1
          if previous != 0
            return 0 unless wassat_cycle_repair_binary(lits, offs, lens, state, -previous, current) == 1
            return 0 unless wassat_cycle_repair_binary(lits, offs, lens, state, -x, -previous) == 1
          previous = current
    col += 1
  1

-> wassat_cycle_repair_emit(n, ne, width, left, right, index, labels, size, map,
                           lits, offs, lens, state, m, stop, deadline) (i64 i64 i64 i32[] i32[] i32[] i32[] i64 i32[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  transpose = (0) ## i64
  while transpose < 2
    row = (0) ## i64
    while row < size
      return 0 if wassat_perm_stop(m, stop, deadline) != 0
      return 0 unless wassat_cycle_repair_one(lits, offs, lens, state, map, size, row, transpose) == 1
      row += 1
    transpose += 1
  e = (0) ## i64
  while e < ne
    a = (index[left[e]]) ## i64
    b = (index[right[e]]) ## i64
    if a >= 0 && b >= 0
      x = (0) ## i64
      while x < size
        av = (map[a * size + x]) ## i64
        if av != 0
          y = (0) ## i64
          while y < size
            bv = (map[b * size + y]) ## i64
            if bv != 0 && wassat_cycle_cost((labels[x] ## i64), (labels[y] ## i64), width, n) > 0
              return 0 unless wassat_cycle_repair_binary(lits, offs, lens, state, -av, -bv) == 1
            m[10] += 1
            return 0 if (m[10] & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
            y += 1
        x += 1
    e += 1
  1

-> wassat_cycle_repair_build(n, ne, width, left, right, heads, occ, perm, m, stop, deadline) (i64 i64 i64 i32[] i32[] i32[] i32[] i32[] i64[] i64[] i64)
  return nil if wassat_perm_stop(m, stop, deadline) != 0
  return nil if n < 4 || n > 1024 || width < 1 || width > n / 2
  return nil if ne < 0 || left.size < ne || right.size < ne || heads.size < n + 1 || occ.size < 2 * ne || perm.size < n
  return nil if heads[0] != 0 || heads[n] != 2 * ne
  used = i8[n]
  free = i8[n]
  v = (0) ## i64
  while v < n
    p = (perm[v]) ## i64
    return nil if p < 0 || p >= n || used[p] != 0
    used[p] = 1
    return nil if heads[v] < 0 || heads[v + 1] < heads[v] || heads[v + 1] > 2 * ne
    v += 1
  e = (0) ## i64
  size = (0) ## i64
  bad_edges = (0) ## i64
  while e < ne
    return nil if (e & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
    a = (left[e]) ## i64
    b = (right[e]) ## i64
    return nil if a < 0 || b <= a || b >= n
    if wassat_cycle_cost((perm[a] ## i64), (perm[b] ## i64), width, n) > 0
      bad_edges += 1
      if free[a] == 0
        free[a] = 1
        size += 1
      if free[b] == 0
        free[b] = 1
        size += 1
    e += 1
  m[16] = bad_edges
  return nil if size == 0 || size > 32
  # Validate CSR entries before using them to filter candidate domains.
  v = 0
  while v < n
    at = (heads[v]) ## i64
    while at < heads[v + 1]
      e = occ[at]
      return nil if e < 0 || e >= ne || (left[e] != v && right[e] != v)
      m[10] += 1
      return nil if (m[10] & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
      at += 1
    v += 1
  added = (0) ## i64
  while added < 64 && size < n
    return nil if wassat_perm_stop(m, stop, deadline) != 0
    best = (-1) ## i64
    best_links = (-1) ## i64
    best_degree = (-1) ## i64
    v = 0
    while v < n
      if free[v] == 0
        links = (0) ## i64
        degree = (heads[v + 1] - heads[v]) ## i64
        at = heads[v]
        while at < heads[v + 1]
          e = occ[at]
          z = (left[e] ^ right[e] ^ v) ## i64
          links += 1 if free[z] != 0
          m[10] += 1
          return nil if (m[10] & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
          at += 1
        if links > best_links || (links == best_links && degree > best_degree)
          best = v
          best_links = links
          best_degree = degree
      v += 1
    return nil if best < 0
    free[best] = 1
    size += 1
    added += 1
  return nil if size > WASSAT_CYCLE_REPAIR_FREE
  m[1] = size
  vertices = i32[size]
  labels = i32[size]
  index = i32[n]
  v = 0
  while v < n
    used[v] = 0
    index[v] = -1
    v += 1
  count = (0) ## i64
  v = 0
  while v < n
    if free[v] != 0
      vertices[count] = v
      index[v] = count
      used[perm[v]] = 1
      count += 1
    v += 1
  count = 0
  v = 0
  while v < n
    if used[v] != 0
      labels[count] = v
      count += 1
    v += 1
  return nil if count != size
  map = i32[size * size]
  assignments = (0) ## i64
  row = (0) ## i64
  while row < size
    return nil if wassat_perm_stop(m, stop, deadline) != 0
    v = vertices[row]
    col = (0) ## i64
    while col < size
      label = (labels[col]) ## i64
      valid = true
      at = heads[v]
      while at < heads[v + 1] && valid
        e = occ[at]
        z = left[e] ^ right[e] ^ v
        valid = false if free[z] == 0 && wassat_cycle_cost(label, (perm[z] ## i64), width, n) > 0
        m[10] += 1
        return nil if (m[10] & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
        at += 1
      if valid
        assignments += 1
        map[row * size + col] = assignments
      col += 1
    row += 1
  m[2] = assignments
  state = i64[4]
  state[2] = assignments
  empty = i64[0]
  ok = wassat_cycle_repair_emit(n, ne, width, left, right, index, labels, size, map, empty, empty, empty, state, m, stop, deadline)
  return nil if ok == 0
  nc = (state[0]) ## i64
  nl = (state[1]) ## i64
  nv = (state[2]) ## i64
  return nil if nv > 3 * WASSAT_CYCLE_REPAIR_FREE * WASSAT_CYCLE_REPAIR_FREE
  m[3] = nv; m[4] = nc; m[5] = nl
  lits = i64[nl]; offs = i64[nc]; lens = i64[nc]
  state[0] = 0; state[1] = 0; state[2] = assignments; state[3] = 1
  ok = wassat_cycle_repair_emit(n, ne, width, left, right, index, labels, size, map, lits, offs, lens, state, m, stop, deadline)
  return nil if ok == 0 || state[0] != nc || state[1] != nl || state[2] != nv
  formula = { "nvars": nv, "flat_ncl": nc, "flat_nlits": nl,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens }
  { "formula": formula, "vertices": vertices, "labels": labels, "map": map, "size": size }

# Only a validated graph model may leave this helper. Restricted UNSAT is a miss.
# Counters: 0 attempts; 1 free vertices; 2 assignments; 3 variables; 4 clauses;
# 5 literals; 6 conflicts; 7 checked model; 8/9 build/solve ms; 10 work;
# 12 stop polls; 14 maximum bytes; 15 checked edges; 16 bad edges;
# 17 restricted solver status; 18 snapshots; 22 stop; 23 last attempted deficit.
-> wassat_cycle_repair(n, ne, width, left, right, heads, occ, perm, m, stop, deadline)
  return 0 if wassat_perm_stop(m, stop, deadline) != 0
  m[0] += 1
  started = clock_ms()
  plan = wassat_cycle_repair_build(n, ne, width, left, right, heads, occ, perm, m, stop, deadline)
  m[8] += clock_ms() - started
  return 0 if plan == nil || wassat_perm_stop(m, stop, deadline) != 0
  formula = plan["formula"]
  bytes = wassat_cdcl_arena_bytes(formula) + 8 * (formula["flat_nlits"] + 2 * formula["flat_ncl"]) + 4194304
  m[14] = bytes if bytes > m[14]
  return 0 if bytes > WASSAT_CYCLE_REPAIR_BYTES
  started = clock_ms()
  art = wassat_raw_artifact(formula, formula["nvars"])
  solver = Wassat.from_flat(formula["nvars"], art, 0)
  solver.enable_fixed_caps
  solver.set_stop_cell(stop)
  conflicts = 0
  result = nil
  while conflicts < 100000 && clock_ms() - started < 2000
    break if wassat_perm_stop(m, stop, deadline) != 0
    result = solver.solve_budget(1000)
    conflicts = result["conflicts"]
    break if result["status"] != 0
  m[6] += conflicts
  m[9] += clock_ms() - started
  return 0 if result == nil || wassat_perm_stop(m, stop, deadline) != 0
  m[17] = result["status"]
  return 0 unless result["status"] == 1
  model = result["model"]
  return 0 unless wassat_model_satisfies?(formula, model)
  truth = i8[formula["nvars"] + 1]
  model.each -> (lit) truth[lit] = 1 if lit > 0
  vertices = plan["vertices"]; labels = plan["labels"]; map = plan["map"]
  size = plan["size"]
  candidate = i32[n]
  v = 0
  while v < n
    candidate[v] = perm[v]
    v += 1
  row = 0
  while row < size
    selected = -1
    col = 0
    while col < size
      variable = map[row * size + col]
      if variable > 0 && truth[variable] != 0
        return 0 if selected >= 0
        selected = col
      col += 1
    return 0 if selected < 0
    candidate[vertices[row]] = labels[selected]
    row += 1
  seen = i8[n]
  v = 0
  while v < n
    label = candidate[v]
    return 0 if label < 0 || label >= n || seen[label] != 0
    seen[label] = 1
    v += 1
  e = 0
  while e < ne
    return 0 if (e & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
    return 0 if wassat_cycle_cost(candidate[left[e]], candidate[right[e]], width, n) != 0
    e += 1
  m[15] += ne
  v = 0
  while v < n
    perm[v] = candidate[v]
    v += 1
  m[7] = 1
  1
