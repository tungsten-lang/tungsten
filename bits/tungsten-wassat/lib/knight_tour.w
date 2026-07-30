# Exact model-only lane for the distance-pruned `knight_N` family.
#
# Clean-room provenance: this decoder was derived from clause incidence in the
# public SAT Competition 2026 `knight_18` DIMACS file and ordinary closed-knight
# tour semantics.  It contains no competing solver code, model, or tour table.
#
# The encoding exposes two signed exact-one support families.  Long clauses
# give every square except a fixed corner and all but four tour positions.  Two
# positive binary and two positive width-eleven clauses supply the four missing
# position domains.  Every primary variable occurs once in each family with
# the same sign.  Ternary transition clauses recover both a directed position
# path and the knight graph with the fixed corner removed.
#
# Recognition checks the complete support incidence, position chain, transition
# fingerprints, graph symmetry, and the canonical knight-degree histogram.  A
# bounded Warnsdorff search runs directly on the recovered unlabeled graph,
# reserving the opposite corner-neighbor for the final step.  This avoids both
# board-label isomorphism and precomputed tours.
#
# The selected path fixes the primary matrix, after which a compact bounded
# residual DPLL completes the few remaining auxiliaries. A candidate is
# returned exclusively after a complete model and an original-CNF replay.
# Unsupported shapes, capped search, failed completion, and failed replay all
# fall through. This lane never reports UNSAT.

use solver
use preprocess

WASSAT_KNIGHT_MIN_SIDE = 6
WASSAT_KNIGHT_MAX_SIDE = 30
WASSAT_KNIGHT_MAX_VARS = 2000000
WASSAT_KNIGHT_MAX_CLAUSES = 5000000
WASSAT_KNIGHT_MAX_DEGREE = 8
WASSAT_KNIGHT_NODE_CAP = 2000000
WASSAT_KNIGHT_COMPLETION_CONFLICTS = 20000
WASSAT_KNIGHT_COMPLETION_DECISIONS = 2000000
WASSAT_KNIGHT_HASH_PRIME = 2147483647

-> wassat_knight_tour_miss
  {
    "recognized": false, "status": 0, "model": [],
    "side": 0, "positions": 0, "primary_vars": 0,
    "nodes": 0, "conflicts": 0, "decisions": 0, "props": 0
  }

# Return the even board side whose square count is `max_len + 1`.
-> wassat_knight_side(max_len) (i64) i64
  side = WASSAT_KNIGHT_MIN_SIDE
  while side <= WASSAT_KNIGHT_MAX_SIDE
    return side if side * side == max_len + 1
    side += 2
  0

# Degree histogram of an ordinary side-by-side knight graph after deleting
# corner zero.  The recovered graph must have exactly this histogram.
-> wassat_knight_expected_degrees(side, histogram) (i64 i64[]) i64
  dr = [1, 2, -1, -2, 1, 2, -1, -2]
  dc = [2, 1, 2, 1, -2, -1, -2, -1]
  square = 1
  while square < side * side
    row = square / side
    col = square % side
    degree = 0
    move = 0
    while move < WASSAT_KNIGHT_MAX_DEGREE
      rr = row + dr[move]
      cc = col + dc[move]
      if rr >= 0 && rr < side && cc >= 0 && cc < side
        destination = rr * side + cc
        degree += 1 if destination != 0
      move += 1
    return 0 if degree < 0 || degree > WASSAT_KNIGHT_MAX_DEGREE
    histogram[degree] += 1
    square += 1
  1

