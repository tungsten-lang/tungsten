use spec
use ../lib/wassat
use ../lib/treewidth
use treewidth_support

describe "Clause-checked treewidth minor refutations" ->
  it "refutes a clique above the decoded bound" ->
    f = treewidth_clique(4, 2).flat; m = i64[32]
    expect(wassat_treewidth_refute(f, m, i64[2])).to eq(-1)
    expect(m[2]).to eq(f["flat_ncl"])
    expect(m[4]).to eq(4)
    expect(m[7]).to eq(2)

  it "declines satisfiable graphs and weaker bounds" ->
    cycle = TreewidthFixture.new(4, [[0, 1], [1, 2], [2, 3], [3, 0]], 2)
    expect(wassat_treewidth_refute(cycle.flat, i64[32], i64[2])).to eq(0)
    expect(wassat_treewidth_refute(treewidth_clique(4, 3).flat, i64[32], i64[2])).to eq(0)

  it "accepts literal permutations made by early watched propagation" ->
    f = treewidth_clique(4, 2)
    f.clauses.each ->(c)
      a = 0; b = c.size - 1
      while a < b
        x = c[a]; c[a] = c[b]; c[b] = x; a += 1; b -= 1
    expect(wassat_treewidth_refute(f.flat, i64[32], i64[2])).to eq(-1)

  it "requires the original ordering clauses" ->
    f = treewidth_clique(4, 2); f.clauses[1][0] = 1
    expect(wassat_treewidth_refute(f.flat, i64[32], i64[2])).to eq(0)

  it "requires fill and orientation clauses" ->
    f = treewidth_clique(4, 2); f.clauses[f.fill_start][0] = 1
    expect(wassat_treewidth_refute(f.flat, i64[32], i64[2])).to eq(0)
    f = treewidth_clique(4, 2); f.clauses[f.orientation_start][0] = 1
    expect(wassat_treewidth_refute(f.flat, i64[32], i64[2])).to eq(0)

  it "rejects repeated or foreign counter inputs" ->
    f = treewidth_clique(4, 2)
    f.clauses[f.counter_start + 1][0] = f.clauses[f.counter_start][0]
    expect(wassat_treewidth_refute(f.flat, i64[32], i64[2])).to eq(0)
    f = treewidth_clique(4, 2); f.clauses[f.counter_start][0] = -1
    expect(wassat_treewidth_refute(f.flat, i64[32], i64[2])).to eq(0)

  it "requires a complete counter bound" ->
    f = treewidth_clique(4, 2); f.clauses.pop
    expect(wassat_treewidth_refute(f.flat, i64[32], i64[2])).to eq(0)

  it "rejects malformed flat offsets and short arrays" ->
    f = treewidth_clique(4, 2).flat; f["flat_offs"][5] = f["flat_nlits"]
    expect(wassat_treewidth_refute(f, i64[32], i64[2])).to eq(0)
    expect(wassat_treewidth_refute(f, i64[2], i64[2])).to eq(0)

  it "honors cancellation and expired deadlines" ->
    f = treewidth_clique(4, 2).flat; m = i64[32]; stop = i64[2]
    z = wassat_stop_cancel(stop)
    expect(wassat_treewidth_refute(f, m, stop)).to eq(0)
    expect(m[0]).to eq(1)
    expect(m[10]).to eq(0)
    expect(wassat_treewidth_refute(f, m, i64[2], clock_ms() - 1)).to eq(0)
    expect(m[0]).to eq(2)

  it "retains interrupted and unpublished scout work for retry" ->
    f = {}; m = i64[32]; p = { "meta": m }
    m[0] = 1; wassat_treewidth_finish_scout(f, p)
    expect(f["treewidth_done"]).to eq(false)
    m[0] = 0; m[16] = -1; wassat_treewidth_finish_scout(f, p)
    expect(f["treewidth_done"]).to eq(false)
    m[16] = 0; wassat_treewidth_finish_scout(f, p)
    expect(f["treewidth_done"]).to eq(true)
