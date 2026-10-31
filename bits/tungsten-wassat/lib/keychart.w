# A model-only heuristic for a four-depth key/lock incidence encoding.
# Infer domains and OR supports from input clauses, then walk the smaller
# finite-domain problem and repair near models under key-level assumptions.
# Recognition is deliberately only a heuristic: additional input constraints
# are allowed. Every candidate is checked against ALL original clauses. This
# lane never publishes UNSAT, including after an empty failed-assumption core.

use atomic_stop

# Bounds cap both recognition memory and one complete move scan. No filename,
# digest, expected verdict, or stored assignment participates in recognition.
-> wassat_keychart_detect(lits, offs, lens, nv, nc, meta, allowed, defs, wkey, wlock) (i64[] i64[] i64[] i64 i64 i64[] i8[] i64[] i32[] i32[]) i64
  primary = 0
  ci = 0
  while ci < nc && lens[ci] == 4
    j = 0
    good = 1
    while j < 4
      good = 0 if lits[offs[ci] + j] != primary + j + 1
      j += 1
    break if good == 0
    primary += 4
    ci += 1
  return 0 if primary < 8 || primary > 4096 || primary > nv
  stride = 0
  ndefs = 0
  ci = 0
  while ci < nc
    n = lens[ci]
    o = offs[ci]
    if n > 2 && lits[o] < 0
      v = 0 - lits[o]
      good = v > primary && v <= nv ? 1 : 0
      j = 1
      while j < n && good == 1
        x = lits[o + j]
        good = 0 if x < 1 || x > primary
        good = 0 if j > 1 && x <= lits[o + j - 1]
        j += 1
      if good == 1
        return 0 if defs[v] != 0
        defs[v] = ci + 1
        ndefs += 1
        j = 2
        while j < n
          a = stride
          b = lits[o + j] - lits[o + j - 1]
          while b != 0
            t = a % b
            a = b
            b = t
          stride = a
          j += 1
    ci += 1
  return 0 if stride < 8 || stride > 64 || stride % 4 != 0
  return 0 if primary % stride != 0 || ndefs == 0 || ndefs % stride != 0
  nk = primary / stride
  nl = ndefs / stride
  return 0 if nk < 2 || nk > 64 || nl > 64 || primary + ndefs > nv
  base = primary + ndefs
  l = 0
  while l < nl
    v = primary + l * stride + 1
    return 0 if defs[v] == 0
    ci = defs[v] - 1
    j = 1
    while j < lens[ci]
      x = lits[offs[ci] + j] - 1
      return 0 if x % stride != 0
      allowed[l * nk + x / stride] = 1
      j += 1
    d = 0
    while d < stride
      return 0 if defs[v + d] == 0
      ci = defs[v + d] - 1
      j = 1
      k = 0
      while k < nk
        if allowed[l * nk + k] == 1
          return 0 if j >= lens[ci]
          return 0 if lits[offs[ci] + j] != k * stride + d + 1
          j += 1
        k += 1
      return 0 if j != lens[ci]
      d += 1
    l += 1
  # Witness implications provide phases for auxiliary variables. Ambiguous
  # or incomplete pairs are rejected; all remaining variables default false.
  ci = 0
  while ci < nc
    if lens[ci] == 2
      a = lits[offs[ci]]
      b = lits[offs[ci] + 1]
      if a < 0 - base
        v = 0 - a
        return 0 if v > nv
        if b > 0 && b <= primary
          return 0 if wkey[v] != 0
          wkey[v] = b
        elsif b < 0 - primary && b >= 0 - base
          return 0 if wlock[v] != 0
          wlock[v] = 0 - b
    ci += 1
  witnesses = 0
  v = base + 1
  while v <= nv
    if wkey[v] != 0 || wlock[v] != 0
      return 0 if wkey[v] == 0 || wlock[v] == 0
      a = wkey[v] - 1
      b = wlock[v] - primary - 1
      return 0 if a % stride != b % stride
      return 0 if allowed[(b / stride) * nk + a / stride] != 0
      witnesses += 1
    v += 1
  return 0 if witnesses == 0
  meta[0] = nk
  meta[1] = nl
  meta[2] = stride / 4
  meta[3] = primary
  meta[4] = base
  1

