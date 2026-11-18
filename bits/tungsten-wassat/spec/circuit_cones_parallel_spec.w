# spec: compiled -- native worker lifetime and atomic aggregate conflict tickets
use spec
use ../lib/circuit_cone_parallel
use circuit_cone_php_fixture
use ../../tungsten-wrat/lib/wrat

# Force a deterministic specialist win without giving either worker a
# different formula or changing the ordinary solver's implementation.
+ ConeDelayedWassat < Wassat
  -> solve_budget(cap)
    ccall("__w_sleep_ms", 40)
    super(cap)

describe "Comparison-cone parallel coordinator" ->
  it "declines unsupported shapes without starting or consuming serial search" ->
    solver = Wassat.new(1, [[1]], WASSAT_PROOF_DRAT)
    expect(wassat_cone_parallel_solve(solver, cone_fixture_flat([[1]], 1), 100) == nil).to eq(true)
    expect(solver.solve_budget(100)["status"]).to eq(1)

  it "returns a checked SAT model from ordinary search and joins the cone worker" ->
    f = cone_fixture_flat(cone_rare_rows, 66)
    solver = Wassat.new(66, wassat_formula_clauses(f), WASSAT_PROOF_DRAT)
    r = wassat_cone_parallel_solve(solver, f, 10000)
    expect(r["cone_won"]).to eq(false)
    expect(r["result"]["status"]).to eq(1)
    expect(wassat_model_satisfies?(f, r["result"]["model"])).to eq(true)

  it "publishes a complete original proof only after a specialist win" ->
    rows = cone_fixture_rows(3)
    f = cone_fixture_flat(rows, 15)
    solver = ConeDelayedWassat.new(15, rows, WASSAT_PROOF_DRAT)
    r = wassat_cone_parallel_solve(solver, f, 1000)
    expect(r["cone_won"]).to eq(true)
    expect(r["cone"]["status"]).to eq(-1)
    text = "p cnf 15 [rows.size]\n"
    rows.each -> (row) text += row.join(" ") + " 0\n"
    expect(wrat_verify(text, r["cone"]["drat_text"])["verified"]).to eq(true)

  it "charges successive local queries to one pre-spent ticket pool" ->
    fixture = cone_php_circuit
    d = wassat_cone_decode(fixture[0])
    work = wassat_cone_workspace(d, 16384)
    state = i64[3]; state[0] = 5; state[1] = 5
    work["conflict_budget"] = state; work["conflict_limit"] = 7; work["conflict_slot"] = 2
    aliases = i64[d["nvars"] + 1]
    q = wassat_cone_prove(d, aliases, work, fixture[1], fixture[2], 100)
    expect(q["equivalent"]).to eq(false)
    expect(q["conflicts"]).to eq(2)
    expect(state[0]).to eq(7)
    expect(state[2]).to eq(2)
    q = wassat_cone_prove(d, aliases, work, fixture[1], fixture[2], 100)
    expect(q["conflicts"]).to eq(0)
    expect(state[0]).to eq(7)

  it "caps the sum of both workers without losing ticket accounting" ->
    fixture = cone_php_circuit
    f = fixture[0]
    rows = wassat_formula_clauses(f)
    [1, 7, 31].each -> (cap)
      solver = Wassat.new(f["nvars"], rows, WASSAT_PROOF_DRAT)
      r = wassat_cone_parallel_solve(solver, f, cap)
      expect(r["result"]["status"]).to eq(0)
      expect(r["cone_won"]).to eq(false)
      expect(r["conflicts"]).to eq(cap)
      state = r["budget"]
      expect(state[0]).to eq(state[1] + state[2])
      expect(state[0]).to eq(cap)

  it "lets ordinary search finish its budget after the cone deadline" ->
    fixture = cone_php_circuit
    f = fixture[0]
    solver = Wassat.new(f["nvars"], wassat_formula_clauses(f), WASSAT_PROOF_DRAT)
    r = wassat_cone_parallel_solve(solver, f, 1000, 1)
    expect(r["cone_won"]).to eq(false)
    expect(r["cone"]["stopped"]).to eq(true)
    expect(r["result"]["status"]).to eq(0)
    expect(r["conflicts"]).to eq(1000)
    expect(solver.solve_budget(1)["conflicts"] > 0).to eq(true)

spec_summary
