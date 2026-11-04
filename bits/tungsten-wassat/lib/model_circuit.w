# Bounded model construction only. Unsupported encodings return UNKNOWN;
# every caller must replay all original clauses before publishing SAT.
use small_circuit

-> wassat_model_circuit_stop(meta, stop, deadline, work_limit) (i64[] i64[] i64 i64) i64
  if wassat_stop_load(stop) != 0
    meta[11] = 1
    return 1
  if deadline > 0 && clock_ms() >= deadline
    meta[11] = 2
    return 1
  if meta[4] > work_limit
    meta[11] = 3
    return 1
  0

-> wassat_model_circuit_build(lits, offs, lens, nv, nc, np, prog, head, next_clause, meta, stop, deadline, work_limit) (i64[] i64[] i64[] i64 i64 i64 i32[] i32[] i32[] i64[] i64[] i64 i64) i64
  count = i8[nv + 1]
  unit = i8[nv + 1]
  polarity = i8[nv + 1]
  ci = nc - 1
  while ci >= 0
    return 0 if (ci & 1023) == 0 && wassat_model_circuit_stop(meta, stop, deadline, work_limit) != 0
    o = offs[ci]
    n = lens[ci]
    return 0 if n < 1 || n > 512
    mx = 0
    j = 0
    while j < n
      l = lits[o + j]
      x = l < 0 ? 0 - l : l
      return 0 if x < 1 || x > nv
      mx = x if x > mx
      polarity[x] = polarity[x] | (l > 0 ? 1 : 2)
      j += 1
    if n == 1
      l = lits[o]
      s = l > 0 ? 1 : -1
      return 0 if unit[mx] != 0 && unit[mx] != s
      unit[mx] = s
    elsif n >= 2 && n <= 4
      return 0 if count[mx] >= 32
      count[mx] += 1
      next_clause[ci] = head[mx]
      head[mx] = ci + 1
    meta[4] += 1
    ci -= 1
  v = np + 1
  while v <= nv
    return 0 if (v & 255) == 0 && wassat_model_circuit_stop(meta, stop, deadline, work_limit) != 0
    chosen = 0
    entry = head[v]
    while entry > 0 && chosen == 0
      ci = entry - 1
      a = 0
      b = 0
      c = 0
      j = 0
      while j < lens[ci]
        l = lits[offs[ci] + j]
        x = l < 0 ? 0 - l : l
        if x != v && x != a && x != b && x != c
          if a == 0
            a = x
          elsif b == 0
            b = x
          else
            c = x
        j += 1
      # Input ordering is irrelevant to the recovered truth table.
      mask = c != 0 ? 255 : (b != 0 ? 15 : 3)
      allow0 = mask
      allow1 = mask
      e = head[v]
      while e > 0
        q = e - 1
        sat = 0
        out = 0
        fits = 1
        j = 0
        while j < lens[q]
          l = lits[offs[q] + j]
          x = l < 0 ? 0 - l : l
          if x == v
            out = out | (l > 0 ? 1 : 2)
          else
            m = x == a ? 170 : (x == b ? 204 : 240)
            fits = 0 if x != a && x != b && x != c
            sat = sat | (l > 0 ? m : (255 ^ m))
          j += 1
        if fits == 1
          allow0 = allow0 & sat if (out & 2) == 0
          allow1 = allow1 & sat if (out & 1) == 0
        meta[4] += 1
        e = next_clause[q]
      meta[5] += 1
      if a != 0 && (allow0 & allow1) == 0 && (allow0 | allow1) == mask
        prog[4 * v] = a
        prog[4 * v + 1] = b
        prog[4 * v + 2] = c
        prog[4 * v + 3] = allow1
        chosen = 1
      entry = next_clause[ci]
    if chosen == 0
      return 0 if unit[v] == 0 && polarity[v] != 1 && polarity[v] != 2
      prog[4 * v + 3] = unit[v] != 0 ? (unit[v] > 0 ? 1 : 0) : (polarity[v] == 1 ? 1 : 0)
    meta[2] += 1
    v += 1
  1

-> wassat_model_circuit_eval(prog, values, np, nv, meta, stop, deadline, work_limit) (i32[] i64[] i64 i64 i64[] i64[] i64 i64) i64
  v = np + 1
  while v <= nv
    return 0 if (v & 1023) == 0 && wassat_model_circuit_stop(meta, stop, deadline, work_limit) != 0
    p = 4 * v
    a = values[prog[p]]
    b = values[prog[p + 1]]
    c = values[prog[p + 2]]
    tt = prog[p + 3] ## i64
    if prog[p] == 0
      values[v] = 0 - tt
    elsif prog[p + 1] == 0
      values[v] = tt == 2 ? a : (tt == 1 ? (-1 ^ a) : (tt == 3 ? -1 : 0))
    elsif prog[p + 2] == 0
      values[v] = wassat_small_circuit_word(a, b, tt)
    elsif tt == 150
      values[v] = a ^ b ^ c
    elsif tt == 232
      values[v] = (a & b) | ((a | b) & c)
    else
      lo = wassat_small_circuit_word(a, b, tt & 15)
      hi = wassat_small_circuit_word(a, b, tt >> 4)
      values[v] = ((-1 ^ c) & lo) | (c & hi)
    meta[6] += 1
    v += 1
  1
