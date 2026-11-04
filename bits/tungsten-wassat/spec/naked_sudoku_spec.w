use spec
use naked_sudoku_support

describe "Clause-checked naked-single progress refutation" ->
  it "keeps a satisfiable finite-progress boundary" ->
    m = i64[64]
    f = NakedTestFormula.new(1, [0,1,2]).formula
    expect(wassat_naked_refute(f, m, i64[2])).to eq(0)
    expect(m[16]).to eq(5)
    expect(m[27]).to eq(1)
  it "refutes a checked requirement for too many progress stages" ->
    m = i64[64]; f = NakedTestFormula.new(2, [0,1,2]).formula
    expect(wassat_naked_refute(f, m, i64[2])).to eq(-1)
    expect(m[16]).to eq(5)
    expect(m[27]).to eq(1)
    expect(m[28]).to eq(3)
  it "declines a satisfiable completion layout" ->
    f = NakedTestFormula.new(2, [1,6,9,14]).formula; m = i64[64]
    expect(wassat_naked_refute(f, m, i64[2])).to eq(0)
    expect(m[16]).to eq(5)
  ["chains", "placements", "candidates", "progress", "rules", "singles", "nonempty"].each -> (section)
    it "requires the original [section] implication" ->
      f = NakedTestFormula.new(2, [0,1,2]).formula(section); m = i64[64]
      expect(wassat_naked_refute(f, m, i64[2])).to eq(0)
      expect(m[16] < 5).to eq(true)
  it "rejects malformed flat storage before indexing" ->
    f = NakedTestFormula.new(1, [0,1,2]).formula
    offs = f["flat_offs"]; lens = f["flat_lens"]; lits = f["flat_lits"]
    old = offs[0]; offs[0] = 9223372036854775807
    expect(wassat_naked_refute(f, i64[64], i64[2])).to eq(0)
    offs[0] = old; old = offs[100]; offs[100] = offs[99]
    expect(wassat_naked_refute(f, i64[64], i64[2])).to eq(0)
    offs[100] = old; old = lens[100]; lens[100] = 1025
    expect(wassat_naked_refute(f, i64[64], i64[2])).to eq(0)
    lens[100] = old; old = lits[200]; lits[200] = f["nvars"] + 1
    expect(wassat_naked_refute(f, i64[64], i64[2])).to eq(0)
    lits[200] = old; f["flat_offs"] = i64[1]
    expect(wassat_naked_refute(f, i64[64], i64[2])).to eq(0)
  it "checks cancellation and deadline before allocating index buffers" ->
    f = NakedTestFormula.new(1, [0,1,2]).formula; m = i64[64]; stop = i64[2]
    wassat_stop_cancel(stop)
    expect(wassat_naked_refute(f, m, stop)).to eq(0)
    expect(m[0]).to eq(1)
    expect(m[30]).to eq(0)
    expect(wassat_naked_refute(f, m, i64[2], clock_ms() - 1)).to eq(0)
    expect(m[0]).to eq(2)
    expect(m[30]).to eq(0)
    expect(wassat_naked_refute(f, i64[1], i64[2])).to eq(0)
    expect(wassat_naked_refute(f, i64[64], i64[1])).to eq(0)
  it "does not use a hash collision as a clause certificate" ->
    # A one-bucket table deliberately collides every clause. The queried
    # literal set must equal the original, including distinctness.
    ks = i64[16]; m = i64[64]; stop = i64[2]
    lits = i64[2]; offs = i64[1]; lens = i64[1]; heads = i32[1]; links = i32[1]
    marks = i32[8]; seen = i32[8]; query = i32[2]
    ks[6] = 3; lens[0] = 2; heads[0] = 1
    query[0] = 1; query[1] = 2; lits[0] = 1; lits[1] = 1
    expect(wassat_naked_k_has_clause(ks,m,stop,lits,offs,lens,heads,links,marks,seen,query,2)).to eq(false)
    lits[1] = 3
    expect(wassat_naked_k_has_clause(ks,m,stop,lits,offs,lens,heads,links,marks,seen,query,2)).to eq(false)
    lits[1] = 2
    expect(wassat_naked_k_has_clause(ks,m,stop,lits,offs,lens,heads,links,marks,seen,query,2)).to eq(true)
  it "does not turn a search cap into a refutation" ->
    # Direct kernel contract: a single forced node at a zero cap must stop.
    m = i64[16]
    wassat_naked_search(i64[16],i64[4],i64[4],i64[4],i32[16],i8[16],0,4,2,m,i64[2],0,0)
    expect(m[6]).to eq(3)
    expect(m[5]).to eq(0)

spec_summary
