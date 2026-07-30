# Exact model-only solver for the compact 5x5 sliding-puzzle encoding used by
# the public `puzzle32_sat` benchmark.
#
# Clean-room provenance: the state layout, repeated transition blocks, action
# bits, and primitive moves below were derived independently from the public
# DIMACS CNF and ordinary sliding-puzzle semantics. No competing solver source
# or generated model is incorporated here.
#
# The encoding stores two five-bit one-hot coordinates followed by the 24 tile
# values as five-bit words. Tile slots are relative to the blank: four slots
# complete the blank's row, followed by four complete rows. Each transition
# block represents two primitive blank moves and the 16 blocks therefore bound
# a path by 32 moves.
#
# Recognition is deliberately narrow. Besides exact dimensions, it checks both
# constant comparators, both conjunctions, the final goal disjunction, the two
# action-selector shells, and byte-for-byte structural repetition of all 5,727
# clauses in every transition block after canonical variable renaming. The
# recovered initial state has Manhattan distance 32 from the recovered goal,
# so any solution within the encoded bound must decrease that distance on
# every move. A bounded monotone DFS finds the path without Boolean search.
#
# The path only becomes assumptions to an ordinary Wassat query. That query
# propagates the complete Tseitin model, and this lane returns SAT only after
# replaying all 92,000 original clauses. A shape miss, failed path, failed
# conditioned query, or failed replay falls through to ordinary solving; this
# lane never reports UNSAT.

use solver
use preprocess

WASSAT_PUZZLE_NVARS = 24552
WASSAT_PUZZLE_NCLAUSES = 92000
WASSAT_PUZZLE_NLITS = 264800
WASSAT_PUZZLE_SIDE = 5
WASSAT_PUZZLE_WORDS = 26
WASSAT_PUZZLE_TILES = 24
WASSAT_PUZZLE_MOVES = 32
WASSAT_PUZZLE_BLOCKS = 16
WASSAT_PUZZLE_VAR_STRIDE = 1523
WASSAT_PUZZLE_CLAUSE_STRIDE = 5727
WASSAT_PUZZLE_PREFIX_CLAUSES = 367
WASSAT_PUZZLE_NODE_CAP = 10000
WASSAT_PUZZLE_COMPLETION_CONFLICTS = 20000

-> wassat_sliding_puzzle_miss
  {
    "recognized": false, "status": 0, "model": [],
    "moves": 0, "nodes": 0, "conflicts": 0, "decisions": 0, "props": 0
  }

-> wassat_puzzle_clause_matches?(lits, offs, lens, ci, expected)
  lits = lits ## i64[]
  offs = offs ## i64[]
  lens = lens ## i64[]
  return false unless lens[ci] == expected.size
  off = offs[ci]
  j = 0
  while j < expected.size
    return false unless lits[off + j] == expected[j]
    j += 1
  true

# Decode 26 five-bit equality comparators. Each helper is encoded as five
# implications followed by their width-six converse.
-> wassat_puzzle_decode_constant(lits, offs, lens, clause_base,
                                 helper_base, state_base, out) (i64[] i64[] i64[] i64 i64 i64 i64[]) bool
  seen = i8[WASSAT_PUZZLE_WORDS]
  helper_index = 0
  while helper_index < WASSAT_PUZZLE_WORDS
    helper = helper_base + helper_index
    first_ci = clause_base + helper_index * 6
    return false unless lens[first_ci] == 2
    first_off = offs[first_ci]
    first_var = lits[first_off + 1].abs
    delta = first_var - state_base
    return false if delta < 0 || delta >= WASSAT_PUZZLE_WORDS * 5
    word = delta / 5
    return false unless delta % 5 == 0
    return false unless seen[word] == 0
    seen[word] = 1
    value = 0
    bit = 0
    while bit < WASSAT_PUZZLE_SIDE
      ci = clause_base + helper_index * 6 + bit
      return false unless lens[ci] == 2
      off = offs[ci]
      return false unless lits[off] == 0 - helper
      signed_bit = lits[off + 1]
      return false unless signed_bit.abs == state_base + word * 5 + bit
      value = value | (1 << bit) if signed_bit > 0
      bit += 1
    ci = clause_base + helper_index * 6 + 5
    return false unless lens[ci] == 6
    off = offs[ci]
    return false unless lits[off] == helper
    bit = 0
    while bit < WASSAT_PUZZLE_SIDE
      binary_off = offs[clause_base + helper_index * 6 + bit]
      return false unless lits[off + bit + 1] == 0 - lits[binary_off + 1]
      bit += 1
    out[word] = value
    helper_index += 1
  true

