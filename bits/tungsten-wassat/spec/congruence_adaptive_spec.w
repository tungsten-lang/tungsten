use spec
use ../lib/solver

-> two_input_gate_merges(a, b, c, d, rotation, missing, noise)
  clauses = []
  [c, d].each -> (out)
    clauses.push([-out, a])
    clauses.push([-out, b]) unless missing && out == d
    # Duplicating the first side never satisfies a missing second side.
    clauses.push([-out, a])
    i = 0
    while i < noise
      clauses.push([-out, i + 5])
      i += 1
    if rotation == 0
      clauses.push([out, -a, -b])
    elsif rotation == 1
      clauses.push([-a, out, -b])
    else
      clauses.push([-a, -b, out])
  s = Wassat.new(noise + 5, clauses, WASSAT_PROOF_NONE)
  s.extract_and_gates

-> adaptive_gate_merge(arity, lhs_noise, rhs_noise, missing)
  cs = []
  [arity + 1, arity + 2].each -> (out)
    long_clause = [out]
    a = 1
    while a <= arity
      cs.push([-out, a]) unless missing && out == arity + 2 && a == arity
      long_clause.push(-a)
      a += 1
    cs.push(long_clause)
    i = 0
    while i < lhs_noise
      cs.push([-out, arity + 3 + i])
      i += 1
  a = 1
  while a <= arity
    i = 0
    while i < rhs_noise
      cs.push([a, arity + 3 + i])
      i += 1
    a += 1
  noise = lhs_noise > rhs_noise ? lhs_noise : rhs_noise
  s = Wassat.new(arity + 3 + noise, cs, WASSAT_PROOF_NONE)
  s.extract_and_gates

describe "Adaptive AND gate membership" ->
  it "checks high-degree lists in every lhs position with mixed signs" ->
    [0, 1, 2].each -> (rotation)
      expect(two_input_gate_merges(-1, 2, -3, 4, rotation, false, 80)).to eq(1)
      expect(two_input_gate_merges(-1, 2, -3, 4, rotation, true, 80)).to eq(0)

  it "checks wide reverse scans and rejects missing premises" ->
    [3, 16].each -> (arity)
      expect(adaptive_gate_merge(arity, 80, 0, false)).to eq(1)
      expect(adaptive_gate_merge(arity, 80, 0, true)).to eq(0)

  it "retains the stamped fallback when opposite lists cost more" ->
    expect(adaptive_gate_merge(16, 80, 80, false)).to eq(1)
    expect(adaptive_gate_merge(16, 80, 80, true)).to eq(0)

spec_summary
