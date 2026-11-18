# spec: compiled -- native parser mirrors are explicitly freed by consuming load
use spec
use ../lib/solver
use ../lib/preprocess

+ SharedFlatArenaFixture < Wassat
  ro :arena, :asize, :aused, :acap, :ccap, :ncl

  # Exercise the huge-input branch using small physical arrays.
  -> consume_flat_input?(art, lean)
    !lean && art["raw"] == true && art.has_key?("formula_ref")

-> shared_flat_fixture(text)
  formula = wassat_parse_cnf_native(text)
  art = wassat_raw_artifact(formula, formula["nvars"])
  s = SharedFlatArenaFixture.new(formula["nvars"], [], WASSAT_PROOF_NONE, 0, true)
  s.load_flat(art)
  [s, formula, art]

describe "Compact shared raw arena" ->
  it "shares typed literals and interleaved metadata with model verification" ->
    text = "p cnf 4 4\n-1 0\n1 2 0\n-2 3 4 0\n-3 0\n"
    f = shared_flat_fixture(text)
    s = f[0]; formula = f[1]; art = f[2]
    expect(formula["flat_lits_bits"]).to eq(32)
    expect(art["arena_consumed"]).to eq(true)
    expect(formula["flat_lens"].size).to eq(0)
    expect([s.ncl, s.asize, s.aused]).to eq([4, 15, 11])
    expect([s.arena[0], s.arena[1], s.arena[2]]).to eq([0, 1, -1])
    expect(wassat_model_satisfies?(formula, [-1, 2, -3, 4])).to eq(true)
    expect(wassat_model_satisfies?(formula, [-1, 2, -3, -4])).to eq(false)
    r = s.solve
    expect(r["status"]).to eq(1)
    expect(wassat_model_satisfies?(formula, r["model"])).to eq(true)
    expect(wassat_model_satisfies?(wassat_parse_cnf(text), r["model"])).to eq(true)
    expect(-> () Wassat.from_flat(4, art, 0)).to raise_error

  it "preserves late contradictory units and empty clauses" ->
    ["p cnf 1 4\n1 0\n1 0\n1 0\n-1 0\n", "p cnf 1 2\n1 0\n0\n"].each -> (text)
      f = shared_flat_fixture(text)
      expect(f[0].solve["status"]).to eq(-1)
      expect(wassat_model_satisfies?(f[1], [1])).to eq(false)
      expect(wassat_model_satisfies?(f[1], [-1])).to eq(false)

  it "retains shared descriptor aliases when the arena grows" ->
    f = shared_flat_fixture("p cnf 2 1\n1 -2 0\n")
    s = f[0]
    old_cap = s.acap
    s.grow_arena(old_cap + 1)
    expect(f[1]["flat_lits"].size).to eq(s.acap + s.ccap)
    expect(s.acap > old_cap).to eq(true)
    expect(wassat_model_satisfies?(f[1], [1, 2])).to eq(true)
    expect(wassat_model_satisfies?(f[1], [-1, 2])).to eq(false)

spec_summary