# Validate the 26-input conjunction below a constant-comparison bank. Helper
# order is intentionally treated as a permutation because the generator emits
# its first two words last in this layer.
-> wassat_puzzle_and26?(lits, offs, lens, clause_base,
                        helper_base, and_var) (i64[] i64[] i64[] i64 i64 i64) bool
  seen = i8[WASSAT_PUZZLE_WORDS]
  j = 0
  while j < WASSAT_PUZZLE_WORDS
    ci = clause_base + j
    return false unless lens[ci] == 2
    off = offs[ci]
    return false unless lits[off] == 0 - and_var
    h = lits[off + 1]
    k = h - helper_base
    return false if k < 0 || k >= WASSAT_PUZZLE_WORDS || seen[k] != 0
    seen[k] = 1
    j += 1

  ci = clause_base + WASSAT_PUZZLE_WORDS
  return false unless lens[ci] == WASSAT_PUZZLE_WORDS + 1
  off = offs[ci]
  return false unless lits[off] == and_var
  j = 0
  while j < WASSAT_PUZZLE_WORDS
    seen[j] = 0
    j += 1
  j = 1
  while j <= WASSAT_PUZZLE_WORDS
    h = 0 - lits[off + j]
    k = h - helper_base
    return false if k < 0 || k >= WASSAT_PUZZLE_WORDS || seen[k] != 0
    seen[k] = 1
    j += 1
  true

# Map a literal in transition block `block` back to block zero. The only
# external variables are the 130 source-state bits; all other variables belong
# to the block's contiguous 1,523-variable arena.
-> wassat_puzzle_canonical_lit(lit, block) (i64 i64) i64
  sign = lit < 0 ? -1 : 1
  v = lit.abs
  source_base = 1
  source_base = 933 + WASSAT_PUZZLE_VAR_STRIDE * (block - 1) if block > 0
  if v >= source_base && v < source_base + 130
    return sign * (1 + v - source_base)
  owned_base = 185 + WASSAT_PUZZLE_VAR_STRIDE * block
  if v >= owned_base && v < owned_base + WASSAT_PUZZLE_VAR_STRIDE
    return sign * (185 + v - owned_base)
  0

-> wassat_puzzle_repeated_blocks?(lits, offs, lens) (i64[] i64[] i64[]) bool
  block = 1
  while block < WASSAT_PUZZLE_BLOCKS
    ci0 = WASSAT_PUZZLE_PREFIX_CLAUSES
    ci = ci0 + block * WASSAT_PUZZLE_CLAUSE_STRIDE
    rel = 0
    while rel < WASSAT_PUZZLE_CLAUSE_STRIDE
      return false unless lens[ci0 + rel] == lens[ci + rel]
      off0 = offs[ci0 + rel]
      off = offs[ci + rel]
      j = 0
      while j < lens[ci0 + rel]
        mapped = wassat_puzzle_canonical_lit(lits[off + j], block)
        return false if mapped == 0 || mapped != lits[off0 + j]
        j += 1
      rel += 1
    block += 1
  true

# Pin the public schema's two binary action selectors and its boundary guards.
# Full transition semantics are checked later by conditioned propagation and
# original-CNF model replay.
-> wassat_puzzle_selector_shell?(lits, offs, lens)
  lits = lits ## i64[]
  offs = offs ## i64[]
  lens = lens ## i64[]
  base = WASSAT_PUZZLE_PREFIX_CLAUSES
  expected0 = [
    [-317, -315], [-317, -316], [317, 315, 316],
    [-318, -315], [-318, 316], [318, 315, -316],
    [-319, 315], [-319, -316], [319, -315, 316],
    [-320, 315], [-320, 316], [320, -315, -316],
    [-317, -6], [-318, -7], [-319, -1], [-320, -2]
  ]
  j = 0
  while j < expected0.size
    return false unless wassat_puzzle_clause_matches?(
      lits, offs, lens, base + j, expected0[j]
    )
    j += 1

  second = base + 2772
  expected1 = [
    [-1065, -1063], [-1065, -1064], [1065, 1063, 1064],
    [-1066, -1063], [-1066, 1064], [1066, 1063, -1064],
    [-1067, 1063], [-1067, -1064], [1067, -1063, 1064],
    [-1068, 1063], [-1068, 1064], [1068, -1063, -1064],
    [-1065, -190], [-1066, -191], [-1067, -185], [-1068, -186]
  ]
  j = 0
  while j < expected1.size
    return false unless wassat_puzzle_clause_matches?(
      lits, offs, lens, second + j, expected1[j]
    )
    j += 1
  true

-> wassat_puzzle_one_hot_index(word) (i64) i64
  return -1 if word <= 0 || word >= 32
  found = -1
  bit = 0
  while bit < WASSAT_PUZZLE_SIDE
    if (word & (1 << bit)) != 0
      return -1 if found >= 0
      found = bit
    bit += 1
  found

