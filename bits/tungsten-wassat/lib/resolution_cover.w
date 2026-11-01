# Bounded resolution-chain projection, using only original clauses.
# Degree selects a possible core; it is never evidence for a verdict. Each
# cover row is an actual resolvent. A full cover refutes, and an all-but-one
# cover entails its unique remaining assignment. Original-clause propagation
# may then refute the conjunction. Unsupported or partial covers decline.
use atomic_stop

# meta: status, projections, rows, chain steps, scan clauses, UP clauses,
# entailed units, propagated units, stop reason, conflict clause (one based),
# work ticks, start ms, finish ms, current support size.
-> wassat_cover_stop(m, stop, deadline) (i64[] i64[] i64) i64
  return 1 if m[8] != 0
  if wassat_stop_load(stop) != 0
    m[8] = 1
  elsif deadline > 0 && clock_ms() >= deadline
    m[8] = 2
  m[8] != 0 ? 1 : 0

-> wassat_cover_tick(m, stop, deadline) (i64[] i64[] i64) i64
  m[10] += 1
  m[8] = 3 if m[10] > 400000000
  return wassat_cover_stop(m, stop, deadline) if (m[10] & 4095) == 0
  m[8] != 0 ? 1 : 0

# One candidate clause per signed auxiliary literal. Preferring unassigned
# core literals separates projections that share auxiliary chains. The fixed
# support pass then discards every clause containing a foreign core variable.
-> wassat_cover_index(lits, offs, lens, nc, degree, position, values, index, score, fixed, m, stop, deadline) (i64[] i64[] i64[] i64 i8[] i8[] i8[] i32[] i8[] i64 i64[] i64[] i64) i64
  i = 0
  while i < index.size
    return 0 if wassat_cover_tick(m, stop, deadline) != 0
    index[i] = 0
    score[i] = -1
    i += 1
  ci = 0
  while ci < nc
    return 0 if wassat_cover_tick(m, stop, deadline) != 0
    m[4] += 1
    n = lens[ci]
    if n > 0 && n <= 4
      a = 0; b = 0; good = 1; priority = 0; j = 0
      while j < n && good != 0
        l = lits[offs[ci] + j]
        v = l < 0 ? -l : l
        if degree[v] > 16
          priority += 1 if values[v] == 0
          good = 0 if fixed != 0 && position[v] == 0
        elsif a == 0
          a = l
        elsif b == 0
          b = l
        else
          good = 0
        j += 1
      if good != 0
        j = 0
        while j < 2
          l = j == 0 ? a : b
          if l != 0
            v = l < 0 ? -l : l
            at = 2 * v + (l < 0 ? 1 : 0)
            if priority > score[at]
              index[at] = ci + 1
              score[at] = priority
          j += 1
    ci += 1
  1

# The current resolvent contains core literals plus at most one auxiliary.
# Resolve that auxiliary against a checked opposite occurrence. Duplicate core
# literals collapse into masks; opposite signs and unsupported pivots decline.
# Return negation mask + 1, or zero on failure. No per-chain allocation.
-> wassat_cover_chain(lits, offs, lens, degree, position, index, vars, start, fixed, m, stop, deadline) (i64[] i64[] i64[] i8[] i8[] i32[] i32[] i64 i64 i64[] i64[] i64) i64
  ci = start; pivot = 0; pos = 0; neg = 0; count = 0; step = 0
  while step < 64
    return 0 if wassat_cover_tick(m, stop, deadline) != 0
    m[3] += 1
    n = lens[ci]
    return 0 if n < 1 || n > 4
    remaining = 0; matched = pivot == 0 ? 1 : 0; j = 0
    while j < n
      l = lits[offs[ci] + j]
      v = l < 0 ? -l : l
      if pivot != 0 && l == -pivot
        matched = 1
      else
        return 0 if pivot != 0 && (l == pivot)
        if degree[v] <= 16
          return 0 if remaining != 0
          remaining = l
        else
          at = position[v] - 1
          if fixed == 0
            at = 0
            while at < count && vars[at] != v
              at += 1
            if at == count
              return 0 if count >= 20
              vars[count] = v
              count += 1
          return 0 if at < 0 || at >= 20
          if l > 0
            pos = pos | (1 << at)
          else
            neg = neg | (1 << at)
      j += 1
    return 0 if matched == 0 || (pos & neg) != 0
    if remaining == 0
      if fixed != 0
        return 0 unless (pos | neg) == (1 << m[13]) - 1
      else
        m[13] = count
      return neg + 1
    pivot = remaining
    v = pivot < 0 ? -pivot : pivot
    at = 2 * v + (pivot < 0 ? 0 : 1)
    ci = index[at] - 1
    return 0 if ci < 0
    step += 1
  0

