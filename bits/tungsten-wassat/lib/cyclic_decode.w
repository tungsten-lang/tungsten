# Decode a candidate circular labelling graph from matrix clauses and binary
# implications. SAT requires original-clause replay. UNSAT additionally needs
# the complete original-clause contract checked by the bounded ball verifier.
use cyclic_walk
use cyclic_bound

WASSAT_CYCLE_MAX_N = 1024
WASSAT_CYCLE_WALL_MS = 15000

# Bounded coordinator probe. Auxiliary covering clauses can be wider than
# three, so only a complete positive matrix column counts as admission.
-> wassat_cycle_prefix(lits, offs, lens, nv, nc) (i64[] i64[] i64[] i64 i64) i64
  return 0 if nc < 4 || offs.size < nc || lens.size < nc
  limit = (nc < 4096 ? nc : 4096) ## i64
  ci = 0 ## i64
  while ci < limit
    index = (ci < 2048 ? ci : nc - limit + ci) ## i64
    n = (lens[index]) ## i64
    if n >= 4 && n <= WASSAT_CYCLE_MAX_N && n * n <= nv
      off = (offs[index]) ## i64
      return 0 if off < 0 || off > lits.size || n > lits.size - off
      col = -1 ## i64
      valid = true
      j = 0 ## i64
      while j < n && valid
        lit = (lits[off + j]) ## i64
        valid = false if lit < 1 || lit > n * n
        c = ((lit - 1) % n) ## i64
        col = c if col < 0
        valid = false if c != col
        j += 1
      return n if valid
    ci += 1
  0

