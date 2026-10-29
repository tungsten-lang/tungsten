use spec
use ../lib/solver

describe "Ordered replacement-watch search" ->
  it "reaches a final unassigned replacement after a false prefix" ->
    s = Wassat.new(5, [[-1, 2, 3, 4, 5]], WASSAT_PROOF_NONE)
    r = s.solve_assuming([1, -2, -3, -4])
    expect(r["sat"]).to eq(true)
    expect(r["model"].include?(5)).to eq(true)

  it "accepts a satisfied replacement without losing the clause on the next query" ->
    s = Wassat.new(5, [[-1, 2, 3, 4, 5]], WASSAT_PROOF_NONE)
    r = s.solve_assuming([-3, -4, 5, 1, -2])
    expect(r["sat"]).to eq(true)
    r = s.solve_assuming([1, -2, -3, -4, -5])
    expect(r["unsat"]).to eq(true)
    r = s.solve_assuming([1, -2, -3, -4, 5])
    expect(r["sat"]).to eq(true)

spec_summary