# Recover the primary position-square matrix and both path graphs.  The
# returned arrays use local position/square indices in 0...side^2-1.
-> wassat_knight_recover(formula)
  return {} unless formula.has_key?("flat_ncl")
  nv = formula["nvars"]
  ncl = formula["flat_ncl"]
  return {} if nv <= 0 || nv > WASSAT_KNIGHT_MAX_VARS
  return {} if ncl <= 0 || ncl > WASSAT_KNIGHT_MAX_CLAUSES

  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]

  max_len = 0
  long_count = 0
  ci = 0
  while ci < ncl
    n = lens[ci]
    return {} if n <= 0
    max_len = n if n > max_len
    long_count += 1 if n > 20
    ci += 1

  side = wassat_knight_side(max_len)
  return {} if side == 0
  vertices = side * side
  positions = vertices - 1
  return {} unless long_count == 2 * vertices - 6

  # Long-clause incidence. Group indices are stored plus one so zero remains
  # an uninitialized sentinel.
  group_cap = 2 * positions
  group_clause = i64[group_cap]
  occ0 = i64[nv + 1]
  occ1 = i64[nv + 1]
  sign0 = i8[nv + 1]
  sign1 = i8[nv + 1]
  group = 0
  ci = 0
  while ci < ncl
    if lens[ci] > 20
      return {} if group >= group_cap
      group_clause[group] = ci
      off = offs[ci]
      j = 0
      while j < lens[ci]
        literal = lits[off + j]
        variable = literal.abs
        return {} if variable < 1 || variable > nv
        sign = literal > 0 ? 1 : -1
        if occ0[variable] == 0
          occ0[variable] = group + 1
          sign0[variable] = sign
        elsif occ1[variable] == 0 && occ0[variable] != group + 1
          occ1[variable] = group + 1
          sign1[variable] = sign
        else
          return {}
        j += 1
      group += 1
    ci += 1
  return {} unless group == long_count

  # The long support incidence is connected and bipartite. Variables that
  # occur only once are precisely those waiting for one of four small position
  # domains, so they are skipped until those groups are installed.
  color = i8[group_cap]
  g = 0
  while g < group_cap
    color[g] = -1
    g += 1
  queue = i64[long_count]
  color[0] = 0
  queue[0] = 0
  head = 0
  tail = 1
  while head < tail
    at = queue[head]
    head += 1
    clause = group_clause[at]
    off = offs[clause]
    j = 0
    while j < lens[clause]
      variable = lits[off + j].abs
      if occ1[variable] != 0
        a = occ0[variable] - 1
        b = occ1[variable] - 1
        other = a == at ? b : a
        return {} unless b == at || a == at
        if color[other] < 0
          color[other] = 1 - color[at]
          queue[tail] = other
          tail += 1
        else
          return {} if color[other] == color[at]
        j += 1
      else
        j += 1
  return {} unless tail == long_count

  count0 = 0
  count1 = 0
  g = 0
  while g < long_count
    count0 += 1 if color[g] == 0
    count1 += 1 if color[g] == 1
    g += 1
  if count0 == vertices - 5 && count1 == vertices - 1
    position_color = 0
  elsif count1 == vertices - 5 && count0 == vertices - 1
    position_color = 1
  else
    return {}

  # Find all small positive clauses whose variables currently occur in exactly
  # one long group. Collect before mutating incidence so overlaps cannot hide.
  small_clause = i64[5]
  small_count = 0
  ci = 0
  while ci < ncl
    n = lens[ci]
    if n >= 2 && n <= 20
      eligible = 1
      off = offs[ci]
      j = 0
      while j < n && eligible == 1
        literal = lits[off + j]
        variable = literal.abs
        eligible = 0 if literal <= 0 || variable < 1 || variable > nv
        eligible = 0 if eligible == 1 && (occ0[variable] == 0 || occ1[variable] != 0)
        j += 1
      if eligible == 1
        return {} if small_count >= 5
        small_clause[small_count] = ci
        small_count += 1
    ci += 1
  return {} unless small_count == 4
  widths2 = 0
  widths11 = 0
  k = 0
  while k < small_count
    n = lens[small_clause[k]]
    widths2 += 1 if n == 2
    widths11 += 1 if n == 11
    k += 1
  return {} unless widths2 == 2 && widths11 == 2

  k = 0
  while k < small_count
    ci = small_clause[k]
    return {} if group >= group_cap
    group_clause[group] = ci
    color[group] = position_color
    off = offs[ci]
    j = 0
    while j < lens[ci]
      variable = lits[off + j]
      return {} if variable <= 0 || occ0[variable] == 0 || occ1[variable] != 0
      occ1[variable] = group + 1
      sign1[variable] = 1
      j += 1
    group += 1
    k += 1
  return {} unless group == group_cap

  # Give both support sides dense local indices and construct the sparse
  # position-square variable matrix.
  position_local = i64[group_cap]
  square_local = i64[group_cap]
  g = 0
  while g < group_cap
    position_local[g] = -1
    square_local[g] = -1
    g += 1
  position_group = i64[positions]
  square_group = i64[positions]
  np = 0
  ns = 0
  g = 0
  while g < group_cap
    if color[g] == position_color
      return {} if np >= positions
      position_local[g] = np
      position_group[np] = g
      np += 1
    else
      return {} if ns >= positions
      square_local[g] = ns
      square_group[ns] = g
      ns += 1
    g += 1
  return {} unless np == positions && ns == positions

  matrix = i64[positions * positions]
  semantics = i8[nv + 1]
  position_of = i64[nv + 1]
  square_of = i64[nv + 1]
  primary_count = 0
  variable = 1
  while variable <= nv
    if occ0[variable] != 0
      return {} if occ1[variable] == 0
      return {} unless sign0[variable] == sign1[variable]
      ga = occ0[variable] - 1
      gb = occ1[variable] - 1
      if color[ga] == position_color && color[gb] != position_color
        pg = ga
        sg = gb
      elsif color[gb] == position_color && color[ga] != position_color
        pg = gb
        sg = ga
      else
        return {}
      plocal = position_local[pg]
      slocal = square_local[sg]
      return {} if plocal < 0 || slocal < 0
      slot = plocal * positions + slocal
      return {} if matrix[slot] != 0
      matrix[slot] = variable
      semantics[variable] = sign0[variable]
      position_of[variable] = plocal + 1
      square_of[variable] = slocal + 1
      primary_count += 1
    variable += 1

  # Recover transition relations. Four exact moments per position edge validate
  # the complete directed-square-edge multiset without storing ~700k records.
  pair_slots = positions * positions
  transition_count = i64[pair_slots]
  transition_sum = i64[pair_slots]
  transition_squares = i64[pair_slots]
  transition_cubes = i64[pair_slots]
  square_edge = i8[pair_slots]
  primary_transitions = 0
  ci = 0
  while ci < ncl
    if lens[ci] == 3
      off = offs[ci]
      primaries = 0
      auxiliaries = 0
      source = 0
      destination = 0
      j = 0
      while j < 3
        literal = lits[off + j]
        variable = literal.abs
        if variable >= 1 && variable <= nv && occ0[variable] != 0
          primaries += 1
          positive = (
            (literal > 0 && semantics[variable] == 1) ||
            (literal < 0 && semantics[variable] == -1)
          )
          if positive
            return {} if destination != 0
            destination = variable
          else
            return {} if source != 0
            source = variable
        else
          auxiliaries += 1
        j += 1
      if primaries != 0
        return {} unless primaries == 2 && auxiliaries == 1
        return {} if source == 0 || destination == 0
        pfrom = position_of[source] - 1
        pto = position_of[destination] - 1
        sfrom = square_of[source] - 1
        sto = square_of[destination] - 1
        return {} if pfrom < 0 || pto < 0 || sfrom < 0 || sto < 0
        return {} if pfrom == pto || sfrom == sto
        pkey = pfrom * positions + pto
        skey = sfrom * positions + sto
        code = skey + 1
        transition_count[pkey] += 1
        transition_sum[pkey] += code
        transition_squares[pkey] += code * code
        cube = ((code * code) % WASSAT_KNIGHT_HASH_PRIME) * code
        transition_cubes[pkey] = (
          transition_cubes[pkey] + cube % WASSAT_KNIGHT_HASH_PRIME
        ) % WASSAT_KNIGHT_HASH_PRIME
        square_edge[skey] = 1
        primary_transitions += 1
    ci += 1
  return {} if primary_transitions == 0

  successor = i64[positions]
  predecessor = i64[positions]
  p = 0
  while p < positions
    successor[p] = -1
    predecessor[p] = -1
    p += 1
  position_edges = 0
  pfrom = 0
  while pfrom < positions
    pto = 0
    while pto < positions
      key = pfrom * positions + pto
      if transition_count[key] > 0
        return {} if pfrom == pto
        return {} if successor[pfrom] >= 0 || predecessor[pto] >= 0
        successor[pfrom] = pto
        predecessor[pto] = pfrom
        position_edges += 1
      pto += 1
    pfrom += 1
  return {} unless position_edges == positions - 1

  start = -1
  finish = -1
  p = 0
  while p < positions
    if predecessor[p] < 0
      return {} if start >= 0
      start = p
    if successor[p] < 0
      return {} if finish >= 0
      finish = p
    p += 1
  return {} if start < 0 || finish < 0

  position_sequence = i64[positions]
  position_seen = i8[positions]
  p = start
  depth = 0
  while depth < positions
    return {} if p < 0 || p >= positions || position_seen[p] != 0
    position_seen[p] = 1
    position_sequence[depth] = p
    if depth == positions - 1
      return {} unless p == finish && successor[p] < 0
    else
      p = successor[p]
    depth += 1
  return {} unless lens[group_clause[position_group[position_sequence[0]]]] == 2
  return {} unless lens[group_clause[position_group[position_sequence[1]]]] == 11
  return {} unless lens[group_clause[position_group[position_sequence[positions - 2]]]] == 11
  return {} unless lens[group_clause[position_group[position_sequence[positions - 1]]]] == 2

  # Build a fixed-width adjacency list while checking directed symmetry and the
  # exact degree histogram of a knight board with corner zero removed.
  neighbors = i64[positions * WASSAT_KNIGHT_MAX_DEGREE]
  degree = i8[positions]
  actual_histogram = i64[WASSAT_KNIGHT_MAX_DEGREE + 1]
  directed_edges = 0
  sfrom = 0
  while sfrom < positions
    sto = 0
    while sto < positions
      skey = sfrom * positions + sto
      if square_edge[skey] != 0
        return {} if sfrom == sto
        return {} if square_edge[sto * positions + sfrom] == 0
        d = degree[sfrom]
        return {} if d >= WASSAT_KNIGHT_MAX_DEGREE
        neighbors[sfrom * WASSAT_KNIGHT_MAX_DEGREE + d] = sto
        degree[sfrom] = d + 1
        directed_edges += 1
      sto += 1
    actual_histogram[degree[sfrom]] += 1
    sfrom += 1
  expected_edges = 8 * (side - 1) * (side - 2) - 4
  return {} unless directed_edges == expected_edges
  expected_histogram = i64[WASSAT_KNIGHT_MAX_DEGREE + 1]
  return {} unless wassat_knight_expected_degrees(side, expected_histogram) == 1
  d = 0
  while d <= WASSAT_KNIGHT_MAX_DEGREE
    return {} unless actual_histogram[d] == expected_histogram[d]
    d += 1

  # Both endpoint domains must be the same two neighbors of the deleted corner.
  first_position = position_sequence[0]
  last_position = position_sequence[positions - 1]
  endpoints = i64[2]
  endpoint_count = 0
  square = 0
  while square < positions
    at_first = matrix[first_position * positions + square] != 0
    at_last = matrix[last_position * positions + square] != 0
    return {} unless at_first == at_last
    if at_first
      return {} if endpoint_count >= 2
      endpoints[endpoint_count] = square
      endpoint_count += 1
      return {} unless degree[square] == 5
    square += 1
  return {} unless endpoint_count == 2

  # Validate the exact transition multiset available at every successive pair
  # of recovered position domains.
  depth = 0
  while depth < positions - 1
    pfrom = position_sequence[depth]
    pto = position_sequence[depth + 1]
    expected_count = 0
    expected_sum = 0
    expected_squares = 0
    expected_cubes = 0
    sfrom = 0
    while sfrom < positions
      if matrix[pfrom * positions + sfrom] != 0
        d = 0
        while d < degree[sfrom]
          sto = neighbors[sfrom * WASSAT_KNIGHT_MAX_DEGREE + d]
          if matrix[pto * positions + sto] != 0
            code = sfrom * positions + sto + 1
            expected_count += 1
            expected_sum += code
            expected_squares += code * code
            cube = ((code * code) % WASSAT_KNIGHT_HASH_PRIME) * code
            expected_cubes = (
              expected_cubes + cube % WASSAT_KNIGHT_HASH_PRIME
            ) % WASSAT_KNIGHT_HASH_PRIME
          d += 1
      sfrom += 1
    pkey = pfrom * positions + pto
    return {} unless transition_count[pkey] == expected_count
    return {} unless transition_sum[pkey] == expected_sum
    return {} unless transition_squares[pkey] == expected_squares
    return {} unless transition_cubes[pkey] == expected_cubes
    depth += 1

  {
    "side": side, "positions": positions, "primary_vars": primary_count,
    "matrix": matrix, "semantics": semantics,
    "position_sequence": position_sequence,
    "neighbors": neighbors, "degree": degree, "endpoints": endpoints
  }

