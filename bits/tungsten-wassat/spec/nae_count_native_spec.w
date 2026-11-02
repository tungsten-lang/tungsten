# spec: compiled -- live native thread cancellation and atomic publication
use spec
use ../lib/wassat

-> nae_native_formula(n)
  scopes = 0
  d = 1
  while 1 + 4 * d <= n
    scopes += n - 4 * d
    d += 1
  nc = 2 * scopes
  lits = i64[5 * nc]; offs = i64[nc]; lens = i64[nc]
  ci = 0; d = 1
  while 1 + 4 * d <= n
    a = 1
    while a + 4 * d <= n
      offs[ci] = 5 * ci; lens[ci] = 5
      offs[ci + 1] = 5 * (ci + 1); lens[ci + 1] = 5
      j = 0
      while j < 5
        v = a + j * d
        lits[5 * ci + j] = v
        lits[5 * (ci + 1) + j] = -v
        j += 1
      ci += 2
      a += 1
    d += 1
  { "nvars": n, "flat_ncl": nc, "flat_nlits": 5 * nc,
    "flat_lits": lits, "flat_offs": offs, "flat_lens": lens }

describe "Arithmetic counter worker lifecycle" ->
  it "stops an active search after cancellation and either winning verdict" ->
    formula = nae_native_formula(260)
    status = -1
    while status <= 1
      plan = { "meta": i64[32], "scratch": 0 }
      stop = i64[4]; res = i64[268]
      handle = wassat_nae_start(formula, plan, stop, res, 0)
      ccall("__w_sleep_ms", 20 ## i64)
      requested = clock_ms()
      if status == 0
        wassat_stop_cancel(stop)
      else
        wassat_stop_publish(stop, status)
      handle.join
      expect(plan["meta"][5]).to eq(3)
      expect(plan["meta"][2] > 0).to eq(true)
      expect(res[0]).to eq(0)
      expect(wassat_stop_status(stop)).to eq(status)
      << "c nae cancellation status=[status] nodes=[plan["meta"][2]] join_ms=[clock_ms() - requested]"
      status += 1

  it "cancels decoding the largest admitted element range" ->
    formula = nae_native_formula(700)
    plan = { "meta": i64[32], "scratch": 0 }
    stop = i64[4]; res = i64[708]
    handle = wassat_nae_start(formula, plan, stop, res, 0)
    ccall("__w_sleep_ms", 1 ## i64)
    requested = clock_ms()
    wassat_stop_cancel(stop)
    handle.join
    expect(plan["meta"][5]).to eq(3)
    expect(res[0]).to eq(0)
    << "c nae decode cancellation clauses=[plan["meta"][16]] join_ms=[clock_ms() - requested]"

spec_summary
