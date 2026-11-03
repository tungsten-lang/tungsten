use atomic_stop

# Exact finite refutation for CNF-defined signed AND and parity circuits.
# Units and complete gate definitions determine a bounded set of free inputs.
# Enumerate all assignments in 64-bit batches. Only exhaustive rejection is
# conclusive; a surviving assignment, unsupported shape or stop is UNKNOWN.
# No cipher identity, variable numbering pattern or stored witness is assumed.

WASSAT_WIDE_MAX_VARS = 4096
WASSAT_WIDE_MAX_CLAUSES = 65536
WASSAT_WIDE_MAX_WORK = 268435456
WASSAT_WIDE_MAX_PROBES = 4194304

# Includes returned arrays, temporary clause/row indices, a hash table whose
# capacity is less than 4*nc, and small descriptors. Actual large buffers use
# at most 250*nc + 90*nv bytes; reserve additional result/allocator headroom.
-> wassat_wide_bytes(nv, nc) (i64 i64) i64
  320 * (nv + nc + 1) + 65536

# Builder counters: 0 recognized, 1 XORs, 2 ANDs, 3 covered clauses,
# 4 instructions, 5 assertions, 6 units, 7 inputs, 8 work bound, 9 stop,
# 12 hash probes, 13 dependency visits, 14 stop polls.
-> wassat_wide_stopped(stop, deadline, m) (i64[] i64 i64[]) i64
  m[14] += 1
  if wassat_stop_load(stop) != 0
    m[9] = 1
    return 1
  if deadline > 0 && clock_ms() >= deadline
    m[9] = 3
    return 1
  0


-> wassat_wide_sort(q, n) (i64[] i64)
  i = (1) ## i64
  while i < n
    x = (q[i]) ## i64
    j = (i) ## i64
    while j > 0 && q[j - 1] > x
      q[j] = q[j - 1]
      j -= 1
    q[j] = x
    i += 1

-> wassat_wide_hash(q, off, n, mask) (i64[] i64 i64 i64) i64
  h = (n) ## i64
  j = (0) ## i64
  while j < n
    h = ((h * 1000003) ^ q[off + j]) & 2147483647
    j += 1
  h & mask

-> wassat_wide_lookup(q, n, keys, slots, lens, mask, m) (i64[] i64 i64[] i64[] i64[] i64 i64[]) i64
  h = (wassat_wide_hash(q, 0, n, mask)) ## i64
  tries = (0) ## i64
  while tries < 256
    m[12] += 1
    return -1 if m[12] > WASSAT_WIDE_MAX_PROBES
    ci = (slots[h] - 1) ## i64
    return -1 if ci < 0
    if lens[ci] == n
      j = (0) ## i64
      while j < n && keys[7 * ci + j] == q[j]
        j += 1
      return ci if j == n
    h = (h + 1) & mask
    tries += 1
  -1

