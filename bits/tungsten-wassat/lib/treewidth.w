# Clause-checked treewidth lower bounds. No filename, graph, contraction
# sequence or answer is stored: decode the graph and bound from this input.
# The portfolio must disable this non-DRAT certificate route in proof mode.
use atomic_stop

# meta: 0 stop reason, 1 polls, 2 checked clauses, 3 ignored units,
# 4 vertices, 5 edges, 6 counter stride, 7 width bound, 8 contractions,
# 9 minor vertices, 10 scratch bytes, 11 phase, 12 decode ms,
# 13 contraction ms, 14 search ms, 15 total ms, 16 final result,
# 20 search nodes, 21 branches, 22 degree prunes, 23 memo hits.
-> wassat_treewidth_poll(m, stop, deadline) (i64[] i64[] i64) bool
  m[1] += 1
  if wassat_stop_requested?(stop)
    m[0] = 1
  elsif deadline > 0 && clock_ms() >= deadline
    m[0] = 2
  elsif m[20] > 1000000
    m[0] = 3
  m[0] != 0

# Exact templates preserve multiplicity while permitting literal permutation:
# the early flat lucky probe can move watched literals in the input buffers.
# Extra clauses can only strengthen a refutation; symmetry units are ignored.
-> wassat_treewidth_match(lits, offs, lens, nc, nl, m, stop, deadline, len, a, b, c, d) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64 i64 i64 i64 i64 i64) bool
  ci = m[2]
  return false if ci >= nc || ci < 0
  return false if (ci & 4095) == 0 && wassat_treewidth_poll(m, stop, deadline)
  return false if lens[ci] != len
  o = offs[ci]
  return false if o < 0 || o > nl - len
  found = 0; j = 0
  while j < len
    x = lits[o + j]
    bit = x == a ? 1 : (len > 1 && x == b ? 2 : (len > 2 && x == c ? 4 : (len > 3 && x == d ? 8 : 0)))
    return false if bit == 0 || (found & bit) != 0
    found |= bit; j += 1
  m[2] += 1
  true

-> wassat_treewidth_ord(n, base, i, j) (i64 i64 i64 i64) i64
  return base + i * (2 * n - i - 1) / 2 + j - i - 1 if i < j
  0 - (base + j * (2 * n - j - 1) / 2 + i - j - 1)

-> wassat_treewidth_header(lits, offs, lens, nc, nl) (i64[] i64[] i64[] i64 i64) i64
  return 0 if nc < 8 || nl < 24 || offs.size < nc || lens.size < nc || lits.size < nl
  return 0 if lens[0] != 3 || offs[0] < 0 || offs[0] > nl - 3
  o = offs[0]; a = lits[o]; b = lits[o + 1]; c = lits[o + 2]
  if a > b
    t = a; a = b; b = t
  if b > c
    t = b; b = c; c = t
  if a > b
    t = a; a = b; b = t
  base = 0 - b; n = 0 - a - base + 1
  return 0 if base < 1 || base > 16 || n < 3 || n > 256 || c != base + 1
  return 0 if nc < 2 * n * (n - 1) * (n - 2) || nc > 40000000 || nl > 160000000
  n

