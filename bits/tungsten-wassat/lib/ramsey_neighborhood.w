-> wassat_ramsey_bound_stop(work, deadline) (i64[] i64) i64
  if deadline > 0
    work[8] += 1
    if clock_ms() >= deadline
      work[0] = 0
      work[1] = 1
      return 1
  0

# Lower edge bounds for triangle-free graphs with no independent k-set.
# For a vertex v of degree d, delete its closed neighborhood. The remaining
# graph avoids an independent (k-1)-set and has e - sum(deg(u), u in N(v))
# edges. Summing over v gives n*e - sum(d^2) >= sum(lower[k-1,n-1-d]).
# Enumerate degree histograms satisfying this necessary inequality.
-> wassat_ramsey_degree_profiles(k, n, d, left, sum, squares, outside, lower, hist, stats) (i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64[]) i64
  if d == k || d == n
    return 0 if left != 0 || (sum & 1) != 0
    edges = sum / 2
    return 0 if n * edges - squares < outside
    stats[0] = edges if edges < stats[0]
    # Any other profile invalidates the corresponding structural deduction.
    stats[1] = 1 if k == 6 && n == 18 && hist[5] != 18
    stats[1] = 1 if k == 5 && n == 12 && edges == 20 && (hist[3] != 8 || hist[4] != 4)
    return 0
  need = lower[(k - 1) * 19 + n - 1 - d]
  count = 0
  while count <= left
    break if count > 0 && need == 1000
    hist[d] = count
    wassat_ramsey_degree_profiles(k, n, d + 1, left - count, sum + d * count,
      squares + d * d * count, outside + need * count, lower, hist, stats)
    count += 1
  0

-> wassat_ramsey_neighborhood_degrees
  lower = i64[7 * 19]
  hist = i64[6]
  stats = i64[2]
  n = 0
  while n <= 17
    # alpha < 2 forces a complete graph, triangle-free only up to two vertices.
    lower[2 * 19 + n] = n < 2 ? 0 : (n == 2 ? 1 : 1000)
    n += 1
  k = 3
  while k <= 5
    n = 1
    while n <= 17
      stats[0] = 1000
      wassat_ramsey_degree_profiles(k, n, 0, n, 0, 0, 0, lower, hist, stats)
      lower[k * 19 + n] = stats[0]
      n += 1
    k += 1
  stats[0] = 1000
  wassat_ramsey_degree_profiles(6, 18, 0, 18, 0, 0, 0, lower, hist, stats)
  stats[1] == 0 && stats[0] == 45 && lower[5 * 19 + 12] == 20 &&
    lower[4 * 19 + 8] == 10 && lower[4 * 19 + 7] == 6

-> wassat_ramsey_link(g, u, v) (i64[] i64 i64)
  g[u] |= 1 << v
  g[v] |= 1 << u

# Each of eight degree-three vertices of H attaches to one of four high
# vertices. Each high needs two low neighbors. Require triangle-freeness,
# then test the necessary one-or-two common neighbors for EVERY nonedge.
-> wassat_ramsey_attach_low(g, i, loads, work) (i64[] i64 i64[] i64[]) bool
  if i == 18
    work[11] += 1
    a = 0
    while a < 18
      b = a + 1
      while b < 18
        if (g[a] & (1 << b)) == 0
          common = ccall_nobox("__w_bit_ctpop_u64", g[a] & g[b]) ## i64
          return false if common < 1 || common > 2
        b += 1
      a += 1
    return true
  h = 0
  while h < 4
    u = h + 6
    if loads[h] < 2 && (g[i] & g[u]) == 0
      wassat_ramsey_link(g, i, u)
      loads[h] += 1
      return true if wassat_ramsey_attach_low(g, i + 1, loads, work)
      loads[h] -= 1
      g[i] ^= 1 << u
      g[u] ^= 1 << i
    h += 1
  false

