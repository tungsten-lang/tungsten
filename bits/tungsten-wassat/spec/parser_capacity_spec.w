# spec: compiled -- exercises the native DIMACS scanner and buffer bounds
use spec
use ../lib/cnf

-> capacity_padding(n)
  text = ""
  i = 0
  while i < n
    text += "c filler line for parser capacity coverage 0123456789\n"
    i += 1
  text

PADDING = capacity_padding(1400)

describe "Native DIMACS capacity hints" ->
  it "sizes small-file clause tables from a valid declaration" ->
    f = wassat_parse_cnf_native("p cnf 3 2\n" + PADDING + "1 -2 0\n3 0\n")
    expect(f["flat_ncl"]).to eq(2)
    expect(f["flat_nlits"]).to eq(3)
    expect(f["flat_lits"][1]).to eq(-2)
    expect(f["flat_offs"].size < 100).to eq(true)
  it "falls back for a header after the bounded hint window" ->
    f = wassat_parse_cnf_native(PADDING + "p cnf 1 1\n1 0\n")
    expect(f["flat_ncl"]).to eq(1)
  it "ignores a clause count truncated by the hint window" ->
    prefix = "c " + "x" * 65522 + "\n"
    f = wassat_parse_cnf_native(prefix + "p cnf 1 10000\n" + "1 0\n" * 10000)
    expect(f["flat_ncl"]).to eq(10000)
    expect(f["flat_nlits"]).to eq(10000)
    expect(f["flat_lits"][9999]).to eq(1)
  it "falls back for whitespace the optional hint does not recognize" ->
    f = wassat_parse_cnf_native("  p\tcnf\t2\t1\n" + PADDING + "-2 0\n")
    expect(f["flat_lits"][0]).to eq(-2)
  it "accepts empty formulas and explicit empty clauses" ->
    f = wassat_parse_cnf_native("p cnf 1 0\n" + PADDING)
    expect(f["flat_ncl"]).to eq(0)
    f = wassat_parse_cnf_native("p cnf 1 2\n" + PADDING + "0\n0")
    expect(f["flat_ncl"]).to eq(2)
    expect(f["flat_nlits"]).to eq(0)
  it "keeps enough literal space for densely packed unit clauses" ->
    lines = []
    i = 0
    while i < 20000
      lines.push("1 0")
      i += 1
    f = wassat_parse_cnf_native("p cnf 1 20000\n" + lines.join("\n"))
    expect(f["flat_ncl"]).to eq(20000)
    expect(f["flat_nlits"]).to eq(20000)
    expect(f["flat_lits"][19999]).to eq(1)
  it "rejects too many clauses with a tightened table" ->
    expect(-> () wassat_parse_cnf_native("p cnf 1 1\n" + PADDING + "1 0\n1 0\n")).to raise_error
  it "rejects too few clauses with a tightened table" ->
    expect(-> () wassat_parse_cnf_native("p cnf 1 2\n" + PADDING + "1 0\n")).to raise_error
  it "rejects malformed declarations after reading a possible hint" ->
    expect(-> () wassat_parse_cnf_native("p cnf 1 1junk\n" + PADDING + "1 0\n")).to raise_error
    expect(-> () wassat_parse_cnf_native("p cnf 1 999999999999999999999999\n" + PADDING + "1 0\n")).to raise_error

  it "retries literal exhaustion and preserves every clause" ->
    f = wassat_parse_cnf_native_buffers("p cnf 3 3\n1 1 1 0\n-2 3 0\n0", 2, 8, 32)
    expect(f["flat_ncl"]).to eq(3)
    expect(f["flat_nlits"]).to eq(5)
    expect(f["flat_lits"][0]).to eq(1)
    expect(f["flat_lits"][2]).to eq(1)
    expect(f["flat_lits"][3]).to eq(-2)
    expect(f["flat_lits"][4]).to eq(3)
    expect(f["flat_offs"][0]).to eq(0)
    expect(f["flat_offs"][1]).to eq(3)
    expect(f["flat_offs"][2]).to eq(5)
    expect(f["flat_lens"][2]).to eq(0)
  it "still rejects invalid input encountered after a retry" ->
    expect(-> () wassat_parse_cnf_native_buffers("p cnf 1 1\n1 1 1 bad 0\n", 1, 8, 32)).to raise_error
    expect(-> () wassat_parse_cnf_native_buffers("p cnf 1 1\n1 1 1 2 0\n", 1, 8, 32)).to raise_error
    expect(-> () wassat_parse_cnf_native_buffers("p cnf 1 1\n1 1 1\n", 1, 8, 32)).to raise_error
    expect(-> () wassat_parse_cnf_native_buffers("p cnf 1 1\n1 1 1 0\n1 0\n", 1, 8, 32)).to raise_error
  it "stops if the fallback cannot satisfy the buffer request" ->
    expect(-> () wassat_parse_cnf_native_buffers("p cnf 1 1\n1 1 1 0\n", 1, 8, 2)).to raise_error
    expect(-> () wassat_parse_cnf_native_buffers("p cnf 1 8\n", 1, 2, 32)).to raise_error

spec_summary
