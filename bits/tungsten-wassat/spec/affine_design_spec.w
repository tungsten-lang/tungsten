use spec
use ../lib/wassat

-> wassat_affine_design_test_flat(rows, nv)
  nl = 0; rows.each -> (c) nl += c.size
  lits = i64[nl]; offs = i64[rows.size]; lens = i64[rows.size]; ci = 0; at = 0
  rows.each -> (c)
    offs[ci] = at; lens[ci] = c.size
    c.each -> (x)
      lits[at] = x; at += 1
    ci += 1
  {"nvars": nv, "flat_ncl": rows.size, "flat_nlits": nl, "flat_lits": lits, "flat_offs": offs, "flat_lens": lens}

# Independent direct encoding of the necessary scheduling constraints. No
# original benchmark data, variable IDs, or stored answer is used.
-> wassat_affine_design_test_formula(q, mode = "base")
  n = q * q; nv = 3 * q * n; rows = []; flags = i64[q * n * n]; r = 0
  while r < q
    p = 0
    while p < n
      t = p + 1
      while t <= n
        link = t == n
        if !link || r < q - 1
          a = 1 + 3 * (r * n + p); b = link ? 1 + 3 * ((r + 1) * n + p) : 1 + 3 * (r * n + t)
          nv += 1; e = nv; flags[r * n * n + p * n + t] = e unless link
          code = mode == "verify" ? 8 : 0
          while code < 8
            row = []; i = 0
            while i < 3
              row.push(((code >> i) & 1) == 1 ? -a - i : a + i)
              row.push(((code >> i) & 1) == 1 ? -b - i : b + i); i += 1
            row.push(e)
            rows.push(row) unless mode == "missing" && r == 0 && p == 0 && t == q && code == 0
            code += 1
        t += 1
      code = q
      while code < 8
        row = []; i = 0; a = 1 + 3 * (r * n + p)
        while i < 3
          row.push(((code >> i) & 1) == 1 ? -a - i : a + i); i += 1
        rows.push(row); code += 1
      p += 1
    r += 1
  p = 0
  while p < n
    t = p + 1
    while t < n
      r = 0
      while r < q
        a = flags[r * n * n + p * n + t]; s = r + 1
        while s < q
          rows.push([-a, -flags[s * n * n + p * n + t]]) unless mode == "relaxed"
          s += 1
        rows.push([-a]) if p / q == t / q && mode != "relaxed"
        r += 1
      t += 1
    p += 1
  if mode == "rename"
    rows = rows.map -> (c)
      c.reverse.map -> (x)
        v = x < 0 ? -x : x; mapped = nv + 18 - v
        ((x > 0) == (v % 3 != 0)) ? mapped : -mapped
    nv += 17
  f = wassat_affine_design_test_flat(rows, nv); f["test_equalities"] = flags; f

-> wassat_affine_design_test_descriptor(q, f)
  n = q * q; nw = q * n; which = i64[f["nvars"] + 1]; coords = i64[f["nvars"] + 1]
  phases = i64[f["nvars"] + 1]; grid = i64[nw]; w = 0
  while w < nw
    grid[w] = w + 1; i = 0
    while i < 3
      v = 1 + 3 * w + i; which[v] = w + 1; coords[v] = i; i += 1
    w += 1
  {"nwords": nw, "rounds": q, "players": n, "which": which, "coordinates": coords, "phases": phases, "grid": grid, "equalities": f["test_equalities"]}

