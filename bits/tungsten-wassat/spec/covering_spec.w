use spec
use wassat

-> covering_formula(rows, conflicts, nvars = 4)
  lines = []
  rows.each -> (row)
    lines.push(row.join(" ") + " 0")
  conflicts.each -> (edge)
    lines.push("-[edge[0]] -[edge[1]] 0")
  wassat_parse_cnf_native(
    "p cnf [nvars] [lines.size]\n" + lines.join("\n") + "\n"
  )

-> covering_complete_edges(n)
  edges = []
  a = 1
  while a <= n
    b = a + 1
    while b <= n
      edges.push([a, b])
      b += 1
    a += 1
  edges

describe "Wassat exact conflict-cover shortcut" ->
  it "finds and verifies a covering independent set" ->
    f = covering_formula(
      [[1, 2, 3], [2, 3, 4]],
      [[1, 2], [2, 3]]
    )
    result = wassat_covering_solve(f)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(1)
    expect(wassat_model_satisfies?(f, result["model"])).to eq(true)

  it "exhaustively refutes an impossible conflict cover" ->
    # A complete conflict graph permits at most one selected variable, while
    # the four rows each omit a different variable.
    f = covering_formula(
      [[1, 2, 3], [1, 2, 4], [1, 3, 4], [2, 3, 4]],
      covering_complete_edges(4)
    )
    result = wassat_covering_solve(f)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(-1)

  it "returns unknown rather than guessing when its node cap is exhausted" ->
    f = covering_formula(
      [[1, 2, 3], [2, 3, 4]],
      [[1, 2], [2, 3]]
    )
    result = wassat_covering_solve(f, 1)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(0)

  it "proves a closed conflict cover has a unique solution" ->
    f = covering_formula(
      [[1, 2, 3], [1, 2, 4], [1, 3, 4]],
      covering_complete_edges(4)
    )
    result = wassat_covering_solve_limit(f, WASSAT_COVER_NODE_CAP, 2)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(1)
    expect(result["solutions"]).to eq(1)
    expect(result["unique"]).to eq(true)
    expect(result["multi"]).to eq(false)
    expect(wassat_model_satisfies?(f, result["model"])).to eq(true)

  it "stops after proving that a closed conflict cover has two solutions" ->
    f = covering_formula(
      [[1, 2, 3, 4]],
      covering_complete_edges(4)
    )
    result = wassat_covering_solve_limit(f, WASSAT_COVER_NODE_CAP, 2)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(1)
    expect(result["solutions"]).to eq(2)
    expect(result["unique"]).to eq(false)
    expect(result["multi"]).to eq(true)
    expect(wassat_model_satisfies?(f, result["model"])).to eq(true)

  it "declines uniqueness when an arbitrary covering variable stays free" ->
    f = covering_formula(
      [[1, 2, 3]],
      [[1, 2]]
    )
    result = wassat_covering_solve_limit(f, WASSAT_COVER_NODE_CAP, 2)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(0)
    expect(result["unsafe_free"]).to eq(true)

  it "still exhaustively refutes an impossible cover in count-to-two mode" ->
    f = covering_formula(
      [[1, 2, 3], [1, 2, 4], [1, 3, 4], [2, 3, 4]],
      covering_complete_edges(4)
    )
    result = wassat_covering_solve_limit(f, WASSAT_COVER_NODE_CAP, 2)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(-1)
    expect(result["solutions"]).to eq(0)
    expect(result["unique"]).to eq(false)
    expect(result["multi"]).to eq(false)

  it "rejects clauses outside the exact positive-row/negative-edge shape" ->
    mixed = wassat_parse_cnf_native(
      "p cnf 4 2\n1 -2 3 0\n-1 -4 0\n"
    )
    negative_wide = wassat_parse_cnf_native(
      "p cnf 4 2\n1 2 3 0\n-1 -2 -4 0\n"
    )
    positive_binary = wassat_parse_cnf_native(
      "p cnf 4 2\n1 2 0\n-3 -4 0\n"
    )
    duplicate = wassat_parse_cnf_native(
      "p cnf 4 2\n1 1 3 0\n-1 -4 0\n"
    )
    self_edge = wassat_parse_cnf_native(
      "p cnf 4 2\n1 2 3 0\n-1 -1 0\n"
    )
    expect(wassat_covering_solve(mixed)["recognized"]).to eq(false)
    expect(wassat_covering_solve(negative_wide)["recognized"]).to eq(false)
    expect(wassat_covering_solve(positive_binary)["recognized"]).to eq(false)
    expect(wassat_covering_solve(duplicate)["recognized"]).to eq(false)
    expect(wassat_covering_solve(self_edge)["recognized"]).to eq(false)

  it "agrees exhaustively with CDCL on all four-variable row/edge subsets" ->
    rows = [[1, 2, 3], [1, 2, 4], [1, 3, 4], [2, 3, 4]]
    edges = covering_complete_edges(4)
    row_mask = 1
    while row_mask < 16
      edge_mask = 1
      while edge_mask < 64
        lines = []
        i = 0
        while i < rows.size
          lines.push(rows[i].join(" ") + " 0") if (row_mask & (1 << i)) != 0
          i += 1
        i = 0
        while i < edges.size
          if (edge_mask & (1 << i)) != 0
            edge = edges[i]
            a = 0 - edge[0]
            b = 0 - edge[1]
            lines.push("[a] [b] 0")
          i += 1
        text = "p cnf 4 [lines.size]\n" + lines.join("\n") + "\n"
        cover = wassat_covering_solve(wassat_parse_cnf_native(text))
        cdcl = wassat_solve_opts(text, false)
        expect(cover["status"]).to eq(cdcl["status"])
        edge_mask += 1
      row_mask += 1

spec_summary
