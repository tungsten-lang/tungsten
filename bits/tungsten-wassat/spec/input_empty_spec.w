use spec
use ../lib/cnf
use ../lib/policy

-> empty_lengths(values)
  out = i64[values.size]
  i = 0
  while i < values.size
    out[i] = values[i]
    i += 1
  out

describe "Original empty-clause recognition" ->
  it "agrees between boxed and flat shape inspection" ->
    cs = [[1, 2], [], [-2], [], [1, 2, 3]]
    boxed = WassatConfig.new(3, cs)
    lens = empty_lengths([2, 0, 1, 0, 3])
    flat = WassatConfig.from_lens(3, lens, 5)
    expect(boxed.empty_clause_count).to eq(2)
    expect(flat.empty_clause_count).to eq(2)
    expect(wassat_first_empty_clause(lens, 5)).to eq(2)

  it "distinguishes an empty formula from a formula containing an empty clause" ->
    expect(WassatConfig.new(0, []).empty_clause_count).to eq(0)
    expect(WassatConfig.from_lens(0, i64[0], 0).empty_clause_count).to eq(0)
    expect(wassat_first_empty_clause(i64[0], 0)).to eq(0)
    lens = empty_lengths([0])
    expect(WassatConfig.new(0, [[]]).empty_clause_count).to eq(1)
    expect(WassatConfig.from_lens(0, lens, 1).empty_clause_count).to eq(1)
    expect(wassat_first_empty_clause(lens, 1)).to eq(1)

  it "does not confuse tautologies and units with empty clauses" ->
    cs = [[1, -1], [2], [-2]]
    lens = empty_lengths([2, 1, 1])
    expect(WassatConfig.new(2, cs).empty_clause_count).to eq(0)
    expect(WassatConfig.from_lens(2, lens, 3).empty_clause_count).to eq(0)
    expect(wassat_first_empty_clause(lens, 3)).to eq(0)

  it "matches the accumulating kernel across prefixes and vector-sized tails" ->
    test = 0
    while test < 128
      n = test % 70
      lens = i64[72]
      j = 0
      while j < 72
        lens[j] = (test * 17 + j * 23) % 37
        j += 1
      expected = i64[8]
      wassat_shape_counts(lens, n, expected)
      actual = wassat_shape_counts_new(lens, n)
      expect(actual).to eq(expected)
      j = 0
      while j < 72
        expect(lens[j]).to eq((test * 17 + j * 23) % 37)
        j += 1
      test += 1

  it "retains wide literal totals and the longest clause" ->
    lens = empty_lengths([2147483640, 2147483640, 0, 1, 2, 3])
    out = wassat_shape_counts_new(lens, 6)
    expect(out[0]).to eq(4294967286)
    expect(out[1]).to eq(2147483640)
    expect(out[2]).to eq(1)
    expect(out[3]).to eq(1)
    expect(out[4]).to eq(1)
    expect(out[5]).to eq(1)

  it "preserves accumulation into an existing output buffer" ->
    lens = empty_lengths([0, 1, 2, 3, 4])
    out = empty_lengths([11, 50, 3, 4, 5, 6, 0, 0])
    wassat_shape_counts(lens, 5, out)
    expect(out).to eq(empty_lengths([21, 50, 4, 5, 6, 7, 0, 0]))

spec_summary
