# A required row contributes one selected literal. If the choices of some
# rows fit into fewer mutually exclusive groups, their demands cannot be met.
# Binary implication paths expose signed aliases after root propagation.
use induction_certificate

WASSAT_HALL_MAX_VARS = 1536
WASSAT_HALL_MAX_CLAUSES = 12000
WASSAT_HALL_MS = 250

-> wassat_hall_code(lit) (i64) i64
  lit < 0 ? 2 * (0 - lit) + 1 : 2 * lit

-> wassat_hall_literal(code) (i64) i64
  (code & 1) == 1 ? 0 - (code >> 1) : code >> 1

# Each edge is a residual binary under the original unit consequences.
# reach[s, t] includes s itself. Every entry is a sound implication s -> t.
-> wassat_hall_paths(lits, offs, lens, roots, nv, nc, reach, deadline) (i64[] i64[] i64[] i8[] i64 i64 i8[] i64) i64
  stride = 2 * nv + 2
  heads = i32[stride]
  next_edge = i32[2 * nc + 1]
  target = i32[2 * nc + 1]
  edges = 0
  ci = 0
  while ci < nc
    a = 0
    b = 0
    n = 0
    j = 0
    while j < lens[ci] && n < 3
      lit = lits[offs[ci] + j]
      var = lit < 0 ? 0 - lit : lit
      value = lit < 0 ? 0 - roots[var] : roots[var]
      if value > 0
        n = 3
      elsif value == 0
        n += 1
        if n == 1
          a = wassat_hall_code(lit)
        else
          b = wassat_hall_code(lit)
      j += 1
    if n == 2
      u = a ^ 1
      edges += 1
      next_edge[edges] = heads[u]
      heads[u] = edges
      target[edges] = b
      u = b ^ 1
      edges += 1
      next_edge[edges] = heads[u]
      heads[u] = edges
      target[edges] = a
    ci += 1
  queue = i32[stride]
  s = 2
  while s < stride
    return 0 if (s & 31) == 0 && deadline != 0 && clock_ms() >= deadline
    base = s * stride
    reach[base + s] = 1
    queue[0] = s
    tail = 1
    head = 0
    while head < tail
      e = heads[queue[head]] ## i64
      while e > 0
        v = target[e] ## i64
        if reach[base + v] == 0
          reach[base + v] = 1
          queue[tail] = v
          tail += 1
        e = next_edge[e]
      head += 1
    s += 1
  1

-> wassat_hall_representatives(reach, stride) (i8[] i64) i32[]
  rep = i32[stride]
  a = 2
  while a < stride
    b = 2
    while b < a && (reach[a * stride + b] == 0 || reach[b * stride + a] == 0)
      b += 1
    # Opposite signs share a representative variable.
    rep[a] = b
    rep[a + 1] = b ^ 1
    a += 2
  rep

-> wassat_hall_rows(formula, roots, reach, rep, stride, deadline)
  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  rows = []
  occupied = i8[stride]
  nc = formula["flat_ncl"]
  ci = 0
  while ci < nc
    return nil if (ci & 127) == 0 && deadline != 0 && clock_ms() >= deadline
    if lens[ci] >= 3
      row = []
      j = 0
      ok = true
      while j < lens[ci] && ok
        lit = lits[offs[ci] + j]
        v = lit.abs
        val = lit < 0 ? 0 - roots[v] : roots[v]
        if val > 0
          ok = false
        elsif val == 0
          a = rep[wassat_hall_code(lit)] ## i64
          ok = false if occupied[a >> 1] != 0
          duplicate = false
          k = 0
          while k < row.size && ok
            b = row[k]
            if a == b
              duplicate = true
            elsif a == (b ^ 1) || reach[a * stride + (b ^ 1)] == 0
              ok = false
            k += 1
          row.push(a) if ok && !duplicate
        j += 1
      if ok && row.size >= 3
        row.each -> (a) occupied[a >> 1] = 1
        rows.push(row)
    ci += 1
  rows

# First-fit partitions row choices into capacity-one resources. The proof
# needs only a valid partition, so missing a better partition is a safe miss.
-> wassat_hall_partition(rows, reach, stride, deadline)
  groups = []
  edges = []
  last_row = i32[stride]
  ri = 0
  while ri < rows.size
    return nil if deadline != 0 && clock_ms() >= deadline
    allowed = []
    row = rows[ri]
    i = 0
    while i < row.size
      a = row[i]
      g = 0
      while g < groups.size
        group = groups[g]
        ok = last_row[g] != ri + 1
        j = 0
        while j < group.size && ok
          b = group[j]
          ok = false if reach[a * stride + (b ^ 1)] == 0
          j += 1
        break if ok
        g += 1
      groups.push([]) if g == groups.size
      groups[g].push(a)
      allowed.push(g)
      last_row[g] = ri + 1
      i += 1
    edges.push(allowed)
    ri += 1
  { "groups": groups, "edges": edges }

