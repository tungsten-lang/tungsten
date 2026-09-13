use spec
use ../lib/wassat

-> xor_test_satisfies(clauses, mask)
  clauses.all? -> (clause)
    clause.any? -> (lit)
      value = ((mask >> (lit.abs - 1)) & 1) == 1
      lit > 0 ? value : !value

describe "DIMACS+XOR conversion" ->
  it "preserves every assignment under existential auxiliary extension" ->
    samples = [[], [1], [-1], [1, 1], [1, -1], [1, 2], [1, -2], [1, 2, 3], [-1, -2, 3], [1, 2, 1, -3]]
    samples.each -> (lits)
      f = wassat_expand_xor("p cnf 3 1\nx " + lits.join(" ") + " 0\n")
      mask = 0
      while mask < 8
        parity = 0
        lits.each -> (lit)
          value = (mask >> (lit.abs - 1)) & 1
          value = 1 - value if lit < 0
          parity = parity ^ value
        found = false
        extension = 0
        while extension < (1 << (f["nvars"] - 3))
          found = true if xor_test_satisfies(f["clauses"], mask | (extension << 3))
          extension += 1
        expect(found).to eq(parity == 1)
        mask += 1

  it "accepts attached markers, multiline clauses, mixed CNF and SATLIB trailers" ->
    f = wassat_expand_xor("c test\np cnf 3 3\nx1 -2\n3 0\n1 0 -1 2 0\n%\n0\n")
    expect(f["input_clauses"]).to eq(3)
    expect(f["xor_clauses"]).to eq(1)
    expect(f["original_nvars"]).to eq(3)
    roundtrip = wassat_parse_cnf(wassat_expanded_xor_text(f))
    expect(roundtrip["nvars"]).to eq(f["nvars"])
    expect(roundtrip["clauses"]).to eq(f["clauses"])

  it "keeps the ordinary CNF parser strict" ->
    expect(-> () wassat_parse_cnf("p cnf 2 1\nx1 2 0\n")).to raise_error

  it "rejects malformed, truncated, misplaced and out-of-range XOR input" ->
    bad = ["x1 0\n", "p cnf 2 1\nx1\n", "p cnf 2 1\nx\n", "p cnf 2 1\nx3 0\n", "p cnf 2 1\nx1 -0\n", "p cnf 2 1\nxfoo 0\n", "p cnf 2 1\n1\nx2 0\n", "p cnf 2 1\nx\nx1 0\n", "p cnf 2 0\nx1 0\n", "p cnf 2 2\nx1 0\n", "p cnf 2 1\np cnf 2 1\nx1 0\n", "p xnf 2 1\nx1 0\n"]
    bad.each -> (text)
      expect(-> () wassat_expand_xor(text)).to raise_error
