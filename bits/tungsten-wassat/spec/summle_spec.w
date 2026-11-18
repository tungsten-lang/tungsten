# spec: compiled -- exercises the native flat parser and conditioned solver
use spec
use ../lib/wassat

# Small independent encoding of selector tables with a chosen operation
# target. The test supplies no solved trace or model to the specialist.
-> sm_eq(clauses, base, value, gate)
  reverse = []
  bit = 0
  while bit < 16
    var = base + bit
    lit = (value & (1 << bit)) != 0 ? var : 0 - var
    clauses.push("[lit] [0 - gate] 0")
    reverse.push((0 - lit).to_s)
    bit += 1
  clauses.push(reverse.join(" ") + " [gate] 0")

-> sm_fixture(changed = false, extra_target = false, forbid_result = false)
  cs = []
  4.times -> (i)
    data = 2+i; gate = 6+i
    cs.push("1 [0-gate] 0"); cs.push("[data] [0-gate] 0")
    cs.push("-1 [0-data] [gate] 0")
  constants = [0, 2, 4, 7, 0, 0]
  gate = 256
  row = 0
  while row < 4
    sel = 10+32*row; operand = sel+16
    k = 0
    while k < constants.size
      unless row >= 2 && k == 4
        sg = gate; vg = gate+1; guard = gate+2; gate += 3
        value = constants[k]
        value = 11 if changed && row == 3 && k == 2
        sm_eq(cs, sel, k, sg); sm_eq(cs, operand, value, vg)
        cs.push("[sg] [guard] 0"); cs.push("[0-vg] [guard] 0")
        cs.push("[vg] [0-sg] [0-guard] 0"); cs.push("[guard] 0")
      k += 1
    row += 1
  sm_eq(cs, 138, 42, gate); sm_eq(cs, 154, 42, gate+1)
  if extra_target
    sm_eq(cs, 170, 17, gate+2); sm_eq(cs, 186, 17, gate+3)
  cs.push("-155 0") if forbid_result
  wassat_parse_cnf_native("p cnf [gate+3] [cs.size]\n"+cs.join("\n")+"\n")

-> sm_search(items, target, steps)
  nums = i32[10]; meta = i64[6]; k = 0
  while k < items.size
    nums[k] = items[k]; k += 1
  meta[0] = items.size; meta[1] = steps; meta[2] = target
  wassat_summle_search(nums, i32[16], i32[16], i32[8], meta)

describe "Summle expression search and checked lifting" ->
  it "extracts repeated table rows and completes a satisfying assignment" ->
    f = sm_fixture()
    result = wassat_summle_solve(f, 50)
    expect(result["status"]).to eq(1)
    m = result["summle"]
    expect([m[0], m[1], m[2], m[5]]).to eq([3, 2, 42, 2])
    expect(wassat_model_satisfies?(f, result["model"])).to eq(true)

  it "declines inconsistent constant tables and ambiguous target words" ->
    expect(wassat_summle_solve(sm_fixture(true), 50)).to eq(nil)
    expect(wassat_summle_solve(sm_fixture(false, true), 50)).to eq(nil)

  it "uses each occurrence once and obeys the operation horizon" ->
    expect(sm_search([2, 4], 8, 1)).to eq(true)
    expect(sm_search([2, 4], 16, 3)).to eq(false)
    expect(sm_search([2, 4, 4], 16, 1)).to eq(true)
    expect(sm_search([2, 4, 7], 42, 1)).to eq(false)
    expect(sm_search([2, 4, 7], 42, 2)).to eq(true)

  it "obeys the guarded low-word product and exact division" ->
    expect(sm_search([300, 300], 24464, 1)).to eq(true)
    expect(sm_search([256, 257], 256, 1)).to eq(false)
    expect(sm_search([36, 3], 12, 1)).to eq(true)
    expect(sm_search([35, 3], 11, 1)).to eq(false)

  it "returns UNKNOWN when its expression contradicts a side constraint" ->
    f = sm_fixture(false, false, true)
    result = wassat_summle_solve(f, 50)
    expect(result["status"]).to eq(0)
    unrestricted = Wassat.from_flat(f["nvars"], wassat_raw_artifact(f, f["nvars"]), 0)
    alternate = unrestricted.solve_assuming_budget([], 100)
    expect(alternate["status"]).to eq(1)
    expect(wassat_model_satisfies?(f, alternate["model"])).to eq(true)

spec_summary
