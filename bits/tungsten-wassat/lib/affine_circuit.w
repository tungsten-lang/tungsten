# Model-only circuit search: exact local parity relations restrict the
# primary choices, then packed simulation and original-CNF replay find SAT.
# A failed decode, inconsistent approximation, or exhausted search is UNKNOWN.
use model_circuit

# meta 0..11 share model_circuit counters; 12 rank, 13 free inputs,
# 14 useful relations, 15 affine gates, 16 batches, 17 scanned clauses,
# 18 phase, 19 decode ms, 20 affine ms, 21 search ms, 22 total ms.
-> wassat_affine_circuit_poll(m, stop, deadline) (i64[] i64[] i64) i64
  return 1 if wassat_model_circuit_stop(m, stop, deadline, 64000000) != 0
  if m[6] > 64000000 || m[17] > 64000000
    m[11] = 3
    return 1
  0

-> wassat_affine_circuit_primary(formula)
  return 0 if formula == nil || formula["flat_ncl"] == nil || formula["flat_ncl"] < 1
  nv = formula["nvars"]; nc = formula["flat_ncl"]; nl = formula["flat_nlits"]
  return 0 if nv < 1 || nv > 1000000 || nc > 4000000 || nl < 4 || nl > 16000000
  lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
  return 0 if lits == nil || offs == nil || lens == nil || offs.size < nc || lens.size < nc || lits.size < nl
  np = lens[0]; o = offs[0]
  return 0 if np < 4 || np > 60 || np >= nv || o < 0 || o > nl - np
  i = 0
  while i < np
    return 0 if lits[o + i] != -i - 1
    i += 1
  np

# An affine expression is a bit mask: bit 0 is its constant, bit i the
# coefficient of primary i. -1 means unknown, never a guessed zero.
-> wassat_affine_circuit_forms(prog, forms, np, nv, m, stop, deadline) (i32[] i64[] i64 i64 i64[] i64[] i64) i64
  v = 1
  while v <= np
    forms[v] = 1 << v; v += 1
  while v <= nv
    return 0 if (v & 1023) == 0 && wassat_affine_circuit_poll(m, stop, deadline) != 0
    q = 4 * v; a = prog[q] ## i64
    b = prog[q + 1] ## i64
    c = prog[q + 2] ## i64
    tt = prog[q + 3] ## i64
    x = forms[a]; y = forms[b]; z = forms[c]; f = -1
    if a == 0
      f = tt
    elsif b == 0
      f = x if tt == 2
      f = x ^ 1 if tt == 1 && x >= 0
      f = 0 if tt == 0
      f = 1 if tt == 3
    elsif c == 0
      if tt == 6 || tt == 9
        f = x ^ y if x >= 0 && y >= 0
        f = 0 if a == b
        f ^= 1 if f >= 0 && tt == 9
      elsif tt == 8
        if x == 0 || y == 0
          f = 0
        elsif x == 1
          f = y
        elsif y == 1 || a == b
          f = x
        elsif x >= 0 && y >= 0
          f = x if x == y
          f = 0 if (x ^ y) == 1
    elsif tt == 150 && x >= 0 && y >= 0 && z >= 0
      f = x ^ y ^ z
    elsif tt == 232 && x >= 0 && y >= 0 && z >= 0
      if x == y || x == z
        f = x
      elsif y == z
        f = y
      elsif (x ^ y) == 1
        f = z
      elsif (x ^ z) == 1
        f = y
      elsif (y ^ z) == 1
        f = x
    forms[v] = f
    m[15] += 1 if f >= 0
    v += 1
  1

-> wassat_affine_circuit_row(row, pivots, np, m) (i64 i64[] i64 i64[]) i64
  b = np
  while b > 0
    if ((row >> b) & 1) != 0
      if pivots[b] == 0
        pivots[b] = row; m[12] += 1
        return 1
      row ^= pivots[b]
    b -= 1
  row == 0 ? 1 : 0