# Bounded Warnsdorff DFS on the recovered graph. The endpoint not used first is
# reserved for the final position, which is the decisive pruning rule for this
# closed-tour family.
-> wassat_knight_tour_dfs(depth, positions, matrix, position_sequence,
                          neighbors, degree, visited, path, reserved,
                          meta, node_cap, candidates, scores) (i64 i64 i64[] i64[] i64[] i8[] i8[] i64[] i64 i64[] i64 i64[] i64[]) i64
  meta[0] += 1
  if meta[0] > node_cap
    meta[1] = 1
    return 0
  if depth == positions - 1
    return path[depth] == reserved ? 1 : 0

  next_depth = depth + 1
  current = path[depth]
  # Each recursion depth owns one fixed eight-entry slice. Allocating these
  # arrays in the recursive body retained two objects per visited node in the
  # non-collecting native runtime and could turn a bounded miss into gigabytes
  # of resident memory. The caller allocates both workspaces once.
  work_base = depth * WASSAT_KNIGHT_MAX_DEGREE
  ncandidates = 0
  d = 0
  while d < degree[current]
    candidate = neighbors[current * WASSAT_KNIGHT_MAX_DEGREE + d]
    allowed = (
      visited[candidate] == 0 &&
      matrix[position_sequence[next_depth] * positions + candidate] != 0
    )
    if next_depth == positions - 1
      allowed = false unless candidate == reserved
    else
      allowed = false if candidate == reserved
    if allowed
      score = 0
      if next_depth + 1 < positions
        e = 0
        while e < degree[candidate]
          future = neighbors[candidate * WASSAT_KNIGHT_MAX_DEGREE + e]
          if (
            visited[future] == 0 && future != reserved &&
            matrix[position_sequence[next_depth + 1] * positions + future] != 0
          )
            score += 1
          e += 1
      candidates[work_base + ncandidates] = candidate
      scores[work_base + ncandidates] = score
      ncandidates += 1
    d += 1

  # Stable insertion sort by onward degree and then recovered square index.
  i = 1
  while i < ncandidates
    candidate = candidates[work_base + i]
    score = scores[work_base + i]
    j = i
    while j > 0 && (
      scores[work_base + j - 1] > score ||
      (
        scores[work_base + j - 1] == score &&
        candidates[work_base + j - 1] > candidate
      )
    )
      candidates[work_base + j] = candidates[work_base + j - 1]
      scores[work_base + j] = scores[work_base + j - 1]
      j -= 1
    candidates[work_base + j] = candidate
    scores[work_base + j] = score
    i += 1

  i = 0
  while i < ncandidates
    candidate = candidates[work_base + i]
    visited[candidate] = 1
    path[next_depth] = candidate
    if wassat_knight_tour_dfs(
      next_depth, positions, matrix, position_sequence,
      neighbors, degree, visited, path, reserved, meta, node_cap,
      candidates, scores
    ) == 1
      return 1
    visited[candidate] = 0
    return 0 if meta[1] == 1
    i += 1
  0