# Validate all flat spans and literals while counting positive implications.
# Clauses wider than the matrix are unsupported. Other auxiliary clauses are
# retained for final replay, even when they do not participate in decoding.
-> wassat_cycle_matrix(lits, offs, lens, nv, nc, n, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64) i64
  return 0 if n < 4 || n > WASSAT_CYCLE_MAX_N || n * n > nv
  return 0 if offs.size < nc || lens.size < nc
  columns = i8[n]
  seen = i32[n]
  wide = 0 ## i64
  ci = 0 ## i64
  work = 0 ## i64
  while ci < nc
    k = (lens[ci]) ## i64
    off = (offs[ci]) ## i64
    return 0 if k < 1 || k > n || off < 0 || off > lits.size || k > lits.size - off
    col = -1 ## i64
    j = 0 ## i64
    while j < k
      work += 1
      return 0 if (work & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
      lit = (lits[off + j]) ## i64
      return 0 if lit == 0 || lit < -nv || lit > nv
      if k == n
        return 0 if lit < 1 || lit > n * n
        c = ((lit - 1) % n) ## i64
        row = ((lit - 1) / n) ## i64
        col = c if col < 0
        return 0 if c != col || seen[row] == ci + 1
        seen[row] = ci + 1
      j += 1
    if k == n
      return 0 if columns[col] != 0
      columns[col] = 1
      wide += 1
    if k == 2
      a = (lits[off]) ## i64
      b = (lits[off + 1]) ## i64
      m[4] += 1 if (a < 0 && b > 0) || (a > 0 && b < 0)
      m[5] += 1 if a < 0 && b < 0
    ci += 1
  wide == n ? 1 : 0

# Build both directions of the positive implication graph in fixed CSR arrays.
-> wassat_cycle_implications(lits, offs, lens, nv, nc, heads, back, dest, src, fill, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i32[] i32[] i32[] i32[] i32[] i64[] i64[] i64) i64
  pass = 0 ## i64
  while pass < 3
    ci = 0 ## i64
    while ci < nc
      return 0 if (ci & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
      if lens[ci] == 2
        off = (offs[ci]) ## i64
        a = (lits[off]) ## i64
        b = (lits[off + 1]) ## i64
        if a > 0 && b < 0
          tmp = a ## i64
          a = b
          b = tmp
        if a < 0 && b > 0
          a = -a
          if pass == 0
            heads[a + 1] += 1
            back[b + 1] += 1
          elsif pass == 1
            dest[heads[a] + fill[a]] = b
            fill[a] += 1
          else
            src[back[b] + fill[b]] = a
            fill[b] += 1
      ci += 1
    v = 0 ## i64
    while v <= nv + 1
      return 0 if (v & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
      if pass == 0 && v > 0
        heads[v] += heads[v - 1]
        back[v] += back[v - 1]
      fill[v] = 0 if v <= nv
      v += 1
    pass += 1
  1

# Auxiliary ownership is a monotone lattice: unknown -> one row -> mixed.
# A variable can therefore be enqueued at most twice, including cycles.
-> wassat_cycle_owners(n, nv, heads, dest, owner, queue, m, stop, deadline) (i64 i64 i32[] i32[] i32[] i32[] i64[] i64[] i64) i64
  tail = (n * n) ## i64
  v = 1 ## i64
  while v <= tail
    return 0 if (v & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
    owner[v] = (v - 1) / n + 1
    queue[v - 1] = v
    v += 1
  at = 0 ## i64
  work = 0 ## i64
  while at < tail
    return 0 if (at & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
    a = (queue[at]) ## i64
    j = (heads[a]) ## i64
    while j < heads[a + 1]
      work += 1
      return 0 if (work & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
      b = (dest[j]) ## i64
      old = (owner[b]) ## i64
      merged = (old == 0 ? owner[a] : (old == owner[a] ? old : -1)) ## i64
      if old != merged
        return 0 if tail >= queue.size
        owner[b] = merged
        queue[tail] = b
        tail += 1
      j += 1
    at += 1
  m[6] = at
  1

# Conservative lower bound on the runtime's configurable memory ceiling.
# Bare numbers are MiB, as in the runtime. Fractional amounts round down;
# unsupported spellings decline this optional worker. Even an unlimited or
# larger runtime ceiling does not enlarge this lane's eight-GiB envelope.
-> wassat_cycle_memory_limit(raw)
  return 8589934592 if raw == nil || raw == "off" || raw == "none" || raw == "unlimited"
  i = 0
  amount = 0
  while i < raw.size && raw.byte_at(i) >= 48 && raw.byte_at(i) <= 57
    amount = amount * 10 + raw.byte_at(i) - 48
    return 0 if amount > 8589934592
    i += 1
  return 0 if i == 0
  if i < raw.size && raw.byte_at(i) == 46
    i += 1
    start = i
    while i < raw.size && raw.byte_at(i) >= 48 && raw.byte_at(i) <= 57
      i += 1
    return 0 if i == start
  unit = 1048576
  if i < raw.size
    c = raw.byte_at(i) | 32
    if c == 107 || c == 109 || c == 103 || c == 116
      unit = 1024 if c == 107
      unit = 1073741824 if c == 103
      unit = 1099511627776 if c == 116
      i += 1
  i += 1 if i < raw.size && raw.byte_at(i) == 105
  i += 1 if i < raw.size && (raw.byte_at(i) | 32) == 98
  return 0 unless i == raw.size
  return 8589934592 if amount >= 8589934592 / unit && unit <= 8589934592
  return 8589934592 if unit > 8589934592 && amount > 0
  amount * unit

-> wassat_cycle_bytes(nv, nc, n) (i64 i64 i64) i64
  # Decoder: 26 bytes/variable, two implication arrays (at most nc edges).
  # Search: at most n*(n-1)/2 graph edges. Include all six result slots when
  # converting the lone CDCL solver into a race, plus small descriptors/ring.
  74 * (nv + 1) + 8 * nc + 15 * n * n + 32 * n + 2097152

# This admission is used only beside the serial fallback. Existing full
# races retain their resource policy; the retained scout remains the CDCL
# arm. Count its resident companions conservatively, without building another
# solver solely to recover implications for this model-only proposal lane.
-> wassat_cycle_plan(formula, cdcl_arenas, sls_arenas)
  mode = env("WASSAT_CYCLIC_WALK")
  return nil if mode == "0" || formula == nil || System.cpu_count < 2
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  return nil if wassat_race_round1_conflicts != 0
  return nil unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  return nil if nv < 16 || nv > 2000000 || nc < 4 || nc > 20000000
  return nil if formula["flat_nlits"] > 50000000
  n = wassat_cycle_prefix(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nv, nc)
  return nil if n < 4 || (n <= WASSAT_PERM_MAX_N && mode != "1")
  scratch = wassat_cycle_bytes(nv, nc, n)
  memory = System.physical_memory_bytes
  return nil if memory <= 0 || scratch > memory / 64 || scratch > 268435456
  cdcl_arenas = 1 if cdcl_arenas < 1
  resident = cdcl_arenas * wassat_cdcl_arena_bytes(formula)
  resident += sls_arenas * wassat_sls_arena_bytes(formula)
  resident += wassat_preprocess_arena_bytes(formula)
  limit = wassat_cycle_memory_limit(env("TUNGSTEN_MEMORY_LIMIT"))
  return nil if (resident + scratch) * 10 > limit * 9 || resident + scratch > memory / 3
  # Reserve the certificate's larger support table only when it independently
  # fits. Insufficient room disables this check and preserves the model lane.
  words = (n + 63) / 64
  extra = 8 * (nv + 1) * words + 4 * nc + 5 * n * n + 8 * (n + 1) * words + 80 * n + 4096
  bound = env("WASSAT_CYCLIC_BOUND") != "0"
  bound = false if scratch + extra > memory / 64 || scratch + extra > 536870912
  bound = false if (resident + scratch + extra) * 10 > limit * 9 || resident + scratch + extra > memory / 3
  scratch += extra if bound
  { "n": n, "scratch": scratch, "bound": bound, "meta": i64[24], "walk": i64[24] }

-> wassat_cycle_arm(lits, offs, lens, nv, nc, n, m, walk, stop, res, base, allow_bound) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[] i64 i64) i64
  m[17] = clock_ms()
  deadline = (m[17] + WASSAT_CYCLE_WALL_MS) ## i64
  hit = (wassat_cycle_search_checked(lits, offs, lens, nv, nc, n, m, walk, stop, res, base, deadline, allow_bound)) ## i64
  m[18] = clock_ms()
  res[base + nv + 6] = m[17]
  res[base + nv + 5] = m[18]
  if hit != 0 && wassat_perm_stop(m, stop, deadline) == 0
    m[0] = hit
    z = ccall("__w_arr_store_rel", res, base, hit)
    won = wassat_stop_publish(stop, hit)
    return hit
  0

-> wassat_cycle_start(formula, plan, stop, res, base)
  lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
  nv = formula["nvars"]; nc = formula["flat_ncl"]; n = plan["n"]
  m = plan["meta"]; walk = plan["walk"]
  m[23] = plan["scratch"]
  allow_bound = plan["bound"] ? 1 : 0
  Thread.new -> wassat_cycle_arm(lits, offs, lens, nv, nc, n, m, walk, stop, res, base, allow_bound)

-> wassat_cycle_profile(plan, status)
  m = plan["meta"]; w = plan["walk"]
  wassat_prof_note("race.cyclic status=[status] vertices=[m[1]] edges=[m[2]] width=[m[3]] implications=[m[4]] negative_pairs=[m[5]] owner_visits=[m[6]] true_closure=[m[7]] false_closure=[m[8]] units=[m[9]] cross_pairs=[m[10]] rejected_clauses=[m[11]] polls=[m[12] + w[12]] restarts=[w[6]] iterations=[w[7]] swaps=[w[8]] bumps=[w[9]] candidates=[w[10]] updates=[w[11]] best_deficit=[w[13]] replay_clauses=[m[14]] replay_literals=[m[15]] verified=[m[16]] decode_ms=[m[19]] search_ms=[m[20]] lift_ms=[m[21]] stopped=[m[22]] scratch_bytes=[m[23]] ms=[m[18] - m[17]]")
  wassat_prof_note("race.cyclic_bound status=[w[0]] root=[w[1]] radius=[w[2]] vertices=[w[3]] positions=[w[4]] edges=[w[5]] work=[w[14]] support_words=[w[15]] rectangle_rows=[w[16]] coverage_words=[w[17]] row_amos=[w[18]] checked_edges=[w[19]] bytes=[w[20]] ms=[w[21]]")

-> wassat_cycle_edges(lits, offs, lens, nc, n, owner, matrix, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i32[] i8[] i64[] i64[] i64) i64
  ci = 0 ## i64
  ne = 0 ## i64
  while ci < nc
    return 0 if (ci & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
    if lens[ci] == 2
      off = (offs[ci]) ## i64
      a = (lits[off]) ## i64
      b = (lits[off + 1]) ## i64
      if a < 0 && b < 0
        u = (owner[-a] - 1) ## i64
        v = (owner[-b] - 1) ## i64
        if u >= 0 && v >= 0 && u != v
          m[10] += 1
          ne += 1 if matrix[u * n + v] == 0
          matrix[u * n + v] = 1
          matrix[v * n + u] = 1
    ci += 1
  ne

# Transitive closure reuses the ownership queue and a byte mark array. Each
# variable is appended at most once. The caller supplies the initial prefix.
-> wassat_cycle_closure(heads, dest, mark, queue, tail, m, stop, deadline) (i32[] i32[] i8[] i32[] i64 i64[] i64[] i64) i64
  at = 0 ## i64
  work = 0 ## i64
  while at < tail
    return -1 if (at & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
    a = (queue[at]) ## i64
    j = (heads[a]) ## i64
    while j < heads[a + 1]
      work += 1
      return -1 if (work & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
      b = (dest[j]) ## i64
      if mark[b] == 0
        mark[b] = 1
        queue[tail] = b
        tail += 1
      j += 1
    at += 1
  tail

# Infer the circular forbidden interval from one graph vertex at label zero.
# This need not characterize every clause: final replay is the soundness gate.
-> wassat_cycle_width(lits, offs, lens, nc, n, matrix, heads, back, dest, src, yes, no, queue, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i8[] i32[] i32[] i32[] i32[] i8[] i8[] i32[] i64[] i64[] i64) i64
  anchor = 0 ## i64
  found = false
  while anchor < n && !found
    v = 0 ## i64
    while v < n
      found = true if matrix[anchor * n + v] != 0
      v += 1
    anchor += 1 unless found
  return 0 unless found
  queue[0] = anchor * n + 1
  yes[queue[0]] = 1
  count = (wassat_cycle_closure(heads, dest, yes, queue, 1, m, stop, deadline)) ## i64
  return 0 if count < 0
  m[7] = count
  tail = 0 ## i64
  ci = 0 ## i64
  while ci < nc
    return 0 if (ci & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
    if lens[ci] == 2
      off = (offs[ci]) ## i64
      a = (lits[off]) ## i64
      b = (lits[off + 1]) ## i64
      if a < 0 && b < 0
        a = -a
        b = -b
        if yes[a] != 0 && no[b] == 0
          no[b] = 1
          queue[tail] = b
          tail += 1
        if yes[b] != 0 && no[a] == 0
          no[a] = 1
          queue[tail] = a
          tail += 1
    ci += 1
  count = wassat_cycle_closure(back, src, no, queue, tail, m, stop, deadline)
  return 0 if count < 0
  m[8] = count
  width = 0 ## i64
  v = 0
  while v < n
    return 0 if wassat_perm_stop(m, stop, deadline) != 0
    if matrix[anchor * n + v] != 0
      k = 0 ## i64
      while k < n && no[v * n + k + 1] != 0
        k += 1
      return 0 if k < 2 || k > n / 2
      width = k if width == 0
      return 0 if k != width
      label = 0 ## i64
      while label < n
        d = (label < n - label ? label : n - label) ## i64
        return 0 if (no[v * n + label + 1] != 0) != (d < width)
        label += 1
    v += 1
  width

# Reuse the matrix storage as graph adjacency and fixed incident-edge lists.
-> wassat_cycle_graph(n, matrix, left, right, heads, occ, fill) (i64 i8[] i32[] i32[] i32[] i32[] i32[]) i64
  e = 0 ## i64
  u = 0 ## i64
  while u < n
    v = (u + 1) ## i64
    while v < n
      if matrix[u * n + v] != 0
        left[e] = u
        right[e] = v
        heads[u + 1] += 1
        heads[v + 1] += 1
        e += 1
      v += 1
    u += 1
  u = 1
  while u <= n
    heads[u] += heads[u - 1]
    u += 1
  e = 0
  while e < left.size
    u = (left[e]) ## i64
    v = (right[e]) ## i64
    occ[heads[u] + fill[u]] = e
    occ[heads[v] + fill[v]] = e
    fill[u] += 1
    fill[v] += 1
    e += 1
  1

# Assign the primary permutation, orient using actual negative units, then
# close positive implications. All unspecified auxiliaries default to false.
-> wassat_cycle_lift(lits, offs, lens, nv, nc, n, perm, heads, dest, values, queue, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i64 i32[] i32[] i32[] i8[] i32[] i64[] i64[] i64) i64
  original_bad = 0 ## i64
  reverse_bad = 0 ## i64
  ci = 0 ## i64
  while ci < nc
    return 0 if (ci & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
    if lens[ci] == 1
      lit = (lits[offs[ci]]) ## i64
      m[9] += 1
      if lit < 0 && -lit <= n * n
        u = ((-lit - 1) / n) ## i64
        label = ((-lit - 1) % n) ## i64
        original_bad += 1 if perm[u] == label
        reverse_bad += 1 if n - 1 - perm[u] == label
    ci += 1
  v = 0 ## i64
  while v <= nv
    return 0 if (v & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
    values[v] = 0
    v += 1
  u = 0
  while u < n
    label = (perm[u]) ## i64
    label = n - 1 - label if reverse_bad < original_bad
    v = u * n + label + 1
    values[v] = 1
    queue[u] = v
    u += 1
  tail = n ## i64
  ci = 0
  while ci < nc
    return 0 if (ci & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
    if lens[ci] == 1
      lit = (lits[offs[ci]]) ## i64
      if lit > 0 && values[lit] == 0
        values[lit] = 1
        queue[tail] = lit
        tail += 1
    ci += 1
  count = (wassat_cycle_closure(heads, dest, values, queue, tail, m, stop, deadline)) ## i64
  return 0 if count < 0
  ci = 0
  work = 0 ## i64
  while ci < nc
    return 0 if (ci & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
    off = (offs[ci]) ## i64
    j = 0 ## i64
    satisfied = false
    while j < lens[ci]
      work += 1
      return 0 if (work & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
      lit = (lits[off + j]) ## i64
      v = (lit < 0 ? -lit : lit) ## i64
      satisfied = true if (values[v] != 0) == (lit > 0)
      j += 1
    m[14] += 1
    m[15] += j
    unless satisfied
      m[11] += 1
      return 0
    ci += 1
  m[16] = 1
  1

# m: status,n,edges,width,implications,negative pairs,ownership visits,
# true/false closure,units,cross pairs,rejected clauses,polls,unused,
# replay clauses/literals,verified,start/end,decode/search/lift ms,stop,scratch.
-> wassat_cycle_search(lits, offs, lens, nv, nc, n, m, walk, stop, res, base, deadline) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[] i64 i64) i64
  wassat_cycle_search_checked(lits, offs, lens, nv, nc, n, m, walk, stop, res, base, deadline, 0)

# Certificate admission belongs to the coordinator. Direct legacy callers
# retain the model-only contract unless they explicitly enable this variant.
-> wassat_cycle_search_checked(lits, offs, lens, nv, nc, n, m, walk, stop, res, base, deadline, allow_bound) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[] i64 i64 i64) i64
  return 0 if wassat_perm_stop(m, stop, deadline) != 0
  return 0 unless wassat_cycle_matrix(lits, offs, lens, nv, nc, n, m, stop, deadline) == 1
  heads = i32[nv + 2]
  back = i32[nv + 2]
  dest = i32[m[4]]
  src = i32[m[4]]
  fill = i32[nv + 1]
  owner = i32[nv + 1]
  queue = i32[2 * (nv + 1)]
  values = i8[nv + 1]
  no = i8[nv + 1]
  matrix = i8[n * n]
  return 0 unless wassat_cycle_implications(lits, offs, lens, nv, nc, heads, back, dest, src, fill, m, stop, deadline) == 1
  return 0 unless wassat_cycle_owners(n, nv, heads, dest, owner, queue, m, stop, deadline) == 1
  ne = (wassat_cycle_edges(lits, offs, lens, nc, n, owner, matrix, m, stop, deadline)) ## i64
  return 0 if ne == 0
  width = (wassat_cycle_width(lits, offs, lens, nc, n, matrix, heads, back, dest, src, values, no, queue, m, stop, deadline)) ## i64
  return 0 if width == 0 || wassat_perm_stop(m, stop, deadline) != 0
  m[1] = n
  m[2] = ne
  m[3] = width
  left = i32[ne]
  right = i32[ne]
  gh = i32[n + 1]
  occ = i32[2 * ne]
  gf = i32[n]
  z = wassat_cycle_graph(n, matrix, left, right, gh, occ, gf)
  t1 = (clock_ms()) ## i64
  m[19] = t1 - m[17]
  if allow_bound == 1
    needed = i8[n * n]
    candidate = wassat_cycle_bound_ball(n, width, left, right, gh, occ, needed, walk, stop, deadline)
    if candidate == 1
      certified = wassat_cycle_bound_verify(lits, offs, lens, nv, nc, n, width, owner, heads, dest, needed, fill, walk, stop, deadline)
      walk[21] = clock_ms() - t1
      m[20] = walk[21]
      return -1 if certified == -1
    m[22] = walk[22]
    return 0 if walk[22] != 0 || wassat_perm_stop(m, stop, deadline) != 0
  perm = i32[n]
  rng = i64[1]
  rng[0] = 1
  hit = (wassat_cycle_trial(n, ne, width, left, right, gh, occ, perm, i32[n], i32[ne], i32[ne], i32[ne], rng, walk, stop, deadline, 32, 100000)) ## i64
  m[20] = clock_ms() - t1
  m[22] = walk[22]
  return 0 if hit == 0 || wassat_perm_stop(m, stop, deadline) != 0
  t2 = (clock_ms()) ## i64
  return 0 unless wassat_cycle_lift(lits, offs, lens, nv, nc, n, perm, heads, dest, values, queue, m, stop, deadline) == 1
  m[21] = clock_ms() - t2
  v = 1 ## i64
  while v <= nv
    return 0 if (v & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
    res[base + v] = values[v]
    v += 1
  1
