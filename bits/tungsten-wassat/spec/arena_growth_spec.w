use spec
use ../lib/solver
use ../../tungsten-wrat/lib/wrat

+ ArenaGrowthFixture < Wassat
  ro :arena, :acap, :asize

  -> fill_arena
    i = 0
    while i < @acap
      @arena[i] = i * 4294967296 + 7
      i += 1
    @asize = @acap - 2
    0

  -> exhaust_spare_words
    while @arena.size > @asize
      @arena.pop
    @acap = @arena.size
    @lookahead = 0
    @lucky_pending = false
    @use_walk = false
    @walker = nil
    0

  -> exceed_limit
    @asize = 1073741824
    0

describe "Wassat arena growth" ->
  it "reuses the arena descriptor and preserves packed words and aliases" ->
    s = ArenaGrowthFixture.new(3, [], WASSAT_PROOF_NONE)
    s.fill_arena
    old = s.arena
    n = old.size
    s.grow_arena(19)
    expect(s.acap >= s.asize + 19).to eq(true)
    expect(old.size).to eq(s.acap)
    i = 0
    while i < n
      expect(old[i]).to eq(i * 4294967296 + 7)
      i += 1
    expect(old[n]).to eq(0)
    expect(old[old.size - 1]).to eq(0)
    s.arena[0] = 123
    expect(old[0]).to eq(123)
    cap = s.acap
    s.grow_arena(19)
    expect(s.acap).to eq(cap)

  it "rejects an unrepresentable request before changing storage" ->
    s = ArenaGrowthFixture.new(1, [], WASSAT_PROOF_NONE)
    cap = s.acap
    s.exceed_limit
    expect(-> () s.grow_arena(1)).to raise_error
    expect(s.acap).to eq(cap)
    expect(s.arena.size).to eq(cap)

  it "retains a checked refutation when learning grows a full arena" ->
    clauses = [[1, 2], [1, -2], [-1, 2], [-1, -2]]
    s = ArenaGrowthFixture.new(2, clauses, WASSAT_PROOF_WRAT)
    s.exhaust_spare_words
    before = s.acap
    r = s.solve
    expect(r["unsat"]).to eq(true)
    expect(s.acap > before).to eq(true)
    cnf = "p cnf 2 4\n1 2 0\n1 -2 0\n-1 2 0\n-1 -2 0\n"
    proof = "wrat 1\n" + r["proof"].join("\n") + "\n"
    expect(wrat_verify(cnf, proof)["verified"]).to eq(true)

spec_summary
