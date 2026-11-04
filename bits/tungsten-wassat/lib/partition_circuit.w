# Model-only arithmetic circuit heuristic. Recover bounded three-input truth
# tables in numeric topological order, infer an equal-sum partition from
# one-hot circuit evaluations, and check every original clause before SAT.
# Recognition may miss or misinterpret a circuit; neither can imply UNSAT.
use model_circuit

# meta: status, primary inputs, gates, output bits, clause visits, truth-table
# candidates, gate evaluations, pair inserts, pair probes, verified clauses,
# candidate models, stop reason (1 cancellation, 2 deadline, 3 work bound).
-> wassat_partition_stop(meta, stop, deadline) (i64[] i64[] i64) i64
  if wassat_stop_load(stop) != 0
    meta[11] = 1
    return 1
  if deadline > 0 && clock_ms() >= deadline
    meta[11] = 2
    return 1
  if meta[4] > 4000000
    meta[11] = 3
    return 1
  0

-> wassat_partition_primary(formula)
  return 0 if formula == nil || formula["flat_ncl"] == 0
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return 0 if nv < 8 || nv > 200000 || nc > 800000
  np = formula["flat_lens"][0]
  return 0 if np < 4 || np > 512 || np % 2 != 0 || nv <= np
  i = 0
  o = formula["flat_offs"][0]
  while i < np
    return 0 if formula["flat_lits"][o + i] != 0 - i - 1
    i += 1
  np

-> wassat_partition_build(lits, offs, lens, nv, nc, np, prog, pairs, meta, stop, deadline) (i64[] i64[] i64[] i64 i64 i64 i32[] i32[] i64[] i64[] i64) i64
  head = i32[nv + 1]
  next_clause = i32[nc]
  return 0 if wassat_model_circuit_build(lits, offs, lens, nv, nc, np, prog, head, next_clause, meta, stop, deadline, 4000000) == 0
  # Equality assertions joining two independently defined XOR outputs expose
  # the ordered result bits. Gate-copy equalities are not candidate outputs.
  nb = 0
  v = np + 1
  while v <= nv
    return 0 if (v & 255) == 0 && wassat_partition_stop(meta, stop, deadline) != 0
    if prog[4 * v + 1] != 0 && ((prog[4 * v + 2] == 0 && prog[4 * v + 3] == 6) || (prog[4 * v + 2] != 0 && prog[4 * v + 3] == 150))
      e = head[v]
      while e > 0
        ci = e - 1
        if lens[ci] == 2
          l = lits[offs[ci]]
          r = lits[offs[ci] + 1]
          x = l < 0 ? 0 - l : l
          y = r < 0 ? 0 - r : r
          a = x == v ? y : x
          if (l < 0) != (r < 0) && a > np && a < v && prog[4 * a + 1] != 0 && ((prog[4 * a + 2] == 0 && prog[4 * a + 3] == 6) || (prog[4 * a + 2] != 0 && prog[4 * a + 3] == 150))
            found = 0
            f = head[v]
            while f > 0 && found == 0
              q = f - 1
              if lens[q] == 2
                s = lits[offs[q]]
                t = lits[offs[q] + 1]
                found = 1 if (s == 0 - l && t == 0 - r) || (s == 0 - r && t == 0 - l)
              meta[4] += 1
              f = next_clause[q]
            if found == 1
              if nb == 0 || pairs[2 * nb - 1] != v
                return 0 if nb >= 30
                pairs[2 * nb] = a
                pairs[2 * nb + 1] = v
                nb += 1
        meta[4] += 1
        e = next_clause[ci]
    v += 1
  meta[3] = nb
  return 0 if nb < 2
  1

-> wassat_partition_eval(prog, values, np, nv, meta, stop, deadline) (i32[] i64[] i64 i64 i64[] i64[] i64) i64
  wassat_model_circuit_eval(prog, values, np, nv, meta, stop, deadline, 4000000)

