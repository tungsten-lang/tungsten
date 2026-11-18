# Recover compact Boolean domains from the connected components of binary
# clauses. A clause over two components forbids the Cartesian product of its
# two falsifying value sets. All masks below refer to actual local assignments.
use block_csp
use domain_walk
use parity_sum
use permuted_capacity
use cnf

-> wassat_compact_components(lits, offs, lens, nc, nv, owner, bit, widths) (i64[] i64[] i64[] i64 i64 i64[] i64[] i64[]) i64
  parent = i64[nv+1]; size = i64[nv+1]
  v = 1
  while v <= nv
    parent[v] = v; size[v] = 1; v += 1
  ci = 0
  while ci < nc
    if lens[ci] == 2
      p = offs[ci]; x = lits[p]; y = lits[p+1]
      a = wassat_parity_find(parent, x < 0 ? 0-x : x)
      b = wassat_parity_find(parent, y < 0 ? 0-y : y)
      if a != b
        return 0 if size[a]+size[b] > 5
        parent[b] = a; size[a] += size[b]
    ci += 1
  by_root = i64[nv+1]; nb = 0; v = 1
  while v <= nv
    r = wassat_parity_find(parent, v)
    return 0 if size[r] < 2
    if by_root[r] == 0
      return 0 if nb == 128
      nb += 1; by_root[r] = nb
    g = by_root[r]-1
    bit[v] = widths[g]; widths[g] += 1; owner[v] = g
    v += 1
  nb

-> wassat_compact_solve(formula)
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  return nil if nv < 4 || nv > 640 || nc < 2 || nc > WASSAT_BLOCK_MAX_CLAUSES
  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  owner = i64[nv+1]; bit = i64[nv+1]; widths = i64[128]
  nb = wassat_compact_components(lits, offs, lens, nc, nv, owner, bit, widths)
  return nil if nb < 2
  started = wassat_prof_clock()
  # All binary clauses lie within a recovered component. Filter its at most
  # 32 assignments first, so the DFS sees only the live domain values.
  raw = i64[nb]; g = 0
  while g < nb
    raw[g] = (1 << (1 << widths[g])) - 1; g += 1
  ci = 0
  while ci < nc
    if lens[ci] == 2
      pos = offs[ci]; x = lits[pos]; y = lits[pos+1]
      u = x < 0 ? 0-x : x; v = y < 0 ? 0-y : y; g = owner[u]
      mask = raw[g]
      while mask != 0
        p = wassat_block_ctz64(mask); mask &= mask-1
        if (((p >> bit[u]) & 1) == 0) == (x > 0) && (((p >> bit[v]) & 1) == 0) == (y > 0)
          raw[g] ^= 1 << p
    ci += 1
  dom = i64[nb]
  truth = i64[nv+1]; masks = i64[nb*5]
  g = 0
  while g < nb
    n = wassat_block_pop64(raw[g])
    return nil if n == 0 || n > WASSAT_BLOCK_MAX_SIZE
    dom[g] = (1 << n)-1; mask = raw[g]; j = 0
    while mask != 0
      p = wassat_block_ctz64(mask); mask &= mask-1
      i = 0
      while i < widths[g]
        masks[g*5+i] |= 1 << j if ((p >> i) & 1) != 0
        i += 1
      j += 1
    g += 1
  v = 1
  while v <= nv
    truth[v] = masks[owner[v]*5+bit[v]]; v += 1
  wassat_pattern_search(formula, nb, owner, truth, dom, true, started)

# A signed one-hot row supplies a literal for each value. On an exactly-one
# proposal the original variable is true either at this value or at all other
# values, according to its sign. Side clauses still constrain this proposal.
-> wassat_signed_domain_solve(formula, width, capacity_only = false)
  nv = formula["nvars"]; nc = formula["flat_ncl"]
  return nil if width < 3 || width > WASSAT_BLOCK_MAX_SIZE || nv % width != 0
  nb = nv / width
  return nil if nb < 2 || nb > 128 || nc > WASSAT_BLOCK_MAX_CLAUSES
  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  owner = i64[nv+1]; truth = i64[nv+1]; dom = i64[nb]
  row_ids = i64[nb]; value = i64[nv+1]
  full = (1 << width)-1; g = 0; ci = 0; signed = false
  while ci < nc
    if lens[ci] == width
      return nil if g >= nb
      offset = offs[ci]; j = 0
      row_ids[g] = ci+1
      while j < width
        lit = lits[offset+j]; v = lit < 0 ? 0-lit : lit
        return nil if truth[v] != 0
        owner[v] = g
        truth[v] = lit > 0 ? 1 << j : full ^ (1 << j)
        value[v] = lit > 0 ? j+1 : 0-(j+1)
        signed = true if lit < 0
        j += 1
      dom[g] = full; g += 1
    ci += 1
  return nil unless g == nb && (signed || capacity_only)
  clique = wassat_permuted_clique(formula, row_ids, owner, value, nb, width)
  if clique != nil
    return {"status": -1, "blocks": nb, "nodes": 0, "witness": clique}
  return nil if capacity_only
  wassat_pattern_search(formula, nb, owner, truth, dom, false, wassat_prof_clock())

