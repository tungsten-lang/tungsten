# Model proposals for matrix-encoded graph labellings. Search preserves a
# permutation by swapping whole labels, rather than flipping its one-hot bits.
# The inferred distance graph is a heuristic only: publication requires a
# completed assignment satisfying every original clause. Never refute here.
use atomic_stop

WASSAT_PERM_MAX_N = 256
WASSAT_PERM_RESTARTS = 32
WASSAT_PERM_STEPS = 100000
WASSAT_PERM_WALL_MS = 10000
WASSAT_PERM_MAX_VARS = 200000
WASSAT_PERM_MAX_CLAUSES = 500000

-> wassat_perm_rand(rng, limit) (i64[] i64) i64
  rng[0] = (rng[0] * 48271) % 2147483647
  rng[0] % limit

-> wassat_perm_cost(a, b, width) (i64 i64 i64) i64
  d = a - b
  d = -d if d < 0
  d < width ? width - d : 0

-> wassat_perm_stop(m, stop, deadline) (i64[] i64[] i64) i64
  m[12] += 1
  if wassat_stop_load(stop) != 0
    m[22] = 1
  elsif deadline > 0 && clock_ms() >= deadline
    m[22] = 2
  m[22]

# Recognize n positive column clauses of a contiguous n*n matrix. Remaining
# clauses must be units, binaries or ternaries. This only selects proposals;
# neither the shape nor the inferred graph proves equivalence to the input.
-> wassat_perm_matrix(lits, offs, lens, nv, nc) (i64[] i64[] i64[] i64 i64) i64
  return 0 if nc < 1 || offs.size < nc || lens.size < nc
  n = 0
  wide = 0
  ci = 0
  while ci < nc
    k = lens[ci]
    return 0 if k < 1 || k > WASSAT_PERM_MAX_N
    off = offs[ci]
    return 0 if off < 0 || off > lits.size || k > lits.size - off
    if k > 3
      n = k if n == 0
      return 0 if k != n
      wide += 1
      return 0 if wide > n
    ci += 1
  return 0 if n < 4 || wide != n || n * n > nv
  columns = i8[n]
  seen = i64[n]
  ci = 0
  while ci < nc
    if lens[ci] == n
      off = offs[ci]
      col = -1
      j = 0
      while j < n
        lit = lits[off + j]
        return 0 if lit < 1 || lit > n * n
        c = (lit - 1) % n
        row = (lit - 1) / n
        col = c if col < 0
        return 0 if c != col || seen[row] == ci + 1
        seen[row] = ci + 1
        j += 1
      return 0 if columns[col] != 0
      columns[col] = 1
    ci += 1
  n

# m: status,n,edges,width,queries,propagated,restarts,steps,swaps,bumps,
# candidates,score updates,polls,best deficit,replay clauses/literals,
# verified,start/end ms,prepare/search/lift ms,stop reason,scratch estimate.
-> wassat_perm_trial(n, ne, width, left, right, heads, occ, perm, tabu,
                      weights, penalty, bad, rng, m, stop, deadline,
                      restarts, steps) (i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64) i64
  m[13] = 1000000000
  # Bound work between polls even for a dense graph or a high-degree hub.
  # One swap scores at most n*max_degree + 2*edges incident edge updates.
  max_degree = 0
  v = 0
  while v < n
    degree = heads[v + 1] - heads[v]
    max_degree = degree if degree > max_degree
    v += 1
  poll_mask = 255
  while poll_mask > 0 && (poll_mask + 1) * (n * max_degree + 2 * ne) > 32768
    poll_mask = (poll_mask - 1) / 2
  restart = 0
  while restart < restarts
    return 0 if wassat_perm_stop(m, stop, deadline) != 0
    m[6] += 1
    v = 0
    while v < n
      perm[v] = v
      tabu[v] = 0
      v += 1
    v = n - 1
    while v > 0
      j = wassat_perm_rand(rng, v + 1)
      tmp = perm[v]
      perm[v] = perm[j]
      perm[j] = tmp
      v -= 1
    e = 0
    while e < ne
      weights[e] = 1
      e += 1
    step = 0
    while step < steps
      return 0 if (step & poll_mask) == 0 && wassat_perm_stop(m, stop, deadline) != 0
      m[7] += 1
      nb = 0
      sum = 0
      e = 0
      while e < ne
        pen = wassat_perm_cost(perm[left[e]], perm[right[e]], width)
        penalty[e] = pen
        sum += pen
        if pen > 0
          bad[nb] = e
          nb += 1
        e += 1
      m[13] = sum if sum < m[13]
      return 1 if sum == 0
      edge = bad[wassat_perm_rand(rng, nb)]
      u = wassat_perm_rand(rng, 2) != 0 ? left[edge] : right[edge]
      best_delta = 1 << 60
      target = -1
      ties = 0
      updates = 0
      v = 0
      while v < n
        if v != u
          delta = 0
          ds = 0
          at = heads[u]
          while at < heads[u + 1]
            e = occ[at]
            z = left[e] ^ right[e] ^ u
            if z != v
              d = wassat_perm_cost(perm[v], perm[z], width) - penalty[e]
              ds += d
              delta += d * weights[e]
              updates += 1
            at += 1
          at = heads[v]
          while at < heads[v + 1]
            e = occ[at]
            z = left[e] ^ right[e] ^ v
            if z != u
              d = wassat_perm_cost(perm[u], perm[z], width) - penalty[e]
              ds += d
              delta += d * weights[e]
              updates += 1
            at += 1
          admissible = (tabu[u] <= step && tabu[v] <= step) || sum + ds < m[13]
          if admissible
            if delta < best_delta
              best_delta = delta
              target = v
              ties = 1
            elsif delta == best_delta
              ties += 1
              target = v if wassat_perm_rand(rng, ties) == 0
        v += 1
      m[10] += n - 1
      m[11] += updates
      if target < 0
        target = wassat_perm_rand(rng, n)
        best_delta = 0
      if best_delta >= 0
        j = 0
        while j < nb
          weights[bad[j]] += 1
          j += 1
        m[9] += 1
      tmp = perm[u]
      perm[u] = perm[target]
      perm[target] = tmp
      until_step = step + 3 + wassat_perm_rand(rng, 8)
      tabu[u] = until_step
      tabu[target] = until_step
      m[8] += 1
      step += 1
    restart += 1
  m[22] = 3
  0

