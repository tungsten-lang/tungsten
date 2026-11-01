use spec
use ../lib/solver

+ LuckyRepairCancelFixture < Wassat
  ro :qhead, :tsize, :wp_state, :formula_unsat, :lucky_cancel_rebuild

  -> cancel_after_next_repair(stop)
    self.rebuild_watches
    li = 0
    while li < 2 * @nvars + 4
      @wsdir[4 * li + 2] = @wsdir[4 * li + 1]
      li += 1
    @wp_state[1] = @wp_state[0]
    @test_cancel_stop = stop

  -> rebuild_watches
    result = super
    wassat_stop_cancel(@test_cancel_stop) if @test_cancel_stop != nil
    result

describe "Lucky-dive cancellation after watch repair" ->
  it "returns a miss and preserves unpropagated root units for resumption" ->
    clauses = [[-1], [-4], [1, 2, 3], [1, -2, 3], [-3, 4]]
    s = LuckyRepairCancelFixture.new(4, clauses, 0, 0)
    stop = i64[4]
    s.set_stop_cell(stop)
    s.cancel_after_next_repair(stop)
    expect(s.lucky_dive(-1, 0)).to eq(0)
    expect(s.wp_state[11]).to eq(1)
    expect(s.qhead).to eq(0)
    expect(s.tsize >= 2).to eq(true)
    expect(s.formula_unsat).to eq(false)
    expect(s.lucky_cancel_rebuild).to eq(false)
    s.set_stop_cell(nil)
    expect(s.solve["status"]).to eq(-1)

  it "unwinds a cancelled decision dive and can later return a valid model" ->
    clauses = [[1, 2, 3], [-1, 2, 3], [-3, 4]]
    s = LuckyRepairCancelFixture.new(4, clauses, 0, 0)
    stop = i64[4]
    s.set_stop_cell(stop)
    s.cancel_after_next_repair(stop)
    expect(s.lucky_dive(-1, 0)).to eq(0)
    expect(s.wp_state[11]).to eq(1)
    expect(s.lucky_cancel_rebuild).to eq(false)
    s.set_stop_cell(nil)
    result = s.solve
    expect(result["status"]).to eq(1)
    clauses.each -> (c)
      expect(c.any? -> (l) result["model"].include?(l)).to eq(true)

  it "keeps ordinary propagation complete despite cancellation" ->
    clauses = [[-1], [-4], [1, 2, 3], [1, -2, 3], [-3, 4]]
    s = LuckyRepairCancelFixture.new(4, clauses, 0, 0)
    stop = i64[4]
    s.set_stop_cell(stop)
    s.cancel_after_next_repair(stop)
    expect(s.propagate >= 0).to eq(true)
    expect(s.wp_state[11]).to eq(0)
    expect(wassat_stop_requested?(stop)).to eq(true)

spec_summary
