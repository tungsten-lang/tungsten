use ramsey_seeds
use ramsey_neighborhood

# A row of the outer graph selects an independent subset of H. The subset
# may not complete a triangle or exceed a degree or common-neighbor bound.
-> wassat_ramsey_glue_fits(g, u, mask, max_degree, common) (i64[] i64 i64 i64 i64) bool
  old = g[u]
  s = mask
  while s != 0
    v = wassat_ramsey_first(s)
    s &= s - 1
    return false if wassat_ramsey_count(g[v]) >= max_degree || (g[v] & old) != 0
    if common > 0
      others = old | s
      while others != 0
        b = wassat_ramsey_first(others)
        return false if wassat_ramsey_count(g[v] & g[b]) >= common
        others &= others - 1
  if common > 0
    b = 0
    while b < g.size
      return false if b != u && wassat_ramsey_count((old | mask) & g[b]) > common
      b += 1
  true

# For an independent subset T of the outer vertices, cover[T] is its
# neighborhood in H. The remaining vertices of H can jointly contribute at most alpha[uncovered].
# Return 1 for a completion, 0 for exhaustive failure, -1 on expiration.
-> wassat_ramsey_glue_visit(g, alpha, options, counts, order, twin, chosen, cover, tests, starts, limits, cfg, depth, edges, stats, deadline) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64[] i64) i64
  stats[0] += 1
  return -1 if (stats[0] & 1023) == 0 && deadline > 0 && clock_ms() >= deadline
  if depth == order.size
    j = 0
    while j < g.size
      return 0 if wassat_ramsey_count(g[j]) < cfg[0]
      j += 1
    return 1
  u = order[depth]
  block = alpha.size
  prev = twin[depth]
  j = 0
  while j < counts[u]
    mask = options[u * block + j]
    j += 1
    next unless prev < 0 || mask >= chosen[prev]
    total = edges + wassat_ramsey_count(mask)
    next if total > cfg[2]
    t = starts[depth]
    end_t = starts[depth + 1]
    while t < end_t
      subset = tests[t]
      hit = cover[subset ^ (1 << depth)] | mask
      cover[subset] = hit
      break if alpha[(block - 1) ^ hit] >= limits[subset]
      t += 1
    next if t < end_t
    next unless wassat_ramsey_glue_fits(g, u, mask, cfg[1], cfg[3])
    g[u] |= mask
    s = mask
    while s != 0
      g[wassat_ramsey_first(s)] |= 1 << u
      s &= s - 1
    chosen[depth] = mask
    res = wassat_ramsey_glue_visit(g, alpha, options, counts, order, twin, chosen, cover, tests, starts, limits, cfg, depth + 1, total, stats, deadline)
    return res if res != 0
    g[u] ^= mask
    s = mask
    while s != 0
      g[wassat_ramsey_first(s)] ^= 1 << u
      s &= s - 1
  0

# cfg holds minimum degree, maximum degree, edge cap and maximum codegree
# (zero disables the latter). Anchors have no incident edges into H.
-> wassat_ramsey_glue(h, g, anchors, k, cfg, stats, deadline) (i64[] i64[] i64 i64 i64[] i64[] i64) i64
  return -1 if deadline > 0 && clock_ms() >= deadline
  n = g.size
  m = n - h.size
  alpha = wassat_ramsey_subset_alpha(h)
  return 0 if alpha[alpha.size - 1] >= k
  options = i64[n * alpha.size]
  counts = i64[n]
  order = i64[m]
  sum = 0
  v = 0
  while v < n
    if v < h.size
      g[v] = h[v]
    else
      deg = wassat_ramsey_count(g[v])
      s = 0
      limit = (anchors & (1 << v)) != 0 ? 1 : alpha.size
      while s < limit
        size = wassat_ramsey_count(s)
        if size == alpha[s] && size + deg >= cfg[0] && size + deg <= cfg[1]
          options[v * alpha.size + counts[v]] = s
          counts[v] += 1
        s += 1
      return 0 if counts[v] == 0
      j = v - h.size
      while j > 0 && counts[order[j - 1]] > counts[v]
        order[j] = order[j - 1]
        j -= 1
      order[j] = v
    sum += wassat_ramsey_count(g[v])
    v += 1
  return 0 if sum / 2 > cfg[2]
  v = 0
  while v < n
    return 0 if wassat_ramsey_count(g[v]) > cfg[1]
    j = v + 1
    while j < n
      common = wassat_ramsey_count(g[v] & g[j])
      return 0 if common > 0 && (g[v] & (1 << j)) != 0
      return 0 if cfg[3] > 0 && common > cfg[3]
      j += 1
    v += 1
  twin = i64[m]
  starts = i64[m + 1]
  tests = i64[1 << m]
  limits = i64[1 << m]
  independent = i8[1 << m]
  independent[0] = 1
  depth = 0
  while depth < m
    u = order[depth]
    twin[depth] = -1
    earlier = 0
    j = 0
    while j < depth
      v = order[j]
      earlier |= 1 << j if (g[u] & (1 << v)) != 0
      if g[u] == g[v] && ((anchors >> u) & 1) == ((anchors >> v) & 1)
        twin[depth] = j
      j += 1
    used = starts[depth]
    s = 0
    while s < (1 << depth)
      if independent[s] == 1 && (s & earlier) == 0
        t = s | (1 << depth)
        independent[t] = 1
        tests[used] = t
        limits[t] = k - wassat_ramsey_count(t)
        used += 1
      s += 1
    starts[depth + 1] = used
    depth += 1
  wassat_ramsey_glue_visit(g, alpha, options, counts, order, twin, i64[m], i64[1 << m], tests, starts, limits, cfg, 0, sum / 2, stats, deadline)