# A bounded original-clause unit propagation sweep. Incomplete propagation is
# safe: every retained assignment is entailed, and only a falsified original
# clause can publish a refutation. Duplicate literals may hide a unit, never
# invent one. Wide clauses participate here even though chains ignore them.
-> wassat_cover_propagate(lits, offs, lens, nc, values, passes, m, stop, deadline) (i64[] i64[] i64[] i64 i8[] i64 i64[] i64[] i64) i64
  pass = 0
  while pass < passes
    changed = 0; ci = 0
    while ci < nc
      return 0 if wassat_cover_tick(m, stop, deadline) != 0
      m[5] += 1
      j = 0; unit = 0; unknown = 0; sat = 0
      while j < lens[ci] && sat == 0
        return 0 if (j & 4095) == 4095 && wassat_cover_tick(m, stop, deadline) != 0
        l = lits[offs[ci] + j]
        v = l < 0 ? -l : l
        value = values[v]
        if value == (l < 0 ? -1 : 1)
          sat = 1
        elsif value == 0
          unit = l
          unknown += 1
        j += 1
      if sat == 0
        if unknown == 0
          return 0 if wassat_cover_stop(m, stop, deadline) != 0
          m[9] = ci + 1
          return -1
        if unknown == 1
          v = unit < 0 ? -unit : unit
          values[v] = unit < 0 ? -1 : 1
          m[7] += 1
          changed = 1
      ci += 1
    return 0 if changed == 0
    pass += 1
  0

# Scratch is allocated by the coordinator, once per worker, and reused across
# every projection and chain. The worker itself has no boxed dispatch.
-> wassat_cover_check(lits, offs, lens, nv, nc, degree, position, values, index, score, vars, cover, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i8[] i8[] i8[] i32[] i8[] i32[] i8[] i64[] i64[] i64) i64
  return 0 if nv < 1 || nv > 2000000 || nc < 1 || nc > 8000000
  return 0 if wassat_cover_stop(m, stop, deadline) != 0
  return 0 if offs.size < nc || lens.size < nc
  ci = 0
  while ci < nc
    return 0 if wassat_cover_tick(m, stop, deadline) != 0
    m[4] += 1
    off = offs[ci]; n = lens[ci]
    return 0 if n < 0 || off < 0 || off + n > lits.size
    j = 0
    while j < n
      return 0 if (j & 4095) == 4095 && wassat_cover_tick(m, stop, deadline) != 0
      l = lits[off + j]
      v = l < 0 ? -l : l
      return 0 if v < 1 || v > nv
      degree[v] += 1 if degree[v] < 17
      j += 1
    ci += 1
  round = 0
  while round < 12
    return 0 if wassat_cover_index(lits, offs, lens, nc, degree, position, values, index, score, 0, m, stop, deadline) == 0
    ci = 0; found = 0
    while ci < nc && found == 0
      return 0 if wassat_cover_tick(m, stop, deadline) != 0
      m[4] += 1
      if lens[ci] > 0 && lens[ci] <= 4
        aux = 0; unknown = 0; j = 0
        while j < lens[ci]
          l = lits[offs[ci] + j]
          v = l < 0 ? -l : l
          if degree[v] <= 16
            aux += 1
          elsif values[v] == 0
            unknown += 1
          j += 1
        if aux <= 1 && unknown > 0
          found = wassat_cover_chain(lits, offs, lens, degree, position, index, vars, ci, 0, m, stop, deadline)
          found = 0 if m[13] < 2
      ci += 1
    break if found == 0
    k = m[13]; size = 1 << k; j = 0
    while j < k
      position[vars[j]] = j + 1
      j += 1
    j = 0
    while j < size
      return 0 if wassat_cover_tick(m, stop, deadline) != 0
      cover[j] = 0
      j += 1
    return 0 if wassat_cover_index(lits, offs, lens, nc, degree, position, values, index, score, 1, m, stop, deadline) == 0
    ci = 0; covered = 0
    while ci < nc && covered < size
      return 0 if wassat_cover_tick(m, stop, deadline) != 0
      m[4] += 1
      n = lens[ci]
      if n > 0 && n <= 4
        aux = 0; good = 1; j = 0
        while j < n && good != 0
          l = lits[offs[ci] + j]
          v = l < 0 ? -l : l
          if degree[v] <= 16
            aux += 1
          elsif position[v] == 0
            good = 0
          j += 1
        if good != 0 && aux <= 1
          row = wassat_cover_chain(lits, offs, lens, degree, position, index, vars, ci, 1, m, stop, deadline)
          if row > 0 && cover[row - 1] == 0
            cover[row - 1] = 1
            covered += 1
            m[2] += 1
      ci += 1
    return 0 if wassat_cover_stop(m, stop, deadline) != 0
    m[1] += 1
    if covered == size
      m[0] = -1
      return -1
    return 0 if covered + 1 != size
    missing = 0
    while cover[missing] != 0
      missing += 1
    j = 0
    while j < k
      v = vars[j]
      value = ((missing >> j) & 1) == 0 ? -1 : 1
      if values[v] != 0 && values[v] != value
        m[0] = -1
        return -1
      m[6] += 1 if values[v] == 0
      values[v] = value
      position[v] = 0
      j += 1
    if wassat_cover_propagate(lits, offs, lens, nc, values, 1, m, stop, deadline) == -1
      m[0] = -1
      return -1
    round += 1
  if wassat_cover_propagate(lits, offs, lens, nc, values, 32, m, stop, deadline) == -1
    m[0] = -1
    return -1
  0

