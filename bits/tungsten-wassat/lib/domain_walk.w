# SAT-only search over verified exact-one domains and binary exclusions.
# A search miss is never an UNSAT result. Every candidate must satisfy every
# ORIGINAL clause, including duplicate clauses, before it can be published.
# Each move changes one domain's selected value, preserving exactly-one.
# Costs sum the weights of forbidden value pairs against current neighbors;
# local minima increase only the violated pair weights. Incremental updates
# and fixed buffers avoid rebuilding scores or allocating during the walk.
# Restarts use the consecutive seeds 1..8 with the same finite work budget.
use atomic_stop

WASSAT_DOMAIN_MAX_VARS = 2048
WASSAT_DOMAIN_MAX_BLOCKS = 128
WASSAT_DOMAIN_MAX_SIZE = 32
WASSAT_DOMAIN_MAX_CLAUSES = 400000
WASSAT_DOMAIN_RESTART_STEPS = 100000
WASSAT_DOMAIN_RESTARTS = 8
WASSAT_DOMAIN_WALL_MS = 15000

# m: status, recognized, stop(1 cancel/2 deadline/3 exhausted), blocks,
# prepared clauses/literals, restarts, iterations, flips, weight bumps,
# candidate scores, score updates, polls, best unique violations,
# replayed clauses/literals, verified, start/end ms, cleared weight words,
# preparation ms, scratch bytes, current-restart iterations, unused.
-> wassat_domain_stop(m, stop, deadline) (i64[] i64[] i64) i64
  return 1 if m[2] != 0
  m[12] += 1
  if wassat_stop_load(stop) != 0
    m[2] = 1
  elsif deadline > 0 && clock_ms() >= deadline
    m[2] = 2
  m[2] != 0 ? 1 : 0

fn wassat_domain_pop(x) (i64) i64
  ccall_nobox("__w_bit_ctpop_u64", x) ## i64

fn wassat_domain_ctz(x) (i64) i64
  ccall_nobox("__w_bit_cttz_u64", x) ## i64

# Recognize all clauses before using the finite-domain interpretation.
# Repeated positive rows are accepted only when they name exactly an already
# declared block; partial overlap and repeated variables in a row decline.
-> wassat_domain_prepare(lits, offs, lens, nv, nc, var_block, var_bit,
                          block_vars, block_len, dom, forbid, amo, seen,
                          is_block, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i8[] i64[] i64[] i64) i64
  return 0 if nv < 4 || nv > WASSAT_DOMAIN_MAX_VARS || nc < 1 || nc > WASSAT_DOMAIN_MAX_CLAUSES
  return 0 if offs.size < nc || lens.size < nc
  nb = 0
  covered = 0
  ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_domain_stop(m, stop, deadline) != 0
    width = lens[ci]
    off = offs[ci]
    return 0 if width < 1 || width > WASSAT_DOMAIN_MAX_SIZE
    return 0 if off < 0 || off > lits.size || width > lits.size - off
    positive = true
    j = 0
    while j < width
      lit = lits[off + j]
      return 0 if lit == 0 || lit > nv || lit < 0 - nv
      positive = false if lit < 0
      j += 1
    m[4] += 1
    m[5] += width
    if positive && width >= 2
      previous = var_block[lits[off]]
      mask = 0
      j = 0
      while j < width
        v = lits[off + j]
        return 0 if seen[v] == ci + 1 || var_block[v] != previous
        seen[v] = ci + 1
        mask |= 1 << var_bit[v] if previous != 0
        j += 1
      if previous != 0
        b = previous - 1
        return 0 if width != block_len[b] || mask != (1 << width) - 1
      else
        return 0 if nb == WASSAT_DOMAIN_MAX_BLOCKS
        block_len[nb] = width
        dom[nb] = (1 << width) - 1
        j = 0
        while j < width
          v = lits[off + j]
          var_block[v] = nb + 1
          var_bit[v] = j
          block_vars[nb * WASSAT_DOMAIN_MAX_SIZE + j] = v
          j += 1
        covered += width
        nb += 1
      is_block[ci] = 1
    ci += 1
  return 0 if nb < 2 || covered != nv
  ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_domain_stop(m, stop, deadline) != 0
    off = offs[ci]
    width = lens[ci]
    if is_block[ci] == 0
      if width == 1
        lit = lits[off]
        v = lit < 0 ? 0 - lit : lit
        b = var_block[v] - 1
        bit = 1 << var_bit[v]
        if lit > 0
          dom[b] &= bit
        else
          dom[b] ^= dom[b] & bit
      elsif width == 2 && lits[off] < 0 && lits[off + 1] < 0
        u = 0 - lits[off]
        v = 0 - lits[off + 1]
        bu = var_block[u] - 1
        bv = var_block[v] - 1
        if u == v
          dom[bu] ^= dom[bu] & (1 << var_bit[u])
        elsif bu == bv
          amo[u] |= 1 << var_bit[v]
          amo[v] |= 1 << var_bit[u]
        else
          forbid[u * WASSAT_DOMAIN_MAX_BLOCKS + bv] |= 1 << var_bit[v]
          forbid[v * WASSAT_DOMAIN_MAX_BLOCKS + bu] |= 1 << var_bit[u]
      else
        return 0
    ci += 1
  b = 0
  while b < nb
    return 0 if dom[b] == 0
    full = (1 << block_len[b]) - 1
    j = 0
    while j < block_len[b]
      v = block_vars[b * WASSAT_DOMAIN_MAX_SIZE + j]
      return 0 unless amo[v] == (full ^ (1 << j))
      j += 1
    b += 1
  return 0 if wassat_domain_stop(m, stop, deadline) != 0
  m[1] = 1
  m[3] = nb
  nb

