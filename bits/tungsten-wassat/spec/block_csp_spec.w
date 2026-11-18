use spec
use ../lib/wassat

# Synthetic exact-one block CSPs: graph coloring and Hamiltonian path.

-> bcsp_clause(lines, lits)
  lines.push(lits.join(" ") + " 0")

-> bcsp_coloring_cnf(nv_graph, edges, colors, drop_one_amo)
  lines = []
  v = 0
  while v < nv_graph
    block = []
    c = 0
    while c < colors
      block.push(v * colors + c + 1)
      c += 1
    bcsp_clause(lines, block)
    c = 0
    while c < colors
      d = c + 1
      while d < colors
        unless drop_one_amo && v == 0 && c == 0 && d == 1
          bcsp_clause(lines, [0 - (v * colors + c + 1), 0 - (v * colors + d + 1)])
        d += 1
      c += 1
    v += 1
  edges.each -> (e)
    c = 0
    while c < colors
      bcsp_clause(lines, [0 - (e[0] * colors + c + 1), 0 - (e[1] * colors + c + 1)])
      c += 1
  "p cnf [nv_graph * colors] [lines.size]\n" + lines.join("\n") + "\n"

-> bcsp_hamiltonian_cnf(n, edges)
  adj = i64[n * n]
  edges.each -> (e)
    adj[e[0] * n + e[1]] = 1
    adj[e[1] * n + e[0]] = 1
  lines = []
  p = 0
  while p < n
    block = []
    v = 0
    while v < n
      block.push(p * n + v + 1)
      v += 1
    bcsp_clause(lines, block)
    v = 0
    while v < n
      u = v + 1
      while u < n
        bcsp_clause(lines, [0 - (p * n + v + 1), 0 - (p * n + u + 1)])
        u += 1
      v += 1
    p += 1
  v = 0
  while v < n
    cover = []
    p = 0
    while p < n
      cover.push(p * n + v + 1)
      p += 1
    bcsp_clause(lines, cover)
    p = 0
    while p < n
      q = p + 1
      while q < n
        bcsp_clause(lines, [0 - (p * n + v + 1), 0 - (q * n + v + 1)])
        q += 1
      p += 1
    v += 1
  p = 0
  while p + 1 < n
    v = 0
    while v < n
      u = 0
      while u < n
        if v != u && adj[v * n + u] == 0
          bcsp_clause(lines, [0 - (p * n + v + 1), 0 - ((p + 1) * n + u + 1)])
        u += 1
      v += 1
    p += 1
  "p cnf [n * n] [lines.size]\n" + lines.join("\n") + "\n"

describe "Wassat generic block CSP" ->
  it "colors a 5-cycle with three colors" ->
    cnf = bcsp_coloring_cnf(5, [[0, 1], [1, 2], [2, 3], [3, 4], [4, 0]], 3, false)
    formula = wassat_parse_cnf_native(cnf)
    res = wassat_block_csp_solve(formula)
    expect(res["status"]).to eq(1)
    expect(wassat_model_satisfies?(formula, res["model"])).to eq(true)

  it "refutes K4 with three colors" ->
    cnf = bcsp_coloring_cnf(4, [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]], 3, false)
    formula = wassat_parse_cnf_native(cnf)
    res = wassat_block_csp_solve(formula)
    expect(res["status"]).to eq(-1)

  it "falls through when one at-most-one binary is missing" ->
    cnf = bcsp_coloring_cnf(4, [[0, 1], [0, 2], [0, 3], [1, 2], [1, 3], [2, 3]], 3, true)
    formula = wassat_parse_cnf_native(cnf)
    res = wassat_block_csp_solve(formula)
    expect(res["recognized"]).to eq(false)

  it "finds a Hamiltonian path in a chorded 4-cycle" ->
    cnf = bcsp_hamiltonian_cnf(4, [[0, 1], [1, 2], [2, 3], [3, 0], [0, 2]])
    formula = wassat_parse_cnf_native(cnf)
    res = wassat_block_csp_solve(formula)
    expect(res["status"]).to eq(1)
    expect(wassat_model_satisfies?(formula, res["model"])).to eq(true)

  it "refutes Hamiltonian path in the 4-star" ->
    cnf = bcsp_hamiltonian_cnf(4, [[0, 1], [0, 2], [0, 3]])
    formula = wassat_parse_cnf_native(cnf)
    res = wassat_block_csp_solve(formula)
    expect(res["status"]).to eq(-1)

describe "Wassat pattern-domain decoding" ->
  it "lifts compact choices through a mixed-sign two-block clause" ->
    f = wassat_parse_cnf_native("p cnf 4 5\n-1 -2 0\n-3 4 0\n1 0\n-4 0\n1 -2 3 -4 0\n")
    r = wassat_compact_solve(f)
    expect(r["blocks"]).to eq(2)
    expect(wassat_model_satisfies?(f, r["model"])).to eq(true)

  it "declines a clause spanning three compact domains" ->
    f = wassat_parse_cnf_native("p cnf 6 4\n-1 -2 0\n-3 -4 0\n-5 -6 0\n1 2 3 5 0\n")
    expect(wassat_compact_solve(f)).to eq(nil)

  it "lifts signed one-hot values and retains merged support clauses" ->
    f = wassat_parse_cnf_native("p cnf 8 5\n-3 1 -2 4 0\n8 -6 5 -7 0\n-1 6 7 0\n1 0\n-6 0\n")
    r = wassat_signed_domain_solve(f, 4)
    expect(r["blocks"]).to eq(2)
    expect(wassat_model_satisfies?(f, r["model"])).to eq(true)

  it "declines when a satisfiable formula rejects the exactly-one proposal" ->
    f = wassat_parse_cnf_native("p cnf 8 4\n-1 2 3 4 0\n-5 6 7 8 0\n2 0\n3 0\n")
    expect(wassat_signed_domain_solve(f, 4)).to eq(nil)

spec_summary