-> wassat_cover_scratch(nv)
  {"degree": i8[nv + 1], "position": i8[nv + 1], "values": i8[nv + 1],
   "index": i32[2 * nv + 2], "score": i8[2 * nv + 2],
   "vars": i32[20], "cover": i8[1048576], "meta": i64[14]}

-> wassat_resolution_cover_refute(formula, stop, deadline = 0)
  nv = formula["nvars"]
  return i64[14] if nv < 1 || nv > 2000000
  p = wassat_cover_scratch(nv)
  m = p["meta"]
  m[11] = clock_ms()
  z = wassat_cover_check(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nv, formula["flat_ncl"], p["degree"], p["position"], p["values"], p["index"], p["score"], p["vars"], p["cover"], m, stop, deadline)
  m[12] = clock_ms()
  m

# Cheap, input-derived admission: a mostly width-four prefix with substantial
# variable reuse. Narrow chains are left to the established search policy. This only limits speculative cost; the worker checks every
# premise again. Explicit enablement admits small generated validation cases.
-> wassat_cover_prefix(lits, offs, lens, nv, nc) (i64[] i64[] i64[] i64 i64) i64
  return 0 if nv < 100000 || nv > 2000000 || nc < 500000 || nc > 8000000
  keys = i32[2048]
  unique = 0; fours = 0; ci = 0
  while ci < 256
    n = lens[ci]
    return 0 if n < 2 || n > 4
    fours += 1 if n == 4
    j = 0
    while j < n
      l = lits[offs[ci] + j]
      v = l < 0 ? -l : l
      slot = (v * 131) & 2047
      while keys[slot] != 0 && keys[slot] != v
        slot = (slot + 1) & 2047
      if keys[slot] == 0
        keys[slot] = v
        unique += 1
        return 0 if unique > 160
      j += 1
    ci += 1
  fours >= 192 ? 1 : 0

-> wassat_resolution_cover_plan(formula, workers)
  mode = env("WASSAT_RESOLUTION_COVER")
  return nil if mode == "0" || formula == nil
  return nil if env("WASSAT_ARMS") != nil && mode != "1"
  return nil if System.cpu_count <= workers || System.physical_memory_bytes <= 0
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return nil if nv < 1 || nv > 2000000 || nc < 1 || nc > 8000000
  return nil if formula["flat_nlits"] > 64000000
  # Include all five result slots when a lone solver becomes a race,
  # as well as scratch. Existing races need only one additional result slot.
  return nil if 53 * (nv + 1) + 1048576 > System.physical_memory_bytes / 64
  if mode != "1"
    return nil if wassat_cover_prefix(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nv, nc) == 0
  wassat_cover_scratch(nv)

-> wassat_cover_arm(lits, offs, lens, nv, nc, degree, position, values, index, score, vars, cover, m, stop, res, base) (i64[] i64[] i64[] i64 i64 i8[] i8[] i8[] i32[] i8[] i32[] i8[] i64[] i64[] i64[] i64) i64
  m[11] = clock_ms()
  z = wassat_cover_check(lits, offs, lens, nv, nc, degree, position, values, index, score, vars, cover, m, stop, m[11] + 15000)
  m[12] = clock_ms()
  res[base + nv + 6] = m[11]
  res[base + nv + 5] = m[12]
  if z == -1 && wassat_cover_stop(m, stop, m[11] + 15000) == 0
    z = ccall("__w_arr_store_rel", res, base, -1)
    won = wassat_stop_publish(stop, -1)
    return -1
  0
