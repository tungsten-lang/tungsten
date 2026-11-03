# Bounded bipartite bandwidth proposal. Degree-ordered breadth-first visits
# order the two color classes; put those orders on opposite arcs of the circle.
# Graph checks are only a proposal: the caller must replay the original CNF.
use permutation_walk

-> wassat_cycle_order(n, ne, width, left, right, heads, matrix, perm, m, stats, stop, deadline) (i64 i64 i64 i32[] i32[] i32[] i8[] i32[] i64[] i64[] i64[] i64) i64
  i = 0 ## i64
  while i < 8
    stats[i] = 0
    i += 1
  return 0 if n < 4 || n > 1024 || ne < 1 || width < 1 || width > n / 2
  return 0 if heads.size < n + 1 || matrix.size < n * n || perm.size < n || left.size < ne || right.size < ne
  if wassat_perm_stop(m, stop, deadline) != 0
    stats[7] = m[22]
    return 0
  order = i32[n]
  queue = i32[n]
  color = i8[n]
  counts = i32[n + 1]
  v = 0 ## i64
  while v < n
    d = (heads[v + 1] - heads[v]) ## i64
    return 0 if d < 0 || d >= n
    counts[d] += 1
    v += 1
  at = 0 ## i64
  d = 0 ## i64
  while d < n
    count = counts[d] ## i64
    counts[d] = at
    at += count
    d += 1
  v = 0
  while v < n
    d = heads[v + 1] - heads[v]
    order[counts[d]] = v
    counts[d] += 1
    v += 1
  tries = n < 8 ? n : 8
  attempt = 0 ## i64
  while attempt < tries
    stats[1] += 1
    v = 0
    while v < n
      color[v] = -1
      v += 1
    at = 0
    tail = 0 ## i64
    part = 0 ## i64
    root = order[attempt] ## i64
    next_root = 0 ## i64
    while at < n
      if at == tail
        if tail != 0
          while next_root < n && color[order[next_root]] >= 0
            next_root += 1
          return 0 if next_root >= n
          root = order[next_root]
        color[root] = 0
        queue[tail] = root
        tail += 1
        part += 1
      v = queue[at]
      at += 1
      stats[2] += 1
      j = 0 ## i64
      while j < n
        stats[3] += 1
        if (stats[3] & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
          stats[7] = m[22]
          return 0
        u = order[j] ## i64
        a = v < u ? v : u
        b = v < u ? u : v
        if matrix[a * n + b] != 0
          if color[u] < 0
            color[u] = color[v] ^ 1
            queue[tail] = u
            tail += 1
            part += 1 if color[u] == 0
          elsif color[u] == color[v]
            return 0
        j += 1
    stats[5] = part
    stats[6] = n - part
    a = 0
    b = part
    j = 0
    while j < n
      v = queue[j]
      if color[v] == 0
        perm[v] = a
        a += 1
      else
        perm[v] = b
        b += 1
      j += 1
    valid = true
    e = 0 ## i64
    while e < ne && valid
      if (e & 4095) == 0 && wassat_perm_stop(m, stop, deadline) != 0
        stats[7] = m[22]
        return 0
      a = left[e]
      b = right[e]
      return 0 if a < 0 || b < 0 || a >= n || b >= n
      delta = (perm[a] ## i64) - (perm[b] ## i64)
      delta = -delta if delta < 0
      delta = n - delta if delta > n - delta
      valid = false if delta < width
      stats[4] += 1
      e += 1
    if valid
      stats[0] = 1
      return 1
    attempt += 1
  0
