# Model-only search for a small exact-size selection with coverage quotas,
# hidden behind feature aliases and row-major Sinz counters. Every accepted
# counter clause is checked, but recognition is only a proposal mechanism:
# SAT publication additionally requires replay of EVERY input clause.
# Unsupported layouts, missing clauses, deadlines and search misses return
# UNKNOWN. No UNSAT conclusion is available from this worker.
use atomic_stop

WASSAT_QUOTA_INPUTS = 512
WASSAT_QUOTA_GROUPS = 64
WASSAT_QUOTA_ALIASES = 65536
WASSAT_QUOTA_WALL_MS = 2000

# m: 0 selectors, 1 alias end, 2 counters, 3 distinct quotas, 4 exact size,
# 5 decoded clauses, 6 counter rows, 7 swaps, 8 swap evaluations,
# 9 best deficit, 10 stop reason (1 deadline,2 cancel,3 work cap),11 deadline,
# 12 polls,13 replay clauses,14 lifted cells,15 restarts,16 recognized,
# 17 start,18 finish,19 decode ms,20 search ms,21 lift/replay ms,22 scratch.
-> wassat_quota_poll(m, stop) (i64[] i64[]) i64
  m[12] += 1
  if wassat_stop_load(stop) != 0
    m[10] = 2
  elsif m[11] > 0 && clock_ms() >= m[11]
    m[10] = 1
  m[10]

-> wassat_quota_abs(x) (i64) i64
  x < 0 ? 0 - x : x

-> wassat_quota_clause2(lits, offs, lens, ci, a, b) (i64[] i64[] i64[] i64 i64 i64) i64
  return 0 if ci >= lens.size || ci >= offs.size || lens[ci] != 2
  off = offs[ci] ## i64
  return 0 if off < 0 || off + 2 > lits.size
  x = lits[off] ## i64
  y = lits[off + 1] ## i64
  ((x == a && y == b) || (x == b && y == a)) ? 1 : 0

-> wassat_quota_clause3(lits, offs, lens, ci, a, b, c) (i64[] i64[] i64[] i64 i64 i64 i64) i64
  return 0 if ci >= lens.size || ci >= offs.size || lens[ci] != 3
  off = offs[ci] ## i64
  return 0 if off < 0 || off + 3 > lits.size
  x = lits[off] ## i64
  y = lits[off + 1] ## i64
  z = lits[off + 2] ## i64
  # Expected literals have distinct variables, so membership plus arity
  # verifies the complete clause, including multiplicity.
  return 0 if x == y || x == z || y == z
  return 0 unless x == a || x == b || x == c
  return 0 unless y == a || y == b || y == c
  return 0 unless z == a || z == b || z == c
  1

