# Congruence of small Boolean functions recovered from original CNF clauses.
# This decoder accepts contiguous gate outputs and consecutive defining clause
# groups, with arbitrary dependency order. Every group is checked exhaustively
# for a unique output on EVERY local input. Incomplete groups and cycles miss.
# Normalized functions only prove equalities/constants. A refutation requires
# an original residual clause whose literals are all proved false. Never SAT.
use atomic_stop

# m: 0 result,1 gates,2 nodes,3 merges,4 constants,5 scheduled,6 decoded clauses,
# 7 truth-literal visits,8 hash probes,9 residual clauses,10 removed inputs,
# 11 stop (1 cancel,2 deadline,3 work),12 polls,13 dependency visits,14 ms.
-> wassat_lut_abs(x) (i64) i64
  x < 0 ? 0 - x : x

-> wassat_lut_stop(m, stop, deadline) (i64[] i64[] i64) i64
  m[12] += 1
  if wassat_stop_load(stop) != 0
    m[11] = 1
  elsif deadline > 0 && clock_ms() >= deadline
    m[11] = 2
  elsif m[7] > 64000000
    m[11] = 3
  m[11]

# Return 0 for a miss; otherwise return the first residual clause plus one.
# program: arity, four inputs, truth table, start clause, end clause.
-> wassat_lut_decode(lits, offs, lens, nv, nc, first, program, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64) i64
  ci = 0 ## i64
  out = first ## i64
  while out <= nv
    return 0 if wassat_lut_stop(m, stop, deadline) != 0
    start = ci ## i64
    base = out * 8 ## i64
    nf = 0 ## i64
    full = 0 ## i64
    while full == 0
      return 0 if ci >= nc || ci - start >= 32
      n = lens[ci] ## i64
      off = offs[ci] ## i64
      return 0 if n < 1 || n > 5 || off < 0 || off + n > lits.size
      found = 0 ## i64
      j = 0 ## i64
      while j < n
        v = wassat_lut_abs(lits[off + j]) ## i64
        return 0 if v < 1 || v > nv
        if v == out
          found = 1
        else
          k = 0 ## i64
          while k < nf && program[base + 1 + k] != v
            k += 1
          if k == nf
            return 0 if nf == 4
            program[base + 1 + nf] = v
            nf += 1
        j += 1
      return 0 if found == 0
      ci += 1
      # At most 32 local assignments. This proves the entire implication,
      # not merely the assignments reachable in the current search state.
      table = 0 ## i64
      full = 1
      mask = 0 ## i64
      while mask < (1 << nf) && full == 1
        allowed = 0 ## i64
        value = 0 ## i64
        bit = 0 ## i64
        while bit < 2
          ok = 1 ## i64
          c = start ## i64
          while c < ci && ok == 1
            hit = 0 ## i64
            j = 0
            while j < lens[c]
              lit = lits[offs[c] + j] ## i64
              v = wassat_lut_abs(lit)
              b = bit ## i64
              if v != out
                k = 0
                while k < nf && program[base + 1 + k] != v
                  k += 1
                return 0 if k == nf
                b = (mask >> k) & 1
              hit = 1 if (lit > 0 && b == 1) || (lit < 0 && b == 0)
              m[7] += 1
              j += 1
            ok = 0 if hit == 0
            c += 1
          if ok == 1
            allowed += 1; value = bit
          bit += 1
        return 0 if allowed == 0
        full = 0 if allowed != 1
        table |= value << mask
        mask += 1
      if full == 1
        program[base] = nf
        program[base + 5] = table
        program[base + 6] = start
        program[base + 7] = ci
    m[1] += 1; m[6] = ci
    out += 1
  ci + 1

