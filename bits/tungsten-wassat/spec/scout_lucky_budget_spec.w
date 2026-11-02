use spec
use ../lib/wassat

+ ScoutLuckyBudgetFixture < Wassat
  ro :assign, :dlevel, :qhead, :pstate

  -> resume_without_lucky
    @lucky_pending = false
    self.solve

-> scout_lucky_model_ok(cs, model)
  cs.all? -> (c) c.any? -> (l) model.include?(l)

-> scout_lucky_budget_case(nv, cs, budget)
  s = ScoutLuckyBudgetFixture.new(nv, cs, WASSAT_PROOF_NONE, 0)
  r = s.lucky_probe(budget)
  expect(r == 0 || r == 1 || r == -1).to eq(true)
  expect(s.dlevel).to eq(0) if r == 0
  if r == 1
    expect(scout_lucky_model_ok(cs, s.result_for(r)["model"])).to eq(true)
  out = s.resume_without_lucky
  expect(scout_lucky_model_ok(cs, out["model"])).to eq(true) if out["sat"]
  [r, out]

describe "Serial scout lucky propagation budget" ->
  it "abandons a partial dive only between propagation calls and can resume" ->
    cs = [[-1, 2], [-3, 4], [-5, 6]]
    s = ScoutLuckyBudgetFixture.new(6, cs, WASSAT_PROOF_NONE, 0)
    expect(s.lucky_dive(1, 0, 1)).to eq(-2)
    expect(s.dlevel).to eq(0)
    expect(s.qhead).to eq(0)
    r = s.resume_without_lucky
    expect(r["sat"]).to eq(true)
    expect(scout_lucky_model_ok(cs, r["model"])).to eq(true)

  it "retains a completed assignment that overshoots the budget" ->
    cs = [[-1, 2], [-2, 3], [-3, 4]]
    s = ScoutLuckyBudgetFixture.new(4, cs, WASSAT_PROOF_NONE, 0)
    expect(s.lucky_dive(1, 0, 1)).to eq(1)
    expect(scout_lucky_model_ok(cs, s.result_for(1)["model"])).to eq(true)

  it "preserves a proved failed literal when the next decision is capped" ->
    cs = [[1, 2], [1, -2], [-1, 3]]
    s = ScoutLuckyBudgetFixture.new(4, cs, WASSAT_PROOF_NONE, 0)
    expect(s.lucky_dive(-1, 0, 1)).to eq(-2)
    expect(s.assign[1]).to eq(1)
    expect(s.assign[3]).to eq(1)
    expect(s.dlevel).to eq(0)
    r = s.resume_without_lucky
    expect(r["sat"]).to eq(true)
    expect(scout_lucky_model_ok(cs, r["model"])).to eq(true)

  it "keeps root conflict detection independent of the speculation cap" ->
    s = ScoutLuckyBudgetFixture.new(4, [[1], [-1, 2], [-2]], WASSAT_PROOF_NONE, 0)
    expect(s.lucky_dive(1, 0, 1)).to eq(-1)

  it "normalizes exhausted probes to unknown and resumes an unsatisfiable core" ->
    cs = [[-1, 2], [3, 4], [3, -4], [-3, 4], [-3, -4]]
    r = scout_lucky_budget_case(6, cs, 1)
    expect(r[0]).to eq(0)
    expect(r[1]["unsat"]).to eq(true)

  it "retains the zero-budget unlimited behavior" ->
    r = scout_lucky_budget_case(6, [[-1, 2], [-3, 4], [-5, 6]], 0)
    expect(r[0]).to eq(1)
    expect(r[1]["sat"]).to eq(true)

  it "accepts an inexpensive model below a nonzero budget" ->
    r = scout_lucky_budget_case(6, [[-1, 2], [-3, 4], [-5, 6]], 48)
    expect(r[0]).to eq(1)
    expect(r[1]["sat"]).to eq(true)

  it "replays root consequences after budget exhaustion and repeated queries" ->
    cs = [[1], [-1, 2], [-3, 4]]
    s = ScoutLuckyBudgetFixture.new(6, cs, WASSAT_PROOF_NONE, 0)
    expect(s.lucky_probe(1)).to eq(0)
    expect(s.dlevel).to eq(0)
    a = s.solve_assuming([-2])
    expect(a["unsat"]).to eq(true)
    b = s.solve_assuming([])
    expect(b["sat"]).to eq(true)
    expect(scout_lucky_model_ok(cs, b["model"])).to eq(true)

spec_summary