-> wassat_knight_find_tour(recovered, path, meta, node_cap)
  positions = recovered["positions"]
  matrix = recovered["matrix"] ## i64[]
  position_sequence = recovered["position_sequence"] ## i64[]
  neighbors = recovered["neighbors"] ## i64[]
  degree = recovered["degree"] ## i8[]
  endpoints = recovered["endpoints"] ## i64[]
  visited = i8[positions]
  candidates = i64[positions * WASSAT_KNIGHT_MAX_DEGREE]
  scores = i64[positions * WASSAT_KNIGHT_MAX_DEGREE]
  choice = 0
  while choice < 2
    start = endpoints[choice]
    reserved = endpoints[1 - choice]
    visited[start] = 1
    path[0] = start
    if wassat_knight_tour_dfs(
      0, positions, matrix, position_sequence, neighbors, degree,
      visited, path, reserved, meta, node_cap, candidates, scores
    ) == 1
      return 1
    visited[start] = 0
    return 0 if meta[1] == 1
    choice += 1
  0

# Native residual-index passes. Keeping these scans outside the object avoids
# a dynamic method dispatch and boxed integer path for each of the 1.3M input
# clauses; signed literals also remain signed machine integers throughout.
-> wassat_knight_residual_count(lits, offs, lens, ncl, assign, counts, stats) (i64[] i64[] i64[] i64 i8[] i64[] i64[]) i64
  ci = 0
  while ci < ncl
    off = offs[ci]
    n = lens[ci]
    sat = 0
    residual = 0
    j = 0
    while j < n
      literal = lits[off + j]
      value = assign[literal.abs]
      if value == 0
        residual += 1
      elsif (
        (literal > 0 && value == 1) ||
        (literal < 0 && value == -1)
      )
        sat = 1
      j += 1
    if sat == 0
      if residual == 0
        stats[2] = ci + 1
        return 0
      stats[0] += 1
      stats[1] += residual
      j = 0
      while j < n
        literal = lits[off + j]
        if assign[literal.abs] == 0
          key = literal > 0 ? 2 * literal : 2 * (0 - literal) + 1
          counts[key + 1] += 1
        j += 1
    ci += 1
  1

