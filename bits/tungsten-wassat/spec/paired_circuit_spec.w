use spec
use ../lib/paired_circuit
use ../lib/cnf

# x1 != y1, x0 == y0, and x1 XOR (x0 AND m) == y1 XOR (y0 AND m).
# The witness comparator has only the gate polarities required by the root.
-> paired_circuit_fixture(require_difference)
  rows = ["-6 1", "-6 -2", "-7 -1", "-7 2", "8 6 7", "9 -3 4", "10 3 -4", "-11 -9", "-11 -10"]
  [[12, 3, 5], [13, 1, 12], [14, -1, -12], [15, -13, -14],
   [16, 4, 5], [17, 2, 16], [18, -2, -16], [19, -17, -18]].each -> (gate)
    v = gate[0]
    a = gate[1]
    b = gate[2]
    rows.push("[-v] [a]")
    rows.push("[-v] [b]")
    rows.push("[v] [-a] [-b]")
  ["20 -15 19", "21 15 -19", "-22 -20", "-22 -21", "-23 22", "-23 11"].each -> (row)
    rows.push(row)
  rows.push(require_difference ? "-23 -8" : "-23 8")
  rows.push("23")
  f = wassat_parse_cnf_test_stub("p cnf 23 [rows.size]\n" + rows.join(" 0\n") + " 0\n")
  lits = i64[f["flat_nlits"]]
  offs = i64[rows.size]
  lens = i64[rows.size]
  i = 0
  while i < lits.size
    lits[i] = f["flat_lits"][i]
    i += 1
  i = 0
  while i < rows.size
    offs[i] = f["flat_offs"][i]
    lens[i] = f["flat_lens"][i]
    i += 1
  f["flat_lits"] = lits
  f["flat_offs"] = offs
  f["flat_lens"] = lens
  f

describe "paired circuit equality propagation" ->
  it "closes the mismatch through a common XOR operand" ->
    f = paired_circuit_fixture(true)
    proof = wassat_paired_refutation(f, true, 0)
    expect(proof != nil).to eq(true)
    expect(proof.ends_with?("0\n")).to eq(true)
    expect(wassat_paired_refutation(f, false, 0)).to eq("")

  it "declines a satisfiable circuit with the same gate pairs" ->
    expect(wassat_paired_refutation(paired_circuit_fixture(false), true, 0)).to eq(nil)

  it "declines a mismatched prefix and an expired budget" ->
    f = paired_circuit_fixture(true)
    expect(wassat_paired_refutation(f, true, clock_ms() - 1)).to eq(nil)
    f["flat_lits"][0] = 1
    expect(wassat_paired_refutation(f, true, 0)).to eq(nil)

spec_summary
