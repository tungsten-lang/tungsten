# spec: compiled -- native flat DIMACS parser
use spec
use ../lib/wassat

-> output_miter_fixture(invert, incomplete, cycle)
  # Outputs 3 and 4 compare interchanged copies of an AND and its complement.
  a = invert ? -3 : 3
  rows = ["[0-a] 5 6", "[0-a] -5 -6", "[a] -5 6", "[a] 5 -6",
    "-4 7 8", "-4 -7 -8", "4 -7 8", "4 7 -8"]
  input = cycle ? 7 : 1
  rows.push("[0-input] -2 5")
  rows.push("[input] -5")
  rows.push("2 -5") unless incomplete
  rows.push("-2 -1 6")
  rows.push("-6 2")
  rows.push("1 -6")
  rows.push("-7 -5")
  rows.push("7 5")
  rows.push("6 8")
  rows.push("-6 -8")
  rows.push("3 4")
  wassat_parse_cnf_native("p cnf 8 [rows.size]\n" + rows.join(" 0\n") + " 0\n")

describe "structural output miter" ->
  it "proves duplicated gates with reordered operands and inverted wires" ->
    f = output_miter_fixture(false, false, false)
    proof = wassat_om_refute(f, true)
    expect(proof != nil).to eq(true)
    expect(proof.ends_with?("0\n")).to eq(true)

  it "declines a satisfiable output change, incomplete definition, or cycle" ->
    expect(wassat_om_refute(output_miter_fixture(true, false, false), false)).to eq(nil)
    expect(wassat_om_refute(output_miter_fixture(false, true, false), false)).to eq(nil)
    expect(wassat_om_refute(output_miter_fixture(false, false, true), false)).to eq(nil)
