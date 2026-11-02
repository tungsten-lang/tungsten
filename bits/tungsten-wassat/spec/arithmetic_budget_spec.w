use spec
use ../lib/wassat

-> budget_fixture
  lits = i64[9]
  offs = i64[3]
  lens = i64[3]
  i = 0
  while i < 3
    offs[i] = 3 * i
    lens[i] = 3
    j = 0
    while j < 3
      lits[3 * i + j] = i == 2 ? 0 - (j + 1) : j + 1
      j += 1
    i += 1
  { "nvars": 3, "flat_ncl": 3, "flat_nlits": 9,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens }

describe "Arithmetic specialist resource limits" ->
  it "returns unknown before preparation when its deadline is expired" ->
    r = wassat_arith_coloring_solve(budget_fixture(), 100, clock_ms() - 1)
    expect(r["status"]).to eq(0)
    expect(r["recognized"]).to eq(false)
    expect(r["model"].size).to eq(0)
    expect(r["work"][3]).to eq(2)
    expect(r["work"][1]).to eq(0)

  it "keeps exhaustion of a node budget distinct from a refutation" ->
    r = wassat_arith_coloring_solve(budget_fixture(), 0, 0)
    expect(r["recognized"]).to eq(true)
    expect(r["status"]).to eq(0)
    expect(r["work"][1]).to eq(1)
    expect(r["work"][3]).to eq(1)

  it "unwinds a propagated seed when a queue safe point observes expiry" ->
    assign = i8[2]
    assign[0] = -1
    assign[1] = -1
    offs = i64[2]
    offs[1] = 2
    elems = i64[2]
    elems[1] = 1
    forbid = i8[1]
    inc_off = i64[3]
    inc_off[1] = 1
    inc_off[2] = 2
    inc = i64[2]
    order = i64[2]
    order[1] = 1
    trail = i64[3]
    queue = i64[4]
    stamp = i64[1]
    meta = i64[15]
    meta[1] = 1
    meta[2] = 100
    meta[6] = 32767
    meta[10] = clock_ms() - 1
    status = wassat_arith_dfs(assign, offs, elems, forbid, inc_off, inc,
      order, trail, queue, stamp, meta, 2, 1)
    expect(status).to eq(0)
    expect(meta[3]).to eq(2)
    expect(meta[0]).to eq(0)
    expect(meta[6]).to eq(32768)
    expect(assign[0]).to eq(-1)
    expect(assign[1]).to eq(-1)

  it "checks expiry at the first recursive node even without propagation" ->
    assign = i8[1]
    offs = i64[1]
    elems = i64[1]
    forbid = i8[1]
    inc_off = i64[2]
    inc = i64[1]
    order = i64[1]
    trail = i64[2]
    queue = i64[2]
    stamp = i64[1]
    meta = i64[15]
    meta[2] = 100
    meta[10] = clock_ms() - 1
    status = wassat_arith_dfs(assign, offs, elems, forbid, inc_off, inc,
      order, trail, queue, stamp, meta, 1, 0)
    expect(status).to eq(0)
    expect(meta[3]).to eq(2)

spec_summary
