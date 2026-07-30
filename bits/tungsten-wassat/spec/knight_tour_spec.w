use spec
use knight_tour

-> knight_fixture_edge?(a, b, side)
  ar = a / side
  ac = a % side
  br = b / side
  bc = b % side
  dr = (ar - br).abs
  dc = (ac - bc).abs
  (dr == 1 && dc == 2) || (dr == 2 && dc == 1)

# A clean-room six-by-six instance with the same structural contract as the
# public distance-pruned family. Transition auxiliaries are private positive
# literals, keeping the fixture small while exercising complete recovery,
# tour construction, conditioned completion, and original-CNF replay.
-> knight_fixture(corrupt_support = false)
  side = 6
  vertices = side * side
  positions = vertices - 1
  endpoint0 = side + 2
  endpoint1 = 2 * side + 1

  near = i8[vertices]
  near[endpoint0] = 1
  near[endpoint1] = 1
  square = 1
  while square < vertices
    if (
      knight_fixture_edge?(endpoint0, square, side) ||
      knight_fixture_edge?(endpoint1, square, side)
    )
      near[square] = 1
    square += 1

  allowed = i8[positions * positions]
  position = 0
  while position < positions
    square = 1
    while square < vertices
      keep = true
      if position == 0 || position == positions - 1
        keep = square == endpoint0 || square == endpoint1
      elsif position == 1 || position == positions - 2
        keep = near[square] == 1
      allowed[position * positions + square - 1] = 1 if keep
      square += 1
    position += 1

  variable_at = i64[positions * positions]
  next_variable = 1
  position = 0
  while position < positions
    square_index = 0
    while square_index < positions
      if allowed[position * positions + square_index] == 1
        variable_at[position * positions + square_index] = next_variable
        next_variable += 1
      square_index += 1
    position += 1

  lines = []

  # Every square support is long.
  square_index = 0
  while square_index < positions
    support = []
    position = 0
    while position < positions
      variable = variable_at[position * positions + square_index]
      support.push(variable) if variable != 0
      position += 1
    if corrupt_support && square_index == 0
      support[1] = support[0]
    lines.push(support.join(" ") + " 0")
    square_index += 1

  # All but the first/last two position supports are long.
  position = 2
  while position < positions - 2
    support = []
    square_index = 0
    while square_index < positions
      support.push(variable_at[position * positions + square_index])
      square_index += 1
    lines.push(support.join(" ") + " 0")
    position += 1

  small_positions = [0, 1, positions - 2, positions - 1]
  k = 0
  while k < small_positions.size
    position = small_positions[k]
    support = []
    square_index = 0
    while square_index < positions
      variable = variable_at[position * positions + square_index]
      support.push(variable) if variable != 0
      square_index += 1
    lines.push(support.join(" ") + " 0")
    k += 1

  # One ternary for every legal directed edge at every adjacent domain pair.
  position = 0
  while position < positions - 1
    source = 1
    while source < vertices
      source_variable = variable_at[position * positions + source - 1]
      if source_variable != 0
        destination = 1
        while destination < vertices
          destination_variable = variable_at[
            (position + 1) * positions + destination - 1
          ]
          if (
            destination_variable != 0 &&
            knight_fixture_edge?(source, destination, side)
          )
            lines.push(
              "-[source_variable] [destination_variable] [next_variable] 0"
            )
            next_variable += 1
          destination += 1
      source += 1
    position += 1

  (
    "p cnf [next_variable - 1] [lines.size]\n" +
    lines.join("\n") + "\n"
  )

describe "Wassat distance-pruned knight-tour specialist" ->
  it "recovers the two support families and generates a table-free tour" ->
    formula = wassat_parse_cnf_native(knight_fixture)
    recovered = wassat_knight_recover(formula)
    expect(recovered.empty?).to eq(false)
    expect(recovered["side"]).to eq(6)
    expect(recovered["positions"]).to eq(35)
    path = i64[35]
    meta = i64[2]
    found = wassat_knight_find_tour(
      recovered, path, meta, WASSAT_KNIGHT_NODE_CAP
    )
    expect(found).to eq(1)
    expect(meta[0] > 0).to eq(true)
    expect(meta[0] < WASSAT_KNIGHT_NODE_CAP).to eq(true)

  it "completes and replays a recovered tour against the original CNF" ->
    formula = wassat_parse_cnf_native(knight_fixture)
    result = wassat_knight_tour_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(1)
    expect(result["model"].size).to eq(formula["nvars"])
    expect(wassat_model_satisfies?(formula, result["model"])).to eq(true)

  it "treats a zero completion-conflict cap as unlimited" ->
    formula = wassat_parse_cnf_native(knight_fixture)
    result = wassat_knight_tour_solve_budget(
      formula, 0, WASSAT_KNIGHT_NODE_CAP
    )
    expect(result["status"]).to eq(1)
    expect(wassat_model_satisfies?(formula, result["model"])).to eq(true)

  it "falls through when the bounded tour search is exhausted" ->
    formula = wassat_parse_cnf_native(knight_fixture)
    result = wassat_knight_tour_solve_budget(formula, 100, 1)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(0)
    expect(result["model"]).to eq([])

  it "rejects duplicated incidence in a long support clause" ->
    formula = wassat_parse_cnf_native(knight_fixture(true))
    expect(wassat_knight_recover(formula).empty?).to eq(true)

  it "falls through on unrelated formulas" ->
    formula = wassat_parse_cnf_native("p cnf 1 1\n1 0\n")
    result = wassat_knight_tour_solve(formula)
    expect(result["recognized"]).to eq(false)
    expect(result["status"]).to eq(0)
    expect(result["model"]).to eq([])

spec_summary
