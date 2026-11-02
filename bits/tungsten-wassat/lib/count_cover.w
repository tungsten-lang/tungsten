# Bounded covering search over a clause-checked monotone circuit.
# Complete AND/OR/majority definitions make each scheduled output a function
# of the free inputs. A ROBDD of original negative assertions supplies an
# upper bound on the number of true inputs. Positive input clauses supply
# covering constraints. Ignoring other assertions only relaxes the formula:
# exhaustive failure refutes it; a surviving cover is UNKNOWN, never SAT.
# Fixed per-depth buffers are reused throughout search. Explicit machine
# locals keep high-bit masks and BDD cache keys out of boxed integer storage.
use atomic_stop

# m: BDD nodes, node cap, stop (1 cancel,2 deadline,3 capacity,4 work),
# apply work, deadline, search nodes, search cap, cover rows, inputs, gates,
# count bound, polls, clause visits, hash probes, cache hits, forces,
# packing prunes, negative assertions, recognition ms, search ms, witness,
# maximum depth, status, definition probes, total ms, BDD work cap,
# search row visits, BDD negation visits.
-> wassat_cc_poll(m, stop) (i64[] i64[]) i64
  m[11] += 1
  if wassat_stop_load(stop) != 0
    m[2] = 1
  elsif m[4] > 0 && clock_ms() >= m[4]
    m[2] = 2
  m[2]

-> wassat_cc_mk(v, lo, hi, nodes, unique, m) (i64 i64 i64 i64[] i32[] i64[]) i64
  mask = 0 ## i64
  h = 0 ## i64
  n = 0 ## i64
  a = 0 ## i64
  return 0 if m[2] != 0
  return lo if lo == hi
  mask = unique.size - 1
  h = ((v * 73856093) ^ (lo * 19349663) ^ (hi * 83492791)) & mask
  n = 0
  while n < 128
    m[13] += 1
    a = unique[h] ## i64
    if a == 0
      if m[0] >= m[1]
        m[2] = 3
        return 0
      a = m[0]
      m[0] += 1
      nodes[3 * a] = v
      nodes[3 * a + 1] = lo
      nodes[3 * a + 2] = hi
      unique[h] = a
      return a
    return a if nodes[3 * a] == v && nodes[3 * a + 1] == lo && nodes[3 * a + 2] == hi
    h = (h + 1) & mask
    n += 1
  m[2] = 3
  0

-> wassat_cc_and(a, b, nodes, unique, cache, m, stop) (i64 i64 i64[] i32[] i64[] i64[] i64[]) i64
  t = 0 ## i64
  key = 0 ## i64
  mask = 0 ## i64
  h = 0 ## i64
  probes = 0 ## i64
  av = 0 ## i64
  bv = 0 ## i64
  v = 0 ## i64
  al = 0 ## i64
  ah = 0 ## i64
  bl = 0 ## i64
  bh = 0 ## i64
  lo = 0 ## i64
  hi = 0 ## i64
  r = 0 ## i64
  return 0 if m[2] != 0 || a == 0 || b == 0
  return b if a == 1
  return a if b == 1 || a == b
  if a > b
    t = a
    a = b
    b = t
  m[3] += 1
  if (m[3] & 1023) == 1
    return 0 if wassat_cc_poll(m, stop) != 0
    if m[3] > m[25]
      m[2] = 4
      return 0
  key = (a << 32) | b
  mask = (cache.size / 2) - 1
  h = ((a * 73856093) ^ (b * 19349663)) & mask
  probes = 0
  while cache[2 * h] != 0 && cache[2 * h] != key && probes < 128
    h = (h + 1) & mask
    probes += 1
  if probes >= 128
    m[2] = 3
    return 0
  if cache[2 * h] == key
    m[14] += 1
    return cache[2 * h + 1]
  av = nodes[3 * a]
  bv = nodes[3 * b]
  v = av < bv ? av : bv
  al = av == v ? nodes[3 * a + 1] : a
  ah = av == v ? nodes[3 * a + 2] : a
  bl = bv == v ? nodes[3 * b + 1] : b
  bh = bv == v ? nodes[3 * b + 2] : b
  lo = wassat_cc_and(al, bl, nodes, unique, cache, m, stop)
  hi = wassat_cc_and(ah, bh, nodes, unique, cache, m, stop)
  r = wassat_cc_mk(v, lo, hi, nodes, unique, m)
  # Recursion may fill the previously empty slot. A direct mapped overwrite
  # is safe for memoization; key and result are replaced together privately.
  cache[2 * h] = key
  cache[2 * h + 1] = r
  r

