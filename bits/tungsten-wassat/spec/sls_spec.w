# SLS specs: model validity, determinism, and the one hard rule -- local
# search returns a model or nothing, never UNSAT.

use spec
use wassat

SLS_CHAIN = "p cnf 3 3\n1 0\n-1 2 0\n-2 3 0\n"
SLS_PHP22 = "p cnf 4 6\n1 2 0\n3 4 0\n-1 -3 0\n-2 -4 0\n1 3 0\n2 4 0\n"
SLS_UNSAT = "p cnf 2 4\n1 2 0\n1 -2 0\n-1 2 0\n-1 -2 0\n"
SLS_EMPTY = "p cnf 1 1\n0\n"

describe "Wassat SLS" ->

  context "models" ->
    it "finds and reports a valid model on satisfiable formulas" ->
      f = wassat_parse_cnf(SLS_CHAIN)
      r = wassat_sls_solve(f, 100000, 7)
      expect(r["sat"]).to eq(true)
      expect(wassat_model_satisfies?(f, r["model"])).to eq(true)
      f2 = wassat_parse_cnf(SLS_PHP22)
      r2 = wassat_sls_solve(f2, 100000, 7)
      expect(r2["sat"]).to eq(true)
      expect(wassat_model_satisfies?(f2, r2["model"])).to eq(true)

    it "is deterministic for a fixed seed" ->
      f = wassat_parse_cnf(SLS_PHP22)
      a = wassat_sls_solve(f, 100000, 42)
      b = wassat_sls_solve(f, 100000, 42)
      expect(a["sat"]).to eq(b["sat"])
      expect(a["flips"]).to eq(b["flips"])
      expect(a["model"].to_s).to eq(b["model"].to_s)

  context "never UNSAT" ->
    it "reports nothing (not UNSAT) on an unsatisfiable formula" ->
      f = wassat_parse_cnf(SLS_UNSAT)
      r = wassat_sls_solve(f, 20000, 3)
      expect(r["sat"]).to eq(false)
      expect(r["model"].size).to eq(0)
      expect(r["best_unsat"] >= 1).to eq(true)

    it "gives up immediately on an input empty clause" ->
      f = wassat_parse_cnf(SLS_EMPTY)
      r = wassat_sls_solve(f, 20000, 3)
      expect(r["sat"]).to eq(false)
      expect(r["flips"]).to eq(0)

  context "stats contract" ->
    it "reports flips, restarts, best_unsat, and the seed" ->
      f = wassat_parse_cnf(SLS_CHAIN)
      r = wassat_sls_solve(f, 100000, 11)
      expect(r["seed"]).to eq(11)
      expect(r["restarts"]).to eq(0)
      expect(r["flips"] >= 0).to eq(true)

spec_summary
