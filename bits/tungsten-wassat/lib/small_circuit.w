# Exact finite-domain evaluation of CNF-defined two-input circuits.
# Each short-clause group must define exactly one output for every input
# assignment. Numeric variable order is the topological order. Units and
# wider clauses are checked as assertions on every complete input assignment.
# No circuit shape, filename, expected answer, or stored model is assumed.

use atomic_stop

WASSAT_SMALL_CIRCUIT_MAX_WORK = 134217728

# meta: recognized, inputs, gates, assertions, assertion literals, batches,
# completed batches, gate evaluations, assertion literals checked, stop reason
# (1 cancellation, 2 work bound, 3 deadline), result (-1 refuted, 1 witness).
-> wassat_small_circuit_build(lits, offs, lens, nv, nc, program, inputs, assertions, meta, budget) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64) i64
  head = i64[nv + 1]
  next_clause = i64[nc]
  v = 0
  while v <= nv
    head[v] = -1
    v += 1
  ci = 0
  na = 0
  alits = 0
  while ci < nc
    n = lens[ci]
    if n == 1 || n > 3
      j = 0
      while j < n
        l = lits[offs[ci] + j]
        x = l < 0 ? 0 - l : l
        return 0 if x < 1 || x > nv
        j += 1
      assertions[na] = ci
      na += 1
      alits += n
    elsif n == 2 || n == 3
      mx = 0
      j = 0
      while j < n
        l = lits[offs[ci] + j]
        x = l < 0 ? 0 - l : l
        return 0 if x < 1 || x > nv
        mx = x if x > mx
        j += 1
      next_clause[ci] = head[mx]
      head[mx] = ci
    else
      return 0
    ci += 1
  return 0 if na == 0
  np = 0
  ng = 0
  v = 1
  while v <= nv
    if head[v] < 0
      return 0 if np >= 24
      inputs[np] = v
      np += 1
    else
      a = 0
      b = 0
      ci = head[v]
      while ci >= 0
        j = 0
        while j < lens[ci]
          l = lits[offs[ci] + j]
          x = l < 0 ? 0 - l : l
          if x != v && x != a && x != b
            if a == 0
              a = x
            elsif b == 0
              b = x
            else
              return 0
          j += 1
        ci = next_clause[ci]
      # Test all four local input assignments directly against ALL defining
      # clauses. Missing/ambiguous outputs reject the plan, never refute CNF.
      tt = 0
      mask = 0
      while mask < 4
        allowed = 0
        value = 0
        output = 0
        while output < 2
          ok = 1
          ci = head[v]
          while ci >= 0 && ok == 1
            sat = 0
            j = 0
            while j < lens[ci]
              l = lits[offs[ci] + j]
              x = l < 0 ? 0 - l : l
              bit = x == v ? output : (x == a ? (mask & 1) : ((mask >> 1) & 1))
              sat = 1 if (l > 0 && bit == 1) || (l < 0 && bit == 0)
              j += 1
            ok = 0 if sat == 0
            ci = next_clause[ci]
          if ok == 1
            allowed += 1
            value = output
          output += 1
        return 0 if allowed != 1
        tt = tt | (value << mask)
        mask += 1
      program[4 * ng] = v
      program[4 * ng + 1] = a
      program[4 * ng + 2] = b
      program[4 * ng + 3] = tt
      ng += 1
    v += 1
  return 0 if ng == 0
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

-> wassat_small_circuit_word(a, b, tt) (i64 i64 i64) i64
  return a & b if tt == 8
  return a ^ b if tt == 6
  return a | b if tt == 14
  return a & (-1 ^ b) if tt == 2
  return (-1 ^ a) & b if tt == 4
  return -1 ^ (a | b) if tt == 1
  return -1 ^ (a & b) if tt == 7
  return -1 ^ (a ^ b) if tt == 9
  lo = (b & (0 - ((tt >> 2) & 1))) | ((-1 ^ b) & (0 - (tt & 1)))
  hi = (b & (0 - ((tt >> 3) & 1))) | ((-1 ^ b) & (0 - ((tt >> 1) & 1)))
  (a & hi) | ((-1 ^ a) & lo)

# A result is published only after every batch completes. The shared stop is
# read-only here; the owning portfolio arm publishes a successful refutation.
-> wassat_small_circuit_eval(lits, offs, lens, program, inputs, assertions, meta, values, stop, deadline) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  np = meta[1]
  ng = meta[2]
  na = meta[3]
  batches = meta[5]
  i = 6
  while i <= 10
    meta[i] = 0
    i += 1
  masks = i64[6]
  masks[0] = -6148914691236517206 ## i64
  masks[1] = -3689348814741910324 ## i64
  masks[2] = -1085102592571150096 ## i64
  masks[3] = -71777214294589696 ## i64
  masks[4] = -281470681808896 ## i64
  masks[5] = -4294967296 ## i64
  batch = 0
  while batch < batches
    if wassat_stop_load(stop) != 0
      meta[9] = 1
      return 0
    if deadline > 0 && clock_ms() >= deadline
      meta[9] = 3
      return 0
    i = 0
    while i < np
      values[inputs[i]] = i < 6 ? masks[i] : (((batch >> (i - 6)) & 1) == 1 ? -1 : 0)
      i += 1
    g = 0
    while g < ng
      d = 4 * g
      values[program[d]] = wassat_small_circuit_word(values[program[d + 1]], values[program[d + 2]], program[d + 3])
      g += 1
    live = -1 ## i64
    ai = 0
    while ai < na && live != 0
      ci = assertions[ai]
      off = offs[ci]
      n = lens[ci]
      sat = 0 ## i64
      j = 0
      while j < n
        l = lits[off + j]
        x = l < 0 ? 0 - l : l
        sat = sat | (l < 0 ? (-1 ^ values[x]) : values[x])
        j += 1
      live = live & sat
      meta[8] += n
      ai += 1
    batch += 1
    meta[6] = batch
    meta[7] += ng
    if live != 0
      meta[10] = 1
      return 0
  meta[10] = -1
  1

-> wassat_small_circuit_plan(formula, budget = WASSAT_SMALL_CIRCUIT_MAX_WORK)
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return nil if nv < 1 || nv > 8192 || nc < 1 || nc > 32768
  program = i64[4 * nv]
  inputs = i64[24]
  assertions = i64[nc]
  meta = i64[12]
  ok = wassat_small_circuit_build(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nv, nc, program, inputs, assertions, meta, budget)
  return nil if ok == 0
  { "program": program, "inputs": inputs, "assertions": assertions,
    "meta": meta, "values": i64[nv + 1] }

-> wassat_small_circuit_run(formula, plan, stop, deadline = 0)
  return 0 if plan == nil
  wassat_small_circuit_eval(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], plan["program"], plan["inputs"], plan["assertions"], plan["meta"], plan["values"], stop, deadline)

# Native-only worker: safe while the coordinator scores other race arms.
-> wassat_small_circuit_arm(lits, offs, lens, program, inputs, assertions, meta, values, stop, res, base, nv) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64) i64
  res[base + nv + 6] = clock_ms()
  hit = wassat_small_circuit_eval(lits, offs, lens, program, inputs, assertions, meta, values, stop, 0)
  res[base + nv + 5] = clock_ms()
  if hit == 1
    z = ccall("__w_arr_store_rel", res, base, -1)
    won = wassat_stop_publish(stop, -1)
  hit