# Original-clause replay is also bounded and cancellable. Do not publish a
# candidate on a partial scan or infer its validity from the incremental cost.
-> wassat_domain_verify(lits, offs, lens, nc, var_block, var_bit, sol, m, stop, deadline) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64) i64
  ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_domain_stop(m, stop, deadline) != 0
    off = offs[ci]
    j = 0
    hit = false
    while j < lens[ci]
      lit = lits[off + j]
      v = lit < 0 ? 0 - lit : lit
      selected = sol[var_block[v] - 1] == var_bit[v]
      hit = true if (lit > 0 && selected) || (lit < 0 && !selected)
      m[15] += 1
      j += 1
    m[14] += 1
    return 0 unless hit
    ci += 1
  return 0 if wassat_domain_stop(m, stop, deadline) != 0
  m[16] = 1
  1

-> wassat_domain_trial(block_vars, block_len, forbid, dom, sol, costs, counts,
                        weights, m, stop, nb, nv, seed, steps, deadline) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  stride = WASSAT_DOMAIN_MAX_SIZE
  i = 0
  while i < weights.size
    return 0 if (i & 4095) == 0 && wassat_domain_stop(m, stop, deadline) != 0
    weights[i] = 0
    m[19] += 1
    i += 1

  rng = seed
  rng = 88172645463325252 if rng == 0
  b = 0
  while b < nb
    return 0 if wassat_domain_stop(m, stop, deadline) != 0
    if dom[b] == 0
      return 0
    rng ^= rng << 13
    rng ^= rng >> 7
    rng ^= rng << 17
    offset = (rng & 2147483647) % wassat_domain_pop(dom[b])
    remaining = dom[b]
    while offset > 0
      remaining &= remaining - 1
      offset -= 1
    sol[b] = wassat_domain_ctz(remaining)
    b += 1
  b = 0
  while b < nb
    return 0 if wassat_domain_stop(m, stop, deadline) != 0
    j = 0
    while j < block_len[b]
      u = block_vars[b * stride + j]
      score = 0
      c = 0
      while c < nb
        score += 1 if ((forbid[u * WASSAT_DOMAIN_MAX_BLOCKS + c] >> sol[c]) & 1) != 0
        c += 1
      costs[b * stride + j] = score
      counts[b * stride + j] = score
      j += 1
    b += 1
  iteration = 0
  while iteration < steps
    return 0 if (iteration & 63) == 0 && wassat_domain_stop(m, stop, deadline) != 0
    iteration += 1
    m[7] += 1
    m[22] = iteration
    unsat = 0
    b = 0
    while b < nb
      unsat += counts[b * stride + sol[b]]
      b += 1
    unsat /= 2
    m[13] = unsat if unsat < m[13]
    return 1 if unsat == 0
    rng ^= rng << 13
    rng ^= rng >> 7
    rng ^= rng << 17
    noise = (rng & 63) == 0
    best_b = 0 - 1
    best_value = 0 - 1
    best_delta = nb * (iteration + 1) + 1
    ties = 0
    b = 0
    while b < nb
      if counts[b * stride + sol[b]] > 0
        current = costs[b * stride + sol[b]]
        values = dom[b] ^ (1 << sol[b])
        while values != 0
          j = wassat_domain_ctz(values)
          values &= values - 1
          delta = costs[b * stride + j] - current
          m[10] += 1
          if noise || delta <= best_delta
            if !noise && delta < best_delta
              best_delta = delta
              ties = 0
            ties += 1
            rng ^= rng << 13
            rng ^= rng >> 7
            rng ^= rng << 17
            if (rng & 2147483647) % ties == 0
              best_b = b
              best_value = j
      b += 1
    if best_b < 0
      return 0
    if best_delta >= 0 && !noise
      # Increase only currently violated relation weights. Update all value
      # scores touched by those weights, without rebuilding the score table.
      m[9] += 1
      b = 0
      while b < nb
        u = block_vars[b * stride + sol[b]]
        c = b + 1
        while c < nb
          if ((forbid[u * WASSAT_DOMAIN_MAX_BLOCKS + c] >> sol[c]) & 1) != 0
            v = block_vars[c * stride + sol[c]]
            weights[u * nv + v] += 1
            weights[v * nv + u] += 1
            costs[b * stride + sol[b]] += 1
            costs[c * stride + sol[c]] += 1
            m[11] += 2
          c += 1
        b += 1
    else
      b = best_b
      u = block_vars[b * stride + sol[b]]
      v = block_vars[b * stride + best_value]
      c = 0
      while c < nb
        old_mask = forbid[u * WASSAT_DOMAIN_MAX_BLOCKS + c]
        new_mask = forbid[v * WASSAT_DOMAIN_MAX_BLOCKS + c]
        remove = old_mask
        add = new_mask
        while remove != 0
          j = wassat_domain_ctz(remove)
          remove &= remove - 1
          neighbor = block_vars[c * stride + j]
          costs[c * stride + j] -= 1 + weights[u * nv + neighbor]
          counts[c * stride + j] -= 1
          m[11] += 1
        while add != 0
          j = wassat_domain_ctz(add)
          add &= add - 1
          neighbor = block_vars[c * stride + j]
          costs[c * stride + j] += 1 + weights[v * nv + neighbor]
          counts[c * stride + j] += 1
          m[11] += 1
        c += 1
      sol[b] = best_value
      m[8] += 1
  0

