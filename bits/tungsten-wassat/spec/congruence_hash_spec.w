use spec
use ../lib/solver

-> xor_hash_probe(clauses, nv, mixed, outcap = 64)
  nc = clauses.size
  nl = 0
  clauses.each ->(c) nl += c.size
  cm = i64[2 * nc]
  alive = i8[nc]
  ar = i64[nl]
  p = 0
  ci = 0
  while ci < nc
    cm[2 * ci] = p
    cm[2 * ci + 1] = clauses[ci].size
    alive[ci] = 1
    clauses[ci].each ->(l)
      ar[p] = l
      p += 1
    ci += 1
  chcap = 1024
  chcap *= 2 while chcap < 2 * (nc + 16)
  nli = 2 * nv + 4
  out = i64[2 * outcap]
  st = i64[8]
  wassat_extract_xor_gates(cm, alive, ar, i8[nli], i64[nli], i64[chcap],
    i64[nli], i64[8], i64[4096], i64[2048], out, st, nc, nli,
    chcap - 1, 4096, 2047, outcap, mixed)
  result = [st[0], st[1], st[2]]
  k = 0
  while k < 2 * st[0]
    result.push(out[k])
    k += 1
  [result, st]

-> hash_xor_pair
  [[-1, -2, -3], [-1, 2, 3], [1, -2, 3], [1, 2, -3],
   [-1, -2, -4], [-1, 2, 4], [1, -2, 4], [1, 2, -4]]

describe "Congruence clause hash" ->
  it "keeps complete XOR gates and ordered merge outputs" ->
    old = xor_hash_probe(hash_xor_pair, 4, 0)
    mixed = xor_hash_probe(hash_xor_pair, 4, 1)
    expect(mixed[0]).to eq(old[0])
    expect(mixed[0][0] > 0).to eq(true)
    expect(mixed[1][3]).to eq(8)

  it "does not let duplicate literals impersonate a parity sibling" ->
    cs = [[1, 2, 3], [-1, -2, 3], [-1, 2, -3], [1, -2, -2]]
    r = xor_hash_probe(cs, 3, 1)
    expect(r[0]).to eq([0, 0, 0])
    expect(r[1][3]).to eq(3)

  it "preserves bounded extraction and literal permutation" ->
    cs = hash_xor_pair.map ->(c) c.reverse
    old = xor_hash_probe(cs, 4, 0, 1)
    mixed = xor_hash_probe(cs, 4, 1, 1)
    expect(mixed[0]).to eq(old[0])
    expect(mixed[0][2]).to eq(1)

  it "separates equal-sum keys without manufacturing gates" ->
    cs = []
    a = 1
    while a <= 12
      b = a + 1
      while b <= 24
        c = 60 - a - b
        cs.push([-a, -b, -c]) if c > b
        b += 1
      a += 1
    old = xor_hash_probe(cs, 60, 0)
    mixed = xor_hash_probe(cs, 60, 1)
    expect(mixed[0]).to eq(old[0])
    expect(mixed[0]).to eq([0, 0, 0])
    expect(mixed[1][4] < old[1][4]).to eq(true)

spec_summary