-> wassat_cc_not(a, nodes, unique, inv, m, stop) (i64 i64[] i32[] i32[] i64[] i64[]) i64
  lo = 0 ## i64
  hi = 0 ## i64
  r = 0 ## i64
  return 0 if m[2] != 0
  m[27] += 1
  return 0 if (m[27] & 1023) == 1 && wassat_cc_poll(m, stop) != 0
  return 1 - a if a < 2
  return inv[a] if inv[a] != 0
  lo = wassat_cc_not(nodes[3 * a + 1], nodes, unique, inv, m, stop)
  hi = wassat_cc_not(nodes[3 * a + 2], nodes, unique, inv, m, stop)
  r = wassat_cc_mk(nodes[3 * a], lo, hi, nodes, unique, m)
  inv[a] = r
  r

-> wassat_cc_or(a, b, nodes, unique, cache, inv, m, stop) (i64 i64 i64[] i32[] i64[] i32[] i64[] i64[]) i64
  na = 0 ## i64
  nb = 0 ## i64
  r = 0 ## i64
  na = wassat_cc_not(a, nodes, unique, inv, m, stop)
  nb = wassat_cc_not(b, nodes, unique, inv, m, stop)
  r = wassat_cc_and(na, nb, nodes, unique, cache, m, stop)
  wassat_cc_not(r, nodes, unique, inv, m, stop)

