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


-> digit_bound_scan(text)
  lits = i64[32]; offs = i64[8]; lens = i64[8]; hdr = i64[8]
  z = ccall("__w_parse_dimacs", text, lits, offs, lens, hdr)
  [hdr, lits]

describe "Native DIMACS decimal bounds" ->
  it "accepts signed literals exactly at the scanner limit" ->
    a = digit_bound_scan("p cnf 2000000000 1\n2000000000 -2000000000 +1999999999 0\n")
    expect(a[0][4]).to eq(0)
    expect(a[0][0]).to eq(2000000000)
    expect(a[0][3]).to eq(3)
    expect(a[1][0]).to eq(2000000000)
    expect(a[1][1]).to eq(-2000000000)
    expect(a[1][2]).to eq(1999999999)
  it "rejects the first out-of-range digit in either polarity" ->
    ["2000000001", "-2000000001", "+2000000001", "2000000010", "18446744073709551616"].each ->(value)
      a = digit_bound_scan("p cnf 2000000000 1\n[value] 0\n")
      expect(a[0][4]).to eq(4)
      expect(a[0][5]).to eq(2)
  it "preserves arbitrarily padded leading zeros on nonzero numbers" ->
    zeros = "0" * 100
    a = digit_bound_scan("p cnf [zeros]2000000000 1\n-[zeros]2000000000 0\n")
    expect(a[0][4]).to eq(0)
    expect(a[1][0]).to eq(-2000000000)
  it "applies the same bound to both declaration fields" ->
    a = digit_bound_scan("p cnf 2000000001 0\n")
    expect(a[0][4]).to eq(2)
    a = digit_bound_scan("p cnf 1 2000000001\n")
    expect(a[0][4]).to eq(2)
    a = digit_bound_scan("p cnf 1 2000000000\n")
    expect(a[0][4]).to eq(7)
  it "keeps zero-terminator and delimiter validation strict" ->
    ["00", "-0", "+0", "1junk", "2000000000x"].each ->(value)
      a = digit_bound_scan("p cnf 2000000000 1\n[value] 0\n")
      expect(a[0][4]).to eq(3)

describe "Native DIMACS exact zero terminators" ->
  it "keeps empty-clause offsets across every accepted delimiter and EOF" ->
    [" ", "\t", "\r", "\n"].each ->(sep)
      f = wassat_parse_cnf_native("p cnf 1 3\n0[sep]1 0[sep]0")
      expect(f["flat_ncl"]).to eq(3)
      expect(f["flat_nlits"]).to eq(1)
      expect(f["flat_offs"][0]).to eq(0)
      expect(f["flat_offs"][1]).to eq(0)
      expect(f["flat_offs"][2]).to eq(1)
      expect(f["flat_lens"][0]).to eq(0)
      expect(f["flat_lens"][1]).to eq(1)
      expect(f["flat_lens"][2]).to eq(0)
  it "requires a delimiter before treating zero as a terminator" ->
    ["0x", "0c", "0%", "000", "-00", "+00", "0-1", "00+1"].each ->(value)
      a = digit_bound_scan("p cnf 1 1\n[value]\n")
      expect(a[0][4]).to eq(3)
      expect(a[0][5]).to eq(2)
  it "retains header and declared-count errors for exact zero" ->
    a = digit_bound_scan("0\n")
    expect(a[0][4]).to eq(1)
    expect(a[0][5]).to eq(1)
    a = digit_bound_scan("p cnf 1 0\n0\n")
    expect(a[0][4]).to eq(6)
    expect(a[0][5]).to eq(2)

spec_summary
