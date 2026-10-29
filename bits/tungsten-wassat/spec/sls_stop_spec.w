use spec
use ../lib/sls

SLS_STOP_UNSAT = [[1, 2], [1, -2], [-1, 2], [-1, -2]]

describe "SLS cancellation ownership" ->
  it "keeps a valid private stop cell when detached before its first walk" ->
    walker = WassatSls.new(2, SLS_STOP_UNSAT, nil, nil)
    walker.set_stop_cell(nil)
    result = walker.solve(12, 3)
    expect(result["sat"]).to eq(false)
    expect(result["flips"]).to eq(12)
    expect(result["best_unsat"]).to eq(1)

  it "detaches from a cancelled race without clearing the shared flag" ->
    walker = WassatSls.new(2, SLS_STOP_UNSAT, nil, nil)
    shared = i64[4]
    walker.set_stop_cell(shared)
    z = wassat_stop_cancel(shared)
    stopped = walker.solve(12, 3)
    expect(stopped["flips"]).to eq(0)
    walker.set_stop_cell(nil)
    resumed = walker.solve(12, 3)
    expect(resumed["flips"]).to eq(12)
    expect(wassat_stop_load(shared)).to eq(1)

  it "preserves the trajectory across cancellation, detachment and reattachment" ->
    reference = WassatSls.new(2, SLS_STOP_UNSAT, nil, nil)
    expected = reference.solve(30, 7)
    walker = WassatSls.new(2, SLS_STOP_UNSAT, nil, nil)
    first = i64[4]
    walker.set_stop_cell(first)
    prefix = walker.solve(10, 7)
    z = wassat_stop_cancel(first)
    stopped = walker.continue_solve(20, 7)
    expect(stopped["flips"]).to eq(10)
    walker.set_stop_cell(nil)
    middle = walker.continue_solve(20, 7)
    expect(middle["flips"]).to eq(20)
    second = i64[4]
    z = wassat_stop_cancel(second)
    walker.set_stop_cell(second)
    stopped_again = walker.continue_solve(30, 7)
    expect(stopped_again["flips"]).to eq(20)
    walker.set_stop_cell(nil)
    walker.set_stop_cell(nil)
    final = walker.continue_solve(30, 7)
    expect(final["flips"]).to eq(expected["flips"])
    expect(final["best_unsat"]).to eq(expected["best_unsat"])
    expect(final["best_assign"]).to eq(expected["best_assign"])
    expect(wassat_stop_load(first)).to eq(1)
    expect(wassat_stop_load(second)).to eq(1)

spec_summary
