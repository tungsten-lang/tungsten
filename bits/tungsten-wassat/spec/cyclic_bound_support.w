use ../lib/wassat

# Direct one-hot encoding; graph proposals may deliberately retain a missing
# premise so the certificate, rather than the recognizer, must reject it.
-> cycle_bound_fixture(n, k, edges, omit = "", aliases = false)
  clauses = []
  col = 0
  while col < n
    row = 0
    clause = []
    while row < n
      clause.push(row * n + col + 1)
      row += 1
    clauses.push(clause) unless omit == "column" && col == 0
    col += 1
  row = 0
  while row < (omit == "high_row" ? 1 : n)
    a = 0
    while a < n
      b = a + 1
      while b < n
        missing = omit == "row" && row == 0 && a == 0 && b == 1
        missing = true if omit == "high_row" && row == 0 && a == n - 2 && b == n - 1
        clauses.push([-(row * n + a + 1), -(row * n + b + 1)]) unless missing
        b += 1
      a += 1
    row += 1
  check_edges = omit == "high_row" ? [] : edges
  check_edges.each -> (edge)
    a = 0
    while a < n
      b = 0
      while b < n
        d = a - b
        d = -d if d < 0
        d = n - d if n - d < d
        if d < k
          clauses.push([-(edge[0] * n + a + 1), -(edge[1] * n + b + 1)]) unless omit == "edge" && edge[0] == 0 && edge[1] == 1 && a == 0 && b == 0
        b += 1
      a += 1
  nv = n * n
  if aliases
    clauses.each -> (c)
      if c.size == 2 && c[0] < 0 && c[1] < 0
        c[0] -= nv
        c[1] -= nv
    v = 1
    while v <= nv
      clauses.push([-v, v + nv])
      clauses.push([v, -v - nv])
      v += 1
    nv *= 2
  nl = 0
  clauses.each -> (c) nl += c.size
  nc = clauses.size
  lits = i64[nl]; offs = i64[nc]; lens = i64[nc]
  ci = 0; at = 0
  clauses.each -> (c)
    offs[ci] = at; lens[ci] = c.size
    c.each -> (lit)
      lits[at] = lit
      at += 1
    ci += 1
  {"nvars": nv, "clauses": clauses, "flat_ncl": nc, "flat_nlits": nl, "flat_lits": lits, "flat_offs": offs, "flat_lens": lens}

-> cycle_bound_check(f, n, k, edges, m, stop, deadline = 0)
  nv = f["nvars"]; nc = f["flat_ncl"]
  lits = f["flat_lits"]; offs = f["flat_offs"]; lens = f["flat_lens"]
  decode = i64[24]
  return 0 unless wassat_cycle_matrix(lits, offs, lens, nv, nc, n, decode, stop, deadline) == 1
  heads = i32[nv + 2]; back = i32[nv + 2]
  dest = i32[decode[4]]; src = i32[decode[4]]; fill = i32[nv + 1]
  owner = i32[nv + 1]; queue = i32[2 * (nv + 1)]
  return 0 unless wassat_cycle_implications(lits, offs, lens, nv, nc, heads, back, dest, src, fill, decode, stop, deadline) == 1
  return 0 unless wassat_cycle_owners(n, nv, heads, dest, owner, queue, decode, stop, deadline) == 1
  matrix = i8[n * n]
  edges.each -> (e)
    matrix[e[0] * n + e[1]] = 1
    matrix[e[1] * n + e[0]] = 1
  left = i32[edges.size]; right = i32[edges.size]
  gh = i32[n + 1]; occ = i32[2 * edges.size]; gf = i32[n]
  wassat_cycle_graph(n, matrix, left, right, gh, occ, gf)
  needed = i8[n * n]
  return 0 unless wassat_cycle_bound_ball(n, k, left, right, gh, occ, needed, m, stop, deadline) == 1
  wassat_cycle_bound_verify(lits, offs, lens, nv, nc, n, k, owner, heads, dest, needed, fill, m, stop, deadline)
