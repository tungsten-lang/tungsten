use spec
use ../lib/solver

+ BoundedCongruenceCapacityConfig < WassatConfig
  -> congruence_gate_ceiling
    64

+ BoundedCongruenceCapacitySolver < Wassat
  -> bound_gate_capacity
    @config = BoundedCongruenceCapacityConfig.new(@nvars, @input_clauses)

-> capacity_and_clauses
  [[-3, 1], [-3, 2], [3, -1, -2], [-4, 1], [-4, 2], [4, -1, -2]]

-> capacity_xor_clauses
  [[-1, -2, -3], [-1, 2, 3], [1, -2, 3], [1, 2, -3],
   [-1, -2, -4], [-1, 2, 4], [1, -2, 4], [1, 2, -4]]

describe "Retained congruence extraction capacity" ->
  it "starts AND extraction with the retained merge capacity" ->
    s = Wassat.new(4, capacity_and_clauses, WASSAT_PROOF_NONE)
    scratch = [nil, nil, nil, i64[1024], nil]
    merges = s.extract_and_gates(scratch)
    expect(merges > 0).to eq(true)
    expect(scratch[1].size).to eq(4096)
    expect(scratch[2].size).to eq(2048)

  it "starts XOR extraction with the retained merge capacity" ->
    s = Wassat.new(4, capacity_xor_clauses, WASSAT_PROOF_NONE)
    scratch = [nil, nil, nil, nil, nil, nil, i64[1024], nil]
    merges = s.extract_xor_gates(scratch)
    expect(merges > 0).to eq(true)
    expect(scratch[4].size).to eq(4096)
    expect(scratch[5].size).to eq(2048)

  it "respects the configured ceiling when the retained output is larger" ->
    s = BoundedCongruenceCapacitySolver.new(4, capacity_and_clauses, WASSAT_PROOF_NONE)
    s.bound_gate_capacity
    scratch = [nil, nil, nil, i64[1024], nil]
    merges = s.extract_and_gates(scratch)
    expect(merges > 0).to eq(true)
    expect(scratch[1].size).to eq(512)
    expect(scratch[2].size).to eq(1024)

spec_summary
