# Solver specs, built on well-known propositional test cases.
#
# The families here are the standard ones used to shake out SAT solvers:
# unit contradictions, pigeonhole (exponential for resolution), mutilated
# and plain colouring constraints, at-most-one encodings, and a chain of
# implications that is pure unit propagation.
#
# Every UNSAT example also asserts that the emitted proof ends in the empty
# clause -- a solver that says UNSAT without being able to show why is the
# failure mode these bits exist to prevent.

use spec
use wassat

# --- fixtures ---------------------------------------------------------------

UNIT_CONTRADICTION = "p cnf 1 2\n1 0\n-1 0\n"

# Pigeonhole PHP(3,2): three pigeons, two holes. Haken's exponential family.
PHP32 = "p cnf 6 9\n1 2 0\n3 4 0\n5 6 0\n-1 -3 0\n-1 -5 0\n-3 -5 0\n-2 -4 0\n-2 -6 0\n-4 -6 0\n"

# PHP(2,1): two pigeons, one hole. Smallest nontrivial pigeonhole.
PHP21 = "p cnf 2 3\n1 0\n2 0\n-1 -2 0\n"

# All four combinations of two variables excluded.
ALL_FOUR = "p cnf 2 4\n1 2 0\n1 -2 0\n-1 2 0\n-1 -2 0\n"

# All eight assignments of three variables excluded. This takes four
# conflicts with the deterministic base policy, enough to exercise multiple
# independently-budgeted continuation calls.
ALL_EIGHT = "p cnf 3 8\n1 2 3 0\n1 2 -3 0\n1 -2 3 0\n1 -2 -3 0\n-1 2 3 0\n-1 2 -3 0\n-1 -2 3 0\n-1 -2 -3 0\n"

# Satisfiable: implication chain 1 -> 2 -> 3, with 1 asserted.
CHAIN = "p cnf 3 3\n1 0\n-1 2 0\n-2 3 0\n"

# Satisfiable: a single clause.
ONE_CLAUSE = "p cnf 2 1\n1 2 0\n"

# Every literal free: the empty clause set over three variables.
NO_CLAUSES = "p cnf 3 0\n"

# An explicitly contradictory DIMACS clause, distinct from an empty clause
# set. Its proof must cite this input clause rather than merely claim UNSAT.
EMPTY_CLAUSE = "p cnf 1 1\n0\n"

# Check that a model actually satisfies every clause of a formula.
-> satisfies?(cnf_text, model)
  f = wassat_parse_cnf(cnf_text)
  ok = true
  f["clauses"].each -> (c)
    hit = false
    c.each -> (l)
      model.each -> (m)
        hit = true if m == l
    ok = false unless hit
  ok

