use spec
use ../lib/solver

+ SubsumptionRejectFixture < Wassat
  ro :cmeta, :arena, :alive, :inp_totals

describe "Subsumption candidate rejection" ->
  it "rejects a missing literal even when the compact signature collides" ->
    clauses = [[1, 33, 2], [33, 70, 71], [33, 72, 73], [2, 70, 72], [2, 71, 73], [1, 65, 3, 4]]
    s = SubsumptionRejectFixture.new(73, clauses, WASSAT_PROOF_NONE, 0)
    s.run_subsume(1, 100000)
    expect(s.alive[5]).to eq(1)
    expect(s.cmeta[11]).to eq(4)
    at = s.cmeta[10]
    expect([s.arena[at], s.arena[at + 1], s.arena[at + 2], s.arena[at + 3]]).to eq([1, 65, 3, 4])
    expect(s.inp_totals[8] > 0).to eq(true)
    if env("WASSAT_SUBSUME_SHORTCUT") == "0"
      expect(s.inp_totals[9]).to eq(0)
    else
      expect(s.inp_totals[9] > 0).to eq(true)

  it "keeps a target when one complement is followed by an absent variable" ->
    s = SubsumptionRejectFixture.new(34, [[1, -33, 34], [1, 33, 2, 4]], WASSAT_PROOF_NONE, 0)
    s.run_subsume(1, 100000)
    expect(s.alive[1]).to eq(1)
    expect(s.cmeta[3]).to eq(4)
    at = s.cmeta[2]
    expect([s.arena[at], s.arena[at + 1], s.arena[at + 2], s.arena[at + 3]]).to eq([1, 33, 2, 4])

  it "still removes the single complemented literal from an actual resolvent" ->
    s = SubsumptionRejectFixture.new(33, [[1, -33, 2], [1, 33, 2, 4]], WASSAT_PROOF_NONE, 0)
    s.run_subsume(1, 100000)
    expect(s.alive[1]).to eq(1)
    expect(s.cmeta[3]).to eq(3)
    at = s.cmeta[2]
    expect([s.arena[at], s.arena[at + 1], s.arena[at + 2]]).to eq([1, 2, 4])

spec_summary
