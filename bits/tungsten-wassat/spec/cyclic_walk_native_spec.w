# spec: compiled -- native thread cancellation and atomic publication
use spec
use ../lib/wassat

-> cycle_impossible_trial(m, stop, deadline, n = 12)
  ne = n * (n - 1) / 2
  left = i32[ne]; right = i32[ne]; heads = i32[n + 1]
  occ = i32[2 * ne]; fill = i32[n]
  e = 0; u = 0
  while u < n
    v = u + 1
    while v < n
      left[e] = u; right[e] = v
      heads[u + 1] += 1; heads[v + 1] += 1
      e += 1; v += 1
    u += 1
  u = 1
  while u <= n
    heads[u] += heads[u - 1]
    u += 1
  e = 0
  while e < ne
    u = left[e]; v = right[e]
    occ[heads[u] + fill[u]] = e; fill[u] += 1
    occ[heads[v] + fill[v]] = e; fill[v] += 1
    e += 1
  rng = i64[1]; rng[0] = 1
  wassat_cycle_trial(n, ne, 6, left, right, heads, occ, i32[n], i32[n],
    i32[ne], i32[ne], i32[ne], rng, m, stop, deadline, 32, 100000)

describe "Circular worker stop points" ->
  it "stops a live search on cancellation and either winning verdict" ->
    outcome = -1
    while outcome <= 1
      m = i64[24]; stop = i64[4]
      deadline = clock_ms() + 5000
      handle = Thread.new -> cycle_impossible_trial(m, stop, deadline)
      delay = 20 ## i64
      ccall("__w_sleep_ms", delay)
      requested = clock_ms()
      if outcome == 0
        wassat_stop_cancel(stop)
      else
        wassat_stop_publish(stop, outcome)
      handle.join
      elapsed = clock_ms() - requested
      expect(m[22]).to eq(1)
      expect(m[7] > 0).to eq(true)
      expect(m[7] < 3200000).to eq(true)
      expect(wassat_stop_status(stop)).to eq(outcome)
      << "c cyclic stop status=[outcome] iterations=[m[7]] join_ms=[elapsed]"
      outcome += 1

  it "checks cancellation on the largest dense admitted graph" ->
    m = i64[24]; stop = i64[4]
    deadline = clock_ms() + 5000
    handle = Thread.new -> cycle_impossible_trial(m, stop, deadline, 1024)
    delay = 30 ## i64
    ccall("__w_sleep_ms", delay)
    requested = clock_ms()
    wassat_stop_cancel(stop)
    handle.join
    expect(m[22]).to eq(1)
    << "c cyclic dense stop iterations=[m[7]] join_ms=[clock_ms() - requested]"

  it "limits a live unsuccessful walk by wall time" ->
    m = i64[24]; stop = i64[4]
    start = clock_ms()
    expect(cycle_impossible_trial(m, stop, start + 20)).to eq(0)
    expect(m[22]).to eq(2)
    expect(wassat_stop_status(stop)).to eq(0)
    << "c cyclic deadline iterations=[m[7]] elapsed_ms=[clock_ms() - start]"

  it "checks a deadline inside a live dense ordering traversal" ->
    n = 1024
    ne = n * n / 4
    left = i32[ne]; right = i32[ne]; heads = i32[n + 1]
    matrix = i8[n * n]
    e = 0; a = 0
    while a < n / 2
      b = n / 2
      while b < n
        left[e] = a; right[e] = b; matrix[a * n + b] = 1
        e += 1; b += 1
      a += 1
    a = 0
    while a <= n
      heads[a] = a * (n / 2)
      a += 1
    m = i64[24]; stats = i64[8]; stop = i64[4]
    start = clock_ms()
    expect(wassat_cycle_order(n, ne, n / 2, left, right, heads, matrix, i32[n], m, stats, stop, start + 3)).to eq(0)
    expect(stats[3] > 0).to eq(true)
    expect(stats[7]).to eq(2)
    expect(stats[0]).to eq(0)
    expect(wassat_stop_status(stop)).to eq(0)
    << "c cyclic order deadline visits=[stats[3]] elapsed_ms=[clock_ms() - start]"

spec_summary