-> wassat_keychart_plan(formula)
  return nil if formula == nil || formula["flat_lits"] == nil
  nv = formula["nvars"]
  lits = formula["flat_lits"]
  offs = formula["flat_offs"]
  lens = formula["flat_lens"]
  nc = lens.size
  return nil if nv < 16 || nv > 50000 || nc < 2 || nc > 100000
  return nil if lens[0] != 4
  return nil if lits[offs[0]] != 1 || lits[offs[0] + 1] != 2 || lits[offs[0] + 2] != 3 || lits[offs[0] + 3] != 4
  meta = i64[5]
  allowed = i8[4096]
  defs = i64[nv + 1]
  wkey = i32[nv + 1]
  wlock = i32[nv + 1]
  return nil if wassat_keychart_detect(lits, offs, lens, nv, nc, meta, allowed, defs, wkey, wlock) == 0
  nk = meta[0]
  nl = meta[1]
  np = meta[2]
  { "meta": meta, "allowed": allowed, "wkey": wkey, "wlock": wlock,
    "value": i64[nk * np], "count": i64[nl * np * 4],
    "other": i64[nl * nk * np], "dist": i64[nl * nk],
    "weight": i64[nl * nk], "state": i64[16], "mutable": i8[nk],
    "phases": i64[nv], "sign": i64[nv + 1],
    "assumptions": i64[nk * np] }

-> wassat_keychart_rebuild(allowed, value, count, other, dist, weight, st, nk, nl, np, nd) (i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64) i64
  i = 0
  while i < nl * np * nd
    count[i] = 0
    i += 1
  l = 0
  while l < nl
    k = 0
    while k < nk
      if allowed[l * nk + k] == 1
        p = 0
        while p < np
          at = (l * np + p) * nd + value[k * np + p]
          count[at] += 1
          p += 1
      k += 1
    l += 1
  bad = 0
  score = 0
  l = 0
  while l < nl
    k = 0
    while k < nk
      pair = l * nk + k
      if allowed[pair] == 0
        low = nk + 1
        second = nk + 1
        ties = 0
        p = 0
        while p < np
          n = count[(l * np + p) * nd + value[k * np + p]]
          if n < low
            second = low
            low = n
            ties = 1
          elsif n == low
            ties += 1
          elsif n < second
            second = n
          p += 1
        dist[pair] = low
        bad += 1 if low > 0
        score += low * weight[pair]
        p = 0
        while p < np
          n = count[(l * np + p) * nd + value[k * np + p]]
          m = low
          m = second if n == low && ties == 1
          other[pair * np + p] = m
          p += 1
      k += 1
    l += 1
  st[2] = bad
  st[3] = score
  st[4] = bad if bad < st[4]
  bad

