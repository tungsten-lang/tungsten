use spec
use ../lib/wassat

# A depth-two, binary AND/OR chain with two formulas, in original CNF.
-> formula_chain_fixture
  rows = [[1], [2], [-9], [-11], [13, 14], [-13, -14], [14, 15], [-14, -15], [16, 17], [-16, -17], [17, 18], [-17, -18], [19, 20], [-19, -20], [20, 21], [-20, -21], [-16, -1, 5], [-17, -1, 6], [-17, -2, 5], [-18, -2, 6], [-19, -3, 7], [-20, -3, 8], [-20, -4, 7], [-21, -4, 8], [-13, -5, 9], [-13, -6, 10], [-14, -5, 11], [-14, -6, 12], [-14, -7, 9], [-14, -8, 10], [-15, -7, 11], [-15, -8, 12]]
  nc = rows.size; nl = 0
  rows.each ->(c) nl += c.size
  lits = i64[nl]; offs = i64[nc]; lens = i64[nc]; i = 0; p = 0
  rows.each ->(c)
    offs[i] = p; lens[i] = c.size
    c.each ->(x)
      lits[p] = x; p += 1
    i += 1
  { "nvars": 21, "flat_ncl": nc, "flat_nlits": nl,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens }

describe "Clause-checked monotone formula chains" ->
  it "checks all clauses before refuting the root transition" ->
    f = formula_chain_fixture; m = i64[32]
    expect(wassat_chain_refute(f, m, i64[2])).to eq(-1)
    expect(m[2]).to eq(32)
    expect(m[4]).to eq(2)
    expect(m[5]).to eq(2)
    expect(m[13]).to eq(16)

  it "accepts watched-literal permutations" ->
    f = formula_chain_fixture; i = 0
    while i < f["flat_ncl"]
      a = f["flat_offs"][i]; b = a + f["flat_lens"][i] - 1
      x = f["flat_lits"][a]; f["flat_lits"][a] = f["flat_lits"][b]; f["flat_lits"][b] = x; i += 1
    expect(wassat_chain_refute(f, i64[32], i64[2])).to eq(-1)

  it "requires both forced endpoint root values" ->
    f = formula_chain_fixture; f["flat_lits"][1] = 3
    expect(wassat_chain_refute(f, i64[32], i64[2])).to eq(0)
    # Both false leaves now belong to the same AND child.
    f = formula_chain_fixture; f["flat_lits"][3] = -10
    expect(wassat_chain_refute(f, i64[32], i64[2])).to eq(0)
    # Either leaf can force the other AND child false.
    f["flat_lits"][3] = -12
    expect(wassat_chain_refute(f, i64[32], i64[2])).to eq(-1)

  it "rejects missing selector choices and exclusivity" ->
    [4, 5].each ->(ci)
      f = formula_chain_fixture; p = f["flat_offs"][ci]
      f["flat_lits"][p] = f["flat_lits"][p + 1]
      expect(wassat_chain_refute(f, i64[32], i64[2])).to eq(0)

  it "rejects reversed and misaligned leaf implications" ->
    [16, 24, 31].each ->(ci)
      f = formula_chain_fixture; p = f["flat_offs"][ci]
      f["flat_lits"][p + 1] = -f["flat_lits"][p + 1]
      expect(wassat_chain_refute(f, i64[32], i64[2])).to eq(0)

  it "does not accept a truncated transition" ->
    f = formula_chain_fixture; f["flat_ncl"] -= 1
    expect(wassat_chain_refute(f, i64[32], i64[2])).to eq(0)

  it "rejects out-of-range offsets and short scratch buffers" ->
    f = formula_chain_fixture; f["flat_offs"][16] = f["flat_nlits"]
    expect(wassat_chain_refute(f, i64[32], i64[2])).to eq(0)
    expect(wassat_chain_refute(f, i64[2], i64[2])).to eq(0)
    expect(wassat_chain_refute(f, i64[32], i64[1])).to eq(0)

  it "rejects invalid dimensions and foreign variables" ->
    f = formula_chain_fixture; f["nvars"] = 20
    expect(wassat_chain_refute(f, i64[32], i64[2])).to eq(0)
    f = formula_chain_fixture; f["flat_lits"][2] = -22
    expect(wassat_chain_refute(f, i64[32], i64[2])).to eq(0)

  it "declines 32-bit flat storage before decoding" ->
    f = formula_chain_fixture
    f["flat_lits_bits"] = 32
    f["flat_lits"] = i32[1]
    expect(wassat_chain_refute(f, i64[32], i64[2])).to eq(0)

  it "honors cancellation and deadlines before allocating scratch" ->
    f = formula_chain_fixture; m = i64[32]; stop = i64[2]
    z = wassat_stop_cancel(stop)
    expect(wassat_chain_refute(f, m, stop)).to eq(0)
    expect(m[0]).to eq(1)
    expect(m[10]).to eq(0)
    expect(wassat_chain_refute(f, m, i64[2], clock_ms() - 1)).to eq(0)
    expect(m[0]).to eq(2)

  it "allows interrupted or unpublished scouts to retry" ->
    f = {}; m = i64[32]; p = { "meta": m }
    m[0] = 1; wassat_chain_finish_scout(f, p)
    expect(f["formula_chain_done"]).to eq(false)
    m[0] = 0; m[16] = -1; wassat_chain_finish_scout(f, p)
    expect(f["formula_chain_done"]).to eq(false)
    m[16] = 0; wassat_chain_finish_scout(f, p)
    expect(f["formula_chain_done"]).to eq(true)