-> wassat_ramsey_cross_key(mask, w) (i64 i64) i64
  best = mask
  cols = 0
  while cols < (1 << (2 * w))
    used = 0
    x = 0
    while x < w
      c = (cols >> (2 * x)) & 3
      break if c >= w || (used & (1 << c)) != 0
      used |= 1 << c
      x += 1
    if x == w
      rows = i64[w]
      x = 0
      while x < w
        val = 0
        y = 0
        while y < w
          val |= ((mask >> (x * w + ((cols >> (2 * y)) & 3))) & 1) << y
          y += 1
        z = x
        while z > 0 && rows[z - 1] < val
          rows[z] = rows[z - 1]
          z -= 1
        rows[z] = val
        x += 1
      value = 0
      x = 0
      while x < w
        value |= rows[x] << (w * x)
        x += 1
      best = value if value < best
    cols += 1
  best

-> wassat_ramsey_regular_branches(h, cfg, stats, deadline) (i64[] i64[] i64[] i64) i64
  return -1 unless h.size == 12 || h.size == 13
  common = h.size - 9
  w = 6 - common
  a = h.size
  b = a + 1
  shared = b + 1
  left = shared + common
  right = left + w
  cfg[3] = common
  mask = 0
  while mask < (1 << (w * w))
    value = mask
    mask += 1
    next unless value == wassat_ramsey_cross_key(value, w)
    g = i64[23]
    x = 0
    while x < common
      wassat_ramsey_link(g, a, shared + x)
      wassat_ramsey_link(g, b, shared + x)
      x += 1
    x = 0
    while x < w
      wassat_ramsey_link(g, a, left + x)
      wassat_ramsey_link(g, b, right + x)
      y = 0
      while y < w
        wassat_ramsey_link(g, left + x, right + y) if (value & (1 << (x * w + y))) != 0
        y += 1
      x += 1
    balance = 0
    v = 0
    while v < g.size
      if v < h.size
        balance += 6 - wassat_ramsey_count(h[v])
      else
        balance -= 6 - wassat_ramsey_count(g[v])
      v += 1
    next if balance != 0
    res = wassat_ramsey_glue(h, g, (1 << a) | (1 << b), 7, cfg, stats, deadline)
    return res if res != 0
  0

# In a triangle-free graph on 17 vertices with alpha < 6 and at most
# 39 edges, a minimum-degree root has degree 3 or 4. Its nonneighbors
# avoid an independent five-set, hence number at most 13.
# Check all attachments for both orders using the generated representatives.
-> wassat_ramsey_sparse_branch(h, cap, stats, deadline) (i64[] i64 i64[] i64) i64
  return -1 unless h.size == 12 || h.size == 13
  d = 16 - h.size
  g = i64[17]
  root = h.size
  v = root + 1
  while v < 17
    wassat_ramsey_link(g, root, v)
    v += 1
  cfg = i64[4]
  cfg[0] = d
  cfg[1] = 5
  cfg[2] = cap
  wassat_ramsey_glue(h, g, 1 << root, 6, cfg, stats, deadline)

# Assume a triangle-free graph on 23 vertices with alpha < 7.
# The R(3,6) proof forces every degree to be 5 or 6. If s vertices have
# degree 5, Mantel's theorem gives one with at most floor(s/2) degree-five
# neighbors. Outside its closed neighborhood are 17 vertices with at most
# (138-s)/2 - 30 + floor(s/2) = 39 edges. The sparse searches exclude this.
#
# In the resulting six-regular graph every nonedge has a common neighbor:
# each vertex outside N[v] has at most five neighbors there. If codegrees
# were at most two, 30 length-two walks to 16 nonneighbors would give 14
# four-cycles through each vertex. Every four-cycle has four vertices.
# Choose a nonedge with maximum codegree c >= 3. Outside both closed
# neighborhoods are 9+c vertices with alpha < 5. The generated seeds bound
# c by four. The only possible edges among the two neighborhoods (aside
# from the anchor edges) join the two sets of exclusive neighbors.
-> wassat_ramsey_gluing_refutes(work, deadline) (i64[] i64) bool
  return false unless wassat_ramsey_neighborhood_refutes(work, deadline)
  sizes = i64[15]
  seeds = wassat_ramsey_small_seeds(deadline, sizes)
  return false if seeds == nil
  return false if sizes[14] != 0
  stats = i64[1]
  i = 0
  while i < seeds.size
    h = seeds[i] ## i64[]
    return false if wassat_ramsey_sparse_branch(h, 39, stats, deadline) != 0
    i += 1
  n = 23
  # The number of degree-five vertices is even by the handshake lemma.
  s = 2
  while s <= n
    return false if (6 * n - s) / 2 - 30 + s / 2 >= 40
    s += 2
  double_paths = 6 * 5 - (n - 1 - 6)
  return false if (double_paths * n) % 4 == 0
  cfg = i64[4]
  cfg[0] = 6
  cfg[1] = 6
  cfg[2] = 6 * n / 2
  i = 0
  while i < seeds.size
    h = seeds[i] ## i64[]
    return false if wassat_ramsey_regular_branches(h, cfg, stats, deadline) != 0
    i += 1
  work[13] = stats[0]
  true