# Fixed scratch and exact collision checks. Node 1 is TRUE; signed node IDs
# represent complementation. A new function is keyed by sorted independent
# input IDs and its truth table, normalized to be false at assignment zero.
-> wassat_lut_normalize(program, out, values, keys, slots, mask, scratch, m, nextid) (i64[] i64 i64[] i64[] i64[] i64 i64[] i64[] i64) i64
  base = 8 * out ## i64
  nf = program[base] ## i64
  ni = 0 ## i64
  j = 0 ## i64
  while j < nf
    v = values[program[base + 1 + j]] ## i64
    return 0 if v == 0
    scratch[j] = v
    x = wassat_lut_abs(v) ## i64
    if x > 1
      k = 0 ## i64
      while k < ni && scratch[4 + k] != x
        k += 1
      if k == ni
        scratch[4 + ni] = x; ni += 1
    j += 1
  j = 1
  while j < ni
    x = scratch[4 + j]
    k = j - 1
    while k >= 0 && scratch[4 + k] > x
      scratch[5 + k] = scratch[4 + k]; k -= 1
    scratch[5 + k] = x; j += 1
  table = 0 ## i64
  a = 0 ## i64
  while a < (1 << ni)
    original = 0 ## i64
    j = 0
    while j < nf
      x = wassat_lut_abs(scratch[j])
      bit = 1 ## i64
      if x > 1
        k = 0
        while k < ni && scratch[4 + k] != x
          k += 1
        return 0 if k == ni
        bit = (a >> k) & 1
      bit = 1 - bit if scratch[j] < 0
      original |= bit << j
      j += 1
    table |= ((program[base + 5] >> original) & 1) << a
    a += 1
  j = ni - 1
  while j >= 0
    same = 1 ## i64
    a = 0
    while a < (1 << ni) && same == 1
      same = 0 if ((table >> a) & 1) != ((table >> (a ^ (1 << j))) & 1)
      a += 1
    if same == 1
      smaller = 0 ## i64
      a = 0
      while a < (1 << (ni - 1))
        old = (a & ((1 << j) - 1)) | ((a >> j) << (j + 1)) ## i64
        smaller |= ((table >> old) & 1) << a
        a += 1
      table = smaller
      k = j
      while k + 1 < ni
        scratch[4 + k] = scratch[5 + k]; k += 1
      ni -= 1; m[10] += 1
    j -= 1
  if ni == 0
    m[4] += 1
    return table == 0 ? -1 : 1
  if ni == 1
    m[3] += 1
    return table == 2 ? scratch[4] : 0 - scratch[4]
  sign = (table & 1) == 1 ? -1 : 1 ## i64
  table ^= (1 << (1 << ni)) - 1 if sign < 0
  j = ni
  while j < 4
    scratch[4 + j] = 0; j += 1
  hash = table ## i64
  j = 0
  while j < 4
    hash = ((hash * 48271) ^ scratch[4 + j]) & mask; j += 1
  probes = 0 ## i64
  while slots[hash] != 0
    m[8] += 1
    id = slots[hash] ## i64
    same = keys[6 * id] == ni && keys[6 * id + 5] == table ? 1 : 0 ## i64
    j = 0
    while j < 4 && same == 1
      same = 0 if keys[6 * id + j + 1] != scratch[4 + j]
      j += 1
    if same == 1
      m[3] += 1
      return sign * id
    probes += 1
    return 0 if probes >= 256
    hash = (hash + 1) & mask
  m[8] += 1; m[2] += 1
  slots[hash] = nextid
  keys[6 * nextid] = ni; keys[6 * nextid + 5] = table
  j = 0
  while j < 4
    keys[6 * nextid + 1 + j] = scratch[4 + j]; j += 1
  sign * nextid

