use spec
use wassat

-> fermat_fixture_clause(lines, values)
  lines.push(values.join(" ") + " 0")

# A small canonical width-four subtract block.  For target 15, Pollard-rho
# recovers 3*5, hence a=4 and b=1.  The eight equivalences expose
# a^2=0 and b^2=1 modulo 16 to the fixed subtractor.
-> fermat_fixture_cnf(target = 15)
  width = 4
  lines = []
  fermat_fixture_clause(lines, [-1, -2, -3, -4])
  fermat_fixture_clause(lines, [-5, -6, -7, -8])

  # x-square output word 9..12: all bits mirror a0, which is zero for a=4.
  v = 9
  while v <= 12
    fermat_fixture_clause(lines, [-1, v])
    fermat_fixture_clause(lines, [1, 0 - v])
    v += 1
  # y-square output word 13..16: bit zero mirrors b0; the rest mirror a0.
  fermat_fixture_clause(lines, [-5, 13])
  fermat_fixture_clause(lines, [5, -13])
  v = 14
  while v <= 16
    fermat_fixture_clause(lines, [-1, v])
    fermat_fixture_clause(lines, [1, 0 - v])
    v += 1

  # Bit zero and its no-borrow carry.
  ylit = (target & 1) == 1 ? 13 : -13
  fermat_fixture_clause(lines, [9, ylit])
  fermat_fixture_clause(lines, [-9, 0 - ylit])
  fermat_fixture_clause(lines, [9, -13, -17])
  fermat_fixture_clause(lines, [9, 13, 17])
  fermat_fixture_clause(lines, [-9, 13, 17])
  fermat_fixture_clause(lines, [-9, 17])

  bit = 1
  while bit < width
    x = 9 + bit
    y = 13 + bit
    carry = 16 + bit
    one = ((target >> bit) & 1) == 1
    sy = one ? 0 - y : y
    fermat_fixture_clause(lines, [x, sy, carry])
    fermat_fixture_clause(lines, [x, 0 - sy, 0 - carry])
    fermat_fixture_clause(lines, [0 - x, 0 - sy, carry])
    fermat_fixture_clause(lines, [0 - x, sy, 0 - carry])
    if bit + 1 < width
      next_carry = carry + 1
      fermat_fixture_clause(lines, [x, 0 - y, 0 - next_carry])
      fermat_fixture_clause(lines, [x, carry, 0 - next_carry])
      fermat_fixture_clause(lines, [x, y, 0 - carry, next_carry])
      fermat_fixture_clause(lines, [0 - x, 0 - y, carry, 0 - next_carry])
      fermat_fixture_clause(lines, [0 - x, y, next_carry])
      fermat_fixture_clause(lines, [0 - x, 0 - carry, next_carry])
    bit += 1
  "p cnf 19 [lines.size]\n" + lines.join("\n") + "\n"

describe "Wassat Fermat circuit shortcut" ->
  it "derives the fixed constant from DIMACS structure" ->
    formula = wassat_parse_cnf_native(fermat_fixture_cnf)
    pm = i64[4]
    ok = wassat_fermat_scan(
      formula["flat_lits"], formula["flat_offs"], formula["flat_lens"],
      formula["nvars"], formula["flat_ncl"], pm
    )
    expect(ok).to eq(1)
    expect(pm[0]).to eq(4)
    expect(pm[1]).to eq(15)

  it "factors, propagates, and verifies a complete model" ->
    formula = wassat_parse_cnf_native(fermat_fixture_cnf)
    model = wassat_fermat_model(formula)
    expect(model.empty?).to eq(false)
    expect(wassat_model_satisfies?(formula, model)).to eq(true)
    # Little-endian a=4 and b=1.
    expect(model.slice(0, 8)).to eq([-1, -2, 3, -4, 5, -6, -7, -8])

  it "falls through on a malformed fixed-result parity table" ->
    text = fermat_fixture_cnf.replace(
      "10 -14 17 0", "10 14 17 0"
    )
    formula = wassat_parse_cnf_native(text)
    expect(wassat_fermat_model(formula).empty?).to eq(true)

  it "falls through on a malformed no-borrow carry table" ->
    text = fermat_fixture_cnf.replace(
      "9 -13 -17 0", "9 -13 17 0"
    )
    formula = wassat_parse_cnf_native(text)
    expect(wassat_fermat_model(formula).empty?).to eq(true)

  it "falls through when the structurally recovered target is prime" ->
    formula = wassat_parse_cnf_native(fermat_fixture_cnf(13))
    pm = i64[4]
    ok = wassat_fermat_scan(
      formula["flat_lits"], formula["flat_offs"], formula["flat_lens"],
      formula["nvars"], formula["flat_ncl"], pm
    )
    expect(ok).to eq(1)
    expect(pm[1]).to eq(13)
    expect(wassat_fermat_model(formula).empty?).to eq(true)

  it "falls through when the leading primary-word contract is changed" ->
    text = fermat_fixture_cnf.replace(
      "-5 -6 -7 -8 0", "-5 -6 -7 8 0"
    )
    formula = wassat_parse_cnf_native(text)
    expect(wassat_fermat_model(formula).empty?).to eq(true)

  it "returns a verified SAT model in proof mode without leaving an artifact" ->
    bin = env("WASSAT_TEST_BIN")
    expect(bin == nil).to eq(false)
    input = "/tmp/wassat-fermat-proof-mode.cnf"
    proof = "/tmp/wassat-fermat-proof-mode.drat"
    output = "/tmp/wassat-fermat-proof-mode.out"
    expect(write_file(input, fermat_fixture_cnf)).to eq(true)
    z = ccall("__w_unlink", proof)
    cmd = "(" + bin + " " + input + " --drat " + proof
    cmd += " > " + output + " 2>&1); test $? -eq 10"
    expect(system(cmd)).to eq(true)
    text = read_file(output)
    expect(text.include?("s SATISFIABLE")).to eq(true)
    expect(text.include?(
      "c mode: proof (verified Fermat circuit model)"
    )).to eq(true)
    expect(file?(proof)).to eq(false)

spec_summary
