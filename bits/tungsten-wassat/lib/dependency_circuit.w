# A bounded circuit backdoor found from original clauses, independent of
# variable numbering. Each scheduled equality, AND or XOR is justified by
# its complete CNF definition. Units seed constants; the smallest remaining
# variable becomes a free input only when dependency propagation stalls.
# Clauses not discharged by scheduled definitions remain assertions. Thus
# every CNF model occurs in the enumerated input space, including on cycles
# and overlapping definitions. Failure or a surviving assignment is UNKNOWN.
# Construction and enumeration both run in the existing parallel circuit arm.

use small_circuit

-> wassat_dep_lookup(a, b, c, n, keys, slots, mask, lens, meta) (i64 i64 i64 i64 i64[] i64[] i64 i64[] i64[]) i64
  if a > b
    t = a
    a = b
    b = t
  if n == 3
    if b > c
      t = b
      b = c
      c = t
    if a > b
      t = a
      a = b
      b = t
  h = ((a * 73856093) ^ (b * 19349663) ^ (c * 83492791)) & mask
  tries = 0
  while tries < 256
    meta[12] += 1
    ci = slots[h] - 1
    return 0 - 1 if ci < 0
    p = 3 * ci
    return ci if lens[ci] == n && keys[p] == a && keys[p + 1] == b && keys[p + 2] == c
    h = (h + 1) & mask
    tries += 1
  0 - 1

-> wassat_dep_stopped(stop, deadline, meta) (i64[] i64 i64[]) i64
  if wassat_stop_load(stop) != 0
    meta[9] = 1
    return 1
  if deadline > 0 && clock_ms() >= deadline
    meta[9] = 3
    return 1
  0

# A relation occupies eight words: kind, three signed operands, and up to
# four original clause indices. kind 1 is disequality of signed operands,
# 2 is signed output = AND(inputs), 3/4 is XOR parity zero/one.
-> wassat_dep_add(rows, nr, kind, a, b, c, c0, c1, c2, c3) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  p = 8 * nr
  rows[p] = kind
  rows[p + 1] = a
  rows[p + 2] = b
  rows[p + 3] = c
  rows[p + 4] = c0
  rows[p + 5] = c1
  rows[p + 6] = c2
  rows[p + 7] = c3
  nr + 1