-> wassat_knight_residual_fill(lits, offs, lens, ncl, assign, cursor, active_ci, remaining, next_unsat, prev_unsat, occ_active, stats) (i64[] i64[] i64[] i64 i8[] i64[] i64[] i64[] i64[] i64[] i64[] i64[]) i64
  ai = 0
  ci = 0
  while ci < ncl
    off = offs[ci]
    n = lens[ci]
    sat = 0
    residual = 0
    j = 0
    while j < n
      literal = lits[off + j]
      value = assign[literal.abs]
      if value == 0
        residual += 1
      elsif (
        (literal > 0 && value == 1) ||
        (literal < 0 && value == -1)
      )
        sat = 1
      j += 1
    if sat == 0
      active_ci[ai] = ci
      remaining[ai] = residual
      prev_unsat[ai] = ai - 1
      next_unsat[ai] = ai + 1
      j = 0
      while j < n
        literal = lits[off + j]
        if assign[literal.abs] == 0
          key = literal > 0 ? 2 * literal : 2 * (0 - literal) + 1
          slot = cursor[key]
          occ_active[slot] = ai
          cursor[key] += 1
        j += 1
      ai += 1
    ci += 1
  stats[0] = ai
  1

# Compact, chronological completion for a recovered tour.  Conditioning fixes
# every primary variable; on the public family, unit propagation then fixes all
# but a handful of Tseitin/cardinality auxiliaries.  Loading the entire 1.3M
# clause formula into the general CDCL arena retained hundreds of megabytes of
# search-only state for those last few choices.  This completer instead indexes
# only clauses not already satisfied by the recovered primary assignment.
#
# The occurrence CSR, per-clause counters, and intrusive unsatisfied list are
# all flat typed arrays.  Search is bounded, chronological, false-first DPLL.
# It never claims UNSAT: a conflict/cap/malformed residual falls through, and a
# SAT candidate still has to replay against every original clause.
+ WassatKnightResidual
  -> new(@formula, @assign, @conflict_cap)
    @nvars = @formula["nvars"]
    @ncl = @formula["flat_ncl"]
    @lits = @formula["flat_lits"] ## i64[]
    @offs = @formula["flat_offs"] ## i64[]
    @lens = @formula["flat_lens"] ## i64[]
    @nlit = 2 * @nvars + 2
    @processed = i8[@nvars + 1]
    v = 1
    while v <= @nvars
      @processed[v] = @assign[v] if @assign[v] != 0
      v += 1
    @trail = i64[@nvars + 2]
    @decision_start = i64[@nvars + 2]
    @decision_var = i64[@nvars + 2]
    @decision_phase = i8[@nvars + 2]
    @scan = i64[2]
    @tsize = 0
    @qhead = 0
    @depth = 0
    @conflicts = 0
    @decisions = 0
    @props = 0
    @bounded = false
    @built = self.build

  -> lit_index(literal)
    literal > 0 ? 2 * literal : 2 * (0 - literal) + 1

  -> build
    lits = @lits ## i64[]
    counts = i64[@nlit + 1]
    build_stats = i64[3]
    unless wassat_knight_residual_count(
      lits, @offs, @lens, @ncl, @assign, counts, build_stats
    ) == 1
      wassat_prof_note(
        "knight residual rejected fixed clause=[build_stats[2] - 1]"
      )
      return false

    active_count = build_stats[0]
    residual_total = build_stats[1]
    @active_count = active_count
    @active_ci = i64[active_count + 1]
    @remaining = i64[active_count + 1]
    @true_count = i64[active_count + 1]
    @next_unsat = i64[active_count + 1]
    @prev_unsat = i64[active_count + 1]
    @occ_starts = i64[@nlit + 1]
    li = 0
    total = 0
    while li <= @nlit
      total += counts[li]
      @occ_starts[li] = total
      li += 1
    unless total == residual_total
      wassat_prof_note(
        "knight residual occurrence mismatch total=[total] expected=[residual_total]"
      )
      return false
    @occ_active = i64[residual_total + 1]

    # Reuse the count array as the fill cursor; its prefix values are no
    # longer needed after `occ_starts` has captured them.
    li = 0
    while li <= @nlit
      counts[li] = @occ_starts[li]
      li += 1
    fill_stats = i64[1]
    wassat_knight_residual_fill(
      lits, @offs, @lens, @ncl, @assign, counts,
      @active_ci, @remaining, @next_unsat, @prev_unsat,
      @occ_active, fill_stats
    )
    unless fill_stats[0] == active_count
      wassat_prof_note(
        "knight residual active mismatch filled=[fill_stats[0]] expected=[active_count]"
      )
      return false
    if active_count > 0
      @next_unsat[active_count - 1] = -1
      @unsat_head = 0
    else
      @unsat_head = -1

    # Install all residual units before the first propagation pass.
    ai = 0
    while ai < active_count
      if @remaining[ai] == 1
        ci = @active_ci[ai]
        off = @offs[ci]
        j = 0
        unit = 0
        while j < @lens[ci]
          literal = lits[off + j]
          unit = literal if @assign[literal.abs] == 0
          j += 1
        if unit == 0 || self.enqueue(unit) == 0
          wassat_prof_note("knight residual rejected unit clause=[@active_ci[ai]]")
          return false
      ai += 1
    true

  -> remove_unsat(ai)
    return 0 if @prev_unsat[ai] == -2
    before = @prev_unsat[ai]
    after = @next_unsat[ai]
    if before >= 0
      @next_unsat[before] = after
    else
      @unsat_head = after
    @prev_unsat[after] = before if after >= 0
    @prev_unsat[ai] = -2
    @next_unsat[ai] = -2
    0

  -> add_unsat(ai)
    return 0 unless @prev_unsat[ai] == -2
    @prev_unsat[ai] = -1
    @next_unsat[ai] = @unsat_head
    @prev_unsat[@unsat_head] = ai if @unsat_head >= 0
    @unsat_head = ai
    0

  -> enqueue(literal)
    variable = literal.abs
    wanted = literal > 0 ? 1 : -1
    return 1 if @assign[variable] == wanted
    return 0 if @assign[variable] != 0
    return 0 if @tsize >= @nvars + 1
    @assign[variable] = wanted
    @trail[@tsize] = literal
    @tsize += 1
    1

  # Scan one residual clause. State: 0 conflict, 1 unit, 2 at least two
  # unassigned, 3 satisfied. The selected literal is in `@scan[1]`.
  -> scan_clause(ai, processed_only)
    lits = @lits ## i64[]
    ci = @active_ci[ai]
    off = @offs[ci]
    n = @lens[ci]
    first = 0
    j = 0
    while j < n
      literal = lits[off + j]
      variable = literal.abs
      value = processed_only ? @processed[variable] : @assign[variable]
      if value == 0
        if first != 0
          @scan[0] = 2
          @scan[1] = first
          return 0
        first = literal
      elsif (
        (literal > 0 && value == 1) ||
        (literal < 0 && value == -1)
      )
        @scan[0] = 3
        @scan[1] = 0
        return 0
      j += 1
    if first == 0
      @scan[0] = 0
      @scan[1] = 0
    else
      @scan[0] = 1
      @scan[1] = first
    0

  -> propagate
    while @qhead < @tsize
      literal = @trail[@qhead]
      @qhead += 1
      variable = literal.abs
      @processed[variable] = @assign[variable]
      polarity = 0
      while polarity < 2
        key = 2 * variable + polarity
        literal_true = (
          (literal > 0 && polarity == 0) ||
          (literal < 0 && polarity == 1)
        )
        slot = @occ_starts[key]
        finish = @occ_starts[key + 1]
        while slot < finish
          ai = @occ_active[slot]
          @remaining[ai] -= 1
          @props += 1
          if literal_true
            self.remove_unsat(ai) if @true_count[ai] == 0
            @true_count[ai] += 1
          elsif @true_count[ai] == 0 && @remaining[ai] <= 1
            self.scan_clause(ai, true)
            return 0 if @scan[0] == 0
            if @scan[0] == 1
              return 0 if self.enqueue(@scan[1]) == 0
          slot += 1
        polarity += 1
    1

  -> undo(target)
    while @tsize > target
      @tsize -= 1
      literal = @trail[@tsize]
      variable = literal.abs
      if @processed[variable] != 0
        polarity = 0
        while polarity < 2
          key = 2 * variable + polarity
          literal_true = (
            (literal > 0 && polarity == 0) ||
            (literal < 0 && polarity == 1)
          )
          slot = @occ_starts[key]
          finish = @occ_starts[key + 1]
          while slot < finish
            ai = @occ_active[slot]
            @remaining[ai] += 1
            if literal_true
              @true_count[ai] -= 1
              self.add_unsat(ai) if @true_count[ai] == 0
            slot += 1
          polarity += 1
        @processed[variable] = 0
      @assign[variable] = 0
    @qhead = target
    0

  -> solve
    return 0 unless @built
    ok = self.propagate
    while true
      if ok == 0
        @conflicts += 1
        if @conflict_cap > 0 && @conflicts >= @conflict_cap
          @bounded = true
          return 0
        found_alternative = false
        while @depth > 0 && !found_alternative
          at = @depth - 1
          self.undo(@decision_start[at])
          if @decision_phase[at] < 0
            @decision_phase[at] = 1
            @decisions += 1
            return 0 if self.enqueue(@decision_var[at]) == 0
            ok = self.propagate
            found_alternative = true
          else
            @depth -= 1
        return 0 unless found_alternative
      elsif @unsat_head < 0
        return 1
      else
        ai = @unsat_head
        self.scan_clause(ai, false)
        state = @scan[0]
        if state == 3
          # Defensive repair only; counter/list transitions should already
          # have removed a satisfied clause.
          self.remove_unsat(ai)
        elsif state == 1
          ok = self.enqueue(@scan[1])
          ok = self.propagate if ok == 1
        elsif state == 0
          ok = 0
        else
          if (
            @depth >= @nvars ||
            @decisions >= WASSAT_KNIGHT_COMPLETION_DECISIONS
          )
            @bounded = true
            return 0
          variable = @scan[1].abs
          @decision_start[@depth] = @tsize
          @decision_var[@depth] = variable
          @decision_phase[@depth] = -1
          @depth += 1
          @decisions += 1
          ok = self.enqueue(0 - variable)
          ok = self.propagate if ok == 1

  -> model
    result = []
    v = 1
    while v <= @nvars
      @assign[v] = -1 if @assign[v] == 0
      result.push(@assign[v] == 1 ? v : 0 - v)
      v += 1
    result

  -> conflicts
    @conflicts

  -> decisions
    @decisions

  -> props
    @props

  -> bounded?
    @bounded

