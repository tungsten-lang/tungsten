use spec
use wassat

-> ais_counter_cell(n, k, row, col)
  n + row * k + col + 1

-> ais_clause_line(clause, reverse_literals)
  values = []
  if reverse_literals
    i = clause.size - 1
    while i >= 0
      values.push(clause[i])
      i -= 1
  else
    clause.each -> (lit)
      values.push(lit)
  values.join(" ") + " 0"

# Standard sequential at-most-k counter over inputs 1..n, followed by the
# supplied positive graph-edge clauses.  `omit_final` creates a malformed
# counter for rejection tests; `duplicate_edge` preserves satisfiability while
# exercising strict duplicate rejection.
-> ais_counter_text(n, k, edges, permuted = false,
                    omit_final = false, duplicate_edge = false)
  clauses = []

  # First counter row.
  clauses.push([0 - 1, ais_counter_cell(n, k, 0, 0)])
  j = 1
  while j < k
    clauses.push([0 - ais_counter_cell(n, k, 0, j)])
    j += 1

  # Middle rows, one for inputs 2..n-1.
  row = 1
  while row < n - 1
    x = row + 1
    clauses.push([0 - x, ais_counter_cell(n, k, row, 0)])
    clauses.push([
      0 - ais_counter_cell(n, k, row - 1, 0),
      ais_counter_cell(n, k, row, 0)
    ])
    j = 1
    while j < k
      clauses.push([
        0 - x,
        0 - ais_counter_cell(n, k, row - 1, j - 1),
        ais_counter_cell(n, k, row, j)
      ])
      clauses.push([
        0 - ais_counter_cell(n, k, row - 1, j),
        ais_counter_cell(n, k, row, j)
      ])
      j += 1
    clauses.push([
      0 - x,
      0 - ais_counter_cell(n, k, row - 1, k - 1)
    ])
    row += 1

  unless omit_final
    clauses.push([
      0 - n,
      0 - ais_counter_cell(n, k, n - 2, k - 1)
    ])

  edges.each -> (edge)
    clauses.push([edge[0], edge[1]])
  if duplicate_edge && !edges.empty?
    clauses.push([edges[0][1], edges[0][0]])

  lines = []
  if permuted
    i = clauses.size - 1
    while i >= 0
      lines.push(ais_clause_line(clauses[i], true))
      i -= 1
  else
    clauses.each -> (clause)
      lines.push(ais_clause_line(clause, false))

  nv = n + (n - 1) * k
  "p cnf [nv] [lines.size]\n" + lines.join("\n") + "\n"

-> ais_complete_edges(n)
  edges = []
  a = 1
  while a <= n
    b = a + 1
    while b <= n
      edges.push([a, b])
      b += 1
    a += 1
  edges

describe "Wassat AIS sequential-counter certificate" ->
  it "certifies a permuted K4 cover bound exactly" ->
    text = ais_counter_text(4, 2, ais_complete_edges(4), true)
    result = wassat_ais_unsat(wassat_parse_cnf_native(text))
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(-1)
    expect(result["graph_vars"]).to eq(4)
    expect(result["upper_bound"]).to eq(2)
    expect(result["lower_bound"]).to eq(3)
    expect(result["components"]).to eq(1)

  it "does not claim UNSAT when the clique-cover bound only meets the counter" ->
    text = ais_counter_text(4, 2, [[1, 2], [3, 4]], true)
    result = wassat_ais_unsat(wassat_parse_cnf_native(text))
    expect(result["status"]).to eq(0)
    expect(wassat_solve_opts(text, false)["status"]).to eq(1)

  it "rejects a connected graph component that is not a clique" ->
    # Treating n-components as a bound without verifying completeness would
    # falsely refute this satisfiable path.
    text = ais_counter_text(4, 2, [[1, 2], [2, 3], [3, 4]], true)
    result = wassat_ais_unsat(wassat_parse_cnf_native(text))
    expect(result["status"]).to eq(0)
    expect(wassat_solve_opts(text, false)["status"]).to eq(1)

  it "rejects an incomplete counter and duplicate graph clauses" ->
    missing = ais_counter_text(
      4, 2, ais_complete_edges(4), false, true, false
    )
    duplicate = ais_counter_text(
      4, 2, ais_complete_edges(4), false, false, true
    )
    expect(
      wassat_ais_unsat(wassat_parse_cnf_native(missing))["status"]
    ).to eq(0)
    expect(
      wassat_ais_unsat(wassat_parse_cnf_native(duplicate))["status"]
    ).to eq(0)

  it "agrees with CDCL on every certified four-vertex graph" ->
    pairs = [[1, 2], [1, 3], [1, 4], [2, 3], [2, 4], [3, 4]]
    certified = 0
    mask = 0
    while mask < 64
      edges = []
      i = 0
      while i < pairs.size
        edges.push(pairs[i]) if (mask & (1 << i)) != 0
        i += 1
      text = ais_counter_text(4, 2, edges, mask % 2 == 1)
      result = wassat_ais_unsat(wassat_parse_cnf_native(text))
      if result["status"] == -1
        certified += 1
        expect(wassat_solve_opts(text, false)["status"]).to eq(-1)
      mask += 1
    expect(certified > 0).to eq(true)

  it "routes the fast CLI but leaves proof-mode UNSAT to the prover" ->
    bin = env("WASSAT_TEST_BIN")
    expect(bin == nil).to eq(false)
    input = "/tmp/wassat-ais-cli.cnf"
    fast_out = "/tmp/wassat-ais-cli-fast.out"
    proof_out = "/tmp/wassat-ais-cli-proof.out"
    proof = "/tmp/wassat-ais-cli.wrat"
    text = ais_counter_text(4, 2, ais_complete_edges(4), true)
    expect(write_file(input, text)).to eq(true)

    fast_cmd = "(" + bin + " " + input + " --fast > " + fast_out + " 2>&1); test $? -eq 20"
    expect(system(fast_cmd)).to eq(true)
    fast_text = read_file(fast_out)
    expect(fast_text.include?(
      "exact sequential-counter clique-cover certificate"
    )).to eq(true)

    File.unlink(proof) if File.exist?(proof)
    proof_cmd = "(" + bin + " " + input + " --proof " + proof + " > " + proof_out + " 2>&1); test $? -eq 20"
    expect(system(proof_cmd)).to eq(true)
    proved_text = read_file(proof_out)
    expect(proved_text.include?(
      "exact sequential-counter clique-cover certificate"
    )).to eq(false)
    expect(file?(proof)).to eq(true)

spec_summary
