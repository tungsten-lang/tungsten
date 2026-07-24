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
      options = wassat_cli_options(["problem.cnf", "--fast", "--conflicts", "2500"])
      expect(options["conflicts"]).to eq(2500)

    it "rejects controls that could silently become unlimited" ->
      expect(-> () wassat_cli_options(["problem.cnf", "--fast", "--conflicts", "oops"])).to raise_error
      expect(-> () wassat_cli_options(["problem.cnf", "--fast", "--conflicts", "-1"])).to raise_error
      expect(-> () wassat_cli_options(["problem.cnf", "--fast", "--conflicts"])).to raise_error
      expect(-> () wassat_cli_options(["problem.cnf", "--fast", "--unknown", "1"])).to raise_error
      expect(-> () wassat_cli_options(["problem.cnf", "--fast", "--lookahead", "2"])).to raise_error

    it "rejects overflowing limits instead of wrapping them" ->
      expect(-> () wassat_cli_options(["problem.cnf", "--fast", "--conflicts", "999999999999999999999"])).to raise_error

    it "requires distinct certificate destinations" ->
      expect(-> () wassat_cli_options(["problem.cnf", "--proof", "same", "--drat", "same"])).to raise_error

    it "selects branching techniques from formula shape" ->
      random_clauses = []
      i = 0
      while i < 100
        a = i % 30 + 1
        b = (i * 7) % 30 + 1
        c = (i * 13) % 30 + 1
        random_clauses.push([a, 0 - b, c])
        i += 1
      random_policy = WassatConfig.new(30, random_clauses)
      tiny_policy = WassatConfig.new(3, [[1, 2], [-1, 3]])
      expect(random_policy.lookahead_candidates).to eq(16)
      expect(tiny_policy.lookahead_candidates).to eq(0)

  context "certificate destinations" ->
    it "leaves stdout available as a certificate destination" ->
      expect(wassat_prepare_output("-", "/tmp/input.cnf", "WRAT")).to eq(0)

    it "never permits a certificate to overwrite its input" ->
      expect(-> () wassat_prepare_output("/tmp/input.cnf", "/tmp/input.cnf", "WRAT")).to raise_error

    it "reports a missing input before DIMACS parsing" ->
      expect(-> () wassat_run_file_checked(["/tmp/wassat-file-that-does-not-exist-9e31", "--fast"])).to raise_error

    it "atomically removes stale certificates on SAT and malformed input" ->
      bin = env("WASSAT_TEST_BIN")
      bin = "bits/tungsten-wassat/bin/wassat" if bin == nil || bin == ""
      sat_cnf = "/tmp/wassat-cli-atomic-sat.cnf"
      bad_cnf = "/tmp/wassat-cli-atomic-bad.cnf"
      proof = "/tmp/wassat-cli-atomic.wrat"
      z = write_file(sat_cnf, "p cnf 1 1\n1 0\n")
      z = write_file(proof, "stale\n")
      ok = system(bin + " " + sat_cnf + " --proof " + proof + " > /tmp/wassat-cli-atomic-sat.out 2>&1")
      expect(ok).to eq(true)
      expect(read_file(proof)).to eq(nil)

      z = write_file(bad_cnf, "p cnf2 1\n1 0\n")
      z = write_file(proof, "stale again\n")
      ok = system(bin + " " + bad_cnf + " --proof " + proof + " > /tmp/wassat-cli-atomic-bad.out 2>&1")
      expect(ok).to eq(false)
      expect(read_file(proof)).to eq(nil)

    it "rejects hardlink aliases without damaging the input" ->
      bin = env("WASSAT_TEST_BIN")
      bin = "bits/tungsten-wassat/bin/wassat" if bin == nil || bin == ""
      input = "/tmp/wassat-cli-alias-input.cnf"
      alias_path = "/tmp/wassat-cli-alias-proof.wrat"
      body = "p cnf 1 1\n1 0\n"
      z = write_file(input, body)
      z = ccall("__w_unlink", alias_path)
      expect(system("ln " + input + " " + alias_path)).to eq(true)
      ok = system(bin + " " + input + " --proof " + alias_path + " > /tmp/wassat-cli-alias.out 2>&1")
      expect(ok).to eq(false)
      expect(read_file(input)).to eq(body)
      expect(read_file(alias_path)).to eq(body)

  context "SLS option contract" ->
    it "rejects GPU-only controls on CPU and honors a zero GPU flip budget" ->
      bin = env("WASSAT_TEST_BIN")
      bin = "bits/tungsten-wassat/bin/wassat" if bin == nil || bin == ""
      input = "/tmp/wassat-cli-sls.cnf"
      z = write_file(input, "p cnf 2 1\n1 2 0\n")
      ok = system(bin + " sls " + input + " --flips 1 --walkers 8 > /tmp/wassat-cli-sls-bad.out 2>&1")
      expect(ok).to eq(false)
      ok = system(bin + " sls " + input + " --gpu --flips 0 --walkers 8 --noise 48 > /tmp/wassat-cli-sls-zero.out 2>&1")
      expect(ok).to eq(true)
      out = read_file("/tmp/wassat-cli-sls-zero.out")
      expect(out.index("flips=0") != nil).to eq(true)

spec_summary
