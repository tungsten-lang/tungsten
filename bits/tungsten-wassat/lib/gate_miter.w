# Grouped Tseitin gates with an asserted XOR/XNOR comparator. Signatures
# nominate pairs; only UNSAT assumption queries can license new clauses.
-> wassat_gm_decode_rows(lits, offs, lens, ci, last, v, args, arity, table) (i64[] i64[] i64[] i64 i64 i64 i64[] i64[] i64[]) bool
  n = 0
  i = ci
  while i < last
    j = 1
    while j < lens[i]
      u = lits[offs[i] + j].abs
      return false if u == v
      k = 0
      while k < n && args[4*v + k] != u
        k += 1
      if k == n
        return false if n == 4
        args[4*v + n] = u
        n += 1
      j += 1
    i += 1
  arity[v] = n
  mask = (1 << (1 << n)) - 1
  allow0 = mask
  allow1 = mask
  i = ci
  while i < last
    bad = mask
    j = 1
    while j < lens[i]
      lit = lits[offs[i]+j]
      k = 0
      while args[4*v+k] != lit.abs
        k += 1
      pattern = 43690
      pattern = 52428 if k == 1
      pattern = 61680 if k == 2
      pattern = 65280 if k == 3
      bad &= lit > 0 ? (pattern ^ -1) : pattern
      j += 1
    if lits[offs[i]] > 0
      allow0 &= (bad ^ -1)
    else
      allow1 &= (bad ^ -1)
    i += 1
  table[v] = allow1
  (allow0 ^ allow1) == mask

-> wassat_gm_cone(root, args, arity, flags, side, queue) (i64 i64[] i64[] i64[] i64 i64[])
  queue[0] = root
  flags[root] |= side
  i = 0
  n = 1
  while i < n
    v = queue[i]
    i += 1
    j = 0
    while j < arity[v]
      u = args[4*v+j]
      if (flags[u] & side) == 0
        flags[u] |= side
        queue[n] = u
        n += 1
      j += 1
  n

