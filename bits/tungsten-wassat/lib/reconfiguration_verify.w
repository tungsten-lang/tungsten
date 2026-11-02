# Sufficient original-clause contract for a token-jump path. Recognition of
# repeated graph blocks alone is never a refutation certificate. Each step
# must additionally enforce exactly one addition and exactly one removal,
# with complete equivalences to the old/new vertex assignments. Pairwise
# AMO may be direct, or implied by two original selector implications and
# an original exclusion between their targets (e.g. a product encoding).
# Extra clauses can only restrict this verified relaxation.

-> wassat_rc_clause(lits, offs, lens, table, a, b, c, n, insert, m) (i64[] i64[] i64[] i32[] i64 i64 i64 i64 i64 i64[]) i64
  if n > 1 && a > b
    tmp = a; a = b; b = tmp
  if n > 2
    if b > c
      tmp = b; b = c; c = tmp
    if a > b
      tmp = a; a = b; b = tmp
  hash = ((a * 1000003) ^ (b * 1000033) ^ (c * 1000037) ^ n) ## i64
  mask = table.size - 1 ## i64
  at = (hash ^ (hash >> 23)) & mask ## i64
  probes = 0 ## i64
  while table[at] != 0
    m[26] += 1
    ci = table[at] - 1 ## i64
    if lens[ci] == n
      off = offs[ci] ## i64
      x = lits[off] ## i64
      y = n > 1 ? lits[off + 1] : 0 ## i64
      z = n > 2 ? lits[off + 2] : 0 ## i64
      if n > 1 && x > y
        tmp = x; x = y; y = tmp
      if n > 2
        if y > z
          tmp = y; y = z; z = tmp
        if x > y
          tmp = x; x = y; y = tmp
      return ci + 1 if a == x && b == y && c == z
    at = (at + 1) & mask
    probes += 1
    if probes >= 256
      m[2] = 4
      return 0
  if insert > 0
    table[at] = insert
    return insert
  0

-> wassat_rc_has(lits, offs, lens, table, a, b, c, n, m) (i64[] i64[] i64[] i32[] i64 i64 i64 i64 i64[]) bool
  m[27] += 1
  wassat_rc_clause(lits, offs, lens, table, a, b, c, n, 0, m) > 0

