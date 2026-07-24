# Incremental solving (E4): assumptions as decisions, failed-assumption
# cores as certificates, query lifecycle, and the freeze contract.

use spec
use wassat
use ../../tungsten-wrat/lib/wrat

# 1 -> 2 -> 3 as implications, nothing asserted: satisfiable every way.
IMPL_CHAIN = "p cnf 3 2\n-1 2 0\n-2 3 0\n"

# Unit 1 asserted, then the chain.
CHAIN_UNIT = "p cnf 3 3\n1 0\n-1 2 0\n-2 3 0\n"

ALL_FOUR_INC = "p cnf 2 4\n1 2 0\n1 -2 0\n-1 2 0\n-1 -2 0\n"

PHP32_INC = "p cnf 6 9\n1 2 0\n3 4 0\n5 6 0\n-1 -3 0\n-1 -5 0\n-3 -5 0\n-2 -4 0\n-2 -6 0\n-4 -6 0\n"

BVE_SIMPLE_INC = "p cnf 3 2\n1 2 0\n-1 3 0\n"

-> inc_solver(text, mode)
  f = wassat_parse_cnf(text)
  Wassat.new(f["nvars"], f["clauses"], mode, 0)

describe "Wassat incremental solving" ->

  context "assumptions as decisions" ->
    it "solves SAT under assumptions and honors them in the model" ->
      s = inc_solver(IMPL_CHAIN, WASSAT_PROOF_NONE)
      r = s.solve_assuming([1])
      expect(r["sat"]).to eq(true)
      has1 = false
      has3 = false
      r["model"].each -> (l)
        has1 = true if l == 1
        has3 = true if l == 3
      expect(has1).to eq(true)
      expect(has3).to eq(true)

    it "returns UNSAT with a core when assumptions conflict with the formula" ->
      s = inc_solver(IMPL_CHAIN, WASSAT_PROOF_NONE)
      r = s.solve_assuming([1, 0 - 3])
      expect(r["unsat"]).to eq(true)
      expect(r["core"].size >= 1).to eq(true)
      # every core member is one of the given assumptions
      ok = true
      r["core"].each -> (l)
        ok = false unless l == 1 || l == 0 - 3
      expect(ok).to eq(true)

    it "cores a root-falsified assumption against an input unit" ->
      s = inc_solver(CHAIN_UNIT, WASSAT_PROOF_WRAT)
      r = s.solve_assuming([0 - 1])
      expect(r["unsat"]).to eq(true)
      expect(r["core"].size).to eq(1)
      expect(r["core"][0]).to eq(0 - 1)

    it "handles directly contradictory assumptions" ->
      s = inc_solver(IMPL_CHAIN, WASSAT_PROOF_WRAT)
      r = s.solve_assuming([2, 0 - 2])
      expect(r["unsat"]).to eq(true)
      expect(r["core"].size).to eq(2)

    it "rejects zero and out-of-range assumptions at the library boundary" ->
      s = inc_solver(IMPL_CHAIN, WASSAT_PROOF_NONE)
      expect(-> () s.solve_assuming([0])).to raise_error
      expect(-> () s.solve_assuming([99])).to raise_error

  context "the core is a certificate" ->
    it "logs the blocking clause as a final RUP addition the checker accepts" ->
      s = inc_solver(IMPL_CHAIN, WASSAT_PROOF_WRAT)
      r = s.solve_assuming([1, 0 - 3])
      expect(r["unsat"]).to eq(true)
      expect(r["proof"].size >= 1).to eq(true)
      # Not a refutation of the formula: the checker must accept every step
      # yet report that no empty clause was derived.
      text = "wrat 1\n" + r["proof"].join("\n") + "\n"
      check = wrat_verify(IMPL_CHAIN, text)
      expect(check["verified"]).to eq(false)
      expect(check["reason"].index("without deriving") != nil).to eq(true)
      expect(check["steps"]).to eq(r["proof"].size)

  context "query lifecycle" ->
    it "answers fresh queries after SAT and after assumption-UNSAT" ->
      s = inc_solver(IMPL_CHAIN, WASSAT_PROOF_NONE)
      a = s.solve_assuming([1, 0 - 3])
      expect(a["unsat"]).to eq(true)
      b = s.solve_assuming([1])
      expect(b["sat"]).to eq(true)
      c = s.solve_assuming([0 - 1])
      expect(c["sat"]).to eq(true)
      d = s.solve_assuming([3])
      expect(d["sat"]).to eq(true)

    it "keeps formula-level UNSAT terminal across later queries" ->
      s = inc_solver(ALL_FOUR_INC, WASSAT_PROOF_WRAT)
      first = s.solve
      expect(first["unsat"]).to eq(true)
      expect(first["core"].size).to eq(0)
      again = s.solve_assuming([1])
      expect(again["unsat"]).to eq(true)
      expect(again["core"].size).to eq(0)

  context "incremental vs cold agreement" ->
    it "matches cold solves across a family of related queries" ->
      queries = [[1], [0 - 1], [1, 4], [2, 4, 6], [1, 3], [0 - 2, 0 - 4]]
      s = inc_solver(PHP32_INC, WASSAT_PROOF_NONE)
      ok = true
      queries.each -> (q)
        inc = s.solve_assuming(q)
        cold = inc_solver(PHP32_INC, WASSAT_PROOF_NONE)
        cr = cold.solve_assuming(q)
        ok = false unless inc["sat"] == cr["sat"] && inc["unsat"] == cr["unsat"]
        if inc["sat"]
          f = wassat_parse_cnf(PHP32_INC)
          ok = false unless wassat_model_satisfies?(f, inc["model"])
          # assumptions hold in the model
          q.each -> (a)
            hit = false
            inc["model"].each -> (l)
              hit = true if l == a
            ok = false unless hit
      expect(ok).to eq(true)

  context "freeze contract with preprocessing" ->
    it "hard-errors on assumptions naming eliminated variables" ->
      # pure-literal elimination takes vars 2 and 3 (single-polarity) first
      art = wassat_preprocess(BVE_SIMPLE_INC, WASSAT_PROOF_NONE)
      expect(art["gone"][2] == 0).to eq(false)
      expect(-> () wassat_check_assumptions(art, [2])).to raise_error

    it "admits assumptions on frozen variables" ->
      f = wassat_parse_cnf(BVE_SIMPLE_INC)
      pre = WassatPreprocess.new(f["nvars"], f["clauses"], WASSAT_PROOF_NONE)
      pre.freeze(1)
      art = pre.run
      expect(wassat_check_assumptions(art, [1])).to eq(0)
      s = Wassat.new(f["nvars"], art["clauses"], WASSAT_PROOF_NONE, 0)
      s.seed_proof_ids(art["gids"], art["next_gid"])
      r = s.solve_assuming([1])
      expect(r["sat"]).to eq(true)

    it "validates assumptions before indexing the elimination map" ->
      art = wassat_preprocess(BVE_SIMPLE_INC, WASSAT_PROOF_NONE)
      expect(-> () wassat_check_assumptions(art, [0])).to raise_error
      expect(-> () wassat_check_assumptions(art, [99])).to raise_error

spec_summary
