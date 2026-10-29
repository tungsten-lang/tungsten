use spec
use wassat

describe "Scout continuation with local search" ->
  it "resumes a detached scout through its phase walk" ->
    # Every assignment is excluded, so the phase walk must enter its flip
    # loop instead of returning before it reads the cancellation cell.
    solver = Wassat.new(2, [[1, 2], [1, -2], [-1, 2], [-1, -2]], WASSAT_PROOF_NONE, 0)
    shared = i64[4]
    solver.set_stop_cell(shared)
    z = wassat_stop_cancel(shared)
    solver.set_stop_cell(nil)
    solver.walk_phases
    expect(wassat_stop_load(shared)).to eq(1)
    result = solver.solve_budget(20)
    expect(result["status"]).to eq(-1)

spec_summary
