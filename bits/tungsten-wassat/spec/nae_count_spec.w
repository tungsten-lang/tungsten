use spec
use ../lib/wassat

-> wassat_nae_fixture(rows, nv)
  heads = i32[nv + 1]
  width = i8[rows.size]
  remain = i32[rows.size]
  counts = i8[2 * rows.size]
  si = 0
  rows.each -> (row)
    width[si] = row.size
    row.each -> (v)
      heads[v + 1] += 1
      remain[si] ^= v
    si += 1
  v = 0
  while v < nv
    heads[v + 1] += heads[v]
    v += 1
  inc = i32[heads[nv]]
  fill = i32[nv]
  si = 0
  rows.each -> (row)
    row.each -> (v)
      inc[heads[v] + fill[v]] = si
      fill[v] += 1
    si += 1
  asg = i8[nv]
  order = i32[nv]
  v = 0
  while v < nv
    asg[v] = -1
    order[v] = v
    v += 1
  m = i64[16]
  m[3] = 1000000
  m[9] = 32768
  { "asg": asg, "heads": heads, "inc": inc, "width": width,
    "counts": counts, "remain": remain, "order": order,
    "trail": i32[nv + 1], "meta": m, "stop": i64[4] }

-> wassat_nae_fixture_solve(f, nv)
  if wassat_nae_propagate(f["asg"], f["trail"], f["heads"], f["inc"], f["width"],
    f["counts"], f["remain"], f["meta"], f["stop"], 0, 0) == 0
    return f["meta"][5] == 0 ? -1 : 0
  wassat_nae_dfs(f["asg"], f["trail"], f["heads"], f["inc"], f["width"],
    f["counts"], f["remain"], f["order"], f["meta"], f["stop"], nv)

-> wassat_nae_oracle(rows, nv)
  mask = 0
  while mask < (1 << nv)
    valid = true
    rows.each -> (row)
      zero = false
      one = false
      row.each -> (v)
        if ((mask >> v) & 1) == 0
          zero = true
        else
          one = true
      valid = false unless zero && one
    return 1 if valid
    mask += 1
  -1

describe "Incremental complementary scope counters" ->
  it "agrees with full enumeration on varied overlapping scopes" ->
    seed = 17
    trial = 0
    while trial < 40
      nv = 3 + trial % 5
      rows = []
      a = 0
      while a < nv
        b = a + 1
        while b < nv
          c = b + 1
          while c < nv
            seed = (seed * 1664525 + 1013904223) & 2147483647
            rows.push([a, b, c]) if seed % 4 < trial % 4
            c += 1
          b += 1
        a += 1
      rows.push([0, nv - 1]) if trial % 3 == 0
      f = wassat_nae_fixture(rows, nv)
      got = wassat_nae_fixture_solve(f, nv)
      expect(got).to eq(wassat_nae_oracle(rows, nv))
      if got == 1
        rows.each -> (row)
          sum = 0
          row.each -> (v) sum += f["asg"][v]
          expect(sum > 0 && sum < row.size).to eq(true)
      trial += 1

  it "undoes processed and pending assignments after conflicting implications" ->
    rows = [[0, 1], [0, 2], [1, 2]]
    f = wassat_nae_fixture(rows, 3)
    expect(wassat_nae_propagate(f["asg"], f["trail"], f["heads"], f["inc"], f["width"],
      f["counts"], f["remain"], f["meta"], f["stop"], 0, 0)).to eq(0)
    wassat_nae_undo(f["asg"], f["trail"], f["heads"], f["inc"], f["counts"], f["remain"], f["meta"], 0)
    expect(f["meta"][0]).to eq(0)
    expect(f["meta"][1]).to eq(0)
    i = 0
    while i < 3
      expect(f["asg"][i]).to eq(-1)
      expect(f["counts"][2 * i]).to eq(0)
      expect(f["counts"][2 * i + 1]).to eq(0)
      expect(f["remain"][i]).to eq(rows[i][0] ^ rows[i][1])
      i += 1

  it "returns unknown on node exhaustion and cancellation" ->
    f = wassat_nae_fixture([[0, 1, 2, 3]], 4)
    f["meta"][3] = 1
    expect(wassat_nae_fixture_solve(f, 4)).to eq(0)
    expect(f["meta"][5]).to eq(1)
    f = wassat_nae_fixture([[0, 1, 2, 3]], 4)
    wassat_stop_cancel(f["stop"])
    expect(wassat_nae_fixture_solve(f, 4)).to eq(0)
    expect(f["meta"][5]).to eq(3)

  it "returns unknown when its deadline has expired" ->
    f = wassat_nae_fixture([[0, 1, 2, 3]], 4)
    f["meta"][4] = clock_ms() - 1
    expect(wassat_nae_fixture_solve(f, 4)).to eq(0)
    expect(f["meta"][5]).to eq(2)

spec_summary
