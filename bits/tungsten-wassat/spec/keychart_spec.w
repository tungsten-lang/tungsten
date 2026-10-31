use spec
use keychart_fixture

describe "Input-derived keychart recognition and kernels" ->
  it "infers domains and shared supports without instance metadata" ->
    f = keychart_test_formula([])
    p = wassat_keychart_plan(f)
    expect(p != nil).to eq(true)
    expect(p["meta"].to_s).to eq([4, 2, 2, 32, 48].to_s)
    expect(p["allowed"][0]).to eq(1)
    expect(p["allowed"][2]).to eq(0)
    expect(p["wkey"][49]).to eq(17)
    expect(p["wlock"][49]).to eq(33)

  it "does no search or repair after cancellation" ->
    f = keychart_test_formula([])
    p = wassat_keychart_plan(f)
    stop = i64[4]
    z = wassat_stop_cancel(stop)
    expect(keychart_test_search(f, p, stop).empty?).to eq(true)
    expect(p["state"][1]).to eq(0)
    expect(p["state"][10]).to eq(0)

  it "rejects inconsistent OR supports and ambiguous witness pairs" ->
    f = keychart_test_formula([[-33, 1, 9]])
    expect(wassat_keychart_plan(f)).to eq(nil)
    f = keychart_test_formula([[-49, 17]])
    expect(wassat_keychart_plan(f)).to eq(nil)
    f = keychart_test_formula([[-33, 1, 8]])
    expect(wassat_keychart_plan(f)).to eq(nil)

  it "bounds recognition and rejects unrelated leading clauses" ->
    f = keychart_test_formula([])
    f["nvars"] = 50001
    expect(wassat_keychart_plan(f)).to eq(nil)
    f = keychart_test_formula([])
    f["flat_lits"][0] = -1
    expect(wassat_keychart_plan(f)).to eq(nil)
    expect(wassat_keychart_plan(nil)).to eq(nil)

  it "checks cancellation inside the allocation-free move kernel" ->
    f = keychart_test_formula([])
    p = wassat_keychart_plan(f)
    st = p["state"]
    wassat_keychart_seed(p["allowed"], p["value"], p["count"], p["other"], p["dist"], p["weight"], p["gain"], st, 4, 2, 2)
    st[8] = -1
    stop = i64[4]
    z = wassat_stop_cancel(stop)
    wassat_keychart_walk(p["allowed"], p["value"], p["count"], p["other"], p["dist"], p["weight"], p["gain"], st, 4, 2, 2, 4, 1, 100, stop)
    expect(st[9]).to eq(1)
    expect(st[1]).to eq(0)

  it "matches every finite-domain move delta to a full score rebuild" ->
    f = keychart_test_formula([])
    p = wassat_keychart_plan(f)
    st = p["state"]
    a = p["allowed"]
    v = p["value"]
    c = p["count"]
    o = p["other"]
    d = p["dist"]
    w = p["weight"]
    g = p["gain"]
    wassat_keychart_seed(a, v, c, o, d, w, g, st, 4, 2, 2)
    i = 0
    while i < 8
      w[i] = i + 1
      i += 1
    wassat_keychart_rebuild(a, v, c, o, d, w, g, st, 4, 2, 2, 4)
    k = 0
    while k < 4
      pos = 0
      while pos < 2
        old = v[k * 2 + pos]
        cand = 0
        while cand < 4
          if cand != old
            before = st[3]
            delta = wassat_keychart_delta(a, v, c, o, d, w, g, 4, 2, 2, 4, k, pos, cand)
            v[k * 2 + pos] = cand
            wassat_keychart_rebuild(a, v, c, o, d, w, g, st, 4, 2, 2, 4)
            expect(st[3]).to eq(before + delta)
            v[k * 2 + pos] = old
            wassat_keychart_rebuild(a, v, c, o, d, w, g, st, 4, 2, 2, 4)
          cand += 1
        pos += 1
      k += 1