-> wassat_gm_schedule(f)
  nc = f["flat_ncl"]
  nv = f["nvars"]
  return nil if nc < 5 || nv > 65536 || nc > 262144
  lens = f["flat_lens"] ## i64[]
  offs = f["flat_offs"] ## i64[]
  lits = f["flat_lits"] ## i64[]
  return nil unless lens[0] == 3 && lens[1] == 3 && lens[2] == 3 && lens[3] == 3
  root = lits[0].abs
  return nil unless lits[offs[1]].abs == root && lits[offs[2]].abs == root && lits[offs[3]].abs == root
  arity = i64[nv+1]; args = i64[4*(nv+1)]; table = i64[nv+1]; fixed = i64[nv+1]
  ci = 0
  gates = 0
  assertion = 0
  while ci < nc
    return nil if lens[ci] == 0
    lit = lits[offs[ci]]
    v = lit.abs
    if lens[ci] == 1
      return nil if fixed[v] != 0
      fixed[v] = lit
      assertion = lit if v == root
      ci += 1
    else
      return nil if arity[v] != 0 || gates >= 16384
      last = ci + 1
      while last < nc && lens[last] > 1 && lits[offs[last]].abs == v
        last += 1
      return nil if last-ci > 16
      return nil unless wassat_gm_decode_rows(lits, offs, lens, ci, last, v, args, arity, table)
      return nil if v == root && !(arity[v] == 2 && (table[v] == 6 || table[v] == 9))
      gates += 1
      ci = last
  return nil if assertion == 0
  a = args[4*root]; b = args[4*root+1]
  flags = i64[nv+1]; queue = i64[nv+1]
  wassat_gm_cone(a,args,arity,flags,1,queue)
  wassat_gm_cone(b,args,arity,flags,2,queue)
  depth = i64[nv+1]; sig = i64[16*(nv+1)]
  order = []
  seed = 846
  v = 1
  while v <= nv
    if arity[v] > 0
      return nil if v != root && (flags[v] == 0 || fixed[v] != 0)
      depth[v] = -1
    elsif flags[v] != 0
      order.push(v)
      j = 0
      while j < 16
        seed ^= seed << 13
        seed ^= seed >> 7
        seed ^= seed << 17
        sig[16*v+j] = fixed[v] == 0 ? seed : (fixed[v] > 0 ? -1 : 0)
        j += 1
    v += 1
  # Reverse fanout lists allow a topological pass even if the two circuits
  # use different variable numbering. A gate enters the queue exactly once.
  heads = i64[nv + 1]
  links = i64[4 * gates + 1]
  sinks = i64[4 * gates + 1]
  pending = i64[nv + 1]
  edges = 0
  count = 0
  v = 1
  while v <= nv
    if arity[v] > 0
      j = 0
      while j < arity[v]
        u = args[4*v+j]
        if arity[u] > 0
          pending[v] += 1
          edges += 1
          sinks[edges] = v
          links[edges] = heads[u]
          heads[u] = edges
        j += 1
      if pending[v] == 0
        queue[count] = v
        count += 1
    v += 1
  i = 0
  while i < count
    v = queue[i]
    level = 0
    j = 0
    while j < arity[v]
      dep = depth[args[4*v+j]]
      level = dep if dep > level
      j += 1
    depth[v] = level + 1
    order.push(depth[v]*(nv+1)+v) if v != root
    row = 0
    while row < (1 << arity[v])
      if (table[v] & (1 << row)) != 0
        k = 0
        while k < 16
          term = -1
          j = 0
          while j < arity[v]
            word = sig[16*args[4*v+j]+k]
            term &= (row & (1 << j)) == 0 ? (word ^ -1) : word
            j += 1
          sig[16*v+k] |= term
          k += 1
      row += 1
    edge = heads[v]
    while edge != 0
      u = sinks[edge]
      pending[u] -= 1
      if pending[u] == 0
        queue[count] = u
        count += 1
      edge = links[edge]
    i += 1
  return nil if count != gates
  j = 0
  while j < 16
    return nil if sig[16*root+j] != (assertion > 0 ? 0 : -1)
    j += 1
  reps = {}
  pairs = []
  cross = false
  order.sort.each -> (key)
    x = key % (nv+1)
    word = sig[16*x]
    h = word < 0 ? (word ^ -1) : word
    if reps.has_key?(h)
      y = reps[h]
      flip = word == sig[16*y] ? 0 : -1
      same = true
      k = 1
      while k < 16
        same = false if sig[16*x+k] != (sig[16*y+k] ^ flip)
        k += 1
      if same && !((x == a && y == b) || (x == b && y == a))
        pairs.push(x)
        pairs.push(flip == 0 ? y : 0-y)
        cross = true if (flags[x] == 1 && flags[y] == 2) || (flags[x] == 2 && flags[y] == 1)
    else
      reps[h] = x
  return nil unless cross
  { "pairs": pairs, "assertion": assertion }

-> wassat_gm_solve(f, plan, mode, path)
  started = clock_ms()
  rows = []
  nc = f["flat_ncl"]
  lens = f["flat_lens"] ## i64[]
  offs = f["flat_offs"] ## i64[]
  lits = f["flat_lits"] ## i64[]
  assertion = plan["assertion"]
  ci = 0
  while ci < nc
    unless lens[ci] == 1 && lits[offs[ci]] == assertion
      row = []
      j = 0
      while j < lens[ci]
        row.push(lits[offs[ci]+j])
        j += 1
      rows.push(row)
    ci += 1
  solver = Wassat.new(f["nvars"], rows, mode)
  solver.stream_proofs(nil,path) if path != nil
  pairs = plan["pairs"]
  i = 0
  proved = 0
  deadline = started + 45000
  while i < pairs.size && clock_ms() < deadline
    x = pairs[i]; y = pairs[i+1]
    sign = 1
    while sign >= -1
      u = sign*x; v = sign*y
      r = solver.solve_assuming_budget([u,0-v],15000)
      break unless r["status"] == -1
      fact = [0-u,v]
      solver.reset_query
      solver.log_clause(fact) if mode != WASSAT_PROOF_NONE
      solver.add_input_clause(fact)
      proved += 1
      sign -= 2
    i += 2
  wassat_prof_note("gate_miter directions=[proved] candidates=[pairs.size / 2] sweep_ms=[clock_ms() - started]") if env("WASSAT_PROFILE") == "1"
  # The comparator assertion is an original unit. Restore it only after
  # the sweep so the two directions were established independently of it.
  solver.reset_query
  solver.add_input_clause([assertion])
  r = solver.solve_budget(200000)
  solver.flush_proof_sinks if path != nil
  r
