use spec
use ../lib/solver

+ ReductionProgressFixture < Wassat
  ro :reductions, :conflicts, :rhist, :reduce_limit, :nlearned

  -> arm_reductions(step, guarded, copies = 10)
    @reduce_floor = guarded
    @reduce_step = step
    @reduce_limit = 1
    @auto_vivify = false
    @lucky_pending = false
    @use_walk = false
    @walker = nil
    self.disable_inprocess
    # The original binaries already entail these identical learned copies.
    # Every copy is protected from deletion by the ordinary binary policy.
    i = 0
    while i < copies
      ci = self.store_clause([1, 2], 2)
      @clbd[ci] = 2
      @nlearned += 1
      i += 1
    0

describe "Reduction survivor headroom" ->
  it "makes search progress when protected learned clauses exceed a fixed cap" ->
    s = ReductionProgressFixture.new(4, [[1, 2], [3, 4]], 0, 0)
    s.arm_reductions(0, true)
    r = s.solve_budget(100)
    expect(r["status"]).to eq(1)
    expect(s.reductions).to eq(1)
    expect(s.rhist[71]).to eq(1)
    expect(s.reduce_limit > s.nlearned).to eq(true)
    expect(s.value(1) > 0 || s.value(2) > 0).to eq(true)
    expect(s.value(3) > 0 || s.value(4) > 0).to eq(true)

  it "avoids repeated root rebuilds while an additive cap catches up" ->
    old = ReductionProgressFixture.new(4, [[1, 2], [3, 4]], 0, 0)
    old.arm_reductions(300, false, 650)
    new = ReductionProgressFixture.new(4, [[1, 2], [3, 4]], 0, 0)
    new.arm_reductions(300, true, 650)
    a = old.solve_budget(100)
    b = new.solve_budget(100)
    expect(a["status"]).to eq(1)
    expect(b["status"]).to eq(1)
    expect(old.reductions > new.reductions).to eq(true)
    expect(new.reductions).to eq(1)

spec_summary
