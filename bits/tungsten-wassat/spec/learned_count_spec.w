use spec
use ../lib/solver

+ LearnedCountFixture < Wassat
  ro :nlearned, :qhead

  -> live_learned
    n = 0
    ci = 0
    while ci < @ncl
      n += 1 if @alive[ci] == 1 && @clbd[ci] > 0
      ci += 1
    n

  -> receive(lits, permanent = false)
    i = 0
    while i < lits.size
      @mbuf[i] = lits[i]
      i += 1
    self.import_clause(lits.size, permanent)

  -> learned_candidate(ci)
    @clbd[ci] = 6
    @nlearned += 1
    0

  -> deny_capacity
    @fixed_caps = true
    @acap = @asize
    0


describe "Live learned-clause accounting" ->
  it "counts pruning clauses before initial propagation" ->
    s = LearnedCountFixture.new(4, [[1, 2, 3], [4]], 0, 0)
    expect(s.qhead).to eq(0)
    expect(s.install_pruning_clause([1, 2, 3], false)).to eq(1)
    expect(s.nlearned).to eq(1)
    expect(s.nlearned).to eq(s.live_learned)
    expect(s.install_pruning_clause([1, 2, 3], false, true)).to eq(1)
    expect(s.nlearned).to eq(1)
    expect(s.nlearned).to eq(s.live_learned)

  it "counts pruning clauses after initial propagation" ->
    s = LearnedCountFixture.new(4, [[1, 2, 3], [4]], 0, 0)
    s.propagate
    expect(s.qhead > 0).to eq(true)
    expect(s.install_pruning_clause([1, 2, 3], false)).to eq(1)
    expect(s.nlearned).to eq(1)
    expect(s.nlearned).to eq(s.live_learned)

  it "counts an imported redundant clause but excludes a permanent clause" ->
    s = LearnedCountFixture.new(3, [[1, 2, 3]], 0, 0)
    expect(s.receive([1, 2, 3])).to eq(1)
    expect(s.nlearned).to eq(1)
    expect(s.receive([1, 2, 3], true)).to eq(1)
    expect(s.nlearned).to eq(1)
    expect(s.nlearned).to eq(s.live_learned)

  it "counts stored units consistently with a reduction recount" ->
    s = LearnedCountFixture.new(2, [[1, 2], [1, -2]], 0, 0)
    expect(s.receive([1])).to eq(1)
    expect(s.nlearned).to eq(1)
    expect(s.nlearned).to eq(s.live_learned)
    s.reduce_db
    expect(s.nlearned).to eq(s.live_learned)

  it "counts a stored imported unit even when propagation refutes" ->
    s = LearnedCountFixture.new(3, [[-1, 2], [-1, -2], [1, 3], [1, -3]], 0, 0)
    expect(s.receive([1])).to eq(-1)
    expect(s.nlearned).to eq(1)
    expect(s.nlearned).to eq(s.live_learned)

  it "does not count satisfied, invalid, or capacity-rejected imports" ->
    s = LearnedCountFixture.new(3, [[1]], 0, 0)
    expect(s.receive([1, 2])).to eq(0)
    expect(s.install_pruning_clause([2, -2], false)).to eq(0)
    s.deny_capacity
    expect(s.receive([2, 3])).to eq(0)
    expect(s.nlearned).to eq(0)
    expect(s.nlearned).to eq(s.live_learned)

  it "keeps one learned clause counted when vivification replaces it" ->
    s = LearnedCountFixture.new(3, [[1, 2, 3], [1, 2, -3]], 0, 0)
    s.learned_candidate(0)
    s.vivify_round(100)
    expect(s.nlearned).to eq(s.live_learned)
    expect(s.nlearned).to eq(1)

spec_summary
