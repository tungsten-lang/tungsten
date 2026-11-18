# spec: compiled -- exercises the native CLI subprocess and atomic proof files
use spec
use ../lib/circuit_cone_search
use circuit_cone_php_fixture
use ../../tungsten-wrat/lib/wrat

-> cone_cli_binary
  binary = env("WASSAT_TEST_BIN")
  binary == nil || binary == "" ? "bits/tungsten-wassat/bin/wassat" : binary

-> cone_cli_exits(command, status)
  system("(" + command + "); test $? -eq [status]")

-> cone_cli_text(formula)
  text = "p cnf [formula["nvars"]] [formula["flat_ncl"]]\n"
  wassat_formula_clauses(formula).each -> (row) text += row.join(" ") + " 0\n"
  text

-> cone_cli_model(text, nv)
  model = i64[nv]
  text.split("\n").each -> (line)
    if line.starts_with?("v ")
      tokens = wassat_tokenize(line)
      i = 1
      while i < tokens.size
        lit = tokens[i].to_i
        model[lit.abs - 1] = lit if lit != 0 && lit.abs <= nv
        i += 1
  model

describe "Comparison-cone CLI contracts" ->
  it "preserves SAT models and removes a stale proof destination" ->
    f = cone_fixture_flat(cone_rare_rows, 66)
    input = "/tmp/wassat-cone-cli-sat.cnf"; proof = "/tmp/wassat-cone-cli-sat.drat"
    output = "/tmp/wassat-cone-cli-sat.out"
    expect(write_file(input, cone_cli_text(f))).to eq(true)
    expect(write_file(proof, "stale invalid proof\n")).to eq(true)
    command = "WASSAT_CIRCUIT_CONES=1 " + cone_cli_binary + " " + input + " --drat " + proof
    expect(cone_cli_exits(command + " > " + output + " 2>&1", 10)).to eq(true)
    expect(wassat_model_satisfies?(f, cone_cli_model(read_file(output), 66))).to eq(true)
    expect(read_file(proof) == nil).to eq(true)

  it "preserves DRAT stdout and dual hinted-proof output" ->
    f = cone_fixture_flat(cone_fixture_rows(3), 15)
    text = cone_cli_text(f)
    input = "/tmp/wassat-cone-cli-unsat.cnf"
    output = "/tmp/wassat-cone-cli-unsat.stdout"; err = "/tmp/wassat-cone-cli-unsat.stderr"
    expect(write_file(input, text)).to eq(true)
    command = "WASSAT_CIRCUIT_CONES=1 " + cone_cli_binary + " " + input
    expect(cone_cli_exits(command + " --drat - > " + output + " 2> " + err, 20)).to eq(true)
    expect(wrat_verify(text, read_file(output))["verified"]).to eq(true)
    hinted = "/tmp/wassat-cone-cli-dual.wrat"; drat = "/tmp/wassat-cone-cli-dual.drat"
    expect(cone_cli_exits(command + " --proof " + hinted + " --drat " + drat + " > " + output + " 2>&1", 20)).to eq(true)
    expect(wrat_verify(text, read_file(hinted))["verified"]).to eq(true)
    expect(wrat_verify(text, read_file(drat))["verified"]).to eq(true)

  it "honors the aggregate CLI cap and leaves no partial certificate" ->
    f = cone_php_circuit[0]
    input = "/tmp/wassat-cone-cli-cap.cnf"; proof = "/tmp/wassat-cone-cli-cap.drat"
    output = "/tmp/wassat-cone-cli-cap.out"
    expect(write_file(input, cone_cli_text(f))).to eq(true)
    command = "env -u WASSAT_CIRCUIT_CONES WASSAT_PROFILE=1 " + cone_cli_binary + " " + input
    expect(write_file(proof, "stale invalid proof\n")).to eq(true)
    expect(cone_cli_exits(command + " --drat " + proof + " --conflicts 1 > " + output + " 2>&1", 0)).to eq(true)
    result = read_file(output)
    expect(result.index("s UNKNOWN") != nil).to eq(true)
    expect(result.index("c conflicts: 1,") != nil).to eq(true)
    # Automatic admission is suspended while cumulative query storage is
    # given a bounded lifetime. Explicit research opt-in keeps the lane live.
    expect(result.index("cli.comparison_cones") == nil).to eq(true)
    enabled = "WASSAT_CIRCUIT_CONES=1 WASSAT_PROFILE=1 " + cone_cli_binary + " " + input
    expect(cone_cli_exits(enabled + " --drat " + proof + " --conflicts 1 > " + output + " 2>&1", 0)).to eq(true)
    result = read_file(output)
    expect(result.index("cli.comparison_cones") != nil).to eq(true)
    expect(result.index("c conflicts: 1,") != nil).to eq(true)
    expect(read_file(proof) == nil).to eq(true)
    disabled = "WASSAT_CIRCUIT_CONES=0 WASSAT_PROFILE=1 " + cone_cli_binary + " " + input
    expect(cone_cli_exits(disabled + " --drat " + proof + " --conflicts 1 > " + output + " 2>&1", 0)).to eq(true)
    expect(read_file(output).index("cli.comparison_cones") == nil).to eq(true)
    expect(read_file(proof) == nil).to eq(true)
    expect(cone_cli_exits(enabled + " --drat " + proof + " --conflicts 1 --sequential > " + output + " 2>&1", 0)).to eq(true)
    expect(read_file(output).index("cli.comparison_cones") == nil).to eq(true)
    expect(read_file(proof) == nil).to eq(true)

spec_summary
