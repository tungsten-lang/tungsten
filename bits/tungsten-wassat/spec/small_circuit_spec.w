use spec
use ../lib/wassat

-> small_circuit_test_flat(text)
  f = wassat_parse_cnf(text)
  total = 0
  f["clauses"].each ->(c) total += c.size
  lits = i64[total]
  offs = i64[f["clauses"].size]
  lens = i64[f["clauses"].size]
  ci = 0
  pos = 0
  f["clauses"].each -> (c)
    offs[ci] = pos
    lens[ci] = c.size
    c.each -> (l)
      lits[pos] = l
      pos += 1
    ci += 1
  f["flat_lits"] = lits
  f["flat_offs"] = offs
  f["flat_lens"] = lens
  f["flat_ncl"] = ci
  f

-> small_circuit_test_gate(tt, extra)
  lines = []
  row = 0
  while row < 4
    a = (row & 1) == 1 ? -1 : 1
    b = (row & 2) == 2 ? -2 : 2
    z = ((tt >> row) & 1) == 1 ? 3 : -3
    lines.push("[a] [b] [z] 0")
    row += 1
  extra.each ->(line) lines.push(line)
  small_circuit_test_flat("p cnf 3 [lines.size]\n[lines.join("\n")]\n")

describe "Exact small circuits" ->
  it "derives all sixteen two-input truth tables from the clauses" ->
    tt = 0
    while tt < 16
      row = 0
      while row < 4
        a = (row & 1) == 1 ? 1 : -1
        b = (row & 2) == 2 ? 2 : -2
        actual = ((tt >> row) & 1) == 1 ? 3 : -3
        good = small_circuit_test_gate(tt, ["[a] 0", "[b] 0", "[actual] 0"])
        p = wassat_small_circuit_plan(good)
        expect(p != nil).to eq(true)
        expect(wassat_small_circuit_run(good, p, i64[4])).to eq(0)
        expect(p["meta"][10]).to eq(1)
        bad = small_circuit_test_gate(tt, ["[a] 0", "[b] 0", "[0 - actual] 0"])
        q = wassat_small_circuit_plan(bad)
        expect(wassat_small_circuit_run(bad, q, i64[4])).to eq(1)
        expect(q["meta"][6]).to eq(q["meta"][5])
        row += 1
      tt += 1

  it "covers the last lane and a second 64-assignment batch" ->
    # z8 = x1 AND x7; z9 = z8 XOR x6. The sole permitted input is 127.
    body = "8 -1 -7 0\n-8 1 0\n-8 7 0\n-9 8 6 0\n-9 -8 -6 0\n9 8 -6 0\n9 -8 6 0\n"
    i = 1
    while i <= 7
      body += "[i] 0\n"
      i += 1
    f = small_circuit_test_flat("p cnf 9 15\n[body]-9 0\n")
    p = wassat_small_circuit_plan(f)
    expect(p["meta"][1]).to eq(7)
    expect(wassat_small_circuit_run(f, p, i64[4])).to eq(0)
    expect(p["meta"][6]).to eq(2)
    f2 = small_circuit_test_flat("p cnf 9 15\n[body]9 0\n")
    p2 = wassat_small_circuit_plan(f2)
    expect(wassat_small_circuit_run(f2, p2, i64[4])).to eq(1)
    expect(p2["meta"][7]).to eq(4)

  it "rejects partial and inconsistent gate definitions without a verdict" ->
    partial = small_circuit_test_flat("p cnf 3 3\n3 -1 -2 0\n-3 1 0\n3 0\n")
    expect(wassat_small_circuit_plan(partial) == nil).to eq(true)
    inconsistent = small_circuit_test_flat("p cnf 2 5\n1 2 0\n1 -2 0\n-1 2 0\n-1 -2 0\n1 0\n")
    expect(wassat_small_circuit_plan(inconsistent) == nil).to eq(true)

  it "accepts a wide assertion and repeated defining clauses" ->
    f = small_circuit_test_flat("p cnf 3 5\n3 -1 -2 0\n-3 1 0\n-3 2 0\n-3 1 0\n1 -1 3 -3 0\n")
    p = wassat_small_circuit_plan(f)
    expect(p != nil).to eq(true)
    expect(wassat_small_circuit_run(f, p, i64[4])).to eq(0)

  it "bounds work and rejects too many independent inputs" ->
    f = small_circuit_test_gate(8, ["3 0"])
    expect(wassat_small_circuit_plan(f, 1) == nil).to eq(true)
    many = small_circuit_test_flat("p cnf 27 4\n27 -1 -2 0\n-27 1 0\n-27 2 0\n27 0\n")
    expect(wassat_small_circuit_plan(many) == nil).to eq(true)

  it "cancels and expires without retaining an earlier refutation" ->
    f = small_circuit_test_gate(0, ["3 0"])
    p = wassat_small_circuit_plan(f)
    expect(wassat_small_circuit_run(f, p, i64[4])).to eq(1)
    stop = i64[4]
    wassat_stop_cancel(stop)
    expect(wassat_small_circuit_run(f, p, stop)).to eq(0)
    expect(p["meta"][9]).to eq(1)
    expect(p["meta"][10]).to eq(0)
    expect(p["meta"][6]).to eq(0)
    expect(wassat_small_circuit_run(f, p, i64[4], 1)).to eq(0)
    expect(p["meta"][9]).to eq(3)

spec_summary
