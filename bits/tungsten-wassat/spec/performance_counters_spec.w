use spec
use ../lib/solver

-> counter_propagation(pool_cap)
  ar = i64[5]
  wassat_hdr_put(ar, 0, 0, 3)
  ar[1] = -1
  ar[2] = 2
  ar[3] = 3
  wd = i64[40]
  wp = i64[pool_cap]
  ws = i64[12]
  ws[1] = pool_cap
  wassat_ws_add(wd, wp, ws, 3, 1, 2)
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
  asg[2] = -1
  lasg[2] = 1
  lasg[3] = -1
  lasg[4] = -1
  lasg[5] = 1
  tr[0] = 1
  st[1] = 1
  wassat_propagate(ar, asg, lasg, lvl, rsn, phs, wd, wp, ws, tr, st, 1, bd, bp)
  { "ws": ws, "st": st, "wd": wd }

describe "Wassat cumulative performance counters" ->
  it "executes repeated writes and appends with the same mutable arguments" ->
    ar = i64[4]
    wassat_hdr_put(ar, 0, 2, 3)
    ar[0] = 0
    wassat_hdr_put(ar, 0, 2, 3)
    expect(ar[0]).to eq(8589934595)
    bd = i64[40]
    bp = i64[16]
    bs = i64[3]
    bs[1] = 16
    wassat_bl_add(bd, bp, bs, 3, 0, 4)
    wassat_bl_add(bd, bp, bs, 3, 0, 4)
    expect(bd[13]).to eq(2)
    wd = i64[40]
    wp = i64[16]
    ws = i64[12]
    ws[1] = 16
    wassat_ws_add(wd, wp, ws, 3, 1, 2)
    wassat_ws_add(wd, wp, ws, 3, 1, 2)
    expect(wd[13]).to eq(2)

  it "counts successful block relocations, copied entries, and failed appends separately" ->
    wd = i64[40]
    wp = i64[12]
    ws = i64[12]
    ws[1] = 12
    i = 0
    while i < 8
      expect(wassat_ws_add(wd, wp, ws, 3, 1 + i, 2)).to eq(0)
      i += 1
    expect(ws[5]).to eq(2)
    expect(ws[6]).to eq(4)
    expect(ws[7]).to eq(0)
    expect(wassat_ws_add(wd, wp, ws, 3, 9, 2)).to eq(-1)
    expect(ws[5]).to eq(2)
    expect(ws[6]).to eq(4)
    expect(ws[7]).to eq(1)
    expect(wd[13]).to eq(8)

  it "counts relocations performed inside native propagation" ->
    r = counter_propagation(8)
    expect(r["ws"][5]).to eq(2)
    expect(r["ws"][6]).to eq(0)
    expect(r["ws"][7]).to eq(0)
    expect(r["st"][3]).to eq(0)
    expect(r["st"][4]).to eq(1)
    expect(r["wd"][25]).to eq(1)

  it "counts a propagation overflow before the caller retries the literal" ->
    r = counter_propagation(4)
    expect(r["ws"][5]).to eq(1)
    expect(r["ws"][7]).to eq(1)
    expect(r["st"][0]).to eq(0)
    expect(r["st"][3]).to eq(1)

  it "accumulates repack work across rebuilds and preserves relocation totals" ->
    ar = i64[5]
    ar[1] = 1
    ar[2] = 2
    ar[3] = 3
    cm = i64[2]
    cm[0] = 1
    cm[1] = 3
    alive = i8[1]
    alive[0] = 1
    wd = i64[40]
    wp = i64[16]
    ws = i64[12]
    ws[1] = 16
    ws[5] = 7
    wassat_ws_rebuild(cm, alive, ar, wd, wp, ws, 1, 10)
    wassat_ws_rebuild(cm, alive, ar, wd, wp, ws, 1, 10)
    expect(ws[3]).to eq(2)
    expect(ws[4]).to eq(4)
    expect(ws[5]).to eq(7)

  it "returns watch work with a solver result" ->
    s = Wassat.new(3, [[1, 2, 3]], WASSAT_PROOF_NONE)
    r = s.solve_budget(0)
    expect(r["sat"]).to eq(true)
    expect(r["watch_relocations"] >= 2).to eq(true)
    expect(r["watch_copied_entries"]).to eq(0)
    expect(r["watch_overflows"]).to eq(0)
    expect(r["watch_recycles"]).to eq(0)
    expect(r["watch_recycle_copied"]).to eq(0)
    expect(r["watch_reclaimed_slots"]).to eq(0)

spec_summary