# Match every forbidden tuple of a two- or three-variable XOR directly in
# the original clauses. Definitions whose affine XOR is already constant
# add no restriction on the primaries and can be skipped.
-> wassat_affine_circuit_rows(lits, offs, lens, head, links, forms, pivots, nc, np, m, stop, deadline) (i64[] i64[] i64[] i32[] i32[] i64[] i64[] i64 i64 i64[] i64[] i64) i64
  ci = 0
  while ci < nc
    return 0 if (ci & 1023) == 0 && wassat_affine_circuit_poll(m, stop, deadline) != 0
    n = lens[ci]; o = offs[ci]
    if n == 2 || n == 3
      a = lits[o]; a = -a if a < 0
      b = lits[o + 1]; b = -b if b < 0
      c = n == 3 ? lits[o + 2] : 0; c = -c if c < 0
      if a != b && a != c && b != c && forms[a] >= 0 && forms[b] >= 0 && forms[c] >= 0
        row = forms[a] ^ forms[b] ^ forms[c]
        if row >= 2
          mx = a > b ? a : b; mx = c if c > mx
          e = head[mx]; forbidden = 0
          while e > 0
            q = e - 1
            if lens[q] == n
              mask = 0; support = 0; j = 0
              while j < n
                l = lits[offs[q] + j]; x = l < 0 ? -l : l
                bit = x == a ? 1 : (x == b ? 2 : (x == c ? 4 : 0))
                support |= bit
                mask |= bit if l < 0
                j += 1
              if support == (n == 2 ? 3 : 7)
                forbidden |= 1 << mask
            m[4] += 1
            e = links[q]
          odd = n == 2 ? 6 : 150
          even = n == 2 ? 9 : 105
          if (forbidden & odd) == odd
            m[14] += 1
            return 0 if wassat_affine_circuit_row(row, pivots, np, m) == 0
          if (forbidden & even) == even
            m[14] += 1
            return 0 if wassat_affine_circuit_row(row ^ 1, pivots, np, m) == 0
    ci += 1
  1

-> wassat_affine_circuit_filter(lits, offs, lens, values, nc, alive, m, stop, deadline) (i64[] i64[] i64[] i64[] i64 i64 i64[] i64[] i64) i64
  ci = 0
  while ci < nc && alive != 0
    return 0 if (ci & 1023) == 0 && wassat_affine_circuit_poll(m, stop, deadline) != 0
    o = offs[ci]; n = lens[ci]; j = 0; sat = 0
    while j < n
      l = lits[o + j]
      sat |= l > 0 ? values[l] : (-1 ^ values[-l])
      j += 1
    alive &= sat
    m[17] += 1; ci += 1
  alive

-> wassat_affine_circuit_search(lits, offs, lens, prog, values, pivots, selected, np, nv, nc, m, stop, deadline) (i64[] i64[] i64[] i32[] i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64) i64
  free = i32[np]; nf = 0; v = 1
  while v <= np
    if pivots[v] == 0
      free[nf] = v; nf += 1
    v += 1
  m[13] = nf
  return 0 if nf > 12
  total = 1 << nf; batch = 0
  while batch < total
    return 0 if wassat_affine_circuit_poll(m, stop, deadline) != 0
    v = 1
    while v <= np
      values[v] = 0; v += 1
    lane = 0
    while lane < 64 && batch + lane < total
      x = 1; j = 0; index = batch + lane
      while j < nf
        x |= ((index >> j) & 1) << free[j]; j += 1
      v = 1
      while v <= np
        if pivots[v] != 0 && (popcount(x & pivots[v]) & 1) != 0
          x |= 1 << v
        values[v] |= ((x >> v) & 1) << lane
        v += 1
      lane += 1
    m[16] += 1; m[10] += lane
    return 0 if wassat_model_circuit_eval(prog, values, np, nv, m, stop, deadline, 64000000) == 0
    alive = lane == 64 ? -1 : (1 << lane) - 1
    alive = wassat_affine_circuit_filter(lits, offs, lens, values, nc, alive, m, stop, deadline)
    if alive != 0
      lane = 0
      while ((alive >> lane) & 1) == 0
        lane += 1
      v = 1
      while v <= nv
        return 0 if (v & 1023) == 0 && wassat_affine_circuit_poll(m, stop, deadline) != 0
        selected[v - 1] = ((values[v] >> lane) & 1) != 0 ? v : -v
        v += 1
      m[9] = nc
      return 1
    batch += 64
  0