-> wassat_treewidth_decode(lits, offs, lens, nc, nl, nv, graph, xs, starts, widths, seen, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i64 u8[] i64[] i64[] i64[] i64[] i64[] i64[] i64) bool
  n = wassat_treewidth_header(lits, offs, lens, nc, nl)
  return false if n == 0 || wassat_treewidth_poll(m, stop, deadline)
  o = offs[0]; base = 0; j = 0
  while j < 3
    base = lits[o + j] - 1 if lits[o + j] > 0
    j += 1
  ab = base + n * (n - 1) / 2
  return false if ab + n * n - 1 > nv
  m[4] = n; m[11] = 1
  i = 0
  while i < n
    j = 0
    while j < n
      if i != j
        k = 0
        while k < n
          if k != i && k != j
            a = 0 - wassat_treewidth_ord(n, base, i, j)
            b = 0 - wassat_treewidth_ord(n, base, j, k)
            c = wassat_treewidth_ord(n, base, i, k)
            return false unless wassat_treewidth_match(lits, offs, lens, nc, nl, m, stop, deadline, 3, a, b, c, 0)
          k += 1
      j += 1
    i += 1
  while m[2] < nc && lens[m[2]] == 2
    ci = m[2]; o = offs[ci]
    return false if o < 0 || o > nl - 2
    a = lits[o]; b = lits[o + 1]
    return false if a < ab || b < ab || a >= ab + n * n || b >= ab + n * n
    i = (a - ab) / n; j = (a - ab) % n
    return false if i == j || b != ab + j * n + i
    m[5] += 1 if graph[i * n + j] == 0
    graph[i * n + j] = 1; graph[j * n + i] = 1
    return false unless wassat_treewidth_match(lits, offs, lens, nc, nl, m, stop, deadline, 2, a, b, 0, 0)
  i = 0
  while i < n
    j = 0
    while j < n
      if i != j
        k = 0
        while k < n
          if k != i && k != j
            return false unless wassat_treewidth_match(lits, offs, lens, nc, nl, m, stop, deadline, 4, 0 - ab - k * n - i, 0 - ab - k * n - j, ab + i * n + j, ab + j * n + i)
          k += 1
      j += 1
    i += 1
  i = 0
  while i < n
    j = 0
    while j < n
      if i != j
        return false unless wassat_treewidth_match(lits, offs, lens, nc, nl, m, stop, deadline, 2, 0 - wassat_treewidth_ord(n, base, i, j), 0 - ab - j * n - i, 0, 0)
      j += 1
    i += 1
  i = 0
  while i < n
    j = 0
    while j < n
      len = i == j ? 1 : 2
      return false unless wassat_treewidth_match(lits, offs, lens, nc, nl, m, stop, deadline, len, 0 - ab - j * n - i, 0 - ab - i * n - j, 0, 0)
      j += 1
    i += 1
  while m[2] < nc && lens[m[2]] == 1
    ci = m[2]; o = offs[ci]
    return false if o < 0 || o >= nl
    return false unless wassat_treewidth_match(lits, offs, lens, nc, nl, m, stop, deadline, 1, lits[o], 0, 0, 0)
    m[3] += 1
  # Each row is a sequential counter over a permutation of exactly its arcs.
  # Counter auxiliaries must be fresh, disjoint, and inside the DIMACS bound.
  high = ab + n * n - 1
  v = 0
  while v < n
    ci = m[2]
    return false if ci + 1 >= nc || lens[ci] != 2 || lens[ci + 1] != 2
    o = offs[ci]; o2 = offs[ci + 1]
    return false if o < 0 || o > nl - 2 || o2 < 0 || o2 > nl - 2
    cb = lits[o] > 0 ? lits[o] : lits[o + 1]
    second = lits[o2] > 0 ? lits[o2] : lits[o2 + 1]
    stride = second - cb
    return false if cb <= high || stride < 2 || stride > 32 || cb + (n - 1) * stride - 1 > nv
    high = cb + (n - 1) * stride - 1; starts[v] = cb; widths[v] = stride; widths[n + v] = stride
    m[6] = stride
    i = 0
    while i < n - 1
      ci = m[2]
      return false if ci >= nc || lens[ci] != 2
      o = offs[ci]
      return false if o < 0 || o > nl - 2
      x = lits[o] < 0 ? 0 - lits[o] : 0 - lits[o + 1]; q = x - ab - v * n
      return false if q < 0 || q >= n || seen[q] == v + 1
      seen[q] = v + 1; xs[v * n + i] = x
      return false unless wassat_treewidth_match(lits, offs, lens, nc, nl, m, stop, deadline, 2, 0 - x, cb + i * stride, 0, 0)
      i += 1
    j = 1
    while j < stride
      return false unless wassat_treewidth_match(lits, offs, lens, nc, nl, m, stop, deadline, 1, 0 - cb - j, 0, 0, 0)
      j += 1
    i = 1
    while i < n - 1
      j = 0
      while j < stride
        return false unless wassat_treewidth_match(lits, offs, lens, nc, nl, m, stop, deadline, 2, 0 - cb - (i - 1) * stride - j, cb + i * stride + j, 0, 0)
        j += 1
      i += 1
    i = 1
    while i < n - 1
      j = 1
      while j < stride
        return false unless wassat_treewidth_match(lits, offs, lens, nc, nl, m, stop, deadline, 3, 0 - xs[v * n + i], 0 - cb - (i - 1) * stride - j + 1, cb + i * stride + j, 0)
        j += 1
      i += 1
    i = 1
    while i < n
      if i == n - 1
        ci = m[2]
        return false if ci >= nc || lens[ci] != 2
        o = offs[ci]
        return false if o < 0 || o > nl - 2
        x = lits[o] > lits[o + 1] ? 0 - lits[o] : 0 - lits[o + 1]; q = x - ab - v * n
        return false if q < 0 || q >= n || seen[q] == v + 1
        seen[q] = v + 1; xs[v * n + i] = x
      return false unless wassat_treewidth_match(lits, offs, lens, nc, nl, m, stop, deadline, 2, 0 - xs[v * n + i], 0 - cb - (i - 1) * stride - stride + 1, 0, 0)
      i += 1
    # One initial tightened bound follows each counter.
    return false unless wassat_treewidth_bound(lits, offs, lens, nc, nl, xs, starts, widths, m, stop, deadline, v, n, stride)
    v += 1
  # Subsequent rounds tighten every vertex. A partial round declines.
  while m[2] < nc
    v = 0
    while v < n
      stride = widths[n + v]
      return false unless wassat_treewidth_bound(lits, offs, lens, nc, nl, xs, starts, widths, m, stop, deadline, v, n, stride)
      v += 1
  k = 0; v = 0
  while v < n
    k = widths[v] if widths[v] > k
    v += 1
  m[7] = k
  k >= 1 && k <= 12 && m[2] == nc

