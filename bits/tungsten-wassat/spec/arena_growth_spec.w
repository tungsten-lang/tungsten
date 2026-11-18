use spec
use ../lib/solver
use ../../tungsten-wrat/lib/wrat

+ ArenaGrowthFixture < Wassat
  ro :arena, :acap, :asize, :aused, :ccap, :ncl

  -> fill_arena
    i = 0
    while i < @arena.size
      @arena[i] = i % 2 == 0 ? 2147483647 : -2147483648
      i += 1
    @aused = @acap - 2
    @asize = @aused + 1
    0

  -> exhaust_spare_words
    @acap = @aused
    while @arena.size > @acap + @ccap
      @arena.pop
    @lookahead = 0
    @lucky_pending = false
    @use_walk = false
    @walker = nil
    0

  -> exceed_limit
    @aused = 1073741824
    0

  -> exceed_physical_limit
    @ccap = 2147483647 - @acap
    @ncl = @ccap - 1
    0

  -> fill_clause_slots
    @ccap = @ncl + 1
    0

describe "Wassat arena growth" ->
  it "reuses the descriptor and preserves signed 32-bit cells and aliases" ->
    s = ArenaGrowthFixture.new(3, [], WASSAT_PROOF_NONE)
    s.fill_arena
    old = s.arena
    n = old.size
    s.grow_arena(19)
    expect(s.acap >= s.aused + 19).to eq(true)
    expect(old.size).to eq(s.acap + s.ccap)
    i = 0
    while i < n
      expect(old[i]).to eq(i % 2 == 0 ? 2147483647 : -2147483648)
      i += 1
    expect(old[n]).to eq(0)
    expect(old[old.size - 1]).to eq(0)
    s.arena[0] = 123
    expect(old[0]).to eq(123)
    cap = s.acap
    s.grow_arena(19)
    expect(s.acap).to eq(cap)

  it "rejects an unrepresentable logical request before changing storage" ->
    s = ArenaGrowthFixture.new(1, [], WASSAT_PROOF_NONE)
    cap = s.acap
    cells = s.arena.size
    s.exceed_limit
    expect(-> () s.grow_arena(1)).to raise_error
    expect(s.acap).to eq(cap)
    expect(s.arena.size).to eq(cells)

  it "rejects unrepresentable physical growth before allocating clause tables" ->
    s = ArenaGrowthFixture.new(1, [], WASSAT_PROOF_NONE)
    cells = s.arena.size
    s.exceed_physical_limit
    cap = s.ccap
    expect(-> () s.grow_clause_tables).to raise_error
    expect(s.ccap).to eq(cap)
    expect(s.arena.size).to eq(cells)

  it "reserves the extra header cells when growing clause tables" ->
    s = ArenaGrowthFixture.new(3, [[1, 2, 3]], WASSAT_PROOF_NONE)
    old = s.arena
    s.fill_clause_slots
    s.grow_clause_tables
    expect(s.ccap).to eq(4)
    expect(old.size >= s.acap + s.ccap).to eq(true)
    expect([old[0], old[1], old[2], old[3], old[4]]).to eq([0, 3, 1, 2, 3])
    expect([s.asize, s.aused]).to eq([5, 4])

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
