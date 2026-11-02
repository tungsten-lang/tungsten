# spec: compiled -- native thread cancellation and atomic publication
use spec
use ../lib/wassat

-> perm_impossible_trial(m, stop, deadline, n = 12)
  ne = n * (n - 1) / 2
  left = i64[ne]; right = i64[ne]; heads = i64[n + 1]
  occ = i64[2 * ne]; fill = i64[n]
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
  wassat_perm_trial(n, ne, 6, left, right, heads, occ, i64[n], i64[n],
    i64[ne], i64[ne], i64[ne], rng, m, stop, deadline, 32, 100000)

describe "Permutation worker stop points" ->
  it "stops a live search on cancellation and either winning verdict" ->
    outcome = -1
    while outcome <= 1
      m = i64[24]; stop = i64[4]
      deadline = clock_ms() + 5000
      handle = Thread.new -> perm_impossible_trial(m, stop, deadline)
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
      << "c permutation stop status=[outcome] iterations=[m[7]] join_ms=[elapsed]"
      outcome += 1

  it "checks cancellation on the largest dense admitted graph" ->
    m = i64[24]; stop = i64[4]
    deadline = clock_ms() + 5000
    handle = Thread.new -> perm_impossible_trial(m, stop, deadline, 256)
    delay = 30 ## i64
    ccall("__w_sleep_ms", delay)
    requested = clock_ms()
    wassat_stop_cancel(stop)
    handle.join
    expect(m[22]).to eq(1)
    << "c permutation dense stop iterations=[m[7]] join_ms=[clock_ms() - requested]"

  it "limits a live unsuccessful walk by wall time" ->
    m = i64[24]; stop = i64[4]
    start = clock_ms()
    expect(perm_impossible_trial(m, stop, start + 20)).to eq(0)
    expect(m[22]).to eq(2)
    expect(wassat_stop_status(stop)).to eq(0)
    << "c permutation deadline iterations=[m[7]] elapsed_ms=[clock_ms() - start]"

spec_summary
