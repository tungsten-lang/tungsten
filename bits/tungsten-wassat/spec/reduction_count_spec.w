use spec
use ../lib/solver

+ RecountFixture < Wassat
  ro :nlearned, :rhist

  -> mark(ci, glue)
    @clbd[ci] = glue
    @nlearned += 1

  -> configure(reuse, clean, fixed)
    @reuse_reduce_count = reuse
    @need_clean = clean
    @last_reduce_at = 10
    @conflicts = 20
    @fixed_caps = fixed
    @gid = i64[@ccap] if fixed

  -> actual_learned
    count = 0
    ci = 0
    while ci < @ncl
      count += 1 if @alive[ci] == 1 && @clbd[ci] > 0
      ci += 1
    count

-> recount_fixture(reuse, fixed, proof)
  s = RecountFixture.new(6, [[1, 2, 3], [4, 5, 6], [-4, 5, 6], [-5, -4, 6]], proof, 0)
  s.mark(1, 3)
  s.mark(2, 4)
  s.mark(3, 8)
  s.configure(reuse, false, fixed)
  s

describe "Reduction count reuse" ->
  it "returns the surviving learned count after selection" ->
    cm = i64[6]; alive = i8[3]; lbd = i64[3]; used = i64[3]; hist = i64[70]
    i = 0
    while i < 3
      cm[2 * i + 1] = 3
      alive[i] = 1
      lbd[i] = i == 0 ? 0 : (i == 1 ? 2 : 8)
      i += 1
    expect(wassat_reduce_select(cm, alive, lbd, used, hist, 3, 10)).to eq(1)
    expect([alive[0], alive[1], alive[2]]).to eq([1, 1, 0])

  it "reuses the count while preserving stable clause indices" ->
    s = recount_fixture(true, false, WASSAT_PROOF_NONE)
    s.reduce_db
    expect(s.nlearned).to eq(2)
    expect(s.nlearned).to eq(s.actual_learned)
    expect(s.rhist[73]).to eq(0)
    expect(s.rhist[74]).to eq(4)
    s.reduce_db
    expect(s.nlearned).to eq(s.actual_learned)
    expect(s.rhist[74]).to eq(8)

  it "retains the count through fixed-capacity clause renumbering" ->
    s = recount_fixture(true, true, WASSAT_PROOF_NONE)
    s.reduce_db
    expect(s.nlearned).to eq(2)
    expect(s.nlearned).to eq(s.actual_learned)
    expect(s.rhist[74]).to eq(3)

  it "retains the explicit recount control" ->
    s = recount_fixture(false, false, WASSAT_PROOF_NONE)
    s.reduce_db
    expect(s.nlearned).to eq(s.actual_learned)
    expect(s.rhist[73]).to eq(4)
    expect(s.rhist[74]).to eq(0)

  it "recounts after root cleaning removes a learned clause" ->
    s = RecountFixture.new(4, [[1], [1, 2, 3], [-1, 2, 3], [2, 3, 4]], WASSAT_PROOF_NONE, 0)
    s.mark(1, 2)
    s.mark(2, 2)
    s.mark(3, 2)
    s.configure(true, true, false)
    s.reduce_db
    expect(s.nlearned).to eq(2)
    expect(s.nlearned).to eq(s.actual_learned)
    expect(s.rhist[73]).to eq(4)
    expect(s.rhist[74]).to eq(0)
    s.reduce_db
    expect(s.nlearned).to eq(s.actual_learned)
    expect(s.rhist[74]).to eq(4)

  it "keeps proof-mode accounting exact without arena compaction" ->
    s = recount_fixture(true, false, WASSAT_PROOF_WRAT)
    s.reduce_db
    expect(s.nlearned).to eq(2)
    expect(s.nlearned).to eq(s.actual_learned)
    expect(s.rhist[74]).to eq(4)

  it "returns zero for an empty learned population" ->
    cm = i64[1]; alive = i8[1]; lbd = i64[1]; used = i64[1]; hist = i64[70]
    expect(wassat_reduce_select(cm, alive, lbd, used, hist, 0, 0)).to eq(0)

  it "keeps large recount telemetry in the native slab" ->
    hist = i64[75]
    wassat_reduce_count_note(hist, 2000000000, 1)
    wassat_reduce_count_note(hist, 2000000000, 1)
    wassat_reduce_count_note(hist, 7, 0)
    expect(hist[74]).to eq(4000000000)
    expect(hist[73]).to eq(7)

spec_summary
