use spec
use ../lib/wassat

-> cycle_order_graph(n, edges, width, m, stats, stop, deadline = 0)
  ne = edges.size / 2
  left = i32[ne]; right = i32[ne]; heads = i32[n + 1]
  matrix = i8[n * n]; perm = i32[n]
  e = 0
  while e < ne
    a = edges[e * 2]; b = edges[e * 2 + 1]
    left[e] = a; right[e] = b
    heads[a + 1] += 1; heads[b + 1] += 1
    lo = a < b ? a : b; hi = a < b ? b : a
    matrix[lo * n + hi] = 1
    e += 1
  v = 1
  while v <= n
    heads[v] += heads[v - 1]
    v += 1
  hit = wassat_cycle_order(n, ne, width, left, right, heads, matrix, perm, m, stats, stop, deadline)
  if hit == 1
    seen = i8[n]
    v = 0
    while v < n
      expect(perm[v] >= 0 && perm[v] < n).to eq(true)
      expect(seen[perm[v]]).to eq(0)
      seen[perm[v]] = 1
      v += 1
    e = 0
    while e < ne
      delta = perm[left[e]] - perm[right[e]]
      delta = -delta if delta < 0
      delta = n - delta if delta > n - delta
      expect(delta >= width).to eq(true)
      e += 1
  hit

describe "Bipartite circular ordering" ->
  it "constructs and independently checks a path ordering" ->
    m = i64[24]; stats = i64[8]
    expect(cycle_order_graph(8, [0,1,1,2,2,3,3,4,4,5,5,6,6,7], 3, m, stats, i64[4])).to eq(1)
    expect(stats[0]).to eq(1)
    expect(stats[1]).to eq(1)
    expect(stats[4]).to eq(7)
    expect(stats[5]).to eq(4)
    expect(stats[6]).to eq(4)

  it "includes disconnected and isolated vertices in the permutation" ->
    expect(cycle_order_graph(8, [0,1,2,3], 2, i64[24], i64[8], i64[4])).to eq(1)

  it "rejects odd cycles without declaring the SAT formula unsatisfiable" ->
    stop = i64[4]; stats = i64[8]
    expect(cycle_order_graph(6, [0,1,1,2,2,0], 1, i64[24], stats, stop)).to eq(0)
    expect(stats[0]).to eq(0)
    expect(wassat_stop_status(stop)).to eq(0)

  it "bounds unsuccessful ordering attempts" ->
    stats = i64[8]; stop = i64[4]
    expect(cycle_order_graph(6, [0,1,0,2,0,3,0,4,0,5], 2, i64[24], stats, stop)).to eq(0)
    expect(stats[1]).to eq(6)
    expect(stats[0]).to eq(0)
    expect(wassat_stop_status(stop)).to eq(0)

  it "stops before allocating traversal buffers on cancellation or deadline" ->
    m = i64[24]; stats = i64[8]; stop = i64[4]
    wassat_stop_cancel(stop)
    expect(cycle_order_graph(6, [0,1], 1, m, stats, stop)).to eq(0)
    expect(stats[1]).to eq(0)
    expect(stats[7]).to eq(1)
    expect(cycle_order_graph(6, [0,1], 1, i64[24], stats, i64[4], clock_ms() - 1)).to eq(0)
    expect(stats[7]).to eq(2)

spec_summary
