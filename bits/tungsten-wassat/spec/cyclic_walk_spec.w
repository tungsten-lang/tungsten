use spec
use ../lib/wassat

-> cycle_fixture(extra = "")
  text = ""
  count = 0
  n = 6
  col = 0
  while col < n
    line = ""
    row = 0
    while row < n
      lit = row * n + col + 1
      line += "[lit] "
      row += 1
    text += line + "0\n"
    count += 1
    col += 1
  row = 0
  while row < n
    a = 0
    while a < n
      b = a + 1
      while b < n
        text += "[-(row * n + a + 1)] [-(row * n + b + 1)] 0\n"
        count += 1
        b += 1
      a += 1
    row += 1
  edge = 0
  while edge < 2
    a = 0
    while a < n
      b = 0
      while b < n
        d = a - b
        d = -d if d < 0
        d = n - d if d > n - d
        if d < 2
          u = edge * 2
          text += "[-(u * n + a + 1)] [-((u + 1) * n + b + 1)] 0\n"
          count += 1
        b += 1
      a += 1
    edge += 1
  # Row-owned implication cycle and a mixed auxiliary reached from two rows.
  text += "-1 37 0\n-37 38 0\n-38 37 0\n-7 39 0\n-13 39 0\n40 0\n"
  count += 6
  if extra != ""
    text += extra + " 0\n"
    count += 1
  f = wassat_parse_cnf("p cnf 42 [count]\n[text]")
  nl = 0
  f["clauses"].each -> (c) nl += c.size
  lits = i64[nl]; offs = i64[count]; lens = i64[count]
  ci = 0; pos = 0
  f["clauses"].each -> (c)
    offs[ci] = pos; lens[ci] = c.size
    c.each -> (lit)
      lits[pos] = lit
      pos += 1
    ci += 1
  f["flat_ncl"] = count; f["flat_nlits"] = nl
  f["flat_lits"] = lits; f["flat_offs"] = offs; f["flat_lens"] = lens
  f

-> cycle_try(f, m, walk, stop, res, deadline = 0)
  m[17] = clock_ms()
  wassat_cycle_search(f["flat_lits"], f["flat_offs"], f["flat_lens"], f["nvars"], f["flat_ncl"], 6, m, walk, stop, res, 0, deadline)

describe "Circular permutation proposals" ->
  it "decodes distance, searches, lifts implications and replays every clause" ->
    f = cycle_fixture()
    m = i64[24]; walk = i64[34]; stop = i64[4]; res = i64[50]
    expect(wassat_cycle_prefix(f["flat_lits"], f["flat_offs"], f["flat_lens"], 42, f["flat_ncl"])).to eq(6)
    expect(cycle_try(f, m, walk, stop, res)).to eq(1)
    expect(m[1]).to eq(6)
    expect(m[2]).to eq(2)
    expect(m[3]).to eq(2)
    expect(m[4]).to eq(5)
    expect(m[14]).to eq(f["flat_ncl"])
    expect(m[15]).to eq(f["flat_nlits"])
    expect(m[16]).to eq(1)
    expect(walk[26]).to eq(2)
    expect(walk[7]).to eq(0)
    expect(res[40]).to eq(1)
    model = []
    v = 1
    while v <= 42
      model.push(res[v] == 1 ? v : -v)
      v += 1
    expect(wassat_model_satisfies?(f, model)).to eq(true)
    expect(wassat_stop_status(stop)).to eq(0)

  it "rejects a graph solution that misses an unrelated original clause" ->
    f = cycle_fixture("41 42")
    m = i64[24]; walk = i64[34]; stop = i64[4]; res = i64[50]
    expect(cycle_try(f, m, walk, stop, res)).to eq(0)
    expect(walk[13]).to eq(0)
    expect(walk[26]).to eq(1)
    expect(walk[7] > 0).to eq(true)
    expect(m[11] >= 1).to eq(true)
    expect(m[16]).to eq(0)
    expect(res[0]).to eq(0)
    expect(wassat_stop_status(stop)).to eq(0)

  it "never turns a contradictory original unit into a refutation" ->
    f = cycle_fixture("-40")
    m = i64[24]; walk = i64[24]; stop = i64[4]; res = i64[50]
    expect(cycle_try(f, m, walk, stop, res)).to eq(0)
    expect(m[16]).to eq(0)
    expect(wassat_stop_status(stop)).to eq(0)

  it "rejects duplicate matrix entries, invalid literals and flat spans" ->
    f = cycle_fixture()
    lits = f["flat_lits"]; offs = f["flat_offs"]; lens = f["flat_lens"]
    nc = f["flat_ncl"]
    lits[1] = lits[0]
    expect(wassat_cycle_matrix(lits, offs, lens, 42, nc, 6, i64[24], i64[4], 0)).to eq(0)
    lits[1] = 7
    lits[lits.size - 1] = 43
    expect(wassat_cycle_matrix(lits, offs, lens, 42, nc, 6, i64[24], i64[4], 0)).to eq(0)
    lits[lits.size - 1] = 40
    offs[nc - 1] = lits.size
    expect(wassat_cycle_matrix(lits, offs, lens, 42, nc, 6, i64[24], i64[4], 0)).to eq(0)
    expect(wassat_cycle_matrix(lits, i64[1], lens, 42, nc, 6, i64[24], i64[4], 0)).to eq(0)

  it "stops before allocation on cancellation or an expired deadline" ->
    f = cycle_fixture()
    m = i64[24]; walk = i64[24]; stop = i64[4]; res = i64[50]
    wassat_stop_cancel(stop)
    expect(cycle_try(f, m, walk, stop, res)).to eq(0)
    expect(walk[7]).to eq(0)
    m = i64[24]; stop = i64[4]
    expect(cycle_try(f, m, walk, stop, res, clock_ms() - 1)).to eq(0)
    expect(m[22]).to eq(2)
    expect(res[0]).to eq(0)

describe "Early circular model construction" ->
  it "returns a miss without starting a walk when original replay rejects the proposal" ->
    f = cycle_fixture("41 42")
    m = i64[24]; walk = i64[34]; stop = i64[4]; res = i64[50]
    m[17] = clock_ms()
    expect(wassat_cycle_search_mode(f["flat_lits"], f["flat_offs"], f["flat_lens"], 42, f["flat_ncl"], 6, m, walk, stop, res, 0, 0, 0, 0, i64[24], 1)).to eq(0)
    expect(walk[26]).to eq(1)
    expect(walk[7]).to eq(0)
    expect(m[11]).to eq(1)
    expect(m[16]).to eq(0)
    expect(wassat_stop_status(stop)).to eq(0)

describe "Circular worker memory admission" ->
  it "uses runtime units, rounds down fractions, and fails closed" ->
    expect(wassat_cycle_memory_limit(nil)).to eq(8589934592)
    expect(wassat_cycle_memory_limit("8G")).to eq(8589934592)
    expect(wassat_cycle_memory_limit("8192")).to eq(8589934592)
    expect(wassat_cycle_memory_limit("1024MiB")).to eq(1073741824)
    expect(wassat_cycle_memory_limit("7.5g")).to eq(7516192768)
    expect(wassat_cycle_memory_limit("512K")).to eq(524288)
    expect(wassat_cycle_memory_limit("off")).to eq(8589934592)
    expect(wassat_cycle_memory_limit("32G")).to eq(8589934592)
    expect(wassat_cycle_memory_limit("0")).to eq(0)
    expect(wassat_cycle_memory_limit("bad")).to eq(0)
    expect(wassat_cycle_memory_limit("8GiBjunk")).to eq(0)

spec_summary
