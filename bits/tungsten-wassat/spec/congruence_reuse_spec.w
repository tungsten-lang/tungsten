use spec
use ../lib/solver

+ RepeatedCongruenceConfig < WassatConfig
  -> congruence_max_rounds
    8

+ RepeatedCongruenceFixture < Wassat
  -> enable_repeated_congruence
    @config = RepeatedCongruenceConfig.new(@nvars, @input_clauses)

-> duplicate_chain
  [[-3, 1], [-3, 2], [3, -1, -2],
   [-4, 3], [-4, 1], [4, -3, -1],
   [-5, 1], [-5, 2], [5, -1, -2],
   [-6, 5], [-6, 1], [6, -5, -1]]

-> checked_congruence_result(clauses)
  s = RepeatedCongruenceFixture.new(6, clauses, WASSAT_PROOF_NONE)
  s.enable_repeated_congruence
  s.simplify_preprocessed(1)
  s.simplify_preprocessed(1)
  r = s.solve
  valid = true
  if r["status"] == 1
    signs = i64[7]
    r["model"].each -> (l)
      signs[l < 0 ? 0 - l : l] = l < 0 ? -1 : 1
    clauses.each -> (clause)
      found = false
      clause.each -> (l)
        v = l < 0 ? 0 - l : l
        found = true if (l > 0 && signs[v] == 1) || (l < 0 && signs[v] == -1)
      valid = false unless found
  [r["status"], valid]

describe "Repeated congruence scratch" ->
  it "finds a contradiction through two duplicate gate layers" ->
    cs = duplicate_chain
    cs.push([4, 6]); cs.push([-4, -6])
    expect(checked_congruence_result(cs)).to eq([-1, true])

  it "reconstructs a satisfying model after layered substitution" ->
    cs = duplicate_chain
    cs.push([-4, 6]); cs.push([4, -6])
    expect(checked_congruence_result(cs)).to eq([1, true])

  it "preserves the SAT model when a definition premise is absent" ->
    original = duplicate_chain
    cs = []
    original.each_with_index -> (clause, i)
      cs.push(clause) unless i == 9
    cs.push([4, 6]); cs.push([-4, -6])
    expect(checked_congruence_result(cs)).to eq([1, true])

spec_summary