# Clause keys are padded to four signed literals and sorted, including zeros.
-> wassat_cc_lookup(a, b, c, d, keys, slots, m) (i64 i64 i64 i64 i64[] i32[] i64[]) i64
  t = 0 ## i64
  mask = 0 ## i64
  h = 0 ## i64
  tries = 0 ## i64
  ci = 0 ## i64
  p = 0 ## i64
  if a > b
    t = a; a = b; b = t
  if c > d
    t = c; c = d; d = t
  if a > c
    t = a; a = c; c = t
  if b > d
    t = b; b = d; d = t
  if b > c
    t = b; b = c; c = t
  mask = slots.size - 1
  h = ((a * 73856093) ^ (b * 19349663) ^ (c * 83492791) ^ (d * 49979687)) & mask
  tries = 0
  while tries < 128
    m[23] += 1
    ci = (slots[h] ## i64) - 1
    return -1 if ci < 0
    p = 4 * ci
    return ci if keys[p] == a && keys[p + 1] == b && keys[p + 2] == c && keys[p + 3] == d
    h = (h + 1) & mask
    tries += 1
  -1

-> wassat_cc_decode(lits, offs, lens, nv, nc, gates, inputs, m, stop) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[]) i64
  cap = 0 ## i64
  ci = 0 ## i64
  n = 0 ## i64
  j = 0 ## i64
  l = 0 ## i64
  v = 0 ## i64
  k = 0 ## i64
  p = 0 ## i64
  h = 0 ## i64
  tries = 0 ## i64
  pos = 0 ## i64
  neg = 0 ## i64
  pv = 0 ## i64
  nvx = 0 ## i64
  kind = 0 ## i64
  out = 0 ## i64
  valid = 0 ## i64
  count = 0 ## i64
  a = 0 ## i64
  b = 0 ## i64
  c = 0 ## i64
  x = 0 ## i64
  y = 0 ## i64
  z = 0 ## i64
  cap = 1
  while cap < 4 * nc
    cap *= 2
  keys = i64[4 * nc]
  slots = i32[cap]
  pairs = i64[9 * (nv + 1)]
  ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_cc_poll(m, stop) != 0
    n = lens[ci]
    return 0 if n < 1 || n > 4
    j = 0
    while j < n
      l = lits[offs[ci] + j]
      v = l < 0 ? 0 - l : l
      return 0 if v < 1 || v > nv
      keys[4 * ci + j] = l
      j += 1
    j = 1
    while j < 4
      l = keys[4 * ci + j]
      k = j
      while k > 0 && keys[4 * ci + k - 1] > l
        keys[4 * ci + k] = keys[4 * ci + k - 1]
        k -= 1
      keys[4 * ci + k] = l
      j += 1
    p = 4 * ci
    h = ((keys[p] * 73856093) ^ (keys[p + 1] * 19349663) ^ (keys[p + 2] * 83492791) ^ (keys[p + 3] * 49979687)) & (cap - 1)
    tries = 0
    while slots[h] != 0
      h = (h + 1) & (cap - 1)
      tries += 1
      return 0 if tries >= 128
    slots[h] = ci + 1
    m[12] += 1
    ci += 1
  ci = 0
  ins = i64[3]
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_cc_poll(m, stop) != 0
    n = lens[ci]
    if n >= 3
      pos = 0
      neg = 0
      pv = 0
      nvx = 0
      j = 0
      while j < n
        l = lits[offs[ci] + j]
        if l > 0
          pos += 1
          pv = l
        else
          neg += 1
          nvx = 0 - l
        j += 1
      kind = pos == 1 ? 1 : (neg == 1 ? 2 : 0)
      out = kind == 1 ? pv : nvx
      if kind > 0
        valid = 1
        count = 0
        j = 0
        while j < n
          l = lits[offs[ci] + j]
          if (kind == 1 && l < 0) || (kind == 2 && l > 0)
            v = l < 0 ? 0 - l : l
            valid = 0 if v == out
            k = 0
            while k < count
              valid = 0 if ins[k] == v
              k += 1
            ins[count] = v
            count += 1
            a = kind == 1 ? 0 - out : out
            b = kind == 1 ? v : 0 - v
            valid = 0 if wassat_cc_lookup(a, b, 0, 0, keys, slots, m) < 0
          j += 1
        if valid == 1 && gates[4 * out] == 0
          gates[4 * out] = kind
          gates[4 * out + 1] = ins[0]
          gates[4 * out + 2] = ins[1]
          gates[4 * out + 3] = count == 3 ? ins[2] : 0
        if pos == 1 && neg == 2
          j = 0
          while j < 2
            v = ins[j]
            p = 9 * out
            k = 0
            while k < pairs[p] && k < 8 && pairs[p + 1 + k] != v
              k += 1
            if k == pairs[p] && k < 8
              pairs[p + 1 + k] = v
              pairs[p] += 1
            elsif k == 8
              pairs[p] = 9
            j += 1
    ci += 1
  v = 1
  while v <= nv
    return 0 if (v & 15) == 1 && wassat_cc_poll(m, stop) != 0
    p = 9 * v
    if gates[4 * v] == 0 && pairs[p] <= 8
      a = 0
      while a < pairs[p] && gates[4 * v] == 0
        b = a + 1
        while b < pairs[p] && gates[4 * v] == 0
          c = b + 1
          while c < pairs[p] && gates[4 * v] == 0
            x = pairs[p + 1 + a]
            y = pairs[p + 1 + b]
            z = pairs[p + 1 + c]
            if x != v && y != v && z != v
              good = wassat_cc_lookup(v, 0 - x, 0 - y, 0, keys, slots, m) >= 0 && wassat_cc_lookup(0 - v, x, y, 0, keys, slots, m) >= 0
              good = good && wassat_cc_lookup(v, 0 - x, 0 - z, 0, keys, slots, m) >= 0 && wassat_cc_lookup(0 - v, x, z, 0, keys, slots, m) >= 0
              good = good && wassat_cc_lookup(v, 0 - y, 0 - z, 0, keys, slots, m) >= 0 && wassat_cc_lookup(0 - v, y, z, 0, keys, slots, m) >= 0
              if good
                gates[4 * v] = 3
                gates[4 * v + 1] = x
                gates[4 * v + 2] = y
                gates[4 * v + 3] = z
            c += 1
          b += 1
        a += 1
    if gates[4 * v] == 0
      return 0 if m[8] >= 63
      inputs[m[8]] = v
      m[8] += 1
    v += 1
  m[8] > 0 ? 1 : 0

