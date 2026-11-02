# Original-clause certificate for a crowded even-distance neighborhood.
# If every edge has circular distance >= k, a two-edge walk changes a label
# by at most n-2*k. A radius-2r even ball therefore occupies at most
# 2*r*(n-2*k)+1 positions. More distinct vertices certify impossibility.
# The proposed graph is not trusted: verify all row AMOs and every edge used
# in the ball against original binary clauses and their implication paths.
use permutation_walk

fn wassat_cycle_bound_ctz(x) (i64) i64
  ccall_nobox("__w_bit_cttz_u64", x) ## i64

# Reuse unused walk-counter slots: 0 certificate status,1 root,2 radius,
# 3 vertices,4 positions,5 tree edges,14 work,15 support ORs,16 rectangle rows,
# 17 coverage words,18 checked row AMOs,19 checked edges,20 bytes,21 time.
# 12/22 retain the common poll/stop contract;23 is the next work-based poll.
-> wassat_cycle_bound_poll(m, stop, deadline) (i64[] i64[] i64) i64
  return m[22] if m[22] != 0
  if m[14] > 12000000000
    m[22] = 3
    return 3
  m[23] = m[14] + 16384
  wassat_perm_stop(m, stop, deadline)

-> wassat_cycle_bound_ball(n, k, left, right, heads, occ, needed, m, stop, deadline) (i64 i64 i32[] i32[] i32[] i32[] i8[] i64[] i64[] i64) i64
  return 0 if wassat_cycle_bound_poll(m, stop, deadline) != 0
  slack = n - 2 * k
  return 0 if slack < 0 || 2 * slack + 1 >= n
  max_r = slack == 0 ? 1 : (n - 2) / (2 * slack)
  best = 2 * max_r + 2
  dist = i32[2 * n]
  parent = i32[2 * n]
  saved = i32[2 * n]
  queue = i32[2 * n]
  picked = i32[n]
  counts = i32[n + 1]
  root = 0
  found = 0
  while root < n
    return 0 if wassat_cycle_bound_poll(m, stop, deadline) != 0
    i = 0
    while i < 2 * n
      dist[i] = -1
      parent[i] = -1
      i += 1
    i = 0
    while i <= n
      counts[i] = 0
      i += 1
    queue[0] = 2 * root
    dist[2 * root] = 0
    counts[0] = 1
    at = 0
    tail = 1
    while at < tail
      s = queue[at] ## i64
      v = s / 2
      if dist[s] + 1 < best
        j = heads[v] ## i64
        while j < heads[v + 1]
          e = occ[j] ## i64
          u = left[e] ^ right[e] ^ v
          z = 2 * u + ((s & 1) ^ 1)
          if dist[z] < 0
            dist[z] = dist[s] + 1
            parent[z] = s
            queue[tail] = z
            tail += 1
            counts[dist[z] / 2] += 1 if (z & 1) == 0
          m[14] += 1
          return 0 if m[14] >= m[23] && wassat_cycle_bound_poll(m, stop, deadline) != 0
          j += 1
      at += 1
    total = 1
    r = 1
    while 2 * r < best
      total += counts[r]
      cap = 2 * r * slack + 1
      if total > cap
        found = 1
        best = 2 * r
        m[0] = 1
        m[1] = root
        m[2] = best
        m[3] = cap + 1
        m[4] = cap
        i = 0
        while i < 2 * n
          saved[i] = parent[i]
          i += 1
        i = 0
        count = 0
        while i < tail && count <= cap
          z = queue[i] ## i64
          if (z & 1) == 0 && dist[z] <= best
            picked[count] = z / 2
            count += 1
          i += 1
        return 0 if count != cap + 1
      r += 1
    root += 1
  return 0 if found == 0
  i = 0
  while i < m[3]
    s = 2 * picked[i]
    while saved[s] >= 0
      a = s / 2
      b = saved[s] / 2
      if a > b
        tmp = a
        a = b
        b = tmp
      if needed[a * n + b] == 0
        needed[a * n + b] = 1
        m[5] += 1
      s = saved[s]
    i += 1
  1

# Each support bit has a concrete chain of original positive implications
# from that row's primary variable. One numeric pass is an underapproximation:
# backward arcs and cycles may lose deductions, but cannot invent one.
-> wassat_cycle_bound_support(n, nv, words, owner, heads, dest, support, m, stop, deadline) (i64 i64 i64 i32[] i32[] i32[] i64[] i64[] i64[] i64) i64
  one = 1 ## i64
  v = 1
  while v <= n * n
    return 0 if owner[v] != (v - 1) / n + 1
    label = (v - 1) % n
    support[v * words + label / 64] = one << (label & 63)
    v += 1
  v = 1
  while v <= nv
    return 0 if (v & 255) == 0 && wassat_cycle_bound_poll(m, stop, deadline) != 0
    if owner[v] > 0
      j = heads[v] ## i64
      while j < heads[v + 1]
        u = dest[j] ## i64
        if owner[u] == owner[v]
          w = 0
          while w < words
            support[u * words + w] = support[u * words + w] | support[v * words + w]
            w += 1
          m[14] += words
          m[15] += words
          return 0 if m[14] >= m[23] && wassat_cycle_bound_poll(m, stop, deadline) != 0
        j += 1
    v += 1
  1

