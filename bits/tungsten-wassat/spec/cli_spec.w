use spec
use wassat

describe "Tungsten Wassat CLI" ->
  context "option validation" ->
    it "parses explicit non-negative search controls" ->
      options = wassat_cli_options(["problem.cnf", "--lookahead", "16", "--conflicts", "2500"])
      expect(options["lookahead"]).to eq(16)
      expect(options["conflicts"]).to eq(2500)

    it "rejects controls that could silently become unlimited" ->
      expect(-> () wassat_cli_options(["problem.cnf", "--conflicts", "oops"])).to raise_error
      expect(-> () wassat_cli_options(["problem.cnf", "--conflicts", "-1"])).to raise_error
      expect(-> () wassat_cli_options(["problem.cnf", "--conflicts"])).to raise_error
      expect(-> () wassat_cli_options(["problem.cnf", "--unknown", "1"])).to raise_error
      expect(-> () wassat_cli_options(["problem.cnf", "--lookahead", "2", "--lookahead", "3"])).to raise_error

    it "requires distinct certificate destinations" ->
      expect(-> () wassat_cli_options(["problem.cnf", "--proof", "same", "--drat", "same"])).to raise_error

  context "certificate destinations" ->
    it "leaves stdout available as a certificate destination" ->
      expect(wassat_prepare_output("-", "/tmp/input.cnf", "WRAT")).to eq(0)

    it "never permits a certificate to overwrite its input" ->
      expect(-> () wassat_prepare_output("/tmp/input.cnf", "/tmp/input.cnf", "WRAT")).to raise_error

    it "reports a missing input before DIMACS parsing" ->
      expect(-> () wassat_run_file_checked(["/tmp/wassat-file-that-does-not-exist-9e31"])).to raise_error

spec_summary