-> wassat_treewidth_bound(lits, offs, lens, nc, nl, xs, starts, widths, m, stop, deadline, v, n, stride) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64) bool
  ci = m[2]
  return false if ci >= nc || lens[ci] != 2
  o = offs[ci]
  return false if o < 0 || o > nl - 2
  aux = lits[o] < lits[o + 1] ? lits[o] : lits[o + 1]
  cb = starts[v]; bound = 0 - aux - cb + 1
  return false if bound < 1 || bound > stride
  i = 1
  while i < n
    return false unless wassat_treewidth_match(lits, offs, lens, nc, nl, m, stop, deadline, 2, 0 - xs[v * n + i], 0 - cb - (i - 1) * stride - bound + 1, 0, 0)
    i += 1
  widths[v] = bound if bound < widths[v]
  true

# Greedy edge contractions preserve the lower-bound direction of treewidth.
# Deterministic ties use a small LCG, independent of names and stored answers.
-> wassat_treewidth_contract(graph, active, degrees, rows, m, stop, deadline) (u8[] u8[] i64[] i64[] i64[] i64[] i64) bool
  n = m[4]; left = n; rng = 1 ## i64
  v = 0
  while v < n
    active[v] = 1; v += 1
  m[11] = 2
  while left > 24
    return false if wassat_treewidth_poll(m, stop, deadline)
    md = n + 1; count = 0; v = 0
    while v < n
      if active[v] == 1
        deg = 0; u = 0
        while u < n
          deg += graph[v * n + u]; u += 1
        degrees[v] = deg
        if deg < md
          md = deg; count = 0
        count += 1 if deg == md
      v += 1
    rng = (rng * 1664525 + 1013904223) & 4294967295
    pick = rng % count; v = 0
    while v < n
      if active[v] == 1 && degrees[v] == md
        break if pick == 0
        pick -= 1
      v += 1
    if md > 0
      best = n + 1; count = 0; u = 0
      while u < n
        if graph[v * n + u] == 1
          common = 0; w = 0
          while w < n
            common += 1 if graph[v * n + w] == 1 && graph[u * n + w] == 1
            w += 1
          degrees[u] = common
          if common < best
            best = common; count = 0
          count += 1 if common == best
        u += 1
      rng = (rng * 1664525 + 1013904223) & 4294967295
      pick = rng % count; u = 0
      while u < n
        if graph[v * n + u] == 1 && degrees[u] == best
          break if pick == 0
          pick -= 1
        u += 1
      w = 0
      while w < n
        if w != u && graph[v * n + w] == 1
          graph[u * n + w] = 1; graph[w * n + u] = 1
        graph[v * n + w] = 0; graph[w * n + v] = 0
        w += 1
    active[v] = 0; left -= 1; m[8] += 1
  m[9] = left
  i = 0; v = 0
  while v < n
    if active[v] == 1
      row = 0; j = 0; u = 0
      while u < n
        if active[u] == 1
          row |= 1 << j if graph[v * n + u] == 1
          j += 1
        u += 1
      rows[i] = row; i += 1
    v += 1
  true

