use spec
use wassat
use ../../tungsten-wrat/lib/wrat

# Pigeonhole PHP(p,h) as DIMACS text: p pigeons, h holes, UNSAT when p > h.
# Compact and deterministic, so the compiled smoke tests stay hermetic.
-> cli_php_cnf(pigeons, holes)
  clauses = []
  i = 0
  while i < pigeons
    row = []
    j = 0
    while j < holes
      row.push(i * holes + j + 1)
      j += 1
    clauses.push(row)
    i += 1
  j = 0
  while j < holes
    a = 0
    while a < pigeons
      b = a + 1
      while b < pigeons
        clauses.push([0 - (a * holes + j + 1), 0 - (b * holes + j + 1)])
        b += 1
      a += 1
    j += 1
  lines = ["p cnf [pigeons * holes] [clauses.size]"]
  clauses.each -> (c)
    lines.push(c.join(" ") + " 0")
  lines.join("\n") + "\n"

-> cli_test_bin
  bin = env("WASSAT_TEST_BIN")
  bin == nil || bin == "" ? "bits/tungsten-wassat/bin/wassat" : bin

# SAT Competition exit codes: 10 = SATISFIABLE, 20 = UNSATISFIABLE, 0 =
# anything else. `system` collapses the wait status to "was it zero", which
# cannot tell 10 from 20 from a crash, so the expected code is asserted by
# the shell that ran the command -- a stricter check than the old
# `system(...) == true`, and the contract every competition harness reads.
-> cli_exits(cmd, code)
  system("(" + cmd + "); test $? -eq [code]")

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

    it "allocates each stage only from the remaining aggregate conflicts" ->
      expect(wassat_stage_conflict_cap(0, 19, 1000)).to eq(1000)
      expect(wassat_stage_conflict_cap(25, 19, 1000)).to eq(6)
      expect(wassat_stage_conflict_cap(25, 25, 1000)).to eq(0)
      expect(wassat_stage_conflict_cap(25, 31, 1000)).to eq(0)
      expect(wassat_stage_conflict_cap(2500, 19, 1000)).to eq(1000)

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
      medium_random_policy = WassatConfig.new(100, random_clauses)
      tiny_policy = WassatConfig.new(3, [[1, 2], [-1, 3]])
      expect(random_policy.lookahead_candidates).to eq(16)
      expect(medium_random_policy.lookahead_candidates).to eq(0)
      expect(tiny_policy.lookahead_candidates).to eq(0)
      expect(random_policy.continue_scout?).to eq(true)
      expect(medium_random_policy.continue_scout?).to eq(false)

    it "selects routing and staged fallback from formula shape" ->
      dense = []
      i = 0
      while i < 1065
        dense.push([i % 250 + 1, 0 - ((i * 7) % 250 + 1), (i * 13) % 250 + 1])
        i += 1
      dense_policy = WassatConfig.new(250, dense)
      expect(dense_policy.race_route?).to eq(true)
      expect(dense_policy.stage_pre_after_scout?).to eq(true)

      compact_choice = []
      i = 0
      while i < 90
        compact_choice.push([i % 42 + 1, 0 - ((i * 5) % 42 + 1)])
        i += 1
      while i < 100
        compact_choice.push([1, 2, 3, 4, 5, 6, 7])
        i += 1
      expect(WassatConfig.new(42, compact_choice).race_route?).to eq(false)
      expect(WassatConfig.new(0, []).race_route?).to eq(false)

    it "bounds discarded scout work on million-clause raw kernels" ->
      counts = i64[8]
      below = WassatConfig.new(1, [])
      below.adopt_counts(999999, counts)
      large = WassatConfig.new(1, [])
      large.adopt_counts(1000000, counts)
      expect(below.probe_conflicts(true)).to eq(2000)
      expect(large.probe_conflicts(true)).to eq(512)
      expect(large.probe_conflicts(false)).to eq(4000)

    it "bypasses discarded scout work only on dense low-variable ternary tasks" ->
      counts = i64[8]
      counts[4] = 240000
      dense = WassatConfig.new(289, [])
      dense.adopt_counts(242594, counts)
      expect(dense.short_dense_ternary_scout?).to eq(true)
      expect(dense.use_lucky).to eq(false)
      expect(dense.probe_conflicts(true)).to eq(128)
      expect(dense.probe_conflicts(false)).to eq(4000)

      wide = WassatConfig.new(513, [])
      wide.adopt_counts(242594, counts)
      expect(wide.short_dense_ternary_scout?).to eq(false)
      expect(wide.use_lucky).to eq(true)
      expect(wide.probe_conflicts(true)).to eq(2000)

    it "keeps measured-losing vivification out of the automatic policy" ->
      clauses = []
      i = 0
      while i < 1000
        clauses.push([i % 100 + 1, 0 - ((i * 7) % 100 + 1), (i * 13) % 100 + 1])
        i += 1
      expect(WassatConfig.new(100, clauses).use_vivification).to eq(false)

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
      ok = cli_exits(bin + " " + sat_cnf + " --proof " + proof + " > /tmp/wassat-cli-atomic-sat.out 2>&1", 10)
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
      File.unlink(alias_path) if File.exist?(alias_path)
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
      # a flipless GPU run answers UNKNOWN, which is exit 0 -- local search
      # can never answer UNSAT, so 20 is unreachable here
      ok = cli_exits(bin + " sls " + input + " --gpu --flips 0 --walkers 8 --noise 48 > /tmp/wassat-cli-sls-zero.out 2>&1", 0)
      expect(ok).to eq(true)
      out = read_file("/tmp/wassat-cli-sls-zero.out")
      expect(out.index("flips=0") != nil).to eq(true)
      # ... and a model from the CPU walker is exit 10 like every other engine's
      ok = cli_exits(bin + " sls " + input + " --flips 100000 > /tmp/wassat-cli-sls-sat.out 2>&1", 10)
      expect(ok).to eq(true)
      expect(read_file("/tmp/wassat-cli-sls-sat.out").index("s SATISFIABLE") != nil).to eq(true)

  # End-to-end smoke tests over the compiled binary: the native parser,
  # streamed proofs, and exit codes only exist in a compiled program.
  context "compiled CLI smoke" ->
    it "prints version and discoverable help" ->
      bin = cli_test_bin
      expect(system(bin + " version > /tmp/wassat-cli-ver.out 2>&1")).to eq(true)
      expect(read_file("/tmp/wassat-cli-ver.out").index("Tungsten Wassat") != nil).to eq(true)
      expect(system(bin + " help > /tmp/wassat-cli-help.out 2>&1")).to eq(true)
      help = read_file("/tmp/wassat-cli-help.out")
      expect(help.index("USAGE") != nil).to eq(true)
      expect(help.index("portfolio") != nil).to eq(true)
      expect(help.index("--conflicts") != nil).to eq(true)

    it "prints a model line for a satisfiable instance" ->
      bin = cli_test_bin
      sat = "/tmp/wassat-cli-smoke-sat.cnf"
      z = write_file(sat, "p cnf 3 2\n1 -2 0\n2 3 0\n")
      expect(z).to eq(true)
      expect(cli_exits(bin + " " + sat + " --fast > /tmp/wassat-cli-smoke-sat.out 2>&1", 10)).to eq(true)
      out = read_file("/tmp/wassat-cli-smoke-sat.out")
      expect(out.index("s SATISFIABLE") != nil).to eq(true)
      expect(out.index("v ") != nil).to eq(true)

    it "keeps every large-model value line within the competition limit" ->
      bin = cli_test_bin
      sat = "/tmp/wassat-cli-large-model.cnf"
      clauses = []
      v = 1
      while v <= 4000
        clauses.push("[v] 0")
        v += 1
      text = "p cnf 4000 4000\n" + clauses.join("\n") + "\n"
      expect(write_file(sat, text)).to eq(true)
      expect(cli_exits(bin + " " + sat + " --fast > /tmp/wassat-cli-large-model.out 2>&1", 10)).to eq(true)
      lines = read_file("/tmp/wassat-cli-large-model.out").split("\n")
      values = []
      lines.each -> (line)
        if line.starts_with?("v ")
          expect(line.size <= WASSAT_VALUE_LINE_MAX).to eq(true)
          values.push(line)
      expect(values.size > 1).to eq(true)
      expect(values[values.size - 1].ends_with?(" 0")).to eq(true)

    it "writes a WRAT certificate that the independent checker verifies" ->
      bin = cli_test_bin
      text = cli_php_cnf(4, 3)
      cnf = "/tmp/wassat-cli-smoke-unsat.cnf"
      proof = "/tmp/wassat-cli-smoke.wrat"
      expect(write_file(cnf, text)).to eq(true)
      expect(cli_exits(bin + " " + cnf + " --proof " + proof + " > /tmp/wassat-cli-smoke-unsat.out 2>&1", 20)).to eq(true)
      out = read_file("/tmp/wassat-cli-smoke-unsat.out")
      expect(out.index("s UNSATISFIABLE") != nil).to eq(true)
      check = wrat_verify(text, read_file(proof))
      expect(check["verified"]).to eq(true)

    it "writes a DRAT certificate that the independent checker verifies" ->
      bin = cli_test_bin
      text = cli_php_cnf(4, 3)
      cnf = "/tmp/wassat-cli-smoke-drat.cnf"
      proof = "/tmp/wassat-cli-smoke.drat"
      expect(write_file(cnf, text)).to eq(true)
      expect(cli_exits(bin + " " + cnf + " --drat " + proof + " > /tmp/wassat-cli-smoke-drat.out 2>&1", 20)).to eq(true)
      out = read_file("/tmp/wassat-cli-smoke-drat.out")
      expect(out.index("s UNSATISFIABLE") != nil).to eq(true)
      check = wrat_verify(text, read_file(proof))
      expect(check["verified"]).to eq(true)

    it "streams a proof to stdout with `--proof -`" ->
      bin = cli_test_bin
      text = cli_php_cnf(4, 3)
      cnf = "/tmp/wassat-cli-smoke-stdout.cnf"
      expect(write_file(cnf, text)).to eq(true)
      # verdict + comments go to stderr in quiet mode; the proof is on stdout
      expect(cli_exits(bin + " " + cnf + " --proof - > /tmp/wassat-cli-stdout.proof 2>/dev/null", 20)).to eq(true)
      proof_text = read_file("/tmp/wassat-cli-stdout.proof")
      expect(proof_text != nil && proof_text != "").to eq(true)
      check = wrat_verify(text, proof_text)
      expect(check["verified"]).to eq(true)

    it "reports malformed input as a clean error, not a crash" ->
      bin = cli_test_bin
      bad = "/tmp/wassat-cli-smoke-bad.cnf"
      expect(write_file(bad, "p cnf 1 5\nnot a clause\n")).to eq(true)
      expect(system(bin + " " + bad + " --fast > /tmp/wassat-cli-bad.out 2>&1")).to eq(false)
      out = read_file("/tmp/wassat-cli-bad.out")
      expect(out.index("c error") != nil).to eq(true)
      expect(out.index("s UNKNOWN") != nil).to eq(true)

  # Aggregate --conflicts cap: NO CDCL stage (scout probe, raw race, final
  # solve) may push the total past the requested budget. PHP(6,5) is decided
  # only after ~143 conflicts, so a small cap must return UNKNOWN with a
  # conflict count that never exceeds the cap. Disable the automatic
  # pigeonhole/coloring and exact-cover certificates here: this test is
  # specifically about aggregate CDCL accounting, while their own specs cover
  # those zero-conflict verdict paths.
  context "aggregate conflict budget" ->
    it "solves within an unlimited budget but stops at a small cap" ->
      bin = cli_test_bin
      text = cli_php_cnf(6, 5)
      cnf = "/tmp/wassat-cli-budget.cnf"
      expect(write_file(cnf, text)).to eq(true)

      expect(cli_exits("WASSAT_COLORING=0 WASSAT_COVERING=0 " + bin + " " + cnf + " --fast --conflicts 0 > /tmp/wassat-cli-budget0.out 2>&1", 20)).to eq(true)
      expect(read_file("/tmp/wassat-cli-budget0.out").index("s UNSATISFIABLE") != nil).to eq(true)

      # a bounded run that stops UNKNOWN is exit 0, not a verdict code
      expect(cli_exits("WASSAT_COLORING=0 WASSAT_COVERING=0 " + bin + " " + cnf + " --fast --conflicts 1 > /tmp/wassat-cli-budget1.out 2>&1", 0)).to eq(true)
      out1 = read_file("/tmp/wassat-cli-budget1.out")
      expect(out1.index("s UNKNOWN") != nil).to eq(true)
      # aggregate conflicts reported must not exceed the cap of 1
      expect(out1.index("c conflicts: 1,") != nil || out1.index("c conflicts: 0,") != nil).to eq(true)

      expect(cli_exits("WASSAT_COLORING=0 WASSAT_COVERING=0 " + bin + " " + cnf + " --fast --conflicts 2 > /tmp/wassat-cli-budget2.out 2>&1", 0)).to eq(true)
      out2 = read_file("/tmp/wassat-cli-budget2.out")
      expect(out2.index("s UNKNOWN") != nil).to eq(true)
      expect(out2.index("c conflicts: 3,") == nil).to eq(true)

spec_summary