# Probe one anchor label per vertex. The common excluded prefix suggests a
# minimum distance; a failed probe or inconsistent width declines the shape.
-> wassat_perm_graph(s, nv, n, root, values, matrix, m, stop, deadline)
  counters = i64[4]
  rc = s.propagation_snapshot([], root, counters)
  m[4] = counters[0]; m[5] = counters[1]
  return 0 unless rc == 1
  assumptions = [0]
  width = 0
  row = 0
  while row < n
    return 0 if wassat_perm_stop(m, stop, deadline) != 0
    return 0 if root[row * n + 1] != 0 || root[row * n + 2] != 0
    assumptions[0] = row * n + 1
    rc = s.propagation_snapshot(assumptions, values, counters)
    m[4] = counters[0]; m[5] = counters[1]
    return 0 unless rc == 1
    other = 0
    while other < n
      if other != row && values[other * n + 2] < 0
        run = 0
        while run < n && values[other * n + run + 1] < 0
          run += 1
        return 0 if run < 2 || run >= n
        width = run if width == 0
        return 0 if run != width
        matrix[row * n + other] = 1
      other += 1
    row += 1
  m[4] = counters[0]
  m[5] = counters[1]
  width

-> wassat_perm_search(formula, art, n, m, stop, res, base, deadline,
                       restarts = WASSAT_PERM_RESTARTS, steps = WASSAT_PERM_STEPS)
  return 0 if n < 4 || n > WASSAT_PERM_MAX_N || wassat_perm_stop(m, stop, deadline) != 0
  nv = formula["nvars"]
  root = i8[nv + 1]
  values = i8[nv + 1]
  matrix = i8[n * n]
  s = Wassat.from_flat_lucky(nv, art)
  s.set_stop_cell(stop)
  width = wassat_perm_graph(s, nv, n, root, values, matrix, m, stop, deadline)
  return 0 if width == 0 || wassat_perm_stop(m, stop, deadline) != 0
  ne = 0
  u = 0
  while u < n
    v = 0
    while v < n
      return 0 if matrix[u * n + v] != matrix[v * n + u]
      ne += 1 if v > u && matrix[u * n + v] != 0
      v += 1
    u += 1
  return 0 if ne == 0
  m[1] = n
  m[2] = ne
  m[3] = width
  left = i64[ne]
  right = i64[ne]
  heads = i64[n + 1]
  occ = i64[2 * ne]
  fill = i64[n]
  e = 0
  u = 0
  while u < n
    v = u + 1
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
  while e < ne
    u = left[e]
    v = right[e]
    occ[heads[u] + fill[u]] = e
    occ[heads[v] + fill[v]] = e
    fill[u] += 1
    fill[v] += 1
    e += 1
  perm = i64[n]
  tabu = i64[n]
  weights = i64[ne]
  penalty = i64[ne]
  bad = i64[ne]
  rng = i64[1]
  rng[0] = 1
  t1 = clock_ms()
  m[19] = t1 - m[17]
  hit = wassat_perm_trial(n, ne, width, left, right, heads, occ, perm, tabu,
    weights, penalty, bad, rng, m, stop, deadline, restarts, steps)
  m[20] = clock_ms() - t1
  return 0 if hit == 0 || wassat_perm_stop(m, stop, deadline) != 0
  # Reversal preserves all inferred distances. Choose the orientation that
  # conflicts with fewer original root assignments, then propagate it.
  original_bad = 0
  reverse_bad = 0
  u = 0
  while u < n
    original_bad += 1 if root[u * n + perm[u] + 1] < 0
    reverse_bad += 1 if root[u * n + n - perm[u]] < 0
    u += 1
  assumptions = []
  u = 0
  while u < n
    perm[u] = n - 1 - perm[u] if reverse_bad < original_bad
    assumptions.push(u * n + perm[u] + 1)
    u += 1
  t2 = clock_ms()
  counters = i64[4]
  return 0 unless s.propagation_snapshot(assumptions, values, counters) == 1
  m[4] += counters[0]
  m[5] += counters[1]
  model = []
  v = 1
  while v <= nv
    model.push(values[v] > 0 ? v : -v)
    v += 1
  return 0 unless wassat_model_satisfies?(formula, model)
  return 0 if wassat_perm_stop(m, stop, deadline) != 0
  m[16] = 1
  m[14] = formula["flat_ncl"]
  m[15] = formula["flat_nlits"]
  m[21] = clock_ms() - t2
  v = 1
  while v <= nv
    res[base + v] = values[v] > 0 ? 1 : 0
    v += 1
  1

