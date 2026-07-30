use spec
use cnf
use stedman

# A small complete instance of the public guarded-transition schema. Five
# nodes form a cycle, both calls preserve the type, and every sequence label is
# copied from a fixed seven-bit boundary value. The fixture is generated
# independently of production recognition code.
-> stedman_fixture_text(omit_last = false)
  nnodes = 5
  nbits = 7
  type_base = nnodes + 1
  seq_base = 4 * nnodes + 1
  nvars = 4 * nnodes + (nnodes - 1) * nbits
  lines = []

  node = 0
  while node < nnodes
    second_bit = type_base + node * 3 + 1
    lines.push("-[second_bit] -[second_bit + 1] 0")
    node += 1
  # Pin one call to exercise unit-hint handling.
  lines.push("3 0")

  node = 0
  while node < nnodes
    destination = (node + 1) % nnodes
    type = 0
    while type < 6
      call = 0
      while call < 2
        gate = []
        bit = 0
        while bit < 3
          unless type >= 4 && bit == 1
            variable = type_base + node * 3 + bit
            gate.push((type & (1 << bit)) != 0 ? 0 - variable : variable)
          bit += 1
        call_var = node + 1
        gate.push(call == 1 ? 0 - call_var : call_var)

        bit = 0
        while bit < 3
          variable = type_base + destination * 3 + bit
          payload = (type & (1 << bit)) != 0 ? variable : 0 - variable
          lines.push((gate + [payload]).join(" ") + " 0")
          bit += 1

        if node == 0
          bit = 0
          while bit < nbits
            variable = seq_base + (destination - 1) * nbits + bit
            payload = bit == 0 ? variable : 0 - variable
            lines.push((gate + [payload]).join(" ") + " 0")
            bit += 1
        elsif destination == 0
          bit = 0
          while bit < nbits
            variable = seq_base + (node - 1) * nbits + bit
            payload = bit == 0 ? variable : 0 - variable
            lines.push((gate + [payload]).join(" ") + " 0")
            bit += 1
        else
          bit = 0
          while bit < nbits
            source_var = seq_base + (node - 1) * nbits + bit
            destination_var = seq_base + (destination - 1) * nbits + bit
            lines.push((gate + [source_var, 0 - destination_var]).join(" ") + " 0")
            lines.push((gate + [0 - source_var, destination_var]).join(" ") + " 0")
            bit += 1
        call += 1
      type += 1
    node += 1

  lines.pop if omit_last
  "p cnf [nvars] [lines.size]\n" + lines.join("\n") + "\n"

-> stedman_fixture(omit_last = false)
  wassat_parse_cnf_native(stedman_fixture_text(omit_last))

describe "Wassat Stedman triples specialist" ->
  it "reconstructs the guarded cycle and returns a verified complete model" ->
    formula = stedman_fixture
    result = wassat_stedman_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(1)
    expect(result["transitions"]).to eq(5)
    expect(result["nodes"] > 0).to eq(true)
    expect(result["model"].size).to eq(48)
    expect(wassat_model_satisfies?(formula, result["model"])).to eq(true)

  it "falls through instead of claiming UNSAT at the search cap" ->
    result = wassat_stedman_solve(stedman_fixture, 1)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(0)
    expect(result["model"]).to eq([])

  it "rejects an incomplete guarded relation" ->
    result = wassat_stedman_solve(stedman_fixture(true))
    expect(result["recognized"]).to eq(false)
    expect(result["status"]).to eq(0)

  it "falls through on an unrelated formula" ->
    formula = wassat_parse_cnf_native("p cnf 1 1\n1 0\n")
    result = wassat_stedman_solve(formula)
    expect(result["recognized"]).to eq(false)
    expect(result["status"]).to eq(0)

  it "returns a SAT model in proof mode without leaving an artifact" ->
    bin = env("WASSAT_TEST_BIN")
    expect(bin == nil).to eq(false)
    input = "/tmp/wassat-stedman-proof-mode.cnf"
    proof = "/tmp/wassat-stedman-proof-mode.wrat"
    output = "/tmp/wassat-stedman-proof-mode.out"
    expect(write_file(input, stedman_fixture_text)).to eq(true)
    z = ccall("__w_unlink", proof)
    cmd = "(" + bin + " " + input + " --proof " + proof
    cmd += " > " + output + " 2>&1); test $? -eq 10"
    expect(system(cmd)).to eq(true)
    text = read_file(output)
    expect(text.include?("s SATISFIABLE")).to eq(true)
    expect(text.include?(
      "c mode: proof (verified Stedman triples model)"
    )).to eq(true)
    expect(file?(proof)).to eq(false)

spec_summary