# A failed augmenting path visits a set of rows and all their resources.
-> wassat_hall_augment(row, edges, mate, visits, touched, epoch)
  return false if visits[row] == epoch
  visits[row] = epoch
  choices = edges[row]
  j = 0
  while j < choices.size
    g = choices[j]
    if touched[g] != epoch
      touched[g] = epoch
      if mate[g] == 0 || wassat_hall_augment(mate[g] - 1, edges, mate, visits, touched, epoch)
        mate[g] = row + 1
        return true
    j += 1
  false

-> wassat_hall_witness(rows, partition)
  edges = partition["edges"]
  groups = partition["groups"]
  mate = i32[groups.size]
  visits = i32[rows.size]
  touched = i32[groups.size]
  i = 0
  while i < rows.size
    epoch = i + 1
    unless wassat_hall_augment(i, edges, mate, visits, touched, epoch)
      demands = []
      used = {}
      r = 0
      while r < rows.size
        if visits[r] == epoch
          demands.push(rows[r])
          rows[r].each -> (a) used[a] = true
        r += 1
      caps = []
      g = 0
      while g < groups.size
        if touched[g] == epoch
          cap = []
          groups[g].each -> (a)
            cap.push(a) if used.has_key?(a)
          caps.push(cap) unless cap.empty?
        g += 1
      return { "rows": demands, "caps": caps } if demands.size > caps.size
      return nil
    i += 1
  nil

# Establish each required row and pair exclusion directly by RUP. Summing the
# row bounds and clique bounds then eliminates each selected literal once.
-> wassat_hall_certificate(solver, witness, nc, emit, deadline)
  proof = StringBuffer()
  proof.append("pseudo-Boolean proof version 3.0\n") if emit
  counters = i64[4]
  last = nc
  bounds = []
  demands = witness["rows"]
  caps = witness["caps"]
  remaining = {}
  return nil if demands.size <= caps.size
  ri = 0
  while ri < demands.size
    row = demands[ri]
    return nil if row.empty?
    return nil if deadline != 0 && clock_ms() >= deadline
    lits = []
    neg = []
    j = 0
    while j < row.size
      a = row[j]
      return nil if remaining.has_key?(a)
      remaining[a] = true
      l = wassat_hall_literal(a)
      lits.push(l)
      neg.push(0 - l)
      j += 1
    return nil unless solver.propagation_snapshot(neg, nil, counters) == -1
    wassat_induction_rup(proof, lits) if emit
    last += 1
    bounds.push(last)
    ri += 1
  covered = 0
  gi = 0
  while gi < caps.size
    cap = caps[gi]
    return nil if cap.empty?
    j = 0
    while j < cap.size
      a = cap[j]
      return nil unless remaining[a] == true
      remaining[a] = false
      covered += 1
      j += 1
    return nil if deadline != 0 && clock_ms() >= deadline
    if cap.size == 1
      lit = 0 - wassat_hall_literal(cap[0])
      if emit
        atom = lit < 0 ? "~x[0 - lit]" : "x[lit]"
        proof.append("rup 1 [atom] >= 0 ;\n")
      last += 1
    else
      k = 1
      while k < cap.size
        b = wassat_hall_literal(cap[k])
        prev = last
        j = 0
        while j < k
          a = wassat_hall_literal(cap[j])
          return nil unless solver.propagation_snapshot([a, b], nil, counters) == -1
          wassat_induction_rup(proof, [0 - a, 0 - b]) if emit
          last += 1
          j += 1
        if k > 1
          if emit
            proof.append("pol [prev] [k - 1] *")
            j = 1
            while j <= k
              proof.append(" [prev + j] +")
              j += 1
            proof.append(" [k] d ;\n")
          last += 1
        k += 1
    bounds.push(last)
    gi += 1
  return nil unless covered == remaining.size
  if emit
    proof.append("pol [bounds[0]]")
    i = 1
    while i < bounds.size
      proof.append(" [bounds[i]] +")
      i += 1
    proof.append(" ;\noutput NONE ;\nconclusion UNSAT : -1 ;\nend pseudo-Boolean proof ;\n")
  proof.to_s

-> wassat_signed_hall(formula, emit, deadline)
  nv = formula["nvars"]
  nc = formula["flat_ncl"]
  return nil if nv < 1 || nv > WASSAT_HALL_MAX_VARS || nc > WASSAT_HALL_MAX_CLAUSES
  return nil if deadline != 0 && clock_ms() >= deadline
  roots = i8[nv + 1]
  solver = Wassat.from_flat(nv, wassat_raw_artifact(formula, nv), WASSAT_PROOF_NONE)
  return nil unless solver.propagation_snapshot([], roots, i64[4]) == 1
  stride = 2 * nv + 2
  reach = i8[stride * stride]
  return nil if wassat_hall_paths(formula["flat_lits"], formula["flat_offs"], formula["flat_lens"], roots,
                                 nv, nc, reach, deadline) == 0
  rep = wassat_hall_representatives(reach, stride)
  rows = wassat_hall_rows(formula, roots, reach, rep, stride, deadline)
  return nil if rows == nil || rows.size < 2
  partition = wassat_hall_partition(rows, reach, stride, deadline)
  return nil if partition == nil
  witness = wassat_hall_witness(rows, partition)
  return nil if witness == nil
  wassat_hall_certificate(solver, witness, nc, emit, deadline)