# A hypothetical 18-vertex graph is 5-regular. For every root, the 12
# vertices H outside its closed neighborhood have 20 edges and degrees
# 3 (eight vertices) and 4 (four). Equality in the deficiency inequality
# forces neighbor-degree sums 10 and 14 respectively. Thus the four high
# vertices induce a 4-cycle, the eight low vertices induce a 2-factor and
# every low vertex has a unique high neighbor. Every nonedge of the full
# graph has one or two common neighbors (5 minus its degree in H).
#
# The five neighbors of the root are independent. Each high vertex meets
# one of these five. Those choices are distinct: adjacent highs cannot form
# a triangle and opposite highs already have two common neighbors. Name
# the four choices in cycle order 0..3. Each low meets a pair of the five.
# The eight pairs are distinct, since a repeated pair would have three
# common neighbors including the root. The two missing pairs are a perfect
# matching on 0..3 by 5-regularity. Enumerate all three such matchings.
-> wassat_ramsey_neighborhood_refutes(work, deadline) (i64[] i64) bool
  return false unless wassat_ramsey_neighborhood_degrees
  mate = 1
  while mate <= 3
    return false if wassat_ramsey_bound_stop(work, deadline) != 0
    missing = 1 | (1 << mate)
    g = i64[18]
    i = 0
    while i < 5
      wassat_ramsey_link(g, 0, 1 + i)
      if i < 4
        wassat_ramsey_link(g, 6 + i, 6 + (i + 1) % 4)
        wassat_ramsey_link(g, 6 + i, 1 + i)
      i += 1
    low = 10
    a = 0
    while a < 5
      b = a + 1
      while b < 5
        mask = (1 << a) | (1 << b)
        if mask != missing && mask != (15 ^ missing)
          wassat_ramsey_link(g, low, 1 + a)
          wassat_ramsey_link(g, low, 1 + b)
          low += 1
        b += 1
      a += 1
    left = i64[10]
    right = i64[10]
    edges = 0
    a = 10
    while a < 18
      b = a + 1
      while b < 18
        if (g[a] & g[b]) == 0
          return false if edges == 10
          left[edges] = a
          right[edges] = b
          edges += 1
        b += 1
      a += 1
    return false unless edges == 10
    # A 2-factor on eight vertices uses eight of ten possible edges.
    omit = 0
    loads = i64[4]
    while omit < edges
      other = omit + 1
      while other < edges
        j = 0
        while j < edges
          wassat_ramsey_link(g, left[j], right[j]) unless j == omit || j == other
          j += 1
        a = 10
        while a < 18
          # Two neighbors among the five and exactly two more in this factor.
          count = ccall_nobox("__w_bit_ctpop_u64", g[a]) ## i64
          break unless count == 4
          a += 1
        if a == 18
          work[10] += 1
          return false if wassat_ramsey_attach_low(g, 10, loads, work)
        a = 10
        while a < 18
          g[a] &= 63
          a += 1
        other += 1
      omit += 1
    mate += 1
  true

# For each vertex count and forbidden independent-set size, minimize the
# deficiency cost at each possible degree sum. A missing feasible sum rules
# out the graph. Finite minima are lower bounds, including when unattained.
-> wassat_ramsey_triangle_bound(kmax, limit, work, deadline) (i64 i64 i64[] i64) i64
  return 0 if kmax < 3 || kmax > 7 || limit < 1 || limit > 40
  stride = limit + 1
  impossible = 1000000
  lower = i64[(kmax + 1) * stride]
  n = 2
  while n <= limit
    lower[2 * stride + n] = n == 2 ? 1 : impossible
    n += 1
  cap = limit * (kmax - 1)
  cost = i64[cap + 1]
  next_cost = i64[cap + 1]
  term = i64[kmax]
  k = 3
  while k <= kmax
    n = 1
    while n <= limit
      return 0 if wassat_ramsey_bound_stop(work, deadline) != 0
      dmax = k - 1
      dmax = n - 1 if n < k
      d = 0
      while d <= dmax
        term[d] = d * d + lower[(k - 1) * stride + n - 1 - d]
        d += 1
      cost[0] = 0
      vertices = 0
      while vertices < n
        s = 0
        while s <= (vertices + 1) * dmax
          next_cost[s] = impossible
          s += 1
        s = 0
        while s <= vertices * dmax
          if cost[s] < impossible
            d = 0
            while d <= dmax
              v = cost[s] + term[d]
              next_cost[s + d] = v if v < next_cost[s + d]
              d += 1
          s += 1
        swap = cost
        cost = next_cost
        next_cost = swap
        vertices += 1
      e = 0
      while 2 * e <= n * dmax && cost[2 * e] > n * e
        e += 1
      if 2 * e > n * dmax
        return n if k == kmax
        # Deleting vertices preserves both forbidden-subgraph conditions.
        while n <= limit
          lower[k * stride + n] = impossible
          n += 1
      else
        lower[k * stride + n] = e
        n += 1
    k += 1
  0