-> wassat_dependency_circuit_build(lits, offs, lens, nv, nc, program, inputs, assertions, meta, stop, deadline, budget) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64 i64) i64
  mi = 0
  while mi < 17
    meta[mi] = 0 if mi != 11
    mi += 1
  return 0 if wassat_dep_stopped(stop, deadline, meta) != 0
  cap = 1
  while cap < 2 * nc
    cap *= 2
  mask = cap - 1
  keys = i64[3 * nc]
  slots = i64[cap]
  covered = i8[nc]
  known = i8[nv + 1]
  queue = i64[nv + 1]
  rows = i64[8 * nc]
  head = i64[nv + 1]
  links = i64[3 * nc]
  v = 0
  while v <= nv
    head[v] = -1
    v += 1
  ng = 0
  tail = 0
  ci = 0
  while ci < nc
    if (ci & 1023) == 0
      return 0 if wassat_dep_stopped(stop, deadline, meta) != 0
    n = lens[ci]
    p = offs[ci]
    j = 0
    while j < n
      if j > 0 && (j & 1023) == 0
        return 0 if wassat_dep_stopped(stop, deadline, meta) != 0
      l = lits[p + j]
      v = l < 0 ? 0 - l : l
      return 0 if v < 1 || v > nv
      j += 1
    if n == 1
      l = lits[p]
      v = l < 0 ? 0 - l : l
      if known[v] == 0
        known[v] = 1
        queue[tail] = v
        tail += 1
        program[4 * ng] = v
        program[4 * ng + 1] = 0
        program[4 * ng + 2] = 0
        program[4 * ng + 3] = l > 0 ? 15 : 0
        ng += 1
        covered[ci] = 1
    elsif n == 2 || n == 3
      a = lits[p]
      b = lits[p + 1]
      c = n == 3 ? lits[p + 2] : 0
      aa = a < 0 ? 0 - a : a
      ab = b < 0 ? 0 - b : b
      ac = c < 0 ? 0 - c : c
      if aa != ab && aa != ac && ab != ac
        if a > b
          t = a
          a = b
          b = t
        if n == 3
          if b > c
            t = b
            b = c
            c = t
          if a > b
            t = a
            a = b
            b = t
        keys[3 * ci] = a
        keys[3 * ci + 1] = b
        keys[3 * ci + 2] = c
        h = ((a * 73856093) ^ (b * 19349663) ^ (c * 83492791)) & mask
        tries = 0
        while slots[h] != 0
          old = slots[h] - 1
          if lens[old] == n && keys[3 * old] == a && keys[3 * old + 1] == b && keys[3 * old + 2] == c
            break
          tries += 1
          return 0 if tries >= 256
          h = (h + 1) & mask
        slots[h] = ci + 1 if slots[h] == 0
    meta[14] += 1
    ci += 1
  nr = 0
  ci = 0
  while ci < nc
    if (ci & 1023) == 0
      return 0 if wassat_dep_stopped(stop, deadline, meta) != 0
    n = lens[ci]
    if (n == 2 || n == 3) && keys[3 * ci] != 0
      a = keys[3 * ci]
      b = keys[3 * ci + 1]
      c = keys[3 * ci + 2]
      if n == 2
        other = wassat_dep_lookup(0 - a, 0 - b, 0, 2, keys, slots, mask, lens, meta)
        if other > ci
          return 0 if nr >= nc
          nr = wassat_dep_add(rows, nr, 1, a, b, 0, ci, other, -1, -1)
      else
        # Three pairwise sign flips complete one parity relation.
        x = wassat_dep_lookup(0 - a, 0 - b, c, 3, keys, slots, mask, lens, meta)
        y = wassat_dep_lookup(0 - a, b, 0 - c, 3, keys, slots, mask, lens, meta)
        z = wassat_dep_lookup(a, 0 - b, 0 - c, 3, keys, slots, mask, lens, meta)
        if x > ci && y > ci && z > ci
          return 0 if nr >= nc
          parity = (a > 0 ? 1 : 0) ^ (b > 0 ? 1 : 0) ^ (c > 0 ? 1 : 0)
          nr = wassat_dep_add(rows, nr, 3 + parity, a < 0 ? 0 - a : a, b < 0 ? 0 - b : b, c < 0 ? 0 - c : c, ci, x, y, z)
        j = 0
        while j < 3
          o = j == 0 ? a : (j == 1 ? b : c)
          u = j == 0 ? b : a
          w = j == 2 ? b : c
          x = wassat_dep_lookup(0 - o, 0 - u, 0, 2, keys, slots, mask, lens, meta)
          y = wassat_dep_lookup(0 - o, 0 - w, 0, 2, keys, slots, mask, lens, meta)
          if x >= 0 && y >= 0
            return 0 if nr >= nc
            nr = wassat_dep_add(rows, nr, 2, o, 0 - u, 0 - w, ci, x, y, -1)
          j += 1
    ci += 1
  meta[13] = nr
  r = 0
  while r < nr
    if (r & 1023) == 0
      return 0 if wassat_dep_stopped(stop, deadline, meta) != 0
    k = rows[8 * r] == 1 ? 2 : 3
    j = 0
    while j < k
      l = rows[8 * r + 1 + j]
      v = l < 0 ? 0 - l : l
      node = 3 * r + j
      links[node] = head[v]
      head[v] = node
      j += 1
    r += 1
  front = 0
  np = 0
  next_free = 1
  while true
    while front < tail
      if (front & 255) == 0
        return 0 if wassat_dep_stopped(stop, deadline, meta) != 0
      node = head[queue[front]]
      front += 1
      while node >= 0
        r = node / 3
        p = 8 * r
        kind = rows[p]
        k = kind == 1 ? 2 : 3
        unknown = 0
        o = 0
        a = 0
        b = 0
        j = 0
        while j < k
          l = rows[p + 1 + j]
          v = l < 0 ? 0 - l : l
          if known[v] == 0
            o = v
            unknown += 1
          elsif a == 0
            a = v
          else
            b = v
          j += 1
        raw_o = rows[p + 1]
        abs_o = raw_o < 0 ? 0 - raw_o : raw_o
        if unknown == 1 && (kind != 2 || o == abs_o)
          tt = 0
          if kind == 1
            tt = (rows[p + 1] < 0) == (rows[p + 2] < 0) ? 5 : 10
          elsif kind >= 3
            tt = kind == 3 ? 6 : 9
          else
            u = rows[p + 2]
            w = rows[p + 3]
            a = u < 0 ? 0 - u : u
            b = w < 0 ? 0 - w : w
            bits = 0
            while bits < 4
              av = (bits & 1) ^ (u < 0 ? 1 : 0)
              bv = ((bits >> 1) & 1) ^ (w < 0 ? 1 : 0)
              value = (av & bv) ^ (raw_o < 0 ? 1 : 0)
              tt = tt | (value << bits)
              bits += 1
          program[4 * ng] = o
          program[4 * ng + 1] = a
          program[4 * ng + 2] = b
          program[4 * ng + 3] = tt
          ng += 1
          known[o] = 1
          queue[tail] = o
          tail += 1
          j = 4
          while j < 8
            cidx = rows[p + j]
            covered[cidx] = 1 if cidx >= 0
            j += 1
        meta[15] += 1
        if (meta[15] & 1023) == 0
          return 0 if wassat_dep_stopped(stop, deadline, meta) != 0
        node = links[node]
    while next_free <= nv && known[next_free] != 0
      next_free += 1
    break if next_free > nv
    if np >= 20
      meta[9] = 2
      return 0
    inputs[np] = next_free
    np += 1
    known[next_free] = 1
    queue[tail] = next_free
    tail += 1
  na = 0
  alits = 0
  ci = 0
  while ci < nc
    if (ci & 1023) == 0
      return 0 if wassat_dep_stopped(stop, deadline, meta) != 0
    if covered[ci] == 0
      assertions[na] = ci
      na += 1
      alits += lens[ci]
    ci += 1
  batches = np <= 6 ? 1 : (1 << (np - 6))
  meta[1] = np
  meta[2] = ng
  meta[3] = na
  meta[4] = alits
  meta[5] = batches
  if batches * (ng + alits) > budget
    meta[9] = 2
    return 0
  meta[0] = 1
  1

