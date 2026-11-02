# spec: compiled -- native cancellation during original-clause gate decoding
use spec
use ../lib/wassat

describe "LUT congruence worker lifecycle" ->
  it "stops live decoding for cancellation or another winner" ->
    nv = 100000
    nc = 4 * (nv - 2) + 2
    lits = i64[12 * (nv - 2) + 2]; offs = i64[nc]; lens = i64[nc]
    ci = 0; at = 0; out = 1
    while out <= nv - 2
      a = 0
      while a < 4
        offs[ci] = at; lens[ci] = 3
        lits[at] = (a & 1) == 1 ? 0 - (nv - 1) : nv - 1
        lits[at + 1] = (a & 2) == 2 ? 0 - nv : nv
        lits[at + 2] = a == 1 || a == 2 ? out : 0 - out
        at += 3; ci += 1; a += 1
      out += 1
    while out <= nv
      offs[ci] = at; lens[ci] = 1; lits[at] = out
      ci += 1; at += 1; out += 1
    program = i64[8 * (nv + 1)]
    [0, 1, -1].each -> (winner)
      m = i64[16]; stop = i64[4]; ready = i64[1]
      h = Thread.new ->
        ccall("__w_arr_store_rel", ready, 0, 1)
        wassat_lut_decode(lits, offs, lens, nv, nc, 1, program, m, stop, clock_ms() + 10000)
      while ccall("__w_arr_load_acq", ready, 0) == 0
        ccall("__w_sleep_ms", 1)
      ccall("__w_sleep_ms", 1)
      started = clock_ms()
      if winner == 0
        wassat_stop_cancel(stop)
      else
        wassat_stop_publish(stop, winner)
      h.join
      expect(m[11]).to eq(1)
      expect(m[6] > 0 && m[6] < nc).to eq(true)
      expect(wassat_stop_status(stop)).to eq(winner)
      expect(m[0]).to eq(0)
      << "c lut winner=[winner] decoded=[m[6]] join_ms=[clock_ms() - started]"

spec_summary
