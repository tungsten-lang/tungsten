use spec
use reconfiguration_support

describe "Wassat bounded graph reconfiguration" ->
  it "finds a path and verifies every original clause" ->
    rows = rc_rows(8, [0, 2], [1, 3])
    r = rc_solve(8, rows)
    expect(r["hit"]).to eq(1)
    expect(r["meta"][3]).to eq(8)
    expect(r["meta"][4]).to eq(2)
    expect(r["meta"][15]).to eq(rows.size)
    expect(r["meta"][23]).to eq(0)
    expect(rc_replay(rows, r["result"])).to eq(true)

  it "handles the high bit of a packed word" ->
    rows = rc_rows(64, [0, 62], [1, 63])
    r = rc_solve(64, rows)
    expect(r["hit"]).to eq(1)
    expect(rc_replay(rows, r["result"])).to eq(true)

  it "handles paths crossing a packed word boundary" ->
    rows = rc_rows(70, [0, 63], [1, 64])
    r = rc_solve(70, rows)
    expect(r["hit"]).to eq(1)
    expect(rc_replay(rows, r["result"])).to eq(true)

  it "falls through when the shortest path is too short for the encoding" ->
    r = rc_solve(8, rc_rows(8, [0, 2], [1, 3], 3), 3)
    expect(r["hit"]).to eq(0)
    expect(r["meta"][1]).to eq(1)
    expect(r["meta"][0]).to eq(0)

  it "never refutes when the token graph has no path" ->
    r = rc_solve(4, rc_rows(4, [0, 2], [1, 3]))
    expect(r["hit"]).to eq(0)
    expect(r["meta"][0]).to eq(0)

  it "rejects contradictory original units" ->
    rows = rc_rows(8, [0, 2], [1, 3]); rows.push([1]); rows.push([-1])
    expect(rc_solve(8, rows)["hit"]).to eq(0)

  it "rejects an original empty clause" ->
    rows = rc_rows(8, [0, 2], [1, 3]); rows.push([])
    expect(rc_solve(8, rows)["hit"]).to eq(0)

  it "does not publish a path that violates an extra original clause" ->
    rows = rc_rows(8, [0, 2], [1, 3]); rows.push([-4])
    r = rc_solve(8, rows)
    expect(r["hit"]).to eq(0)
    expect(r["meta"][0]).to eq(0)

  it "rejects self-loop graph prefixes" ->
    rows = rc_rows(8, [0, 2], [1, 3]); rows[0] = [-1, -1]
    expect(rc_solve(8, rows)["hit"]).to eq(0)

  it "rejects an inconsistent repeated graph" ->
    rows = rc_rows(8, [0, 2], [1, 3]); rows[1] = [-2, -4]
    r = rc_solve(8, rows)
    expect(r["hit"]).to eq(0)
    expect(r["meta"][1]).to eq(0)

  it "rejects a goal with a different number of tokens" ->
    expect(rc_solve(8, rc_rows(8, [0, 2], [1]))["hit"]).to eq(0)

  it "rejects a non-independent final state" ->
    expect(rc_solve(8, rc_rows(8, [0, 2], [0, 1]))["hit"]).to eq(0)

  it "honors cancellation before recognition and allocation of search buffers" ->
    r = rc_solve(8, rc_rows(8, [0, 2], [1, 3]), 2, true)
    expect(r["hit"]).to eq(0)
    expect(r["meta"][2]).to eq(1)
    expect(r["meta"][8]).to eq(0)

  it "bounds the visited-state table without inferring UNSAT" ->
    initial = i64[1]; goal = i64[1]; adj = i64[8]
    initial[0] = 5
    goal[0] = 10
    v = 0
    while v < 8
      adj[v] = (1 << ((v + 1) % 8)) | (1 << ((v + 7) % 8))
      v += 1
    states = i64[2]; parents = i64[2]; m = i64[24]; stop = i64[4]
    hit = wassat_reconf_search(initial, goal, adj, states, parents, 8, 2, 2, m, stop, 0)
    expect(hit).to eq(-1)
    expect(m[2]).to eq(3)
    expect(m[8] <= 2).to eq(true)

  it "rejects unsafe search buffer dimensions" ->
    initial = i64[1]; goal = i64[1]; adj = i64[8]
    expect(wassat_reconf_search(initial, goal, adj, i64[1], i64[1], 8, 2, 2, i64[24], i64[4], 0)).to eq(-1)

spec_summary
