# Portfolio specs (Phase 3, --proof half). Correctness only — NEVER which
# arm wins. Runs the compiled binary via system(); the Process externs are
# compiled-only.

use spec
use wassat
use ../../tungsten-wrat/lib/wrat

PORT_BIN = "bits/tungsten-wassat/bin/wassat"

-> port_run(cnf_path, proof_path, dir)
  z = system("rm -rf " + dir)
  cmd = "cd /Users/erik/tungsten && " + PORT_BIN + " portfolio " + cnf_path
  cmd = cmd + " --proof " + proof_path unless proof_path == nil
  cmd = cmd + " --dir " + dir + " > " + dir + ".out 2>&1"
  z = system("mkdir -p " + dir)
  system(cmd)

describe "Wassat portfolio (process race)" ->

  context "UNSAT: the spliced certificate is the answer" ->
    it "wins dubois25 and the splice verifies independently" ->
      ok = port_run("/tmp/satlib/structclean/dubois/dubois25.cnf", "/tmp/pspec_dub.wrat", "/tmp/pspec_race1")
      expect(ok).to eq(true)
      out = read_file("/tmp/pspec_race1.out")
      expect(out.index("s UNSATISFIABLE") != nil).to eq(true)
      cnf = read_file("/tmp/satlib/structclean/dubois/dubois25.cnf")
      proof = read_file("/tmp/pspec_dub.wrat")
      expect(proof == nil).to eq(false)
      check = wrat_verify(cnf, proof)
      expect(check["verified"]).to eq(true)

    it "keeps racing when the SLS arm retires without an answer" ->
      # SLS can never answer UNSAT; its arm exhausts and exits non-decisive,
      # exercising the arm-failure path while CDCL still proves the result.
      out = read_file("/tmp/pspec_race1.out")
      expect(out.index("s UNSATISFIABLE") != nil).to eq(true)

  context "SAT: the model is reconstructed and honest" ->
    it "answers bmc-ibm-2 with a model satisfying the ORIGINAL formula" ->
      ok = port_run("/tmp/satlib/structclean/bmc/bmc-ibm-2.cnf", nil, "/tmp/pspec_race2")
      expect(ok).to eq(true)
      out = read_file("/tmp/pspec_race2.out")
      expect(out.index("s SATISFIABLE") != nil).to eq(true)
      model = []
      out.split("\n").each -> (line)
        if line.starts_with?("v ")
          wassat_tokenize(line.slice(2, line.size - 2)).each -> (t)
            v = t.to_i
            model.push(v) unless t == "0"
      f = wassat_parse_cnf(read_file("/tmp/satlib/structclean/bmc/bmc-ibm-2.cnf"))
      expect(wassat_model_satisfies?(f, model)).to eq(true)

  context "threaded --fast race" ->
    it "answers UNSAT through the thread race with sharing stats" ->
      z = system("rm -f /tmp/pspec_fast1.out")
      ok = system("cd /Users/erik/tungsten && " + PORT_BIN + " portfolio /tmp/satlib/clean/uuf100-430/uuf100-01.cnf --fast --threads 3 > /tmp/pspec_fast1.out 2>&1")
      expect(ok).to eq(true)
      out = read_file("/tmp/pspec_fast1.out")
      expect(out.index("s UNSATISFIABLE") != nil).to eq(true)
      expect(out.index("exported=") != nil).to eq(true)

    it "answers SAT with a model verified against the original formula" ->
      z = system("rm -f /tmp/pspec_fast2.out")
      ok = system("cd /Users/erik/tungsten && " + PORT_BIN + " portfolio /tmp/satlib/structclean/bmc/bmc-ibm-2.cnf --fast --threads 3 > /tmp/pspec_fast2.out 2>&1")
      expect(ok).to eq(true)
      out = read_file("/tmp/pspec_fast2.out")
      expect(out.index("s SATISFIABLE") != nil).to eq(true)
      model = []
      out.split("\n").each -> (line)
        if line.starts_with?("v ")
          wassat_tokenize(line.slice(2, line.size - 2)).each -> (t)
            v = t.to_i
            model.push(v) unless t == "0"
      f = wassat_parse_cnf(read_file("/tmp/satlib/structclean/bmc/bmc-ibm-2.cnf"))
      expect(wassat_model_satisfies?(f, model)).to eq(true)

    it "rejects --fast combined with --proof" ->
      rc = system("cd /Users/erik/tungsten && " + PORT_BIN + " portfolio /tmp/pspec_triv.cnf --fast --proof /tmp/x.wrat > /dev/null 2>&1")
      expect(rc).to eq(false)

  context "degenerate input" ->
    it "answers a preprocessing-refutable formula without spawning arms" ->
      z = system("printf 'p cnf 1 2\\n1 0\\n-1 0\\n' > /tmp/pspec_triv.cnf")
      ok = port_run("/tmp/pspec_triv.cnf", "/tmp/pspec_triv.wrat", "/tmp/pspec_race3")
      expect(ok).to eq(true)
      out = read_file("/tmp/pspec_race3.out")
      expect(out.index("s UNSATISFIABLE") != nil).to eq(true)
      expect(out.index("winner: preprocess") != nil).to eq(true)
      check = wrat_verify(read_file("/tmp/pspec_triv.cnf"), read_file("/tmp/pspec_triv.wrat"))
      expect(check["verified"]).to eq(true)

spec_summary
