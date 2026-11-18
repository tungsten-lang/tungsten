# spec: compiled -- live native threads and acquire/release cancellation cells
use spec
use ../lib/circuit_cone_search
use circuit_cone_fixtures

use circuit_cone_php_fixture

describe "Comparison-cone cancellation" ->
  it "declines cancelled decoding, simulation and equivalence work without a verdict" ->
    f = cone_fixture_flat(cone_fixture_rows, 7)
    d = wassat_cone_decode(f)
    stop = i64[2]
    z = wassat_stop_cancel(stop)
    expect(wassat_cone_decode(f, 0, stop)["stopped"]).to eq(true)
    expect(wassat_cone_sim_candidates(d, 16, 0, 0, stop)["stopped"]).to eq(true)
    q = wassat_cone_prove(d, i64[8], wassat_cone_workspace(d), 4, 3, 100, 0, false, stop)
    expect(q["stopped"]).to eq(true)
    expect(q["conflicts"]).to eq(0)
    expect(q["drat"].empty?).to eq(true)
    expect(wassat_cone_lift_drat(["1 0"], [1], 0, stop) == nil).to eq(true)
    r = wassat_cone_search(f, 1000, 0, false, stop)
    expect(r["status"]).to eq(0)
    expect(r["stopped"]).to eq(true)
    expect(r["drat_text"]).to eq("")
    expect(wassat_stop_status(stop)).to eq(0)

  it "keeps both local equivalence outcomes private" ->
    stop = i64[2]
    d = wassat_cone_decode(cone_fixture_flat(cone_fixture_rows, 7))
    q = wassat_cone_prove(d, i64[8], wassat_cone_workspace(d), 4, 3, 100, 0, false, stop)
    expect(q["equivalent"]).to eq(true)
    expect(wassat_stop_load(stop)).to eq(0)
    expect(wassat_stop_status(stop)).to eq(0)
    d = wassat_cone_decode(cone_fixture_flat(cone_rare_rows, 66))
    q = wassat_cone_prove(d, i64[67], wassat_cone_workspace(d), 62, -1, 100, 0, true, stop)
    expect(q["separated"]).to eq(true)
    expect(wassat_stop_load(stop)).to eq(0)
    expect(wassat_stop_status(stop)).to eq(0)

  it "interrupts live bit-parallel simulation" ->
    last = 300000; words = 16
    ga = i64[last + 1]; gb = i64[last + 1]
    v = 2
    while v <= last
      ga[v] = v - 1; gb[v] = 1
      v += 1
    sig = i64[(last + 1) * words]; state = i64[1]
    state[0] = 88172645463325252
    stop = i64[2]; ready = i64[1]; result = i64[1]
    handle = Thread.new ->
      ccall("__w_arr_store_rel", ready, 0, 1)
      result[0] = wassat_cone_simulate(ga, gb, 1, last, words, sig, state, 0, 0, stop)
    while ccall("__w_arr_load_acq", ready, 0) == 0
      ccall("__w_sleep_ms", 1)
    ccall("__w_sleep_ms", 1)
    requested = clock_ms()
    z = wassat_stop_cancel(stop)
    finished = handle.join(5000)
    expect(finished).to eq(true)
    expect(result[0]).to eq(0)
    expect(wassat_stop_status(stop)).to eq(0)
    << "c cone simulation stop_to_join_ms=[clock_ms() - requested]"

  it "interrupts a live compact SAT query without publishing its assumption result" ->
    fixture = cone_php_circuit
    d = wassat_cone_decode(fixture[0])
    expect(d["recognized"]).to eq(true)
    aliases = i64[d["nvars"] + 1]; workspace = wassat_cone_workspace(d, 16384)
    stop = i64[2]; ready = i64[1]; results = []
    handle = Thread.new ->
      ccall("__w_arr_store_rel", ready, 0, 1)
      results.push(wassat_cone_prove(d, aliases, workspace, fixture[1], fixture[2], 1000000000, 0, false, stop))
    while ccall("__w_arr_load_acq", ready, 0) == 0
      ccall("__w_sleep_ms", 1)
    ccall("__w_sleep_ms", 200)
    requested = clock_ms()
    z = wassat_stop_cancel(stop)
    finished = handle.join(5000)
    expect(finished).to eq(true)
    expect(results.size).to eq(1)
    r = results[0]
    expect(r["conflicts"] > 0).to eq(true)
    expect(r["stopped"]).to eq(true)
    expect(r["equivalent"]).to eq(false)
    expect(r["drat"].empty?).to eq(true)
    expect(wassat_stop_status(stop)).to eq(0)
    << "c cone query conflicts=[r["conflicts"]] stop_to_join_ms=[clock_ms() - requested]"

