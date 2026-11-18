use spec
use ../lib/solver

+ ArenaCapacityFixture < Wassat
  ro :asize, :aused, :acap, :ncl, :arena

  -> keep_sparse_pair(remap)
    @fixed_caps = remap
    i = 0
    while i < @ncl
      @alive[i] = i == 0 || i == 3 ? 1 : 0
      i += 1
    0

describe "Compact arena capacity accounting" ->
  it "counts resident records independently of stable clause indices" ->
    [false, true].each -> (remap)
      cs = [[1, 2, 3], [-1, -2, 4], [1, -3, 4], [-1, 2, -4], [-2, 3, 4], [1, -2, -3]]
      s = ArenaCapacityFixture.new(4, cs, WASSAT_PROOF_NONE)
      expect([s.asize, s.aused]).to eq([30, 24])
      cap = s.acap
      s.keep_sparse_pair(remap)
      s.reduce_db
      expect([s.asize, s.aused]).to eq([10, 8])
      expect(s.ncl).to eq(remap ? 2 : 6)
      expect(s.acap).to eq(cap)
      expect([s.arena[0], s.arena[1], s.arena[5], s.arena[6]]).to eq([0, 3, remap ? 1 : 3, 3])
      s.store_clause([1, -4], 2)
      expect([s.asize, s.aused]).to eq([14, 11])
      expect(s.ncl).to eq(remap ? 3 : 7)
      expect([s.arena[10], s.arena[11], s.arena[12], s.arena[13]]).to eq([remap ? 2 : 6, 2, 1, -4])

spec_summary
