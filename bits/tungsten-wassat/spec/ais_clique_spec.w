use spec
use ../lib/ais

-> ais_rook_graph(rows, cols)
  n = rows * cols
  adj = i8[n * n]
  a = 0
  while a < n
    b = 0
    while b < n
      if a != b && (a / cols == b / cols || a % cols == b % cols)
        adj[a * n + b] = 1
      b += 1
    a += 1
  adj

describe "Wassat bounded neighborhood clique certificate" ->
  it "counts overlapping larger cliques with their exact incidence bound" ->
    adj = ais_rook_graph(4, 4)
    m = i64[6]
    expect(wassat_ais_clique_bound(adj, 16, m)).to eq(12)
    expect([m[0], m[1], m[2], m[4]]).to eq([8, 24, 2, 0])
    triangles = i64[4]
    expect(wassat_ais_triangle_bound(adj, 16, triangles)).to eq(11)

  it "rounds a fractional bound upward for unequal clique sizes" ->
    m = i64[6]
    expect(wassat_ais_clique_bound(ais_rook_graph(3, 4), 12, m)).to eq(9)
    expect([m[0], m[1], m[2]]).to eq([7, 17, 2])

  it "checks every neighborhood component before using it as a clique" ->
    adj = i8[36]
    a = 0
    while a < 6
      b = 0
      while b < 6
        adj[a * 6 + b] = 1 if a != b && a + b != 5
        b += 1
      a += 1
    m = i64[6]
    expect(wassat_ais_clique_bound(adj, 6, m)).to eq(0)
    expect(m[5]).to eq(6)
    triangles = i64[4]
    expect(wassat_ais_triangle_bound(adj, 6, triangles)).to eq(4)

  it "does not refute the relaxed graph with a five-vertex independent set" ->
    adj = ais_rook_graph(4, 4)
    [1, 4].each -> (b)
      adj[b] = 0
      adj[b * 16] = 0
    independent = [0, 1, 4, 10, 15]
    independent.each -> (a)
      independent.each -> (b)
        expect(adj[a * 16 + b]).to eq(0)
    m = i64[6]
    expect(wassat_ais_clique_bound(adj, 16, m) <= 11).to eq(true)

  it "never turns a partial clique count into a certificate on work exhaustion" ->
    adj = ais_rook_graph(4, 4)
    m = i64[6]
    expect(wassat_ais_clique_bound(adj, 16, m, 35)).to eq(0)
    expect([m[3], m[4]]).to eq([35, 1])
    expect(wassat_ais_clique_bound(adj, 16, m)).to eq(12)
    expect(m[4]).to eq(0)

spec_summary