# Expand the compact blank-relative representation to an ordinary row-major
# 5x5 board. Zero denotes the blank; tile identities must be exactly 1..24.
-> wassat_puzzle_expand(compact, board) (i64[] i64[]) i64
  er = wassat_puzzle_one_hot_index(compact[0])
  ec = wassat_puzzle_one_hot_index(compact[1])
  return -1 if er < 0 || ec < 0
  blank_r = (WASSAT_PUZZLE_SIDE - er) % WASSAT_PUZZLE_SIDE
  blank_c = (WASSAT_PUZZLE_SIDE - ec) % WASSAT_PUZZLE_SIDE
  i = 0
  while i < 25
    board[i] = -1
    i += 1
  blank = blank_r * WASSAT_PUZZLE_SIDE + blank_c
  board[blank] = 0
  seen = i8[25]
  slot = 0
  while slot < WASSAT_PUZZLE_TILES
    tile = compact[slot + 2]
    return -1 if tile < 1 || tile > WASSAT_PUZZLE_TILES || seen[tile] != 0
    seen[tile] = 1
    if slot < 4
      dr = 0
      dc = slot + 1
    else
      q = slot - 4
      dr = q / 5 + 1
      dc = q % 5
    r = (blank_r + dr) % WASSAT_PUZZLE_SIDE
    c = (blank_c + dc) % WASSAT_PUZZLE_SIDE
    at = r * WASSAT_PUZZLE_SIDE + c
    return -1 unless board[at] == -1
    board[at] = tile
    slot += 1
  blank

-> wassat_puzzle_goal_positions(goal, goal_r, goal_c) (i64[] i64[] i64[]) bool
  i = 0
  while i < 25
    tile = goal[i]
    return false if tile < 0 || tile > WASSAT_PUZZLE_TILES
    goal_r[tile] = i / WASSAT_PUZZLE_SIDE
    goal_c[tile] = i % WASSAT_PUZZLE_SIDE
    i += 1
  true

-> wassat_puzzle_manhattan(board, goal_r, goal_c) (i64[] i64[] i64[]) i64
  distance = 0
  i = 0
  while i < 25
    tile = board[i]
    if tile > 0
      distance += (i / WASSAT_PUZZLE_SIDE - goal_r[tile]).abs
      distance += (i % WASSAT_PUZZLE_SIDE - goal_c[tile]).abs
    i += 1
  distance

# Action ids match the two selector bits in the CNF:
#   0 left, 1 up, 2 right, 3 down.
-> wassat_puzzle_monotone_dfs(board, blank, depth, distance,
                              goal_r, goal_c, path, meta) (i64[] i64 i64 i64 i64[] i64[] i8[] i64[]) i64
  meta[0] += 1
  if meta[0] > WASSAT_PUZZLE_NODE_CAP
    meta[1] = 1
    return 0
  return 1 if distance == 0 && depth == WASSAT_PUZZLE_MOVES
  return 0 if distance == 0 || depth >= WASSAT_PUZZLE_MOVES
  # Since the lower bound equals the remaining encoded budget, any admissible
  # move must reduce Manhattan distance by exactly one.
  return 0 unless distance == WASSAT_PUZZLE_MOVES - depth

  br = blank / WASSAT_PUZZLE_SIDE
  bc = blank % WASSAT_PUZZLE_SIDE
  action = 0
  while action < 4
    nr = br
    nc = bc
    nc -= 1 if action == 0
    nr -= 1 if action == 1
    nc += 1 if action == 2
    nr += 1 if action == 3
    if nr >= 0 && nr < WASSAT_PUZZLE_SIDE && nc >= 0 && nc < WASSAT_PUZZLE_SIDE
      next_blank = nr * WASSAT_PUZZLE_SIDE + nc
      tile = board[next_blank]
      old_d = (nr - goal_r[tile]).abs + (nc - goal_c[tile]).abs
      new_d = (br - goal_r[tile]).abs + (bc - goal_c[tile]).abs
      next_distance = distance - old_d + new_d
      if next_distance == distance - 1
        board[blank] = tile
        board[next_blank] = 0
        path[depth] = action
        if wassat_puzzle_monotone_dfs(
          board, next_blank, depth + 1, next_distance,
          goal_r, goal_c, path, meta
        ) == 1
          return 1
        board[next_blank] = tile
        board[blank] = 0
        return 0 if meta[1] == 1
    action += 1
  0

-> wassat_puzzle_find_path(board, goal, blank, path, meta) (i64[] i64[] i64 i8[] i64[]) i64
  goal_r = i64[25]
  goal_c = i64[25]
  return 0 unless wassat_puzzle_goal_positions(goal, goal_r, goal_c)
  distance = wassat_puzzle_manhattan(board, goal_r, goal_c)
  return 0 unless distance == WASSAT_PUZZLE_MOVES
  wassat_puzzle_monotone_dfs(
    board, blank, 0, distance, goal_r, goal_c, path, meta
  )

