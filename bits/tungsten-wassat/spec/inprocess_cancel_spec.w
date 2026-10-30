use spec
use ../lib/solver

+ CancelFixture < Wassat
  ro :sub_head, :sub_stamp, :inp_s_stk, :inp_s_mark, :inprocess_at, :inp_pm, :inp_subsumed, :inprocessings, :inp_failed, :inp_totals, :inp_phase, :sub_sig, :vivify_phase, :dlevel, :nsubst
  -> cancel_on_propagation(n, stop)
    @cancel_after = n
    @cancel_test_stop = stop
    0

  -> propagate
    result = super
    if @cancel_after != nil && @cancel_after > 0
      @cancel_after -= 1
      z = wassat_stop_cancel(@cancel_test_stop) if @cancel_after == 0
    result

  -> mask(n)
    @inprocess_passes = n
    0
  -> phases
    out = []
    i = 1
    while i <= @nvars
      out.push(@phase[i])
      i += 1
    out
  -> root
    self.backjump(0)
  -> mark_dirty
    @need_clean = true
    0

-> cancel_model_ok(clauses, model)
  clauses.all? -> (c)
    c.any? -> (l)
      model.include?(l)

describe "Inprocessing cancellation and query boundaries" ->
  it "delays an enabled first round without re-enabling a disabled arm" ->
    s = CancelFixture.new(3, [[1, 2, 3]], 0, 0)
    s.enable_inprocess(100, 20)
    s.delay_inprocess(25)
    expect(s.inprocess_at).to eq(125)
    s.disable_inprocess
    s.delay_inprocess(25)
    expect(s.inprocess_at).to eq(0)

  it "does no optional work after cancellation and resumes after detachment" ->
    clauses = [[1, 2], [1, -2], [2, 3]]
    s = CancelFixture.new(3, clauses, 0, 0)
    s.prepare_inprocessing
    phases = s.phases
    stop = i64[4]
    s.set_stop_cell(stop)
    z = wassat_stop_cancel(stop)
    s.inprocess_round
    s.probe_round(100000)
    s.vivify_round(100, true, 100000)
    s.run_subsume(1, 100000)
    s.substitute_equivalences
    expect(s.inprocessings).to eq(0)
    expect(s.inp_failed).to eq(0)
    expect(s.phases).to eq(phases)
    expect(s.dlevel).to eq(0)
    s.set_stop_cell(nil)
    result = s.solve
    expect(result["status"]).to eq(1)
    expect(cancel_model_ok(clauses, result["model"])).to eq(true)

  it "abandons a cancelled probe without deriving an unfinished implication" ->
    clauses = [[1, 2], [1, -2], [2, 3]]
    s = CancelFixture.new(3, clauses, 0, 0)
    s.prepare_inprocessing
    before = s.phases
    stop = i64[4]
    s.set_stop_cell(stop)
    s.cancel_on_propagation(2, stop)
    s.probe_round(100000)
    expect(wassat_stop_load(stop)).to eq(1)
    expect(s.dlevel).to eq(0)
    expect(s.phases).to eq(before)
    s.set_stop_cell(nil)
    result = s.solve
    expect(cancel_model_ok(clauses, result["model"])).to eq(true)

  it "discards a partial vivification test and restores phases" ->
    clauses = [[1, 2, 3], [-1, 2, 3], [1, -2, 3]]
    s = CancelFixture.new(3, clauses, 0, 0)
    s.prepare_inprocessing
    before = s.phases
    stop = i64[4]
    s.set_stop_cell(stop)
    s.cancel_on_propagation(2, stop)
    s.vivify_round(100, true, 100000)
    expect(wassat_stop_load(stop)).to eq(1)
    expect(s.dlevel).to eq(0)
    expect(s.phases).to eq(before)
    s.set_stop_cell(nil)
    result = s.solve_assuming([-3, 1, 2])
    expect(result["status"]).to eq(1)
    expect(cancel_model_ok(clauses, result["model"])).to eq(true)

  it "reports index construction separately from candidate-visit budgets" ->
    clauses = []
    100.times -> clauses.push([1, 2, 3])
    s = CancelFixture.new(3, clauses, 0, 0)
    s.prepare_inprocessing
    s.run_subsume(1, 20)
    expect(s.inp_pm[6] <= 20).to eq(true)
    expect(s.inp_pm[13] > s.inp_pm[6]).to eq(true)
    s.clean_root_clauses
    expect(s.solve["status"]).to eq(1)

  it "finishes required root repair even after cancellation" ->
    clauses = [[-2, 3], [1, 2, 3], [4, 5, 6]]
    s = CancelFixture.new(6, clauses, 0, 0)
    s.prepare_inprocessing
    s.run_subsume(1, 100000)
    stop = i64[4]
    s.set_stop_cell(stop)
    z = wassat_stop_cancel(stop)
    s.clean_root_clauses
    s.set_stop_cell(nil)
    result = s.solve_assuming([-1, -3])
    expect(result["status"]).to eq(-1)

  it "omits unused scratch when every optional pass is disabled" ->
    s = CancelFixture.new(3, [[1, 2, 3]], 0, 0)
    s.mask(0)
    s.prepare_inprocessing
    expect(s.inp_phase).to eq(nil)
    expect(s.sub_sig).to eq(nil)
    expect(s.vivify_phase).to eq(nil)

  it "reuses subsumption tables even when they were prepared before SCC" ->
    s = CancelFixture.new(3, [[1, 2, 3]], 0, 0)
    s.enable_subsume(100)
    head = s.sub_head
    stamp = s.sub_stamp
    s.prepare_inprocessing
    s.inp_s_stk[0] = 123
    s.inp_s_mark[0] = 456
    expect(head[0]).to eq(123)
    expect(stamp[0]).to eq(456)

  it "does not count parked equivalences as forced units" ->
    s = CancelFixture.new(2, [[-1, 2], [1, -2]], 0, 0)
    s.mask(8)
    s.inprocess_round
    expect(s.nsubst).to eq(1)
    expect(s.inp_totals[1]).to eq(0)

  it "follows mappings accumulated over separate substitution rounds" ->
    clauses = [[-2, -3], [2, 3], [1, 2], [-1, -2]]
    s = CancelFixture.new(3, [[-2, -3], [2, 3]], 0, 0)
    s.substitute_equivalences
    s.add_input_clause([1, 2])
    s.add_input_clause([-1, -2])
    s.substitute_equivalences
    expect(s.nsubst).to eq(2)
    result = s.solve_assuming([3, -2, 1])
    expect(result["status"]).to eq(1)
    expect(cancel_model_ok(clauses, result["model"])).to eq(true)
    bad = s.solve_assuming([3, -1])
    expect(bad["status"]).to eq(-1)
    expect(bad["core"].include?(3)).to eq(true)
    expect(bad["core"].include?(-1)).to eq(true)
    fresh = Wassat.new(3, clauses, 0, 0)
    expect(fresh.solve_assuming(bad["core"])["status"]).to eq(-1)

  it "maps later assumptions and failed cores through signed substitution chains" ->
    clauses = [[-1, 2], [1, -2], [-2, -3], [2, 3]]
    s = CancelFixture.new(3, clauses, 0, 0)
    s.substitute_equivalences
    expect(s.nsubst > 0).to eq(true)
    [[-1, -2, 3], [1, 2, -3], [-2, -3], [2, 3], [-2, -2], [2, -2], []].each -> (assumptions)
      result = s.solve_assuming(assumptions)
      fresh = Wassat.new(3, clauses, 0, 0)
      expected = fresh.solve_assuming(assumptions)
      expect(result["status"]).to eq(expected["status"])
      if result["sat"]
        expect(cancel_model_ok(clauses, result["model"])).to eq(true)
        assumptions.each -> (a)
          expect(result["model"].include?(a)).to eq(true)
      else
        core = result["core"]
        expect(core.empty?).to eq(false)
        core.each -> (a)
          expect(assumptions.include?(a)).to eq(true)
        check = Wassat.new(3, clauses, 0, 0)
        expect(check.solve_assuming(core)["status"]).to eq(-1)

spec_summary
