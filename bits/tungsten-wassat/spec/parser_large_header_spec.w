use spec
use ../lib/wassat

describe "Large DIMACS headers" ->
  it "accepts competition-scale variable counts in the boxed parser" ->
    f = wassat_parse_cnf("p cnf 117295030 0\n")
    expect(f["nvars"]).to eq(117295030)
    f = wassat_parse_cnf("p cnf 200000000 0\n")
    expect(f["nvars"]).to eq(200000000)
    expect(-> () wassat_parse_cnf("p cnf 200000001 0\n")).to raise_error

  it "allows XOR auxiliaries up to the same variable limit" ->
    f = wassat_expand_xor("p cnf 199999999 1\nx1 2 3 0\n")
    expect(f["nvars"]).to eq(200000000)
    expect(-> () wassat_expand_xor("p cnf 200000000 1\nx1 2 3 0\n")).to raise_error

  it "checks clause counts up to the raised limit in both parsers" ->
    [false, true].each -> (is_xor)
      message = ""
      begin
        if is_xor
          wassat_expand_xor("p cnf 1 315573317\n")
        else
          wassat_parse_cnf("p cnf 1 315573317\n")
      rescue e
        message = "[e]"
      expect(message.index("clause count mismatch") != nil).to eq(true)
      message = ""
      begin
        if is_xor
          wassat_expand_xor("p cnf 1 500000001\n")
        else
          wassat_parse_cnf("p cnf 1 500000001\n")
      rescue e
        message = "[e]"
      expect(message.index("implausible clause count") != nil).to eq(true)