# Only small fixed arrays are prepared on the coordinator. Hashing, gate
# recognition and dependency traversal happen alongside the solving arms.
-> wassat_dependency_circuit_plan(formula, budget = WASSAT_SMALL_CIRCUIT_MAX_WORK)
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return nil if nv < 1 || nv > 100000 || nc < 1 || nc > 400000
  literal_count = formula.has_key?("flat_nlits") ? formula["flat_nlits"] : formula["flat_lits"].size
  return nil if literal_count > 1600000
  meta = i64[20]
  meta[11] = 1
  meta[17] = budget
  meta[18] = nc
  { "program": i64[4 * nv], "inputs": i64[24], "assertions": i64[nc],
    "meta": meta, "values": i64[nv + 1], "dependency": true }

-> wassat_dependency_circuit_eval(lits, offs, lens, nv, program, inputs, assertions, meta, values, stop, deadline) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  start = clock_ms()
  build_deadline = start + 250
  build_deadline = deadline if deadline > 0 && deadline < build_deadline
  ok = wassat_dependency_circuit_build(lits, offs, lens, nv, meta[18], program, inputs, assertions, meta, stop, build_deadline, meta[17])
  meta[16] = clock_ms() - start
  return 0 if ok == 0
  wassat_small_circuit_eval(lits, offs, lens, program, inputs, assertions, meta, values, stop, deadline)

-> wassat_dependency_circuit_run(formula, plan, stop, deadline = 0)
  return 0 if plan == nil
  wassat_dependency_circuit_eval(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], formula["nvars"], plan["program"], plan["inputs"], plan["assertions"], plan["meta"], plan["values"], stop, deadline)

-> wassat_dependency_circuit_arm(lits, offs, lens, program, inputs, assertions, meta, values, stop, res, base, nv) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64) i64
  res[base + nv + 6] = clock_ms()
  hit = wassat_dependency_circuit_eval(lits, offs, lens, nv, program, inputs, assertions, meta, values, stop, 0)
  res[base + nv + 5] = clock_ms()
  if hit == 1
    z = ccall("__w_arr_store_rel", res, base, -1)
    won = wassat_stop_publish(stop, -1)
  hit

-> wassat_dependency_circuit_start(formula, plan, stop, res)
  lits = formula["flat_lits"]
  offs = formula["flat_offs"]
  lens = formula["flat_lens"]
  nv = formula["nvars"]
  program = plan["program"]
  inputs = plan["inputs"]
  assertions = plan["assertions"]
  meta = plan["meta"]
  values = plan["values"]
  Thread.new -> wassat_dependency_circuit_arm(lits, offs, lens, program, inputs, assertions, meta, values, stop, res, 0, nv)

-> wassat_dependency_circuit_profile(label, plan)
  m = plan["meta"]
  wassat_prof_note("[label] recognized=[m[0]] inputs=[m[1]] gates=[m[2]] batches=[m[6]]/[m[5]] gate_evaluations=[m[7]] assertion_literals=[m[8]] stopped=[m[9]] result=[m[10]] relations=[m[13]] hash_probes=[m[12]] clauses=[m[14]] dependency_visits=[m[15]] build_ms=[m[16]]")