-> wassat_pattern_search(formula, nb, owner, truth, dom, binary_decoded, started)
  nv = formula["nvars"]; nc = formula["flat_ncl"]; stride = WASSAT_BLOCK_MAX_SIZE
  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  forbid = i64[nb*stride*nb]; ci = 0
  while ci < nc
    if lens[ci] != 2 || !binary_decoded
      a = -1; b = -1; ma = 0; mb = 0; j = 0
      while j < lens[ci]
        lit = lits[offs[ci]+j]; v = lit < 0 ? 0-lit : lit; g = owner[v]
        bad = lit < 0 ? truth[v] : dom[g] ^ (dom[g] & truth[v])
        if a < 0 || g == a
          if a < 0
            a = g; ma = bad
          else
            ma &= bad
        elsif b < 0 || g == b
          if b < 0
            b = g; mb = bad
          else
            mb &= bad
        else
          return nil
        j += 1
      return nil if a < 0
      if b < 0
        dom[a] ^= dom[a] & ma
        return nil if dom[a] == 0
      else
        mask = ma
        while mask != 0
          p = wassat_block_ctz64(mask); mask &= mask-1
          forbid[(a*stride+p)*nb+b] |= mb
        mask = mb
        while mask != 0
          p = wassat_block_ctz64(mask); mask &= mask-1
          forbid[(b*stride+p)*nb+a] |= ma
    ci += 1
  started = wassat_prof("compact_domains.decode", started)
  # Every clause has been compiled to a unary mask or a binary relation, so
  # the existing MRV search needs an empty residual-clause list for each group.
  space = (nb+1)*nb; ds = i64[space]; choices = i64[space]; applied = i8[space]
  sol = i64[nb]; limits = i64[3]; limits[1] = 10000
  ids = i64[nb*stride]; i = 0
  while i < ids.size
    ids[i] = i; i += 1
  g = 0
  while g < nb
    ds[g] = dom[g]; choices[g] = -1; g += 1
  found = wassat_block_csp_dfs(lits, offs, lens, owner, truth, ids, forbid,
    i64[nb+1], i64[0], ds, choices, applied, sol, limits, nb, 0)
  started = wassat_prof("compact_domains.search", started)
  moves = 0
  if !found && limits[2] != 0
    m = i64[24]
    found = wassat_pattern_walk(nb, dom, forbid, sol, m, !binary_decoded) == 1
    moves = m[7]
    z = wassat_prof("compact_domains.tabu", started)
  return nil unless found
  model = i64[nv]; v = 1
  while v <= nv
    g = owner[v]
    model[v-1] = ((truth[v] >> sol[g]) & 1) == 1 ? v : 0-v
    v += 1
  return nil unless wassat_model_satisfies?(formula, model)
  {"status": 1, "model": model, "blocks": nb, "nodes": limits[0], "moves": moves}

# The existing tabu worker uses fixed table strides so its incremental update
# loop can also run in portfolio threads. Expand the smaller DFS table only
# when its node budget expires. An exhaustive DFS miss already excludes all
# proposals in these domains.
-> wassat_pattern_walk(nb, dom, forbid, sol, m, restart) (i64 i64[] i64[] i64[] i64[] bool) i64
  size = WASSAT_DOMAIN_MAX_SIZE; blocks = WASSAT_DOMAIN_MAX_BLOCKS
  vars = i64[nb*size]; widths = i64[nb]
  table = i64[nb*WASSAT_BLOCK_MAX_SIZE*blocks]
  g = 0
  while g < nb
    d = dom[g]; j = 0
    while d != 0
      u = g*WASSAT_BLOCK_MAX_SIZE+j
      vars[g*size+j] = u; h = 0
      while h < nb
        table[u*blocks+h] = forbid[u*nb+h]; h += 1
      d = d >> 1; j += 1
    widths[g] = j; g += 1
  off = i64[nb+1]; neighbors = i64[nb*nb]
  edges = wassat_domain_neighbors(vars, widths, table, off, neighbors, nb)
  m[13] = nb*nb; stop = i64[4]
  deadline = clock_ms()+150
  # The two signed-domain trajectories reach different near-solutions. Let
  # each continue until a model or the common deadline. Only the tables are
  # shared for reading. Each trajectory owns its assignments and scores.
  if restart && !wassat_sequential? && System.cpu_count > 1
    other_sol = i64[nb]; other = i64[24]; other[13] = nb*nb
    worker = Thread.new -> wassat_pattern_trial(vars, widths, table, dom, other_sol, off, neighbors, other, stop, nb, 11, 100000, deadline)
    begin
      hit = wassat_pattern_trial(vars, widths, table, dom, sol, off, neighbors, m, stop, nb, 1, 100000, deadline)
    ensure
      z = worker.join
    m[7] += other[7]
    return 1 if m[0] == 1
    return 0 unless other[0] == 1
    g = 0
    while g < nb
      sol[g] = other_sol[g]; g += 1
    return 1
  first = restart ? 25000 : 100000
  hit = wassat_pattern_trial(vars, widths, table, dom, sol, off, neighbors, m, stop, nb, 1, first, deadline)
  return hit if hit == 1 || !restart || m[2] != 0
  wassat_pattern_trial(vars, widths, table, dom, sol, off, neighbors, m, stop, nb, 11, 100000-first, deadline)

-> wassat_pattern_trial(vars, widths, table, dom, sol, off, neighbors, m, stop, nb, seed, steps, deadline) (i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64[] i64 i64 i64 i64) i64
  n = nb*WASSAT_DOMAIN_MAX_SIZE
  hit = wassat_domain_tabu(vars, widths, table, dom, sol, i64[n], i64[n],
    off, neighbors, i64[nb], m, stop, nb, seed, steps, deadline)
  if hit == 1
    m[0] = 1
    z = wassat_stop_publish(stop, 1)
  hit