# Keep the model API uniformly typed, including empty results.
# TODO(compiler): mixed ordinary/typed array return joins can select boxed
# Array#each storage for a native buffer (standalone model printer crash).
-> wassat_affine_circuit_model(formula, m, stop, deadline = 0)
  np = wassat_affine_circuit_primary(formula)
  return i64[0] if np == 0 || m.size < 32 || stop.size < 2
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  m[1] = np; m[18] = 1; start = clock_ms()
  return i64[0] if wassat_affine_circuit_poll(m, stop, deadline) != 0
  prog = i32[4 * (nv + 1)]; head = i32[nv + 1]; links = i32[nc]
  ok = wassat_model_circuit_build(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nv, nc, np, prog, head, links, m, stop, deadline, 64000000)
  m[19] = clock_ms() - start
  return i64[0] if ok == 0
  forms = i64[nv + 1]; pivots = i64[np + 1]
  m[18] = 2; start = clock_ms()
  return i64[0] if wassat_affine_circuit_forms(prog, forms, np, nv, m, stop, deadline) == 0
  return i64[0] if wassat_affine_circuit_rows(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], head, links, forms, pivots, nc, np, m, stop, deadline) == 0
  m[20] = clock_ms() - start
  values = i64[nv + 1]; selected = i64[nv]
  m[18] = 3; start = clock_ms()
  hit = wassat_affine_circuit_search(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], prog, values, pivots, selected, np, nv, nc, m, stop, deadline)
  m[21] = clock_ms() - start; m[0] = hit
  return i64[0] if hit == 0 || wassat_affine_circuit_poll(m, stop, deadline) != 0
  selected

-> wassat_affine_circuit_plan(formula, workers, cdcl, sls, pre, extra)
  mode = env("WASSAT_AFFINE_CIRCUIT")
  return nil if mode == "0" || formula == nil || formula["affine_circuit_done"] == true
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  return nil if wassat_race_round1_conflicts != 0
  return nil if System.cpu_count <= workers || System.physical_memory_bytes <= 0
  return nil if wassat_affine_circuit_primary(formula) == 0
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  # Includes the result slice, decoder scratch and every fixed search array.
  # No growth or per-candidate allocation in packed enumeration.
  bytes = 1048576 + 64 * (nv + 1) + 4 * nc
  return nil if bytes > System.physical_memory_bytes / 32
  estimate = wassat_cdcl_arena_bytes(formula) * cdcl + wassat_sls_arena_bytes(formula) * sls
  estimate += wassat_preprocess_arena_bytes(formula) * pre + extra + bytes
  memory = System.physical_memory_bytes ## i64
  ceiling = memory / 3; ceiling = 6442450944 if ceiling > 6442450944
  wassat_prof_note("race.affine_circuit_plan estimate=[estimate] ceiling=[ceiling] scratch=[bytes] existing_workers=[workers]")
  return nil if estimate > ceiling
  { "affine_circuit": true, "meta": i64[32], "scratch": bytes }

-> wassat_affine_circuit_arm(formula, plan, stop, res, base, nv)
  m = plan["meta"]; start = clock_ms()
  model = wassat_affine_circuit_model(formula, m, stop, start + 5000)
  m[22] = clock_ms() - start
  res[base + nv + 6] = start; res[base + nv + 5] = clock_ms()
  return 0 if model.size != nv || wassat_stop_load(stop) != 0 || clock_ms() >= start + 5000
  v = 1
  while v <= nv
    return 0 if (v & 1023) == 0 && wassat_affine_circuit_poll(m, stop, start + 5000) != 0
    res[base + v] = model[v - 1] > 0 ? 1 : -1; v += 1
  return 0 if wassat_stop_load(stop) != 0
  z = ccall("__w_arr_store_rel", res, base, 1)
  z = wassat_stop_publish(stop, 1)
  1

-> wassat_affine_circuit_finish_scout(formula, plan)
  m = plan["meta"]
  formula["affine_circuit_done"] = m[11] != 1 && m[0] != 1
  0

-> wassat_affine_circuit_profile(m, label = "race.affine_circuit")
  wassat_prof_note("[label] status=[m[0]] inputs=[m[1]] gates=[m[2]] decode_work=[m[4]] truth_candidates=[m[5]] gate_evals=[m[6]] verified_clauses=[m[9]] candidates=[m[10]] stop=[m[11]] rank=[m[12]] free=[m[13]] relations=[m[14]] affine_gates=[m[15]] batches=[m[16]] scanned_clauses=[m[17]] phase=[m[18]] decode_ms=[m[19]] affine_ms=[m[20]] search_ms=[m[21]] ms=[m[22]]")
