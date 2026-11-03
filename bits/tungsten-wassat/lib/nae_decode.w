# Recover complementary arithmetic clauses from the actual input. No known
# Ramsey/Van der Waerden number, instance identity or saved answer is used.
use nae_count
use monochrome_watch

WASSAT_NAE_MAX_VARS = 700
WASSAT_NAE_MAX_CLAUSES = 200000
WASSAT_NAE_MAX_LITERALS = 2000000
WASSAT_NAE_NODE_CAP = 2000000
WASSAT_NAE_WALL_MS = 20000

-> wassat_nae_prefix(lits, offs, lens, nv, nc) (i64[] i64[] i64[] i64 i64) i64
  return 0 if nc < 1 || offs.size < nc || lens.size < nc
  limit = nc < 256 ? nc : 256
  ci = 0
  while ci < limit
    index = ci < 128 ? ci : nc - limit + ci
    n = lens[index]
    off = offs[index]
    return 0 if n < 3 || n > 28 || off < 0 || off > lits.size || n > lits.size - off
    sign = lits[off] > 0 ? 1 : -1
    j = 0
    while j < n
      v = sign * lits[off + j]
      return 0 if v < 1 || v > nv
      j += 1
    ci += 1
  1

-> wassat_nae_bytes(nv, nc, nl) (i64 i64 i64) i64
  4194304 + 65 * nc + 20 * nl + 88 * nv

-> wassat_nae_plan(formula, workers, cdcl, sls, pre, extra)
  mode = env("WASSAT_NAE_COUNT")
  return nil if mode == "0" || formula == nil
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  return nil if wassat_race_round1_conflicts != 0
  return nil if System.cpu_count <= workers || System.physical_memory_bytes <= 0
  nv = formula["nvars"]; nc = formula["flat_ncl"]; nl = formula["flat_nlits"]
  return nil if nv < 3 || nv > WASSAT_NAE_MAX_VARS || nc < 1 || nc > WASSAT_NAE_MAX_CLAUSES
  return nil if nl < 1 || nl > WASSAT_NAE_MAX_LITERALS
  return nil if mode != "1" && (nv < 64 || nc < 64)
  return nil if wassat_nae_prefix(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nv, nc) == 0
  bytes = wassat_nae_bytes(nv, nc, nl)
  return nil if bytes > System.physical_memory_bytes / 64
  return nil unless wassat_race_memory_fits?(formula, cdcl, sls, pre, extra + bytes)
  { "meta": i64[32], "scratch": bytes, "watch_meta": i64[32] }

# Each unique sorted scope must occur in both polarities. Hashes only select
# candidates: equality compares every element. Duplicate clauses are harmless.
# Validated spans, bounds, distinctness and AP shape precede every acceptance.
-> wassat_nae_decode(lits, offs, lens, nv, nc, rows, elems, widths, masks,
                     slots, scratch, remain, m, stop) (i64[] i64[] i64[] i64 i64 i32[] i32[] i8[] i8[] i32[] i32[] i32[] i64[] i64[]) i64
  return 0 if offs.size < nc || lens.size < nc
  ns = 0 ## i64
  used = 0 ## i64
  ci = 0 ## i64
  mask = slots.size - 1 ## i64
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_nae_poll(m, stop) != 0
    n = lens[ci] ## i64
    off = offs[ci] ## i64
    return 0 if n < 3 || n > 28 || off < 0 || off > lits.size || n > lits.size - off
    sign = lits[off] > 0 ? 1 : -1 ## i64
    j = 0 ## i64
    while j < n
      v = sign * lits[off + j] - 1 ## i64
      return 0 if v < 0 || v >= nv
      scratch[j] = v
      j += 1
    j = 1
    while j < n
      v = scratch[j]
      k = j ## i64
      while k > 0 && scratch[k - 1] > v
        scratch[k] = scratch[k - 1]
        k -= 1
      scratch[k] = v
      j += 1
    delta = scratch[1] - scratch[0] ## i64
    return 0 if delta <= 0
    hash = n ## i64
    j = 0
    while j < n
      return 0 if j > 0 && scratch[j] - scratch[j - 1] != delta
      hash = ((hash * 1000003) ^ scratch[j]) & 2147483647
      j += 1
    slot = hash & mask ## i64
    found = -1 ## i64
    while slots[slot] != 0 && found < 0
      m[19] += 1
      return 0 if (m[19] & 4095) == 0 && wassat_nae_poll(m, stop) != 0
      candidate = slots[slot] - 1 ## i64
      if widths[candidate] == n
        equal = 1 ## i64
        j = 0
        while j < n && equal == 1
          m[20] += 1
          equal = 0 if elems[rows[candidate] + j] != scratch[j]
          j += 1
        found = candidate if equal == 1
      slot = (slot + 1) & mask if found < 0
    if found < 0
      return 0 if ns >= widths.size || ns + 1 >= rows.size || used > elems.size || n > elems.size - used
      found = ns
      slots[slot] = ns + 1
      rows[ns] = used
      widths[ns] = n
      j = 0
      while j < n
        v = scratch[j]
        elems[used] = v
        remain[ns] ^= v
        used += 1
        j += 1
      ns += 1
      rows[ns] = used
    bit = sign > 0 ? 1 : 2 ## i64
    masks[found] |= bit
    m[16] += 1
    ci += 1
  si = 0 ## i64
  while si < ns
    return 0 if (si & 255) == 0 && wassat_nae_poll(m, stop) != 0
    return 0 if masks[si] != 3
    si += 1
  m[14] = ns
  m[15] = used
  ns

