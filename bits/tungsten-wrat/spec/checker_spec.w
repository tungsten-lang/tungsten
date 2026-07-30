# Checker specs, built on well-known propositional test cases.
#
# The soundness examples matter more than the completeness ones: a checker
# that accepts everything would pass every "verifies a real proof" test and
# still be worthless.  Each positive case is therefore paired with a
# negative one.

use spec
use wrat

# --- fixtures ---------------------------------------------------------------

# (x) and (not x)
UNIT_CONTRADICTION = "p cnf 1 2\n1 0\n-1 0\n"

# Pigeonhole PHP(3,2): three pigeons, two holes. The classic UNSAT family,
# with exponential resolution lower bounds (Haken 1985).
PHP32 = "p cnf 6 9\n1 2 0\n3 4 0\n5 6 0\n-1 -3 0\n-1 -5 0\n-3 -5 0\n-2 -4 0\n-2 -6 0\n-4 -6 0\n"

# A refutation of PHP32 as emitted by CaDiCaL.
PHP32_DRAT = "-2 0\n1 0\n-3 0\n-5 0\n4 0\n6 0\n0\n"

# Satisfiable: a single two-literal clause.
SATISFIABLE = "p cnf 2 1\n1 2 0\n"

describe "Tungsten Wrat" ->

  context "RUP checking, unhinted (DRAT)" ->
    it "verifies the empty clause from a unit contradiction" ->
      r = wrat_verify(UNIT_CONTRADICTION, "0\n")
      expect(r["verified"]).to eq(true)
      expect(r["format"]).to eq("drat")

    it "verifies a real CaDiCaL refutation of pigeonhole PHP(3,2)" ->
      r = wrat_verify(PHP32, PHP32_DRAT)
      expect(r["verified"]).to eq(true)
      expect(r["steps"]).to eq(7)

  context "RUP checking, hinted (WRAT / LRAT)" ->
    it "verifies a hint chain naming the two unit clauses" ->
      r = wrat_verify(UNIT_CONTRADICTION, "3 0 1 2 0\n")
      expect(r["verified"]).to eq(true)
      expect(r["format"]).to eq("lrat")

    it "accepts the same chain behind a wrat header" ->
      r = wrat_verify(UNIT_CONTRADICTION, "wrat 1\n3 0 1 2 0\n")
      expect(r["verified"]).to eq(true)
      expect(r["format"]).to eq("wrat")

  context "soundness -- bad proofs must be rejected" ->
    it "rejects an empty clause claimed from a satisfiable formula" ->
      r = wrat_verify(SATISFIABLE, "0\n")
      expect(r["verified"]).to eq(false)

    it "rejects a hint chain that names a nonexistent clause" ->
      r = wrat_verify(UNIT_CONTRADICTION, "3 0 42 0\n")
      expect(r["verified"]).to eq(false)

    it "rejects a hint chain that does not reach a conflict" ->
      r = wrat_verify(UNIT_CONTRADICTION, "3 0 1 0\n")
      expect(r["verified"]).to eq(false)

    it "rejects a non-redundant intermediate clause" ->
      # (1) is not implied by the satisfiable formula (1 2)
      r = wrat_verify(SATISFIABLE, "1 0\n0\n")
      expect(r["verified"]).to eq(false)

    it "reports a proof that never derives the empty clause" ->
      r = wrat_verify(UNIT_CONTRADICTION, "1 0\n")
      expect(r["verified"]).to eq(false)

  context "deletion" ->
    it "honours DRAT content deletion" ->
      r = wrat_verify(UNIT_CONTRADICTION, "d 1 0\n0\n")
      # after deleting (1) the formula is satisfiable, so the empty
      # clause is no longer derivable
      expect(r["verified"]).to eq(false)

    it "honours LRAT id deletion" ->
      r = wrat_verify(UNIT_CONTRADICTION, "3 d 1 0\n4 0 1 2 0\n")
      expect(r["verified"]).to eq(false)

  context "streaming and packed certificates" ->
    it "packs hinted WRAT, preserves deletion semantics, and replays WRATB" ->
      text = "wrat 1\n3 1 0 1 0\n3 d 3 0\n4 0 1 2 0\n"
      info = wrat_packed_measure(wrat_scanner_for_text(text))
      packed = wrat_pack_into(wrat_scanner_for_text(text), info)
      expect(info["additions"]).to eq(2)
      expect(info["deletions"]).to eq(1)
      expect(packed.size < text.size).to eq(true)

      scanner = wrat_scanner_for_bytes(packed)
      formula = wrat_parse_cnf(UNIT_CONTRADICTION)
      r = wrat_checker_for(formula, scanner.format).check_stream(scanner)
      expect(r["verified"]).to eq(true)
      expect(scanner.format).to eq("wratb")
      expect(r["records"]).to eq(3)

    it "reports bounded record buffers and logical database storage" ->
      r = wrat_verify(UNIT_CONTRADICTION, "wrat 1\n3 0 1 2 0\n")
      expect(r["peak_record_literals"]).to eq(0)
      expect(r["peak_record_hints"]).to eq(2)
      expect(r["peak_live_clauses"]).to eq(3)
      expect(r["peak_live_literals"]).to eq(2)

    it "still parses trailing records after deriving the empty clause" ->
      bad_tail = "wrat 1\n3 0 1 2 0\ngarbage\n"
      expect(-> () wrat_verify(UNIT_CONTRADICTION, bad_tail)).to raise_error

  # The checker must trust the formula's OWN declared dimensions, independently
  # of any solver: it enforces exactly one `p cnf V C` header, the declared
  # clause count, and the declared variable bound. Otherwise a file declaring
  # zero (or fewer) clauses but carrying a contradiction could be VERIFIED.
  context "DIMACS strictness (independent of the solver)" ->
    it "rejects a header that declares fewer clauses than the file carries" ->
      # the bug shape: declares 0 clauses, actually contains a contradiction
      expect(-> () wrat_parse_cnf("p cnf 1 0\n1 0\n-1 0\n")).to raise_error
      expect(-> () wrat_parse_cnf("p cnf 1 1\n1 0\n-1 0\n")).to raise_error

    it "rejects a header that declares more clauses than the file carries" ->
      expect(-> () wrat_parse_cnf("p cnf 1 2\n1 0\n")).to raise_error

    it "enforces the declared variable bound instead of auto-expanding it" ->
      expect(-> () wrat_parse_cnf("p cnf 1 1\n2 0\n")).to raise_error

    it "requires exactly one p cnf header" ->
      expect(-> () wrat_parse_cnf("1 0\n")).to raise_error
      expect(-> () wrat_parse_cnf("p cnf 1 1\np cnf 1 1\n1 0\n")).to raise_error

    it "still accepts a well-formed formula with exact dimensions" ->
      f = wrat_parse_cnf("p cnf 2 2\n1 -2 0\n2 0\n")
      expect(f["nvars"]).to eq(2)
      expect(f["clauses"].size).to eq(2)

spec_summary
