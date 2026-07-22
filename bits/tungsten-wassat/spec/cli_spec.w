use spec
use wassat

describe "Tungsten Wassat CLI" ->
  context "the mode contract" ->
    it "refuses to run without an explicit mode" ->
      message = ""
      begin
        wassat_cli_options(["problem.cnf"])
      rescue e
        message = "[e]"
      expect(message.index("choose a mode") != nil).to eq(true)

    it "accepts --proof and selects proof mode" ->
      options = wassat_cli_options(["problem.cnf", "--proof", "out.wrat"])
      expect(options["proof"]).to eq("out.wrat")
      expect(wassat_mode_of(options)).to eq("proof")

    it "accepts --fast and selects fast mode" ->
      options = wassat_cli_options(["problem.cnf", "--fast"])
      expect(options["fast"]).to eq(true)
      expect(wassat_mode_of(options)).to eq("fast")

    it "treats --drat as proof mode" ->
      options = wassat_cli_options(["problem.cnf", "--drat", "out.drat"])
      expect(wassat_mode_of(options)).to eq("proof")

    it "rejects --fast combined with certificate output" ->
      expect(-> () wassat_cli_options(["problem.cnf", "--fast", "--proof", "p"])).to raise_error
      expect(-> () wassat_cli_options(["problem.cnf", "--fast", "--drat", "d"])).to raise_error
      expect(-> () wassat_cli_options(["problem.cnf", "--fast", "--lrat", "l"])).to raise_error

    it "treats --lrat as proof mode and as exclusive with --proof" ->
      options = wassat_cli_options(["problem.cnf", "--lrat", "out.lrat"])
      expect(wassat_mode_of(options)).to eq("proof")
      expect(-> () wassat_cli_options(["problem.cnf", "--proof", "a", "--lrat", "b"])).to raise_error

    it "accepts flags in any position around the input path" ->
      options = wassat_cli_options(["--fast", "problem.cnf"])
      expect(options["input"]).to eq("problem.cnf")
      expect(options["fast"]).to eq(true)

    it "rejects a second positional input" ->
      expect(-> () wassat_cli_options(["a.cnf", "b.cnf", "--fast"])).to raise_error

  context "option validation" ->
    it "parses explicit non-negative search controls" ->
      options = wassat_cli_options(["problem.cnf", "--fast", "--lookahead", "16", "--conflicts", "2500"])
      expect(options["lookahead"]).to eq(16)
      expect(options["conflicts"]).to eq(2500)

    it "rejects controls that could silently become unlimited" ->
      expect(-> () wassat_cli_options(["problem.cnf", "--fast", "--conflicts", "oops"])).to raise_error
      expect(-> () wassat_cli_options(["problem.cnf", "--fast", "--conflicts", "-1"])).to raise_error
      expect(-> () wassat_cli_options(["problem.cnf", "--fast", "--conflicts"])).to raise_error
      expect(-> () wassat_cli_options(["problem.cnf", "--fast", "--unknown", "1"])).to raise_error
      expect(-> () wassat_cli_options(["problem.cnf", "--fast", "--lookahead", "2", "--lookahead", "3"])).to raise_error

    it "requires distinct certificate destinations" ->
      expect(-> () wassat_cli_options(["problem.cnf", "--proof", "same", "--drat", "same"])).to raise_error

  context "certificate destinations" ->
    it "leaves stdout available as a certificate destination" ->
      expect(wassat_prepare_output("-", "/tmp/input.cnf", "WRAT")).to eq(0)

    it "never permits a certificate to overwrite its input" ->
      expect(-> () wassat_prepare_output("/tmp/input.cnf", "/tmp/input.cnf", "WRAT")).to raise_error

    it "reports a missing input before DIMACS parsing" ->
      expect(-> () wassat_run_file_checked(["/tmp/wassat-file-that-does-not-exist-9e31", "--fast"])).to raise_error

spec_summary
