# Fixed-array propagation and exhaustive row search for decoded order-seven Latin relations.
use atomic_stop

fn wassat_qg_ctz(x) (i64) i64
  ccall_nobox("__w_bit_cttz_u64", x) ## i64

fn wassat_qg_pop(x) (i64) i64
  ccall_nobox("__w_bit_ctpop_u64", x) ## i64

-> wassat_qg_poll(m, stop) (i64[] i64[]) i64
  m[15] += 1
  if wassat_stop_load(stop) != 0
    m[8] = 1
  elsif m[9] > 0 && clock_ms() >= m[9]
    m[8] = 2
  m[8]

# State stride 2176: 49 domains, 924 active table words, 98 scope caches,
# 128 live-clause words, six live-leaf words, 924 sparse word indices,
# and 14 live-word counts. Eight levels suffice for row DFS.
-> wassat_qg_status(lit, state, base) (i64 i64[] i64) i64
  x = lit < 0 ? 0 - lit - 1 : lit - 1 ## i64
  mask = state[base + x / 7] ## i64
  bit = (1 ## i64) << (x % 7) ## i64
  v = mask == bit ? 1 : ((mask & bit) == 0 ? -1 : 0) ## i64
  lit > 0 ? v : 0 - v

-> wassat_qg_force(lit, state, base) (i64 i64[] i64) i64
  x = lit < 0 ? 0 - lit - 1 : lit - 1 ## i64
  cell = base + x / 7 ## i64
  bit = (1 ## i64) << (x % 7) ## i64
  mask = lit > 0 ? (state[cell] & bit) : (state[cell] & (127 ^ bit)) ## i64
  return -1 if mask == 0
  return 0 if mask == state[cell]
  state[cell] = mask
  1

# Returns -1 on contradiction, otherwise whether this sweep changed domains.
-> wassat_qg_clauses(first, count, state, base, offs, lens, lits, m) (i64 i64 i64[] i64 i64[] i64[] i64[] i64[]) i64
  changed = 0 ## i64
  ci = first ## i64
  while ci < first + count
    open = 0 ## i64
    last = 0 ## i64
    sat = 0 ## i64
    j = 0 ## i64
    while j < lens[ci]
      l = lits[offs[ci] + j] ## i64
      m[2] += 1
      v = wassat_qg_status(l, state, base) ## i64
      if v > 0
        sat = 1
        break
      if v == 0
        open += 1
        last = l
      j += 1
    if sat == 0
      return -1 if open == 0
      if open == 1
        r = wassat_qg_force(last, state, base) ## i64
        return -1 if r < 0
        changed |= r
    ci += 1
  changed

-> wassat_qg_primary(state, base, offs, lens, lits, m) (i64[] i64 i64[] i64[] i64[] i64[]) i64
  return wassat_qg_clauses(0, m[13], state, base, offs, lens, lits, m) if m[11] < 2
  changed = 0 ## i64
  w = 0 ## i64
  while w < (m[13] + 63) / 64
    bits = state[base + 1071 + w] ## i64
    while bits != 0
      b = wassat_qg_ctz(bits) ## i64
      bits &= bits - 1
      ci = w * 64 + b ## i64
      open = 0 ## i64
      last = 0 ## i64
      sat = 0 ## i64
      j = 0 ## i64
      while j < lens[ci]
        l = lits[offs[ci] + j] ## i64
        m[2] += 1
        v = wassat_qg_status(l, state, base) ## i64
        if v > 0
          sat = 1
          break
        if v == 0
          open += 1
          last = l
        j += 1
      if sat != 0
        state[base + 1071 + w] &= (0 - 1) ^ ((1 ## i64) << b)
      else
        return -1 if open == 0
        if open == 1
          r = wassat_qg_force(last, state, base) ## i64
          return -1 if r < 0
          changed |= r
    w += 1
  changed

-> wassat_qg_propagate(state, base, tables, supports, offs, lens, lits, leaves, groups, scratch, m, stop) (i64[] i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  changed = 1 ## i64
  while changed != 0
    changed = 0
    ci = 0 ## i64
    while ci < 14
      tb = ci * 10 ## i64
      active = base + 49 + ci * 66 ## i64
      lastbase = base + 973 + ci * 7 ## i64
      dirty = m[11] == 0 ? 1 : 0 ## i64
      pos = 0 ## i64
      while pos < 7
        dirty = 1 if state[lastbase + pos] != state[base + tables[tb + pos]]
        pos += 1
      if dirty == 0
        m[7] += 1
      else
        pos = 0
        while pos < 7
          mask = state[base + tables[tb + pos]] ## i64
          if mask != 127 && (m[11] == 0 || state[lastbase + pos] != mask)
            q = 0 ## i64
            while q < (m[11] >= 3 ? state[base + 2140 + ci] : tables[tb + 8])
              w = m[11] >= 3 ? state[base + 1216 + ci * 66 + q] : q ## i64
              u = 0 ## i64
              v = 0 ## i64
              while v < 7
                u |= supports[((ci * 7 + pos) * 7 + v) * 66 + w] if ((mask >> v) & 1) != 0
                v += 1
              state[active + w] &= u
              m[1] += 1
              if m[11] >= 3 && state[active + w] == 0
                state[base + 2140 + ci] -= 1
                state[base + 1216 + ci * 66 + q] = state[base + 1216 + ci * 66 + state[base + 2140 + ci]]
              else
                q += 1
          pos += 1
        any = 0 ## i64
        w = 0 ## i64
        while w < tables[tb + 8]
          any |= state[active + w]
          w += 1
        if any == 0
          m[4] += 1
          return -1
        pos = 0
        while pos < 7
          cell = base + tables[tb + pos] ## i64
          mask = 0 ## i64
          v = 0 ## i64
          while v < 7
            if ((state[cell] >> v) & 1) != 0
              q = 0
              while q < (m[11] >= 3 ? state[base + 2140 + ci] : tables[tb + 8])
                w = m[11] >= 3 ? state[base + 1216 + ci * 66 + q] : q
                m[1] += 1
                if (state[active + w] & supports[((ci * 7 + pos) * 7 + v) * 66 + w]) != 0
                  mask |= (1 ## i64) << v
                  break
                q += 1
            v += 1
          if mask != state[cell]
            state[cell] = mask
            changed = 1
          pos += 1
        if m[11] != 0
          pos = 0
          while pos < 7
            state[lastbase + pos] = state[base + tables[tb + pos]]
            pos += 1
      ci += 1
    r = wassat_qg_primary(state, base, offs, lens, lits, m) ## i64
    if r < 0
      m[5] += 1
      return -1
    changed |= r
    gi = 0 ## i64
    while gi < m[14]
      c = 0 ## i64
      while c < 49
        scratch[49 + c] = 0
        c += 1
      viable = 0 ## i64
      li = 0 ## i64
      while li < groups[2 * gi + 1]
        if m[11] < 2 || ((state[base + 1199 + gi] >> li) & 1) != 0
          m[3] += 1
          c = 0
          while c < 49
            scratch[c] = state[base + c]
            c += 1
          leaf = groups[2 * gi] + li ## i64
          r = 1
          while r > 0
            r = wassat_qg_clauses(leaves[2 * leaf], leaves[2 * leaf + 1], scratch, 0, offs, lens, lits, m)
          if r >= 0
            viable = 1
            c = 0
            while c < 49
              scratch[49 + c] |= scratch[c]
              c += 1
          elsif m[11] >= 2
            state[base + 1199 + gi] &= (0 - 1) ^ ((1 ## i64) << li)
        li += 1
      if viable == 0
        m[6] += 1
        return -1
      c = 0
      while c < 49
        if scratch[49 + c] != state[base + c]
          state[base + c] = scratch[49 + c]
          changed = 1
        c += 1
      gi += 1
  1

-> wassat_qg_dfs(depth, state, tables, tuples, supports, offs, lens, lits, leaves, groups, scratch, m, stop) (i64 i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  m[0] += 1
  if m[10] > 0 && m[0] > m[10]
    m[8] = 3
    return 0
  m[12] = depth if depth > m[12]
  return 0 if (m[0] & 127) == 1 && wassat_qg_poll(m, stop) != 0
  base = depth * 2176 ## i64
  r = wassat_qg_propagate(state, base, tables, supports, offs, lens, lits, leaves, groups, scratch, m, stop) ## i64
  return r if r < 0
  best = 0 - 1 ## i64
  count = 100000 ## i64
  ci = 0 ## i64
  while ci < 7
    n = 0 ## i64
    w = 0 ## i64
    while w < tables[10 * ci + 8]
      n += wassat_qg_pop(state[base + 49 + ci * 66 + w])
      w += 1
    if n > 1 && n < count
      best = ci
      count = n
    ci += 1
  return 1 if best < 0
  if depth >= 7
    m[8] = 4
    return 0
  tb = best * 10 ## i64
  w = 0 ## i64
  while w < tables[tb + 8]
    bits = state[base + 49 + best * 66 + w] ## i64
    while bits != 0
      k = w * 64 + wassat_qg_ctz(bits) ## i64
      bits &= bits - 1
      j = 0 ## i64
      while j < 2176
        state[base + 2176 + j] = state[base + j]
        j += 1
      pos = 0 ## i64
      while pos < 7
        state[base + 2176 + tables[tb + pos]] = (1 ## i64) << tuples[tables[tb + 9] + k * 7 + pos]
        pos += 1
      r = wassat_qg_dfs(depth + 1, state, tables, tuples, supports, offs, lens, lits, leaves, groups, scratch, m, stop)
      return r if r >= 0
    w += 1
  -1
