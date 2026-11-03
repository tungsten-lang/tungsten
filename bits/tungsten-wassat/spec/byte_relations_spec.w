use spec
use ../lib/wassat


-> byte_test_flat(rows, nv)
  nl = 0; rows.each -> (c) nl += c.size
  lits = i64[nl]; offs = i64[rows.size]; lens = i64[rows.size]; at = 0; ci = 0
  rows.each -> (c)
    offs[ci] = at; lens[ci] = c.size
    c.each -> (l)
      lits[at] = l; at += 1
    ci += 1
  {"nvars": nv, "flat_ncl": rows.size, "flat_nlits": nl, "flat_lits": lits, "flat_offs": offs, "flat_lens": lens}

-> byte_test_and(rows, out, xs)
  xs.each -> (x) rows.push([-out, x])
  c = xs.map -> (x) -x
  c.push(out); rows.push(c)

-> byte_test_formula(mode = "same")
  width = 3; nv = 3 * width; rows = []; which = 0
  while which < 2
    a = 0
    while a < 8
      if mode != "missing" || which != 1 || a != 5
        ins = []; outs = []; j = 0; value = (3 * a + 1) & 7
        value ^= 1 if which == 1 && mode == "different" && a == 5
        while j < width
          ins.push((a >> j) & 1 == 1 ? j + 1 : -j - 1)
          v = width + which * width + j + 1
          outs.push((value >> j) & 1 == 1 ? v : -v); j += 1
        nv += 1; eqin = nv; byte_test_and(rows, eqin, ins)
        nv += 1; eqout = nv; byte_test_and(rows, eqout, outs)
        nv += 1; byte_test_and(rows, nv, [eqin, -eqout]); rows.push([-nv])
      a += 1
    which += 1
  mismatch = []; j = 0
  while j < width
    a = width + j + 1; b = 2 * width + j + 1; nv += 1
    rows.push([a, b, -nv]); rows.push([-a, -b, -nv])
    rows.push([a, -b, nv]); rows.push([-a, b, nv]); mismatch.push(nv); j += 1
  rows.push(mode == "satisfied" ? mismatch.map(-> (x) -x) : mismatch)
  rows = rows.map(-> (c) c.reverse) if mode == "reverse"
  byte_test_flat(rows, nv)

describe "Original-clause byte relation refutation" ->
  it "refutes a mismatch between identical complete tables" ->
    m = i64[64]
    expect(wassat_byte_refute(byte_test_formula, m, i64[4])).to eq(-1)
    expect(m[18]).to eq(2)
    expect(m[23] > 0).to eq(true)

  it "accepts reversed literal order in defining clauses" ->
    expect(wassat_byte_refute(byte_test_formula("reverse"), i64[64], i64[4])).to eq(-1)

  it "leaves distinct functions unresolved" ->
    expect(wassat_byte_refute(byte_test_formula("different"), i64[64], i64[4])).to eq(0)

  it "does not infer a total function from an incomplete table" ->
    expect(wassat_byte_refute(byte_test_formula("missing"), i64[64], i64[4])).to eq(0)

  it "does not refute a satisfied residual clause" ->
    expect(wassat_byte_refute(byte_test_formula("satisfied"), i64[64], i64[4])).to eq(0)

  it "checks an original root contradiction" ->
    expect(wassat_byte_refute(byte_test_flat([[1], [-1]], 1), i64[64], i64[4])).to eq(-1)

  it "fails closed on an out-of-range literal" ->
    expect(wassat_byte_refute(byte_test_flat([[2]], 1), i64[64], i64[4])).to eq(0)

  it "fails closed on an invalid clause span" ->
    f = byte_test_formula
    f["flat_offs"][0] = f["flat_lits"].size
    expect(wassat_byte_refute(f, i64[64], i64[4])).to eq(0)

  it "uses logical literal counts in overallocated parser buffers" ->
    f = byte_test_formula
    old = f["flat_lits"]; more = i64[old.size + 200]; i = 0
    while i < old.size
      more[i] = old[i]; i += 1
    more[i] = 9999999; f["flat_lits"] = more
    expect(wassat_byte_refute(f, i64[64], i64[4])).to eq(-1)
    f["flat_nlits"] = old.size - 1
    expect(wassat_byte_refute(f, i64[64], i64[4])).to eq(0)

  it "rejects undersized control buffers before allocating scratch" ->
    f = byte_test_formula
    expect(wassat_byte_refute(f, i64[63], i64[4])).to eq(0)
    expect(wassat_byte_refute(f, i64[64], i64[1])).to eq(0)

  it "resets counters when a caller reuses metadata" ->
    m = i64[64]; f = byte_test_formula
    expect(wassat_byte_refute(f, m, i64[4])).to eq(-1)
    first = m[0]
    expect(wassat_byte_refute(f, m, i64[4])).to eq(-1)
    expect(m[0]).to eq(first)
    expect(m[18]).to eq(2)

  it "checks cancellation before allocation" ->
    stop = i64[4]; m = i64[64]; wassat_stop_cancel(stop)
    expect(wassat_byte_refute(byte_test_formula, m, stop)).to eq(0)
    expect(m[11]).to eq(1)
    expect(m[0]).to eq(0)

  it "honors an expired deadline" ->
    m = i64[64]
    expect(wassat_byte_refute(byte_test_formula, m, i64[4], clock_ms() - 1)).to eq(0)
    expect(m[11]).to eq(2)

  it "compresses long signed union-find paths iteratively" ->
    p = i64[1026]; i = 1
    while i < 1025
      p[i] = -i - 1; i += 1
    p[1025] = 1025
    expect(wassat_byte_find(p, 1)).to eq(1025)
    expect(wassat_byte_find(p, -2)).to eq(1025)
    expect(p[1]).to eq(1025)



