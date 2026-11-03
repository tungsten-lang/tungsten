use decoder

-> wassat_counter_cover_rand(state, limit) (i64[] i64) i64
  state[3] = (state[3] * 48271) % 2147483647
  state[3] % limit

# Fixed-size swap buffers. Only rows touched by a changed selection update
# counts, exclusive-cover losses, and uncovered-cover gains.
-> wassat_counter_cover_move(v, adding, co, cr, row_offs, rv, counts, owners, weights, gain, loss, bad, bpos, selected, spos, age, removed, state, m, stop) (i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  if adding == 1
    spos[v] = state[0]; selected[state[0]] = v; state[0] += 1; age[v] = state[2]
  else
    state[0] -= 1; z = selected[state[0]]; p = spos[v]; selected[p] = z; spos[z] = p; spos[v] = -1; removed[v] = state[2]
  at = co[v]
  while at < co[v + 1]
    r = cr[at]; w = weights[r]
    if adding == 1
      if counts[r] == 0
        state[1] -= 1; z = bad[state[1]]; p = bpos[r]; bad[p] = z; bpos[z] = p; bpos[r] = -1
        j = row_offs[r]
        while j < row_offs[r + 1]
          gain[rv[j]] -= w; j += 1
        m[27] += row_offs[r + 1] - row_offs[r]
        loss[v] += w
      elsif counts[r] == 1
        loss[owners[r] - 1] -= w
      counts[r] += 1; owners[r] ^= v + 1
    else
      counts[r] -= 1; owners[r] ^= v + 1
      if counts[r] == 0
        bpos[r] = state[1]; bad[state[1]] = r; state[1] += 1
        j = row_offs[r]
        while j < row_offs[r + 1]
          gain[rv[j]] += w; j += 1
        m[27] += row_offs[r + 1] - row_offs[r]
        loss[v] -= w
      elsif counts[r] == 1
        loss[owners[r] - 1] += w
    m[23] += row_offs[r + 1] - row_offs[r]; m[28] += 1; at += 1
    if m[23] >= m[24]
      m[24] = m[23] + 4096
      return 1 if wassat_counter_cover_poll(m, stop) != 0
  0

-> wassat_counter_cover_walk(row_offs, rv, n, nr, terms, k, selected, m, stop, seed) (i64[] i64[] i64 i64 i64 i64 i64[] i64[] i64[] i64) i64
  co = i64[n + 1]; cr = i64[terms]; cursor = i64[n]; counts = i64[nr]; owners = i64[nr]; weights = i64[nr]
  gain = i64[n]; loss = i64[n]; bad = i64[nr]; bpos = i64[nr]; spos = i64[n]; age = i64[n]; removed = i64[n]; state = i64[4]
  state[3] = seed; m[21] = nr
  r = 0
  while r < nr
    return 0 if (r & 255) == 0 && wassat_counter_cover_poll(m, stop) != 0
    j = row_offs[r]
    while j < row_offs[r + 1]
      co[rv[j] + 1] += 1; j += 1
    r += 1
  v = 0
  while v < n
    co[v + 1] += co[v]; cursor[v] = co[v]; v += 1
  r = 0
  while r < nr
    j = row_offs[r]
    while j < row_offs[r + 1]
      v = rv[j]; cr[cursor[v]] = r; cursor[v] += 1; j += 1
    r += 1
  restart = 0
  while restart < 16
    return 0 if wassat_counter_cover_poll(m, stop) != 0
    m[22] += 1; state[0] = 0; state[1] = nr; v = 0
    while v < n
      gain[v] = co[v + 1] - co[v]; loss[v] = 0; spos[v] = -1; age[v] = -100; removed[v] = -100; v += 1
    r = 0
    while r < nr
      counts[r] = 0; owners[r] = 0; weights[r] = 1; bad[r] = r; bpos[r] = r; r += 1
    i = 0
    while i < k
      return 0 if wassat_counter_cover_poll(m, stop) != 0
      best = -1; pick = -1; ties = 0; v = 0
      while v < n
        if spos[v] < 0
          if gain[v] > best
            best = gain[v]; pick = v; ties = 1
          elsif gain[v] == best
            ties += 1; pick = v if wassat_counter_cover_rand(state, ties) == 0
        v += 1
      z = wassat_counter_cover_move(pick, 1, co, cr, row_offs, rv, counts, owners, weights, gain, loss, bad, bpos, selected, spos, age, removed, state, m, stop)
      return 0 if z != 0
      i += 1
    step = 0
    while step < 200000
      return 0 if (step & 63) == 0 && wassat_counter_cover_poll(m, stop) != 0
      m[21] = state[1] if state[1] < m[21]
      return 1 if state[1] == 0
      low = 1 ## i64
      low = low << 60; drop = -1; ties = 0; j = 0
      while j < k
        v = selected[j]
        if state[2] - age[v] >= 3
          if loss[v] < low
            low = loss[v]; drop = v; ties = 1
          elsif loss[v] == low
            ties += 1; drop = v if wassat_counter_cover_rand(state, ties) == 0
        j += 1
      drop = selected[wassat_counter_cover_rand(state, k)] if drop < 0 || wassat_counter_cover_rand(state, 100) < 2
      z = wassat_counter_cover_move(drop, 0, co, cr, row_offs, rv, counts, owners, weights, gain, loss, bad, bpos, selected, spos, age, removed, state, m, stop)
      return 0 if z != 0
      # Removing an item cannot create a full cover from an incomplete one.
      r = bad[wassat_counter_cover_rand(state, state[1])]; best = -1; pick = -1; ties = 0; j = row_offs[r]
      while j < row_offs[r + 1]
        v = rv[j]
        if spos[v] < 0 && removed[v] != state[2]
          if gain[v] > best
            best = gain[v]; pick = v; ties = 1
          elsif gain[v] == best
            ties += 1; pick = v if wassat_counter_cover_rand(state, ties) == 0
        j += 1
      pick = drop if pick < 0
      z = wassat_counter_cover_move(pick, 1, co, cr, row_offs, rv, counts, owners, weights, gain, loss, bad, bpos, selected, spos, age, removed, state, m, stop)
      return 0 if z != 0
      i = 0
      while i < state[1]
        r = bad[i]; weights[r] += 1; j = row_offs[r]
        while j < row_offs[r + 1]
          gain[rv[j]] += 1; j += 1
        m[23] += row_offs[r + 1] - row_offs[r]; m[27] += row_offs[r + 1] - row_offs[r]; i += 1
        if m[23] >= m[24]
          m[24] = m[23] + 4096
          return 0 if wassat_counter_cover_poll(m, stop) != 0
      step += 1; state[2] += 1; m[20] += 1
    m[21] = state[1] if state[1] < m[21]
    return 1 if state[1] == 0
    restart += 1
  0

-> wassat_counter_cover_model(formula, d, selected, m, stop)
  started = clock_ms(); nv = formula["nvars"]; values = i64[nv + 1]; inputs = d["inputs"]; i = 0
  while i < d["ninputs"]
    x = inputs[i]; values[wassat_counter_cover_abs(x)] = x > 0 ? -1 : 1; i += 1
  i = 0
  while i < d["target"]
    x = inputs[selected[i]]; values[wassat_counter_cover_abs(x)] = x > 0 ? 1 : -1; i += 1
  ops = d["steps"]; i = 0
  while i < d["nsteps"]
    return nil if (i & 255) == 0 && wassat_counter_cover_poll(m, stop) != 0
    total = 0; j = 0
    while j < ops[6 * i]
      x = ops[6 * i + 1 + j]
      return nil if values[wassat_counter_cover_abs(x)] == 0
      total += 1 if (x > 0) == (values[wassat_counter_cover_abs(x)] > 0); j += 1
    x = ops[6 * i + 4]; values[wassat_counter_cover_abs(x)] = ((total & 1) == 1) == (x > 0) ? 1 : -1
    x = ops[6 * i + 5]; values[wassat_counter_cover_abs(x)] = (total >= 2) == (x > 0) ? 1 : -1
    i += 1
  parent = d["parent"]; v = 1
  while v <= nv
    return nil if (v & 255) == 0 && wassat_counter_cover_poll(m, stop) != 0
    x = wassat_counter_cover_root(v, parent)
    values[wassat_counter_cover_abs(x)] = -1 if values[wassat_counter_cover_abs(x)] == 0
    values[v] = x > 0 ? values[wassat_counter_cover_abs(x)] : 0 - values[wassat_counter_cover_abs(x)]; v += 1
  lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]; ci = 0
  while ci < formula["flat_ncl"]
    return nil if (ci & 255) == 0 && wassat_counter_cover_poll(m, stop) != 0
    j = 0; satisfied = false
    while j < lens[ci] && !satisfied
      x = lits[offs[ci] + j]; satisfied = (x > 0) == (values[wassat_counter_cover_abs(x)] > 0); j += 1
    return nil unless satisfied
    ci += 1; m[16] += 1
  m[15] = clock_ms() - started
  values

-> wassat_counter_cover_run(formula, m, stop, deadline = 0, seed = 1)
  return nil if m.size < 64 || stop.size < 2
  i = 0
  while i < 64
    m[i] = 0; i += 1
  return nil if seed < 1 || seed >= 2147483647
  started = clock_ms(); d = wassat_counter_cover_decode(formula, m, stop, deadline)
  return nil if d == nil
  selected = i64[d["ninputs"]]; t = clock_ms()
  hit = wassat_counter_cover_walk(d["rows"], d["terms"], d["ninputs"], d["nrows"], d["nterms"], d["target"], selected, m, stop, seed)
  m[14] = clock_ms() - t
  return nil if hit == 0
  model = wassat_counter_cover_model(formula, d, selected, m, stop)
  m[17] = model == nil ? 0 : 1; m[18] = clock_ms() - started
  model