-> wassat_knight_tour_solve(formula)
  wassat_knight_tour_solve_budget(
    formula, WASSAT_KNIGHT_COMPLETION_CONFLICTS, WASSAT_KNIGHT_NODE_CAP
  )

-> wassat_knight_tour_solve_budget(formula, conflict_cap, node_cap)
  miss = wassat_knight_tour_miss
  tprof = wassat_prof_clock
  recovered = wassat_knight_recover(formula)
  return miss if recovered.empty?
  tprof = wassat_prof("knight.recognize", tprof)

  positions = recovered["positions"]
  path = i64[positions]
  meta = i64[2]
  result = {
    "recognized": true, "status": 0, "model": [],
    "side": recovered["side"], "positions": positions,
    "primary_vars": recovered["primary_vars"], "nodes": 0,
    "conflicts": 0, "decisions": 0, "props": 0
  }
  found = wassat_knight_find_tour(
    recovered, path, meta, node_cap
  )
  result["nodes"] = meta[0]
  return result unless found == 1
  tprof = wassat_prof("knight.tour", tprof)

  matrix = recovered["matrix"] ## i64[]
  semantics = recovered["semantics"] ## i8[]
  position_sequence = recovered["position_sequence"] ## i64[]
  values = i8[formula["nvars"] + 1]
  variable = 1
  while variable <= formula["nvars"]
    if semantics[variable] == 1
      values[variable] = -1
    elsif semantics[variable] == -1
      values[variable] = 1
    variable += 1
  depth = 0
  while depth < positions
    variable = matrix[
      position_sequence[depth] * positions + path[depth]
    ]
    return result if variable <= 0
    values[variable] = semantics[variable]
    depth += 1

  completion = WassatKnightResidual.new(formula, values, conflict_cap)
  tprof = wassat_prof("knight.load", tprof)
  status = completion.solve
  tprof = wassat_prof("knight.complete", tprof)
  result["conflicts"] = completion.conflicts
  result["decisions"] = completion.decisions
  result["props"] = completion.props
  wassat_prof_note(
    "knight residual status=[status] conflicts=[result["conflicts"]] " +
    "decisions=[result["decisions"]] props=[result["props"]]"
  )
  return result unless status == 1
  model = completion.model
  return result unless model.size == formula["nvars"]
  return result unless wassat_model_satisfies?(formula, model)
  result["status"] = 1
  result["model"] = model
  result
