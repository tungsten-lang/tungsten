# spec: compiled -- exercises a 65k-slot native reduction database
use spec
use ../lib/solver

+ GrowingRecycleFixture < Wassat
  ro :ncl, :ccap, :rhist, :vivify_cursor, :subsume_cursor

  -> scatter(count, enabled, sentinel = false)
    @recycle_growing = enabled
    oldcm = @cmeta; oldal = @alive; oldlb = @clbd; oldcu = @cused
    oldn = @ncl
    @ccap = count + 2; @ncl = count
    @cmeta = i64[2 * @ccap]; @alive = i8[@ccap]
    @clbd = i64[@ccap]; @cused = i64[@ccap]; @gid = sentinel ? i64[1] : i64[@ccap]
    ci = 0
    while ci < oldn
      dst = ci == oldn-1 ? count-1 : ci * (count / oldn)
      @cmeta[2*dst] = oldcm[2*ci]; @cmeta[2*dst+1] = oldcm[2*ci+1]
      @alive[dst] = oldal[ci]; @clbd[dst] = oldlb[ci]; @cused[dst] = oldcu[ci]
      wassat_hdr_put(@arena, oldcm[2*ci]-1, dst, oldcm[2*ci+1])
      v = 1
      while v <= @nvars
        # Re-encode only reasons still naming the original compact index.
        @reason[v] = -dst-2 if @reason[v] == ci
        v += 1
      ci += 1
    v = 1
    while v <= @nvars
      @reason[v] = - @reason[v]-2 if @reason[v] <= -2
      v += 1
    @vivify_cursor = 1
    @subsume_cursor = count
    self.rebuild_binaries
    self.rebuild_watches

  -> append_duplicates(n)
    c = [3, 4]
    i = 0
    while i < n
      self.store_clause(c, 2)
      i += 1

-> growing_recycle_fixture(count, enabled, sentinel = false, proof = WASSAT_PROOF_NONE)
  clauses = [[1], [-1, 2], [-2, 3, 4], [-3, -4], [5, 6], [-5, -6]]
  s = GrowingRecycleFixture.new(6, clauses, proof, 0)
  s.scatter(count, enabled, sentinel)
  s

describe "Growing clause table recycling" ->
  it "reclaims dead slots and preserves root reasons and future queries" ->
    s = growing_recycle_fixture(65536, true)
    s.reduce_db
    expect(s.ncl).to eq(6)
    expect(s.ccap).to eq(65538)
    expect(s.rhist[75]).to eq(1)
    expect(s.rhist[76]).to eq(65530)
    expect(s.vivify_cursor).to eq(1)
    expect(s.subsume_cursor).to eq(6)
    expect(s.solve_assuming([-3])["status"]).to eq(1)
    expect(s.solve_assuming([-3, -4])["status"]).to eq(-1)
    expect(s.solve_assuming([-4])["status"]).to eq(1)
    s.install_pruning_clause([-5], false, true)
    r = s.solve
    expect(r["status"]).to eq(1)
    expect(r["model"].include?(6)).to eq(true)
    expect(r["model"].include?(-5)).to eq(true)
    expect(s.install_pruning_clause([-6], false, true)).to eq(-1)
    expect(s.solve["status"]).to eq(-1)

  it "retains the disabled control" ->
    s = growing_recycle_fixture(65536, false)
    s.reduce_db
    expect(s.ncl).to eq(65536)
    expect(s.rhist[75]).to eq(0)
    expect(s.solve["status"]).to eq(1)

  it "keeps small tables and unavailable index maps on the existing path" ->
    s = growing_recycle_fixture(32, true)
    s.reduce_db
    expect(s.ncl).to eq(32)
    expect(s.rhist[75]).to eq(0)
    t = growing_recycle_fixture(65536, true, true)
    t.reduce_db
    expect(t.ncl).to eq(65536)
    expect(t.rhist[75]).to eq(0)
    expect(t.solve["status"]).to eq(1)

  it "retains mostly-live large tables" ->
    s = growing_recycle_fixture(65536, true)
    s.append_duplicates(65531)
    before = s.ncl
    s.reduce_db
    expect(s.ncl).to eq(before)
    expect(s.rhist[75]).to eq(0)

  it "never recycles proof-mode clause indices" ->
    s = growing_recycle_fixture(65536, true, false, WASSAT_PROOF_DRAT)
    s.reduce_db
    expect(s.ncl).to eq(65536)
    expect(s.rhist[75]).to eq(0)

spec_summary
