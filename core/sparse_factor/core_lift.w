# Typed leaf kernels for SparseAnalysis's sparse degree-bounded core lift.
# This internal module keeps calls statically bound and hash/heap traffic on
# raw integer arrays in native builds.

-> sparse_core_edge_hash(key, mask) (i64 i64) i64
  x = key ^ (key >> 17)
  x = x * 33
  (x ^ (x >> 11)) & mask

-> sparse_core_edge_contains(keys, mask, key) (i64[] i64 i64) bool
  pos = sparse_core_edge_hash(key, mask)
  probes = 0
  while probes <= mask
    slot = keys[pos]
    return false if slot == 0
    return true if slot == key
    pos = (pos + 1) & mask
    probes += 1
  false

# Returns 1 for a new edge, 0 for an existing edge, and -1 when the bounded
# table has no reusable slot.
-> sparse_core_edge_insert(keys, mask, key) (i64[] i64 i64) i64
  pos = sparse_core_edge_hash(key, mask)
  first_tomb = -1
  probes = 0
  while probes <= mask
    slot = keys[pos]
    if slot == 0
      pos = first_tomb if first_tomb >= 0
      keys[pos] = key
      return 1
    return 0 if slot == key
    first_tomb = pos if slot == 1 && first_tomb < 0
    pos = (pos + 1) & mask
    probes += 1
  if first_tomb >= 0
    keys[first_tomb] = key
    return 1
  -1

-> sparse_core_edge_remove(keys, mask, key) (i64[] i64 i64) bool
  pos = sparse_core_edge_hash(key, mask)
  probes = 0
  while probes <= mask
    slot = keys[pos]
    return false if slot == 0
    if slot == key
      keys[pos] = 1
      return true
    pos = (pos + 1) & mask
    probes += 1
  false

-> sparse_core_heap_less(ad, av, bd, bv) (i64 i64 i64 i64) bool
  ad < bd || (ad == bd && av < bv)

-> sparse_core_heap_push(heap_d, heap_v, heap_n, cap, degree, vertex) (i64[] i64[] i64 i64 i64 i64) i64
  return -1 if heap_n >= cap
  i = heap_n
  while i > 0
    parent = (i - 1) / 2
    break if !sparse_core_heap_less(
      degree, vertex, heap_d[parent], heap_v[parent])
    heap_d[i] = heap_d[parent]
    heap_v[i] = heap_v[parent]
    i = parent
  heap_d[i] = degree
  heap_v[i] = vertex
  heap_n + 1

