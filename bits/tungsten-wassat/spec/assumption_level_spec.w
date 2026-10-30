use spec
use ../lib/solver

+ AssumptionLevelFixture < Wassat
  ro :trail_lim, :lbd_seen, :shcnt, :max_query_level

  -> force_negative_decisions(vars)
    @lookahead = 0
    @use_target = false
    @use_vmtf = false
    @lucky_pending = false
    @pending_simplify = -1
    @max_query_level = 0
    self.promote_control_vars(vars)

  -> compute_lbd_buf(n)
    i = 0
    while i < n
      lv = @level[@lbuf[i].abs]
      raise "LBD level outside scratch" if lv >= @lbd_seen.size
      @max_query_level = lv if lv > @max_query_level
      i += 1
    super(n)

  -> shrink_learned(n)
    i = 0
    while i < n
      lv = @level[@lbuf[i].abs]
      raise "shrink level outside scratch" if lv >= @shcnt.size || lv >= @trail_lim.size
      i += 1
    super(n)

-> repeated_level_assumptions(n)
  out = []
  i = 0
  while i < n
    out.push(1)
    i += 1
  out

describe "Wassat assumption decision-level capacity" ->
  it "learns safely above the variable count after repeated assumptions" ->
    s = AssumptionLevelFixture.new(4, [[2, 3], [2, -3]], 0, 0)
    s.force_negative_decisions([2])
    r = s.solve_assuming(repeated_level_assumptions(1000))
    expect(r["sat"]).to eq(true)
    expect(r["conflicts"] > 0).to eq(true)
    expect(r["model"].include?(1)).to eq(true)
    expect(r["model"].include?(2)).to eq(true)
    expect(s.max_query_level > 1000).to eq(true)
    cap = s.trail_lim.size
    r = s.solve_assuming(repeated_level_assumptions(999))
    expect(r["sat"]).to eq(true)
    expect(s.trail_lim.size).to eq(cap)

  it "sizes shrinking counts and trail boundaries for high assumption levels" ->
    clauses = [[2, 3, 4, 5], [2, 3, 4, -5]]
    s = AssumptionLevelFixture.new(5, clauses, 0, 0)
    s.force_negative_decisions([2, 3, 4])
    s.enable_shrink
    r = s.solve_assuming(repeated_level_assumptions(1000))
    expect(r["sat"]).to eq(true)
    expect(r["conflicts"] > 0).to eq(true)
    expect(s.max_query_level > 1000).to eq(true)
    expect(clauses.all? -> (c) c.any? -> (l) r["model"].include?(l)).to eq(true)

  it "keeps ordinary capacity for distinct assumptions" ->
    s = AssumptionLevelFixture.new(64, [], 0, 0)
    assumptions = []
    i = 1
    while i <= 64
      assumptions.push(i)
      i += 1
    cap = s.trail_lim.size
    r = s.solve_assuming(assumptions)
    expect(r["sat"]).to eq(true)
    expect(s.trail_lim.size).to eq(cap)
    expect(s.lbd_seen.size).to eq(66)

  it "preserves failed cores and later queries after empty assumption levels" ->
    s = AssumptionLevelFixture.new(4, [[2, 3], [2, -3]], 0, 0)
    assumptions = repeated_level_assumptions(1000)
    assumptions.push(-1)
    r = s.solve_assuming(assumptions)
    expect(r["unsat"]).to eq(true)
    expect(r["core"].include?(1)).to eq(true)
    expect(r["core"].include?(-1)).to eq(true)
    expect(s.solve_assuming([])["sat"]).to eq(true)

  it "rejects insufficient frozen capacity before search and clears borrowed marks" ->
    s = AssumptionLevelFixture.new(4, [[2, 3], [2, -3]], 0, 0)
    s.enable_fixed_caps
    expect(-> () s.solve_assuming(repeated_level_assumptions(1000))).to raise_error
    r = s.solve_assuming([1])
    expect(r["sat"]).to eq(true)
    expect(r["model"].include?(1)).to eq(true)

spec_summary
