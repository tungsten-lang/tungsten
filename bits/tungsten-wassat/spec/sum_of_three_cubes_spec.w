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
-> sum3_fixture_cnf(target)
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

# A SAT-X prefix and equality output with a free interior. Insert an
# optional clause there to reject the proposed operands during completion.
-> satx_cube_fixture(target, extra)
  width = 70
  one = 3 * width + 2
  rows = ["-1 0"]
  bit = 0
  while bit < width
    c = one + bit
    rows.push("[bit == 0 ? c : 0 - c] 0")
    bit += 1
  bit = 0
  while bit < 4
    v = bit + 2
    g = one + width + bit
    rows.push("[v] [one] -[g] 0")
    rows.push("-[v] [one] -[g] 0")
    rows.push("[v] -[one] -[g] 0")
    rows.push("-[v] -[one] [g] 0")
    bit += 1
  rows.push(extra) unless extra == ""
  a = one + width + 5
  b = a + width
  d = b + width
  bit = 0
  while bit < width
    positive = bit < 31 && ((target >> bit) & 1) != 0
    rows.push("[positive ? b + bit : 0 - b - bit] 0")
    bit += 1
  bit = 0
  while bit < width
    v = a + bit
    c = b + bit
    g = d + bit
    rows.push("[v] [c] -[g] 0")
    rows.push("-[v] -[c] -[g] 0")
    rows.push("[v] -[c] [g] 0")
    rows.push("-[v] [c] [g] 0")
    bit += 1
  bit = 0
  while bit < width
    rows.push("-[d + bit] 0")
    bit += 1
  wassat_parse_cnf_native("p cnf [d + width - 1] [rows.size]\n" + rows.join("\n") + "\n")