# Every relation is checked against its complete original definition. All
# original clauses must be covered; unsupported clauses decline the plan.
-> wassat_wide_build(lits, offs, lens, nv, nc, program, check, free, values, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  return 0 if nv < 1 || nv > WASSAT_WIDE_MAX_VARS || nc < 1 || nc > WASSAT_WIDE_MAX_CLAUSES
  return 0 if offs.size < nc || lens.size < nc || program.size < 10 * nv || check.size < 10 * nc
  return 0 if free.size < 24 || values.size < nv + 1
  return 0 if wassat_wide_stopped(stop, deadline, m) != 0
  cap = (1) ## i64
  while cap < 2 * nc
    cap *= 2
  mask = (cap - 1) ## i64
  keys = i64[7 * nc]; slots = i64[cap]; covered = i8[nc]
  known = i8[nv + 1]; live = i8[nv + 1]
  rows = i64[10 * nc]; done = i8[nc]
  q = i64[7]; ids = i64[64]
  ci = (0) ## i64
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_wide_stopped(stop, deadline, m) != 0
    n = (lens[ci]) ## i64
    off = (offs[ci]) ## i64
    return 0 if n < 1 || n > 7 || off < 0 || off + n > lits.size
    j = (0) ## i64
    while j < n
      x = (lits[off + j]) ## i64
      v = (x < 0 ? -x : x) ## i64
      return 0 if v < 1 || v > nv
      k = (0) ## i64
      while k < j
        return 0 if q[k] == x || q[k] == -x
        k += 1
      q[j] = x; live[v] = 1
      j += 1
    wassat_wide_sort(q, n)
    h = (wassat_wide_hash(q, 0, n, mask)) ## i64
    tries = (0) ## i64
    while slots[h] != 0
      h = (h + 1) & mask
      tries += 1
      return 0 if tries >= 256
    slots[h] = ci + 1
    j = 0
    while j < n
      keys[7 * ci + j] = q[j]
      j += 1
    if n == 1
      x = q[0]; v = x < 0 ? -x : x
      want = (x > 0 ? -1 : 0) ## i64
      return 0 if known[v] != 0 && values[v] != want
      known[v] = 1; values[v] = want; covered[ci] = 1
      m[6] += 1
    ci += 1
  nr = (0) ## i64
  ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_wide_stopped(stop, deadline, m) != 0
    if m[12] > WASSAT_WIDE_MAX_PROBES
      m[9] = 2
      return 0
    n = lens[ci]
    if covered[ci] == 0 && n >= 2
      bits = (0) ## i64
      found = (0) ## i64
      complete = (1) ## i64
      while bits < (1 << n) && complete == 1
        parity = (0) ## i64
        j = 0
        while j < n
          parity = parity ^ ((bits >> j) & 1)
          x = keys[7 * ci + j]
          q[j] = ((bits >> j) & 1) == 0 ? x : -x
          j += 1
        if parity == 0
          wassat_wide_sort(q, n)
          id = (wassat_wide_lookup(q, n, keys, slots, lens, mask, m)) ## i64
          if id < 0
            complete = 0
          else
            ids[found] = id
            found += 1
        bits += 1
      if complete == 1
        rows[10 * nr] = 1; rows[10 * nr + 1] = n
        rhs = (1) ## i64
        j = 0
        while j < n
          x = keys[7 * ci + j]
          rhs = rhs ^ (x < 0 ? 1 : 0)
          q[j] = x < 0 ? -x : x
          j += 1
        wassat_wide_sort(q, n)
        rows[10 * nr + 2] = rhs
        j = 0
        while j < n
          rows[10 * nr + 3 + j] = q[j]
          j += 1
        j = 0
        while j < found
          covered[ids[j]] = 1
          j += 1
        nr += 1; m[1] += 1
    ci += 1
  ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_wide_stopped(stop, deadline, m) != 0
    if m[12] > WASSAT_WIDE_MAX_PROBES
      m[9] = 2
      return 0
    n = lens[ci]
    if covered[ci] == 0 && n >= 3
      choice = (n - 1) ## i64
      found = (-1) ## i64
      while choice >= 0 && found < 0
        out = (keys[7 * ci + choice]) ## i64
        ok = (1) ## i64
        j = 0
        while j < n && ok == 1
          if j != choice
            q[0] = -out; q[1] = -keys[7 * ci + j]
            wassat_wide_sort(q, 2)
            id = wassat_wide_lookup(q, 2, keys, slots, lens, mask, m)
            if id < 0
              ok = 0
            else
              ids[j] = id
          j += 1
        found = choice if ok == 1
        choice -= 1
      if found >= 0
        rows[10 * nr] = 0; rows[10 * nr + 1] = n
        rows[10 * nr + 3] = keys[7 * ci + found]
        j = 0; k = 1
        while j < n
          if j != found
            rows[10 * nr + 3 + k] = -keys[7 * ci + j]
            covered[ids[j]] = 1
            k += 1
          j += 1
        covered[ci] = 1; nr += 1; m[2] += 1
    ci += 1
  ci = 0
  while ci < nc
    return 0 if covered[ci] == 0
    ci += 1
  m[3] = nc
  ng = (0) ## i64
  na = (0) ## i64
  nf = (0) ## i64
  next_free = (1) ## i64
  while true
    changed = (1) ## i64
    while changed != 0
      changed = 0
      kind = (0) ## i64
      while kind < 2
        r = (0) ## i64
        while r < nr
          if done[r] == 0 && rows[10 * r] == kind
            if (r & 255) == 0
              return 0 if wassat_wide_stopped(stop, deadline, m) != 0
            p = (10 * r) ## i64
            n = rows[p + 1]
            unknown = (0) ## i64
            out = (0) ## i64
            j = 0
            while j < n
              x = rows[p + 3 + j]; v = x < 0 ? -x : x
              if known[v] == 0
                unknown += 1; out = v
              j += 1
            m[13] += n
            if m[13] > 8000000
              m[9] = 2
              return 0
            signed_out = (rows[p + 3]) ## i64
            abs_out = (signed_out < 0 ? -signed_out : signed_out) ## i64
            if unknown == 1 && (kind == 1 || out == abs_out)
              at = (10 * ng) ## i64
              program[at] = kind; program[at + 1] = out
              program[at + 2] = kind == 1 ? rows[p + 2] : (signed_out < 0 ? 1 : 0)
              program[at + 3] = n - 1
              j = 0; k = 0
              while j < n
                x = rows[p + 3 + j]; v = x < 0 ? -x : x
                if v != out
                  program[at + 4 + k] = x; k += 1
                j += 1
              ng += 1; known[out] = 1; done[r] = 1; changed = 1
            elsif unknown == 0
              at = 10 * na
              check[at] = kind; check[at + 1] = rows[p + 2]; check[at + 2] = n
              j = 0
              while j < n
                check[at + 3 + j] = rows[p + 3 + j]
                j += 1
              na += 1; done[r] = 1
          r += 1
        kind += 1
    while next_free <= nv && (known[next_free] != 0 || live[next_free] == 0)
      next_free += 1
    break if next_free > nv
    if nf >= 24
      m[9] = 2
      return 0
    free[nf] = next_free; nf += 1; known[next_free] = 1
  r = 0
  while r < nr
    return 0 if done[r] == 0
    r += 1
  m[4] = ng; m[5] = na; m[7] = nf
  work = (ng) ## i64
  r = 0
  while r < na
    work += check[10 * r + 2]; r += 1
  batches = (1 << (nf > 6 ? nf - 6 : 0)) ## i64
  m[8] = work * batches
  if m[8] > WASSAT_WIDE_MAX_WORK
    m[9] = 2
    return 0
  m[0] = 1
  1

# Evaluator counters: batches, gates, assertions, survivor mask, assertion
# operands, stop (1 cancellation / 2 deadline), stop polls.

-> wassat_wide_word(values, x) (i64[] i64) i64
  x > 0 ? values[x] : (-1 ^ values[-x])

-> wassat_wide_enumerate(program, check, free, values, nf, no, nc, m, stop, deadline) (i64[] i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64) i64
  masks = i64[6]
  masks[0] = -6148914691236517206 ## i64
  masks[1] = -3689348814741910324 ## i64
  masks[2] = -1085102592571150096 ## i64
  masks[3] = -71777214294589696 ## i64
  masks[4] = -281470681808896 ## i64
  masks[5] = -4294967296 ## i64
  batches = (1 << (nf > 6 ? nf - 6 : 0)) ## i64
  batch = (0) ## i64
  while batch < batches
    if (batch & 1023) == 0
      m[6] += 1
      if wassat_stop_load(stop) != 0
        m[5] = 1
        return 0
      if deadline > 0 && clock_ms() >= deadline
        m[5] = 2
        return 0
    j = (0) ## i64
    while j < nf
      values[free[j]] = j < 6 ? masks[j] : (((batch >> (j - 6)) & 1) == 0 ? 0 : -1)
      j += 1
    i = (0) ## i64
    while i < no
      at = (10 * i) ## i64
      kind = (program[at]) ## i64
      r = (kind == 1 ? 0 : -1) ## i64
      j = 0
      while j < program[at + 3]
        x = (wassat_wide_word(values, program[at + 4 + j])) ## i64
        if kind == 1
          r = r ^ x
        else
          r = r & x
        j += 1
      values[program[at + 1]] = program[at + 2] != 0 ? -1 ^ r : r
      i += 1
    m[1] += no
    live = (-1) ## i64
    i = 0
    while i < nc && live != 0
      at = (10 * i) ## i64
      kind = (check[at]) ## i64
      r = (kind == 1 ? 0 : -1) ## i64
      j = kind == 1 ? 0 : 1
      while j < check[at + 2]
        x = (wassat_wide_word(values, check[at + 3 + j])) ## i64
        if kind == 1
          r = r ^ x
        else
          r = r & x
        j += 1
      pass = (0) ## i64
      if kind == 1
        pass = check[at + 1] != 0 ? r : -1 ^ r
      else
        pass = -1 ^ (r ^ wassat_wide_word(values, check[at + 3]))
      live = live & pass
      m[2] += 1
      m[4] += check[at + 2]
      i += 1
    batch += 1
    m[0] = batch
    if live != 0
      m[3] = live
      return 0
  m[6] += 1
  if wassat_stop_load(stop) != 0
    m[5] = 1
    return 0
  if deadline > 0 && clock_ms() >= deadline
    m[5] = 2
    return 0
  1

# Coordinator admission is constant-time. Recognition and enumeration occur
# in the existing parallel circuit slot, beside the ordinary solving arms.
-> wassat_wide_plan(formula)
  return nil if env("WASSAT_WIDE_CIRCUIT") == "0" || !formula.has_key?("flat_ncl")
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  return nil if nv < 1 || nv > WASSAT_WIDE_MAX_VARS || nc < 1 || nc > WASSAT_WIDE_MAX_CLAUSES
  meta = i64[32]
  meta[18] = nc
  { "program": i64[10 * nv], "inputs": i64[24], "assertions": i64[10 * nc],
    "meta": meta, "values": i64[nv + 1], "wide_circuit": true,
    "scratch": wassat_wide_bytes(nv, nc) }

# The common circuit metadata layout is preserved for coordinator telemetry.
# Extra counters: 20 XORs, 21 ANDs, 22 units, 23 work bound, 24 assertions
# checked, 25 polls, 26 gate operands, 27 evaluation milliseconds.
-> wassat_wide_eval(lits, offs, lens, nv, program, inputs, assertions, meta, values, stop, deadline) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64) i64
  started = (clock_ms()) ## i64
  wall_end = (started + 5000) ## i64
  slot = (0) ## i64
  while slot < 32
    meta[slot] = 0 if slot != 18
    slot += 1
  wall_end = deadline if deadline > 0 && deadline < wall_end
  build_end = (started + 250) ## i64
  build_end = wall_end if wall_end < build_end
  b = i64[20]; e = i64[8]
  ok = (wassat_wide_build(lits, offs, lens, nv, meta[18], program, assertions, inputs, values, b, stop, build_end)) ## i64
  meta[0] = ok; meta[1] = b[7]; meta[2] = b[4]; meta[3] = b[5]
  meta[9] = b[9]; meta[12] = b[12]; meta[13] = b[1] + b[2]
  meta[14] = b[3]; meta[15] = b[13]; meta[16] = clock_ms() - started
  meta[20] = b[1]; meta[21] = b[2]; meta[22] = b[6]; meta[23] = b[8]; meta[25] = b[14]
  return 0 if ok == 0
  j = (0) ## i64
  operands = (0) ## i64
  while j < b[4]
    operands += program[10 * j + 3]; j += 1
  j = 0
  while j < b[5]
    meta[4] += assertions[10 * j + 2]; j += 1
  meta[5] = 1 << (b[7] > 6 ? b[7] - 6 : 0)
  tick = (clock_ms()) ## i64
  hit = (wassat_wide_enumerate(program, assertions, inputs, values, b[7], b[4], b[5], e, stop, wall_end)) ## i64
  meta[6] = e[0]; meta[7] = e[1]; meta[8] = e[4]
  meta[9] = e[5] == 2 ? 3 : e[5]
  meta[10] = hit == 1 ? -1 : (e[3] != 0 ? 1 : 0)
  meta[24] = e[2]; meta[25] += e[6]; meta[26] = operands * e[0]; meta[27] = clock_ms() - tick
  hit

