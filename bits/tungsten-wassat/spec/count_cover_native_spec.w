# spec: compiled -- live cancellation of native covering search
use spec
use ../lib/wassat

-> count_cover_native_rows
  rows = []
  dx = 1
  while dx < 9
    dy = 0
    while dy < 7
      x = dy
      while x + dx < 9
        y = 0
        while y + dx + dy < 7
          mask = (1 << (x + 9 * y)) | (1 << (x + dx + 9 * (y + dy)))
          mask |= (1 << (x - dy + 9 * (y + dx))) | (1 << (x + dx - dy + 9 * (y + dx + dy)))
          rows.push(mask)
          y += 1
        x += 1
      dy += 1
    dx += 1
  covers = i64[rows.size]
  i = 0
  while i < rows.size
    covers[i] = rows[i]
    i += 1
  covers

describe "Counting cover worker lifecycle" ->
  it "stops active search after cancellation and either winning verdict" ->
    covers = count_cover_native_rows()
    nr = covers.size
    expect(nr).to eq(308)
    status = -1
    while status <= 1
      m = i64[28]
      m[6] = 100000000
      m[7] = nr
      m[4] = clock_ms() + 5000
      scratch = i64[64 * nr]
      occurrences = i64[64 * 63]
      orders = i64[64 * 4]
      stop = i64[4]
      handle = Thread.new -> wassat_cc_search(covers, scratch, occurrences, orders, m, stop, 0, 0, 27, 0, nr)
      ccall("__w_sleep_ms", 20 ## i64)
      requested = clock_ms()
      if status == 0
        wassat_stop_cancel(stop)
      else
        wassat_stop_publish(stop, status)
      result = handle.join
      expect(m[2]).to eq(1)
      expect(m[5] > 0).to eq(true)
      expect(wassat_stop_status(stop)).to eq(status)
      << "c count_cover cancellation status=[status] nodes=[m[5]] join_ms=[clock_ms() - requested]"
      status += 1

spec_summary
