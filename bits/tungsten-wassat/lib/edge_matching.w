# Exact model-only solver for compact edge-matching encodings.
#
# Clean-room provenance: the schema, tuple decoder, grid reconstruction, and
# search below were derived independently from DIMACS clause incidence. No
# third-party matcher or solver implementation is incorporated here.
#
# The recognized encoding has three independently checked layers:
#
#   * two positive partitions of one contiguous placement-variable block,
#     one partition by board cell and one by physical piece;
#   * direct exact-one groups for every internal board-edge color; and
#   * clauses led by -placement whose remaining literals mention only the
#     incident edge-color groups.
#
# Conditioning the third layer on one placement leaves a tiny relation over
# at most four one-hot groups.  Enumerating that relation recovers the legal
# orientations without relying on variable names, comments, or generator
# metadata.  The incidence graph of color groups and cell partitions must be
# exactly an unlabeled square grid before search begins.
#
# Search chooses one piece/orientation per cell in a deterministic grid walk.
# It only returns SAT, never UNSAT: a shape miss, option cap, or node cap falls
# through to ordinary Wassat.  The caller verifies every returned bit against
# every original clause.

WASSAT_EDGE_MAX_CELLS = 256
WASSAT_EDGE_MAX_VARS = 50000
WASSAT_EDGE_MAX_CLAUSES = 1000000
WASSAT_EDGE_MAX_DOMAIN = 256
WASSAT_EDGE_MAX_COLORS = 8
WASSAT_EDGE_MAX_DEGREE = 4
WASSAT_EDGE_MAX_OPTIONS = 8
WASSAT_EDGE_NODE_CAP = 1000000

-> wassat_edge_miss
  {
    "recognized": false, "status": 0, "model": [],
    "side": 0, "cells": 0, "edges": 0, "nodes": 0
  }

-> wassat_edge_bfs(neighbors, degree, ncells, source,
                   distance, queue) (i64[] i8[] i64 i64 i64[] i64[]) i64
  c = 0
  while c < ncells
    distance[c] = -1
    c += 1
  distance[source] = 0
  head = 0
  tail = 1
  queue[0] = source
  while head < tail
    at = queue[head]
    head += 1
    d = 0
    while d < degree[at]
      to = neighbors[at * WASSAT_EDGE_MAX_DEGREE + d]
      if distance[to] < 0
        distance[to] = distance[at] + 1
        queue[tail] = to
        tail += 1
      d += 1
  tail

-> wassat_edge_cell_partition?(row_off, row_lits, nrows,
                               placement_degree,
                               placement_groups) (i64[] i64[] i64 i8[] i64[]) bool
  row = 0
  while row < nrows
    return false if row_off[row] >= row_off[row + 1]
    first = row_lits[row_off[row]]
    degree = placement_degree[first]
    return false if degree < 2 || degree > WASSAT_EDGE_MAX_DEGREE
    p = row_off[row] + 1
    while p < row_off[row + 1]
      v = row_lits[p]
      return false unless placement_degree[v] == degree
      d = 0
      while d < degree
        return false unless placement_groups[v * WASSAT_EDGE_MAX_DEGREE + d] == placement_groups[first * WASSAT_EDGE_MAX_DEGREE + d]
        d += 1
      p += 1
    row += 1
  true

