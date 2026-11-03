use spec
use cyclic_bound_support

-> cycle_clique_check(f, n, k, edges, m, stop, deadline = 0)
  nv = f["nvars"]; nc = f["flat_ncl"]
  lits = f["flat_lits"]; offs = f["flat_offs"]; lens = f["flat_lens"]
  decode = i64[24]
  return 0 unless wassat_cycle_matrix(lits, offs, lens, nv, nc, n, decode, stop, deadline) == 1
  heads = i32[nv + 2]; back = i32[nv + 2]
  dest = i32[decode[4]]; src = i32[decode[4]]; fill = i32[nv + 1]
  owner = i32[nv + 1]; queue = i32[2 * (nv + 1)]
  return 0 unless wassat_cycle_implications(lits, offs, lens, nv, nc, heads, back, dest, src, fill, decode, stop, deadline) == 1
  return 0 unless wassat_cycle_owners(n, nv, heads, dest, owner, queue, decode, stop, deadline) == 1
  matrix = i8[n * n]
  edges.each -> (e)
    matrix[e[0] * n + e[1]] = 1
    matrix[e[1] * n + e[0]] = 1
  left = i32[edges.size]; right = i32[edges.size]
  gh = i32[n + 1]; occ = i32[2 * edges.size]; gf = i32[n]
  wassat_cycle_graph(n, matrix, left, right, gh, occ, gf)
  needed = i8[n * n]
  return 0 unless wassat_cycle_bound_clique(n,k,matrix,gh,needed,m,stop,deadline) == 1
  wassat_cycle_bound_verify(lits, offs, lens, nv, nc, n, k, owner, heads, dest, needed, fill, m, stop, deadline)


describe "Checked circular clique capacity" ->
  it "refutes a clique whose minimum gaps exceed the circle" ->
    edges = [[0,1],[0,2],[1,2]]
    m = i64[24]
    expect(cycle_clique_check(cycle_bound_fixture(8,3,edges),8,3,edges,m,i64[4])).to eq(-1)
    expect([m[0],m[2],m[3],m[4],m[5],m[18],m[19]]).to eq([-1,-1,3,2,3,8,3])

  it "allows a clique that fits exactly at the gap boundary" ->
    edges = [[0,1],[0,2],[1,2]]
    m = i64[24]
    expect(cycle_clique_check(cycle_bound_fixture(9,3,edges),9,3,edges,m,i64[4])).to eq(0)
    expect(m[0]).to eq(0)

  it "checks original row exclusions rather than trusting the graph" ->
    edges = [[0,1],[0,2],[1,2]]
    m = i64[24]
    expect(cycle_clique_check(cycle_bound_fixture(8,3,edges,"row"),8,3,edges,m,i64[4])).to eq(0)
    expect(m[0]).to eq(1)

  it "checks every required edge exclusion" ->
    edges = [[0,1],[0,2],[1,2]]
    m = i64[24]
    expect(cycle_clique_check(cycle_bound_fixture(8,3,edges,"edge"),8,3,edges,m,i64[4])).to eq(0)
    expect(m[0]).to eq(1)

  it "requires every original column" ->
    edges = [[0,1],[0,2],[1,2]]
    m = i64[24]
    expect(cycle_clique_check(cycle_bound_fixture(8,3,edges,"column"),8,3,edges,m,i64[4])).to eq(0)
    expect(m[20]).to eq(0)

  it "verifies alias implications with backward arcs" ->
    edges = [[0,1],[0,2],[1,2]]
    m = i64[24]
    expect(cycle_clique_check(cycle_bound_fixture(8,3,edges,"",true),8,3,edges,m,i64[4])).to eq(-1)
    expect(m[15] > 0).to eq(true)

  it "does not mistake high degree for a clique" ->
    edges = [[0,4],[0,5],[0,6],[0,7],[1,4],[1,5],[1,6],[1,7],[2,4],[2,5],[2,6],[2,7],[3,4],[3,5],[3,6],[3,7]]
    m = i64[24]
    expect(cycle_clique_check(cycle_bound_fixture(8,3,edges),8,3,edges,m,i64[4])).to eq(0)
    expect([m[0],m[20]]).to eq([0,0])

  it "honors cancellation and deadlines before searching" ->
    stop = i64[4]
    wassat_stop_cancel(stop)
    m = i64[24]
    expect(wassat_cycle_bound_clique(8,3,i8[64],i32[9],i8[64],m,stop,0)).to eq(0)
    expect(m[22]).to eq(1)
    m = i64[24]
    expect(wassat_cycle_bound_clique(8,3,i8[64],i32[9],i8[64],m,i64[4],clock_ms()-1)).to eq(0)
    expect(m[22]).to eq(2)

spec_summary