-> wassat_quota_decode(lits, offs, lens, nv, nc, aliases, roots, bounds, sizes, inputs, m, stop) (i64[] i64[] i64[] i64 i64 i32[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  return 0 if nc < 4 || lens.size < nc || offs.size < nc
  return 0 if lens[0] != 2 || offs[0] < 0 || offs[0] + 2 > lits.size
  n = wassat_quota_abs(lits[offs[0] + 1]) - 1 ## i64
  return 0 if n < 2 || n > WASSAT_QUOTA_INPUTS
  maxv = n ## i64
  ci = 0 ## i64
  while ci + 1 < nc && lens[ci] == 2
    off = offs[ci] ## i64
    return 0 if off < 0 || off + 2 > lits.size
    x = 0 - lits[off] ## i64
    y = wassat_quota_abs(lits[off + 1]) ## i64
    break if x < 1 || x > n || y != maxv + 1
    break if wassat_quota_clause2(lits, offs, lens, ci + 1, x, 0 - y) == 0
    return 0 if y >= aliases.size || y > nv
    aliases[y] = lits[off + 1] > 0 ? x : 0
    maxv = y
    ci += 2
    return 0 if (ci & 1023) == 0 && wassat_quota_poll(m, stop) != 0
  return 0 if maxv == n
  m[0] = n; m[1] = maxv
  g = 0 ## i64
  while ci < nc
    return 0 if g >= WASSAT_QUOTA_GROUPS || wassat_quota_poll(m, stop) != 0
    root = maxv + 1 ## i64
    return 0 if root > nv || lens[ci] != 2
    off = offs[ci] ## i64
    return 0 if off < 0 || off + 2 > lits.size
    a = lits[off] ## i64
    b = lits[off + 1] ## i64
    return 0 unless a == root || b == root
    input = 0 - (a == root ? b : a) ## i64
    return 0 if input == 0 || wassat_quota_abs(input) > m[1]
    inputs[g * WASSAT_QUOTA_INPUTS] = input
    ci += 1
    k = 1 ## i64
    while ci < nc && lens[ci] == 1
      off = offs[ci]
      return 0 if off < 0 || off >= lits.size || lits[off] != 0 - (root + k)
      k += 1; ci += 1
      return 0 if k > WASSAT_QUOTA_INPUTS
    rows = 1 ## i64
    done = 0 ## i64
    while done == 0
      m[5] = ci; m[6] += 1
      return 0 if rows >= WASSAT_QUOTA_INPUTS || ci >= nc || lens[ci] != 2
      return 0 if (rows & 15) == 0 && wassat_quota_poll(m, stop) != 0
      off = offs[ci]
      return 0 if off < 0 || off + 2 > lits.size
      a = lits[off]; b = lits[off + 1]
      last = root + rows * k - 1 ## i64
      return 0 if last > nv
      if a == 0 - last || b == 0 - last
        input = 0 - (a == 0 - last ? b : a)
        done = 1
      else
        head = last + 1 ## i64
        return 0 if head + k - 1 > nv
        return 0 unless a == head || b == head
        input = 0 - (a == head ? b : a)
      return 0 if input == 0 || wassat_quota_abs(input) > m[1]
      inputs[g * WASSAT_QUOTA_INPUTS + rows] = input
      ci += 1
      if done == 0
        head = last + 1
        return 0 if wassat_quota_clause2(lits, offs, lens, ci, 0 - (head - k), head) == 0
        ci += 1
        j = 1 ## i64
        while j < k
          return 0 if wassat_quota_clause3(lits, offs, lens, ci, 0 - input, 0 - (head - k + j - 1), head + j) == 0
          return 0 if wassat_quota_clause2(lits, offs, lens, ci + 1, 0 - (head - k + j), head + j) == 0
          ci += 2; j += 1
        return 0 if wassat_quota_clause2(lits, offs, lens, ci, 0 - input, 0 - last) == 0
        ci += 1; rows += 1
    roots[g] = root; bounds[g] = k; sizes[g] = rows + 1
    maxv = root + rows * k - 1
    g += 1
  return 0 unless ci == nc && maxv == nv
  m[2] = g; m[5] = ci
  1

# Convert only unweighted positive coverage rows and a complementary exact
# selection bound. Aliases to false disappear; duplicate input occurrences,
# mixed polarity, and other upper bounds are deliberately unsupported.
-> wassat_quota_reduce(aliases, bounds, sizes, inputs, masks, need, m) (i32[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  n = m[0] ## i64
  rows = i8[WASSAT_QUOTA_GROUPS * WASSAT_QUOTA_INPUTS]
  row = i8[WASSAT_QUOTA_INPUTS]
  upper = n + 1 ## i64
  lower = 0 - 1 ## i64
  nr = 0 ## i64
  g = 0 ## i64
  one = 1 ## i64
  while g < m[2]
    v = 0 ## i64
    while v < n
      row[v] = 0; v += 1
    sign = 0 ## i64
    full = 1 ## i64
    possible = 0 ## i64
    j = 0 ## i64
    while j < sizes[g]
      input = inputs[g * WASSAT_QUOTA_INPUTS + j] ## i64
      polarity = input > 0 ? 1 : -1 ## i64
      return 0 if sign != 0 && sign != polarity
      sign = polarity
      x = wassat_quota_abs(input) ## i64
      full = 0 if x > n
      x = aliases[x] if x > n
      if x != 0
        return 0 if row[x - 1] != 0
        row[x - 1] = 1
        possible += 1
      j += 1
    if full == 1 && sizes[g] == n
      if sign == 1
        upper = bounds[g] if bounds[g] < upper
      else
        lower = n - bounds[g] if n - bounds[g] > lower
    else
      return 0 unless sign == -1
      quota = sizes[g] - bounds[g] ## i64
      return 0 if quota < 1 || quota > possible
      same = 0 - 1 ## i64
      r = 0 ## i64
      while r < nr
        equal = 1 ## i64
        v = 0
        while v < n && equal == 1
          equal = 0 if rows[r * WASSAT_QUOTA_INPUTS + v] != row[v]
          v += 1
        same = r if equal == 1
        r += 1
      if same < 0
        return 0 if nr >= 62
        same = nr; nr += 1
        v = 0
        while v < n
          rows[same * WASSAT_QUOTA_INPUTS + v] = row[v]
          masks[v] |= one << same if row[v] != 0
          v += 1
      need[same] = quota if quota > need[same]
    g += 1
  return 0 if lower != upper || lower < 1 || lower > n || nr == 0
  r = 0 ## i64
  while r < nr
    return 0 if need[r] > lower
    r += 1
  m[3] = nr; m[4] = lower; m[16] = 1
  1

-> wassat_quota_rand(rng, limit) (i64[] i64) i64
  rng[0] = (rng[0] * 48271) % 2147483647
  rng[0] % limit

fn wassat_quota_ctz(x) (i64) i64
  ccall_nobox("__w_bit_cttz_u64", x) ## i64

-> wassat_quota_walk(masks, need, selected, m, stop) (i64[] i64[] i64[] i64[] i64[]) i64
  n = m[0] ## i64
  nr = m[3] ## i64
  k = m[4] ## i64
  counts = i64[64]; weights = i64[64]; tabu = i64[n]
  inside = i8[n]; bad = i64[64]; rng = i64[1]
  rng[0] = 7
  m[9] = n * nr
  one = 1 ## i64
  restart = 0 ## i64
  while restart < 64
    return 0 if wassat_quota_poll(m, stop) != 0
    m[15] += 1
    v = 0 ## i64
    while v < n
      inside[v] = 0; tabu[v] = 0; v += 1
    r = 0 ## i64
    while r < nr
      counts[r] = 0; weights[r] = 1; r += 1
    t = 0 ## i64
    while t < k
      return 0 if wassat_quota_poll(m, stop) != 0
      bv = 0 - 1 ## i64
      best = 0 - 1 ## i64
      ties = 0 ## i64
      v = 0
      while v < n
        if inside[v] == 0
          score = 0 ## i64
          bits = masks[v] ## i64
          while bits != 0
            r = wassat_quota_ctz(bits); bits &= bits - 1
            score += 1 if counts[r] < need[r]
          if score > best
            best = score; bv = v; ties = 1
          elsif score == best
            ties += 1
            bv = v if wassat_quota_rand(rng, ties) == 0
        v += 1
      selected[t] = bv; inside[bv] = 1
      bits = masks[bv]
      while bits != 0
        r = wassat_quota_ctz(bits); bits &= bits - 1
        counts[r] += 1
      t += 1
    it = 0 ## i64
    while it < 20000
      return 0 if wassat_quota_poll(m, stop) != 0
      nb = 0 ## i64
      deficit = 0 ## i64
      r = 0
      while r < nr
        if counts[r] < need[r]
          bad[nb] = r; nb += 1
          deficit += need[r] - counts[r]
        r += 1
      m[9] = deficit if deficit < m[9]
      return 1 if deficit == 0
      row = bad[wassat_quota_rand(rng, nb)] ## i64
      best_delta = 1000000000 ## i64
      bi = 0 - 1 ## i64
      bv = 0 - 1
      ties = 0
      noise = wassat_quota_rand(rng, 100) < 3 ## bool
      v = 0
      while v < n
        return 0 if (v & 15) == 0 && wassat_quota_poll(m, stop) != 0
        if inside[v] == 0 && (masks[v] & (one << row)) != 0 && tabu[v] <= it
          i = 0 ## i64
          while i < k
            old = selected[i] ## i64
            if tabu[old] <= it
              delta = 0 ## i64
              changed = masks[v] ^ masks[old] ## i64
              add = masks[v] & changed ## i64
              sub = masks[old] & changed ## i64
              while add != 0
                r = wassat_quota_ctz(add); add &= add - 1
                delta -= weights[r] if counts[r] < need[r]
              while sub != 0
                r = wassat_quota_ctz(sub); sub &= sub - 1
                delta += weights[r] if counts[r] <= need[r]
              m[8] += 1
              delta = 0 if noise
              if delta < best_delta
                best_delta = delta; bi = i; bv = v; ties = 1
              elsif delta == best_delta
                ties += 1
                if wassat_quota_rand(rng, ties) == 0
                  bi = i; bv = v
            i += 1
        v += 1
      if bi >= 0
        if best_delta >= 0 && !noise
          r = 0
          while r < nb
            weights[bad[r]] += 1; r += 1
        old = selected[bi]
        inside[old] = 0; inside[bv] = 1; selected[bi] = bv
        tabu[old] = it + 3; tabu[bv] = it + 3
        bits = masks[old]
        while bits != 0
          r = wassat_quota_ctz(bits); bits &= bits - 1
          counts[r] -= 1
        bits = masks[bv]
        while bits != 0
          r = wassat_quota_ctz(bits); bits &= bits - 1
          counts[r] += 1
        m[7] += 1
      it += 1
    restart += 1
  m[10] = 3
  0

-> wassat_quota_lift(aliases, roots, bounds, sizes, inputs, selected, res, nv, m, stop) (i32[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64[] i64[]) i64
  i = 0 ## i64
  while i < m[4]
    res[selected[i] + 1] = 1; i += 1
  v = m[0] + 1 ## i64
  while v <= m[1]
    res[v] = aliases[v] == 0 ? 0 : res[aliases[v]]
    v += 1
  g = 0 ## i64
  while g < m[2]
    sum = 0 ## i64
    i = 0
    while i + 1 < sizes[g]
      return 0 if (i & 15) == 0 && wassat_quota_poll(m, stop) != 0
      input = inputs[g * WASSAT_QUOTA_INPUTS + i] ## i64
      value = res[wassat_quota_abs(input)] ## i64
      sum += 1 if (input > 0 && value == 1) || (input < 0 && value == 0)
      base = roots[g] + i * bounds[g] ## i64
      j = 0 ## i64
      while j < bounds[g]
        res[base + j] = sum > j ? 1 : 0
        m[14] += 1
        j += 1
      i += 1
    g += 1
  1

-> wassat_quota_replay(lits, offs, lens, res, nv, nc, m, stop) (i64[] i64[] i64[] i64[] i64 i64 i64[] i64[]) i64
  ci = 0 ## i64
  while ci < nc
    return 0 if (ci & 1023) == 0 && wassat_quota_poll(m, stop) != 0
    off = offs[ci] ## i64
    size = lens[ci] ## i64
    return 0 if off < 0 || size < 0 || off + size > lits.size
    hit = 0 ## i64
    j = 0 ## i64
    while j < size
      lit = lits[off + j] ## i64
      v = wassat_quota_abs(lit) ## i64
      return 0 if v < 1 || v > nv
      hit = 1 if (lit > 0 && res[v] == 1) || (lit < 0 && res[v] == 0)
      j += 1
    m[13] += 1
    return 0 if hit == 0
    ci += 1
  1

-> wassat_quota_run(formula, m, stop, res)
  m[17] = clock_ms(); m[11] = m[17] + WASSAT_QUOTA_WALL_MS
  m[18] = m[17]
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  return 0 if nv < 4 || nv > 5000000 || nc < 4 || nc > 10000000
  return 0 if wassat_quota_poll(m, stop) != 0
  aliases = i32[WASSAT_QUOTA_ALIASES]
  roots = i64[64]; bounds = i64[64]; sizes = i64[64]
  inputs = i64[WASSAT_QUOTA_GROUPS * WASSAT_QUOTA_INPUTS]
  masks = i64[WASSAT_QUOTA_INPUTS]; need = i64[64]; selected = i64[WASSAT_QUOTA_INPUTS]
  lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
  ok = wassat_quota_decode(lits, offs, lens, nv, nc, aliases, roots, bounds, sizes, inputs, m, stop)
  ok = wassat_quota_reduce(aliases, bounds, sizes, inputs, masks, need, m) if ok == 1
  m[19] = clock_ms() - m[17]
  began = clock_ms()
  ok = wassat_quota_walk(masks, need, selected, m, stop) if ok == 1
  m[20] = clock_ms() - began
  began = clock_ms()
  ok = wassat_quota_lift(aliases, roots, bounds, sizes, inputs, selected, res, nv, m, stop) if ok == 1
  ok = wassat_quota_replay(lits, offs, lens, res, nv, nc, m, stop) if ok == 1
  m[21] = clock_ms() - began
  m[18] = clock_ms()
  res[nv + 6] = m[17]; res[nv + 5] = m[18]
  return 0 if ok == 0 || wassat_quota_poll(m, stop) != 0
  z = ccall("__w_arr_store_rel", res, 0, 1)
  won = wassat_stop_publish(stop, 1)
  1

-> wassat_quota_profile(m, status)
  wassat_prof_note("scout.quota status=[status] selectors=[m[0]] alias_end=[m[1]] counters=[m[2]] quotas=[m[3]] selected=[m[4]] decoded_clauses=[m[5]] rows=[m[6]] swaps=[m[7]] evaluations=[m[8]] best_deficit=[m[9]] stopped=[m[10]] polls=[m[12]] replayed=[m[13]] lifted=[m[14]] restarts=[m[15]] recognized=[m[16]] decode_ms=[m[19]] search_ms=[m[20]] replay_ms=[m[21]] ms=[m[18] - m[17]]")

# Add only beside the single scout, with its normal XOR companion. This
# avoids displacing another optional arm or enlarging a full portfolio.
# As for the cyclic serial companion, reserve the conservative complete
# resident estimate under both physical RAM and the runtime's memory limit.
-> wassat_quota_plan(formula)
  mode = env("WASSAT_QUOTA_COVER")
  return nil if mode == "0" || formula == nil || System.cpu_count < 3
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  return nil if wassat_race_round1_conflicts != 0
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  return nil if nv < 4 || nv > 5000000 || nc < 4 || nc > 10000000
  return nil if mode != "1" && (nv < 10000 || nc < 10000)
  lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
  return nil if lens.size < nc || offs.size < nc || lens[0] != 2
  off = offs[0]
  return nil if off < 0 || off + 2 > lits.size
  x = 0 - lits[off]; y = wassat_quota_abs(lits[off + 1])
  return nil if y < 3 || y > WASSAT_QUOTA_INPUTS + 1 || x < 1 || x >= y
  return nil if wassat_quota_clause2(lits, offs, lens, 1, x, 0 - y) == 0
  scratch = 24 * (nv + 1) + 4194304
  memory = System.physical_memory_bytes
  return nil if memory <= 0 || scratch > memory / 64 || scratch > 268435456
  resident = wassat_cdcl_arena_bytes(formula) + wassat_preprocess_arena_bytes(formula)
  limit = wassat_cycle_memory_limit(env("TUNGSTEN_MEMORY_LIMIT"))
  return nil if (resident + scratch) * 10 > limit * 9 || resident + scratch > memory / 3
  m = i64[24]
  m[22] = scratch
  m
