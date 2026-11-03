use spec
use ../lib/sls

describe "Packed SLS clause state" ->
  it "rejects variable IDs outside the solver representation before allocating" ->
    expect(-> () WassatSls.new(2147483648, [], nil, nil)).to raise_error

  it "retains true counts above 255 and critical XORs above 127" ->
    nv = 512
    literals = i64[nv + 1]
    offsets = i64[2]
    lengths = i64[2]
    assignment = i64[nv + 1]
    i = 0
    while i < nv
      literals[i] = i + 1
      assignment[i + 1] = 1
      i += 1
    literals[nv] = 0 - nv
    lengths[0] = nv
    offsets[1] = nv
    lengths[1] = 1
    clause_state = i64[2]
    weights = i64[2]
    unsatisfied = i64[2]
    positions = i64[2]
    scores = i64[nv + 1]
    good = i64[nv + 1]
    in_good = i64[nv + 1]
    state = i64[13]
    state[0] = nv
    state[1] = 2
    wassat_sls_init_state(literals, offsets, lengths, assignment,
      clause_state, weights, unsatisfied, positions, scores, good,
      in_good, state)
    expect(clause_state[0] >> 32).to eq(512)
    expect(clause_state[0] & 2147483647).to eq(512)
    expect(clause_state[1] >> 32).to eq(0)
    expect(clause_state[1] & 2147483647).to eq(0)
    expect(state[2]).to eq(1)
    expect(scores[512]).to eq(1)

  it "updates high variable IDs through a phase-seeded walk" ->
    clauses = [[512], [-512, 257], [-257, 128]]
    walker = WassatSls.new(512, clauses, nil, nil)
    phase = i8[513]
    best = walker.walk_from_phase(phase, 100, 7)
    expect(best).to eq(0)
    expect(phase[512]).to eq(1)
    expect(phase[257]).to eq(1)
    expect(phase[128]).to eq(1)

spec_summary