-> expr_fixture(nv, program, inputs, groups = nil, tables = nil, ng = 0, stop = nil)
  parent = i64[nv + 2]; i = 1
  while i <= nv + 1
    parent[i] = i; i += 1
  groups = i64[80] if groups == nil
  tables = i64[256] if tables == nil
  stop = i64[4] if stop == nil
  WassatByteExpressions.new(program, inputs, parent, groups, tables, nv, ng, i64[64], stop, 0)

-> expr_gate(program, inputs, out, kind, a, b, offset, truth)
  p = 8 * out
  program[p] = kind; program[p + 1] = out; program[p + 2] = 2
  program[p + 3] = offset; program[p + 4] = truth
  inputs[offset] = a; inputs[offset + 1] = b

-> expr_reverse_byte(a) (i64) i64
  out = 0; j = 0
  while j < 8
    out |= ((a >> j) & 1) << (7 - j); j += 1
  out

describe "Byte expression normalization" ->
  it "keeps independent inputs and signed complements distinct" ->
    e = expr_fixture(3, i64[32], i64[1])
    a = e.get(1); b = e.get(2)
    expect(a == b).to eq(false)
    expect(a > 1).to eq(true)
    expect(e.get(-1)).to eq(a ^ 1)
    expect(e.failed).to eq(false)

  it "normalizes XOR association across different gate shapes" ->
    p = i64[72]; xs = i64[10]
    expr_gate(p, xs, 4, 2, 1, 2, 0, 6)
    expr_gate(p, xs, 5, 2, 4, 3, 2, 6)
    expr_gate(p, xs, 6, 2, 2, 3, 4, 6)
    expr_gate(p, xs, 7, 2, 1, 6, 6, 6)
    expr_gate(p, xs, 8, 2, 5, 7, 8, 6)
    e = expr_fixture(8, p, xs)
    expect(e.get(8)).to eq(0)
    expect(e.get(-8)).to eq(1)
    expect(e.failed).to eq(false)

  it "normalizes AND order and detects complemented operands" ->
    p = i64[56]; xs = i64[8]
    expr_gate(p, xs, 3, 1, 1, -2, 0, 0)
    expr_gate(p, xs, 4, 1, -2, 1, 2, 0)
    expr_gate(p, xs, 5, 2, 3, 4, 4, 6)
    expr_gate(p, xs, 6, 1, 1, -1, 6, 0)
    e = expr_fixture(6, p, xs)
    expect(e.get(5)).to eq(0)
    expect(e.get(6)).to eq(0)
    expect(e.failed).to eq(false)

  it "matches reordered byte inputs and composes full 256-entry functions" ->
    groups = i64[320]; tables = i64[1024]; g = 0
    while g < 4
      p = 80 * g
      groups[p] = 8; groups[p + 1] = 8; groups[p + 2] = 8; groups[p + 3] = 256
      j = 0
      while j < 8
        source = g == 1 ? 8 - j : g == 2 ? j + 9 : j + 1
        groups[p + 70 + j] = source; groups[p + 38 + j] = 9 + 8 * g + j
        j += 1
      a = 0
      while a < 256
        x = g == 1 ? expr_reverse_byte(a) : a
        val = (x * x + 17) & 255
        val = x ^ 165 if g == 2
        val ^= 165 if g == 3
        tables[256 * g + a] = val; a += 1
      g += 1
    e = expr_fixture(40, i64[328], i64[1], groups, tables, 4)
    j = 0
    while j < 8
      expect(e.get(9 + j)).to eq(e.get(17 + j))
      expect(e.get(25 + j)).to eq(e.get(33 + j))
      j += 1
    expect(e.failed).to eq(false)

  it "rejects dependency cycles" ->
    p = i64[32]; xs = i64[4]
    expr_gate(p, xs, 2, 1, 3, 1, 0, 0)
    expr_gate(p, xs, 3, 1, 2, 1, 2, 0)
    e = expr_fixture(3, p, xs)
    e.get(2)
    expect(e.failed).to eq(true)
    expect(e.cycles > 0).to eq(true)

  it "rejects a dependency chain beyond the recursion bound" ->
    p = i64[8 * 520]; xs = i64[2 * 517]; v = 3
    while v < 520
      expr_gate(p, xs, v, 2, v - 1, 1, 2 * (v - 3), 6); v += 1
    e = expr_fixture(519, p, xs)
    e.get(519)
    expect(e.failed).to eq(true)

  it "fails closed when the expression allocation budget is exhausted" ->
    e = expr_fixture(3, i64[32], i64[1])
    expect(e.charge(67108865)).to eq(false)
    expect(e.get(1)).to eq(0)
    expect(e.failed).to eq(true)

  it "honors cancellation before evaluating an expression" ->
    stop = i64[4]; wassat_stop_cancel(stop)
    e = expr_fixture(3, i64[32], i64[1], nil, nil, 0, stop)
    e.get(1)
    expect(e.failed).to eq(true)



