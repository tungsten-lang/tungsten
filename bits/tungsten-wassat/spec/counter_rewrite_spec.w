use spec
use ../lib/counter_rewrite

-> wassat_counter_test_fixture(mode = "")
  rows = [[1, -1], [2, -2], [3, -3], [4, -4],
    [-6, 5], [-1, 5], [-2, 5], [-5, 1, 2], [-2, -1, 6], [-6, 1], [-6, 2],
    [-8, 7], [-3, 7], [-4, 7], [-7, 3, 4], [-4, -3, 8], [-8, 3], [-8, 4],
    [-10, 9], [-5, 9], [-7, 9], [-9, 5, 7],
    [-6, 11], [-7, -5, 11], [-11, 5], [-11, 6, 7], [-7, -6],
    [-11, 10], [-8, 10], [-10, 11, 8], [-8, -11], [10]]
  rows[30] = [-8, 11] if mode == "overflow"
  rows[24] = [-11, 1] if mode == "cross"
  rows[17] = [-8, 1] if mode == "incomplete"
  rows[31] = [9] if mode == "root"
  words = 0
  rows.each -> (c) words += c.size
  l = i64[words]; o = i64[rows.size]; n = i64[rows.size]
  at = 0; ci = 0
  rows.each -> (c)
    o[ci] = at; n[ci] = c.size
    c.each -> (x)
      l[at] = x; at += 1
    ci += 1
  { "l": l, "o": o, "n": n, "nc": rows.size }

-> wassat_counter_test_result(mode = "", cancel = false, expired = false)
  f = wassat_counter_test_fixture(mode)
  l = f["l"]; o = f["o"]; n = f["n"]; nc = f["nc"]
  m = i64[32]; stop = i64[4]
  wassat_stop_cancel(stop) if cancel
  m[7] = clock_ms() - 1 if expired
  found = wassat_counter_find(l, o, n, 11, nc, m, stop)
  return [0, m] if found == 0
  nodes = i64[128]; gates = i64[64]; owner = i32[12]; index = i32[12]; defined = i8[12]; used = i8[12]
  parsed = wassat_counter_parse(l, o, n, 11, nc, nodes, gates, owner, index, defined, used, m, stop)
  return [0, m] if parsed == 0
  checked = wassat_counter_verify(l, o, n, nodes, gates, index, i64[12], m, stop)
  [checked, m]

describe "Checked closed unary counter rewriting" ->
  it "checks every local unary sum and overflow relation" ->
    r = wassat_counter_test_result
    expect(r[0]).to eq(1)
    expect(r[1][0]).to eq(4)
    expect(r[1][1]).to eq(5)
    expect(r[1][2]).to eq(3)
    expect(r[1][3]).to eq(7)
    expect(r[1][4]).to eq(4)
    expect(r[1][5]).to eq(2)
    expect(r[1][10]).to eq(17)

  it "rejects a corrupted overflow even when gate parsing succeeds" ->
    expect(wassat_counter_test_result("overflow")[0]).to eq(0)

  it "rejects cross-node dependencies" ->
    expect(wassat_counter_test_result("cross")[0]).to eq(0)

  it "rejects incomplete gate definitions" ->
    expect(wassat_counter_test_result("incomplete")[0]).to eq(0)

  it "requires the final exact count assertion" ->
    expect(wassat_counter_test_result("root")[0]).to eq(0)

  it "stops before parsing after cancellation" ->
    r = wassat_counter_test_result("", true)
    expect(r[0]).to eq(0)
    expect(r[1][6]).to eq(1)

  it "stops at an expired deadline" ->
    r = wassat_counter_test_result("", false, true)
    expect(r[0]).to eq(0)
    expect(r[1][6]).to eq(2)

  it "does not write past exhausted output buffers" ->
    m = i64[32]; l = i64[2]; o = i64[1]; n = i64[1]
    expect(wassat_counter_emit(l, o, n, 1, 2, 3, m)).to eq(0)
    expect(m[6]).to eq(3)
    expect(l[0]).to eq(0)

  it "encodes exactly two of four under all Boolean assignments" ->
    inputs = i64[4]
    i = 0
    while i < 4
      inputs[i] = i + 1; i += 1
    l = i64[512]; o = i64[128]; n = i64[128]; m = i64[32]
    m[20] = 4; m[23] = 20
    root = wassat_counter_build(inputs, 0, 4, 2, l, o, n, m, i64[4])
    expect(root).to eq(9)
    expect(wassat_counter_emit(l, o, n, root + 1, 0, 0, m)).to eq(1)
    solutions = i64[16]
    bits = 0
    while bits < 1024
      ok = true
      ci = 0
      while ci < m[21] && ok
        sat = false; j = 0
        while j < n[ci]
          lit = l[o[ci] + j]
          truth = ((bits >> (wassat_counter_abs(lit) - 1)) & 1) != 0
          sat = true if truth == (lit > 0)
          j += 1
        ok = sat; ci += 1
      solutions[bits & 15] += 1 if ok
      bits += 1
    bits = 0
    while bits < 16
      count = 0; j = 0
      while j < 4
        count += (bits >> j) & 1; j += 1
      expect(solutions[bits]).to eq(count == 2 ? 1 : 0)
      bits += 1

# These functions are imported by the focused integration fixture below as
# well as by standalone solver callers; the fixed work bound is deterministic.
describe "Counter rewrite resource limits" ->
  it "rejects an exhausted local-check allowance" ->
    m = i64[32]; m[9] = 64000000
    expect(wassat_counter_poll(m, i64[4])).to eq(4)


describe "Counter grouping complexity" ->
  it "propagates regular-ancestor coverage in a single reverse pass" ->
    count = 8192
    nodes = i64[16 * count]; used = i8[65]; inputs = i64[64]; groups = i64[256]; m = i64[32]
    m[1] = 65; m[2] = count; m[4] = 64
    i = 0
    while i < count
      p = i * 16
      nodes[p + 9] = 64; nodes[p + 10] = 1; nodes[p + 11] = 64; nodes[p + 12] = 1
      nodes[p + 13] = i + 1 < count ? i + 2 : 0
      nodes[p + 14] = 1
      i += 1
    i = 1
    while i <= 64
      used[i] = 1; i += 1
    # One root group is intentionally unsupported, but the scan stays linear.
    expect(wassat_counter_group(nodes, used, groups, inputs, m, i64[4])).to eq(0)
    expect(m[18]).to eq(count + 64)

spec_summary