-> wassat_nae_incidence(rows, elems, ns, nv, heads, inc, fill, order, asg, m, stop) (i32[] i32[] i64 i64 i32[] i32[] i32[] i32[] i8[] i64[] i64[]) i64
  si = 0 ## i64
  while si < ns
    return 0 if (si & 255) == 0 && wassat_nae_poll(m, stop) != 0
    j = rows[si] ## i64
    while j < rows[si + 1]
      heads[elems[j] + 1] += 1
      j += 1
    si += 1
  v = 0 ## i64
  while v < nv
    heads[v + 1] += heads[v]
    order[v] = v
    asg[v] = -1
    v += 1
  si = 0
  while si < ns
    return 0 if (si & 255) == 0 && wassat_nae_poll(m, stop) != 0
    j = rows[si]
    while j < rows[si + 1]
      v = elems[j]
      inc[heads[v] + fill[v]] = si
      fill[v] += 1
      j += 1
    si += 1
  i = 0 ## i64
  while i < nv
    return 0 if (i & 15) == 0 && wassat_nae_poll(m, stop) != 0
    best = i ## i64
    j = i + 1
    while j < nv
      best = j if fill[order[j]] > fill[order[best]]
      j += 1
    tmp = order[i] ## i64
    order[i] = order[best]
    order[best] = tmp
    i += 1
  1

-> wassat_nae_verify(lits, offs, lens, nc, asg, m, stop) (i64[] i64[] i64[] i64 i8[] i64[] i64[]) i64
  ci = 0 ## i64
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_nae_poll(m, stop) != 0
    good = 0 ## i64
    j = 0 ## i64
    while j < lens[ci]
      lit = lits[offs[ci] + j] ## i64
      v = lit > 0 ? lit - 1 : -lit - 1 ## i64
      good = 1 if (lit > 0 && asg[v] == 1) || (lit < 0 && asg[v] == 0)
      j += 1
    return 0 if good == 0
    ci += 1
  m[21] = 1
  1

# The decoder has established exact complementary scopes. Preserve that
# guard and degree order; the watched backend searches the original clauses.
# Scratch is fixed, and the plan includes both retained decoder arrays and
# this representation. No known extremal number or saved answer is used.
-> wassat_nae_watch(formula, asg, order, wm, m, stop)
  nv = formula["nvars"]; nc = formula["flat_ncl"]; nl = formula["flat_nlits"]
  lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
  return 0 if wassat_nae_poll(m, stop) != 0
  woff = i64[nc + 1]; wel = i64[nl]; forbid = i8[nc]
  word = i64[nv]; wtrail = i64[nv + 1]
  i = 0
  while i < nv
    word[i] = order[i]
    i += 1
  ci = 0
  used = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_nae_poll(m, stop) != 0
    woff[ci] = used
    forbid[ci] = lits[offs[ci]] > 0 ? 0 : 1
    j = 0
    while j < lens[ci]
      l = lits[offs[ci] + j]
      wel[used] = (l > 0 ? l : -l) - 1
      used += 1
      j += 1
    ci += 1
  woff[nc] = used
  wassat_mwatch_run(asg, woff, wel, forbid, word, wtrail,
    nv, nc, WASSAT_NAE_NODE_CAP, m[4], 1, wm, stop)