-> wassat_wide_run(formula, plan, stop, deadline = 0)
  return 0 if plan == nil
  wassat_wide_eval(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], formula["nvars"], plan["program"], plan["inputs"], plan["assertions"], plan["meta"], plan["values"], stop, deadline)

-> wassat_wide_arm(lits, offs, lens, program, inputs, assertions, meta, values, stop, res, base, nv) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64) i64
  res[base + nv + 6] = clock_ms()
  hit = wassat_wide_eval(lits, offs, lens, nv, program, inputs, assertions, meta, values, stop, 0)
  res[base + nv + 5] = clock_ms()
  if hit == 1 && wassat_stop_load(stop) == 0
    z = ccall("__w_arr_store_rel", res, base, -1)
    won = wassat_stop_publish(stop, -1)
  hit

-> wassat_wide_profile(m)
  wassat_prof_note("race.wide_circuit recognized=[m[0]] inputs=[m[1]] gates=[m[2]] assertions=[m[3]] batches=[m[6]]/[m[5]] gate_evaluations=[m[7]] gate_operands=[m[26]] assertions_checked=[m[24]] assertion_operands=[m[8]] result=[m[10]] xors=[m[20]] ands=[m[21]] units=[m[22]] covered=[m[14]] probes=[m[12]] dependency_visits=[m[15]] work_bound=[m[23]] polls=[m[25]] build_ms=[m[16]] eval_ms=[m[27]] stopped=[m[9]]")
