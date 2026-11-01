use spec
use ../lib/resolution_cover

-> binary_candidate(nv, clauses, initial = [], stop = nil, deadline = 0)
  size = 0
  clauses.each -> (c) size += c.size
  lits = i64[size]; offs = i64[clauses.size]; lens = i64[clauses.size]
  at = 0; ci = 0
  clauses.each -> (c)
    offs[ci] = at; lens[ci] = c.size
    c.each -> (l)
      lits[at] = l; at += 1
    ci += 1
  values = i8[nv + 1]
  initial.each -> (l) values[l.abs] = l > 0 ? 1 : -1
  m = i64[20]
  stop = i64[4] if stop == nil
  r = wassat_cover_binary_model(lits, offs, lens, nv, ci, values, i32[2 * nv + 2], m, stop, deadline)
  if r == 1
    clauses.each -> (c)
      expect(c.any? -> (l) values[l.abs] == (l > 0 ? 1 : -1)).to eq(true)
  {"status": r, "values": values, "meta": m}

describe "Residual binary model completion" ->
  it "satisfies unit implications and replays original clauses" ->
    r = binary_candidate(3, [[1], [-1, 2], [-2, 3]])
    expect(r["status"]).to eq(1)
    expect(r["values"][3]).to eq(1)
    expect(r["meta"][17]).to eq(3)
    expect(r["meta"][18]).to eq(1)

  it "handles nontrivial SCCs and disconnected components" ->
    r = binary_candidate(7, [[-1, 2], [-2, 1], [1, 2], [3, 4], [-3, -4], [5]])
    expect(r["status"]).to eq(1)
    expect(r["values"][7]).to eq(-1)

  it "declines contradictory units without publishing UNSAT" ->
    r = binary_candidate(1, [[1], [-1]])
    expect(r["status"]).to eq(0)
    expect(r["meta"][18]).to eq(0)

  it "declines an inconsistent binary SCC" ->
    expect(binary_candidate(2, [[1, 2], [-1, 2], [1, -2], [-1, -2]])["status"]).to eq(0)

  it "declines empty and unsupported wide residual clauses" ->
    expect(binary_candidate(2, [[]])["status"]).to eq(0)
    expect(binary_candidate(3, [[1, 2, 3]])["status"]).to eq(0)

  it "retains satisfied wide clauses in final replay" ->
    r = binary_candidate(5, [[1, 2, 3, 4], [-1, 4, 5], [-4]], [1])
    expect(r["status"]).to eq(1)
    expect(r["values"][1]).to eq(1)
    expect(r["values"][5]).to eq(1)

  it "collapses repeated literals and skips residual tautologies" ->
    expect(binary_candidate(4, [[-1, -1, -1], [1, -1, 2, 3], [2, 2, 3]])["status"]).to eq(1)

  it "completes empty graphs and already satisfied formulas" ->
    expect(binary_candidate(2, [])["status"]).to eq(1)
    expect(binary_candidate(2, [[1, 2]], [1])["status"]).to eq(1)

  it "does not claim a model when fixed values falsify a clause" ->
    expect(binary_candidate(2, [[1, 2]], [-1, -2])["status"]).to eq(0)

  it "obeys cancellation and deadlines" ->
    stop = i64[4]
    wassat_stop_cancel(stop)
    r = binary_candidate(2, [[1, 2]], [], stop)
    expect(r["status"]).to eq(0)
    expect(r["meta"][8]).to eq(1)
    r = binary_candidate(2, [[1, 2]], [], nil, clock_ms() - 1)
    expect(r["status"]).to eq(0)
    expect(r["meta"][8]).to eq(2)

spec_summary
