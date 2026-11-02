# spec: compiled -- live cancellation of a native decoder thread
use spec
use ../lib/wassat

describe "Capacity decoder lifecycle" ->
  it "stops a live scan without publishing a verdict" ->
    nc = 1200000
    lits = i64[2 * nc]; offs = i64[nc]; lens = i64[nc]
    ci = 0
    while ci < nc
      offs[ci] = 2 * ci; lens[ci] = 2
      lits[2 * ci] = -1; lits[2 * ci + 1] = -2
      ci += 1
    table = i64[4194304]; domains = i32[1200]
    member = i8[32]; units = i8[32]; rooms = i32[64]; targets = i32[64]
    m = i64[24]; stop = i64[4]; started = i64[1]
    handle = Thread.new ->
      ccall("__w_arr_store_rel", started, 0, 1)
      wassat_capacity_decode(lits, offs, lens, 31, nc, 2, domains, member, units, rooms, targets, table, m, stop)
    while ccall("__w_arr_load_acq", started, 0) == 0
      ccall("__w_sleep_ms", 1)
    ccall("__w_sleep_ms", 1)
    requested = clock_ms()
    wassat_stop_cancel(stop)
    handle.join
    expect(m[10]).to eq(2)
    expect(m[2] > 0 && m[2] < nc).to eq(true)
    expect(wassat_stop_status(stop)).to eq(0)
    << "c capacity cancelled clauses=[m[2]] join_ms=[clock_ms() - requested]"

spec_summary
