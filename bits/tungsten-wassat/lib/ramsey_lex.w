# Symmetry reduction for COMPLETE monochromatic clique families.
# A family name, clause count, or matching width histogram is insufficient:
# validate every clique and every combinatorial rank for every present sign
# and width. Only then are all vertex permutations automorphisms of the CNF.
# Every satisfying orbit has a minimum edge vector. It satisfies the lex
# leader for every vertex transposition. Auxiliary prefix variables encode
# these comparisons; original variables retain their IDs.
# For i < j, every changed edge is paired with its image under the swap.
# The first member of each pair is incident to i; ordering the remaining
# vertices enumerates these first positions in edge-vector order. Comparing
# the two adjacency rows therefore compares the complete permuted vectors.
# This is equisatisfiability, not a RUP consequence. Use only in fast mode.

WASSAT_RAMSEY_LEX_MS = 50

# work: accepted, deadline stop, vertices, checked clauses, literal reads,
# groups, distinct cliques, duplicates, rank terms, output clauses/literals,
# auxiliaries, transpositions, generated comparisons, copied literals, polls.
-> wassat_ramsey_lex_stop(work, deadline) (i64[] i64) i64
  if deadline > 0
    work[15] += 1
    if clock_ms() >= deadline
      work[0] = 0
      work[1] = 1
      return 1
  0

-> wassat_ramsey_lex_check(lits, offs, lens, nv, nc, n, work, deadline) (i64[] i64[] i64[] i64 i64 i64 i64[] i64) i64
  return 0 if n < 3 || n > 40 || nv != n * (n - 1) / 2 || nc > 400000
  return 0 if nc < 1 || offs.size < nc || lens.size < nc
  return 0 if wassat_ramsey_lex_stop(work, deadline) != 0
  choose = i64[(n + 1) * 9]
  v = 0
  while v <= n
    choose[v * 9] = 1
    k = 1
    while k <= 8 && k <= v
      choose[v * 9 + k] = choose[(v - 1) * 9 + k - 1] + choose[(v - 1) * 9 + k]
      k += 1
    v += 1
  eu = i64[nv + 1]
  ev = i64[nv + 1]
  seen_edge = i64[nv + 1]
  e = 1
  u = 0
  while u < n
    v = u + 1
    while v < n
      eu[e] = u
      ev[e] = v
      e += 1
      v += 1
    u += 1
  width_k = i64[29]
  k = 3
  while k <= 8
    width_k[k * (k - 1) / 2] = k
    k += 1
  rank = i64[nc]
  group = i8[nc]
  expected = i64[18]
  ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_ramsey_lex_stop(work, deadline) != 0
    width = lens[ci]
    return 0 if width < 3 || width > 28
    k = width_k[width]
    return 0 if k == 0
    off = offs[ci]
    return 0 if off < 0 || off > lits.size || width > lits.size - off
    first = lits[off]
    negative = first < 0 ? 1 : 0
    vertices = 0
    j = 0
    while j < width
      lit = lits[off + j]
      return 0 if lit == 0 || lit > nv || lit < 0 - nv
      return 0 if (lit < 0 ? 1 : 0) != negative
      e = lit < 0 ? 0 - lit : lit
      return 0 if e > nv || seen_edge[e] == ci + 1
      seen_edge[e] = ci + 1
      vertices |= 1 << eu[e]
      vertices |= 1 << ev[e]
      j += 1
    work[4] += width
    # Enumerating the vertex bits in increasing order gives the combinadic
    # rank sum C(vertex,t), a bijection onto [0,C(n,k)) for k-subsets.
    t = 0
    r = 0
    v = 0
    while v < n
      if (vertices & (1 << v)) != 0
        t += 1
        return 0 if t > k
        r += choose[v * 9 + t]
        work[8] += 1
      v += 1
    return 0 if t != k
    # Distinct edges with k endpoints and C(k,2) members form a clique.
    g = negative * 9 + k
    expected[g] = choose[n * 9 + k]
    rank[ci] = r
    group[ci] = g
    work[3] += 1
    ci += 1
  base = i64[18]
  count = i64[18]
  total = 0
  g = 0
  while g < 18
    base[g] = total
    total += expected[g]
    work[5] += 1 if expected[g] > 0
    g += 1
  # Each required distinct clique must have appeared in an actual clause.
  return 0 if total > nc
  seen = i8[total]
  ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_ramsey_lex_stop(work, deadline) != 0
    g = group[ci]
    r = rank[ci]
    return 0 if r < 0 || r >= expected[g]
    slot = base[g] + r
    if seen[slot] == 0
      seen[slot] = 1
      count[g] += 1
      work[6] += 1
    else
      work[7] += 1
    ci += 1
  g = 0
  while g < 18
    return 0 if count[g] != expected[g]
    g += 1
  return 0 if wassat_ramsey_lex_stop(work, deadline) != 0
  work[0] = 1
  1

