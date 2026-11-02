use spec
use ../lib/wassat

-> lut_test_gate(rows, out, inputs, table)
  a = 0
  while a < (1 << inputs.size)
    c = []
    i = 0
    while i < inputs.size
      c.push(((a >> i) & 1) == 1 ? 0 - inputs[i] : inputs[i])
      i += 1
    c.push(((table >> a) & 1) == 1 ? out : 0 - out)
    rows.push(c)
    a += 1

-> lut_test_flat(rows, nv)
  n = 0
  rows.each -> (c) n += c.size
  lits = i64[n]; offs = i64[rows.size]; lens = i64[rows.size]
  at = 0; ci = 0
  rows.each -> (c)
    offs[ci] = at; lens[ci] = c.size
    c.each -> (l)
      lits[at] = l; at += 1
    ci += 1
  { "nvars": nv, "flat_ncl": rows.size, "flat_nlits": n,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens }

-> lut_test_fixture(mode = "")
  rows = []
  lut_test_gate(rows, 3, [5, 6], 6)
  lut_test_gate(rows, 4, [1, 2], 7)
  lut_test_gate(rows, 5, [4], 1)
  lut_test_gate(rows, 6, [1, 2], mode == "different" ? 14 : 8)
  rows.push(mode == "satisfied" ? [-3] : [3])
  rows[5] = [4] if mode == "corrupt"
  if mode == "reverse"
    rows = rows.map -> (c) c.reverse
  lut_test_flat(rows, 6)

-> lut_test_result(f)
  m = i64[16]
  status = wassat_lut_refute(f, m, i64[4])
  [status, m]

describe "Checked small-function congruence" ->
  it "refutes differing outputs after complement and function merging" ->
    r = lut_test_result(lut_test_fixture)
    expect(r[0]).to eq(-1)
    expect(r[1][1]).to eq(4)
    expect(r[1][5]).to eq(4)
    expect(r[1][4]).to eq(1)
    expect(r[1][9]).to eq(1)

  it "accepts either literal order inside a gate clause" ->
    expect(lut_test_result(lut_test_fixture("reverse"))[0]).to eq(-1)

  it "does not refute distinct Boolean functions" ->
    expect(lut_test_result(lut_test_fixture("different"))[0]).to eq(0)

  it "does not turn a satisfied assertion into UNSAT" ->
    expect(lut_test_result(lut_test_fixture("satisfied"))[0]).to eq(0)

  it "declines an incomplete or inconsistent definition" ->
    expect(lut_test_result(lut_test_fixture("corrupt"))[0]).to eq(0)

  it "declines cyclic dependencies" ->
    rows = []
    lut_test_gate(rows, 1, [2], 2)
    lut_test_gate(rows, 2, [1], 2)
    rows.push([1]); rows.push([-1])
    r = lut_test_result(lut_test_flat(rows, 2))
    expect(r[0]).to eq(0)
    expect(r[1][5]).to eq(0)

  it "checks constant gates before a contradictory assertion" ->
    expect(lut_test_result(lut_test_flat([[1], [2], [-1, -2]], 2))[0]).to eq(-1)

  it "cancels without publishing a result" ->
    stop = i64[4]; m = i64[16]; res = i64[14]
    wassat_stop_cancel(stop)
    expect(wassat_lut_run(lut_test_fixture, m, stop, res)).to eq(0)
    expect(res[0]).to eq(0)
    expect(m[11]).to eq(1)

  it "honors an already expired deadline" ->
    m = i64[16]
    expect(wassat_lut_refute(lut_test_fixture, m, i64[4], clock_ms() - 1)).to eq(0)
    expect(m[11]).to eq(2)

  it "enforces the bounded truth-table work allowance" ->
    m = i64[16]; m[7] = 64000001
    expect(wassat_lut_stop(m, i64[4], 0)).to eq(3)

spec_summary