-> wassat_cc_bound(lits, offs, lens, nv, nc, gates, inputs, covers, m, stop) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  v = 0 ## i64
  i = 0 ## i64
  added = 0 ## i64
  p = 0 ## i64
  kind = 0 ## i64
  a = 0 ## i64
  b = 0 ## i64
  c = 0 ## i64
  x = 0 ## i64
  y = 0 ## i64
  z = 0 ## i64
  r = 0 ## i64
  xy = 0 ## i64
  either = 0 ## i64
  ze = 0 ## i64
  root = 0 ## i64
  ci = 0 ## i64
  negative = 0 ## i64
  positive = 0 ## i64
  mask = 0 ## i64
  j = 0 ## i64
  l = 0 ## i64
  both = 0 ## i64
  clause = 0 ## i64
  lo = 0 ## i64
  hi = 0 ## i64
  nodes = i64[3 * m[1]]
  unique = i32[2 * m[1]]
  cache = i64[8 * m[1]]
  inv = i32[m[1]]
  vals = i64[nv + 1]
  known = i8[nv + 1]
  index = i8[nv + 1]
  v = 0
  while v <= nv
    index[v] = -1
    v += 1
  m[0] = 2
  nodes[0] = m[8]
  nodes[3] = m[8]
  i = 0
  while i < m[8]
    v = inputs[i]
    vals[v] = wassat_cc_mk(i, 0, 1, nodes, unique, m)
    known[v] = 1
    index[v] = i
    i += 1
  added = 1
  while added > 0
    added = 0
    v = 1
    while v <= nv
      return 0 if (v & 15) == 1 && wassat_cc_poll(m, stop) != 0
      p = 4 * v
      kind = gates[p]
      a = gates[p + 1]
      b = gates[p + 2]
      c = gates[p + 3]
      if known[v] == 0 && kind > 0 && known[a] != 0 && known[b] != 0 && (c == 0 || known[c] != 0)
        x = vals[a]
        y = vals[b]
        z = vals[c]
        if kind == 1
          r = wassat_cc_and(x, y, nodes, unique, cache, m, stop)
          r = wassat_cc_and(r, z, nodes, unique, cache, m, stop) if c != 0
        elsif kind == 2
          r = wassat_cc_or(x, y, nodes, unique, cache, inv, m, stop)
          r = wassat_cc_or(r, z, nodes, unique, cache, inv, m, stop) if c != 0
        else
          xy = wassat_cc_and(x, y, nodes, unique, cache, m, stop)
          either = wassat_cc_or(x, y, nodes, unique, cache, inv, m, stop)
          ze = wassat_cc_and(z, either, nodes, unique, cache, m, stop)
          r = wassat_cc_or(xy, ze, nodes, unique, cache, inv, m, stop)
        return 0 if m[2] != 0
        vals[v] = r
        known[v] = 1
        m[9] += 1
        added += 1
      v += 1
  root = 1
  ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_cc_poll(m, stop) != 0
    negative = 1
    positive = 1
    mask = 0
    j = 0
    while j < lens[ci]
      l = lits[offs[ci] + j]
      v = l < 0 ? 0 - l : l
      negative = 0 if l > 0 || known[v] == 0
      if l < 0 || index[v] < 0
        positive = 0
      else
        mask |= (1 ## i64) << (index[v] ## i64)
      j += 1
    if positive == 1
      return 0 if m[7] >= 1024
      covers[m[7]] = mask
      m[7] += 1
    if negative == 1
      # A negative clause is the negation of the conjunction of its outputs.
      both = 1
      j = 0
      while j < lens[ci]
        v = 0 - lits[offs[ci] + j]
        both = wassat_cc_and(both, vals[v], nodes, unique, cache, m, stop)
        j += 1
      clause = wassat_cc_not(both, nodes, unique, inv, m, stop)
      root = wassat_cc_and(root, clause, nodes, unique, cache, m, stop)
      m[17] += 1
      return 0 if m[2] != 0
    ci += 1
  return 0 if m[17] == 0 || m[7] == 0
  if root == 0
    m[10] = -1
    return 1
  # Maximize the number of true inputs accepted by the assertion ROBDD.
  # Skipped variables are free and can all be true, including above the root.
  best = i8[m[0]]
  best[0] = -64
  i = 2
  while i < m[0]
    return 0 if (i & 1023) == 0 && wassat_cc_poll(m, stop) != 0
    v = nodes[3 * i]
    lo = nodes[3 * i + 1]
    hi = nodes[3 * i + 2]
    a = (best[lo] ## i64) + nodes[3 * lo] - v - 1
    b = (best[hi] ## i64) + nodes[3 * hi] - v
    best[i] = a > b ? a : b
    i += 1
  m[10] = (best[root] ## i64) + nodes[3 * root]
  # Stable numeric ordering removes dependence on input clause order.
  i = 1
  while i < m[7]
    return 0 if (i & 63) == 0 && wassat_cc_poll(m, stop) != 0
    x = covers[i]
    j = i
    while j > 0 && covers[j - 1] > x
      covers[j] = covers[j - 1]
      j -= 1
    covers[j] = x
    i += 1
  1

fn wassat_cc_pop(x) (i64) i64
  ccall_nobox("__w_bit_ctpop_u64", x) ## i64

fn wassat_cc_ctz(x) (i64) i64
  ccall_nobox("__w_bit_cttz_u64", x) ## i64

-> wassat_cc_search(covers, scratch, occurrences, orders, m, stop, yes, no, left, depth, nr) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64 i64) i64
  base = 0 ## i64
  count = 0 ## i64
  changed = 0 ## i64
  ci = 0 ## i64
  c = 0 ## i64
  f = 0 ## i64
  width = 0 ## i64
  j = 0 ## i64
  ob = 0 ## i64
  i = 0 ## i64
  packed = 0 ## i64
  lb = 0 ## i64
  q = 0 ## i64
  v = 0 ## i64
  edge = 0 ## i64
  best = 0 ## i64
  score = 0 ## i64
  order_base = 0 ## i64
  open_count = 0 ## i64
  bit = 0 ## i64
  result = 0 ## i64
  m[5] += 1
  m[21] = depth if depth > m[21]
  if (m[5] & 255) == 1
    return 0 if wassat_cc_poll(m, stop) != 0
  if m[5] > m[6]
    m[2] = 4
    return 0
  return -1 if left < 0
  base = depth * m[7]
  count = 0
  changed = 1
  while changed != 0
    changed = 0
    count = 0
    ci = 0
    while ci < nr
      c = depth == 0 ? covers[ci] : scratch[(depth - 1) * m[7] + ci]
      m[26] += 1
      if (c & yes) == 0
        f = c & (-1 ^ no)
        return -1 if f == 0
        if (f & (f - 1)) == 0
          yes |= f
          left -= 1
          m[15] += 1
          return -1 if left < 0
          changed = 1
        else
          # Children inherit only still-uncovered rows, preserving original
          # row order. No child scans rows already satisfied by an ancestor.
          scratch[base + count] = f
          count += 1
      ci += 1
  if count == 0
    m[20] = yes
    return 1
  return -1 if left == 0
  ob = depth * 63
  i = 0
  while i < 63
    occurrences[ob + i] = 0
    i += 1
  packed = 0
  lb = 0
  i = 0
  while i < count
    c = scratch[base + i]
    q = c
    while q != 0
      v = wassat_cc_ctz(q)
      occurrences[ob + v] += 1
      q &= q - 1
    i += 1
  # Width buckets retain the full-scan kernel's stable packing order.
  width = 2
  while width <= 4
    i = 0
    while i < count
      c = scratch[base + i]
      if wassat_cc_pop(c) == width && (c & packed) == 0
        packed |= c
        lb += 1
        if lb > left
          m[16] += 1
          return -1
      i += 1
    width += 1
  edge = 0
  best = -1
  i = 0
  while i < count
    c = scratch[base + i]
    score = 10000 * (5 - wassat_cc_pop(c))
    q = c
    while q != 0
      score += occurrences[ob + wassat_cc_ctz(q)]
      q &= q - 1
    if score > best
      best = score
      edge = c
    i += 1
  open_count = count
  order_base = depth * 4
  count = 0
  while edge != 0
    v = wassat_cc_ctz(edge)
    j = count
    while j > 0 && occurrences[ob + orders[order_base + j - 1]] < occurrences[ob + v]
      orders[order_base + j] = orders[order_base + j - 1]
      j -= 1
    orders[order_base + j] = v
    count += 1
    edge &= edge - 1
  i = 0
  while i < count
    bit = (1 ## i64) << orders[order_base + i]
    result = wassat_cc_search(covers, scratch, occurrences, orders, m, stop, yes | bit, no, left - 1, depth + 1, open_count)
    return result if result != -1
    no |= bit
    i += 1
  -1

-> wassat_count_cover_run(lits, offs, lens, nv, nc, m, stop, deadline, node_cap, bdd_cap) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64 i64 i64) i64
  i = 0 ## i64
  start = 0 ## i64
  ok = 0 ## i64
  result = 0 ## i64
  i = 0
  while i < 28
    m[i] = 0
    i += 1
  start = clock_ms()
  m[1] = bdd_cap
  m[4] = deadline
  m[4] = start + 250 if deadline == 0 || deadline > start + 250
  m[6] = node_cap
  m[25] = 8000000
  return 0 if wassat_cc_poll(m, stop) != 0
  # The hash tables require a power-of-two capacity. Bounds also limit all
  # recursion to 63 input decisions and all worker-owned scratch allocations.
  return 0 if nv < 1 || nv > 4096 || nc < 1 || nc > 16000
  return 0 if bdd_cap < 128 || bdd_cap > 262144 || (bdd_cap & (bdd_cap - 1)) != 0
  gates = i64[4 * (nv + 1)]
  inputs = i64[63]
  covers = i64[nc]
  ok = wassat_cc_decode(lits, offs, lens, nv, nc, gates, inputs, m, stop)
  return 0 if ok == 0
  ok = wassat_cc_bound(lits, offs, lens, nv, nc, gates, inputs, covers, m, stop)
  m[18] = clock_ms() - start
  return 0 if ok == 0 || m[2] != 0
  m[4] = deadline
  scratch = i64[64 * m[7]]
  occurrences = i64[64 * 63]
  orders = i64[64 * 4]
  result = wassat_cc_search(covers, scratch, occurrences, orders, m, stop, 0, 0, m[10], 0, m[7])
  m[19] = clock_ms() - start - m[18]
  m[24] = clock_ms() - start
  m[22] = result
  result == -1 && m[2] == 0 ? 1 : 0

WASSAT_COUNT_COVER_BYTES = 33554432

# Admission is constant-time; all clause inspection and large scratch belong
# to the worker. This arm shares the existing circuit result slot and never
# delays a completed race to finish an unsuccessful search.
-> wassat_count_cover_plan(formula)
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return nil if nv < 1 || nv > 4096 || nc < 1 || nc > 16000
  { "count_cover": true, "meta": i64[28] }

-> wassat_count_cover_arm(lits, offs, lens, meta, stop, res, base, nv, nc) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64) i64
  start = clock_ms()
  res[base + nv + 6] = start
  hit = wassat_count_cover_run(lits, offs, lens, nv, nc, meta, stop, start + 10000, 20000000, 262144)
  res[base + nv + 5] = clock_ms()
  if hit == 1
    z = ccall("__w_arr_store_rel", res, base, -1)
    won = wassat_stop_publish(stop, -1)
  hit

-> wassat_count_cover_profile(m)
  wassat_prof_note("race.count_cover inputs=[m[8]] gates=[m[9]] rows=[m[7]] bound=[m[10]] bdd_nodes=[m[0]] apply_work=[m[3]] negation_visits=[m[27]] cache_hits=[m[14]] unique_probes=[m[13]] definition_probes=[m[23]] assertions=[m[17]] nodes=[m[5]] row_visits=[m[26]] forced=[m[15]] packing_prunes=[m[16]] max_depth=[m[21]] polls=[m[11]] stopped=[m[2]] result=[m[22]] recognition_ms=[m[18]] search_ms=[m[19]]")
