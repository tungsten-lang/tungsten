use spec
use sliding_puzzle

-> puzzle32_typed(values)
  out = i64[values.size]
  i = 0
  while i < values.size
    out[i] = values[i]
    i += 1
  out

-> puzzle32_initial_compact
  puzzle32_typed([
    4, 4, 22, 7, 8, 16, 19, 24, 3, 4, 9, 15, 20,
    1, 5, 10, 21, 14, 2, 17, 13, 23, 11, 12, 6, 18
  ])

-> puzzle32_goal_compact
  puzzle32_typed([
    1, 1, 5, 10, 15, 20, 1, 6, 11, 16, 21, 2, 7,
    12, 17, 22, 3, 8, 13, 18, 23, 4, 9, 14, 19, 24
  ])

-> puzzle32_boxed(values, n)
  out = []
  i = 0
  while i < n
    out.push(values[i])
    i += 1
  out

-> puzzle32_comparator_fixture
  order = [
    0, 1, 13, 18, 23, 3, 8, 14, 19, 24, 4, 9, 15,
    20, 25, 5, 10, 11, 16, 21, 6, 12, 17, 22, 2, 7
  ]
  lines = []
  helper_index = 0
  while helper_index < 26
    word = order[helper_index]
    helper = 131 + helper_index
    inverse = [helper]
    bit = 0
    while bit < 5
      variable = 1 + word * 5 + bit
      value = (word * 7 + 3) % 32
      signed = (value & (1 << bit)) != 0 ? variable : 0 - variable
      lines.push("-[helper] [signed] 0")
      inverse.push(0 - signed)
      bit += 1
    lines.push(inverse.join(" ") + " 0")
    helper_index += 1
  wassat_parse_cnf_native(
    "p cnf 156 [lines.size]\n" + lines.join("\n") + "\n"
  )

describe "Wassat compact sliding-puzzle specialist" ->
  it "decodes constants by state word rather than helper emission order" ->
    formula = puzzle32_comparator_fixture
    out = i64[26]
    lits = formula["flat_lits"] ## i64[]
    offs = formula["flat_offs"] ## i64[]
    lens = formula["flat_lens"] ## i64[]
    expect(wassat_puzzle_decode_constant(
      lits, offs, lens, 0, 131, 1, out
    )).to eq(true)
    word = 0
    while word < 26
      expect(out[word]).to eq((word * 7 + 3) % 32)
      word += 1

  it "expands the clean-room DIMACS state into the ordinary 5x5 board" ->
    board = i64[25]
    compact = puzzle32_initial_compact ## i64[]
    blank = wassat_puzzle_expand(compact, board)
    expect(blank).to eq(18)
    expect(puzzle32_boxed(board, 25)).to eq([
      1, 5, 10, 15, 20,
      2, 17, 13, 21, 14,
      12, 6, 18, 23, 11,
      7, 8, 16, 0, 22,
      3, 4, 9, 19, 24
    ])

  it "derives a 32-move Manhattan-optimal solution without Boolean search" ->
    board = i64[25]
    goal = i64[25]
    initial_compact = puzzle32_initial_compact ## i64[]
    goal_compact = puzzle32_goal_compact ## i64[]
    blank = wassat_puzzle_expand(initial_compact, board)
    goal_blank = wassat_puzzle_expand(goal_compact, goal)
    expect(goal_blank).to eq(0)
    path = i8[WASSAT_PUZZLE_MOVES]
    meta = i64[2]
    expect(wassat_puzzle_find_path(board, goal, blank, path, meta)).to eq(1)
    expect(meta[0] > 0).to eq(true)
    expect(meta[0] < WASSAT_PUZZLE_NODE_CAP).to eq(true)
    expect(puzzle32_boxed(board, 25)).to eq(puzzle32_boxed(goal, 25))

  it "encodes both primitive moves in every transition block as assumptions" ->
    path = i8[WASSAT_PUZZLE_MOVES]
    i = 0
    while i < WASSAT_PUZZLE_MOVES
      path[i] = i % 4
      i += 1
    assumptions = wassat_puzzle_action_assumptions(path)
    expect(assumptions.size).to eq(65)
    expect(assumptions.slice(0, 4)).to eq([-315, -316, 1063, -1064])
    expect(assumptions.slice(64, 1)).to eq([WASSAT_PUZZLE_NVARS])

  it "rejects malformed compact coordinates and duplicate tiles" ->
    compact = puzzle32_initial_compact ## i64[]
    compact[0] = 3
    board = i64[25]
    expect(wassat_puzzle_expand(compact, board)).to eq(-1)
    compact = puzzle32_initial_compact ## i64[]
    compact[2] = compact[3]
    expect(wassat_puzzle_expand(compact, board)).to eq(-1)

  it "falls through on unrelated formulas" ->
    formula = wassat_parse_cnf_native("p cnf 1 1\n1 0\n")
    result = wassat_sliding_puzzle_solve(formula)
    expect(result["recognized"]).to eq(false)
    expect(result["status"]).to eq(0)
    expect(result["model"]).to eq([])

spec_summary