-> wassat_treewidth_popcount(x) (i64) i64
  n = 0
  while x != 0
    x &= x - 1; n += 1
  n

# 1: a width-k order exists; -1: all possible first vertices refuted;
# 0: cancelled/capped. No allocation per node. The remaining vertex mask
# uniquely determines the fill graph; memoize only completed refutations.
-> wassat_treewidth_search(rows, memo, alive, depth, n, k, m, stop, deadline) (i64[] u8[] i64 i64 i64 i64 i64[] i64[] i64) i64
  m[20] += 1
  return 0 if (m[20] & 1023) == 1 && wassat_treewidth_poll(m, stop, deadline)
  return 1 if wassat_treewidth_popcount(alive) <= k + 1
  slot = alive >> 3; bit = 1 << (alive & 7)
  if (memo[slot] & bit) != 0
    m[23] += 1; return -1
  base = depth * 24; child = base + 24
  degree = 0; branches = 0
  while degree <= k
    v = 0
    while v < n
      if (alive & (1 << v)) != 0 && wassat_treewidth_popcount(rows[base + v]) == degree
        branches += 1; m[21] += 1
        ns = rows[base + v]; rest = alive ^ (1 << v); u = 0
        while u < n
          row = rows[base + u]
          row |= ns if (ns & (1 << u)) != 0
          rows[child + u] = row & rest & (-1 ^ (1 << u))
          u += 1
        rows[child + v] = 0
        result = wassat_treewidth_search(rows, memo, rest, depth + 1, n, k, m, stop, deadline)
        return result if result != -1
      v += 1
    degree += 1
  m[22] += 1 if branches == 0
  memo[slot] = memo[slot] | bit
  -1