# Emit one clause without allocating a temporary literal array. A zero
# prefix denotes the first comparison, whose equality prefix is true.
-> wassat_ramsey_lex_clause(lits, offs, lens, state, prefix, a, b, z) (i64[] i64[] i64[] i64[] i64 i64 i64 i64)
  ci = state[0]
  pos = state[1]
  offs[ci] = pos
  if prefix != 0
    lits[pos] = 0 - prefix
    pos += 1
  lits[pos] = a
  lits[pos + 1] = b
  pos += 2
  if z != 0
    lits[pos] = z
    pos += 1
  lens[ci] = pos - offs[ci]
  state[0] = ci + 1
  state[1] = pos
  0

-> wassat_ramsey_lex_fill(src, soff, slen, out, off, len, nv, nc, n, work, deadline) (i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64[] i64) i64
  state = i64[2]
  ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_ramsey_lex_stop(work, deadline) != 0
    off[ci] = state[1]
    len[ci] = slen[ci]
    j = 0
    while j < slen[ci]
      out[state[1]] = src[soff[ci] + j]
      state[1] += 1
      j += 1
    ci += 1
  work[14] = state[1]
  state[0] = nc
  edge = i64[n * n]
  e = 1
  i = 0
  while i < n
    j = i + 1
    while j < n
      edge[i * n + j] = e
      edge[j * n + i] = e
      e += 1
      j += 1
    i += 1
  nextvar = nv + 1
  i = 0
  while i < n
    j = i + 1
    while j < n
      return 0 if wassat_ramsey_lex_stop(work, deadline) != 0
      prefix = 0
      t = 0
      k = 0
      while k < n
        if k != i && k != j
          a = edge[i * n + k]
          b = edge[j * n + k]
          # prefix -> a <= b
          wassat_ramsey_lex_clause(out, off, len, state, prefix, 0 - a, b, 0)
          t += 1
          if t < n - 2
            # Equality extends the prefix. Reverse implications are not
            # needed: after the first strict ascent all later prefixes may
            # be false, giving exactly the existential lex-order relation.
            wassat_ramsey_lex_clause(out, off, len, state, prefix, 0 - a, 0 - b, nextvar)
            wassat_ramsey_lex_clause(out, off, len, state, prefix, a, b, nextvar)
            prefix = nextvar
            nextvar += 1
          work[13] += 1
        k += 1
      work[12] += 1
      j += 1
    i += 1
  work[9] = state[0]
  work[10] = state[1]
  work[11] = nextvar - nv - 1
  return 0 if wassat_ramsey_lex_stop(work, deadline) != 0
  1

-> wassat_ramsey_lex_lift(formula, deadline = 0)
  return nil unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return nil if nv < 3 || nv > 780 || nc < 1 || nc > 400000
  n = 3
  while n <= 40 && n * (n - 1) / 2 < nv
    n += 1
  return nil if n > 40 || n * (n - 1) / 2 != nv
  work = i64[16]
  work[2] = n
  return nil unless wassat_ramsey_lex_check(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], nv, nc, n, work, deadline) == 1
  # Per transposition: m order clauses and 2*(m-1) prefix clauses.
  # First comparison has no prefix literal; the last has no new auxiliary.
  pairs = n * (n - 1) / 2
  m = n - 2
  added_clauses = pairs * (3 * m - 2)
  added_literals = pairs * (m == 1 ? 2 : 11 * m - 11)
  added_vars = pairs * (m - 1)
  out = i64[work[4] + added_literals]
  off = i64[nc + added_clauses]
  len = i64[nc + added_clauses]
  return nil unless wassat_ramsey_lex_fill(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], out, off, len, nv, nc, n, work, deadline) == 1
  raise "internal error: Ramsey lex clause count" unless work[9] == nc + added_clauses
  raise "internal error: Ramsey lex literal count" unless work[10] == out.size
  raise "internal error: Ramsey lex auxiliary count" unless work[11] == added_vars
  lifted = { "nvars": nv + added_vars, "nclauses": work[9], "clauses": [], "boxed": false,
    "flat_lits": out, "flat_offs": off, "flat_lens": len,
    "flat_ncl": work[9], "flat_nlits": work[10] }
  { "formula": lifted, "work": work }