-> wassat_rc_verify(lits, offs, lens, nv, nc, n, starts, initial, goal, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i64) i64
  m[25] = 0
  count = m[4] ## i64
  return 0 if n < 4 || n > WASSAT_RECONF_MAX_VERTICES || count < 2 || count > WASSAT_RECONF_MAX_STATES
  size = 1 ## i64
  while size < 2 * nc
    size *= 2
  table = i32[size]
  graph_at = i64[WASSAT_RECONF_MAX_STATES + 1]
  rows = i64[2 * WASSAT_RECONF_MAX_STATES]
  selectors = i64[2 * WASSAT_RECONF_MAX_VERTICES]
  step = 0 ## i64
  ci = 0 ## i64
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_reconf_stop(m, stop, deadline) != 0
    off = offs[ci] ## i64
    len = lens[ci] ## i64
    # prepare already checked every input span and variable bound.
    if len >= 1 && len <= 3
      b = len > 1 ? lits[off + 1] : 0 ## i64
      c = len > 2 ? lits[off + 2] : 0 ## i64
      z = wassat_rc_clause(lits, offs, lens, table, lits[off], b, c, len, ci + 1, m)
      return 0 if m[2] != 0
    if step < count && len == 2
      if lits[off] == lits[offs[0]] - starts[step] && lits[off + 1] == lits[offs[0] + 1] - starts[step]
        graph_at[step] = ci
        step += 1
    ci += 1
  return 0 if step != count
  graph_at[count] = nc
  one = 1 ## i64
  step = 0
  while step < count
    return 0 if wassat_reconf_stop(m, stop, deadline) != 0
    # The first two positive consecutive n-wide clauses in a graph interval
    # nominate selectors only. Every required frame and AMO is checked below.
    nr = 0 ## i64
    ci = graph_at[step] + m[5]
    while ci < graph_at[step + 1] && nr < 2
      return 0 if (ci & 255) == 0 && wassat_reconf_stop(m, stop, deadline) != 0
      if lens[ci] == n
        off = offs[ci]
        base = lits[off] ## i64
        j = 0 ## i64
        while base > 0 && j < n && lits[off + j] == base + j
          j += 1
        if j == n
          rows[2 * step + nr] = base
          nr += 1
      ci += 1
    return 0 if nr != 2
    side = 0 ## i64
    while side < 2
      base = rows[2 * step + side] ## i64
      v = 0 ## i64
      while v < 2 * n
        selectors[v] = 0
        v += 1
      # Auxiliary targets above the selector row are a conservative candidate
      # choice; their numeric ordering never justifies an implication.
      ci = graph_at[step]
      while ci < graph_at[step + 1]
        return 0 if (ci & 255) == 0 && wassat_reconf_stop(m, stop, deadline) != 0
        if lens[ci] == 2
          off = offs[ci]
          a = lits[off] ## i64
          b = lits[off + 1] ## i64
          if a > 0 && b < 0
            tmp = a; a = b; b = tmp
          v = -a - base
          if a < 0 && v >= 0 && v < n && b >= base + n
            if selectors[2 * v] == 0
              selectors[2 * v] = b
            elsif selectors[2 * v] != b && selectors[2 * v + 1] == 0
              selectors[2 * v + 1] = b
        ci += 1
      v = 0
      while v < n
        x = starts[step] + v + 1 ## i64
        a = base + v ## i64
        good = false
        if step == 0
          inside = (initial[v >> 6] & (one << (v & 63))) != 0
          if side == 0
            good = inside ? wassat_rc_has(lits, offs, lens, table, -a, 0, 0, 1, m) : wassat_rc_has(lits, offs, lens, table, -x, a, 0, 2, m)
            good = good && wassat_rc_has(lits, offs, lens, table, -a, x, 0, 2, m)
          else
            good = inside ? wassat_rc_has(lits, offs, lens, table, a, x, 0, 2, m) : wassat_rc_has(lits, offs, lens, table, -a, 0, 0, 1, m)
            good = good && wassat_rc_has(lits, offs, lens, table, -a, -x, 0, 2, m)
        else
          old = starts[step - 1] + v + 1 ## i64
          if side == 0
            good = wassat_rc_has(lits, offs, lens, table, -x, old, a, 3, m)
            good = good && wassat_rc_has(lits, offs, lens, table, -a, x, 0, 2, m)
            good = good && wassat_rc_has(lits, offs, lens, table, -a, -old, 0, 2, m)
          else
            good = wassat_rc_has(lits, offs, lens, table, -old, x, a, 3, m)
            good = good && wassat_rc_has(lits, offs, lens, table, -a, old, 0, 2, m)
            good = good && wassat_rc_has(lits, offs, lens, table, -a, -x, 0, 2, m)
        return 0 unless good
        u = v + 1 ## i64
        while u < n
          m[28] += 1
          return 0 if (m[28] & 255) == 0 && wassat_reconf_stop(m, stop, deadline) != 0
          conflict = wassat_rc_has(lits, offs, lens, table, -a, -(base + u), 0, 2, m)
          i = 0 ## i64
          while i < 2 && !conflict
            j = 0 ## i64
            while j < 2 && !conflict
              s = selectors[2 * v + i] ## i64
              t = selectors[2 * u + j] ## i64
              if s > 0 && t > 0
                conflict = wassat_rc_has(lits, offs, lens, table, -s, -t, 0, 2, m)
              j += 1
            i += 1
          return 0 unless conflict
          u += 1
        v += 1
      side += 1
    step += 1
  v = 0
  while v < n
    lit = starts[count - 1] + v + 1 ## i64
    lit = -lit if (goal[v >> 6] & (one << (v & 63))) == 0
    return 0 unless wassat_rc_has(lits, offs, lens, table, lit, 0, 0, 1, m)
    v += 1
  return 0 if wassat_reconf_stop(m, stop, deadline) != 0
  m[25] = 1
  1

-> wassat_rc_verify_bytes(nc) (i64) i64
  size = 1 ## i64
  while size < 2 * nc
    size *= 2
  4 * size + 65536
