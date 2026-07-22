# Preprocessing specs: the four techniques, their proof obligations, the
# elimination stack, and the edge-case traps from the Phase 1 checklist.
#
# The independent checker is imported from its own bit for the certificate
# regressions: every UNSAT fixture's proof is replayed by tungsten-wrat
# in-process. The two bits still share no parser or checking code — the
# spec merely runs both.

use spec
use wassat
use ../../tungsten-wrat/lib/wrat

# Probing target: assuming x propagates a and -a, so -x is implied; y then
# follows from (x | y).
PROBE_FAILS = "p cnf 3 3\n-1 2 0\n-1 -2 0\n1 3 0\n"

# a == b through an SCC of the binary implication graph, plus pressure that
# keeps the instance satisfiable.
EQUIV_AB = "p cnf 3 4\n-1 2 0\n-2 1 0\n1 3 0\n-2 -3 0\n"

# x => y => -x and -x => z => x: the implication graph puts x and -x in one
# SCC, which refutes the formula outright.
EQUIV_CONTRA = "p cnf 3 4\n-1 2 0\n-2 -1 0\n1 3 0\n-3 1 0\n"

# (a|b) subsumes (a|b|c); (a|b) also strengthens (-a|b|c) to (b|c).
SUBSUME = "p cnf 3 3\n1 2 0\n1 2 3 0\n-1 2 3 0\n"

# v resolves away: (v|a)(-v|b) => (a|b). One resolvent replaces two clauses.
BVE_SIMPLE = "p cnf 3 2\n1 2 0\n-1 3 0\n"

# (v|a|b)(-v|-a|-b): the only resolvent is a tautology, so eliminating v
# must add nothing -- counting or emitting it would be a bug either way.
# Ternary on purpose: binary clauses would be substituted away first.
BVE_TAUT = "p cnf 3 2\n1 2 3 0\n-1 -2 -3 0\n"

PHP32_PRE = "p cnf 6 9\n1 2 0\n3 4 0\n5 6 0\n-1 -3 0\n-1 -5 0\n-3 -5 0\n-2 -4 0\n-2 -6 0\n-4 -6 0\n"

DUPLICATES = "p cnf 3 3\n1 1 2 0\n-1 3 3 0\n-2 -3 0\n"

# Helper-lifetime regression: 1 == 2 through an SCC, then the ternary blocks
# force 1 true and 2 false, so the formula is UNSAT and every (-2 ...) clause
# is rewritten citing the equivalence helper (2 | -1). A bug once rewrote the
# helpers themselves into tautologies and deleted them while later rewritten
# clauses still cited their ids — both certificate dialects failed the
# independent checkers ("step N is not redundant").
HELPER_LIFETIME = "p cnf 4 10\n-1 2 0\n-2 1 0\n1 3 4 0\n1 3 -4 0\n1 -3 4 0\n1 -3 -4 0\n-2 3 4 0\n-2 3 -4 0\n-2 -3 4 0\n-2 -3 -4 0\n"

