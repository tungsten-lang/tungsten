use spec
use ../lib/cnf
use ../lib/policy
use ../lib/solver
use ../lib/preprocess
use ../lib/sum_of_three_cubes

-> sum3_fixture_clause(lines, values)
  lines.push(values.join(" ") + " 0")

-> sum3_fixture_anchor(lines, base, out, width)
  sum3_fixture_clause(lines, [0 - base, out])
  sum3_fixture_clause(lines, [base, 0 - out])
  sum3_fixture_clause(lines, [base, 0 - out])
  bit = 1
  while bit < width
    gate = out + bit
    sum3_fixture_clause(lines, [0 - base, 0 - base - bit, gate])
    sum3_fixture_clause(lines, [base + bit, 0 - gate])
    sum3_fixture_clause(lines, [base, 0 - gate])
    bit += 1

# Width eight is sufficient for target 91. The six anchor rows model the
# recognizable x*x then x*x^2 shells; the production solver still supplies
# and verifies the complete model rather than trusting this fixture shape.
-> sum3_fixture_cnf(target = 91)
  width = 8
  lines = []
  word = 0
  while word < 3
    clause = []
    bit = 0
    while bit < width
      clause.push(0 - word * width - bit - 1)
      bit += 1
    sum3_fixture_clause(lines, clause)
    word += 1

  sum3_fixture_anchor(lines, 1, 25, width)
  sum3_fixture_anchor(lines, 9, 34, width)
  sum3_fixture_anchor(lines, 17, 43, width)
  sum3_fixture_anchor(lines, 1, 52, width)
  sum3_fixture_anchor(lines, 9, 61, width)
  sum3_fixture_anchor(lines, 17, 70, width)

  output_base = 79
  carry_base = 94
  bit = 0
  while bit < width
    sum3_fixture_clause(lines, [0 - carry_base - bit])
    output = output_base + 2 * bit
    sum3_fixture_clause(
      lines, [((target >> bit) & 1) == 1 ? output : 0 - output]
    )
    bit += 1
  "p cnf 101 [lines.size]\n" + lines.join("\n") + "\n"

describe "Wassat sum-of-three-cubes shortcut" ->
  it "derives the target from the terminal DIMACS units" ->
    formula = wassat_parse_cnf_native(sum3_fixture_cnf)
    pm = i64[8]
    ok = wassat_sum3_scan(
      formula["flat_lits"], formula["flat_offs"], formula["flat_lens"],
      formula["nvars"], formula["flat_ncl"], pm
    )
    expect(ok).to eq(1)
    expect(pm[0]).to eq(8)
    expect(pm[1]).to eq(91)

  it "finds bounded operands and verifies the complete model" ->
    formula = wassat_parse_cnf_native(sum3_fixture_cnf)
    result = wassat_sum3_solve(formula)
    expect(result["status"]).to eq(1)
    expect([result["x"], result["y"], result["z"]]).to eq([3, 4, 0])
    expect(wassat_model_satisfies?(formula, result["model"])).to eq(true)

  it "falls through on a malformed cube anchor" ->
    text = sum3_fixture_cnf.replace("-1 -2 26 0", "-1 -2 -26 0")
    formula = wassat_parse_cnf_native(text)
    expect(wassat_sum3_solve(formula)["recognized"]).to eq(false)

  it "falls through on a malformed target suffix" ->
    text = sum3_fixture_cnf.replace("-94 0\n79 0", "94 0\n79 0")
    formula = wassat_parse_cnf_native(text)
    expect(wassat_sum3_solve(formula)["recognized"]).to eq(false)

  it "falls through when the recovered target has no bounded decomposition" ->
    formula = wassat_parse_cnf_native(sum3_fixture_cnf(13))
    result = wassat_sum3_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(0)
    expect(result["model"].empty?).to eq(true)

  it "returns a verified SAT model in proof mode without leaving an artifact" ->
    bin = env("WASSAT_TEST_BIN")
    expect(bin == nil).to eq(false)
    input = "/tmp/wassat-sum3-proof-mode.cnf"
    proof = "/tmp/wassat-sum3-proof-mode.drat"
    output = "/tmp/wassat-sum3-proof-mode.out"
    expect(write_file(input, sum3_fixture_cnf)).to eq(true)
    z = ccall("__w_unlink", proof)
    cmd = "(" + bin + " " + input + " --drat " + proof
    cmd += " > " + output + " 2>&1); test $? -eq 10"
    expect(system(cmd)).to eq(true)
    text = read_file(output)
    expect(text.include?("s SATISFIABLE")).to eq(true)
    expect(text.include?(
      "c mode: proof (verified sum-of-three-cubes circuit model)"
    )).to eq(true)
    expect(file?(proof)).to eq(false)

spec_summary
