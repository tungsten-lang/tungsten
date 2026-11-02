use spec
use ../lib/wassat

-> dependency_test_flat(text)
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

-> dependency_test_run(text, budget = WASSAT_SMALL_CIRCUIT_MAX_WORK, deadline = 0)
  f = dependency_test_flat(text)
  p = wassat_dependency_circuit_plan(f, budget)
  r = wassat_dependency_circuit_run(f, p, i64[4], deadline)
  [r, p]

-> dependency_test_gate(kind, a, b, o)
  if kind == 0
    "[o] [0 - a] [0 - b] 0\n[0 - o] [a] 0\n[0 - o] [b] 0\n"
  else
    "[0 - o] [a] [b] 0\n[0 - o] [0 - a] [0 - b] 0\n[o] [a] [0 - b] 0\n[o] [0 - a] [b] 0\n"

describe "Dependency circuit backdoors" ->
  it "derives signed AND and XOR gates regardless of variable order" ->
    kind = 0
    while kind < 2
      signs = 0
      while signs < 8
        a = (signs & 1) == 0 ? 3 : -3
        b = (signs & 2) == 0 ? 2 : -2
        o = (signs & 4) == 0 ? 1 : -1
        body = dependency_test_gate(kind, a, b, o)
        row = 0
        while row < 4
          av = (row & 1) ^ (a < 0 ? 1 : 0)
          bv = ((row >> 1) & 1) ^ (b < 0 ? 1 : 0)
          ov = (kind == 0 ? (av & bv) : (av ^ bv)) ^ (o < 0 ? 1 : 0)
          al = (row & 1) == 0 ? -3 : 3
          bl = (row & 2) == 0 ? -2 : 2
          ol = ov == 0 ? -1 : 1
          nc = kind == 0 ? 6 : 7
          # Keep the output unassigned during planning: the repeated-literal
          # assertion checks the gate's computed value, rather than seeding it.
          good = dependency_test_run("p cnf 3 [nc]\n[body][al] 0\n[bl] 0\n[ol] [ol] 0\n")
          expect(good[0]).to eq(0)
          expect(good[1]["meta"][10]).to eq(1)
          bad = dependency_test_run("p cnf 3 [nc]\n[body][al] 0\n[bl] 0\n[0 - ol] [0 - ol] 0\n")
          expect(bad[0]).to eq(1)
          row += 1
        signs += 1
      kind += 1

  it "uses equality in either direction and retains conflicting assertions" ->
    r = dependency_test_run("p cnf 4 6\n1 -4 0\n-1 4 0\n2 4 0\n-2 -4 0\n1 0\n2 0\n")
    expect(r[0]).to eq(1)
    expect(r[1]["meta"][0]).to eq(1)
    expect(r[1]["meta"][1]).to eq(1)

  it "evaluates a cyclic definition by enumerating a feedback input" ->
    r = dependency_test_run("p cnf 3 6\n1 -2 0\n-1 2 0\n2 -3 0\n-2 3 0\n3 1 0\n-3 -1 0\n")
    expect(r[0]).to eq(1)
    expect(r[1]["meta"][1]).to eq(1)

  it "retains unsupported and repeated-variable clauses as assertions" ->
    r = dependency_test_run("p cnf 3 4\n1 1 0\n-1 -1 0\n2 -2 3 0\n1 2 3 -3 0\n")
    expect(r[0]).to eq(1)
    expect(r[1]["meta"][3]).to eq(4)
    partial = dependency_test_run("p cnf 3 3\n3 -1 -2 0\n-3 1 0\n3 0\n")
    expect(partial[0]).to eq(0)
    expect(partial[1]["meta"][10]).to eq(1)

  it "checks duplicate definitions and opposite units without overwriting them" ->
    r = dependency_test_run("p cnf 3 5\n1 0\n-1 0\n3 -2 0\n-3 2 0\n3 -2 0\n")
    expect(r[0]).to eq(1)

  it "enumerates a second batch and retains a satisfying last assignment" ->
    # Only all seven inputs true satisfies this assertion-only encoding.
    body = ""
    i = 1
    while i <= 7
      body += "[i] [i] 0\n"
      i += 1
    r = dependency_test_run("p cnf 7 7\n[body]")
    expect(r[0]).to eq(0)
    expect(r[1]["meta"][1]).to eq(7)
    expect(r[1]["meta"][6]).to eq(2)
    expect(r[1]["meta"][10]).to eq(1)

  it "bounds total work and the number of independent variables" ->
    r = dependency_test_run("p cnf 3 1\n1 1 0\n", 1)
    expect(r[0]).to eq(0)
    expect(r[1]["meta"][0]).to eq(0)
    expect(r[1]["meta"][9]).to eq(2)
    r = dependency_test_run("p cnf 21 1\n1 1 0\n")
    expect(r[0]).to eq(0)
    expect(r[1]["meta"][9]).to eq(2)

  it "cancels or expires without retaining an earlier verdict" ->
    f = dependency_test_flat("p cnf 2 2\n1 0\n-1 0\n")
    p = wassat_dependency_circuit_plan(f)
    expect(wassat_dependency_circuit_run(f, p, i64[4])).to eq(1)
    stop = i64[4]
    wassat_stop_cancel(stop)
    expect(wassat_dependency_circuit_run(f, p, stop)).to eq(0)
    expect(p["meta"][10]).to eq(0)
    expect(p["meta"][9]).to eq(1)
    expect(wassat_dependency_circuit_run(f, p, i64[4], 1)).to eq(0)
    expect(p["meta"][9]).to eq(3)

  it "bounds logical literals rather than spare parser capacity" ->
    f = dependency_test_flat("p cnf 1 1\n1 0\n")
    f["flat_nlits"] = 1
    spare = i64[1600001]
    spare[0] = 1
    f["flat_lits"] = spare
    expect(wassat_dependency_circuit_plan(f) != nil).to eq(true)

  it "publishes a complete refutation and respects an existing winner" ->
    f = dependency_test_flat("p cnf 2 4\n1 2 0\n1 -2 0\n-1 2 0\n-1 -2 0\n")
    p = wassat_dependency_circuit_plan(f)
    stop = i64[4]
    res = i64[10]
    hit = wassat_dependency_circuit_arm(f["flat_lits"], f["flat_offs"], f["flat_lens"], p["program"], p["inputs"], p["assertions"], p["meta"], p["values"], stop, res, 0, 2)
    expect(hit).to eq(1)
    expect(res[0]).to eq(-1)
    expect(wassat_stop_status(stop)).to eq(-1)
    res2 = i64[10]
    stop2 = i64[4]
    wassat_stop_publish(stop2, 1)
    hit = wassat_dependency_circuit_arm(f["flat_lits"], f["flat_offs"], f["flat_lens"], p["program"], p["inputs"], p["assertions"], p["meta"], p["values"], stop2, res2, 0, 2)
    expect(hit).to eq(0)
    expect(res2[0]).to eq(0)
    expect(wassat_stop_status(stop2)).to eq(1)

spec_summary