describe "Clause-checked affine design obstruction" ->
  it "recognizes the complete necessary geometry of a satisfiable order-two plane" ->
    m = i64[64]
    expect(wassat_affine_design_refute(wassat_affine_design_test_formula(2), m, i64[2])).to eq(0)
    expect(m[23]).to eq(1)
    expect(m[14]).to eq(6)

  it "accepts variable renaming, polarity flips and unused gaps" ->
    m = i64[64]
    expect(wassat_affine_design_refute(wassat_affine_design_test_formula(2, "rename"), m, i64[2])).to eq(0)
    expect(m[23]).to eq(1)

  it "checks all order-six exclusions and domains before applying the obstruction" ->
    m = i64[64]; f = wassat_affine_design_test_formula(6, "verify")
    expect(wassat_affine_design_verify(f, wassat_affine_design_test_descriptor(6, f), m, i64[2])).to eq(-1)
    expect(m[23]).to eq(1)
    expect(m[24]).to eq(3)
    expect(m[14]).to eq(9450)
    expect(m[28]).to eq(540)

  it "rejects an incomplete equality implication" ->
    m = i64[64]
    expect(wassat_affine_design_refute(wassat_affine_design_test_formula(2, "missing"), m, i64[2])).to eq(0)
    expect(m[23]).to eq(0)

  it "requires original scheduling exclusions" ->
    m = i64[64]
    expect(wassat_affine_design_refute(wassat_affine_design_test_formula(2, "relaxed"), m, i64[2])).to eq(0)
    expect(m[23]).to eq(0)

  it "factors the inferred order rather than consulting known plane orders" ->
    expect(wassat_affine_design_obstruction(6)).to eq(3)
    expect(wassat_affine_design_obstruction(14)).to eq(7)
    expect(wassat_affine_design_obstruction(21)).to eq(7)
    expect(wassat_affine_design_obstruction(33)).to eq(11)
    expect(wassat_affine_design_obstruction(10)).to eq(0)
    expect(wassat_affine_design_obstruction(9)).to eq(0)
    expect(wassat_affine_design_obstruction(3)).to eq(0)
    expect(wassat_affine_design_obstruction(0)).to eq(0)

  it "validates literal ranges before indexed access" ->
    f = wassat_affine_design_test_formula(2); f["flat_lits"][0] = f["nvars"] + 1
    expect(wassat_affine_design_refute(f, i64[64], i64[2])).to eq(0)

  it "validates negative offsets" ->
    f = wassat_affine_design_test_formula(2); f["flat_offs"][0] = -1
    expect(wassat_affine_design_refute(f, i64[64], i64[2])).to eq(0)

  it "validates lengths and the logical literal boundary" ->
    f = wassat_affine_design_test_formula(2); f["flat_nlits"] = f["flat_nlits"] - 1
    expect(wassat_affine_design_refute(f, i64[64], i64[2])).to eq(0)
    f = wassat_affine_design_test_formula(2); f["flat_lens"][0] = 0
    expect(wassat_affine_design_refute(f, i64[64], i64[2])).to eq(0)

  it "rejects formulas outside the bounded input envelope" ->
    f = wassat_affine_design_test_formula(2); f["nvars"] = 100001
    expect(wassat_affine_design_refute(f, i64[64], i64[2])).to eq(0)

  it "checks metadata and cancellation buffer sizes" ->
    f = wassat_affine_design_test_formula(2)
    expect(wassat_affine_design_refute(f, i64[4], i64[2])).to eq(0)
    expect(wassat_affine_design_refute(f, i64[64], i64[1])).to eq(0)

  it "honors cancellation before any decoding" ->
    m = i64[64]; stop = i64[2]; wassat_stop_cancel(stop)
    expect(wassat_affine_design_refute(wassat_affine_design_test_formula(2), m, stop)).to eq(0)
    expect(m[0]).to eq(1)

  it "honors an expired deadline" ->
    m = i64[64]
    expect(wassat_affine_design_refute(wassat_affine_design_test_formula(2), m, i64[2], clock_ms() - 1)).to eq(0)
    expect(m[0]).to eq(2)

  it "bounds both structural scans and binary implication work" ->
    m = i64[64]; m[3] = 50000000; m[15] = 1
    expect(wassat_affine_design_poll(m, i64[2])).to eq(3)

  it "resets reused metrics before rejecting an incomplete certificate" ->
    m = i64[64]; f = wassat_affine_design_test_formula(2)
    expect(wassat_affine_design_refute(f, m, i64[2])).to eq(0)
    expect(m[23]).to eq(1)
    f["flat_lits"][0] = 0
    expect(wassat_affine_design_refute(f, m, i64[2])).to eq(0)
    expect(m[23]).to eq(0)