# Includes every worker buffer and conservative descriptor/alignment headroom.
-> wassat_domain_bytes(nv, nc) (i64 i64) i64
  (8 * ((nv + 1) * (nv + 1) + WASSAT_DOMAIN_MAX_BLOCKS * (nv + 1) + 4 * (nv + 1) + 3 * WASSAT_DOMAIN_MAX_BLOCKS * WASSAT_DOMAIN_MAX_SIZE + 3 * WASSAT_DOMAIN_MAX_BLOCKS)) + nc + 1048576

-> wassat_domain_search(lits, offs, lens, nv, nc, m, stop, res, base, restarts, steps, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64 i64 i64 i64) i64
  return 0 if wassat_domain_stop(m, stop, deadline) != 0
  return 0 if nv < 4 || nv > WASSAT_DOMAIN_MAX_VARS || nc < 1 || nc > WASSAT_DOMAIN_MAX_CLAUSES
  return 0 if restarts < 1 || restarts > 64 || steps < 1 || steps > 1000000
  var_block = i64[nv + 1]
  var_bit = i64[nv + 1]
  amo = i64[nv + 1]
  seen = i64[nv + 1]
  block_vars = i64[WASSAT_DOMAIN_MAX_BLOCKS * WASSAT_DOMAIN_MAX_SIZE]
  block_len = i64[WASSAT_DOMAIN_MAX_BLOCKS]
  dom = i64[WASSAT_DOMAIN_MAX_BLOCKS]
  forbid = i64[(nv + 1) * WASSAT_DOMAIN_MAX_BLOCKS]
  is_block = i8[nc]
  prep_deadline = clock_ms() + 50
  prep_deadline = deadline if deadline > 0 && deadline < prep_deadline
  nb = wassat_domain_prepare(lits, offs, lens, nv, nc, var_block, var_bit,
    block_vars, block_len, dom, forbid, amo, seen, is_block, m, stop, prep_deadline)
  m[20] = clock_ms() - m[17]
  return 0 if nb == 0
  m[21] = wassat_domain_bytes(nv, nc)
  # These four search buffers are allocated once and recycled at restarts.
  sol = i64[WASSAT_DOMAIN_MAX_BLOCKS]
  costs = i64[WASSAT_DOMAIN_MAX_BLOCKS * WASSAT_DOMAIN_MAX_SIZE]
  counts = i64[WASSAT_DOMAIN_MAX_BLOCKS * WASSAT_DOMAIN_MAX_SIZE]
  weights = i64[(nv + 1) * (nv + 1)]
  m[13] = nb * nb
  seed = 1
  while seed <= restarts
    return 0 if wassat_domain_stop(m, stop, deadline) != 0
    m[6] = seed
    hit = wassat_domain_trial(block_vars, block_len, forbid, dom, sol,
      costs, counts, weights, m, stop, nb, nv + 1, seed, steps, deadline)
    if hit == 1
      return 0 unless wassat_domain_verify(lits, offs, lens, nc, var_block, var_bit, sol, m, stop, deadline) == 1
      v = 1
      while v <= nv
        res[base + v] = sol[var_block[v] - 1] == var_bit[v] ? 1 : 0
        v += 1
      return 1
    return 0 if m[2] != 0
    seed += 1
  m[2] = 3
  0