-> wassat_treewidth_refute(formula, m, stop, deadline = 0)
  return 0 if m.size < 32 || stop.size < 2
  i = 0
  while i < 32
    m[i] = 0; i += 1
  n = wassat_treewidth_header(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], formula["flat_ncl"], formula["flat_nlits"])
  return 0 if n == 0 || wassat_treewidth_poll(m, stop, deadline)
  start = clock_ms()
  graph = u8[n * n]; xs = i64[n * n]; starts = i64[n]; widths = i64[2 * n]; seen = i64[n]
  active = u8[n]; degrees = i64[n]; rows = i64[25 * 24]
  memo_n = n < 24 ? n : 24
  memo = u8[(1 << memo_n) / 8 + 1]
  m[10] = 9 * n * n + 41 * n + 25 * 24 * 8 + memo.size
  hit = 0
  if wassat_treewidth_decode(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], formula["flat_ncl"], formula["flat_nlits"], formula["nvars"], graph, xs, starts, widths, seen, m, stop, deadline)
    m[12] = clock_ms() - start; t = clock_ms()
    if wassat_treewidth_contract(graph, active, degrees, rows, m, stop, deadline)
      m[13] = clock_ms() - t; t = clock_ms(); m[11] = 3
      r = wassat_treewidth_search(rows, memo, (1 << m[9]) - 1, 0, m[9], m[7], m, stop, deadline)
      m[14] = clock_ms() - t
      hit = -1 if r == -1 && !wassat_treewidth_poll(m, stop, deadline)
  m[15] = clock_ms() - start; m[16] = hit
  hit

-> wassat_treewidth_plan(formula, workers, cdcl, sls, pre, extra)
  mode = env("WASSAT_TREEWIDTH")
  return nil if mode == "0" || formula == nil || formula["treewidth_done"] == true
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  return nil if wassat_race_round1_conflicts != 0
  return nil if System.cpu_count <= workers || System.physical_memory_bytes <= 0
  nv = formula["nvars"]; nc = formula["flat_ncl"]; nl = formula["flat_nlits"]
  return nil if nv == nil || nv < 1 || nv > 2000000 || nc == nil || nl == nil
  return nil if formula["flat_lits"] == nil || formula["flat_offs"] == nil || formula["flat_lens"] == nil
  return nil if wassat_treewidth_header(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nc, nl) == 0
  # Bound every fixed scratch array, plus the portfolio's result slice.
  bytes = 8388608 + 8 * (nv + 8)
  return nil if bytes > System.physical_memory_bytes / 32
  estimate = wassat_cdcl_arena_bytes(formula) * cdcl + wassat_sls_arena_bytes(formula) * sls
  estimate += wassat_preprocess_arena_bytes(formula) * pre + extra + bytes
  memory = System.physical_memory_bytes ## i64
  ceiling = memory / 3; ceiling = 6442450944 if ceiling > 6442450944
  wassat_prof_note("race.treewidth_plan estimate=[estimate] ceiling=[ceiling] scratch=[bytes] existing_workers=[workers]")
  return nil if estimate > ceiling
  { "treewidth": true, "meta": i64[32], "scratch": bytes }

-> wassat_treewidth_arm(formula, plan, stop, res, base, nv)
  m = plan["meta"]; start = clock_ms()
  hit = wassat_treewidth_refute(formula, m, stop, start + 5000)
  res[base + nv + 6] = start; res[base + nv + 5] = clock_ms()
  return 0 if hit != -1 || wassat_stop_load(stop) != 0 || clock_ms() >= start + 5000
  z = ccall("__w_arr_store_rel", res, base, -1)
  z = wassat_stop_publish(stop, -1)
  -1

-> wassat_treewidth_finish_scout(formula, plan)
  m = plan["meta"]
  # An interrupted or completed-but-unpublished proof may retry after scout.
  formula["treewidth_done"] = m[0] != 1 && m[16] != -1
  0

-> wassat_treewidth_profile(m, label = "race.treewidth")
  wassat_prof_note("[label] status=[m[16]] vertices=[m[4]] edges=[m[5]] bound=[m[7]] stride=[m[6]] checked_clauses=[m[2]] ignored_units=[m[3]] contractions=[m[8]] minor_vertices=[m[9]] nodes=[m[20]] branches=[m[21]] degree_prunes=[m[22]] memo_hits=[m[23]] polls=[m[1]] stop=[m[0]] phase=[m[11]] scratch_bytes=[m[10]] decode_ms=[m[12]] contract_ms=[m[13]] search_ms=[m[14]] ms=[m[15]]")
