use spec
use ../lib/solver

+ MinimizeBudgetFixture < Wassat
  ro :astate, :lbuf, :lsize, :seen

  -> prepare_trace(chain, polarity, budget)
    @astate[11] = budget
    @conflicts = 1
    @tsize = @nvars
    v = 1
    while v <= @nvars
      @assign[v] = polarity
      @trail[v - 1] = polarity * v
      @level[v] = v <= chain ? 1 : 65
      @reason[v] = -1
      @reason[v] = v - 2 if v >= 2 && v <= chain
      v += 1
    @level[@nvars] = 66
    @reason[chain + 2] = chain - 1
    @reason[chain + 3] = chain
    0

  -> analyze_fixture
    self.analyze(@ncl - 1, 66)
    clause = []
    i = 0
    while i < @lsize
      clause.push(@lbuf[i])
      i += 1
    clause

  -> marks_clean?
    v = 0
    while v <= @nvars
      return false if @seen[v] != 0
      v += 1
    true

-> minimize_budget_fixture(chain, polarity, budget, covered)
  cs = []
  v = 2
  while v <= chain
    cs.push([polarity * (1 - v), polarity * v])
    v += 1
  d = chain + 1
  a = chain + 2
  b = chain + 3
  u = chain + 4
  cs.push([0 - polarity * chain, 0 - polarity * d, polarity * a])
  cs.push([polarity * b, 0 - polarity * d, 0 - polarity * chain])
  conflict = [0 - polarity * u, 0 - polarity * a,
              0 - polarity * b, 0 - polarity * d]
  conflict.push(0 - polarity) if covered
  cs.push(conflict)
  s = MinimizeBudgetFixture.new(u, cs, WASSAT_PROOF_NONE)
  s.prepare_trace(chain, polarity, budget)
  s

describe "Wassat optional minimization work budget" ->
  it "keeps the later redundant literal after a completed probe exhausts the budget" ->
    s = minimize_budget_fixture(64, 1, 1, true)
    expect(s.analyze_fixture).to eq([-68, -67, -65, -1])
    expect(s.astate[16]).to eq(1)
    expect(s.astate[20]).to eq(1)
    expect(s.marks_clean?).to eq(true)

  it "preserves unrestricted minimization when the work limit is zero" ->
    s = minimize_budget_fixture(64, 1, 0, true)
    expect(s.analyze_fixture).to eq([-68, -65, -1])
    expect(s.astate[16]).to eq(2)
    expect(s.astate[20]).to eq(0)
    expect(s.marks_clean?).to eq(true)

  it "clears all borrowed marks before a subsequent conflict" ->
    s = minimize_budget_fixture(64, 1, 1, true)
    first = s.analyze_fixture
    visits = s.astate[12] + s.astate[13]
    expect(s.analyze_fixture).to eq(first)
    expect(s.astate[12] + s.astate[13]).to eq(2 * visits)
    expect(s.astate[16]).to eq(2)
    expect(s.astate[20]).to eq(2)
    expect(s.marks_clean?).to eq(true)

  it "retains a literal whose reason reaches an uncovered decision" ->
    s = minimize_budget_fixture(64, 1, 0, false)
    expect(s.analyze_fixture).to eq([-68, -66, -67, -65])
    expect(s.astate[16]).to eq(0)
    expect(s.marks_clean?).to eq(true)

  it "handles reversed literal signs and either position of a reason pivot" ->
    s = minimize_budget_fixture(8, -1, 1, true)
    expect(s.analyze_fixture).to eq([12, 11, 9, 1])
    expect(s.marks_clean?).to eq(true)

  it "matches the unrestricted result when the whole minimization fits" ->
    a = minimize_budget_fixture(8, 1, 0, true)
    b = minimize_budget_fixture(8, 1, 16384, true)
    expect(b.analyze_fixture).to eq(a.analyze_fixture)
    expect(b.astate[20]).to eq(0)
    expect(b.marks_clean?).to eq(true)

spec_summary