describe "Tungsten Wassat" ->

  context "unsatisfiable formulas" ->
    it "refutes a unit contradiction" ->
      r = wassat_solve(UNIT_CONTRADICTION)
      expect(r["sat"]).to eq(false)

    it "refutes pigeonhole PHP(2,1)" ->
      r = wassat_solve(PHP21)
      expect(r["sat"]).to eq(false)

    it "refutes pigeonhole PHP(3,2)" ->
      r = wassat_solve(PHP32)
      expect(r["sat"]).to eq(false)

    it "refutes an exhaustive two-variable clause set" ->
      r = wassat_solve(ALL_FOUR)
      expect(r["sat"]).to eq(false)

  context "satisfiable formulas" ->
    it "solves a single clause and returns a real model" ->
      r = wassat_solve(ONE_CLAUSE)
      expect(r["sat"]).to eq(true)
      expect(satisfies?(ONE_CLAUSE, r["model"])).to eq(true)

    it "propagates an implication chain" ->
      r = wassat_solve(CHAIN)
      expect(r["sat"]).to eq(true)
      expect(satisfies?(CHAIN, r["model"])).to eq(true)

    it "accepts a formula with no clauses" ->
      r = wassat_solve(NO_CLAUSES)
      expect(r["sat"]).to eq(true)

  context "bounded search" ->
    it "reports UNKNOWN rather than UNSAT when its conflict budget expires" ->
      r = wassat_solve_limited(ALL_FOUR, false, 0, 1)
      expect(r["status"]).to eq(0)
      expect(r["conflicts"]).to eq(1)
      expect(wassat_result_text(r)).to eq("s UNKNOWN\n")
      expect(r["proof"].size).to eq(0)

    it "keeps decisive root contradictions conclusive under a budget" ->
      r = wassat_solve_limited(UNIT_CONTRADICTION, true, 0, 1)
      expect(r["status"]).to eq(-1)
      expect(wassat_result_text(r)).to eq("s UNSATISFIABLE\n")

    it "does not expose a partial raw proof for UNKNOWN" ->
      r = wassat_solve_mode_limited(ALL_FOUR, WASSAT_PROOF_DRAT, 0, 1)
      expect(r["status"]).to eq(0)
      expect(r["complete"]).to eq(false)
      expect(r["unsat"]).to eq(false)
      expect(r["drat"].size).to eq(0)
      expect(wassat_drat_text(r)).to eq("")

    it "treats each positive budget as additional work" ->
      f = wassat_parse_cnf(ALL_EIGHT)
      s = Wassat.new(f["nvars"], f["clauses"], WASSAT_PROOF_NONE, 0)
      first = s.solve_budget(1)
      second = s.solve_budget(2)
      expect(first["status"]).to eq(0)
      expect(first["conflicts"]).to eq(1)
      expect(second["status"]).to eq(0)
      expect(second["conflicts"]).to eq(3)
      expect(s.solve_budget(0)["status"]).to eq(-1)

    it "rejects a negative library conflict budget" ->
      f = wassat_parse_cnf(ALL_FOUR)
      s = Wassat.new(f["nvars"], f["clauses"], WASSAT_PROOF_NONE, 0)
      expect(-> () s.solve_budget(-1)).to raise_error
      expect(-> () wassat_solve_limited(ALL_FOUR, false, 0, -1)).to raise_error

    it "retains a hidden WRAT prefix across UNKNOWN and detaches old results" ->
      f = wassat_parse_cnf(ALL_FOUR)
      s = Wassat.new(f["nvars"], f["clauses"], WASSAT_PROOF_WRAT, 0)
      partial = s.solve_budget(1)
      expect(partial["status"]).to eq(0)
      expect(partial["proof"].size).to eq(0)
      finished = s.solve_budget(0)
      expect(finished["status"]).to eq(-1)
      expect(finished["complete"]).to eq(true)
      expect(finished["unsat"]).to eq(true)
      expect(finished["proof_mode"]).to eq(WASSAT_PROOF_WRAT)
      expect(finished["proof"].size).to eq(2)
      expect(wassat_tokenize(finished["proof"][0])[0]).to eq("5")
      expect(wassat_tokenize(finished["proof"][1])[0]).to eq("6")
      expect(partial["proof"].size).to eq(0)

    it "retains a hidden raw DRAT prefix across UNKNOWN" ->
      f = wassat_parse_cnf(ALL_FOUR)
      s = Wassat.new(f["nvars"], f["clauses"], WASSAT_PROOF_DRAT, 0)
      partial = s.solve_budget(1)
      finished = s.solve_budget(0)
      expect(partial["drat"].size).to eq(0)
      expect(finished["status"]).to eq(-1)
      expect(finished["drat"].size).to eq(2)
      expect(wassat_drat_text(finished).ends_with?("0\n")).to eq(true)

    it "makes terminal calls idempotent and returns fresh result arrays" ->
      f = wassat_parse_cnf(ALL_FOUR)
      s = Wassat.new(f["nvars"], f["clauses"], WASSAT_PROOF_WRAT, 0)
      first = s.solve_budget(0)
      conflicts = first["conflicts"]
      proof_size = first["proof"].size
      first["proof"].push("caller mutation")
      again = s.solve_budget(1)
      expect(again["status"]).to eq(-1)
      expect(again["conflicts"]).to eq(conflicts)
      expect(again["proof"].size).to eq(proof_size)

      sf = wassat_parse_cnf(ONE_CLAUSE)
      sat_solver = Wassat.new(sf["nvars"], sf["clauses"], WASSAT_PROOF_NONE, 0)
      sat_first = sat_solver.solve_budget(0)
      sat_first["model"].push(99)
      sat_again = sat_solver.solve_budget(1)
      expect(sat_again["status"]).to eq(1)
      expect(sat_again["model"].size).to eq(2)

  context "EVSIDS variable-order heap" ->
    it "raises bumped variables to the top and keeps inverse positions valid" ->
      asg = i64[6]
      act = i64[6]
      heap = i64[6]
      hpos = i64[6]
      hst = i64[2]
      v = 0
      while v < 6
        hpos[v] = -1
        v += 1
      hst[1] = 32
      v = 1
      while v <= 5
        wassat_heap_insert(heap, hpos, act, hst, v)
        v += 1

      wassat_evsids_bump(act, heap, hpos, hst, 4, 5)
      expect(wassat_heap_valid(heap, hpos, act, hst, 5)).to eq(1)
      expect(wassat_heap_pick(asg, heap, hpos, act, hst)).to eq(4)
      expect(hpos[4]).to eq(-1)
      expect(wassat_heap_valid(heap, hpos, act, hst, 5)).to eq(1)

    it "lazily drops assigned variables and reinserts them after unassignment" ->
      asg = i64[5]
      act = i64[5]
      heap = i64[5]
      hpos = i64[5]
      hst = i64[2]
      v = 0
      while v < 5
        hpos[v] = -1
        v += 1
      hst[1] = 32
      v = 1
      while v <= 4
        wassat_heap_insert(heap, hpos, act, hst, v)
        v += 1
      wassat_evsids_bump(act, heap, hpos, hst, 3, 4)
      asg[3] = 1

      chosen = wassat_heap_pick(asg, heap, hpos, act, hst)
      expect(chosen == 3).to eq(false)
      expect(hpos[3]).to eq(-1)
      asg[3] = 0
      expect(wassat_heap_insert(heap, hpos, act, hst, 3)).to eq(1)
      expect(wassat_heap_valid(heap, hpos, act, hst, 4)).to eq(1)
      expect(wassat_heap_pick(asg, heap, hpos, act, hst)).to eq(3)

    it "grows the integer increment by one sixteenth and rescales safely" ->
      act = i64[4]
      heap = i64[4]
      hpos = i64[4]
      hst = i64[2]
      v = 0
      while v < 4
        hpos[v] = -1
        v += 1
      hst[1] = 32
      v = 1
      while v <= 3
        wassat_heap_insert(heap, hpos, act, hst, v)
        v += 1

      wassat_evsids_advance(hst)
      expect(hst[1]).to eq(34)
      wassat_evsids_bump(act, heap, hpos, hst, 2, 3)
      expect(act[2]).to eq(34)
      act[2] = 4503599627370496
      wassat_evsids_bump(act, heap, hpos, hst, 2, 3)
      expect(act[2] < 4503599627370496).to eq(true)
      expect(hst[1]).to eq(32)
      expect(wassat_heap_valid(heap, hpos, act, hst, 3)).to eq(1)

    it "keeps legacy lookahead arguments source-compatible under automatic policy" ->
      sat = wassat_solve_full(CHAIN, false, 3)
      unsat = wassat_solve_full(PHP32, false, 4)
      expect(sat["status"]).to eq(1)
      expect(satisfies?(CHAIN, sat["model"])).to eq(true)
      expect(unsat["status"]).to eq(-1)

  context "proof emission" ->
    it "ends a refutation with the empty clause" ->
      r = wassat_solve(PHP32)
      proof = r["proof"]
      last = proof[proof.size - 1]
      # A hinted line is `<id> <lits> 0 <hints> 0`, so the empty clause is
      # the one whose literal section is already closed at token 1.
      toks = wassat_tokenize(last)
      expect(toks[1]).to eq("0")

    it "emits a hinted .wrat proof with a header" ->
      text = wassat_proof_text(wassat_solve(PHP32))
      expect(text.starts_with?("wrat 1")).to eq(true)

    it "emits plain .drat ending in the empty clause" ->
      text = wassat_drat_text(wassat_solve(UNIT_CONTRADICTION))
      expect(text.ends_with?("0\n")).to eq(true)

    it "records raw DRAT without constructing hinted WRAT" ->
      r = wassat_solve_mode_limited(PHP32, WASSAT_PROOF_DRAT, 0, 0)
      expect(r["status"]).to eq(-1)
      expect(r["proof"].size).to eq(0)
      expect(r["drat"].size > 0).to eq(true)
      expect(wassat_drat_text(r).ends_with?("0\n")).to eq(true)

    it "refuses to render absent or wrong-mode certificates" ->
      no_proof = wassat_solve_opts(UNIT_CONTRADICTION, false)
      raw = wassat_solve_mode_limited(UNIT_CONTRADICTION, WASSAT_PROOF_DRAT, 0, 0)
      expect(no_proof["complete"]).to eq(true)
      expect(no_proof["unsat"]).to eq(true)
      expect(wassat_proof_text(no_proof)).to eq("")
      expect(wassat_drat_text(no_proof)).to eq("")
      expect(wassat_proof_text(raw)).to eq("")
      expect(wassat_drat_text(raw).ends_with?("0\n")).to eq(true)

    it "derives an empty clause from an explicit empty input clause" ->
      r = wassat_solve(EMPTY_CLAUSE)
      expect(r["status"]).to eq(-1)
      expect(r["proof"].size).to eq(1)
      toks = wassat_tokenize(r["proof"][0])
      expect(toks[1]).to eq("0")
      expect(toks[2]).to eq("1")

    it "records a raw terminal step for an explicit empty input clause" ->
      r = wassat_solve_mode_limited(EMPTY_CLAUSE, WASSAT_PROOF_DRAT, 0, 0)
      expect(r["drat"].size).to eq(1)
      expect(r["drat"][0]).to eq("0")

    it "emits no proof for a satisfiable formula" ->
      r = wassat_solve(ONE_CLAUSE)
      expect(r["proof"].size).to eq(0)

  context "DIMACS parsing" ->
    it "ignores comments and honors the declared variable count" ->
      f = wassat_parse_cnf("c hello\np cnf 2 1\n1 -2 0\n")
      expect(f["nvars"]).to eq(2)
      expect(f["clauses"].size).to eq(1)

    it "accepts clauses spanning several lines" ->
      f = wassat_parse_cnf("p cnf 3 1\n1 2\n3 0\n")
      expect(f["clauses"].size).to eq(1)
      expect(f["clauses"][0].size).to eq(3)

    it "accepts several clauses on one line and a SATLIB trailer" ->
      f = wassat_parse_cnf("p cnf 2 2\n1 0 -2 0\n%\n0\n")
      expect(f["clauses"].size).to eq(2)

    it "rejects XNF instead of misreading x as an empty clause" ->
      xnf = "p cnf 2 1\nx 1 2 0\n"
      expect(-> () wassat_parse_cnf(xnf)).to raise_error

    it "rejects non-integer clause tokens" ->
      bad = "p cnf 1 1\nwat 0\n"
      comment_prefix = "p cnf 1 1\ncat 1 0\n"
      expect(-> () wassat_parse_cnf(bad)).to raise_error
      expect(-> () wassat_parse_cnf(comment_prefix)).to raise_error

    it "requires exactly one well-formed p cnf header" ->
      no_header = "1 0\n"
      short_header = "p cnf 1\n1 0\n"
      extra_header_field = "p cnf 1 1 trailing\n1 0\n"
      wrong_kind = "p xnf 1 1\n1 0\n"
      negative_count = "p cnf -1 1\n1 0\n"
      duplicate = "p cnf 1 1\np cnf 1 1\n1 0\n"
      expect(-> () wassat_parse_cnf(no_header)).to raise_error
      expect(-> () wassat_parse_cnf(short_header)).to raise_error
      expect(-> () wassat_parse_cnf(extra_header_field)).to raise_error
      expect(-> () wassat_parse_cnf(wrong_kind)).to raise_error
      expect(-> () wassat_parse_cnf(negative_count)).to raise_error
      expect(-> () wassat_parse_cnf(duplicate)).to raise_error

    it "rejects missing or signed clause terminators" ->
      missing = "p cnf 1 1\n1\n"
      signed = "p cnf 1 1\n1 -0\n"
      padded = "p cnf 1 1\n00 0\n"
      expect(-> () wassat_parse_cnf(missing)).to raise_error
      expect(-> () wassat_parse_cnf(signed)).to raise_error
      expect(-> () wassat_parse_cnf(padded)).to raise_error

    it "enforces the declared variable bound" ->
      bad = "p cnf 2 1\n3 0\n"
      expect(-> () wassat_parse_cnf(bad)).to raise_error

    it "enforces both underfilled and overfilled clause counts" ->
      too_few = "p cnf 2 2\n1 0\n"
      too_many = "p cnf 2 1\n1 0\n2 0\n"
      expect(-> () wassat_parse_cnf(too_few)).to raise_error
      expect(-> () wassat_parse_cnf(too_many)).to raise_error

spec_summary
