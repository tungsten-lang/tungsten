use decoder

-> wassat_affine_design_node(x) (i64) i64
  x > 0 ? 2 * x : 2 * (0 - x) + 1

# Original binary clauses only. Stamped arrays and the queue are reused.
-> wassat_affine_design_closure(first, tail, offsets, edges, marks, stamp, queue, m, stop) (i64 i64 i64[] i64[] i64[] i64 i64[] i64[] i64[]) i64
  head = 0
  if first >= 0 && marks[first] != stamp
    marks[first] = stamp; queue[tail] = first; tail += 1
  while head < tail
    return 0 if (head & 255) == 0 && wassat_affine_design_poll(m, stop) != 0
    x = queue[head]; head += 1; k = offsets[x]
    while k < offsets[x + 1]
      y = edges[k]; k += 1; m[15] += 1
      return 0 if (m[15] & 1023) == 0 && wassat_affine_design_poll(m, stop) != 0
      if marks[y] != stamp
        marks[y] = stamp; queue[tail] = y; tail += 1
  1

-> wassat_affine_design_verify(formula, d, m, stop)
  nv = formula["nvars"]; nc = formula["flat_ncl"]; lits = formula["flat_lits"]; offs = formula["flat_offs"]; lens = formula["flat_lens"]
  nw = d["nwords"]; q = d["rounds"]; n = d["players"]; which = d["which"]; coord = d["coordinates"]; phase = d["phases"]
  grid = d["grid"]; eq = d["equalities"]; domains = i64[nw]; w = 0
  while w < nw
    domains[w] = 255; w += 1
  ci = 0; nb = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_affine_design_poll(m, stop) != 0
    len = lens[ci]; nb += 1 if len == 2
    if len <= 3
      w = which[wassat_affine_design_abs(lits[offs[ci]])] - 1; local = w >= 0; j = 1
      while j < len && local
        local = false if which[wassat_affine_design_abs(lits[offs[ci] + j])] - 1 != w
        j += 1
      if local
        m[10] += 1; code = 0
        while code < 8
          sat = false; j = 0
          while j < len && !sat
            x = lits[offs[ci] + j]; v = wassat_affine_design_abs(x); value = ((code >> coord[v]) & 1) ^ phase[v]
            sat = true if (x > 0 && value == 1) || (x < 0 && value == 0)
            j += 1
          domains[w] &= 255 ^ (1 << code) unless sat
          code += 1; m[3] += 1
    ci += 1; m[3] += 1
  r = 0
  while r < q
    labels = 0; p = 0
    while p < n
      labels |= domains[grid[r * n + p] - 1]; p += 1
    count = 0; code = 0
    while code < 8
      count += (labels >> code) & 1; code += 1
    return 0 if count > q
    r += 1
  w = 0
  while w < nw
    code = 0
    while code < 8
      m[11] += 1 if (domains[w] & (1 << code)) == 0
      code += 1
    w += 1
  # CSR represents (-a)->b and (-b)->a for each actual binary clause.
  nodes = 2 * nv + 2; offsets = i64[nodes + 1]; cursor = i64[nodes]; edges = i64[2 * nb]
  root = i64[nodes]; marks = i64[nodes]; queue = i64[nodes]; tail = 0; ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_affine_design_poll(m, stop) != 0
    if lens[ci] == 1
      x = wassat_affine_design_node(lits[offs[ci]])
      if root[x] == 0
        root[x] = 1; queue[tail] = x; tail += 1; m[21] += 1
    elsif lens[ci] == 2
      a = wassat_affine_design_node(lits[offs[ci]]); b = wassat_affine_design_node(lits[offs[ci] + 1])
      offsets[(a ^ 1) + 1] += 1; offsets[(b ^ 1) + 1] += 1
    ci += 1; m[3] += 1
  x = 0
  while x < nodes
    offsets[x + 1] += offsets[x]; cursor[x] = offsets[x]; x += 1
  ci = 0
  while ci < nc
    return 0 if (ci & 255) == 0 && wassat_affine_design_poll(m, stop) != 0
    if lens[ci] == 2
      a = wassat_affine_design_node(lits[offs[ci]]); b = wassat_affine_design_node(lits[offs[ci] + 1])
      edges[cursor[a ^ 1]] = b; cursor[a ^ 1] += 1
      edges[cursor[b ^ 1]] = a; cursor[b ^ 1] += 1
    ci += 1; m[3] += 1
  m[22] = 2 * nb
  return 0 if wassat_affine_design_closure(-1, tail, offsets, edges, root, 1, queue, m, stop) == 0
  x = 2
  while x < nodes
    return 0 if root[x] != 0 && root[x ^ 1] != 0
    x += 2
  # Unit-forced inequalities propose a fixed first round. Component membership
  # is insufficient: verify every pair in each final group explicitly below.
  parent = i64[n + 1]; sizes = i64[n + 1]; fixed = i64[n * n]; p = 1
  while p <= n
    parent[p] = p; p += 1
  p = 0
  while p < n
    return 0 if wassat_affine_design_poll(m, stop) != 0
    t = p + 1
    while t < n
      all_false = true; r = 0
      while r < q && all_false
        a = wassat_affine_design_node(eq[r * n * n + p * n + t]); all_false = false if root[a ^ 1] == 0; r += 1
      if all_false
        fixed[p * n + t] = 1; m[13] += 1; z = wassat_affine_design_gauge_join(p + 1, t + 1, 0, parent)
      t += 1
    p += 1
  p = 1
  while p <= n
    root_id = wassat_affine_design_gauge_root(p, parent); sizes[root_id] += 1; p += 1
  groups = 0; p = 1
  while p <= n
    if sizes[p] > 0
      return 0 if sizes[p] != q
      groups += 1
    p += 1
  return 0 if groups != q
  p = 0
  while p < n
    t = p + 1
    while t < n
      if wassat_affine_design_gauge_root(p + 1, parent) == wassat_affine_design_gauge_root(t + 1, parent)
        return 0 if fixed[p * n + t] == 0
        m[28] += q
      t += 1
    p += 1
  # Every pair can agree in at most one free round. Root consequences or an
  # actual binary implication path justify each pair of equality flags.
  stamp = 0; p = 0
  while p < n
    t = p + 1
    while t < n
      r = 0
      while r < q - 1
        return 0 if wassat_affine_design_poll(m, stop) != 0
        a = wassat_affine_design_node(eq[r * n * n + p * n + t]); searched = false; s = r + 1
        while s < q
          b = wassat_affine_design_node(eq[s * n * n + p * n + t])
          if root[a ^ 1] == 0 && root[b ^ 1] == 0
            unless searched
              stamp += 1
              return 0 if wassat_affine_design_closure(a, 0, offsets, edges, marks, stamp, queue, m, stop) == 0
              searched = true
            return 0 if marks[b ^ 1] != stamp
          m[14] += 1; s += 1
        r += 1
      t += 1
    p += 1
  # Any model now induces q+1 partitions of q^2 players into at most q groups.
  # Each partition contributes at least q*C(q,2) pairs. No pair can recur, so
  # (q+1)*q*C(q,2) = C(q^2,2) forces every group to have q players and every
  # pair to occur exactly once. These parallel classes form an affine plane.
  m[23] = 1
  # Pair counting forces an affine plane of order q; its projective completion
  # must satisfy the Bruck-Ryser necessary condition (1949, Theorem 1).
  # https://doi.org/10.4153/CJM-1949-009-2
  m[24] = wassat_affine_design_obstruction(q)
  m[24] > 0 ? -1 : 0

-> wassat_affine_design_obstruction(q)
  return 0 if q < 2
  return 0 unless q % 4 == 1 || q % 4 == 2
  factor = q; divisor = 2; obstruction = 0
  while divisor * divisor <= factor
    exponent = 0
    while factor % divisor == 0
      factor /= divisor; exponent += 1
    obstruction = divisor if divisor % 4 == 3 && exponent % 2 == 1
    divisor += 1
  obstruction = factor if factor > 1 && factor % 4 == 3
  obstruction

-> wassat_affine_design_refute(formula, m, stop, deadline = 0)
  return 0 if m.size < 64 || stop.size < 2
  i = 0
  while i < 64
    m[i] = 0; i += 1
  start = clock_ms(); m[2] = deadline
  d = wassat_affine_design_decode(formula, m, stop); now = clock_ms(); m[16] = now - start
  if d != nil && wassat_affine_design_poll(m, stop) == 0
    m[18] = wassat_affine_design_verify(formula, d, m, stop); m[17] = clock_ms() - now
  m[19] = clock_ms() - start
  m[18]