-> wassat_domain_arm(lits, offs, lens, nv, nc, m, stop, res, base, restarts, steps, wall_ms) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64 i64 i64 i64) i64
  m[17] = clock_ms()
  deadline = wall_ms > 0 ? m[17] + wall_ms : 0
  found = wassat_domain_search(lits, offs, lens, nv, nc, m, stop, res, base, restarts, steps, deadline)
  m[18] = clock_ms()
  res[base + nv + 6] = m[17]
  res[base + nv + 5] = m[18]
  if found == 1 && wassat_domain_stop(m, stop, deadline) == 0
    m[0] = 1
    z = ccall("__w_arr_store_rel", res, base, 1)
    won = wassat_stop_publish(stop, 1)
    return 1
  0

# This prefix is only a cheap admission heuristic. It can decline reordered
# input; it never establishes a model or substitutes for the full recognizer.
-> wassat_domain_prefix(lits, offs, lens, nv, nc) (i64[] i64[] i64[] i64 i64) i64
  return 0 if nv < 64 || nv > WASSAT_DOMAIN_MAX_VARS || nc < 500 || nc > WASSAT_DOMAIN_MAX_CLAUSES
  return 0 if offs.size < nc || lens.size < nc
  limit = nc < 512 ? nc : 512
  binary = 0
  wide = 0
  ci = 0
  while ci < limit
    n = lens[ci]
    off = offs[ci]
    return 0 if n < 1 || n > WASSAT_DOMAIN_MAX_SIZE || off < 0 || off > lits.size || n > lits.size - off
    if n == 2
      binary += 1 if lits[off] < 0 && lits[off + 1] < 0
    elsif n >= 8
      j = 0
      positive = true
      while j < n
        v = lits[off + j]
        positive = false if v < 1 || v > nv
        j += 1
      wide += 1 if positive
    ci += 1
  wide > 0 && binary * 4 >= limit * 3 ? 1 : 0

-> wassat_domain_plan(formula, workers, cdcl_arenas, sls_arenas, pre_arenas)
  mode = env("WASSAT_DOMAIN_WALK")
  return nil if mode == "0" || formula == nil
  return nil unless formula.has_key?("flat_ncl")
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  return nil if System.cpu_count <= workers || System.physical_memory_bytes <= 0
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return nil if nv < 4 || nv > WASSAT_DOMAIN_MAX_VARS || nc < 1 || nc > WASSAT_DOMAIN_MAX_CLAUSES
  return nil if formula["flat_nlits"] > WASSAT_DOMAIN_MAX_CLAUSES * WASSAT_DOMAIN_MAX_SIZE
  if mode != "1"
    return nil if wassat_domain_prefix(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nv, nc) == 0
  return nil unless wassat_race_memory_fits?(formula, cdcl_arenas, sls_arenas, pre_arenas, wassat_domain_bytes(nv, nc))
  { "meta": i64[24] }

# Resolve boxed metadata before starting a worker. Recognition, allocations,
# every restart, replay and publication then use only typed native operations.
-> wassat_domain_start(formula, plan, stop, res, base)
  lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
  nv = formula["nvars"]; nc = formula["flat_ncl"]; m = plan["meta"]
  Thread.new -> wassat_domain_arm(lits, offs, lens, nv, nc, m, stop, res, base,
    WASSAT_DOMAIN_RESTARTS, WASSAT_DOMAIN_RESTART_STEPS, WASSAT_DOMAIN_WALL_MS)

-> wassat_domain_profile(plan, status)
  m = plan["meta"]
  wassat_prof_note("race.domain status=[status] recognized=[m[1]] stopped=[m[2]] blocks=[m[3]] prep_clauses=[m[4]] prep_literals=[m[5]] restarts=[m[6]] iterations=[m[7]] flips=[m[8]] bumps=[m[9]] candidates=[m[10]] updates=[m[11]] polls=[m[12]] best_unique=[m[13]] replay_clauses=[m[14]] replay_literals=[m[15]] verified=[m[16]] clear_words=[m[19]] prepare_ms=[m[20]] scratch_bytes=[m[21]] restart_iterations=[m[22]] ms=[m[18] - m[17]]")
