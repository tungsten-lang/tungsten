# Exact UNSAT certificate for a graph vertex-cover bound encoded with a
# sequential at-most counter.
#
# The accepted formula is exactly:
#
#   * positive binaries (u | v), describing graph edges; and
#   * the standard row-major sequential counter proving that at most k graph
#     variables may be true.
#
# A true graph variable is a vertex in the cover.  If every connected graph
# component is a clique, its minimum vertex-cover size is exactly |C|-1.
# Therefore
#
#     sum_C (|C|-1) > k
#
# is a complete, directly checkable UNSAT certificate.
#
# Recognition is deliberately strict.  Clause and literal order, variable
# numbering, counter-row numbering, and counter-column numbering are ignored,
# but the complete counter grammar is reconstructed and checked: k vertical
# chains, the diagonal chain ordering, every input link, every overflow
# clause, every initializer, and every expected transition must occur exactly
# once.  Duplicate clauses, unused variables, non-clique graph components, or
# any resource-cap miss fall through to ordinary solving.

WASSAT_AIS_MAX_GRAPH_VARS = 2048
WASSAT_AIS_MAX_BOUND = 512
WASSAT_AIS_MAX_AUX = 1000000
WASSAT_AIS_MAX_CLAUSES = 5000000
WASSAT_AIS_MAX_EDGES = 1000000

-> wassat_ais_miss
  { "recognized": false, "status": 0, "graph_vars": 0,
    "upper_bound": 0, "lower_bound": 0, "components": 0 }

