# spec: compiled -- native resource admission, worker threads and atomics
use spec
use ../lib/wassat
use ../../../core/env

-> sdn_formula(impossible)
  blocks = 300; width = 8; rows = []; b = 0
  while b < blocks
    row = []; j = 1
    while j <= width
      row.push(b*width+j); j += 1
    rows.push(row.join(" ")+" 0"); j = 1
    while j <= width
      k = j+1
      while k <= width
        rows.push("[-b*width-j] [-b*width-k] 0"); k += 1
      j += 1
    b += 1
  if impossible
    j = 1
    while j <= width
      k = 1
      while k <= width
        rows.push("[-j] [-width-k] 0"); k += 1
      j += 1
  wassat_parse_cnf_native("p cnf [blocks*width] [rows.size]\n"+rows.join("\n")+"\n")

-> sdn_restore(key,value)
  if value == nil
    Env.delete(key)
  else
    Env.set(key,value)

describe "Sparse domain worker admission" ->
  it "honors opt-outs, pinned arms, spare cores and the total arena budget" ->
    f = sdn_formula(false); config = WassatConfig.from_lens(f["nvars"],f["flat_lens"],f["flat_ncl"])
    old = env("WASSAT_SPARSE_DOMAIN"); arms = env("WASSAT_ARMS"); domain = env("WASSAT_DOMAIN_WALK")
    Env.set("WASSAT_SPARSE_DOMAIN","0")
    expect(wassat_sparse_domain_plan(f,config,0,0,0,0,0)).to eq(nil)
    Env.set("WASSAT_SPARSE_DOMAIN","1"); Env.set("WASSAT_DOMAIN_WALK","0")
    expect(wassat_sparse_domain_plan(f,config,0,0,0,0,0)).to eq(nil)
    Env.delete("WASSAT_DOMAIN_WALK"); Env.delete("WASSAT_SPARSE_DOMAIN"); Env.set("WASSAT_ARMS","2")
    expect(wassat_sparse_domain_plan(f,config,0,0,0,0,0)).to eq(nil)
    Env.set("WASSAT_SPARSE_DOMAIN","1")
    expect(wassat_sparse_domain_plan(f,config,System.cpu_count,0,0,0,0)).to eq(nil)
    expect(wassat_sparse_domain_plan(f,config,0,1000000,0,0,0)).to eq(nil)
    expect(wassat_sparse_domain_plan(f,config,0,0,0,0,6442450944)).to eq(nil)
    if System.cpu_count > 0 && System.physical_memory_bytes > 100000000
      expect(wassat_sparse_domain_plan(f,config,0,0,0,0,0) != nil).to eq(true)
    sdn_restore("WASSAT_SPARSE_DOMAIN",old); sdn_restore("WASSAT_ARMS",arms); sdn_restore("WASSAT_DOMAIN_WALK",domain)
  it "publishes a fully checked model from its private worker" ->
    f = sdn_formula(false); stop = i64[4]; res = i64[f["nvars"]+8]
    plan = { "meta": i64[32], "scratch": wassat_sparse_domain_bytes(f["nvars"],f["flat_ncl"]) }
    h = Thread.new -> wassat_sparse_domain_arm(f,plan,stop,res,0,f["nvars"])
    h.join
    expect(res[0]).to eq(1); expect(wassat_stop_status(stop)).to eq(1)
    expect(plan["meta"][14]).to eq(f["flat_ncl"]); expect(plan["meta"][16]).to eq(1)
    model = []; v = 1
    while v <= f["nvars"]
      model.push(res[v] == 1 ? v : -v); v += 1
    expect(wassat_model_satisfies?(f,model)).to eq(true)
  it "cancels a live search without publishing a model" ->
    f = sdn_formula(true); stop = i64[4]; res = i64[f["nvars"]+8]
    plan = { "meta": i64[32], "scratch": wassat_sparse_domain_bytes(f["nvars"],f["flat_ncl"]) }
    h = Thread.new -> wassat_sparse_domain_arm(f,plan,stop,res,0,f["nvars"])
    ended = h.join(20); started = clock_ms(); z = wassat_stop_cancel(stop); z = h.join
    expect(clock_ms()-started < 100).to eq(true); expect(plan["meta"][2]).to eq(1)
    expect(plan["meta"][7] > 0).to eq(true); expect(res[0]).to eq(0); expect(wassat_stop_status(stop)).to eq(0)

spec_summary
