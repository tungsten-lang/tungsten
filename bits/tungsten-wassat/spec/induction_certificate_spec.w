# spec: compiled -- native propagation shell checks the concluding conflict
use spec
use ../lib/wassat

-> induction_fixture(complete)
  rows = ["-1 -2 0", "-3 -4 0", "-5 -6 1 3 0", "-5 -6 1 4 0",
    "-5 -6 2 3 0", "-7 -8 5 0", "-7 -8 6 0", "7 0", "8 0"]
  rows.push("-5 -6 2 4 0") if complete
  wassat_parse_cnf_native("p cnf 8 [rows.size]\n" + rows.join("\n") + "\n")

describe "Local induction certificates" ->
  it "derives an impossible target from two blocked predecessors" ->
    proof = wassat_induction_proof(induction_fixture(true))
    expect(proof.starts_with?("pseudo-Boolean proof version 3.0\n")).to eq(true)
    expect(proof.ends_with?("rup >= 1 ;\noutput NONE ;\nconclusion UNSAT : -1 ;\nend pseudo-Boolean proof ;\n")).to eq(true)

  it "declines a satisfiable transition missing a predecessor case" ->
    expect(wassat_induction_proof(induction_fixture(false))).to eq(nil)

  it "declines a cycle with no base case" ->
    f = wassat_parse_cnf_native("p cnf 4 6\n-1 -2 3 0\n-1 -2 4 0\n-3 -4 1 0\n-3 -4 2 0\n1 0\n2 0\n")
    expect(wassat_induction_proof(f)).to eq(nil)

spec_summary
