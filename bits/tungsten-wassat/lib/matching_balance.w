# A checked UNSAT subset: positive exact-one rows form graph vertices and
# each participating variable occurs in exactly two rows, forming an edge.
# In a bipartite component, each true variable contributes one to each side.
# Unequal side sizes therefore contradict the exact-one row requirements.
# No geometry, variable naming, or stored answer is part of the certificate.
use atomic_stop

# meta: status, rows, edges, components, left, right, clause visits, AMO pairs,
# stop reason (1 cancellation, 2 deadline). All counters use fixed buffers.
-> wassat_matching_balance_stop(meta, stop, deadline) (i64[] i64[] i64) i64
  if wassat_stop_load(stop) != 0
    meta[8] = 1
    return 1
  if deadline > 0 && clock_ms() >= deadline
    meta[8] = 2
    return 1
  0

-> wassat_matching_balance_check(lits, offs, lens, nv, nc, meta, stop, deadline) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64) i64
  return 0 if nv < 2 || nv > 4096 || nc < 3 || nc > 50000
  return 0 if wassat_matching_balance_stop(meta, stop, deadline) != 0
  first = i32[nv + 1]
  second = i32[nv + 1]
  rows = i32[2 * nv]
  nr = 0
  ci = 0
  while ci < nc
    return 0 if (ci & 1023) == 0 && wassat_matching_balance_stop(meta, stop, deadline) != 0
    n = lens[ci]
    if n >= 1 && n <= 32
      positive = 1
      j = 0
      while j < n
        positive = 0 if lits[offs[ci] + j] <= 0
        j += 1
      if positive == 1
        return 0 if nr >= 2 * nv
        rows[nr] = ci
        j = 0
        while j < n
          v = lits[offs[ci] + j]
          return 0 if v > nv
          k = 0
          while k < j
            return 0 if lits[offs[ci] + k] == v
            k += 1
          if first[v] == 0
            first[v] = nr + 1
          elsif second[v] == 0
            second[v] = nr + 1
          else
            return 0
          j += 1
        nr += 1
    meta[6] += 1
    ci += 1
  meta[1] = nr
  return 0 if nr < 3
  v = 1
  while v <= nv
    if first[v] != 0
      return 0 if second[v] == 0
      meta[2] += 1
    v += 1
  color = i8[nr]
  queue = i32[nr]
  root = 0
  witness = 0
  tail = 0
  while root < nr && witness == 0
    if color[root] == 0
      meta[3] += 1
      color[root] = 1
      queue[0] = root
      head = 0
      tail = 1
      left = 0
      right = 0
      bipartite = 1
      while head < tail
        return 0 if (head & 255) == 0 && wassat_matching_balance_stop(meta, stop, deadline) != 0
        row = queue[head]
        if color[row] == 1
          left += 1
        else
          right += 1
        ci = rows[row]
        j = 0
        while j < lens[ci]
          v = lits[offs[ci] + j]
          other = first[v] + second[v] - row - 2
          if color[other] == 0
            color[other] = 0 - color[row]
            queue[tail] = other
            tail += 1
          elsif color[other] == color[row]
            bipartite = 0
          j += 1
        head += 1
      if bipartite == 1 && left != right
        witness = 1
        meta[4] = left
        meta[5] = right
    root += 1
  return 0 if witness == 0
  # A positive row supplies at-least-one. Require every pairwise exclusion
  # literally in the input before treating that row as exact-one.
  words = (nv + 63) / 64
  exclusion = i64[nv * words]
  one = 1 ## i64
  ci = 0
  while ci < nc
    return 0 if (ci & 1023) == 0 && wassat_matching_balance_stop(meta, stop, deadline) != 0
    if lens[ci] == 2
      a = lits[offs[ci]]
      b = lits[offs[ci] + 1]
      if a < 0 && b < 0
        a = 0 - a - 1
        b = 0 - b - 1
        return 0 if a >= nv || b >= nv
        # Keep high mask bits native rather than boxing them as BigInts.
        edge = a * words + b / 64 ## i64
        mask = one << (b % 64) ## i64
        bits = exclusion[edge] ## i64
        bits = bits | mask
        exclusion[edge] = bits
        edge = b * words + a / 64
        mask = one << (a % 64)
        bits = exclusion[edge]
        bits = bits | mask
        exclusion[edge] = bits
    meta[6] += 1
    ci += 1
  at = 0
  while at < tail
    return 0 if (at & 255) == 0 && wassat_matching_balance_stop(meta, stop, deadline) != 0
    ci = rows[queue[at]]
    i = 0
    while i < lens[ci]
      a = lits[offs[ci] + i] - 1
      j = i + 1
      while j < lens[ci]
        b = lits[offs[ci] + j] - 1
        meta[7] += 1
        edge = a * words + b / 64 ## i64
        mask = one << (b % 64) ## i64
        bits = exclusion[edge] ## i64
        return 0 if (bits & mask) == 0
        j += 1
      i += 1
    at += 1
  meta[0] = -1
  -1

-> wassat_matching_balance_refute(formula, stop, deadline = 0)
  meta = i64[9]
  return meta if formula == nil
  z = wassat_matching_balance_check(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], formula["nvars"], formula["flat_ncl"], meta, stop, deadline)
  meta
