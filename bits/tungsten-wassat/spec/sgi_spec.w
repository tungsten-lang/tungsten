use spec
use ../lib/wassat

-> sgi_supported_fixture(rotated = false)
  canon = i64[3 * 30]
  pattern = i64[3]
  host = i64[30]
  forbidden = i64[22 * 22 * 30]
  p = 0
  while p < 3
    h = 0
    while h < 30
      canon[p * 30 + h] = rotated ? (h + p) % 30 : h
      h += 1
    p += 1
  pattern[0] = 2
  pattern[1] = 1
  h = 0
  while h < 30
    host[h] = 1073741823 ^ (1 << h)
    h += 1
  p = 0
  while p < 3
    q = p + 1
    while q < 3
      h = 0
      while h < 30
        k = 0
        while k < 30
          if canon[p * 30 + h] == canon[q * 30 + k]
            forbidden[(p * 22 + q) * 30 + h] = 1 << k
          k += 1
        h += 1
      q += 1
    p += 1
  [canon, pattern, host, forbidden]

describe "Wassat SGI original-clause support" ->
  it "accepts a complete host graph with original injectivity clauses" ->
    f = sgi_supported_fixture
    expect(wassat_sgi_graph_supported?(3, f[0], f[1], f[2], f[3])).to eq(true)

  it "accepts independent permutations of each domain" ->
    f = sgi_supported_fixture(true)
    expect(wassat_sgi_graph_supported?(3, f[0], f[1], f[2], f[3])).to eq(true)

  it "rejects an invented host-edge exclusion" ->
    f = sgi_supported_fixture
    host = f[2]
    host[0] = host[0] ^ 2
    host[1] = host[1] ^ 1
    expect(wassat_sgi_graph_supported?(3, f[0], f[1], host, f[3])).to eq(false)

  it "rejects missing injectivity even between nonadjacent pattern vertices" ->
    f = sgi_supported_fixture
    forbidden = f[3]
    forbidden[2 * 30 + 7] = 0
    expect(wassat_sgi_graph_supported?(3, f[0], f[1], f[2], forbidden)).to eq(false)

  it "rejects a canonical map that merges domain values" ->
    f = sgi_supported_fixture
    canon = f[0]
    canon[31] = 0
    expect(wassat_sgi_graph_supported?(3, canon, f[1], f[2], f[3])).to eq(false)

  it "accepts restrictive host edges only when every exclusion has a clause" ->
    f = sgi_supported_fixture
    host = f[2]
    forbidden = f[3]
    h = 0
    while h < 30
      host[h] = 1 << (h ^ 1)
      forbidden[30 + h] = 1073741823 ^ host[h]
      h += 1
    expect(wassat_sgi_graph_supported?(3, f[0], f[1], host, forbidden)).to eq(true)

spec_summary
