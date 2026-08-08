use spec
use wassat

# A complete 2x2 instance of the compact encoding. Variables 1..16 are the
# cell/piece placement matrix; 17..24 are four two-color internal edges.
# Every piece exposes color zero on every edge, so the first permutation is a
# model. The fixture is intentionally generated independently of production
# recognition code.
-> edge_matching_fixture(extra, reverse_partitions, omit_last_partition)
  lines = []
  cells = [
    [1, 2, 3, 4],
    [5, 6, 7, 8],
    [9, 10, 11, 12],
    [13, 14, 15, 16]
  ]
  pieces = [
    [1, 5, 9, 13],
    [2, 6, 10, 14],
    [3, 7, 11, 15],
    [4, 8, 12, 16]
  ]
  first = reverse_partitions ? pieces : cells
  second = reverse_partitions ? cells : pieces
  first.each -> (row)
    lines.push(row.join(" ") + " 0")
  i = 0
  while i < second.size
    lines.push(second[i].join(" ") + " 0") unless omit_last_partition && i + 1 == second.size
    i += 1

  groups = [[17, 18], [19, 20], [21, 22], [23, 24]]
  groups.each -> (group)
    lines.push("[group[0]] [group[1]] 0")
    lines.push("-[group[0]] -[group[1]] 0")

  incident = [
    [17, 21],
    [17, 23],
    [19, 21],
    [19, 23]
  ]
  # Emit the two edge implications in separate generator passes. Production
  # rows likewise interleave each placement's relation instead of storing one
  # contiguous block, and recognition must not depend on that ordering.
  slot = 0
  while slot < 2
    cell = 0
    while cell < 4
      color = incident[cell][slot]
      cells[cell].each -> (v)
        lines.push("-[v] [color] 0")
      cell += 1
    slot += 1
  extra.each -> (clause)
    lines.push(clause)
  wassat_parse_cnf_native(
    "p cnf 24 [lines.size]\n" + lines.join("\n") + "\n"
  )

describe "Wassat compact edge-matching specialist" ->
  it "reconstructs the square grid and returns a verified complete model" ->
    formula = edge_matching_fixture([], false, false)
    result = wassat_edge_matching_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(1)
    expect(result["side"]).to eq(2)
    expect(result["cells"]).to eq(4)
    expect(result["edges"]).to eq(4)
    expect(result["nodes"]).to eq(5)
    expect(result["model"].size).to eq(24)
    expect(wassat_model_satisfies?(formula, result["model"])).to eq(true)

  it "falls through instead of claiming UNSAT at the search cap" ->
    result = wassat_edge_matching_solve(
      edge_matching_fixture([], false, false), 1
    )
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(0)
    expect(result["model"]).to eq([])

  it "recognizes either ordering of the cell and piece partitions" ->
    formula = edge_matching_fixture([], true, false)
    result = wassat_edge_matching_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(1)
    expect(wassat_model_satisfies?(formula, result["model"])).to eq(true)

  it "derives one omitted final partition row from uncovered placements" ->
    formula = edge_matching_fixture([], false, true)
    result = wassat_edge_matching_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(1)
    expect(wassat_model_satisfies?(formula, result["model"])).to eq(true)

  it "rejects a tail condition spanning two distinct cells" ->
    formula = edge_matching_fixture(["-1 -5 0"], false, false)
    result = wassat_edge_matching_solve(formula)
    expect(result["recognized"]).to eq(false)
    expect(result["status"]).to eq(0)

  it "rejects a placement relation with no legal one-hot tuple" ->
    formula = edge_matching_fixture(["-1 18 0"], false, false)
    result = wassat_edge_matching_solve(formula)
    expect(result["recognized"]).to eq(false)
    expect(result["status"]).to eq(0)

spec_summary
