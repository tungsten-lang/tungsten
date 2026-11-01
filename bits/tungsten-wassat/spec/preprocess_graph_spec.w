use spec
use ../lib/wassat

-> graph_rows(p, nv)
  g = p.build_binary_graph
  out = []
  u = 2
  while u < 2 * nv + 2
    k = g[0][u]
    while k < g[0][u + 1]
      out.push([u, g[1][k], g[2][k]])
      k += 1
    u += 1
  out

-> graph_partition_oracle(seed)
  nv = 2 + (seed % 5)
  n = 2 * nv + 2
  rows = []
  reach = i64[n * n]
  i = 2
  while i < n
    reach[i * n + i] = 1
    i += 1
  r = seed + 1
  i = 0
  edges = 0
  while i < seed % 19
    r = (r * 1103515245 + 12345) & 2147483647
    a = 1 + ((r >> 8) % nv)
    a = 0 - a if ((r >> 17) & 1) == 1
    r = (r * 1103515245 + 12345) & 2147483647
    b = 1 + ((r >> 8) % nv)
    b = 0 - b if ((r >> 19) & 1) == 1
    rows.push([a, b])
    if a != b && a != 0 - b
      ai = a > 0 ? 2 * a : 2 * (0 - a) + 1
      bi = b > 0 ? 2 * b : 2 * (0 - b) + 1
      reach[(ai ^ 1) * n + bi] = 1
      reach[(bi ^ 1) * n + ai] = 1
      edges += 2
    i += 1
  k = 2
  while k < n
    i = 2
    while i < n
      j = 2
      while j < n
        reach[i * n + j] = 1 if reach[i * n + k] == 1 && reach[k * n + j] == 1
        j += 1
      i += 1
    k += 1
  p = WassatPreprocess.new(nv, rows, WASSAT_PROOF_NONE, nil)
  p.intake
  g = p.build_binary_graph
  comp = p.tarjan(g)
  ok = g[0][n] == edges
  i = 2
  while i < n
    j = 2
    while j < n
      same = reach[i * n + j] == 1 && reach[j * n + i] == 1
      ok = false unless (comp[i] == comp[j]) == same
      j += 1
    i += 1
  ok

describe "Flat preprocessing implication graph" ->
  it "keeps clause order and provenance while omitting inadmissible edges" ->
    rows = [[-1, 2], [-1, 2], [3, 3], [3, -3], [-2, 4], [-4, 5], [1, 2, 3], [5]]
    p = WassatPreprocess.new(5, rows, WASSAT_PROOF_NONE, nil)
    p.intake
    expect(graph_rows(p, 5)).to eq([[2, 4, 0], [2, 4, 1], [4, 8, 4], [5, 3, 0], [5, 3, 1], [9, 5, 4]])
    p.delete_clause(4)
    expect(graph_rows(p, 5)).to eq([[2, 4, 0], [2, 4, 1], [5, 3, 0], [5, 3, 1]])

  it "reuses capacity and resets offsets after the live database changes" ->
    p = WassatPreprocess.new(4, [[-1, 2], [-2, 3]], WASSAT_PROOF_NONE, nil)
    p.intake
    g = p.build_binary_graph
    offsets = g[0]
    targets = g[1]
    clauses = g[2]
    bytes = p.artifact["stats"]["scc_graph_bytes"]
    offsets[0] = 99
    targets[0] = -99
    clauses[0] = -99
    p.delete_clause(1)
    rows = graph_rows(p, 4)
    expect(rows).to eq([[2, 4, 0], [5, 3, 0]])
    expect(offsets[0]).to eq(0)
    expect(targets[0]).to eq(4)
    expect(clauses[0]).to eq(0)
    expect(p.artifact["stats"]["scc_graph_bytes"]).to eq(bytes)
    expect(p.artifact["stats"]["scc_edges"]).to eq(6)

  it "grows edge buffers from an empty graph and preserves parallel edges" ->
    p = WassatPreprocess.new(4, [], WASSAT_PROOF_NONE, nil)
    p.intake
    g = p.build_binary_graph
    expect(g[0][10]).to eq(0)
    i = 0
    while i < 8
      p.store([1, 2])
      i += 1
    g = p.build_binary_graph
    expect(g[0][10]).to eq(16)
    expect(g[1].size >= 16).to eq(true)
    expect(g[2][7]).to eq(7)
    expect(g[2][15]).to eq(7)
    p.store([-3, 4])
    g = p.build_binary_graph
    expect(g[0][10]).to eq(18)
    expect(g[1].size >= 18).to eq(true)
    expect(g[2][7]).to eq(7)
    expect(g[2][15]).to eq(7)
    expect(g[2][16]).to eq(8)
    expect(g[2][17]).to eq(8)

  it "keeps deterministic shortest proof paths through nontrivial components" ->
    rows = [[-1, 2], [-1, 3], [-2, 4], [-3, 4], [-4, 1]]
    p = WassatPreprocess.new(4, rows, WASSAT_PROOF_WRAT, nil)
    p.intake
    g = p.build_binary_graph
    comp = p.tarjan(g)
    expect(p.implication_path(g, comp, 1, 4)).to eq([0, 2])
    expect(p.implication_path(g, comp, 4, 3)).to eq([4, 1])
    expect(p.implication_path(g, comp, 1, 1)).to eq([])

  it "honors cancellation before allocating graph storage" ->
    p = WassatPreprocess.new(4, [[-1, 2], [-2, 3]], WASSAT_PROOF_NONE, nil)
    p.intake
    stop = i64[1]
    p.set_stop_cell(stop)
    wassat_stop_cancel(stop)
    p.run_substitution
    a = p.artifact
    expect(a["stats"]["scc_runs"]).to eq(0)
    expect(a["stats"]["scc_edges"]).to eq(0)
    expect(a["stats"]["scc_graph_bytes"]).to eq(0)

  it "matches independent transitive closure on 128 signed graphs" ->
    seed = 0
    failure = -1
    while seed < 128 && failure < 0
      failure = seed unless graph_partition_oracle(seed)
      seed += 1
    expect(failure).to eq(-1)

spec_summary
