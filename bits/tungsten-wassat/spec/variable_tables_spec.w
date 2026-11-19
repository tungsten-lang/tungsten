use spec
use ../lib/solver

+ VarTableFixture < Wassat
  -> first_variable
    [@reason[1], @phase[1], @bphase[1], @best_phase[1], @heap[0], @heappos[0]]

  -> priorities
    result = []
    (1..@nvars).each -> (v)
      result.push([@vq_stamp[v], @activity[v]])
    result

describe "Decision-variable table initialization" ->
  it "uses the same priorities for ordinary and flat solvers across decision limits" ->
    name = "WASSAT_MAX_DEC_VAR"
    previous = env(name)
    begin
      cases = [
        ["2", [[3, 0], [2, 0], [0, -1]]],
        ["9223372036854775808", [[3, 0], [2, 0], [1, 0]]],
        ["-9223372036854775809", [[0, -1], [0, -1], [0, -1]]]
      ]
      cases.each -> (entry)
        Env.set(name, entry[0])
        ordinary = VarTableFixture.new(3, [], WASSAT_PROOF_NONE)
        flat = VarTableFixture.new(3, [], WASSAT_PROOF_NONE, 0, true)
        flat.init_var_tables
        expect(ordinary.priorities).to eq(entry[1])
        expect(flat.priorities).to eq(entry[1])
    ensure
      if previous == nil
        Env.delete(name)
      else
        Env.set(name, previous)

  it "initializes only the propagation tables for a lean flat solver" ->
    lean = VarTableFixture.new(3, [], WASSAT_PROOF_NONE, 0, true)
    lean.init_var_tables(true)
    expect(lean.first_variable).to eq([-1, -1, 0, 0, 0, -1])
    ordinary = VarTableFixture.new(3, [], WASSAT_PROOF_NONE)
    expect(ordinary.first_variable).to eq([-1, -1, -1, -1, 1, -1])

spec_summary
