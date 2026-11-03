use spec
use ../lib/wassat

-> cycle_repair_fixture(n, pairs)
  ne = pairs.size
  left = i32[ne]; right = i32[ne]; heads = i32[n + 1]
  occ = i32[2 * ne]; fill = i32[n]; perm = i32[n]
  e = 0
  while e < ne
    a = pairs[e][0]; b = pairs[e][1]
    left[e] = a; right[e] = b
    heads[a + 1] += 1; heads[b + 1] += 1
    e += 1
  v = 1
  while v <= n
    heads[v] += heads[v - 1]
    perm[v - 1] = v - 1
    v += 1
  e = 0
  while e < ne
    a = left[e]; b = right[e]
    occ[heads[a] + fill[a]] = e; fill[a] += 1
    occ[heads[b] + fill[b]] = e; fill[b] += 1
    e += 1
  { "n": n, "ne": ne, "left": left, "right": right, "heads": heads, "occ": occ, "perm": perm }

-> cycle_repair_run(f, width, m, stop, deadline = 0)
  wassat_cycle_repair(f["n"], f["ne"], width, f["left"], f["right"], f["heads"], f["occ"], f["perm"], m, stop, deadline)

describe "Bounded circular graph repairs" ->
  it "builds the exact permutation domains and sequential AMO constraints" ->
    f = cycle_repair_fixture(6, [[0, 1], [2, 3], [4, 5]])
    m = i64[24]
    plan = wassat_cycle_repair_build(6, 3, 2, f["left"], f["right"], f["heads"], f["occ"], f["perm"], m, i64[4], 0)
    expect(plan != nil).to eq(true)
    expect(m[1]).to eq(6)
    expect(m[2]).to eq(36)
    expect(m[3]).to eq(96)
    expect(m[4]).to eq(234)
    expect(m[5]).to eq(516)
    expect(plan["formula"]["flat_lits"].size).to eq(516)
    expect(plan["formula"]["flat_offs"].size).to eq(234)

  it "returns a checked bijection and never changes the shared winner cell" ->
    f = cycle_repair_fixture(6, [[0, 1], [2, 3], [4, 5]])
    m = i64[24]; stop = i64[4]
    expect(cycle_repair_run(f, 2, m, stop)).to eq(1)
    seen = i8[6]
    p = f["perm"]
    v = 0
    while v < 6
      expect(seen[p[v]]).to eq(0)
      seen[p[v]] = 1
      v += 1
    expect(wassat_cycle_cost(p[0], p[1], 2, 6)).to eq(0)
    expect(wassat_cycle_cost(p[2], p[3], 2, 6)).to eq(0)
    expect(wassat_cycle_cost(p[4], p[5], 2, 6)).to eq(0)
    expect(m[7]).to eq(1)
    expect(m[15]).to eq(3)
    expect(wassat_stop_status(stop)).to eq(0)

  it "treats a restricted refutation as a miss and preserves the input permutation" ->
    f = cycle_repair_fixture(6, [[0, 1], [0, 2], [1, 2]])
    m = i64[24]; stop = i64[4]
    expect(cycle_repair_run(f, 3, m, stop)).to eq(0)
    expect(m[17]).to eq(-1)
    expect(m[7]).to eq(0)
    expect(wassat_stop_status(stop)).to eq(0)
    v = 0
    while v < 6
      expect(f["perm"][v]).to eq(v)
      v += 1

  it "declines invalid permutations, CSR spans, and an excessive damaged set" ->
    f = cycle_repair_fixture(6, [[0, 1]])
    f["perm"][5] = 0
    expect(cycle_repair_run(f, 2, i64[24], i64[4])).to eq(0)
    f["perm"][5] = 5
    f["heads"][6] = 1
    expect(cycle_repair_run(f, 2, i64[24], i64[4])).to eq(0)
    edges = []
    v = 0
    while v < 34
      edges.push([v, v + 1])
      v += 2
    f = cycle_repair_fixture(40, edges)
    expect(cycle_repair_run(f, 2, i64[24], i64[4])).to eq(0)

  it "honors cancellation and expired deadlines before constructing a solver" ->
    f = cycle_repair_fixture(6, [[0, 1]])
    stop = i64[4]; m = i64[24]
    wassat_stop_cancel(stop)
    expect(cycle_repair_run(f, 2, m, stop)).to eq(0)
    expect(m[0]).to eq(0)
    expect(m[22]).to eq(1)
    m = i64[24]
    expect(cycle_repair_run(f, 2, m, i64[4], clock_ms() - 1)).to eq(0)
    expect(m[0]).to eq(0)
    expect(m[22]).to eq(2)

  it "reserves both fixed-cap solvers and input buffers under the published envelope" ->
    shape = { "nvars": 27648, "flat_ncl": WASSAT_CYCLE_REPAIR_CLAUSES, "flat_nlits": WASSAT_CYCLE_REPAIR_LITERALS }
    bytes = wassat_cdcl_arena_bytes(shape) + 8 * (shape["flat_nlits"] + 2 * shape["flat_ncl"]) + 4194304
    expect(bytes <= WASSAT_CYCLE_REPAIR_BYTES).to eq(true)
    expect(wassat_cycle_repair_peak_bytes(1024) >= 2 * bytes + 4096).to eq(true)

spec_summary