-> wassat_keychart_delta(allowed, value, count, other, dist, weight, nk, nl, np, nd, key, pos, cand) (i8[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64) i64
  old = value[key * np + pos]
  delta = 0
  l = 0
  while l < nl
    pair = l * nk + key
    base = (l * np + pos) * nd
    if allowed[pair] == 0
      cost = count[base + cand]
      rest = other[pair * np + pos]
      cost = rest if rest < cost
      delta += weight[pair] * (cost - dist[pair])
    else
      k = 0
      while k < nk
        pair = l * nk + k
        if allowed[pair] == 0
          d = value[k * np + pos]
          change = 0
          change = -1 if d == old
          change = 1 if d == cand
          if change != 0
            cost = count[base + d] + change
            rest = other[pair * np + pos]
            cost = rest if rest < cost
            delta += weight[pair] * (cost - dist[pair])
        k += 1
    l += 1
  delta

-> wassat_keychart_walk(allowed, value, count, other, dist, weight, st, nk, nl, np, nd, jump, steps, stop) (i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64 i64 i64[]) i64
  seed = st[0]
  iter = 0
  while iter < steps && st[2] > st[8]
    if (iter & 15) == 0 && wassat_stop_load(stop) != 0
      st[9] = 1
      break
    best = 0
    ties = 0
    bk = 0
    bp = 0
    bc = 0
    k = 0
    while k < nk
      p = 0
      while p < np
        old = value[k * np + p]
        d = 0
        while d < nd
          valid = d != old
          if valid && p > 0
            diff = d - value[k * np + p - 1]
            diff = 0 - diff if diff < 0
            valid = false if diff > jump
          if valid && p + 1 < np
            diff = d - value[k * np + p + 1]
            diff = 0 - diff if diff < 0
            valid = false if diff > jump
          if valid
            delta = wassat_keychart_delta(allowed, value, count, other, dist, weight, nk, nl, np, nd, k, p, d)
            st[5] += 1
            if ties == 0 || delta < best
              best = delta
              ties = 1
              bk = k
              bp = p
              bc = d
            elsif delta == best
              ties += 1
              seed = (seed * 1103515245 + 12345) & 2147483647
              if (seed >> 8) % ties == 0
                bk = k
                bp = p
                bc = d
          d += 1
        p += 1
      k += 1
    if best >= 0
      i = 0
      while i < nk * nl
        weight[i] += 1 if allowed[i] == 0 && dist[i] > 0
        i += 1
      st[7] += 1
    seed = (seed * 1103515245 + 12345) & 2147483647
    if best > 0 || (seed >> 8) % 100 < 3
      tries = 0
      done = false
      while tries < 100 && !done
        seed = (seed * 1103515245 + 12345) & 2147483647
        k = (seed >> 8) % nk
        seed = (seed * 1103515245 + 12345) & 2147483647
        p = (seed >> 8) % np
        seed = (seed * 1103515245 + 12345) & 2147483647
        d = (seed >> 8) % nd
        valid = d != value[k * np + p]
        if valid && p > 0
          diff = d - value[k * np + p - 1]
          diff = 0 - diff if diff < 0
          valid = false if diff > jump
        if valid && p + 1 < np
          diff = d - value[k * np + p + 1]
          diff = 0 - diff if diff < 0
          valid = false if diff > jump
        if valid
          bk = k
          bp = p
          bc = d
          done = true
        tries += 1
    value[bk * np + bp] = bc
    st[1] += 1
    st[6] += 1
    z = wassat_keychart_rebuild(allowed, value, count, other, dist, weight, st, nk, nl, np, nd)
    iter += 1
  st[0] = seed
  st[2]

# All scratch belongs to this plan and is reused across the walk and queries.
# state: RNG, moves, bad pairs, score, best bad, move evaluations, rebuilds,
# weight bumps, target bad, cancelled, repair rounds, repair conflicts,
# relaxed keys, local-search ms, repair ms, verified result.
-> wassat_keychart_seed(allowed, value, count, other, dist, weight, st, nk, nl, np) (i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64)
  seed = 1
  i = 0
  while i < nk * nl
    weight[i] = 1
    i += 1
  k = 0
  while k < nk
    p = 0
    while p < np
      lo = 0
      hi = 3
      if p > 0
        lo = value[k * np + p - 1] - 1
        hi = value[k * np + p - 1] + 1
        lo = 0 if lo < 0
        hi = 3 if hi > 3
      seed = (seed * 1103515245 + 12345) & 2147483647
      value[k * np + p] = lo + ((seed >> 8) % (hi - lo + 1))
      p += 1
    k += 1
  st[0] = seed
  st[4] = nk * nl
  st[8] = 2
  wassat_keychart_rebuild(allowed, value, count, other, dist, weight, st, nk, nl, np, 4)
  0

-> wassat_keychart_phases(value, count, allowed, dist, mutable, wkey, wlock, phases, sign, nk, nl, np, nv) (i64[] i64[] i8[] i64[] i8[] i32[] i32[] i64[] i64[] i64 i64 i64 i64)
  primary = nk * np * 4
  base = primary + nl * np * 4
  v = 1
  while v <= nv
    yes = false
    if v <= primary
      a = v - 1
      yes = value[a / 4] == a % 4
    elsif v <= base
      yes = count[v - primary - 1] > 0
    elsif wkey[v] > 0
      yes = sign[wkey[v]] == 1 && sign[wlock[v]] == -1
    sign[v] = yes ? 1 : -1
    phases[v - 1] = yes ? v : 0 - v
    v += 1
  l = 0
  while l < nl
    k = 0
    while k < nk
      if allowed[l * nk + k] == 0 && dist[l * nk + k] > 0
        mutable[k] = 1
        a = 0
        while a < nk
          mutable[a] = 1 if allowed[l * nk + a] == 1
          a += 1
      k += 1
    l += 1
  0

-> wassat_keychart_prepare(plan, art, stop)
  # Construct the full arena before any race workers start. Search and phase
  # setup stay in the additional worker; baseline configurations are untouched.
  nv = plan["phases"].size
  solver = Wassat.from_flat(nv, art, 0)
  solver.enable_shrink
  solver.enable_chrono
  primary = plan["meta"][3]
  vars = i64[primary]
  i = 0
  while i < primary
    vars[i] = i + 1
    i += 1
  solver.set_primary_decision_vars(vars)
  solver.prepare_inprocessing
  solver.enable_fixed_caps
  solver.set_stop_cell(stop)
  plan["solver"] = solver
  0

-> wassat_keychart_search(plan, formula, stop)
  st = plan["state"]
  return [] if wassat_stop_requested?(stop)
  m = plan["meta"]
  nk = m[0]
  nl = m[1]
  np = m[2]
  t0 = ccall("__w_clock_ms")
  wassat_keychart_seed(plan["allowed"], plan["value"], plan["count"], plan["other"], plan["dist"], plan["weight"], st, nk, nl, np)
  wassat_keychart_walk(plan["allowed"], plan["value"], plan["count"], plan["other"], plan["dist"], plan["weight"], st, nk, nl, np, 4, 1, 20000, stop)
  st[13] = ccall("__w_clock_ms") - t0
  return [] if wassat_stop_requested?(stop) || st[2] > 2
  phases = plan["phases"]
  mutable = plan["mutable"]
  wassat_keychart_phases(plan["value"], plan["count"], plan["allowed"], plan["dist"], mutable, plan["wkey"], plan["wlock"], phases, plan["sign"], nk, nl, np, formula["nvars"])
  # A zero structural cost is still only a candidate for the original CNF.
  if st[2] == 0 && wassat_model_satisfies?(formula, phases)
    st[15] = 1
    return phases
  solver = plan["solver"]
  solver.set_phases(phases)
  assumptions = plan["assumptions"]
  t0 = ccall("__w_clock_ms")
  while st[10] < 100 && st[11] < 50000 && !wassat_stop_requested?(stop)
    assumptions.clear
    i = 0
    while i < m[3]
      l = phases[i]
      assumptions.push(l) if l > 0 && mutable[i / (np * 4)] == 0
      i += 1
    cap = 50000 - st[11]
    cap = 5000 if cap > 5000
    r = solver.solve_assuming_budget(assumptions, cap)
    delta = r["conflicts"] - st[11]
    st[11] = r["conflicts"]
    st[10] += 1
    st[14] = ccall("__w_clock_ms") - t0
    if r["sat"]
      if wassat_model_satisfies?(formula, r["model"])
        st[15] = 1
        return r["model"]
      return []
    elsif r["unsat"]
      core = r["core"]
      return [] if core.empty?
      added = 0
      ci = 0
      while ci < core.size
        v = core[ci].abs
        return [] if v < 1 || v > m[3]
        k = (v - 1) / (np * 4)
        if mutable[k] == 0
          mutable[k] = 1
          added += 1
        ci += 1
      st[12] += added
      return [] if added == 0
    elsif delta == 0
      return []
  []

-> wassat_keychart_arm(plan, formula, stop, res, base, nv)
  res[base + nv + 6] = ccall("__w_clock_ms")
  model = wassat_keychart_search(plan, formula, stop)
  st = plan["state"]
  st[9] = 1 if model.empty? && wassat_stop_requested?(stop)
  res[base + nv + 4] = st[11]
  res[base + nv + 5] = ccall("__w_clock_ms")
  if model.size == nv
    v = 1
    while v <= nv
      res[base + v] = model[v - 1] > 0 ? 1 : 0
      v += 1
    res[base] = 1
    z = wassat_stop_publish(stop, 1)
  0
