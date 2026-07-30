# SLS specs: model validity, determinism, and the one hard rule -- local
# search returns a model or nothing, never UNSAT.

use spec
use wassat

SLS_CHAIN = "p cnf 3 3\n1 0\n-1 2 0\n-2 3 0\n"
SLS_PHP22 = "p cnf 4 6\n1 2 0\n3 4 0\n-1 -3 0\n-2 -4 0\n1 3 0\n2 4 0\n"
SLS_UNSAT = "p cnf 2 4\n1 2 0\n1 -2 0\n-1 2 0\n-1 -2 0\n"
SLS_EMPTY = "p cnf 1 1\n0\n"

# Interpreter-safe flat mirror builder. The production native parser is a
# compiled-only ccall; these unit tests need the identical typed layout without
# turning the whole SLS spec into a compiled/process suite.
-> sls_test_flat(text)
  boxed = wassat_parse_cnf(text)
  ncl = boxed["clauses"].size
  nlits = 0
  boxed["clauses"].each -> (c)
    nlits += c.size
  fla = i64[nlits]
  fcs = i64[ncl]
  fcl = i64[ncl]
  ci = 0
  pos = 0
  boxed["clauses"].each -> (c)
    fcs[ci] = pos
    fcl[ci] = c.size
    c.each -> (l)
      fla[pos] = l
      pos += 1
    ci += 1
  { "nvars": boxed["nvars"], "clauses": boxed["clauses"],
    "flat_lits": fla, "flat_offs": fcs, "flat_lens": fcl,
    "flat_ncl": ncl, "flat_nlits": nlits }

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

  context "native construction cancellation" ->
    it "returns before exact-sized clause mirrors on a pre-raised stop" ->
      # Exact ncl-sized mirrors make the old `ci = ncl` pseudo-break visible:
      # the same iteration continued into fcs[ncl]/fcl[ncl].
      fla = i64[1]
      fcs = i64[1]
      fcl = i64[1]
      fla[0] = 1
      fcs[0] = 0
      fcl[0] = 1
      stop = i64[1]
      z = wassat_stop_cancel(stop)
      stamp = i64[8]
      size_pm = i64[6]
      size_pm[0] = 1
      size_pm[1] = 2
      wassat_sls_flat_size(fla, fcs, fcl, stamp, size_pm, stop)
      expect(size_pm[5]).to eq(1)
      expect(size_pm[2]).to eq(0)
      expect(size_pm[3]).to eq(0)

      ofla = i64[1]
      ofcs = i64[1]
      ofcl = i64[1]
      fill_pm = i64[6]
      fill_pm[0] = 1
      fill_pm[1] = 2
      wassat_sls_flat_fill(
        fla, fcs, fcl, stamp, ofla, ofcs, ofcl, fill_pm, stop
      )
      expect(fill_pm[5]).to eq(1)
      expect(fill_pm[2]).to eq(0)
      expect(fill_pm[3]).to eq(0)

  context "best-snapshot handoff" ->
    it "exports the true best assignment and its exact unsatisfied fringe" ->
      f = sls_test_flat(SLS_UNSAT)
      s = WassatSls.new(f["nvars"], [], nil, f)
      r = s.solve(2000, 3)
      expected = []
      v = 1
      while v <= f["nvars"]
        expected.push(r["best_bits"][v] == 1 ? v : 0 - v)
        v += 1
      expect(r["assign"]).to eq(expected)
      expect(r["best_assign"]).to eq(expected)

      mutable = i64[f["nvars"] + 1]
      meta = i64[2]
      wassat_sls_mark_fringe(
        f["flat_lits"], f["flat_offs"], f["flat_lens"], f["flat_ncl"],
        r["best_bits"], mutable, meta
      )
      expect(meta[0]).to eq(r["best_unsat"])
      expect(meta[1] > 0).to eq(true)

    it "resumes bit-identically from a fixed prefix" ->
      f = sls_test_flat(SLS_UNSAT)
      straight = WassatSls.new(f["nvars"], [], nil, f)
      a = straight.solve(2000, 3)
      staged = WassatSls.new(f["nvars"], [], nil, f)
      z = staged.solve(100, 3)
      b = staged.continue_solve(2000, 3)
      expect(b["flips"]).to eq(a["flips"])
      expect(b["best_unsat"]).to eq(a["best_unsat"])
      expect(b["best_assign"]).to eq(a["best_assign"])

  context "bounded frozen-fringe repair" ->
    it "grows only failed-core coordinates and returns a verified model" ->
      f = sls_test_flat(SLS_CHAIN)
      art = wassat_raw_artifact(f, f["nvars"])
      bits = i64[f["nvars"] + 1]
      best = [-1, -2, -3]
      stop = i64[4]
      r = wassat_sls_frozen_repair(f, art, bits, best, 1, stop, 3840)
      expect(r["attempted"]).to eq(true)
      expect(r["sat"]).to eq(true)
      expect(r["core_rounds"] > 0).to eq(true)
      expect(r["relaxed"]).to eq(3)
      expect(r["conflicts"] <= 3840).to eq(true)
      expect(wassat_model_satisfies?(f, r["model"])).to eq(true)

    it "keeps formula-level UNSAT non-decisive in the model-only lane" ->
      f = sls_test_flat(SLS_UNSAT)
      art = wassat_raw_artifact(f, f["nvars"])
      bits = i64[f["nvars"] + 1]
      stop = i64[4]
      r = wassat_sls_frozen_repair(f, art, bits, [-1, -2], 1, stop, 3840)
      expect(r["attempted"]).to eq(true)
      expect(r["sat"]).to eq(false)
      expect(r["model"].empty?).to eq(true)
      expect(wassat_stop_requested?(stop)).to eq(false)

  context "bounded race lifecycle and memory" ->
    it "counts retained scout, race, preprocessor, SLS, and repair arenas" ->
      f = sls_test_flat(SLS_CHAIN)
      art = wassat_raw_artifact(f, f["nvars"])
      race = wassat_race_build(
        f["nvars"], art, 1, f, nil, 0, 2, 1, 2, 1, 1
      )
      expect(race["resident_cdcl_arenas"]).to eq(5)
      expect(race["resident_sls_arenas"]).to eq(2)
      expect(race["resident_preprocess_arenas"]).to eq(3)
      expect(race["repair_cdcl_arenas"]).to eq(1)

spec_summary
