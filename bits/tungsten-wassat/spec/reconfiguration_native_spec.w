# spec: compiled -- native thread publication and resource admission
use spec
use reconfiguration_support

-> rcn_restore(name, value)
  if value == nil
    Env.delete(name)
  else
    Env.set(name, value)

describe "Wassat native reconfiguration scout" ->
  it "respects opt-out, explicit pins, spare cores and resident memory" ->
    f = rc_flat(48, rc_rows(8, [0, 2], [1, 3]))
    old_mode = env("WASSAT_RECONFIGURATION")
    old_arms = env("WASSAT_ARMS")
    Env.set("WASSAT_RECONFIGURATION", "0")
    expect(wassat_reconf_plan(f, 0, 0, 0)).to eq(nil)
    Env.delete("WASSAT_RECONFIGURATION")
    Env.set("WASSAT_ARMS", "2")
    expect(wassat_reconf_plan(f, 0, 0, 0)).to eq(nil)
    Env.set("WASSAT_RECONFIGURATION", "1")
    expect(wassat_reconf_plan(f, System.cpu_count, 0, 0)).to eq(nil)
    expect(wassat_reconf_plan(f, 0, 1000000, 0)).to eq(nil)
    if System.cpu_count > 0 && System.physical_memory_bytes > 100000000
      expect(wassat_reconf_plan(f, 0, 0, 0) != nil).to eq(true)
    rcn_restore("WASSAT_RECONFIGURATION", old_mode)
    rcn_restore("WASSAT_ARMS", old_arms)

  it "uses the cheap prefix only for admission" ->
    rows = []
    i = 0
    while i < 1000
      rows.push([-1, -2])
      i += 1
    f = rc_flat(64, rows)
    expect(wassat_reconf_prefix(f["flat_lits"], f["flat_offs"], f["flat_lens"], 64, 1000)).to eq(1)
    m = i64[32]
    expect(wassat_reconf_run(f["flat_lits"], f["flat_offs"], f["flat_lens"], 64, 1000, m, i64[4], i64[72], 0, 1000)).to eq(0)
    expect(m[1]).to eq(0)
    expect(m[15]).to eq(0)

  it "admits a sparse graph prefix and rejects a mixed-sign prefix" ->
    rows = [[-1, -2], [-2, -3], [-3, -4], [-4, -1], [5]]
    while rows.size < 1000
      rows.push([5])
    f = rc_flat(64, rows)
    expect(wassat_reconf_prefix(f["flat_lits"], f["flat_offs"], f["flat_lens"], 64, 1000)).to eq(1)
    f["flat_lits"][1] = 2
    expect(wassat_reconf_prefix(f["flat_lits"], f["flat_offs"], f["flat_lens"], 64, 1000)).to eq(0)

  it "publishes only a complete original model from a native thread" ->
    rows = rc_rows(8, [0, 2], [1, 3])
    f = rc_flat(48, rows)
    stop = i64[4]; res = i64[56]; m = i64[32]
    handle = wassat_reconf_start(f, { "meta": m }, stop, res)
    handle.join
    expect(res[0]).to eq(1)
    expect(wassat_stop_status(stop)).to eq(1)
    expect(m[15]).to eq(rows.size)
    expect(rc_replay(rows, res)).to eq(true)

  it "does not publish after cancellation" ->
    f = rc_flat(48, rc_rows(8, [0, 2], [1, 3]))
    stop = i64[4]; res = i64[56]; m = i64[32]
    wassat_stop_cancel(stop)
    handle = wassat_reconf_start(f, { "meta": m }, stop, res)
    handle.join
    expect(res[0]).to eq(0)
    expect(m[2]).to eq(1)
    expect(wassat_stop_status(stop)).to eq(0)

  it "joins with a SAT scout regardless of which arm wins" ->
    rows = rc_rows(8, [0, 2], [1, 3])
    f = rc_flat(48, rows)
    art = wassat_raw_artifact(f, 48)
    stop = i64[4]; res = i64[56]; m = i64[32]; out = []
    handle = wassat_reconf_start(f, { "meta": m }, stop, res)
    scout = Thread.new -> wassat_scout_arm_body(48, art, stop, 128, 1000, true, false, out)
    scout.join
    wassat_stop_cancel(stop)
    handle.join
    expect(res[0] == 1 || out[0]["status"] == 1).to eq(true)
    if res[0] == 1
      expect(rc_replay(rows, res)).to eq(true)
    else
      expect(wassat_model_satisfies?(f, out[0]["model"])).to eq(true)

  it "joins after an independently unsatisfiable scout outcome" ->
    f = rc_flat(24, rc_rows(4, [0, 2], [1, 3]))
    art = wassat_raw_artifact(f, 24)
    stop = i64[4]; res = i64[32]; m = i64[32]; out = []
    handle = wassat_reconf_start(f, { "meta": m }, stop, res)
    scout = Thread.new -> wassat_scout_arm_body(24, art, stop, 128, 1000, true, false, out)
    scout.join
    wassat_stop_cancel(stop)
    handle.join
    expect(out[0]["status"] == -1 || res[0] == -1).to eq(true)
    expect(res[0] == 0 || res[0] == -1).to eq(true)

  it "cancels the original-clause verifier during a large live scan" ->
    start = []; goal_set = []
    v = 0
    while v < 512
      start.push(v); goal_set.push(v + 1)
      v += 2
    rows = rc_rows(512, start, goal_set, 4)
    f = rc_flat(6144, rows)
    lits = f["flat_lits"]; offs = f["flat_offs"]; lens = f["flat_lens"]
    nc = f["flat_ncl"]
    units = i8[6145]; starts = i64[64]; initial = i64[8]; goal = i64[8]
    adj = i64[4096]; m = i64[32]; stop = i64[4]; ready = i64[1]
    n = wassat_reconf_prepare(lits, offs, lens, 6144, nc, units, starts, initial, goal, adj, m, stop, 0)
    expect(n).to eq(512)
    h = Thread.new ->
      ccall("__w_arr_store_rel", ready, 0, 1)
      wassat_rc_verify(lits, offs, lens, 6144, nc, n, starts, initial, goal, m, stop, 0)
    while ccall("__w_arr_load_acq", ready, 0) == 0
      ccall("__w_sleep_ms", 1)
    ccall("__w_sleep_ms", 5)
    t = clock_ms()
    wassat_stop_cancel(stop)
    h.join
    expect(m[2]).to eq(1)
    expect(m[25]).to eq(0)
    << "c reconf verify cancellation probes=[m[26]] join_ms=[clock_ms() - t]"

spec_summary
