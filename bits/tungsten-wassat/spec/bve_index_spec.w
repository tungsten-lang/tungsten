use spec
use ../lib/wassat

+ BveIndexProbe < WassatPreprocess
  -> prepare
    self.init_budget
    self.intake

  rw :lgen

  -> scan(hashcap = WASSAT_PRE_BVE_HASH_CAPACITY)
    @bve_pm[0] = 1
    @bve_pm[1] = 0
    @bve_pm[2] = 16
    @bve_pm[3] = WASSAT_PRE_BVE_OUT_CAPACITY
    @bve_pm[6] = hashcap
    wassat_pre_bve_scan(@fla, @fcs, @fcl, @falive, @ftaut, @oh, @on, @ov,
                       @lstamp, @bve_hash, @bve_hpos, @bve_out, @bve_pm, @lgen)
    @lgen = @bve_pm[8]
    lits = []
    i = 0
    while i < @bve_out[0]
      lits.push(@bve_out[3 + i])
      i += 1
    [@bve_pm[4], @bve_pm[5], @bve_pm[9], @bve_pm[10], lits.sort]

describe "BVE indexed duplicate resolution" ->
  it "recognizes reordered signed sets and reuses stamps across scans" ->
    seed = 0
    while seed < 24
      n = 2 + 4 * seed
      a = [1]
      b = [1]
      expected = []
      j = 0
      while j < n
        v = j + 2
        l = (j + seed) % 3 == 0 ? 0 - v : v
        a.push(l)
        expected.push(l)
        j += 1
      j = n - 1
      while j >= 0
        b.push(a[j + 1])
        j -= 1
      expected.push(n + 2)
      pre = BveIndexProbe.new(n + 2, [a, b, [-1, n + 2], [n + 2, -1]], WASSAT_PROOF_NONE, nil)
      pre.prepare
      want = [1, 1, 3, 3 * (n + 1) * (n + 2) / 2, expected.sort]
      expect(pre.scan).to eq(want)
      g = pre.lgen
      expect(pre.scan).to eq(want)
      expect(pre.lgen > g).to eq(true)
      seed += 1

  it "accepts duplicates at a full table and clears tags after their packed range" ->
    pre = BveIndexProbe.new(3, [[1, 2], [2, 1], [-1, 3], [3, -1]], WASSAT_PROOF_NONE, nil)
    pre.prepare
    want = [1, 1, 3, 9, [2, 3]]
    expect(pre.scan(1)).to eq(want)
    pre.lgen = 70368744177662
    expect(pre.scan(1)).to eq(want)
    expect(pre.scan(2)).to eq(want)
    r = pre.scan(0)
    expect(r[0]).to eq(0)
    expect(r[1]).to eq(0)

spec_summary