# Return status -1 only after reconstructing the exact counter and verifying
# the clique-cover lower bound.  Status zero is a one-sided fall-through.
-> wassat_ais_unsat(formula)
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return wassat_ais_miss if nv < 5 || ncl < 6
  return wassat_ais_miss if nv > WASSAT_AIS_MAX_AUX + WASSAT_AIS_MAX_GRAPH_VARS
  return wassat_ais_miss if ncl > WASSAT_AIS_MAX_CLAUSES

  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]

  # Counter clauses never contain two positive literals.  Their union is
  # therefore an order-independent definition of the graph-variable set.
  graph = i8[nv + 1]
  graph_edges = 0
  ngraph = 0
  ci = 0
  while ci < ncl
    n = lens[ci]
    # The exact counter/graph grammar contains only units, binaries, and
    # ternaries. Most unrelated formulas therefore leave after a handful of
    # length reads rather than paying a whole structural scan.
    return wassat_ais_miss if n < 1 || n > 3
    if n == 2
      off = offs[ci]
      a = lits[off]
      b = lits[off + 1]
      if a > 0 && b > 0
        return wassat_ais_miss if a == b
        if graph[a] == 0
          graph[a] = 1
          ngraph += 1
        if graph[b] == 0
          graph[b] = 1
          ngraph += 1
        return wassat_ais_miss if ngraph > WASSAT_AIS_MAX_GRAPH_VARS
        graph_edges += 1
        return wassat_ais_miss if graph_edges > WASSAT_AIS_MAX_EDGES
    ci += 1

  return wassat_ais_miss if ngraph < 3

  # In this counter grammar the first row has k-1 negative unit
  # initializers.  k=1 is a safe unsupported narrowing.
  unit_count = 0
  ci = 0
  while ci < ncl
    if lens[ci] == 1
      l = lits[offs[ci]]
      unit_count += 1 if l < 0 && graph[0 - l] == 0
    ci += 1
  kbound = unit_count + 1
  return wassat_ais_miss if kbound < 2
  return wassat_ais_miss if kbound > WASSAT_AIS_MAX_BOUND

  naux = nv - ngraph
  return wassat_ais_miss if naux > WASSAT_AIS_MAX_AUX
  return wassat_ais_miss unless naux == (ngraph - 1) * kbound

  want_units = kbound - 1
  want_input_links = ngraph - 1
  want_aux_links = (ngraph - 2) * kbound
  want_overflows = ngraph - 1
  want_ternaries = (ngraph - 2) * (kbound - 1)
  want_counter = want_units + want_input_links + want_aux_links + want_overflows + want_ternaries
  return wassat_ais_miss unless ncl == want_counter + graph_edges

  # Compact graph ids keep the clique matrix bounded by graph size rather
  # than by the much larger counter-variable range.
  graph_id = i64[nv + 1]
  graph_var = i64[ngraph]
  gi = 0
  v = 1
  while v <= nv
    if graph[v] != 0
      graph_id[v] = gi + 1
      graph_var[gi] = v
      gi += 1
    v += 1
  adj = i8[ngraph * ngraph]

  unit = i8[nv + 1]
  next_aux = i64[nv + 1]
  prev_aux = i64[nv + 1]
  input_link = i64[nv + 1]       # positive aux -> negative graph input
  input_cell = i64[nv + 1]       # graph input -> positive aux
  overflow_aux = i64[nv + 1]     # graph input -> negative aux
  overflow_owner = i64[nv + 1]   # aux -> graph input
  ternary_clause = i64[want_ternaries]

  seen_units = 0
  seen_input_links = 0
  seen_aux_links = 0
  seen_overflows = 0
  seen_ternaries = 0
  seen_graph_edges = 0

  # Classify every clause by literal roles.  Every accepted category has one
  # exact place in the sequential-counter grammar.
  ci = 0
  while ci < ncl
    n = lens[ci]
    off = offs[ci]
    if n == 1
      l = lits[off]
      return wassat_ais_miss if l >= 0
      a = 0 - l
      return wassat_ais_miss if graph[a] != 0 || unit[a] != 0
      unit[a] = 1
      seen_units += 1
    elsif n == 2
      l0 = lits[off]
      l1 = lits[off + 1]
      if l0 > 0 && l1 > 0
        return wassat_ais_miss unless graph[l0] != 0 && graph[l1] != 0
        return wassat_ais_miss if l0 == l1
        a = graph_id[l0] - 1
        b = graph_id[l1] - 1
        return wassat_ais_miss if adj[a * ngraph + b] != 0
        adj[a * ngraph + b] = 1
        adj[b * ngraph + a] = 1
        seen_graph_edges += 1
      elsif (l0 > 0) != (l1 > 0)
        p = l0 > 0 ? l0 : l1
        m = l0 < 0 ? 0 - l0 : 0 - l1
        # The positive head is always a counter cell.
        return wassat_ais_miss if graph[p] != 0
        if graph[m] != 0
          return wassat_ais_miss if input_link[p] != 0
          return wassat_ais_miss if input_cell[m] != 0
          input_link[p] = m
          input_cell[m] = p
          seen_input_links += 1
        else
          return wassat_ais_miss if p == m
          return wassat_ais_miss if next_aux[m] != 0
          return wassat_ais_miss if prev_aux[p] != 0
          next_aux[m] = p
          prev_aux[p] = m
          seen_aux_links += 1
      else
        # The only all-negative binary is an input/counter overflow guard.
        return wassat_ais_miss if l0 >= 0 || l1 >= 0
        a = 0 - l0
        b = 0 - l1
        if graph[a] != 0 && graph[b] == 0
          x = a
          cell = b
        elsif graph[b] != 0 && graph[a] == 0
          x = b
          cell = a
        else
          return wassat_ais_miss
        return wassat_ais_miss if overflow_aux[x] != 0
        return wassat_ais_miss if overflow_owner[cell] != 0
        overflow_aux[x] = cell
        overflow_owner[cell] = x
        seen_overflows += 1
    elsif n == 3
      positive_aux = 0
      negative_aux = 0
      negative_input = 0
      j = 0
      while j < 3
        l = lits[off + j]
        if l > 0
          return wassat_ais_miss if graph[l] != 0 || positive_aux != 0
          positive_aux = l
        else
          a = 0 - l
          if graph[a] != 0
            return wassat_ais_miss if negative_input != 0
            negative_input = a
          else
            return wassat_ais_miss if negative_aux != 0
            negative_aux = a
        j += 1
      return wassat_ais_miss if positive_aux == 0 || negative_aux == 0 || negative_input == 0
      return wassat_ais_miss if seen_ternaries >= want_ternaries
      ternary_clause[seen_ternaries] = ci
      seen_ternaries += 1
    else
      return wassat_ais_miss
    ci += 1

  return wassat_ais_miss unless seen_units == want_units
  return wassat_ais_miss unless seen_input_links == want_input_links
  return wassat_ais_miss unless seen_aux_links == want_aux_links
  return wassat_ais_miss unless seen_overflows == want_overflows
  return wassat_ais_miss unless seen_ternaries == want_ternaries
  return wassat_ais_miss unless seen_graph_edges == graph_edges

  # The aux implication graph must be exactly k disjoint vertical chains,
  # each with n-1 cells.  Chain and row ids are reconstructed, not inferred
  # from variable numbering.
  roots = i64[kbound]
  nroots = 0
  v = 1
  while v <= nv
    if graph[v] == 0 && prev_aux[v] == 0
      return wassat_ais_miss if nroots >= kbound
      roots[nroots] = v
      nroots += 1
    v += 1
  return wassat_ais_miss unless nroots == kbound

  row_of = i64[nv + 1]           # one-based row, zero means unvisited
  chain_of = i64[nv + 1]         # one-based chain
  rows = ngraph - 1
  grid = i64[kbound * rows]
  first_chain = -1
  c = 0
  while c < kbound
    root = roots[c]
    if unit[root] == 0
      return wassat_ais_miss if first_chain >= 0
      first_chain = c
    cur = root
    r = 0
    while cur != 0
      return wassat_ais_miss if graph[cur] != 0 || row_of[cur] != 0
      return wassat_ais_miss if r >= rows
      row_of[cur] = r + 1
      chain_of[cur] = c + 1
      grid[c * rows + r] = cur
      r += 1
      cur = next_aux[cur]
    return wassat_ais_miss unless r == rows
    c += 1
  return wassat_ais_miss if first_chain < 0

  v = 1
  while v <= nv
    if graph[v] == 0
      return wassat_ais_miss if row_of[v] == 0
      # Initializers occur on every first-row chain except column one.
      if unit[v] != 0
        return wassat_ais_miss unless row_of[v] == 1
        return wassat_ais_miss if chain_of[v] - 1 == first_chain
    v += 1

  # Column one has exactly one input implication per row.  These n-1 inputs
  # are distinct; the sole unused graph variable is the final input.
  inputs = i64[ngraph]
  input_used = i8[nv + 1]
  c = 0
  while c < kbound
    r = 0
    while r < rows
      cell = grid[c * rows + r]
      x = input_link[cell]
      if c == first_chain
        return wassat_ais_miss if x == 0 || graph[x] == 0
        return wassat_ais_miss if input_used[x] != 0
        inputs[r] = x
        input_used[x] = 1
      else
        return wassat_ais_miss if x != 0
      r += 1
    c += 1

  final_input = 0
  gi = 0
  while gi < ngraph
    x = graph_var[gi]
    if input_used[x] == 0
      return wassat_ais_miss if final_input != 0
      final_input = x
    gi += 1
  return wassat_ais_miss if final_input == 0
  inputs[ngraph - 1] = final_input

  # Ternary transitions order the otherwise anonymous vertical chains:
  #
  #   (-x_i | -s[i-1,j-1] | s[i,j]).
  #
  # The same adjacent-column relation must occur once on every middle row.
  diag_next = i64[kbound]
  diag_prev = i64[kbound]
  diag_count = i64[kbound * kbound]
  diag_seen = i8[(ngraph - 2) * kbound]
  ti = 0
  while ti < want_ternaries
    ci = ternary_clause[ti]
    off = offs[ci]
    x = 0
    a = 0
    b = 0
    j = 0
    while j < 3
      l = lits[off + j]
      if l > 0
        b = l
      elsif graph[0 - l] != 0
        x = 0 - l
      else
        a = 0 - l
      j += 1
    return wassat_ais_miss unless row_of[b] == row_of[a] + 1
    return wassat_ais_miss if row_of[b] < 2 || row_of[b] > rows
    ca = chain_of[a] - 1
    cb = chain_of[b] - 1
    return wassat_ais_miss if ca == cb
    return wassat_ais_miss if diag_next[ca] != 0 && diag_next[ca] != cb + 1
    return wassat_ais_miss if diag_prev[cb] != 0 && diag_prev[cb] != ca + 1
    diag_next[ca] = cb + 1
    diag_prev[cb] = ca + 1
    slot = (row_of[b] - 2) * kbound + ca
    return wassat_ais_miss if diag_seen[slot] != 0
    diag_seen[slot] = 1
    diag_count[ca * kbound + cb] += 1
    return wassat_ais_miss unless x == inputs[row_of[b] - 1]
    ti += 1

  # Column ordering starts at the unique non-initialized root.
  return wassat_ais_miss if diag_prev[first_chain] != 0
  chain_column = i64[kbound]
  ordered_chain = i64[kbound]
  chain_seen = i8[kbound]
  cur_chain = first_chain
  col = 0
  while col < kbound
    return wassat_ais_miss if cur_chain < 0 || cur_chain >= kbound
    return wassat_ais_miss if chain_seen[cur_chain] != 0
    chain_seen[cur_chain] = 1
    chain_column[cur_chain] = col + 1
    ordered_chain[col] = cur_chain
    if col + 1 < kbound
      return wassat_ais_miss if diag_next[cur_chain] == 0
      cur_chain = diag_next[cur_chain] - 1
    else
      return wassat_ais_miss if diag_next[cur_chain] != 0
    col += 1

  col = 0
  while col + 1 < kbound
    ca = ordered_chain[col]
    cb = ordered_chain[col + 1]
    return wassat_ais_miss unless diag_count[ca * kbound + cb] == ngraph - 2
    col += 1

  # Every input after the first has exactly one overflow guard against the
  # preceding row's last-column cell.
  last_chain = ordered_chain[kbound - 1]
  return wassat_ais_miss if overflow_aux[inputs[0]] != 0
  r = 1
  while r < ngraph - 1
    expected = grid[last_chain * rows + r - 1]
    return wassat_ais_miss unless overflow_aux[inputs[r]] == expected
    r += 1
  expected = grid[last_chain * rows + rows - 1]
  return wassat_ais_miss unless overflow_aux[final_input] == expected

  # Finally verify the graph certificate.  Connected components are found on
  # compact ids; degree |C|-1 for every member proves that each is a clique.
  component_seen = i8[ngraph]
  queue = i64[ngraph]
  members = i64[ngraph]
  components = 0
  lower = 0
  start = 0
  while start < ngraph
    if component_seen[start] == 0
      head = 0
      tail = 1
      queue[0] = start
      component_seen[start] = 1
      size = 0
      while head < tail
        a = queue[head]
        head += 1
        members[size] = a
        size += 1
        b = 0
        while b < ngraph
          if adj[a * ngraph + b] != 0 && component_seen[b] == 0
            component_seen[b] = 1
            queue[tail] = b
            tail += 1
          b += 1
      mi = 0
      while mi < size
        a = members[mi]
        degree = 0
        b = 0
        while b < ngraph
          degree += 1 if adj[a * ngraph + b] != 0
          b += 1
        return wassat_ais_miss unless degree == size - 1
        mi += 1
      lower += size - 1
      components += 1
    start += 1

  return wassat_ais_miss unless lower > kbound
  { "recognized": true, "status": -1, "graph_vars": ngraph,
    "upper_bound": kbound, "lower_bound": lower,
    "components": components }
