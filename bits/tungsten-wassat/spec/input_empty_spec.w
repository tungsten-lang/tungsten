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

spec_summary