# Decode one conditioned placement relation into at most eight explicit edge
# tuples.  Options are emitted in lexicographic group-value order so the
# production search is deterministic across interpreted and compiled builds.
-> wassat_edge_decode_placement(v, start_item, stop_item, clause_ids,
                                lits, offs, lens,
                                aux_group, aux_value, group_width,
                                placement_degree, placement_groups,
                                option_count, option_values,
                                choices) (i64 i64 i64 i64[] i64[] i64[] i64[] i64[] i8[] i8[] i8[] i64[] i8[] i8[] i8[]) i64
  degree = 0
  item = start_item
  while item < stop_item
    ci = clause_ids[item]
    off = offs[ci]
    n = lens[ci]
    return 0 if n < 2 || lits[off] != 0 - v
    j = 1
    while j < n
      lit = lits[off + j]
      av = lit.abs
      g = aux_group[av]
      return 0 if g < 0
      d = 0
      d += 1 while d < degree && placement_groups[v * WASSAT_EDGE_MAX_DEGREE + d] != g
      if d == degree
        return 0 if degree >= WASSAT_EDGE_MAX_DEGREE
        placement_groups[v * WASSAT_EDGE_MAX_DEGREE + degree] = g
        degree += 1
      j += 1
    item += 1
  return 0 if degree < 2

  # Stable insertion sort makes group order independent of literal order
  # inside the implication CNF.
  d = 1
  while d < degree
    g = placement_groups[v * WASSAT_EDGE_MAX_DEGREE + d]
    k = d
    while k > 0 && placement_groups[v * WASSAT_EDGE_MAX_DEGREE + k - 1] > g
      placement_groups[v * WASSAT_EDGE_MAX_DEGREE + k] = placement_groups[v * WASSAT_EDGE_MAX_DEGREE + k - 1]
      k -= 1
    placement_groups[v * WASSAT_EDGE_MAX_DEGREE + k] = g
    d += 1
  placement_degree[v] = degree

  combinations = 1
  d = 0
  while d < degree
    g = placement_groups[v * WASSAT_EDGE_MAX_DEGREE + d]
    combinations *= group_width[g]
    return 0 if combinations > 4096
    d += 1

  found = 0
  code = 0
  while code < combinations
    q = code
    d = degree - 1
    while d >= 0
      g = placement_groups[v * WASSAT_EDGE_MAX_DEGREE + d]
      choices[d] = q % group_width[g]
      q /= group_width[g]
      d -= 1

    valid = 1
    item = start_item
    while item < stop_item && valid == 1
      ci = clause_ids[item]
      off = offs[ci]
      n = lens[ci]
      sat = 0
      j = 1
      while j < n && sat == 0
        lit = lits[off + j]
        av = lit.abs
        g = aux_group[av]
        d = 0
        d += 1 while d < degree && placement_groups[v * WASSAT_EDGE_MAX_DEGREE + d] != g
        return 0 if d == degree
        truth = choices[d] == aux_value[av]
        truth = !truth if lit < 0
        sat = 1 if truth
        j += 1
      valid = 0 if sat == 0
      item += 1

    if valid == 1
      return 0 if found >= WASSAT_EDGE_MAX_OPTIONS
      base = (v * WASSAT_EDGE_MAX_OPTIONS + found) * WASSAT_EDGE_MAX_DEGREE
      d = 0
      while d < degree
        option_values[base + d] = choices[d]
        d += 1
      found += 1
    code += 1
  return 0 if found == 0
  option_count[v] = found
  1

-> wassat_edge_search(depth, ncells, order,
                      cell_off, cell_lits, tile_of,
                      placement_degree, placement_groups,
                      option_count, option_values,
                      used_tile, edge_value, chosen,
                      meta, node_cap) (i64 i64 i64[] i64[] i64[] i64[] i8[] i64[] i8[] i8[] i8[] i8[] i8[] i64[] i64) i64
  meta[0] += 1
  if meta[0] > node_cap
    meta[1] = 1
    return 0
  return 1 if depth == ncells

  cell = order[depth]
  p = cell_off[cell]
  stop = cell_off[cell + 1]
  while p < stop
    v = cell_lits[p]
    tile = tile_of[v]
    if used_tile[tile] == 0
      o = 0
      while o < option_count[v]
        compatible = 1
        degree = placement_degree[v]
        base = (v * WASSAT_EDGE_MAX_OPTIONS + o) * WASSAT_EDGE_MAX_DEGREE
        d = 0
        while d < degree && compatible == 1
          g = placement_groups[v * WASSAT_EDGE_MAX_DEGREE + d]
          value = option_values[base + d]
          compatible = 0 if edge_value[g] >= 0 && edge_value[g] != value
          d += 1

        if compatible == 1
          mark = 0
          d = 0
          while d < degree
            g = placement_groups[v * WASSAT_EDGE_MAX_DEGREE + d]
            if edge_value[g] < 0
              edge_value[g] = option_values[base + d]
              mark = mark | (1 << d)
            d += 1
          used_tile[tile] = 1
          chosen[v] = 1
          if wassat_edge_search(
            depth + 1, ncells, order, cell_off, cell_lits, tile_of,
            placement_degree, placement_groups, option_count, option_values,
            used_tile, edge_value, chosen, meta, node_cap
          ) == 1
            return 1
          chosen[v] = 0
          used_tile[tile] = 0
          d = 0
          while d < degree
            if (mark & (1 << d)) != 0
              g = placement_groups[v * WASSAT_EDGE_MAX_DEGREE + d]
              edge_value[g] = -1
            d += 1
          return 0 if meta[1] == 1
        o += 1
    p += 1
  0

