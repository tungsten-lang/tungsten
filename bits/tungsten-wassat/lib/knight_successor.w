# Directed successor encoding. A long incoming support contains one signed
# matrix entry per possible predecessor. Short outgoing supports restrict the
# actual moves. The guarded rank counters identify a vertex on both sides of
# this matrix even after independent permutations of clauses and variables.

# Intersect the rank variables attached to all arcs at each vertex.
-> wassat_knight_rank_signatures(nodes, edges, degree, labels, counts, stride) (i64 i32[] i8[] i32[] i8[] i64)
  signatures = i32[nodes * stride]
  sizes = i8[nodes]
  u = 0
  while u < nodes
    first = edges[u * 8]
    k = 0
    while k < counts[first]
      label = labels[first * stride + k]
      j = 1
      while j < degree[u]
        arc = edges[u * 8 + j]
        i = 0
        while i < counts[arc] && labels[arc * stride + i] != label
          i += 1
        break if i == counts[arc]
        j += 1
      if j == degree[u]
        signatures[u * stride + sizes[u]] = label
        sizes[u] += 1
      k += 1
    u += 1
  {"labels": signatures, "sizes": sizes}

# A few vertices may share no rank label because arcs into the counter root
# have no increment guard. Try the remaining bijections and require every
# recovered move to have a reverse. Ambiguity beyond three is a cheap miss.
-> wassat_knight_align_successors(nodes, outgoing, degree, dest, inverse, unknown_cols, unknown_rows, k, missing, neighbors, matrix, arc_var)
  if k < missing
    j = k
    while j < missing
      tmp = unknown_rows[k]
      unknown_rows[k] = unknown_rows[j]
      unknown_rows[j] = tmp
      inverse[unknown_cols[k]] = unknown_rows[k] + 1
      if wassat_knight_align_successors(nodes, outgoing, degree, dest, inverse, unknown_cols, unknown_rows, k + 1, missing, neighbors, matrix, arc_var)
        return true
      tmp = unknown_rows[k]
      unknown_rows[k] = unknown_rows[j]
      unknown_rows[j] = tmp
      j += 1
    return false

  u = 0
  while u < nodes
    j = 0
    while j < degree[u]
      arc = outgoing[u * 8 + j]
      v = inverse[dest[arc]] - 1
      neighbors[u * 8 + j] = v
      j += 1
    u += 1
  u = 0
  while u < nodes
    j = 0
    while j < degree[u]
      v = neighbors[u * 8 + j]
      return false if v == u
      i = 0
      while i < degree[v] && neighbors[v * 8 + i] != u
        i += 1
      return false if i == degree[v]
      j += 1
    u += 1
  u = 0
  while u < nodes
    j = 0
    while j < degree[u]
      v = neighbors[u * 8 + j]
      return false if matrix[u * nodes + v] != 0
      matrix[u * nodes + v] = arc_var[outgoing[u * 8 + j]]
      j += 1
    u += 1
  true

