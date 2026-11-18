-> wassat_ramsey_count(m) (i64) i64
  ccall_nobox("__w_bit_ctpop_u64", m) ## i64

-> wassat_ramsey_first(m) (i64) i64
  ccall_nobox("__w_bit_cttz_u64", m) ## i64

# Equitable refinement splits an ordered partition by neighbor counts.
# Individualize one vertex in the first tied cell. Swapping twins preserves
# all edges. The minimum of the resulting complete adjacency words is an
# isomorphism invariant; equality of the words gives an explicit labeling.
-> wassat_ramsey_seed_key(g, cells, count, best) (i64[] i64[] i64 i64[]) i64
  n = g.size
  next_cells = i64[n]
  signature = i64[n]
  while count < n
    v = 0
    while v < n
      value = 0
      j = 0
      while j < count
        value = (value << 4) + wassat_ramsey_count(g[v] & cells[j])
        j += 1
      signature[v] = value
      v += 1
    used = 0
    j = 0
    while j < count
      left = cells[j]
      while left != 0
        s = left
        lowest = signature[wassat_ramsey_first(s)]
        part = 0
        while s != 0
          v = wassat_ramsey_first(s)
          if signature[v] < lowest
            lowest = signature[v]
            part = 0
          part |= 1 << v if signature[v] == lowest
          s &= s - 1
        next_cells[used] = part
        used += 1
        left ^= part
      j += 1
    break if used == count
    swap = cells
    cells = next_cells
    next_cells = swap
    count = used
  j = 0
  while j < count
    tied = cells[j]
    if (tied & (tied - 1)) != 0
      tried = 0
      remaining = tied
      while remaining != 0
        v = wassat_ramsey_first(remaining)
        b = 1 << v
        earlier = tried
        twin = false
        while earlier != 0
          u = wassat_ramsey_first(earlier)
          if ((g[v] ^ g[u]) & (-1 ^ (b | (1 << u)))) == 0
            twin = true
            break
          earlier &= earlier - 1
        unless twin
          child = i64[n]
          t = 0
          while t < count
            if t < j
              child[t] = cells[t]
            elsif t > j
              child[t + 1] = cells[t]
            else
              child[t] = b
              child[t + 1] = tied ^ b
            t += 1
          wassat_ramsey_seed_key(g, child, count + 1, best)
          tried |= b
        remaining &= remaining - 1
      return 0
    j += 1
  high = 0
  low = 0
  pos = 0
  j = 1
  while j < n
    row = g[wassat_ramsey_first(cells[j])]
    i = 0
    while i < j
      if (row & cells[i]) != 0
        if pos < 55
          low |= 1 << pos
        else
          high |= 1 << (pos - 55)
      pos += 1
      i += 1
    j += 1
  if best[0] < 0 || high < best[0] || (high == best[0] && low < best[1])
    best[0] = high
    best[1] = low
  0

-> wassat_ramsey_subset_alpha(g) (i64[]) i64[]
  size = 1 << g.size
  alpha = i64[size]
  s = 1
  while s < size
    v = wassat_ramsey_first(s)
    rest = s & (s - 1)
    with_v = 1 + alpha[rest & (-1 ^ g[v])]
    alpha[s] = with_v > alpha[rest] ? with_v : alpha[rest]
    s += 1
  alpha

# Every induced subgraph also avoids both forbidden sets. New neighbors
# must be independent, and every old independent four-set must meet them.
-> wassat_ramsey_small_seeds(deadline, stats)
  current = [i64[0]]
  seeds = []
  n = 0
  while n < 14
    following = []
    keys = {}
    i = 0
    while i < current.size
      return nil if deadline > 0 && clock_ms() >= deadline
      g = current[i] ## i64[]
      alpha = wassat_ramsey_subset_alpha(g)
      all = (1 << n) - 1
      s = 0
      while s <= all
        if alpha[s] == wassat_ramsey_count(s) && alpha[all ^ s] < 4
          child = i64[n + 1]
          child[n] = s
          v = 0
          while v < n
            child[v] = g[v]
            child[v] |= 1 << n if (s & (1 << v)) != 0
            v += 1
          cells = i64[n + 1]
          cells[0] = (1 << (n + 1)) - 1
          best = i64[2]
          best[0] = -1
          wassat_ramsey_seed_key(child, cells, 1, best)
          key = "[best[0]]/[best[1]]"
          unless keys.has_key?(key)
            keys[key] = true
            following.push(child)
            seeds.push(child) if n + 1 >= 12
        s += 1
      i += 1
    n += 1
    stats[n] = following.size
    current = following
  return nil if current.size > 0
  seeds
