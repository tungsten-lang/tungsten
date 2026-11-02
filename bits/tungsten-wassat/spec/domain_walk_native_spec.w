# spec: compiled -- native worker threads, atomics and resource admission
use spec
use ../lib/wassat
use ../../../core/env

-> dwn_formula(blocks, width, impossible = false)
  rows = []
  b = 0
  while b < blocks
    row = []
    j = 1
    while j <= width
      row.push(b * width + j)
      k = j + 1
      while k <= width
        rows.push("[0 - (b * width + j)] [0 - (b * width + k)] 0")
        k += 1
      j += 1
    rows.push(row.join(" ") + " 0")
    b += 1
  if impossible
    j = 1
    while j <= width
      k = 1
      while k <= width
        rows.push("[0 - j] [0 - (width + k)] 0")
        k += 1
      j += 1
  text = "p cnf [blocks * width] [rows.size]\n" + rows.join("\n") + "\n"
  wassat_parse_cnf_native(text)

-> dwn_restore(name, old)
  if old == nil
    Env.delete(name)
  else
    Env.set(name, old)

describe "Wassat native finite-domain worker" ->
  it "honors opt-out, arm pins, spare cores and resident memory" ->
    f = dwn_formula(8, 25)
    old_mode = env("WASSAT_DOMAIN_WALK")
    old_arms = env("WASSAT_ARMS")
    Env.set("WASSAT_DOMAIN_WALK", "0")
    expect(wassat_domain_plan(f, 0, 0, 0, 0)).to eq(nil)
    Env.delete("WASSAT_DOMAIN_WALK")
    Env.set("WASSAT_ARMS", "2")
    expect(wassat_domain_plan(f, 0, 0, 0, 0)).to eq(nil)
    Env.set("WASSAT_DOMAIN_WALK", "1")
    expect(wassat_domain_plan(f, System.cpu_count, 0, 0, 0)).to eq(nil)
    expect(wassat_domain_plan(f, 0, 1000000, 0, 0)).to eq(nil)
    if System.cpu_count > 0 && System.physical_memory_bytes > 100000000
      expect(wassat_domain_plan(f, 0, 0, 0, 0) != nil).to eq(true)
    expect(wassat_race_memory_fits?(f, 0, 0, 0, 2684354561)).to eq(false)
    dwn_restore("WASSAT_DOMAIN_WALK", old_mode)
    dwn_restore("WASSAT_ARMS", old_arms)

  it "uses the prefix only for admission" ->
    f = dwn_formula(8, 25)
    expect(wassat_domain_prefix(f["flat_lits"], f["flat_offs"], f["flat_lens"], f["nvars"], f["flat_ncl"])).to eq(1)
    small = dwn_formula(3, 2)
    expect(wassat_domain_prefix(small["flat_lits"], small["flat_offs"], small["flat_lens"], small["nvars"], small["flat_ncl"])).to eq(0)

  it "publishes a complete original model from a native thread" ->
    f = dwn_formula(8, 25)
    stop = i64[4]
    res = i64[f["nvars"] + 8]
    plan = { "meta": i64[24] }
    handle = wassat_domain_start(f, plan, stop, res, 0)
    handle.join
    expect(res[0]).to eq(1)
    expect(wassat_stop_status(stop)).to eq(1)
    expect(plan["meta"][16]).to eq(1)
    model = []
    v = 1
    while v <= f["nvars"]
      model.push(res[v] == 1 ? v : 0 - v)
      v += 1
    expect(wassat_model_satisfies?(f, model)).to eq(true)

  it "cancels a live native search without publishing an answer" ->
    f = dwn_formula(32, 8, true)
    stop = i64[4]
    res = i64[f["nvars"] + 8]
    plan = { "meta": i64[24] }
    handle = wassat_domain_start(f, plan, stop, res, 0)
    delay = 20 ## i64
    ccall("__w_sleep_ms", delay)
    wassat_stop_cancel(stop)
    handle.join
    expect(res[0]).to eq(0)
    expect(plan["meta"][2]).to eq(1)
    expect(wassat_stop_status(stop)).to eq(0)

  it "joins the additive arm for SAT and UNSAT race outcomes" ->
    old_mode = env("WASSAT_DOMAIN_WALK")
    old_otfs = env("WASSAT_OTFS")
    Env.set("WASSAT_DOMAIN_WALK", "1")
    Env.set("WASSAT_OTFS", "0")
    i = 0
    while i < 2
      f = dwn_formula(3, 2, i == 1)
      art = wassat_raw_artifact(f, f["nvars"])
      race = wassat_race_build(f["nvars"], art, 2, f)
      result = wassat_race_run(race, 0)
      expect(result["status"]).to eq(i == 0 ? 1 : -1)
      if result["status"] == 1
        expect(wassat_model_satisfies?(f, result["model"])).to eq(true)
      i += 1
    dwn_restore("WASSAT_DOMAIN_WALK", old_mode)
    dwn_restore("WASSAT_OTFS", old_otfs)

spec_summary
