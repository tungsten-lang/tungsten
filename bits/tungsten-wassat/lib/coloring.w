# Fast-only certificate for an explicit pigeonhole obstruction in a graph-
# coloring encoding.
#
# A common coloring CNF contains one positive width-k choice clause per graph
# vertex and, for an edge (u,v), all k binaries
#
#   (-x[u,0] | -x[v,0]) ... (-x[u,k-1] | -x[v,k-1]).
#
# If k+1 choice clauses form a clique under those complete binary bundles,
# their clauses alone are PHP(k+1,k): every group must choose a color, while
# no two groups may choose the same one.  The input is therefore UNSAT.
#
# Recognition is deliberately one-sided.  Partial bundles, overlapping choice
# clauses, unsupported widths, or a bounded clique-search miss all fall through
# to ordinary solving.  Every successful result is backed only by clauses
# literally present in the original formula; unrelated clauses are ignored.

WASSAT_COLORING_MAX_WIDTH = 62
WASSAT_COLORING_MAX_GROUPS = 512
WASSAT_COLORING_NODE_CAP = 200000

# Bounded target-clique search over a dense row-major adjacency matrix.
# Candidate vectors for depth d occupy cands[d*g .. (d+1)*g).
-> wassat_coloring_clique_dfs(adj, g, target, cands, ncand,
                              depth, clique, pm) (i64[] i64 i64 i64[] i64 i64 i64[] i64[]) i64
  pm[0] = pm[0] + 1
  return 0 if pm[0] > pm[1]
  return 1 if depth >= target
  return 0 if depth + ncand < target

  base = depth * g
  remaining = ncand
  while remaining > 0
    return 0 if depth + remaining < target

    # Follow the densest remaining vertex first.  On the competition coloring
    # families this finds the explicit k+1 witness after only tens of nodes;
    # the node cap keeps an adversarial non-witness from becoming a new stage.
    best_i = 0
    best_degree = -1
    i = 0
    while i < remaining
      v = cands[base + i]
      degree = 0
      j = 0
      while j < remaining
        u = cands[base + j]
        degree += 1 if adj[v * g + u] != 0
        j += 1
      if degree > best_degree
        best_degree = degree
        best_i = i
      i += 1

    v = cands[base + best_i]
    remaining -= 1
    cands[base + best_i] = cands[base + remaining]
    cands[base + remaining] = v

    child_base = (depth + 1) * g
    child_n = 0
    i = 0
    while i < remaining
      u = cands[base + i]
      if adj[v * g + u] != 0
        cands[child_base + child_n] = u
        child_n += 1
      i += 1
    clique[depth] = v
    if wassat_coloring_clique_dfs(adj, g, target, cands, child_n,
                                  depth + 1, clique, pm) == 1
      return 1
  0

# Return the clique size on a verified obstruction, otherwise zero.
-> wassat_coloring_clique_unsat(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return 0 if nv < 6 || ncl < 7

  fla = formula["flat_lits"] ## i64[]
  fcs = formula["flat_offs"] ## i64[]
  fcl = formula["flat_lens"] ## i64[]

  # Cheap length-only gate.  Supported coloring encodings are overwhelmingly
  # binary and nearly every non-binary clause has one dominant choice width.
  widths = i64[WASSAT_COLORING_MAX_WIDTH + 1]
  binaries = 0
  ci = 0
  while ci < ncl
    n = fcl[ci]
    if n == 2
      binaries += 1
    elsif n >= 2 && n <= WASSAT_COLORING_MAX_WIDTH
      widths[n] = widths[n] + 1
    ci += 1
  return 0 if binaries * 10 < ncl * 9

  width = 0
  count = 0
  w = 2
  while w <= WASSAT_COLORING_MAX_WIDTH
    if widths[w] > count
      width = w
      count = widths[w]
    w += 1
  other = ncl - binaries
  return 0 if width == 0 || count < width + 1
  return 0 if count * 10 < other * 9
  return 0 if count * width > nv

  # Collect pairwise-disjoint positive choice clauses.  Sorting the variable
  # ids gives each clause a deterministic color coordinate independent of
  # literal order.  An overlapping clause is simply not a candidate.
  group_vars = i64[count * width]
  owner = i64[nv + 1]
  color = i64[nv + 1]
  scratch = i64[width]
  groups = 0
  ci = 0
  while ci < ncl && groups < WASSAT_COLORING_MAX_GROUPS
    if fcl[ci] == width
      off = fcs[ci]
      positive = true
      j = 0
      while j < width
        l = fla[off + j]
        positive = false if l <= 0 || l > nv
        scratch[j] = l
        j += 1
      if positive
        # Width is at most 62; insertion sort avoids boxed comparator calls.
        j = 1
        while j < width
          x = scratch[j]
          k = j
          while k > 0 && scratch[k - 1] > x
            scratch[k] = scratch[k - 1]
            k -= 1
          scratch[k] = x
          j += 1
        disjoint = true
        j = 0
        while j < width
          v = scratch[j]
          disjoint = false if j > 0 && scratch[j - 1] == v
          disjoint = false if owner[v] != 0
          j += 1
        if disjoint
          j = 0
          while j < width
            v = scratch[j]
            group_vars[groups * width + j] = v
            owner[v] = groups + 1
            color[v] = j
            j += 1
          groups += 1
    ci += 1
  target = width + 1
  return 0 if groups < target

  # Accumulate which color coordinates are forbidden for each group pair.
  # Duplicate binaries are harmless because this is a bit mask.
  masks = i64[groups * groups]
  ci = 0
  while ci < ncl
    if fcl[ci] == 2
      off = fcs[ci]
      la = fla[off]
      lb = fla[off + 1]
      if la < 0 && lb < 0
        a = 0 - la
        b = 0 - lb
        if a <= nv && b <= nv && owner[a] != 0 && owner[b] != 0
          ga = owner[a] - 1
          gb = owner[b] - 1
          if ga != gb && color[a] == color[b]
            bit = 1 << color[a]
            masks[ga * groups + gb] = masks[ga * groups + gb] | bit
            masks[gb * groups + ga] = masks[gb * groups + ga] | bit
    ci += 1

  full = (1 << width) - 1
  adj = i64[groups * groups]
  a = 0
  while a < groups
    b = a + 1
    while b < groups
      if masks[a * groups + b] == full
        adj[a * groups + b] = 1
        adj[b * groups + a] = 1
      b += 1
    a += 1

  cands = i64[(target + 1) * groups]
  a = 0
  while a < groups
    cands[a] = a
    a += 1
  clique = i64[target]
  pm = i64[3]
  pm[1] = WASSAT_COLORING_NODE_CAP
  return 0 unless wassat_coloring_clique_dfs(
    adj, groups, target, cands, groups, 0, clique, pm
  ) == 1
  target
