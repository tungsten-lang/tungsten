# spec: compiled -- uses the native flat DIMACS parser and proof-mode CDCL
use spec
use ../lib/wassat

-> gm_fixture(assertion, complete = true, shared = false)
  # Two independently numbered copies of (p AND q) AND r.
  next_gate = shared ? 4 : 5
  rows = ["-1 -2 -3", "-1 2 3", "1 -2 3", "1 2 -3",
    "2 -4 -8", "-2 4", "-2 8",
    "3 [0-next_gate] -8", "-3 [next_gate]", "-3 8",
    "4 -6 -7", "-4 6", "-4 7"]
  unless shared
    rows.push("5 -7 -6"); rows.push("-5 7")
    rows.push("-5 6") if complete
  rows.push("[assertion]")
  wassat_parse_cnf_native("p cnf 8 [rows.size]\n" + rows.join(" 0\n") + " 0\n")

describe "native gate-miter sweep" ->
  it "proposes an internal pair across the comparator cones" ->
    f = gm_fixture(1)
    plan = wassat_gm_schedule(f)
    expect(plan["assertion"]).to eq(1)
    expect(plan["pairs"]).to eq([5, 4])
    r = wassat_gm_solve(f, plan, WASSAT_PROOF_NONE, nil)
    expect(r["status"]).to eq(-1)

  it "declines an agreement query, incomplete gate and shared-only cone" ->
    expect(wassat_gm_schedule(gm_fixture(-1))).to eq(nil)
    expect(wassat_gm_schedule(gm_fixture(1, false))).to eq(nil)
    expect(wassat_gm_schedule(gm_fixture(1, true, true))).to eq(nil)