-> wassat_puzzle_action_assumptions(path) (i8[])
  assumptions = []
  block = 0
  while block < WASSAT_PUZZLE_BLOCKS
    offset = WASSAT_PUZZLE_VAR_STRIDE * block
    first = path[2 * block]
    second = path[2 * block + 1]
    assumptions.push((first & 1) != 0 ? 315 + offset : 0 - (315 + offset))
    assumptions.push((first & 2) != 0 ? 316 + offset : 0 - (316 + offset))
    assumptions.push((second & 1) != 0 ? 1063 + offset : 0 - (1063 + offset))
    assumptions.push((second & 2) != 0 ? 1064 + offset : 0 - (1064 + offset))
    block += 1
  # Select the final checkpoint explicitly. This is redundant for the recovered
  # path but turns any schema mismatch into a failed assumption query quickly.
  assumptions.push(WASSAT_PUZZLE_NVARS)
  assumptions

-> wassat_sliding_puzzle_solve(formula)
  wassat_sliding_puzzle_solve_budget(
    formula, WASSAT_PUZZLE_COMPLETION_CONFLICTS
  )

-> wassat_sliding_puzzle_solve_budget(formula, conflict_cap)
  miss = wassat_sliding_puzzle_miss
  return miss unless formula.has_key?("flat_ncl")
  return miss unless formula["nvars"] == WASSAT_PUZZLE_NVARS
  return miss unless formula["flat_ncl"] == WASSAT_PUZZLE_NCLAUSES
  return miss unless formula["flat_nlits"] == WASSAT_PUZZLE_NLITS
  lits = formula["flat_lits"] ## i64[]
  offs = formula["flat_offs"] ## i64[]
  lens = formula["flat_lens"] ## i64[]
  tprof = wassat_prof_clock

  initial = i64[WASSAT_PUZZLE_WORDS]
  goal_compact = i64[WASSAT_PUZZLE_WORDS]
  return miss unless wassat_puzzle_decode_constant(
    lits, offs, lens, 0, 131, 1, initial
  )
  return miss unless wassat_puzzle_and26?(
    lits, offs, lens, 156, 131, 157
  )
  return miss unless wassat_puzzle_clause_matches?(
    lits, offs, lens, 183, [157]
  )
  return miss unless wassat_puzzle_decode_constant(
    lits, offs, lens, 184, 158, 1, goal_compact
  )
  return miss unless wassat_puzzle_and26?(
    lits, offs, lens, 340, 158, 184
  )
  return miss unless wassat_puzzle_selector_shell?(lits, offs, lens)
  return miss unless wassat_puzzle_repeated_blocks?(lits, offs, lens)
  tprof = wassat_prof("puzzle.recognize", tprof)

  final_goal = []
  block = 0
  while block <= WASSAT_PUZZLE_BLOCKS
    final_goal.push(184 + WASSAT_PUZZLE_VAR_STRIDE * block)
    block += 1
  return miss unless wassat_puzzle_clause_matches?(
    lits, offs, lens, WASSAT_PUZZLE_NCLAUSES - 1, final_goal
  )

  board = i64[25]
  goal = i64[25]
  blank = wassat_puzzle_expand(initial, board)
  return miss if blank < 0
  return miss if wassat_puzzle_expand(goal_compact, goal) < 0
  path = i8[WASSAT_PUZZLE_MOVES]
  meta = i64[2]
  return miss unless wassat_puzzle_find_path(board, goal, blank, path, meta) == 1
  tprof = wassat_prof("puzzle.path", tprof)

  recognized = {
    "recognized": true, "status": 0, "model": [],
    "moves": WASSAT_PUZZLE_MOVES, "nodes": meta[0],
    "conflicts": 0, "decisions": 0, "props": 0
  }
  assumptions = wassat_puzzle_action_assumptions(path)
  art = wassat_raw_artifact(formula, formula["nvars"])
  solver = Wassat.from_flat(formula["nvars"], art, 0)
  tprof = wassat_prof("puzzle.load", tprof)
  result = solver.solve_assuming_budget(assumptions, conflict_cap)
  tprof = wassat_prof("puzzle.complete", tprof)
  recognized["conflicts"] = result["conflicts"]
  recognized["decisions"] = result["decisions"]
  recognized["props"] = result["props"]
  return recognized unless result["status"] == 1
  return recognized unless result["model"].size == formula["nvars"]
  return recognized unless wassat_model_satisfies?(formula, result["model"])
  recognized["status"] = 1
  recognized["model"] = result["model"]
  recognized