-> wassat_partition_find(weights, np, selected, meta, stop, deadline) (i64[] i64 i8[] i64[] i64[] i64) i64
  target = 0 - weights[0]
  return 0 if target <= 0
  order = i32[np]
  total = 0
  biggest = 0
  i = 0
  while i < np
    w = weights[i + 1] - weights[0]
    return 0 if w <= 0 || w > 262143
    weights[i + 1] = w
    total += w
    biggest = w if w > biggest
    j = i
    while j > 0 && weights[order[j - 1]] < w
      order[j] = order[j - 1]
      j -= 1
    order[j] = i + 1
    i += 1
  return 0 if total != 2 * target
  left = 0
  right = 0
  i = 0
  while i < np
    x = order[i]
    y = order[i + 1]
    if left > right
      t = x
      x = y
      y = t
    selected[x] = 1
    left += weights[x]
    right += weights[y]
    i += 2
  return 1 if left == target
  table = i32[2 * biggest + 1]
  i = 1
  while i <= np
    return 0 if (i & 31) == 0 && wassat_partition_stop(meta, stop, deadline) != 0
    if selected[i] == 1
      j = i + 1
      while j <= np
        if selected[j] == 1
          table[weights[i] + weights[j]] = (i - 1) * np + j
          meta[7] += 1
        j += 1
    i += 1
  i = 1
  while i <= np
    return 0 if (i & 31) == 0 && wassat_partition_stop(meta, stop, deadline) != 0
    if selected[i] == 0
      j = i + 1
      while j <= np
        if selected[j] == 0
          need = left - target + weights[i] + weights[j]
          meta[8] += 1
          if need >= 0 && need <= 2 * biggest && table[need] != 0
            code = table[need] - 1
            selected[code / np + 1] = 0
            selected[code % np + 1] = 0
            selected[i] = 1
            selected[j] = 1
            return 1
        j += 1
    i += 1
  0

-> wassat_partition_samples(prog, pairs, values, weights, meta, np, nv, stop, deadline) (i32[] i32[] i64[] i64[] i64[] i64 i64 i64[] i64) i64
  batch = 0
  while batch <= np
    i = 1
    while i <= np
      values[i] = i >= batch && i < batch + 64 ? (1 << (i - batch)) : 0
      i += 1
    return 0 if wassat_partition_eval(prog, values, np, nv, meta, stop, deadline) == 0
    lane = 0
    while lane < 64 && batch + lane <= np
      diff = 0
      bit = 0
      while bit < meta[3]
        a = (values[pairs[2 * bit]] >> lane) & 1
        b = (values[pairs[2 * bit + 1]] >> lane) & 1
        diff += (a - b) << bit
        bit += 1
      weights[batch + lane] = diff
      lane += 1
    batch += 64
  1

-> wassat_partition_model(formula, stop, deadline = 0)
  np = wassat_partition_primary(formula)
  return nil if np == 0
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  meta = i64[12]
  meta[1] = np
  result = { "meta": meta, "model": [] }
  return result if wassat_partition_stop(meta, stop, deadline) != 0
  prog = i32[4 * (nv + 1)]
  pairs = i32[60]
  return result if wassat_partition_build(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nv, nc, np, prog, pairs, meta, stop, deadline) == 0
  values = i64[nv + 1]
  weights = i64[np + 1]
  return result if wassat_partition_samples(prog, pairs, values, weights, meta, np, nv, stop, deadline) == 0
  selected = i8[np + 1]
  return result if wassat_partition_find(weights, np, selected, meta, stop, deadline) == 0
  i = 1
  while i <= np
    values[i] = 0 - selected[i]
    i += 1
  return result if wassat_partition_eval(prog, values, np, nv, meta, stop, deadline) == 0
  meta[10] += 1
  ci = 0
  while ci < nc
    return result if (ci & 1023) == 0 && wassat_partition_stop(meta, stop, deadline) != 0
    sat = false
    j = 0
    while j < formula["flat_lens"][ci] && !sat
      l = formula["flat_lits"][formula["flat_offs"][ci] + j]
      x = l < 0 ? 0 - l : l
      sat = (l > 0) == (values[x] != 0)
      j += 1
    meta[9] += 1
    return result unless sat
    ci += 1
  model = i64[nv]
  i = 1
  while i <= nv
    model[i - 1] = values[i] != 0 ? i : 0 - i
    i += 1
  meta[0] = 1
  result["model"] = model
  result