-> wassat_knight_successor_recover(formula, side, long_count)
  nodes = side * side
  nv = formula["nvars"]
  return {} if long_count != nodes || nv < nodes * nodes
  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  ncl = formula["flat_ncl"]
  col_of = i32[nv + 1]
  semantics = i8[nv + 1]
  col = 0
  ci = 0
  while ci < ncl
    if lens[ci] == nodes
      off = offs[ci]
      j = 0
      while j < nodes
        lit = lits[off + j]
        v = lit.abs
        return {} if v < 1 || v > nv || col_of[v] != 0
        col_of[v] = col + 1
        semantics[v] = lit > 0 ? 1 : -1
        j += 1
      col += 1
    ci += 1
  return {} unless col == nodes

  degree = i8[nodes]
  indegree = i8[nodes]
  outgoing = i32[nodes * 8]
  incoming = i32[nodes * 8]
  dest = i32[nodes * 8]
  arc_var = i32[nodes * 8]
  arc_of = i32[nv + 1]
  row = 0
  narcs = 0
  ci = 0
  while ci < ncl
    n = lens[ci]
    if n >= 2 && n <= 8
      off = offs[ci]
      j = 0
      while j < n
        lit = lits[off + j]
        break unless semantics[lit.abs] == (lit > 0 ? 1 : -1)
        j += 1
      if j == n
        return {} if row >= nodes
        degree[row] = n
        j = 0
        while j < n
          v = lits[off + j].abs
          col = col_of[v] - 1
          return {} if arc_of[v] != 0 || indegree[col] >= 8
          i = 0
          while i < j
            return {} if dest[outgoing[row * 8 + i]] == col
            i += 1
          outgoing[row * 8 + j] = narcs
          incoming[col * 8 + indegree[col]] = narcs
          indegree[col] += 1
          dest[narcs] = col
          arc_var[narcs] = v
          narcs += 1
          arc_of[v] = narcs
          j += 1
        row += 1
    ci += 1
  return {} unless row == nodes
  actual = i64[9]
  col = 0
  while col < nodes
    return {} if indegree[col] < 2
    actual[degree[col]] += 1
    col += 1
  expected = i64[9]
  wassat_knight_expected_degrees(side, expected, 0)
  j = 0
  while j <= 8
    return {} unless actual[j] == expected[j]
    j += 1

  # One edge sees source, destination and carry bits of the guarded increment.
  # Bounded lists keep even an unrelated formula cheap to reject.
  stride = 40
  labels = i32[narcs * stride]
  counts = i8[narcs]
  ci = 0
  while ci < ncl
    n = lens[ci]
    if n == 3 || n == 4
      off = offs[ci]
      arc = -1
      j = 0
      while j < n
        v = lits[off + j].abs
        if col_of[v] != 0
          break if arc >= 0 || arc_of[v] == 0
          arc = arc_of[v] - 1
        j += 1
      if j == n && arc >= 0
        j = 0
        while j < n
          v = lits[off + j].abs
          if col_of[v] == 0
            i = 0
            while i < counts[arc] && labels[arc * stride + i] != v
              i += 1
            if i == counts[arc]
              return {} if i == stride
              labels[arc * stride + i] = v
              counts[arc] += 1
          j += 1
    ci += 1

  src = wassat_knight_rank_signatures(nodes, outgoing, degree, labels, counts, stride)
  dst = wassat_knight_rank_signatures(nodes, incoming, indegree, labels, counts, stride)
  src_labels = src["labels"] ## i32[]
  src_sizes = src["sizes"] ## i8[]
  dst_labels = dst["labels"] ## i32[]
  dst_sizes = dst["sizes"] ## i8[]
  owner = i32[nv + 1]
  row = 0
  while row < nodes
    j = 0
    while j < src_sizes[row]
      v = src_labels[row * stride + j]
      return {} if owner[v] != 0
      owner[v] = row + 1
      j += 1
    row += 1
  unknown_cols = i64[3]
  unknown_rows = i64[3]
  inverse = i32[nodes]
  used = i8[nodes]
  missing = 0
  col = 0
  while col < nodes
    j = 0
    while j < dst_sizes[col]
      match = owner[dst_labels[col * stride + j]]
      if match != 0
        return {} if inverse[col] != 0 && inverse[col] != match
        inverse[col] = match
      j += 1
    if inverse[col] == 0
      return {} if missing == 3
      unknown_cols[missing] = col
      missing += 1
    else
      row = inverse[col] - 1
      return {} if used[row] != 0
      used[row] = 1
    col += 1
  j = 0
  row = 0
  while row < nodes
    if used[row] == 0
      unknown_rows[j] = row
      j += 1
    row += 1
  neighbors = i64[nodes * 8]
  matrix = i64[nodes * nodes]
  return {} unless wassat_knight_align_successors(nodes, outgoing, degree, dest, inverse, unknown_cols, unknown_rows, 0, missing, neighbors, matrix, arc_var)
  {
    "side": side, "positions": nodes, "primary_vars": nodes * nodes,
    "matrix": matrix, "semantics": semantics, "neighbors": neighbors,
    "degree": degree, "successor": true
  }

# Successor variables put no restrictions on the order of the positions.
# Try Warnsdorff walks from variable starting points, breaking equal-degree
# ties reproducibly. A generation stamp avoids clearing the board on restart.
-> wassat_knight_successor_tour(recovered, path, meta, node_cap)
  nodes = recovered["positions"]
  neighbors = recovered["neighbors"] ## i64[]
  degree = recovered["degree"] ## i8[]
  seen = i64[nodes]
  seed = 1
  attempt = 0
  while meta[0] < node_cap
    attempt += 1
    seed = (seed * 48271) % 2147483647
    start = seed % nodes
    path[0] = start
    seen[start] = attempt
    depth = 1
    while depth < nodes && meta[0] < node_cap
      meta[0] += 1
      u = path[depth - 1]
      best = -1
      best_degree = 9
      tie = 0
      j = 0
      while j < degree[u]
        v = neighbors[u * 8 + j]
        if seen[v] != attempt
          onward = 0
          closes = false
          i = 0
          while i < degree[v]
            w = neighbors[v * 8 + i]
            onward += 1 if seen[w] != attempt
            closes = true if w == start
            i += 1
          if (depth != nodes - 1 || closes) && onward <= best_degree
            seed = (seed * 48271) % 2147483647
            if onward < best_degree || seed > tie
              best = v
              best_degree = onward
              tie = seed
        j += 1
      break if best < 0
      seen[best] = attempt
      path[depth] = best
      depth += 1
    return 1 if depth == nodes
  0
