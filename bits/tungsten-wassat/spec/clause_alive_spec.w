use spec
use ../lib/solver

+ ClauseAliveFixture < Wassat
  ro :alive, :ccap, :ncl

  -> prepare_growth
    @ccap = 8
    @alive[1] = 0
    @alive[3] = 0
    0

describe "Wassat clause liveness storage" ->
  it "preserves adjacent live and dead flags through table growth" ->
    s = ClauseAliveFixture.new(3, [[1, 2, 3], [-1, 2, 3], [1, -2, 3], [1, 2, -3]], WASSAT_PROOF_NONE)
    s.prepare_growth
    a = i64[3]
    a[0] = 1
    a[1] = 2
    a[2] = 3
    i = 0
    while i < 10
      s.store_clause(a, 3)
      i += 1
    expect(s.ccap).to eq(16)
    expect(s.ncl).to eq(14)
    i = 0
    while i < s.ncl
      expect(s.alive[i]).to eq(i == 1 || i == 3 ? 0 : 1)
      i += 1
    expect(s.alive[14]).to eq(0)
    expect(s.alive[15]).to eq(0)

spec_summary
