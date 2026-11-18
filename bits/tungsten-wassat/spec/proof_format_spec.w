use spec
use ../lib/solver

-> proof_bytes_equal(buf, start, n, text)
  return false unless n == text.size
  i = 0
  while i < n
    return false unless buf[start + i] == text.byte_at(i)
    i += 1
  true

describe "Native hinted proof formatting" ->
  it "writes signed literals and full-width positive IDs at a nonzero offset" ->
    b = u8[200]
    ls = i64[3]
    hs = i64[3]
    ls[0] = -2147483647
    ls[1] = 2147483647
    ls[2] = -1
    hs[0] = 1
    hs[1] = 281474976710656
    hs[2] = 9223372036854775807
    n = wassat_wrat_put(b, 7, 200, 9223372036854775807, ls, 3, hs, 3)
    expected = "9223372036854775807 -2147483647 2147483647 -1 0 1 281474976710656 9223372036854775807 0\n"
    expect(proof_bytes_equal(b, 7, n - 7, expected)).to eq(true)
    expect(b[6]).to eq(0)
    expect(b[n]).to eq(0)

  it "preserves empty-clause and empty-hint text" ->
    b = u8[64]
    a = i64[1]
    n = wassat_wrat_put(b, 0, 64, 10, a, 0, a, 0)
    expect(proof_bytes_equal(b, 0, n, "10 0  0\n")).to eq(true)

  it "rejects insufficient capacity and overflowing lengths without writing" ->
    b = u8[64]
    a = i64[1]
    a[0] = 1
    expect(wassat_wrat_put(b, 0, 56, 10, a, 1, a, 1)).to eq(-1)
    expect(wassat_wrat_put(b, 0, 64, 10, a, 9223372036854775807, a, 1)).to eq(-1)
    expect(wassat_wrat_put(b, 0, 64, 10, a, 1, a, 9223372036854775807)).to eq(-1)
    expect(wassat_wrat_put(b, 65, 64, 10, a, 0, a, 0)).to eq(-1)
    expect(wassat_wrat_put(b, -1, 64, 10, a, 0, a, 0)).to eq(-1)
    i = 0
    while i < 64
      expect(b[i]).to eq(0)
      i += 1
    expect(wassat_wrat_put(b, 0, 57, 10, a, 1, a, 1) > 0).to eq(true)
