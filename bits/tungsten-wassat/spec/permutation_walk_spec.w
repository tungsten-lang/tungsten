use spec
use ../lib/wassat

-> perm_formula(text)
  f = wassat_parse_cnf(text)
  nc = f["clauses"].size
  nl = 0
  f["clauses"].each -> (c) nl += c.size
  lits = i64[nl]; offs = i64[nc]; lens = i64[nc]
  ci = 0; pos = 0
  f["clauses"].each -> (c)
    offs[ci] = pos
    lens[ci] = c.size
    c.each -> (lit)
      lits[pos] = lit
      pos += 1
    ci += 1
  f["flat_ncl"] = nc; f["flat_nlits"] = nl
  f["flat_lits"] = lits; f["flat_offs"] = offs; f["flat_lens"] = lens
  f

-> perm_art(f)
  wassat_raw_artifact(f, f["nvars"])

# Four vertices, a single edge (0,1), distance at least two. Columns plus
# pairwise row/column exclusions enforce a permutation, with no stored model.
-> perm_fixture(extra = "")
  text = ""
  count = 0
  col = 0
  while col < 4
    text += "[col + 1] [col + 5] [col + 9] [col + 13] 0\n"
    count += 1
    col += 1
  row = 0
  while row < 4
    a = 0
    while a < 4
      b = a + 1
      while b < 4
        text += "[-(row * 4 + a + 1)] [-(row * 4 + b + 1)] 0\n"
        text += "[-(a * 4 + row + 1)] [-(b * 4 + row + 1)] 0\n"
        count += 2
        b += 1
      a += 1
    row += 1
  a = 0
  while a < 4
    b = 0
    while b < 4
      d = a - b
      d = -d if d < 0
      if d < 2
        text += "[-(a + 1)] [-(b + 5)] 0\n"
        count += 1
      b += 1
    a += 1
  nv = extra == "" ? 16 : 18
  count += 1 unless extra == ""
  perm_formula("p cnf [nv] [count]\n[text][extra]")

describe "Propagation snapshots for model proposals" ->
  it "restores roots, copies values, and retracts failed assumptions" ->
    f = perm_formula("p cnf 4 3\n1 0\n-2 3 0\n-2 -3 4 0\n")
    s = Wassat.from_flat_lucky(4, perm_art(f))
    values = i8[5]; first = i8[5]; counters = i64[4]
    expect(s.propagation_snapshot([2], first, counters)).to eq(1)
    expect(first[3]).to eq(1)
    expect(first[4]).to eq(1)
    expect(s.propagation_snapshot([2, -4], values, counters)).to eq(-1)
    expect(values[1]).to eq(0)
    expect(s.propagation_snapshot([], values, counters)).to eq(1)
    expect(values[1]).to eq(1)
    expect(values[2]).to eq(0)
    expect(values[3]).to eq(0)
    expect(first[3]).to eq(1)
    expect(s.propagation_snapshot([-2, -2], values, counters)).to eq(1)
    expect(values[2]).to eq(-1)
    expect(counters[0]).to eq(4)
    expect(counters[3]).to eq(1)

  it "rejects invalid literals, buffers, proof mode and prior cancellation" ->
    s = Wassat.new(4, [[1]], WASSAT_PROOF_NONE, 0)
    values = i8[5]; counters = i64[4]
    expect(s.propagation_snapshot([0], values, counters)).to eq(-1)
    expect(s.propagation_snapshot([5], values, counters)).to eq(-1)
    expect(s.propagation_snapshot([-5], values, counters)).to eq(-1)
    expect(s.propagation_snapshot([], i8[4], counters)).to eq(0)
    expect(s.propagation_snapshot([], values, i64[3])).to eq(0)
    proof = Wassat.new(4, [[1]], WASSAT_PROOF_WRAT, 0)
    expect(proof.propagation_snapshot([], values, counters)).to eq(0)
    stop = i64[4]
    wassat_stop_cancel(stop)
    s.set_stop_cell(stop)
    expect(s.propagation_snapshot([], values, counters)).to eq(0)

  it "does not reinterpret a root contradiction as a global proof" ->
    s = Wassat.new(4, [[1], [-1]], WASSAT_PROOF_NONE, 0)
    expect(s.propagation_snapshot([], i8[5], i64[4])).to eq(-1)

describe "Permutation model proposals" ->
  it "decodes and lifts a fresh distance-preserving permutation" ->
    f = perm_fixture()
    n = wassat_perm_matrix(f["flat_lits"], f["flat_offs"], f["flat_lens"], 16, f["flat_ncl"])
    expect(n).to eq(4)
    expect(wassat_perm_prefix(f["flat_lits"], f["flat_offs"], f["flat_lens"], 16, f["flat_ncl"])).to eq(4)
    m = i64[24]; stop = i64[4]; res = i64[24]
    m[17] = clock_ms()
    expect(wassat_perm_search(f, perm_art(f), n, m, stop, res, 0, 0, 2, 1000)).to eq(1)
    expect(m[1]).to eq(4)
    expect(m[2]).to eq(1)
    expect(m[3]).to eq(2)
    expect(m[16]).to eq(1)
    model = []
    v = 1
    while v <= 16
      model.push(res[v] == 1 ? v : -v)
      v += 1
    expect(wassat_model_satisfies?(f, model)).to eq(true)
    expect(wassat_stop_status(stop)).to eq(0)

  it "declines malformed matrices, duplicate columns and undersized mirrors" ->
    f = perm_fixture()
    lits = f["flat_lits"]; offs = f["flat_offs"]; lens = f["flat_lens"]
    nc = f["flat_ncl"]
    expect(wassat_perm_matrix(lits, i64[1], lens, 16, nc)).to eq(0)
    lits[1] = lits[0]
    expect(wassat_perm_matrix(lits, offs, lens, 16, nc)).to eq(0)
    lits[1] = 5
    lits[4] = 1; lits[5] = 5; lits[6] = 9; lits[7] = 13
    expect(wassat_perm_matrix(lits, offs, lens, 16, nc)).to eq(0)
    lens[0] = 257
    expect(wassat_perm_matrix(lits, offs, lens, 16, nc)).to eq(0)

  it "rejects a graph solution that fails an unrelated original clause" ->
    f = perm_fixture("17 18 0\n")
    m = i64[24]; stop = i64[4]; res = i64[26]
    m[17] = clock_ms()
    expect(wassat_perm_search(f, perm_art(f), 4, m, stop, res, 0, 0, 2, 1000)).to eq(0)
    expect(m[13]).to eq(0)
    expect(m[16]).to eq(0)
    expect(res[0]).to eq(0)
    expect(wassat_stop_status(stop)).to eq(0)

  it "does no search after cancellation or expiration" ->
    f = perm_fixture(); art = perm_art(f)
    m = i64[24]; stop = i64[4]; res = i64[24]
    wassat_stop_cancel(stop)
    expect(wassat_perm_search(f, art, 4, m, stop, res, 0, 0)).to eq(0)
    expect(m[7]).to eq(0)
    m = i64[24]; stop = i64[4]
    expect(wassat_perm_search(f, art, 4, m, stop, res, 0, clock_ms() - 1)).to eq(0)
    expect(m[22]).to eq(2)
    expect(res[0]).to eq(0)

spec_summary