-> wassat_lut_refute(formula, m, stop, deadline = 0)
  started = clock_ms()
  return 0 if wassat_lut_stop(m, stop, deadline) != 0
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  return 0 if nv < 2 || nv > 100000 || nc < 2 || nc > 1000000
  lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
  return 0 if offs.size < nc || lens.size < nc || lens[0] < 1 || lens[0] > 5
  return 0 if offs[0] < 0 || offs[0] + lens[0] > lits.size
  first = nv + 1
  j = 0
  while j < lens[0]
    x = wassat_lut_abs(lits[offs[0] + j])
    first = x if x < first
    j += 1
  return 0 if first < 1 || first > nv
  program = i64[8 * (nv + 1)]
  end = wassat_lut_decode(lits, offs, lens, nv, nc, first, program, m, stop, deadline)
  return 0 if end == 0
  # A work queue schedules gates only after every dependency is known.
  values = i64[nv + 1]; head = i64[nv + 1]; links = i64[4 * (nv + 1)]
  waiting = i64[nv + 1]; queue = i64[nv + 1]
  v = 0
  while v <= nv
    head[v] = -1
    values[v] = v + 1 if v > 0 && v < first
    v += 1
  tail = 0
  v = first
  while v <= nv
    return 0 if (v & 255) == 0 && wassat_lut_stop(m, stop, deadline) != 0
    j = 0
    while j < program[8 * v]
      x = program[8 * v + 1 + j]
      if x >= first
        waiting[v] += 1
        link = 4 * v + j
        links[link] = head[x]; head[x] = link
      j += 1
    if waiting[v] == 0
      queue[tail] = v; tail += 1
    v += 1
  cap = 1
  while cap < 2 * (nv + 1)
    cap *= 2
  slots = i64[cap]; keys = i64[6 * (nv + 2)]; scratch = i64[8]
  nextid = first + 1
  at = 0
  while at < tail
    return 0 if (at & 127) == 0 && wassat_lut_stop(m, stop, deadline) != 0
    v = queue[at]; at += 1
    oldnodes = m[2]
    val = wassat_lut_normalize(program, v, values, keys, slots, cap - 1, scratch, m, nextid)
    return 0 if val == 0
    nextid += 1 if m[2] > oldnodes
    values[v] = val; m[5] += 1
    link = head[v]
    while link >= 0
      out = link / 4
      waiting[out] -= 1; m[13] += 1
      if waiting[out] == 0
        queue[tail] = out; tail += 1
      link = links[link]
  return 0 if m[5] != m[1]
  ci = end - 1
  while ci < nc
    return 0 if wassat_lut_stop(m, stop, deadline) != 0
    off = offs[ci]; size = lens[ci]
    return 0 if off < 0 || size < 0 || off + size > lits.size
    allfalse = 1
    j = 0
    while j < size
      return 0 if (j & 1023) == 0 && wassat_lut_stop(m, stop, deadline) != 0
      lit = lits[off + j]; x = wassat_lut_abs(lit)
      return 0 if x < 1 || x > nv
      val = values[x]
      val = 0 - val if lit < 0
      allfalse = 0 if val != -1
      j += 1
    m[9] += 1
    if allfalse == 1
      m[0] = -1; m[14] = clock_ms() - started
      return -1
    ci += 1
  m[14] = clock_ms() - started
  0

-> wassat_lut_profile(m)
  wassat_prof_note("lut.congruence result=[m[0]] gates=[m[1]] nodes=[m[2]] merges=[m[3]] constants=[m[4]] scheduled=[m[5]] decoded=[m[6]] truth_visits=[m[7]] hash_probes=[m[8]] assertions=[m[9]] removed_inputs=[m[10]] stopped=[m[11]] polls=[m[12]] dependencies=[m[13]] ms=[m[14]]")

# Constant-size admission for an ordered miter prefix: four clauses over the
# same three variables. Complete gate validation remains inside the worker.
-> wassat_lut_plan(formula, workers, cdcl, sls)
  mode = env("WASSAT_LUT_CONGRUENCE")
  return nil if mode == "0" || System.cpu_count <= workers
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  return nil if wassat_race_round1_conflicts != 0
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  return nil if nv < 2 || nv > 100000 || nc < 5 || nc > 1000000
  return nil if mode != "1" && nv < 1000
  lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
  return nil if lens.size < nc || offs.size < nc || lens[nc - 1] < 2
  return nil if lens[0] != 3 || offs[0] < 0 || offs[0] + 3 > lits.size
  a = wassat_lut_abs(lits[offs[0]]); b = wassat_lut_abs(lits[offs[0] + 1]); c = wassat_lut_abs(lits[offs[0] + 2])
  return nil if a == b || a == c || b == c
  ci = 1
  while ci < 4
    return nil if lens[ci] != 3 || offs[ci] < 0 || offs[ci] + 3 > lits.size
    j = 0
    while j < 3
      x = wassat_lut_abs(lits[offs[ci] + j])
      return nil unless x == a || x == b || x == c
      j += 1
    ci += 1
  return nil unless wassat_race_memory_fits?(formula, cdcl, sls, 1, 256 * (nv + 2) + 65536)
  i64[16]

-> wassat_lut_run(formula, m, stop, res)
  nv = formula["nvars"]
  started = clock_ms()
  res[nv + 6] = started
  status = wassat_lut_refute(formula, m, stop, started + 2000)
  m[14] = clock_ms() - started
  res[nv + 5] = clock_ms()
  return 0 if status != -1 || wassat_lut_stop(m, stop, started + 2000) != 0
  z = ccall("__w_arr_store_rel", res, 0, -1)
  won = wassat_stop_publish(stop, -1)
  -1