-> byte_oracle_fixture(nonlinear = false)
  rows = []; j = 0
  while j < 8
    a = j + 1; b = ((j + 1) % 8) + 1; y = 9 + j
    if nonlinear && j == 0
      rows.push([-y, a]); rows.push([-y, b]); rows.push([y, -a, -b])
    else
      rows.push([a, b, -y]); rows.push([-a, -b, -y])
      rows.push([a, -b, y]); rows.push([-a, b, y])
    j += 1
  n = 0; rows.each -> (c) n += c.size + 1
  flat = i64[n]; local = i64[11]; local[0] = 16; local[1] = rows.size; local[2] = n
  at = 0
  rows.each -> (c)
    c.each -> (x)
      flat[at] = x; at += 1
    at += 1
  j = 0
  while j < 8
    local[3 + j] = 9 + j; j += 1
  [flat, local]

describe "Universal byte relation proof" ->
  it "proves a sampled affine function before accepting it" ->
    f = byte_oracle_fixture; m = i64[64]
    images = wassat_byte_linear_oracle(f[0], f[1], i64[4], 0, m)
    expect(images == nil).to eq(false)
    expect(images[0]).to eq(0)
    expect(images[1]).to eq(129)
    expect(m[21]).to eq(9)
    expect(m[22]).to eq(1)

  it "rejects a nonlinear relation that agrees at the basis points" ->
    f = byte_oracle_fixture(true); m = i64[64]
    expect(wassat_byte_linear_oracle(f[0], f[1], i64[4], 0, m)).to eq(nil)
    expect(m[21]).to eq(9)
    expect(m[22]).to eq(0)

  it "stops before a cancelled local proof" ->
    f = byte_oracle_fixture; stop = i64[4]; wassat_stop_cancel(stop)
    expect(wassat_byte_linear_oracle(f[0], f[1], stop, 0, i64[64])).to eq(nil)


spec_summary
