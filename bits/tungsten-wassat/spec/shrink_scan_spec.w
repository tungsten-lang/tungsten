use spec
use ../lib/solver

-> shrink_scan_fixture(interleaved, failed, fallback)
  nv = 8
  ar = i64[8]
  ar[0] = -1
  ar[1] = 2
  ar[2] = -1
  ar[3] = 3
  ar[4] = -2
  ar[5] = 5
  ar[6] = -4
  ar[7] = 6
  cm = i64[8]
  ci = 0
  while ci < 4
    cm[2 * ci] = 2 * ci
    cm[2 * ci + 1] = 2
    ci += 1
  asg = i8[nv + 3]
  lvl = i64[nv + 3]
  rsn = i32[nv + 3]
  sn = i8[nv + 3]
  tr = i64[nv + 3]
  tlim = i64[nv + 3]
  out = i64[nv + 3]
  tmp = i64[nv + 3]
  stk = i64[nv + 3]
  dstk = i64[nv + 3]
  tclr = i64[nv + 3]
  cnt = i64[nv + 3]
  st = i64[8]
  v = 1
  while v <= nv
    asg[v] = 1
    lvl[v] = v - 2
    lvl[v] = 1 if v <= 3
    rsn[v] = -1
    tr[v - 1] = v
    v += 1
  rsn[2] = 0 unless failed
  rsn[3] = 1 unless failed
  tlim[1] = 3
  tlim[2] = 4
  tlim[3] = 5
  tlim[4] = 6
  out[0] = -6
  out[1] = -2
  out[2] = -3
  out[3] = -4
  out[4] = -5
  st[0] = 5
  if interleaved
    # A marked foreign-level entry and an unmarked same-level entry sit
    # inside the block. Neither may become its next resolution pivot.
    tr[2] = 4
    tr[3] = 7
    tr[4] = 3
    tr[5] = 5
    tr[6] = 6
    lvl[7] = 1
    tlim[1] = 5
    tlim[2] = 5
    tlim[3] = 6
    tlim[4] = 7
  if fallback
    # The first block proves 2 and 3 removable via 1. The later block
    # cannot resolve through the uncovered decision 4, but its fallback
    # can remove 5 via 2; literals 6, 7 and the new 1 must shift left.
    lvl[6] = 3
    lvl[7] = 4
    lvl[8] = 5
    rsn[5] = 2
    rsn[6] = 3
    tlim[3] = 6
    tlim[4] = 7
    tlim[5] = 8
    out[0] = -8
    out[3] = -5
    out[4] = -6
    out[5] = -7
    st[0] = 6
  wassat_shrink(ar, asg, lvl, rsn, sn, cm, tr, tlim, out, tmp, stk,
                 dstk, tclr, cnt, st, nv)
  result = []
  i = 0
  while i < st[0]
    result.push(out[i])
    i += 1
  clean = true
  i = 0
  while i < nv + 3
    clean = false if sn[i] != 0 || cnt[i] != 0
    i += 1
  { "clause": result, "clean": clean, "target": st[5],
    "attempts": st[3], "shrunk": st[4] }

describe "Wassat shrinking scan and compaction" ->
  it "replaces a same-level block with its implication point" ->
    r = shrink_scan_fixture(false, false, false)
    expect(r["clause"]).to eq([-6, -4, -5, -1])
    expect(r["target"]).to eq(3)
    expect(r["clean"]).to eq(true)

  it "skips both unmarked and marked foreign-level trail entries" ->
    r = shrink_scan_fixture(true, false, false)
    expect(r["clause"]).to eq([-6, -4, -5, -1])
    expect(r["clean"]).to eq(true)

  it "retains the original clause when all fallback probes fail" ->
    r = shrink_scan_fixture(false, true, false)
    expect(r["clause"]).to eq([-6, -2, -3, -4, -5])
    expect(r["attempts"]).to eq(1)
    expect(r["shrunk"]).to eq(0)
    expect(r["clean"]).to eq(true)

  it "compacts the retained suffix after a successful fallback probe" ->
    r = shrink_scan_fixture(false, false, true)
    expect(r["clause"]).to eq([-8, -6, -7, -1])
    expect(r["target"]).to eq(4)
    expect(r["attempts"]).to eq(2)
    expect(r["shrunk"]).to eq(1)
    expect(r["clean"]).to eq(true)

spec_summary
