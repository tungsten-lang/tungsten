use spec
use wassat

-> multiplier_gate_lines(a, b, o, kind)
  out = []
  av = 0
  while av <= 1
    bv = 0
    while bv <= 1
      want = kind == WASSAT_MULTIPLIER_XOR ? av ^ bv : av & bv
      wrong = 1 - want
      la = av == 0 ? a : 0 - a
      lb = bv == 0 ? b : 0 - b
      lo = wrong == 0 ? o : 0 - o
      out.push("[la] [lb] [lo] 0")
      bv += 1
    av += 1
  out

# Canonical two-by-two multiplier:
#   5 = a0b0
#   8 = a1b0 xor a0b1
#  11 = a1b1 xor carry
#  12 = a1b1 and carry
# Sinks 5,8,11,12 are therefore product bits 0..3.
-> multiplier_2x2_cnf(product)
  lines = []
  gates = [
    [1, 3, 5, WASSAT_MULTIPLIER_AND],
    [2, 3, 6, WASSAT_MULTIPLIER_AND],
    [1, 4, 7, WASSAT_MULTIPLIER_AND],
    [6, 7, 8, WASSAT_MULTIPLIER_XOR],
    [6, 7, 9, WASSAT_MULTIPLIER_AND],
    [2, 4, 10, WASSAT_MULTIPLIER_AND],
    [9, 10, 11, WASSAT_MULTIPLIER_XOR],
    [9, 10, 12, WASSAT_MULTIPLIER_AND]
  ]
  gates.each -> (g)
    multiplier_gate_lines(g[0], g[1], g[2], g[3]).each -> (line)
      lines.push(line)
  sinks = [5, 8, 11, 12]
  i = 0
  while i < sinks.size
    v = sinks[i]
    lines.push(((product >> i) & 1) == 1 ? "[v] 0" : "-[v] 0")
    i += 1
  "p cnf 12 [lines.size]\n" + lines.join("\n") + "\n"

describe "Wassat multiplier shortcut" ->
  it "constructs and verifies every representative satisfiable product" ->
    [0, 1, 6, 9].each -> (product)
      text = multiplier_2x2_cnf(product)
      formula = wassat_parse_cnf_native(text)
      model = wassat_multiplier_model(formula)
      expect(model.empty?).to eq(false)
      expect(wassat_model_satisfies?(formula, model)).to eq(true)

  it "declines products with no width-valid factorization" ->
    [7, 8].each -> (product)
      formula = wassat_parse_cnf_native(multiplier_2x2_cnf(product))
      expect(wassat_multiplier_model(formula).empty?).to eq(true)

  it "declines a truth table that is not AND or XOR" ->
    text = multiplier_2x2_cnf(6)
    # Change one forbidden row in gate 5 without changing the DIMACS shape.
    text = text.replace("1 3 -5 0", "1 3 5 0")
    formula = wassat_parse_cnf_native(text)
    expect(wassat_multiplier_model(formula).empty?).to eq(true)

  it "declines a unit on an internal node" ->
    text = multiplier_2x2_cnf(6)
    text = text.replace("-12 0\n", "-9 0\n")
    formula = wassat_parse_cnf_native(text)
    expect(wassat_multiplier_model(formula).empty?).to eq(true)

  it "uses a verified multiplier model in proof mode without publishing a proof" ->
    bin = env("WASSAT_TEST_BIN")
    expect(bin == nil).to eq(false)
    input = "/tmp/wassat-multiplier-proof-mode.cnf"
    proof = "/tmp/wassat-multiplier-proof-mode.drat"
    output = "/tmp/wassat-multiplier-proof-mode.out"
    expect(write_file(input, multiplier_2x2_cnf(6))).to eq(true)
    File.unlink(proof) if File.exist?(proof)
    cmd = "(" + bin + " " + input + " --drat " + proof + " > " + output + " 2>&1); test $? -eq 10"
    ok = system(cmd)
    expect(ok).to eq(true)
    text = read_file(output)
    expect(text.include?("s SATISFIABLE")).to eq(true)
    expect(text.include?("c mode: proof (verified multiplier circuit model)")).to eq(true)
    expect(file?(proof)).to eq(false)

spec_summary