-> wassat_nae_search(formula, plan, stop, res, base)
  nv = formula["nvars"]; nc = formula["flat_ncl"]; nl = formula["flat_nlits"]
  lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
  m = plan["meta"]
  m[17] = clock_ms()
  m[4] = m[17] + WASSAT_NAE_WALL_MS
  m[3] = WASSAT_NAE_NODE_CAP
  m[9] = 32768
  m[24] = plan["scratch"]
  size = 1
  while size < 2 * nc
    size *= 2
  rows = i32[nc + 1]; elems = i32[nl]; widths = i8[nc]
  masks = i8[nc]; slots = i32[size]; scratch = i32[28]
  remain = i32[nc]; counts = i8[2 * nc]
  heads = i32[nv + 1]; inc = i32[nl]; fill = i32[nv]
  order = i32[nv]; asg = i8[nv]; trail = i32[nv + 1]
  hit = 0
  ns = wassat_nae_decode(lits, offs, lens, nv, nc, rows, elems,
    widths, masks, slots, scratch, remain, m, stop)
  if ns > 0 && wassat_nae_incidence(rows, elems, ns, nv, heads, inc, fill, order, asg, m, stop) == 1
    m[22] = clock_ms() - m[17]
    # Exact complementary scopes justify fixing the first color: every model
    # has its globally complemented model. No other symmetry is assumed.
    if env("WASSAT_ARITH_WATCH") != "0"
      wm = plan["watch_meta"]
      if wm == nil
        wm = i64[32]
        plan["watch_meta"] = wm
      hit = wassat_nae_watch(formula, asg, order, wm, m, stop)
      i = 0
      while i < 14
        m[i] = wm[i] if i != 3 && i != 4 && i != 8
        i += 1
      m[8] += wm[8]
    else
      seed = wassat_nae_propagate(asg, trail, heads, inc, widths, counts, remain, m, stop, (order[0] ## i64), 0)
      if seed == 1
        hit = wassat_nae_dfs(asg, trail, heads, inc, widths, counts, remain, order, m, stop, nv)
      elsif m[5] == 0
        hit = -1
    if hit == 1
      if wassat_nae_verify(lits, offs, lens, nc, asg, m, stop) == 1
        v = 1
        while v <= nv
          res[base + v] = asg[v - 1]
          v += 1
      else
        hit = 0
  hit = 0 if wassat_nae_poll(m, stop) != 0
  m[18] = clock_ms()
  res[base + nv + 6] = m[17]
  res[base + nv + 5] = m[18]
  if hit != 0
    m[23] = hit
    z = ccall("__w_arr_store_rel", res, base, hit)
    won = wassat_stop_publish(stop, hit)
  hit

-> wassat_nae_start(formula, plan, stop, res, base)
  Thread.new -> wassat_nae_search(formula, plan, stop, res, base)

-> wassat_nae_profile(plan, status)
  m = plan["meta"]
  wm = plan["watch_meta"]
  backend = "count"
  if wm != nil && wm[14] > 0
    backend = "watch"
    wassat_prof_note("race.nae_watch nodes=[wm[2]] visits=[wm[6]] reads=[wm[19]] moves=[wm[20]] safe=[wm[21]] undone=[wm[10]] branches=[wm[12]] conflicts=[wm[13]] stop=[wm[5]]")
  wassat_prof_note("race.nae status=[status] backend=[backend] scopes=[m[14]] clauses=[m[16]] nodes=[m[2]] visits=[m[6]] forces=[m[7]] undo_visits=[m[10]] enqueues=[m[11]] branches=[m[12]] conflicts=[m[13]] stop=[m[5]] polls=[m[8]] hash_probes=[m[19]] compared=[m[20]] verified=[m[21]] decode_ms=[m[22]] ms=[m[18] - m[17]] extra_bytes=[m[24]]")