-> wassat_cycle_bound_rectangle(a, b, words, support, masks, cover, m) (i64 i64 i64 i64[] i32[] i64[] i64[]) i64
  rows = 0
  word_mask = masks[b] ## i64
  return 0 if word_mask == 0
  nonzero = popcount(word_mask) ## i64
  w = 0
  while w < words
    bits = support[a * words + w] ## i64
    while bits != 0
      label = 64 * w + wassat_cycle_bound_ctz(bits)
      bits = bits & (bits - 1)
      active = word_mask
      while active != 0
        t = wassat_cycle_bound_ctz(active)
        active = active & (active - 1)
        cover[label * words + t] = cover[label * words + t] | support[b * words + t]
      rows += 1
    w += 1
  m[16] += rows
  m[14] += rows * nonzero
  0

# The caller has already checked n complete positive matrix columns. Row
# AMOs then force a bijection by counting: n nonempty columns consume n rows,
# each of capacity one. Consequently every row/column contains exactly one.
-> wassat_cycle_bound_verify(lits, offs, lens, nv, nc, n, k, owner, heads, dest, needed, masks, m, stop, deadline) (i64[] i64[] i64[] i64 i64 i64 i64 i32[] i32[] i32[] i8[] i32[] i64[] i64[] i64) i64
  return 0 if wassat_cycle_bound_poll(m, stop, deadline) != 0
  words = (n + 63) / 64
  support = i64[(nv + 1) * words]
  groups = i32[n * n]
  next_clause = i32[nc]
  cover = i64[n * words]
  required = i64[words]
  m[20] = 8 * (nv + 1) * words + 4 * n * n + 4 * nc + 8 * (n + 1) * words
  return 0 unless wassat_cycle_bound_support(n, nv, words, owner, heads, dest, support, m, stop, deadline) == 1
  # The implication builder's fill slab is dead scratch now. Cache nonzero
  # support words there: short intervals otherwise OR many zero words into
  # each row of the coverage matrix. This adds no allocation or graph work.
  one = 1 ## i64
  v = 1
  while v <= nv
    return 0 if (v & 255) == 0 && wassat_cycle_bound_poll(m, stop, deadline) != 0
    mask = 0 ## i64
    w = 0
    while w < words
      mask = mask | (one << w) if support[v * words + w] != 0
      w += 1
    masks[v] = mask
    m[14] += words
    v += 1
  ci = 0
  while ci < nc
    return 0 if (ci & 4095) == 0 && wassat_cycle_bound_poll(m, stop, deadline) != 0
    if lens[ci] == 2
      off = offs[ci] ## i64
      a = lits[off] ## i64
      b = lits[off + 1] ## i64
      if a < 0 && b < 0
        x = owner[-a] - 1
        y = owner[-b] - 1
        if x >= 0 && y >= 0
          if x > y
            tmp = x
            x = y
            y = tmp
          if x == y || needed[x * n + y] != 0
            key = x * n + y
            next_clause[ci] = groups[key]
            groups[key] = ci + 1
    ci += 1
  one = 1 ## i64
  full = -1 ## i64
  last = ((n & 63) == 0 ? full : (one << (n & 63)) - 1) ## i64
  x = 0
  while x < n
    y = x
    while y < n
      if x == y || needed[x * n + y] != 0
        return 0 if wassat_cycle_bound_poll(m, stop, deadline) != 0
        i = 0
        while i < n * words
          cover[i] = 0
          i += 1
        entry = groups[x * n + y] ## i64
        while entry > 0
          ci = entry - 1
          off = offs[ci] ## i64
          a = -lits[off]
          b = -lits[off + 1]
          if owner[a] > owner[b]
            tmp = a
            a = b
            b = tmp
          z = wassat_cycle_bound_rectangle(a, b, words, support, masks, cover, m)
          z = wassat_cycle_bound_rectangle(b, a, words, support, masks, cover, m) if x == y
          return 0 if m[14] >= m[23] && wassat_cycle_bound_poll(m, stop, deadline) != 0
          entry = next_clause[ci]
        p = 0
        while p < n
          w = 0
          while w < words
            required[w] = w + 1 == words ? last : full
            w += 1
          if x == y
            required[p / 64] = required[p / 64] & (full ^ (one << (p & 63)))
          else
            q = k
            while q <= n - k
              label = (p + q) % n
              required[label / 64] = required[label / 64] & (full ^ (one << (label & 63)))
              q += 1
          w = 0
          while w < words
            return 0 if (required[w] & (full ^ cover[p * words + w])) != 0
            w += 1
          m[14] += words
          m[17] += words
          return 0 if m[14] >= m[23] && wassat_cycle_bound_poll(m, stop, deadline) != 0
          p += 1
        if x == y
          m[18] += 1
        else
          m[19] += 1
      y += 1
    x += 1
  return 0 if m[18] != n || m[19] != m[5]
  return 0 if wassat_cycle_bound_poll(m, stop, deadline) != 0
  m[0] = -1
  -1
