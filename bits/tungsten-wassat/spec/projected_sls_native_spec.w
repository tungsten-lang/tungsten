# spec: compiled -- native thread lifecycle and atomic publication
use spec
use ../lib/wassat

describe "Projected SLS worker lifecycle" ->
  it "stops a live losing walk for cancellation, SAT, and UNSAT" ->
    f = wassat_parse_cnf_native("p cnf 128 4\n1 2 0\n1 -2 0\n-1 2 0\n-1 -2 0\n")
    alive = i64[4]
    ci = 0
    while ci < 4
      alive[ci] = 1
      ci += 1
    art = { "fla": f["flat_lits"], "fcs": f["flat_offs"], "fcl": f["flat_lens"],
      "falive": alive, "ftaut": i64[4], "fncl": 4,
      "stats": { "vars_substituted": 64 }, "stack": [] }
    outcome = -1
    while outcome <= 1
      stop = i64[4]
      res = i64[129]
      meta = i64[12]
      handle = Thread.new -> wassat_pre_sls_body(f, art, stop, res, meta)
      delay = 20 ## i64
      ccall("__w_sleep_ms", delay)
      requested = clock_ms()
      if outcome == 0
        wassat_stop_cancel(stop)
      else
        wassat_stop_publish(stop, outcome)
      handle.join
      joined = clock_ms()
      expect(res[0]).to eq(0)
      expect(meta[4] > 0).to eq(true)
      expect(meta[4] < WASSAT_PRE_SLS_FLIPS).to eq(true)
      expect(meta[9]).to eq(1)
      expect(wassat_stop_status(stop)).to eq(outcome)
      << "c projected cancellation status=[outcome] flips=[meta[4]] join_ms=[joined - requested]"
      outcome += 1

spec_summary
