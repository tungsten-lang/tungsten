use spec
use ../lib/solver

-> pool_fixture(ncl, extra)
  nlits = 28
  ar = i64[4 * ncl + 4]
  cm = i64[2 * ncl]
  alive = i64[ncl]
  entries = 0
  ci = 0
  while ci < ncl
    st = 1 + 4 * ci
    cm[2 * ci] = st
    cm[2 * ci + 1] = ci % 11 == 0 ? 2 : 3
    alive[ci] = ci % 7 == 0 ? 0 : 1
    ar[st] = ci % 3 == 0 ? -1 : 1
    ar[st + 1] = ci % 2 == 0 ? 2 : -2
    ar[st + 2] = 3 + ci % 9
    entries += 2 if alive[ci] == 1 && cm[2 * ci + 1] >= 3
    ci += 1
  cap = entries + nlits + extra
  wd = i64[4 * nlits]
  wp = i64[cap + 2]
  ws = i64[8]
  ws[1] = cap
  wp[cap] = 8273
  wp[cap + 1] = 19285
  z = wassat_ws_rebuild(cm, alive, ar, wd, wp, ws, ncl, nlits)
  { "ar": ar, "cm": cm, "alive": alive, "wd": wd, "wp": wp,
    "ws": ws, "entries": entries, "cap": cap, "ncl": ncl, "nlits": nlits }

-> pool_li(l)
  l > 0 ? 2 * l : 2 * (0 - l) + 1

-> pool_check(result)
  ar = result["ar"] ## i64[]
  cm = result["cm"] ## i64[]
  alive = result["alive"] ## i64[]
  wd = result["wd"] ## i64[]
  wp = result["wp"] ## i64[]
  ws = result["ws"] ## i64[]
  ncl = result["ncl"]
  cap = result["cap"]
  seen = i64[ncl]
  total = 0
  last_end = 0
  li = 0
  while li < result["nlits"]
    d = 4 * li
    expect(wd[d] >= last_end).to eq(true)
    expect(wd[d + 1] <= wd[d + 2]).to eq(true)
    last_end = wd[d] + wd[d + 2]
    j = 0
    previous = 0
    while j < wd[d + 1]
      word = wp[wd[d] + j] ## i64
      st = word >> 32
      blocker = word & 4294967295
      ci = (st - 1) / 4
      expect(ci >= 0 && ci < ncl).to eq(true)
      expect(alive[ci]).to eq(1)
      expect(cm[2 * ci + 1] >= 3).to eq(true)
      expect(st > previous).to eq(true)
      previous = st
      first = pool_li(ar[st])
      second = pool_li(ar[st + 1])
      expect((li == first && blocker == second) || (li == second && blocker == first)).to eq(true)
      seen[ci] += 1
      total += 1
      j += 1
    li += 1
  ci = 0
  while ci < ncl
    expected = alive[ci] == 1 && cm[2 * ci + 1] >= 3 ? 2 : 0
    expect(seen[ci]).to eq(expected)
    ci += 1
  expect(total).to eq(result["entries"])
  expect(ws[3]).to eq(1)
  expect(ws[4]).to eq(total)
  expect(last_end).to eq(ws[0])
  expect(ws[0] <= cap).to eq(true)
  expect(ws[0] <= result["entries"] + result["nlits"] + result["entries"] / 4).to eq(true)
  expect(wp[cap]).to eq(8273)
  expect(wp[cap + 1]).to eq(19285)

describe "Wassat watch-pool headroom" ->
  it "retains every live long-clause watch in a tightly sized pool" ->
    result = pool_fixture(96, 0)
    pool_check(result)
    expect(result["ws"][0]).to eq(result["cap"])

  it "keeps dense lists intact with limited relocation space" ->
    result = pool_fixture(2048, 512)
    pool_check(result)
    # Positive literal 1 is dense and must have room for several appends.
    expect(result["wd"][10] > result["wd"][9] + 1).to eq(true)

  it "does not spread a small database across an oversized pool" ->
    result = pool_fixture(96, 100000)
    pool_check(result)
    expect(result["ws"][0]).to eq(result["entries"] + result["nlits"])

  it "bounds extra capacity in a dense oversized pool" ->
    pool_check(pool_fixture(2048, 100000))

  it "handles an empty watch database without division by zero" ->
    pool_check(pool_fixture(0, 64))

spec_summary