describe "Wassat preprocessing" ->

  context "failed-literal probing" ->
    it "derives the negation of a failed literal and cascades it" ->
      art = wassat_preprocess(PROBE_FAILS, WASSAT_PROOF_WRAT)
      expect(art["status"]).to eq(0)
      expect(art["stats"]["probes_failed"] >= 1).to eq(true)
      r = wassat_solve_preprocessed(PROBE_FAILS, WASSAT_PROOF_WRAT, 0, 0)
      expect(r["sat"]).to eq(true)
      f = wassat_parse_cnf(PROBE_FAILS)
      expect(wassat_model_satisfies?(f, r["model"])).to eq(true)

    it "runs no probes when every variable is already assigned" ->
      art = wassat_preprocess("p cnf 1 1\n1 0\n", WASSAT_PROOF_WRAT)
      expect(art["stats"]["probes"]).to eq(0)

  context "equivalent-literal substitution" ->
    it "substitutes an SCC through its representative" ->
      art = wassat_preprocess(EQUIV_AB, WASSAT_PROOF_WRAT)
      expect(art["stats"]["vars_substituted"] >= 1).to eq(true)
      r = wassat_solve_preprocessed(EQUIV_AB, WASSAT_PROOF_WRAT, 0, 0)
      expect(r["sat"]).to eq(true)
      f = wassat_parse_cnf(EQUIV_AB)
      expect(wassat_model_satisfies?(f, r["model"])).to eq(true)

    it "refutes on the spot when x and -x share an SCC" ->
      art = wassat_preprocess(EQUIV_CONTRA, WASSAT_PROOF_WRAT)
      expect(art["status"]).to eq(-1)
      last = art["wrat"][art["wrat"].size - 1]
      toks = wassat_tokenize(last)
      expect(toks[1]).to eq("0")
      plain = wassat_solve(EQUIV_CONTRA)
      expect(plain["sat"]).to eq(false)

  context "subsumption and strengthening" ->
    it "deletes subsumed clauses and strengthens self-subsumed ones" ->
      art = wassat_preprocess(SUBSUME, WASSAT_PROOF_WRAT)
      expect(art["stats"]["clauses_subsumed"] >= 1).to eq(true)
      expect(art["stats"]["clauses_strengthened"] >= 1).to eq(true)
      r = wassat_solve_preprocessed(SUBSUME, WASSAT_PROOF_WRAT, 0, 0)
      expect(r["sat"]).to eq(true)
      f = wassat_parse_cnf(SUBSUME)
      expect(wassat_model_satisfies?(f, r["model"])).to eq(true)

  context "bounded variable elimination" ->
    it "eliminates a variable and reconstructs its value in the model" ->
      art = wassat_preprocess(BVE_SIMPLE, WASSAT_PROOF_WRAT)
      expect(art["stats"]["vars_eliminated"] >= 1).to eq(true)
      r = wassat_solve_preprocessed(BVE_SIMPLE, WASSAT_PROOF_WRAT, 0, 0)
      expect(r["sat"]).to eq(true)
      f = wassat_parse_cnf(BVE_SIMPLE)
      expect(wassat_model_satisfies?(f, r["model"])).to eq(true)

    it "skips tautological resolvents without counting or emitting them" ->
      art = wassat_preprocess(BVE_TAUT, WASSAT_PROOF_WRAT)
      expect(art["stats"]["vars_eliminated"] >= 1).to eq(true)
      # both originals deleted, the tautological resolvent never added
      kept = 0
      art["clauses"].each -> (c)
        kept += 1
      expect(kept).to eq(0)
      r = wassat_solve_preprocessed(BVE_TAUT, WASSAT_PROOF_WRAT, 0, 0)
      expect(r["sat"]).to eq(true)
      f = wassat_parse_cnf(BVE_TAUT)
      expect(wassat_model_satisfies?(f, r["model"])).to eq(true)

    it "leaves no live clause mentioning an eliminated variable" ->
      art = wassat_preprocess(SUBSUME, WASSAT_PROOF_WRAT)
      gone = art["gone"]
      ok = true
      art["clauses"].each -> (c)
        c.each -> (l)
          ok = false unless gone[l.abs] == 0
      expect(ok).to eq(true)

  context "degenerate inputs" ->
    it "accepts the empty formula as trivially satisfiable" ->
      r = wassat_solve_preprocessed("p cnf 3 0\n", WASSAT_PROOF_WRAT, 0, 0)
      expect(r["sat"]).to eq(true)

    it "refutes an explicit empty input clause before any search" ->
      art = wassat_preprocess("p cnf 1 1\n0\n", WASSAT_PROOF_WRAT)
      expect(art["status"]).to eq(-1)
      toks = wassat_tokenize(art["wrat"][0])
      expect(toks[1]).to eq("0")
      expect(toks[2]).to eq("1")

    it "handles duplicated literals inside input clauses" ->
      r = wassat_solve_preprocessed(DUPLICATES, WASSAT_PROOF_WRAT, 0, 0)
      expect(r["sat"]).to eq(true)
      f = wassat_parse_cnf(DUPLICATES)
      expect(wassat_model_satisfies?(f, r["model"])).to eq(true)

    it "rejects implausible header declarations loudly" ->
      expect(-> () wassat_parse_cnf("p cnf 99999999999 1\n1 0\n")).to raise_error
      expect(-> () wassat_parse_cnf("p cnf 2 99999999999\n1 0\n")).to raise_error

    it "accepts tab-separated DIMACS" ->
      f = wassat_parse_cnf("p cnf 2 1\n1\t-2\t0\n")
      expect(f["clauses"].size).to eq(1)
      expect(f["clauses"][0].size).to eq(2)

  context "freeze set" ->
    it "never eliminates or substitutes a frozen variable" ->
      f = wassat_parse_cnf(EQUIV_AB)
      pre = WassatPreprocess.new(f["nvars"], f["clauses"], WASSAT_PROOF_WRAT)
      pre.freeze(1)
      pre.freeze(2)
      art = pre.run
      gone = art["gone"]
      expect(gone[1]).to eq(0)
      expect(gone[2]).to eq(0)

  context "output integrity" ->
    it "rejects a corrupted model against the original formula" ->
      f = wassat_parse_cnf(PROBE_FAILS)
      r = wassat_solve_preprocessed(PROBE_FAILS, WASSAT_PROOF_NONE, 0, 0)
      bad = []
      r["model"].each -> (l)
        bad.push(0 - l)
      expect(wassat_model_satisfies?(f, bad)).to eq(false)

  context "certificates" ->
    it "refutes PHP(3,2) through preprocessing with a hinted prefix" ->
      r = wassat_solve_preprocessed(PHP32_PRE, WASSAT_PROOF_WRAT, 0, 0)
      expect(r["unsat"]).to eq(true)
      expect(r["proof"].size > 0).to eq(true)
      last = r["proof"][r["proof"].size - 1]
      toks = wassat_tokenize(last)
      expect(toks[1]).to eq("0")

    it "substitution certificates survive helper deletion ordering" ->
      r = wassat_solve_preprocessed(HELPER_LIFETIME, WASSAT_PROOF_WRAT, 0, 0)
      expect(r["unsat"]).to eq(true)
      expect(r["pre"]["stats"]["vars_substituted"] >= 1).to eq(true)
      check = wrat_verify(HELPER_LIFETIME, wassat_proof_text(r))
      expect(check["verified"]).to eq(true)

    it "every UNSAT fixture certificate verifies under the independent checker" ->
      fixtures = [EQUIV_CONTRA, PHP32_PRE, HELPER_LIFETIME, "p cnf 1 1\n0\n"]
      ok = true
      fixtures.each -> (text)
        r = wassat_solve_preprocessed(text, WASSAT_PROOF_WRAT, 0, 0)
        if r["unsat"]
          check = wrat_verify(text, wassat_proof_text(r))
          ok = false unless check["verified"] == true
        else
          ok = false
      expect(ok).to eq(true)

    it "agrees with the unpreprocessed solver across the fixture set" ->
      fixtures = [PROBE_FAILS, EQUIV_AB, EQUIV_CONTRA, SUBSUME, BVE_SIMPLE, BVE_TAUT, DUPLICATES, PHP32_PRE]
      ok = true
      fixtures.each -> (text)
        plain = wassat_solve_opts(text, false)
        prep = wassat_solve_preprocessed(text, WASSAT_PROOF_NONE, 0, 0)
        ok = false unless plain["status"] == prep["status"]
        if prep["status"] == 1
          f = wassat_parse_cnf(text)
          ok = false unless wassat_model_satisfies?(f, prep["model"])
      expect(ok).to eq(true)

spec_summary
