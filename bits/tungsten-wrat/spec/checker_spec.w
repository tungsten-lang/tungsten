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

spec_summary
