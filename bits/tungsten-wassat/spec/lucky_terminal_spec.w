use spec
use ../lib/solver

-> lucky_terminal_fixture
  Wassat.new(2, [[1, 2], [1, -2], [-1, 2], [-1, -2]], WASSAT_PROOF_NONE, 0)

describe "Lucky root refutations remain terminal" ->
  it "preserves UNSAT across ordinary and budgeted solve calls" ->
    s = lucky_terminal_fixture()
    expect(s.lucky_probe).to eq(-1)
    [0, 1, 8].each -> (budget)
      r = s.solve_budget(budget)
      expect(r["status"]).to eq(-1)
      expect(r["model"].empty?).to eq(true)
      expect(r["core"].empty?).to eq(true)

  it "preserves formula UNSAT across assumption queries" ->
    s = lucky_terminal_fixture()
    expect(s.lucky_probe).to eq(-1)
    [[], [1], [-1], [2]].each -> (assumptions)
      r = s.solve_assuming(assumptions)
      expect(r["status"]).to eq(-1)
      expect(r["model"].empty?).to eq(true)
      expect(r["core"].empty?).to eq(true)

  it "preserves a consumed root conflict in the worker search entry" ->
    s = lucky_terminal_fixture()
    expect(s.lucky_probe).to eq(-1)
    expect(s.solve_loop(1)).to eq(-1)
    expect(s.solve_loop(0)).to eq(-1)

  it "keeps repeated dives and rearmed probes terminal" ->
    s = lucky_terminal_fixture()
    expect(s.lucky_probe).to eq(-1)
    expect(s.lucky_dive(1, 1)).to eq(-1)
    s.enable_lucky_once
    expect(s.lucky_probe).to eq(-1)

  it "keeps proof-producing repeated UNSAT results stable" ->
    s = Wassat.new(2, [[1, 2], [1, -2], [-1, 2], [-1, -2]], WASSAT_PROOF_DRAT, 0)
    first = s.solve
    expect(first["status"]).to eq(-1)
    expect(first["drat"].empty?).to eq(false)
    again = s.solve_assuming([])
    expect(again["status"]).to eq(-1)
    expect(again["drat"]).to eq(first["drat"])

spec_summary
