use spec
use ../lib/solver

-> arena_format_matches(buf, from, to, text)
  return false if to - from != text.size
  i = 0
  while i < text.size
    return false if buf[from + i] != text.byte_at(i)
    i += 1
  true

describe "Compact arena DRAT records" ->
  it "formats signed 32-bit boundary literals at nonzero offsets" ->
    lits = i32[4]
    lits[0] = 99
    lits[1] = -2147483647
    lits[2] = 2147483647
    lits[3] = -1
    buf = u8[100]
    n = wassat_drat_put32(buf, 3, 100, lits, 1, 3, 1)
    expect(arena_format_matches(buf, 3, n, "d -2147483647 2147483647 -1 0\n")).to eq(true)
    expect(buf[2]).to eq(0)
    expect(buf[n]).to eq(0)

  it "rejects a short buffer without writing and formats the empty clause" ->
    lits = i32[1]
    lits[0] = -1
    buf = u8[32]
    expect(wassat_drat_put32(buf, 3, 20, lits, 0, 1, 1)).to eq(-1)
    i = 0
    while i < 32
      expect(buf[i]).to eq(0)
      i += 1
    n = wassat_drat_put32(buf, 3, 21, lits, 0, 1, 1)
    expect(arena_format_matches(buf, 3, n, "d -1 0\n")).to eq(true)
    n = wassat_drat_put32(buf, 3, 32, lits, 0, 0, 0)
    expect(arena_format_matches(buf, 3, n, "0\n")).to eq(true)

spec_summary
