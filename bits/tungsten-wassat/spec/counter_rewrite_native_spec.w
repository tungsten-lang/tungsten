# spec: compiled -- native cancellation of the flat counter admission scan
use spec
use ../lib/counter_rewrite

describe "Counter rewrite worker lifecycle" ->
  it "stops admission when another arm cancels or publishes a winner" ->
    nc = 1000001
    l = i64[2 * nc]; o = i64[nc]; n = i64[nc]
    ci = 0
    while ci < nc
      o[ci] = 2 * ci; n[ci] = 2
      l[2 * ci] = -1; l[2 * ci + 1] = 128
      ci += 1
    n[nc - 1] = 1; l[2 * (nc - 1)] = 1
    [0, 1, -1].each -> (winner)
      m = i64[32]; stop = i64[4]; ready = i64[1]; result = i64[1]
      h = Thread.new ->
        ccall("__w_arr_store_rel", ready, 0, 1)
        result[0] = wassat_counter_find(l, o, n, 128, nc, m, stop)
      while ccall("__w_arr_load_acq", ready, 0) == 0
        ccall("__w_sleep_ms", 1)
      ccall("__w_sleep_ms", 1)
      started = clock_ms()
      if winner == 0
        wassat_stop_cancel(stop)
      else
        wassat_stop_publish(stop, winner)
      h.join
      expect(result[0]).to eq(0)
      expect(m[6]).to eq(1)
      expect(m[12] > 0 && m[12] < 2 * nc - 1).to eq(true)
      expect(wassat_stop_status(stop)).to eq(winner)
      << "c counter winner=[winner] scanned=[m[12]] join_ms=[clock_ms() - started]"

spec_summary
