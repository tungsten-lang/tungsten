# spec: compiled -- cancellation during native original-clause replay
use spec
use ../lib/wassat

describe "Quota worker lifecycle" ->
  it "stops a live replay without publishing a partial model" ->
    nc = 8000000
    lits = i64[1]; lits[0] = 1
    offs = i64[nc]; lens = i64[nc]
    i = 0
    while i < nc
      lens[i] = 1; i += 1
    res = i64[9]; res[1] = 1
    [0, 1].each -> (winner)
      m = i64[24]; stop = i64[4]; started = i64[1]
      m[11] = clock_ms() + 10000
      handle = Thread.new ->
        ccall("__w_arr_store_rel", started, 0, 1)
        wassat_quota_replay(lits, offs, lens, res, 1, nc, m, stop)
      while ccall("__w_arr_load_acq", started, 0) == 0
        ccall("__w_sleep_ms", 1)
      ccall("__w_sleep_ms", 1)
      requested = clock_ms()
      if winner == 0
        wassat_stop_cancel(stop)
      else
        wassat_stop_publish(stop, winner)
      handle.join
      expect(m[10]).to eq(2)
      expect(m[13] > 0 && m[13] < nc).to eq(true)
      expect(wassat_stop_status(stop)).to eq(winner)
      expect(res[0]).to eq(0)
      << "c quota winner=[winner] replayed=[m[13]] join_ms=[clock_ms() - requested]"

spec_summary