describe "Wassat sum-of-three-cubes shortcut" ->
  it "derives the target from the terminal DIMACS units" ->
    formula = wassat_parse_cnf_native(sum3_fixture_cnf(91))
    pm = i64[8]
    ok = wassat_sum3_scan(
      formula["flat_lits"], formula["flat_offs"], formula["flat_lens"],
      formula["nvars"], formula["flat_ncl"], pm
    )
    expect(ok).to eq(1)
    expect(pm[0]).to eq(8)
    expect(pm[1]).to eq(91)

  it "recognizes paired binary and output-unit suffixes" ->
    text = sum3_fixture_cnf(91)
    bit = 0
    while bit < 8
      output = 79 + 2 * bit
      literal = ((91 >> bit) & 1) == 1 ? output : 0 - output
      text = text.replace("[0 - 94 - bit] 0\n[literal] 0", "[0 - literal] [0 - 94 - bit] 0\n[literal] 0")
      bit += 1
    formula = wassat_parse_cnf_native(text)
    pm = i64[8]
    expect(wassat_sum3_scan(
      formula["flat_lits"], formula["flat_offs"], formula["flat_lens"],
      formula["nvars"], formula["flat_ncl"], pm
    )).to eq(1)
    expect(pm[1]).to eq(91)
    expect(pm[5]).to eq(1)
    broken = wassat_parse_cnf_native(text.replace("-79 -94 0", "79 -94 0"))
    expect(wassat_sum3_solve(broken)["recognized"]).to eq(false)

  it "derives signed cube magnitudes from the target" ->
    values = i64[3]
    expect(wassat_sum3_find_signed(19, values, 3, 3)).to eq(1)
    expect([values[0], values[1], values[2]]).to eq([3, 2, 0])
    expect(wassat_sum3_find_signed(19, values, 1, 0)).to eq(1)
    expect(wassat_sum3_find_signed(13, values, 3, 3)).to eq(0)
    expect(wassat_sum3_find_signed(1000000001, values, 3, 3)).to eq(0)
    expect(wassat_sum3_find_signed(19, values, 201, 3)).to eq(0)

  it "matches an independent bounded signed search across targets" ->
    target = 1
    while target <= 50
      found = false
      x = -8
      while x <= 8
        y = -8
        while y <= 8
          if x + y >= 1 && x + y <= 3
            z = -3
            while z <= 3
              found = true if x * x * x + y * y * y + z * z * z == target
              z += 1
          y += 1
        x += 1
      values = i64[3]
      actual = wassat_sum3_find_signed(target, values, 3, 3)
      expect(actual == 1).to eq(found)
      target += 1

  it "uses exact integer roots at square boundaries" ->
    expect(wassat_sum3_integer_root(0)).to eq(0)
    expect(wassat_sum3_integer_root(24)).to eq(4)
    expect(wassat_sum3_integer_root(25)).to eq(5)
    expect(wassat_sum3_integer_root(26)).to eq(5)
    expect(wassat_sum3_integer_root(12000000000)).to eq(109544)

  it "finds bounded operands and verifies the complete model" ->
    formula = wassat_parse_cnf_native(sum3_fixture_cnf(91))
    result = wassat_sum3_solve(formula)
    expect(result["status"]).to eq(1)
    expect([result["x"], result["y"], result["z"]]).to eq([3, 4, 0])
    expect(wassat_model_satisfies?(formula, result["model"])).to eq(true)

  it "falls through on a malformed cube anchor" ->
    text = sum3_fixture_cnf(91).replace("-1 -2 26 0", "-1 -2 -26 0")
    formula = wassat_parse_cnf_native(text)
    expect(wassat_sum3_solve(formula)["recognized"]).to eq(false)

  it "falls through on a malformed target suffix" ->
    text = sum3_fixture_cnf(91).replace("-94 0\n79 0", "94 0\n79 0")
    formula = wassat_parse_cnf_native(text)
    expect(wassat_sum3_solve(formula)["recognized"]).to eq(false)

  it "falls through when the recovered target has no bounded decomposition" ->
    formula = wassat_parse_cnf_native(sum3_fixture_cnf(13))
    result = wassat_sum3_solve(formula)
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(0)
    expect(result["model"].empty?).to eq(true)

  it "reads the compare target and zero-extends signed witnesses above 64 bits" ->
    [3, 89].each -> (target)
      formula = satx_cube_fixture(target, "")
      result = wassat_sum3_solve(formula)
      expect(result["target"]).to eq(target)
      expect(result["status"]).to eq(1)
      x = result["x"]; y = result["y"]; z = result["z"]
      expect(x*x*x + y*y*y - z*z*z).to eq(target)
      expect(result["model"][67] < 0).to eq(true)
      expect(wassat_model_satisfies?(formula, result["model"])).to eq(true)

  it "rejects an incompatible SAT-X proposal without claiming UNSAT" ->
    # The proposed first operand is even. This unit requires it to be odd.
    result = wassat_sum3_solve(satx_cube_fixture(3, "2 0"))
    expect(result["recognized"]).to eq(true)
    expect(result["status"]).to eq(0)
    expect(result["model"].empty?).to eq(true)

  it "returns a verified SAT model in proof mode without leaving an artifact" ->
    bin = env("WASSAT_TEST_BIN")
    expect(bin == nil).to eq(false)
    input = "/tmp/wassat-sum3-proof-mode.cnf"
    proof = "/tmp/wassat-sum3-proof-mode.drat"
    output = "/tmp/wassat-sum3-proof-mode.out"
    expect(write_file(input, sum3_fixture_cnf(91))).to eq(true)
    File.unlink(proof) if File.exist?(proof)
    cmd = "(env -u TUNGSTEN_WASSAT_PARSE_STUB " + bin + " " + input + " --drat " + proof
    cmd += " > " + output + " 2>&1); test $? -eq 10"
    expect(system(cmd)).to eq(true)
    text = read_file(output)
    expect(text.include?("s SATISFIABLE")).to eq(true)
    expect(text.include?(
      "c mode: proof (verified sum-of-three-cubes circuit model)"
    )).to eq(true)
    expect(file?(proof)).to eq(false)

spec_summary
