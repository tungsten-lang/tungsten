use spec
use wassat

describe "Packed watch words above the boxed small-integer range" ->
  it "preserves high clause ids through binary propagation" ->
    bd = i64[40]
    pool = i64[32]
    ps = i64[3]
    ps[1] = 32
    wassat_bl_add(bd, pool, ps, 3, 70000, 5)
    ar = i64[1]
    asg = i8[4]
    lasg = i8[10]
    lvl = i64[4]
    rsn = i64[4]
    phs = i64[4]
    wd = i64[40]
    wp = i64[1]
    ws = i64[3]
    tr = i64[4]
    st = i64[6]
    tr[0] = 1
    asg[1] = 1
    lasg[2] = 1
    lasg[3] = -1
    st[1] = 1
    wassat_propagate(ar, asg, lasg, lvl, rsn, phs, wd, wp, ws, tr, st, 1, bd, pool)
    expect(asg[2]).to eq(-1)
    expect(rsn[2]).to eq(70000)
    expect(tr[1]).to eq(-2)
    expect(st[2]).to eq(-1)

  it "preserves high arena offsets and header ids through long propagation" ->
    ar = i64[70005]
    wassat_hdr_put(ar, 70000, 70000, 3)
    ar[70001] = -1
    ar[70002] = 3
    ar[70003] = 2
    wd = i64[40]
    wp = i64[32]
    ws = i64[3]
    ws[1] = 32
    wassat_ws_add(wd, wp, ws, 3, 70001, 3)
    asg = i8[4]
    lasg = i8[10]
    lvl = i64[4]
    rsn = i64[4]
    phs = i64[4]
    tr = i64[4]
    st = i64[6]
    bd = i64[40]
    bp = i64[1]
    tr[0] = 1
    st[1] = 1
    asg[1] = 1
    asg[2] = -1
    lasg[2] = 1
    lasg[3] = -1
    lasg[4] = -1
    lasg[5] = 1
    wassat_propagate(ar, asg, lasg, lvl, rsn, phs, wd, wp, ws, tr, st, 1, bd, bp)
    expect(asg[3]).to eq(1)
    expect(rsn[3]).to eq(70000)
    expect(tr[1]).to eq(3)
    expect(st[2]).to eq(-1)

  it "rebuilds long watches without truncating their arena offsets" ->
    ar = i64[70005]
    ar[70001] = -1
    ar[70002] = 2
    ar[70003] = 3
    cm = i64[2]
    cm[0] = 70001
    cm[1] = 3
    alive = i64[1]
    alive[0] = 1
    wd = i64[40]
    wp = i64[32]
    ws = i64[3]
    ws[1] = 32
    wassat_ws_rebuild(cm, alive, ar, wd, wp, ws, 1, 10)
    expect(wd[13]).to eq(1)
    expect(wd[17]).to eq(1)
    expect(wp[wd[12]]).to eq(300652005687300)
    expect(wp[wd[16]]).to eq(300652005687299)
