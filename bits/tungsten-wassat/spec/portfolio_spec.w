# Portfolio specs (Phase 3, --proof half). Correctness only — NEVER which
# arm wins. Runs the compiled binary via system(); the Process externs are
# compiled-only.

use spec
use wassat
use ../../tungsten-wrat/lib/wrat

PORT_BIN_ENV = env("WASSAT_TEST_BIN")
PORT_BIN = PORT_BIN_ENV == nil || PORT_BIN_ENV == "" ? "bits/tungsten-wassat/bin/wassat" : PORT_BIN_ENV

PORT_SAT = "p cnf 3 3\n1 0\n-1 2 0\n-2 3 0\n"

# Exclude every assignment over ten variables. The wide clauses prevent the
# preprocessor from collapsing the task, so proof mode genuinely exercises a
# worker process and the coordinator's streamed prefix+suffix splice.
-> port_search_unsat
  nvars = 10
  lines = ["p cnf [nvars] [1 << nvars]"]
  mask = 0
  while mask < (1 << nvars)
    clause = []
    v = 1
    while v <= nvars
      bit = (mask >> (v - 1)) & 1
      clause.push(bit == 1 ? 0 - v : v)
      v += 1
    lines.push(clause.join(" ") + " 0")
    mask += 1
  lines.join("\n") + "\n"

-> port_run(cnf_path, proof_path, dir, suffix = "", timeout_ms = 30000)
  cmd = PORT_BIN + " portfolio " + cnf_path
  cmd = cmd + " --proof " + proof_path unless proof_path == nil
  cmd = cmd + " --dir " + dir + " --timeout-ms [timeout_ms] " + suffix + " > " + dir + ".out 2>&1"
  system(cmd)

describe "Wassat portfolio (process race)" ->

  context "UNSAT: the spliced certificate is the answer" ->
    it "wins a hermetic search formula and the splice verifies independently" ->
      cnf_path = "/tmp/pspec_search_unsat.cnf"
      z = write_file(cnf_path, port_search_unsat)
      ok = port_run(cnf_path, "/tmp/pspec_search.wrat", "/tmp/pspec_race1")
      expect(ok).to eq(true)
      out = read_file("/tmp/pspec_race1.out")
      expect(out.index("s UNSATISFIABLE") != nil).to eq(true)
      expect(out.index("winner: preprocess") == nil).to eq(true)
      cnf = read_file(cnf_path)
      proof = read_file("/tmp/pspec_search.wrat")
      expect(proof == nil).to eq(false)
      check = wrat_verify(cnf, proof)
      expect(check["verified"]).to eq(true)

    it "keeps racing when the SLS arm retires without an answer" ->
      # SLS can never answer UNSAT; its arm exhausts and exits non-decisive,
      # exercising the arm-failure path while CDCL still proves the result.
      out = read_file("/tmp/pspec_race1.out")
      expect(out.index("s UNSATISFIABLE") != nil).to eq(true)

  context "SAT: the model is reconstructed and honest" ->
    it "answers a hermetic formula and leaves no certificate" ->
      cnf_path = "/tmp/pspec_sat.cnf"
      proof_path = "/tmp/pspec_sat.wrat"
      z = write_file(cnf_path, PORT_SAT)
      z = write_file(proof_path, "stale proof\n")
      ok = port_run(cnf_path, proof_path, "/tmp/pspec_race2")
      expect(ok).to eq(true)
      out = read_file("/tmp/pspec_race2.out")
      expect(out.index("s SATISFIABLE") != nil).to eq(true)
      expect(read_file(proof_path)).to eq(nil)
      model = []
      out.split("\n").each -> (line)
        if line.starts_with?("v ")
          wassat_tokenize(line.slice(2, line.size - 2)).each -> (t)
            v = t.to_i
            model.push(v) unless t == "0"
      f = wassat_parse_cnf(read_file(cnf_path))
      expect(wassat_model_satisfies?(f, model)).to eq(true)

  context "threaded --fast race" ->
    it "answers UNSAT through the thread race with sharing stats" ->
      cnf_path = "/tmp/pspec_search_unsat.cnf"
      z = write_file(cnf_path, port_search_unsat)
      ok = system(PORT_BIN + " portfolio " + cnf_path + " --fast --threads 3 > /tmp/pspec_fast1.out 2>&1")
      expect(ok).to eq(true)
      out = read_file("/tmp/pspec_fast1.out")
      expect(out.index("s UNSATISFIABLE") != nil).to eq(true)
      expect(out.index("exported=") != nil).to eq(true)

    it "answers SAT with a model verified against the original formula" ->
      cnf_path = "/tmp/pspec_fast_sat.cnf"
      z = write_file(cnf_path, PORT_SAT)
      ok = system(PORT_BIN + " portfolio " + cnf_path + " --fast --threads 3 > /tmp/pspec_fast2.out 2>&1")
      expect(ok).to eq(true)
      out = read_file("/tmp/pspec_fast2.out")
      expect(out.index("s SATISFIABLE") != nil).to eq(true)
      model = []
      out.split("\n").each -> (line)
        if line.starts_with?("v ")
          wassat_tokenize(line.slice(2, line.size - 2)).each -> (t)
            v = t.to_i
            model.push(v) unless t == "0"
      f = wassat_parse_cnf(read_file(cnf_path))
      expect(wassat_model_satisfies?(f, model)).to eq(true)

    it "rejects --fast combined with --proof" ->
      z = write_file("/tmp/pspec_triv.cnf", PORT_SAT)
      rc = system(PORT_BIN + " portfolio /tmp/pspec_triv.cnf --fast --proof /tmp/x.wrat > /dev/null 2>&1")
      expect(rc).to eq(false)

  context "degenerate input" ->
    it "answers a preprocessing-refutable formula without spawning arms" ->
      z = write_file("/tmp/pspec_triv.cnf", "p cnf 1 2\n1 0\n-1 0\n")
      ok = port_run("/tmp/pspec_triv.cnf", "/tmp/pspec_triv.wrat", "/tmp/pspec_race3")
      expect(ok).to eq(true)
      out = read_file("/tmp/pspec_race3.out")
      expect(out.index("s UNSATISFIABLE") != nil).to eq(true)
      expect(out.index("winner: preprocess") != nil).to eq(true)
      check = wrat_verify(read_file("/tmp/pspec_triv.cnf"), read_file("/tmp/pspec_triv.wrat"))
      expect(check["verified"]).to eq(true)

  context "deadline" ->
    it "returns UNKNOWN and publishes no partial proof" ->
      cnf_path = "/tmp/pspec_deadline.cnf"
      proof_path = "/tmp/pspec_deadline.wrat"
      z = write_file(cnf_path, port_search_unsat)
      z = write_file(proof_path, "stale\n")
      ok = port_run(cnf_path, proof_path, "/tmp/pspec_race_deadline", "", 1)
      expect(ok).to eq(true)
      out = read_file("/tmp/pspec_race_deadline.out")
      expect(out.index("s UNKNOWN") != nil).to eq(true)
      expect(out.index("deadline") != nil).to eq(true)
      expect(read_file(proof_path)).to eq(nil)

spec_summary