# Return status 1 only with a complete Boolean model. A recognized-but-capped
# result remains status zero and is handed to the generic solver.
-> wassat_edge_matching_solve(formula, node_cap = WASSAT_EDGE_NODE_CAP)
  miss = wassat_edge_miss
  return miss unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return miss if nv < 12 || nv > WASSAT_EDGE_MAX_VARS
  return miss if ncl < 24 || ncl > WASSAT_EDGE_MAX_CLAUSES
  return miss if node_cap < 1

  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  seen = i8[nv + 1]
  stamp = i64[nv + 1]
  cell_off = i64[WASSAT_EDGE_MAX_CELLS + 1]
  cell_lits = i64[nv]
  cell_of = i64[nv + 1]

  # First positive partition: each placement occurs in exactly one cell row.
  ci = 0
  ncells = 0
  nprimary = 0
  max_primary = 0
  epoch = 0
  scanning = 1
  while ci < ncl && scanning == 1
    off = offs[ci]
    n = lens[ci]
    scanning = 0 if n < 2 || n > WASSAT_EDGE_MAX_DOMAIN
    collision = 0
    epoch += 1
    j = 0
    while j < n && scanning == 1
      v = lits[off + j]
      if v < 1 || v > nv || stamp[v] == epoch
        return miss
      stamp[v] = epoch
      collision = 1 if seen[v] != 0
      j += 1
    if scanning == 1 && collision == 0
      return miss if ncells >= WASSAT_EDGE_MAX_CELLS
      cell_off[ncells] = nprimary
      j = 0
      while j < n
        v = lits[off + j]
        seen[v] = 1
        cell_lits[nprimary] = v
        cell_of[v] = ncells
        nprimary += 1
        max_primary = v if v > max_primary
        j += 1
      ncells += 1
      ci += 1
    else
      scanning = 0
  cell_off[ncells] = nprimary
  return miss if ncells < 4 || nprimary < ncells
  return miss unless nprimary == max_primary
  v = 1
  while v <= nprimary
    return miss if seen[v] == 0
    v += 1

  side = 2
  side += 1 while side * side < ncells
  return miss unless side * side == ncells

  # Second positive partition: each placement occurs in exactly one piece
  # row. It must cover precisely the first partition.
  tile_of = i64[nprimary + 1]
  second_off = i64[WASSAT_EDGE_MAX_CELLS + 1]
  second_lits = i64[nprimary]
  second_of = tile_of
  seen2 = i8[nprimary + 1]
  second_count = 0
  tile = 0
  while tile < ncells
    return miss if ci >= ncl
    off = offs[ci]
    n = lens[ci]
    primary_row = n >= 2 && n <= WASSAT_EDGE_MAX_DOMAIN
    j = 0
    while j < n && primary_row
      v = lits[off + j]
      primary_row = false if v < 1 || v > nprimary
      j += 1
    break unless primary_row
    epoch += 1
    second_off[tile] = second_count
    j = 0
    while j < n
      v = lits[off + j]
      return miss if v < 1 || v > nprimary
      return miss if stamp[v] == epoch || seen2[v] != 0
      stamp[v] = epoch
      seen2[v] = 1
      second_of[v] = tile
      second_lits[second_count] = v
      second_count += 1
      j += 1
    tile += 1
    ci += 1
  # One compact generator variant omits its final partition row because that
  # row is exactly the placement variables not covered by the preceding rows.
  if tile == ncells - 1
    second_off[tile] = second_count
    missing = 0
    v = 1
    while v <= nprimary
      if seen2[v] == 0
        seen2[v] = 1
        second_of[v] = tile
        second_lits[second_count] = v
        second_count += 1
        missing += 1
      v += 1
    return miss if missing < 2 || missing > WASSAT_EDGE_MAX_DOMAIN
    tile += 1
  return miss unless tile == ncells
  second_off[ncells] = second_count
  return miss unless second_count == nprimary
  v = 1
  while v <= nprimary
    return miss if seen2[v] == 0
    v += 1

  # A cell/piece pair has at most one placement literal.
  tile_stamp = i64[ncells]
  cell = 0
  while cell < ncells
    epoch += 1
    p = cell_off[cell]
    while p < cell_off[cell + 1]
      v = cell_lits[p]
      tile = tile_of[v]
      return miss if tile_stamp[tile] == epoch
      tile_stamp[tile] = epoch
      p += 1
    cell += 1

  # Every internal grid edge has a direct one-hot color group.
  expected_edges = 2 * side * (side - 1)
  aux_group = i64[nv + 1]
  aux_value = i8[nv + 1]
  v = 0
  while v <= nv
    aux_group[v] = -1
    v += 1
  group_width = i8[expected_edges]
  pair_seen = i8[WASSAT_EDGE_MAX_COLORS * WASSAT_EDGE_MAX_COLORS]
  g = 0
  aux_count = 0
  while g < expected_edges
    return miss if ci >= ncl
    off = offs[ci]
    width = lens[ci]
    return miss if width < 2 || width > WASSAT_EDGE_MAX_COLORS
    j = 0
    while j < width
      av = lits[off + j]
      return miss if av <= nprimary || av > nv || aux_group[av] >= 0
      aux_group[av] = g
      aux_value[av] = j
      j += 1
    group_width[g] = width
    aux_count += width
    ci += 1

    z = 0
    while z < WASSAT_EDGE_MAX_COLORS * WASSAT_EDGE_MAX_COLORS
      pair_seen[z] = 0
      z += 1
    npairs = width * (width - 1) / 2
    k = 0
    while k < npairs
      return miss if ci >= ncl || lens[ci] != 2
      poff = offs[ci]
      a = lits[poff]
      b = lits[poff + 1]
      return miss if a >= 0 || b >= 0
      a = 0 - a
      b = 0 - b
      return miss unless aux_group[a] == g && aux_group[b] == g
      x = aux_value[a]
      y = aux_value[b]
      return miss if x == y
      if x > y
        tmp = x
        x = y
        y = tmp
      pair = x * WASSAT_EDGE_MAX_COLORS + y
      return miss if pair_seen[pair] != 0
      pair_seen[pair] = 1
      ci += 1
      k += 1
    x = 0
    while x < width
      y = x + 1
      while y < width
        return miss if pair_seen[x * WASSAT_EDGE_MAX_COLORS + y] == 0
        y += 1
      x += 1
    g += 1
  return miss unless aux_count == nv - nprimary
  v = nprimary + 1
  while v <= nv
    return miss if aux_group[v] < 0
    v += 1

  # Collect the conditioned relation clauses by placement. Generators often
  # emit these in several passes (unary exclusions first, tuple clauses later),
  # so clause order is deliberately not part of recognition.
  placement_degree = i8[nprimary + 1]
  placement_groups = i64[(nprimary + 1) * WASSAT_EDGE_MAX_DEGREE]
  option_count = i8[nprimary + 1]
  option_values = i8[(nprimary + 1) * WASSAT_EDGE_MAX_OPTIONS * WASSAT_EDGE_MAX_DEGREE]
  choices = i8[WASSAT_EDGE_MAX_DEGREE]
  relation_begin = ci
  relation_count = i64[nprimary + 1]
  nrelations = 0
  scanning = 1
  while ci < ncl && scanning == 1
    off = offs[ci]
    n = lens[ci]
    scanning = 0 if n < 2
    pv = 0
    if scanning == 1
      lead = lits[off]
      scanning = 0 unless lead < 0 && lead >= 0 - nprimary
      pv = 0 - lead if scanning == 1
    j = 1
    while j < n && scanning == 1
      av = lits[off + j].abs
      scanning = 0 if av <= nprimary || av > nv || aux_group[av] < 0
      j += 1
    if scanning == 1
      relation_count[pv] += 1
      nrelations += 1
      ci += 1
  relation_end = ci
  return miss if nrelations == 0
  relation_off = i64[nprimary + 2]
  relation_cursor = i64[nprimary + 1]
  v = 1
  while v <= nprimary
    return miss if relation_count[v] == 0
    relation_off[v + 1] = relation_off[v] + relation_count[v]
    relation_cursor[v] = relation_off[v]
    v += 1
  relation_ids = i64[nrelations]
  rci = relation_begin
  while rci < relation_end
    pv = 0 - lits[offs[rci]]
    relation_ids[relation_cursor[pv]] = rci
    relation_cursor[pv] += 1
    rci += 1

  v = 1
  while v <= nprimary
    decoded = wassat_edge_decode_placement(
      v, relation_off[v], relation_off[v + 1], relation_ids,
      lits, offs, lens, aux_group, aux_value, group_width,
      placement_degree, placement_groups, option_count, option_values,
      choices
    )
    if decoded == 0
      return miss
    v += 1

  # Remaining clauses may only be negative placement binaries. Once the cell
  # partition is identified below, both endpoints must belong to the same
  # exact cell row.
  tail_begin = ci
  while ci < ncl
    return miss unless lens[ci] == 2
    off = offs[ci]
    a = lits[off]
    b = lits[off + 1]
    return miss if a >= 0 || b >= 0
    a = 0 - a
    b = 0 - b
    return miss if a < 1 || a > nprimary || b < 1 || b > nprimary
    return miss if a == b
    ci += 1

  # Either positive partition may be emitted first. The actual cell rows are
  # exactly those whose placements all touch the same board-edge groups.
  first_is_cells = wassat_edge_cell_partition?(
    cell_off, cell_lits, ncells, placement_degree, placement_groups
  )
  second_is_cells = wassat_edge_cell_partition?(
    second_off, second_lits, ncells, placement_degree, placement_groups
  )
  return miss if first_is_cells == second_is_cells
  if second_is_cells
    first_of = cell_of
    cell_off = second_off
    cell_lits = second_lits
    cell_of = second_of
    tile_of = first_of

  tci = tail_begin
  while tci < ncl
    off = offs[tci]
    a = 0 - lits[off]
    b = 0 - lits[off + 1]
    return miss unless cell_of[a] == cell_of[b]
    tci += 1

  # Every placement candidate of one cell must refer to exactly the same
  # incident edge groups.
  cell_degree = i8[ncells]
  cell_edges = i64[ncells * WASSAT_EDGE_MAX_DEGREE]
  corners = 0
  borders = 0
  interiors = 0
  cell = 0
  while cell < ncells
    first = cell_lits[cell_off[cell]]
    degree = placement_degree[first]
    return miss if degree < 2 || degree > WASSAT_EDGE_MAX_DEGREE
    cell_degree[cell] = degree
    d = 0
    while d < degree
      cell_edges[cell * WASSAT_EDGE_MAX_DEGREE + d] = placement_groups[first * WASSAT_EDGE_MAX_DEGREE + d]
      d += 1
    p = cell_off[cell] + 1
    while p < cell_off[cell + 1]
      v = cell_lits[p]
      return miss unless placement_degree[v] == degree
      d = 0
      while d < degree
        return miss unless placement_groups[v * WASSAT_EDGE_MAX_DEGREE + d] == cell_edges[cell * WASSAT_EDGE_MAX_DEGREE + d]
        d += 1
      p += 1
    corners += 1 if degree == 2
    borders += 1 if degree == 3
    interiors += 1 if degree == 4
    cell += 1
  return miss unless corners == 4
  return miss unless borders == 4 * (side - 2)
  return miss unless interiors == (side - 2) * (side - 2)

  # Color-group incidence recovers the unlabeled board graph.
  edge_cell0 = i64[expected_edges]
  edge_cell1 = i64[expected_edges]
  edge_inc = i8[expected_edges]
  cell = 0
  while cell < ncells
    d = 0
    while d < cell_degree[cell]
      g = cell_edges[cell * WASSAT_EDGE_MAX_DEGREE + d]
      return miss if g < 0 || g >= expected_edges || edge_inc[g] >= 2
      if edge_inc[g] == 0
        edge_cell0[g] = cell
      else
        edge_cell1[g] = cell
      edge_inc[g] += 1
      d += 1
    cell += 1
  g = 0
  while g < expected_edges
    return miss unless edge_inc[g] == 2 && edge_cell0[g] != edge_cell1[g]
    g += 1

  neighbors = i64[ncells * WASSAT_EDGE_MAX_DEGREE]
  cell = 0
  while cell < ncells
    d = 0
    while d < cell_degree[cell]
      g = cell_edges[cell * WASSAT_EDGE_MAX_DEGREE + d]
      other = edge_cell0[g] == cell ? edge_cell1[g] : edge_cell0[g]
      k = 0
      while k < d
        return miss if neighbors[cell * WASSAT_EDGE_MAX_DEGREE + k] == other
        k += 1
      neighbors[cell * WASSAT_EDGE_MAX_DEGREE + d] = other
      d += 1
    cell += 1

  corner_ids = i64[4]
  k = 0
  cell = 0
  while cell < ncells
    if cell_degree[cell] == 2
      corner_ids[k] = cell
      k += 1
    cell += 1
  c0 = corner_ids[0]
  d0 = i64[ncells]
  dx = i64[ncells]
  queue = i64[ncells]
  return miss unless wassat_edge_bfs(
    neighbors, cell_degree, ncells, c0, d0, queue
  ) == ncells
  opposite = -1
  side0 = -1
  side1 = -1
  k = 1
  while k < 4
    c = corner_ids[k]
    if d0[c] == 2 * (side - 1)
      return miss if opposite >= 0
      opposite = c
    elsif d0[c] == side - 1
      if side0 < 0
        side0 = c
      elsif side1 < 0
        side1 = c
      else
        return miss
    else
      return miss
    k += 1
  return miss if opposite < 0 || side0 < 0 || side1 < 0
  cx = side0 < side1 ? side0 : side1
  return miss unless wassat_edge_bfs(
    neighbors, cell_degree, ncells, cx, dx, queue
  ) == ncells

  grid = i64[ncells]
  order = i64[ncells]
  cell_x = i64[ncells]
  cell_y = i64[ncells]
  k = 0
  while k < ncells
    grid[k] = -1
    k += 1
  cell = 0
  while cell < ncells
    numerator = d0[cell] - dx[cell] + side - 1
    return miss if numerator < 0 || numerator % 2 != 0
    x = numerator / 2
    y = d0[cell] - x
    return miss if x < 0 || x >= side || y < 0 || y >= side
    at = y * side + x
    return miss if grid[at] >= 0
    grid[at] = cell
    cell_x[cell] = x
    cell_y[cell] = y
    cell += 1
  g = 0
  while g < expected_edges
    a = edge_cell0[g]
    b = edge_cell1[g]
    manhattan = (cell_x[a] - cell_x[b]).abs + (cell_y[a] - cell_y[b]).abs
    return miss unless manhattan == 1
    g += 1
  k = 0
  while k < ncells
    return miss if grid[k] < 0
    order[k] = grid[k]
    k += 1

  used_tile = i8[ncells]
  edge_value = i8[expected_edges]
  chosen = i8[nprimary + 1]
  g = 0
  while g < expected_edges
    edge_value[g] = -1
    g += 1
  meta = i64[2]
  status = wassat_edge_search(
    0, ncells, order, cell_off, cell_lits, tile_of,
    placement_degree, placement_groups, option_count, option_values,
    used_tile, edge_value, chosen, meta, node_cap
  )
  recognized = {
    "recognized": true, "status": status, "model": [],
    "side": side, "cells": ncells, "edges": expected_edges,
    "nodes": meta[0]
  }
  return recognized unless status == 1

  model = []
  v = 1
  while v <= nprimary
    model.push(chosen[v] == 1 ? v : 0 - v)
    v += 1
  while v <= nv
    g = aux_group[v]
    model.push(edge_value[g] == aux_value[v] ? v : 0 - v)
    v += 1
  recognized["model"] = model
  recognized
