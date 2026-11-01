use spec
use ../lib/solver

describe "Watch-block prefix recycling" ->
  it "reclaims an overlapping dead prefix without changing entry order" ->
    wd = i64[8]
    wp = i64[32]
    st = i64[12]
    wd[0] = 8
    wd[1] = 6
    wd[2] = 6
    wd[3] = 4
    st[0] = 14
    st[1] = 32
    wp[3] = 678
    wp[14] = 789
    i = 0
    while i < 6
      wp[8 + i] = 9007199254740992 + i
      i += 1
    expect(wassat_ws_recycle(wd, wp, st, 0)).to eq(1)
    expect(wd[0]).to eq(4)
    expect(wd[1]).to eq(6)
    expect(wd[2]).to eq(10)
    expect(wd[3]).to eq(4)
    expect(st[0]).to eq(14)
    expect(st[8]).to eq(1)
    expect(st[9]).to eq(6)
    expect(st[10]).to eq(4)
    expect(wp[3]).to eq(678)
    expect(wp[14]).to eq(789)
    i = 0
    while i < 6
      expect(wp[4 + i]).to eq(9007199254740992 + i)
      i += 1

  it "requires substantial reclaimed capacity before copying a large block" ->
    wd = i64[4]
    wp = i64[64]
    st = i64[12]
    wd[0] = 4
    wd[1] = 10
    wd[2] = 10
    expect(wassat_ws_recycle(wd, wp, st, 0)).to eq(0)
    expect(wd[0]).to eq(4)
    expect(st[8]).to eq(0)

  it "reuses space for an append even when the pool has no free tail" ->
    wd = i64[16]
    wp = i64[12]
    st = i64[12]
    st[1] = 12
    i = 0
    while i < 8
      wassat_ws_add(wd, wp, st, 3, 70001 + i, 2)
      i += 1
    # Mirror propagation's front removal of four entries.
    wd[12] = wd[12] + 4
    wd[13] = wd[13] - 4
    wd[14] = wd[14] - 4
    expect(wassat_ws_add(wd, wp, st, 3, 70009, 2)).to eq(0)
    expect(st[0]).to eq(12)
    expect(st[2]).to eq(0)
    expect(st[8]).to eq(1)
    expect(wd[13]).to eq(5)
    i = 0
    while i < 5
      word = wp[wd[12] + i] ## i64
      expect(word >> 32).to eq(70005 + i)
      expect(word & 4294967295).to eq(4)
      i += 1

  it "reclaims the destination block inside propagation without retrying" ->
    ar = i64[5]
    wassat_hdr_put(ar, 0, 0, 3)
    ar[1] = -1
    ar[2] = -2
    ar[3] = 3
    wd = i64[40]
    wp = i64[16]
    ws = i64[12]
    ws[1] = 16
    i = 0
    while i < 8
      wassat_ws_add(wd, wp, ws, 6, 70001 + i, 2)
      i += 1
    wassat_ws_add(wd, wp, ws, 3, 1, -2)
    wd[24] = wd[24] + 4
    wd[25] = wd[25] - 4
    wd[26] = wd[26] - 4
    asg = i8[4]
    lasg = i8[10]
    lvl = i64[4]
    rsn = i32[4]
    phs = i8[4]
    tr = i64[4]
    st = i64[6]
    bd = i64[40]
    bp = i64[1]
    asg[1] = 1
    asg[2] = 1
    lasg[2] = 1
    lasg[3] = -1
    lasg[4] = 1
    lasg[5] = -1
    tr[0] = 1
    st[1] = 1
    wassat_propagate(ar, asg, lasg, lvl, rsn, phs, wd, wp, ws, tr, st, 1, bd, bp)
    expect(st[2]).to eq(-1)
    expect(st[3]).to eq(0)
    expect(ws[0]).to eq(16)
    expect(ws[7]).to eq(0)
    expect(ws[8]).to eq(1)
    expect(wd[25]).to eq(5)
    expect(wd[13]).to eq(0)
    expect(ar[2]).to eq(3)
    word = wp[wd[24] + 4] ## i64
    expect(word >> 32).to eq(1)
    expect(word & 4294967295).to eq(5)

spec_summary