# UNSAFE typed leaf. SparseAnalysis.sparse_core_lift_reduce is the checked
# public route; direct callers must establish every condition below before
# entering this allocation-free kernel:
#   ri.size, ci.size >= m
#   edge_keys.size >= hash_mask+1 and edge_keys[0..hash_mask] are zero
#   to.size, next_edge.size >= directed_cap
#   head.size, degree.size, alive.size, prefix.size, core_vertices.size >= n
#   heap_d.size, heap_v.size >= heap_cap
#   core_ri.size, core_ci.size >= min(m, max_core_edges); stats.size >= 4
# The writable storage ranges edge_keys/to/next_edge/head/degree/alive/heap_d/
# heap_v/prefix/core_vertices/core_ri/core_ci/stats must be mutually disjoint
# and disjoint from ri/ci; the two read-only inputs may alias each other.
# degree and edge_keys must be zero-initialized. Scalar constraints are n>0,
# m>=0, 0<=max_row_degree<=3, positive core/capacity limits, and hash_mask is
# one less than a power of two. Failure is a scalar status; `stats` receives
# prefix_n, core_n, core_edges, and prefix_flops only on success.
-> sparse_core_lift_kernel_unsafe(n, ri, ci, m, max_row_degree, max_core_n, max_core_edges, edge_keys, hash_mask, to, next_edge, head, degree, alive, directed_cap, heap_d, heap_v, heap_cap, prefix, core_vertices, core_ri, core_ci, stats) (i64 u32[] u32[] i64 i64 i64 i64 i64[] i64 u32[] u32[] u32[] u32[] u8[] i64 i64[] i64[] i64 u32[] u32[] u32[] u32[] i64[]) i64
  none = 4294967295
  i = 0
  while i < n
    head[i] = none
    alive[i] = 1
    i += 1

  edge_nodes = 0
  k = 0
  while k < m
    a = ri[k]
    b = ci[k]
    return 0 if a >= n || b >= n
    if a != b
      lo = a
      hi = b
      if lo > hi
        t = lo
        lo = hi
        hi = t
      key = lo * n + hi + 2
      inserted = sparse_core_edge_insert(edge_keys, hash_mask, key)
      return 0 if inserted < 0
      if inserted == 1
        return 0 if edge_nodes + 2 > directed_cap
        to[edge_nodes] = b
        next_edge[edge_nodes] = head[a]
        head[a] = edge_nodes
        edge_nodes += 1
        to[edge_nodes] = a
        next_edge[edge_nodes] = head[b]
        head[b] = edge_nodes
        edge_nodes += 1
        degree[a] = degree[a] + 1
        degree[b] = degree[b] + 1
    k += 1

  heap_n = 0
  i = 0
  while i < n
    if degree[i] <= max_row_degree
      heap_n = sparse_core_heap_push(
        heap_d, heap_v, heap_n, heap_cap, degree[i], i)
      return 0 if heap_n < 0
    i += 1

  prefix_n = 0
  prefix_flops = 0
  alive_count = n
  live = u32[4]
  while heap_n > 0
    cand_d = heap_d[0]
    cand_v = heap_v[0]
    heap_n -= 1
    last_d = heap_d[heap_n]
    last_v = heap_v[heap_n]
    if heap_n > 0
      pos = 0
      heap_d[0] = last_d
      heap_v[0] = last_v
      moving = true
      while moving
        left = pos * 2 + 1
        if left >= heap_n
          moving = false
        else
          right = left + 1
          child = left
          if right < heap_n && sparse_core_heap_less(heap_d[right], heap_v[right], heap_d[left], heap_v[left])
            child = right
          if sparse_core_heap_less(heap_d[child], heap_v[child], heap_d[pos], heap_v[pos])
            td = heap_d[pos]
            tv = heap_v[pos]
            heap_d[pos] = heap_d[child]
            heap_v[pos] = heap_v[child]
            heap_d[child] = td
            heap_v[child] = tv
            pos = child
          else
            moving = false
    next if alive[cand_v] == 0 || degree[cand_v] != cand_d
    return 0 if cand_d > max_row_degree

    live_n = 0
    p = head[cand_v]
    while p != none
      w = to[p]
      if alive[w] != 0
        lo = cand_v
        hi = w
        if lo > hi
          t = lo
          lo = hi
          hi = t
        key = lo * n + hi + 2
        if sparse_core_edge_contains(edge_keys, hash_mask, key)
          return 0 if live_n >= 4
          live[live_n] = w
          live_n += 1
      p = next_edge[p]
    return 0 if live_n != cand_d || live_n > max_row_degree

    a = 1
    while a < live_n
      value = live[a]
      b = a
      while b > 0 && live[b - 1] > value
        live[b] = live[b - 1]
        b -= 1
      live[b] = value
      a += 1

    cv = live_n + 1
    prefix_flops += cv * cv
    prefix[prefix_n] = cand_v
    prefix_n += 1

    a = 0
    while a < live_n
      u = live[a]
      b = a + 1
      while b < live_n
        w = live[b]
        lo = u
        hi = w
        if lo > hi
          t = lo
          lo = hi
          hi = t
        key = lo * n + hi + 2
        inserted = sparse_core_edge_insert(edge_keys, hash_mask, key)
        return 0 if inserted < 0
        if inserted == 1
          return 0 if edge_nodes + 2 > directed_cap
          to[edge_nodes] = w
          next_edge[edge_nodes] = head[u]
          head[u] = edge_nodes
          edge_nodes += 1
          to[edge_nodes] = u
          next_edge[edge_nodes] = head[w]
          head[w] = edge_nodes
          edge_nodes += 1
          degree[u] = degree[u] + 1
          degree[w] = degree[w] + 1
        b += 1
      a += 1

    alive[cand_v] = 0
    alive_count -= 1
    a = 0
    while a < live_n
      w = live[a]
      lo = cand_v
      hi = w
      if lo > hi
        t = lo
        lo = hi
        hi = t
      key = lo * n + hi + 2
      return 0 if !sparse_core_edge_remove(edge_keys, hash_mask, key)
      return 0 if degree[w] == 0
      degree[w] = degree[w] - 1
      a += 1
    degree[cand_v] = 0
    a = 0
    while a < live_n
      w = live[a]
      if degree[w] <= max_row_degree
        heap_n = sparse_core_heap_push(
          heap_d, heap_v, heap_n, heap_cap, degree[w], w)
        return 0 if heap_n < 0
      a += 1

  core_n = alive_count
  return 0 if core_n <= 0 || core_n > max_core_n
  core_id = u32[n]
  cp = 0
  i = 0
  while i < n
    if alive[i] != 0
      core_id[i] = cp
      core_vertices[cp] = i
      cp += 1
    i += 1
  return 0 if cp != core_n

  core_edges = 0
  i = 0
  while i < n
    if alive[i] != 0
      p = head[i]
      while p != none
        w = to[p]
        if w < i && alive[w] != 0
          key = w * n + i + 2
          if sparse_core_edge_contains(edge_keys, hash_mask, key)
            return 0 if core_edges >= m || core_edges >= max_core_edges
            core_ri[core_edges] = core_id[i]
            core_ci[core_edges] = core_id[w]
            core_edges += 1
        p = next_edge[p]
    i += 1

  stats[0] = prefix_n
  stats[1] = core_n
  stats[2] = core_edges
  stats[3] = prefix_flops
  1
