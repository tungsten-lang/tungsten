use spec
use ../lib/solver

+ ReasonIndexFixture < Wassat
  ro :reason, :ncl, :asize, :ccap, :acap

  -> exhaust_clause_indices
    @ncl = 2147483648
    0

describe "Wassat signed clause reasons" ->
  it "preserves the no-reason sentinel for unassigned and decision variables" ->
    s = ReasonIndexFixture.new(2, [], WASSAT_PROOF_NONE)
    expect(s.reason[1]).to eq(-1)
    expect(s.reason[2]).to eq(-1)
    s.enqueue(-1, -1)
    expect(s.reason[1]).to eq(-1)

  it "rejects a new unrepresentable index before growing or changing storage" ->
    s = ReasonIndexFixture.new(2, [[1, 2]], WASSAT_PROOF_NONE)
    asize = s.asize
    ccap = s.ccap
    acap = s.acap
    s.exhaust_clause_indices
    expect(-> () s.store_clause(i64[0], 0)).to raise_error
    expect(s.ncl).to eq(2147483648)
    expect(s.asize).to eq(asize)
    expect(s.ccap).to eq(ccap)
    expect(s.acap).to eq(acap)

  it "rejects an unrepresentable flat clause count before allocating storage" ->
    s = ReasonIndexFixture.new(2, [], WASSAT_PROOF_NONE)
    asize = s.asize
    ccap = s.ccap
    acap = s.acap
    art = { "config": WassatConfig.new(2, []), "fncl": 2147483649 }
    expect(-> () s.load_flat(art)).to raise_error
    expect(s.ncl).to eq(0)
    expect(s.asize).to eq(asize)
    expect(s.ccap).to eq(ccap)
    expect(s.acap).to eq(acap)

spec_summary