describe "Certified constant query lifecycle" ->
  it "shares a pre-spent pool across successive private constant queries" ->
    fixture = cone_php_circuit
    decoded = wassat_cone_decode(fixture[0])
    workspace = wassat_cone_workspace(decoded, 16384)
    state = i64[3]; state[0] = 5; state[1] = 5
    workspace["conflict_budget"] = state; workspace["conflict_limit"] = 7; workspace["conflict_slot"] = 2
    stop = i64[2]; aliases = i64[decoded["nvars"] + 1]
    result = wassat_cone_prove_constant(decoded, aliases, workspace, fixture[1], -1, 100, 0, stop)
    expect(result["equivalent"]).to eq(false)
    expect(result["conflicts"]).to eq(2)
    expect(state[0]).to eq(7)
    expect(state[2]).to eq(2)
    result = wassat_cone_prove_constant(decoded, aliases, workspace, fixture[1], -1, 100, 0, stop)
    expect(result["conflicts"]).to eq(0)
    expect(result["drat"].empty?).to eq(true)
    # Shared budget exhaustion requests cancellation, never a formula verdict.
    expect(wassat_stop_status(stop)).to eq(0)

  it "cancels a live constant query without publishing a unit or verdict" ->
    fixture = cone_php_circuit
    decoded = wassat_cone_decode(fixture[0])
    aliases = i64[decoded["nvars"] + 1]; workspace = wassat_cone_workspace(decoded, 16384)
    stop = i64[2]; ready = i64[1]; results = []
    handle = Thread.new ->
      ccall("__w_arr_store_rel", ready, 0, 1)
      results.push(wassat_cone_prove_constant(decoded, aliases, workspace, fixture[1], -1, 1000000000, 0, stop))
    while ccall("__w_arr_load_acq", ready, 0) == 0
      ccall("__w_sleep_ms", 1)
    ccall("__w_sleep_ms", 200)
    requested = clock_ms()
    z = wassat_stop_cancel(stop)
    expect(handle.join(5000)).to eq(true)
    result = results[0]
    expect(result["conflicts"] > 0).to eq(true)
    expect(result["stopped"]).to eq(true)
    expect(result["equivalent"]).to eq(false)
    expect(result["drat"].empty?).to eq(true)
    expect(wassat_stop_status(stop)).to eq(0)
    << "c constant query stop_to_join_ms=[clock_ms() - requested]"

describe "Retained cone conflict deltas" ->
  it "charges cumulative retained work once to the shared pool" ->
    fixture = cone_php_circuit
    decoded = wassat_cone_decode(fixture[0])
    workspace = wassat_cone_workspace(decoded, 16384)
    workspace["retry_cache"] = wassat_cone_retry_cache(1); workspace["retry_active"] = true
    state = i64[3]
    workspace["conflict_budget"] = state; workspace["conflict_limit"] = 7; workspace["conflict_slot"] = 2
    stop = i64[2]; aliases = i64[decoded["nvars"] + 1]
    first = wassat_cone_prove(decoded, aliases, workspace, fixture[1], fixture[2], 2, 0, false, stop)
    expect(first["conflicts"]).to eq(2)
    second = wassat_cone_prove(decoded, aliases, workspace, fixture[1], fixture[2], 100, 0, false, stop)
    expect(second["conflicts"]).to eq(5)
    expect(first["conflicts"] + second["conflicts"]).to eq(state[0])
    expect(state[0]).to eq(7)
    expect(state[2]).to eq(7)
    expect(wassat_stop_status(stop)).to eq(0)

spec_summary
