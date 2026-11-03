use spec
use ../lib/solver

describe "Clause recycling cursors" ->
  it "continues at the next surviving clause through a deleted gap" ->
    map = i64[6]
    map[0] = 0; map[1] = -1; map[2] = -1
    map[3] = 1; map[4] = -1; map[5] = 2
    expect(wassat_recycle_cursor(map, 6, 3, 1)).to eq(1)
    expect(wassat_recycle_cursor(map, 6, 3, 3)).to eq(1)
    expect(wassat_recycle_cursor(map, 6, 3, 4)).to eq(2)

  it "preserves an end cursor for clauses appended after compaction" ->
    map = i64[3]
    map[0] = 0; map[1] = -1; map[2] = -1
    expect(wassat_recycle_cursor(map, 3, 1, 1)).to eq(1)
    expect(wassat_recycle_cursor(map, 3, 1, 3)).to eq(1)
    expect(wassat_recycle_cursor(map, 3, 1, 9)).to eq(1)

  it "handles an empty table and a surviving prefix" ->
    map = i64[1]
    expect(wassat_recycle_cursor(map, 0, 0, 0)).to eq(0)
    expect(wassat_recycle_cursor(map, 1, 1, 0)).to eq(0)

spec_summary