# Additional buffers beyond the private propagation solver, including model
# replay and the largest simple graph. Fixed buffers are reused on restarts.
-> wassat_perm_bytes(nv, n) (i64 i64) i64
  24 * (nv + 1) + 64 * n * n + 128 * n + 4096

# Cheap admission at both ends: encoders often append their long clauses.
# Full matrix validation and graph decoding happen on the worker. Declining
# reordered inputs is harmless for this proposal lane.
-> wassat_perm_prefix(lits, offs, lens, nv, nc) (i64[] i64[] i64[] i64 i64) i64
  return 0 if nc < 4 || lens.size < nc || offs.size < nc
  limit = nc < 1024 ? nc : 1024
  ci = 0
  n = 0
  while ci < limit
    index = ci < 512 ? ci : nc - limit + ci
    k = lens[index]
    return 0 if k < 1 || k > WASSAT_PERM_MAX_N
    if k > 3
      n = k if n == 0
      return 0 if k != n || n * n > nv
      off = offs[index]
      return 0 if off < 0 || off > lits.size || n > lits.size - off
      col = -1
      j = 0
      while j < n
        lit = lits[off + j]
        return 0 if lit < 1 || lit > n * n
        c = (lit - 1) % n
        col = c if col < 0
        return 0 if c != col
        j += 1
    ci += 1
  n

-> wassat_perm_plan(formula, workers, cdcl_arenas, sls_arenas, pre_arenas, extra)
  mode = env("WASSAT_PERM_WALK")
  return nil if mode == "0" || formula == nil
  return nil unless formula.has_key?("flat_ncl")
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  return nil if wassat_race_round1_conflicts != 0
  return nil if System.cpu_count <= workers || System.physical_memory_bytes <= 0
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  return nil if nv < 16 || nv > WASSAT_PERM_MAX_VARS || nc < 4 || nc > WASSAT_PERM_MAX_CLAUSES
  return nil if formula["flat_nlits"] > 2000000
  n = wassat_perm_prefix(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nv, nc)
  return nil if n < 4 || n * n > nv
  scratch = wassat_perm_bytes(nv, n)
  # Count the lean propagation shell as a full CDCL arena conservatively.
  return nil unless wassat_race_memory_fits?(formula, cdcl_arenas + 1,
    sls_arenas, pre_arenas, extra + scratch)
  { "meta": i64[24], "n": n, "scratch": scratch }

-> wassat_perm_arm(formula, art, plan, stop, res, base)
  m = plan["meta"]; nv = formula["nvars"]
  m[17] = clock_ms()
  m[23] = plan["scratch"]
  deadline = m[17] + WASSAT_PERM_WALL_MS
  hit = 0
  unless wassat_perm_stop(m, stop, deadline) != 0
    n = wassat_perm_matrix(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nv, formula["flat_ncl"])
    if n == plan["n"]
      hit = wassat_perm_search(formula, art, n, m, stop, res, base, deadline)
  m[18] = clock_ms()
  res[base + nv + 6] = m[17]
  res[base + nv + 5] = m[18]
  if hit == 1 && wassat_perm_stop(m, stop, deadline) == 0
    m[0] = 1
    z = ccall("__w_arr_store_rel", res, base, 1)
    won = wassat_stop_publish(stop, 1)
    return 1
  0

-> wassat_perm_start(formula, art, plan, stop, res, base)
  Thread.new -> wassat_perm_arm(formula, art, plan, stop, res, base)

-> wassat_perm_profile(plan, status)
  m = plan["meta"]
  wassat_prof_note("race.permutation status=[status] vertices=[m[1]] edges=[m[2]] width=[m[3]] probes=[m[4]] propagated=[m[5]] restarts=[m[6]] iterations=[m[7]] swaps=[m[8]] bumps=[m[9]] candidates=[m[10]] updates=[m[11]] polls=[m[12]] best_deficit=[m[13]] replay_clauses=[m[14]] replay_literals=[m[15]] verified=[m[16]] prepare_ms=[m[19]] search_ms=[m[20]] lift_ms=[m[21]] stopped=[m[22]] scratch_bytes=[m[23]] ms=[m[18] - m[17]]")
