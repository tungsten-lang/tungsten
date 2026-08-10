# Portfolio specs (--proof half). Correctness only — NEVER which
# arm wins. Runs the compiled binary via system(); the Process externs are
# compiled-only.

use spec
use wassat
use ../../tungsten-wrat/lib/wrat

PORT_BIN_ENV = env("WASSAT_TEST_BIN")
PORT_BIN = PORT_BIN_ENV == nil || PORT_BIN_ENV == "" ? "bits/tungsten-wassat/bin/wassat" : PORT_BIN_ENV

PORT_SAT = "p cnf 3 3\n1 0\n-1 2 0\n-2 3 0\n"
PORT_SLS_UNSAT = "p cnf 2 4\n1 2 0\n1 -2 0\n-1 2 0\n-1 -2 0\n"

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

# SAT Competition exit codes: 10 = SATISFIABLE, 20 = UNSATISFIABLE, 0 =
# anything else. `system` collapses the wait status to "was it zero", which
# cannot tell 10 from 20 from a crash, so the code is round-tripped through
# the shell that ran the command.
-> port_exit_code(cmd)
  code_file = "/tmp/pspec_exit_code"
  z = system("(" + cmd + "); echo $? > " + code_file)
  text = read_file(code_file)
  text == nil ? 0 - 1 : text.strip.to_i

# Runs the portfolio over `cnf_path` and returns its exit code.
-> port_run(cnf_path, proof_path, dir, suffix = "", timeout_ms = 30000)
  cmd = PORT_BIN + " portfolio " + cnf_path
  cmd = cmd + " --proof " + proof_path unless proof_path == nil
  cmd = cmd + " --dir " + dir + " --timeout-ms [timeout_ms] " + suffix + " > " + dir + ".out 2>&1"
  port_exit_code(cmd)

# Small strict xorshift-circuit fixture. The production recognizer never sees
# these builders; they independently emit the same exact Tseitin contracts.
-> port_xs_gate(g, kind, a, b)
  o = g["next"]
  g["next"] = o + 1
  lines = g["lines"]
  if kind == 1
    lines.push("[0 - a] [0 - b] [0 - o] 0")
    lines.push("[0 - a] [b] [o] 0")
    lines.push("[a] [0 - b] [o] 0")
    lines.push("[a] [b] [0 - o] 0")
  elsif kind == 2
    lines.push("[0 - a] [0 - b] [o] 0")
    lines.push("[a] [0 - o] 0")
    lines.push("[b] [0 - o] 0")
  else
    lines.push("[a] [b] [0 - o] 0")
    lines.push("[0 - a] [o] 0")
    lines.push("[0 - b] [o] 0")
  o

-> port_xs_step(g, input)
  word = []
  input.each -> (v)
    word.push(v)
  old = []
  word.each -> (v)
    old.push(v)
  i = 13
  while i < 32
    word[i] = port_xs_gate(g, 1, old[i], old[i - 13])
    i += 1
  old = []
  word.each -> (v)
    old.push(v)
  i = 0
  while i < 15
    word[i] = port_xs_gate(g, 1, old[i], old[i + 17])
    i += 1
  old = []
  word.each -> (v)
    old.push(v)
  i = 5
  while i < 32
    word[i] = port_xs_gate(g, 1, old[i], old[i - 5])
    i += 1
  word

-> port_xs_add(g, a, b)
  out = []
  out.push(port_xs_gate(g, 1, a[0], b[0]))
  carry = port_xs_gate(g, 2, a[0], b[0])
  a_or_b = port_xs_gate(g, 3, a[0], b[0])
  i = 1
  while i < 32
    pair = port_xs_gate(g, 1, a[i], b[i])
    out.push(port_xs_gate(g, 1, carry, pair))
    both = port_xs_gate(g, 2, a[i], b[i])
    a_or_b = port_xs_gate(g, 3, a[i], b[i])
    carried = port_xs_gate(g, 2, carry, a_or_b)
    carry = port_xs_gate(g, 3, both, carried)
    i += 1
  out

-> port_xs_word_xor(g, a, b, wrong_wire = false)
  out = []
  i = 0
  while i < 32
    left = a[i]
    # Produces a valid, fully defined XOR circuit with unchanged gate counts,
    # but breaks one edge of the expected word-level dataflow.
    left = a[i + 1] if wrong_wire && i == 7
    out.push(port_xs_gate(g, 1, left, b[i]))
    i += 1
  out

# Two folds, ADD then XOR, plus the generator's final unused xorshift state.
# Input 5 maps to the independently calculated 0x141dbeaf.
-> port_xs_fixture(final_add, wrong_wire)
  g = { "next": 33, "lines": [] }
  input = []
  v = 1
  while v <= 32
    input.push(v)
    v += 1
  state = port_xs_step(g, input)
  accumulator = port_xs_add(g, input, state)
  state = port_xs_step(g, state)
  if final_add
    accumulator = port_xs_add(g, accumulator, state)
  else
    accumulator = port_xs_word_xor(g, accumulator, state, wrong_wire)
  unused = port_xs_step(g, state)
  target = 0x141dbeaf
  i = 0
  while i < 32
    bit = (target >> i) & 1
    g["lines"].push("[bit == 1 ? accumulator[i] : 0 - accumulator[i]] 0")
    i += 1
  nv = g["next"] - 1
  "p cnf [nv] [g["lines"].size]\n" + g["lines"].join("\n") + "\n"

describe "Wassat portfolio (process race)" ->

  context "UNSAT: the spliced certificate is the answer" ->
    it "wins a hermetic search formula and the splice verifies independently" ->
      cnf_path = "/tmp/pspec_search_unsat.cnf"
      z = write_file(cnf_path, port_search_unsat)
      ok = port_run(cnf_path, "/tmp/pspec_search.wrat", "/tmp/pspec_race1")
      expect(ok).to eq(20)
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
      expect(ok).to eq(10)
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
    it "returns before constructing a policy-disabled lucky solver" ->
      counts = i64[8]
      counts[4] = 199027
      config = WassatConfig.new(272, [])
      config.adopt_counts(200920, counts)
      expect(config.use_lucky).to eq(false)
      # Deliberately omit every flat-artifact array. Reaching from_flat_lucky
      # would fail; a clean return proves policy is checked before allocation.
      art = { "config": config }
      res = i64[280]
      stop = i64[4]
      expect(wassat_lucky_arm_body(272, art, res, 0, stop)).to eq(0)
      expect(res[0]).to eq(0)

    it "keeps the bounded dense SLS specialist just above the generic cap" ->
      divs = {
        "nvars": 862, "flat_ncl": 855716, "flat_nlits": 9386236
      }
      expect(wassat_sls_arena_mb(divs)).to eq(261)
      expect(wassat_sls_arm_memory_allowed?(divs)).to eq(true)

      # The same allocation size on a broad application shape remains over
      # the limit: the exception is about dense few-variable kernels, not a
      # disguised global cap increase.
      broad = {
        "nvars": 50000, "flat_ncl": 855716, "flat_nlits": 9386236
      }
      expect(wassat_sls_arm_memory_allowed?(broad)).to eq(false)

    it "compresses XOR rows by participating variables, not declared nvars" ->
      # One valid two-variable XOR group plus two ignored units. The declared
      # DIMACS range is intentionally enormous; the GE row still needs one
      # word because only the two high-numbered variables participate.
      a = 999999937
      b = 1000000000
      formula = {
        "flat_lits": i64[6], "flat_offs": i64[4],
        "flat_lens": i64[4], "flat_ncl": 4
      }
      formula["flat_lits"][0] = a
      formula["flat_lits"][1] = b
      formula["flat_lits"][2] = 0 - a
      formula["flat_lits"][3] = 0 - b
      formula["flat_lits"][4] = 1
      formula["flat_lits"][5] = -1
      formula["flat_offs"][0] = 0
      formula["flat_offs"][1] = 2
      formula["flat_offs"][2] = 4
      formula["flat_offs"][3] = 5
      formula["flat_lens"][0] = 2
      formula["flat_lens"][1] = 2
      formula["flat_lens"][2] = 1
      formula["flat_lens"][3] = 1
      metrics = i64[2]
      wassat_xor_arm_body(b, formula, i64[1], 0, i64[4], metrics)
      expect(metrics[0]).to eq(2)
      expect(metrics[1]).to eq(1)

    it "back-substitutes and verifies a satisfiable pure XOR kernel" ->
      formula = wassat_parse_cnf_native(
        "p cnf 3 4\n" +
        "1 2 3 0\n" +
        "1 -2 -3 0\n" +
        "-1 2 -3 0\n" +
        "-1 -2 3 0\n"
      )
      res = i64[formula["nvars"] + 8]
      stop = i64[2]
      wassat_xor_arm_body(formula["nvars"], formula, res, 0, stop)
      expect(res[0]).to eq(1)
      expect(res[formula["nvars"] + 4]).to eq(1)
      expect(wassat_stop_status(stop)).to eq(1)
      model = []
      v = 1
      while v <= formula["nvars"]
        model.push(res[v] == 1 ? v : 0 - v)
        v += 1
      expect(wassat_model_satisfies?(formula, model)).to eq(true)

    it "retains exact XOR-subsystem refutations" ->
      # x=y, y=z, and x!=z.
      formula = wassat_parse_cnf_native(
        "p cnf 3 6\n" +
        "-1 2 0\n" +
        "1 -2 0\n" +
        "-2 3 0\n" +
        "2 -3 0\n" +
        "1 3 0\n" +
        "-1 -3 0\n"
      )
      res = i64[formula["nvars"] + 8]
      stop = i64[2]
      wassat_xor_arm_body(formula["nvars"], formula, res, 0, stop)
      expect(res[0]).to eq(-1)
      expect(res[formula["nvars"] + 4]).to eq(3)
      expect(wassat_stop_status(stop)).to eq(-1)

    it "enumerates free coordinates when the zero-free XOR point misses" ->
      # The old all-free-zero choice sets variable 2 false, while this
      # satisfiable mixed formula additionally requires 2. A different point
      # in the same affine space satisfies every original clause.
      formula = wassat_parse_cnf_native(
        "p cnf 3 5\n" +
        "1 2 3 0\n" +
        "1 -2 -3 0\n" +
        "-1 2 -3 0\n" +
        "-1 -2 3 0\n" +
        "2 0\n"
      )
      res = i64[formula["nvars"] + 8]
      stop = i64[2]
      wassat_xor_arm_body(formula["nvars"], formula, res, 0, stop)
      expect(res[0]).to eq(1)
      expect(res[2]).to eq(1)
      expect(wassat_stop_status(stop)).to eq(1)
      model = []
      v = 1
      while v <= formula["nvars"]
        model.push(res[v] == 1 ? v : 0 - v)
        v += 1
      expect(wassat_model_satisfies?(formula, model)).to eq(true)

    it "publishes nothing when every affine point misses the residual CNF" ->
      formula = wassat_parse_cnf_native(
        "p cnf 3 6\n" +
        "1 2 3 0\n" +
        "1 -2 -3 0\n" +
        "-1 2 -3 0\n" +
        "-1 -2 3 0\n" +
        "2 0\n" +
        "-2 0\n"
      )
      res = i64[formula["nvars"] + 8]
      stop = i64[2]
      wassat_xor_arm_body(formula["nvars"], formula, res, 0, stop)
      expect(res[0]).to eq(0)
      expect(wassat_stop_requested?(stop)).to eq(false)

    it "derives a width-three XOR row from its unique binary subclause" ->
      # The missing fourth XOR clause is (-1 -2 3). The stronger binary
      # (-1 -2) implies it, so all four forbidden parity points are present
      # semantically even though only three ternary clauses are rendered.
      formula = wassat_parse_cnf_native(
        "p cnf 3 4\n" +
        "1 2 3 0\n" +
        "1 -2 -3 0\n" +
        "-1 2 -3 0\n" +
        "-1 -2 0\n"
      )
      res = i64[formula["nvars"] + 8]
      stop = i64[2]
      metrics = i64[4]
      wassat_xor_arm_body(
        formula["nvars"], formula, res, 0, stop, metrics
      )
      expect(metrics[2]).to eq(1)
      expect(metrics[3]).to eq(1)
      expect(res[0]).to eq(1)
      expect(wassat_xor_grace_requested?(res, 0, formula["nvars"])).to eq(false)

    it "requests bounded grace only for a substantial near-XOR cluster" ->
      lines = ["p cnf 48 64"]
      i = 0
      while i < 16
        x = 3 * i + 1
        y = x + 1
        z = x + 2
        lines.push("[x] [y] [z] 0")
        lines.push("[x] [0 - y] [0 - z] 0")
        lines.push("[0 - x] [y] [0 - z] 0")
        lines.push("[0 - x] [0 - y] 0")
        i += 1
      formula = wassat_parse_cnf_native(lines.join("\n") + "\n")
      res = i64[formula["nvars"] + 8]
      metrics = i64[4]
      wassat_xor_arm_body(
        formula["nvars"], formula, res, 0, i64[2], metrics
      )
      expect(metrics[3]).to eq(16)
      expect(wassat_xor_grace_requested?(res, 0, formula["nvars"])).to eq(true)

    it "rejects a near-XOR whose binary is not a missing-clause subset" ->
      formula = wassat_parse_cnf_native(
        "p cnf 3 4\n" +
        "1 2 3 0\n" +
        "1 -2 -3 0\n" +
        "-1 2 -3 0\n" +
        "1 -2 0\n"
      )
      metrics = i64[4]
      wassat_xor_arm_body(
        formula["nvars"], formula, i64[formula["nvars"] + 8],
        0, i64[2], metrics
      )
      expect(metrics[2]).to eq(0)
      expect(metrics[3]).to eq(0)

    it "rejects one binary clause shared by two near-XOR groups" ->
      formula = wassat_parse_cnf_native(
        "p cnf 4 7\n" +
        "1 2 3 0\n" +
        "1 -2 -3 0\n" +
        "-1 2 -3 0\n" +
        "1 2 4 0\n" +
        "1 -2 -4 0\n" +
        "-1 2 -4 0\n" +
        "-1 -2 0\n"
      )
      metrics = i64[4]
      wassat_xor_arm_body(
        formula["nvars"], formula, i64[formula["nvars"] + 8],
        0, i64[2], metrics
      )
      expect(metrics[2]).to eq(0)
      expect(metrics[3]).to eq(0)

    it "recognizes and solves a complete xorshift/add circuit as a model-only lane" ->
      formula = wassat_parse_cnf_native(port_xs_fixture(false, false))
      plan = wassat_xs32_circuit_plan(formula["nvars"], formula)
      expect(plan == nil).to eq(false)
      expect(plan["nfolds"]).to eq(2)
      expect(plan["add_mask"]).to eq(1)
      expect(plan["target"]).to eq(0x141dbeaf)
      expect(plan["nand"]).to eq(63)
      expect(plan["nor"]).to eq(63)

      res = i64[formula["nvars"] + 8]
      stop = i64[4]
      metrics = i64[6]
      wassat_xs32_circuit_arm_body(
        formula["nvars"], formula, plan, res, 0, stop, metrics
      )
      expect(res[0]).to eq(1)
      expect(res[formula["nvars"] + 2]).to eq(1)
      expect(wassat_stop_status(stop)).to eq(1)
      expect(metrics[2]).to eq(2)
      model = []
      v = 1
      while v <= formula["nvars"]
        model.push(res[v] == 1 ? v : 0 - v)
        v += 1
      expect(wassat_model_satisfies?(formula, model)).to eq(true)

    it "recognizes a final ripple-add fold whose sum wires are gapped" ->
      formula = wassat_parse_cnf_native(port_xs_fixture(true, false))
      plan = wassat_xs32_circuit_plan(formula["nvars"], formula)
      expect(plan == nil).to eq(false)
      expect(plan["nfolds"]).to eq(2)
      expect(plan["add_mask"]).to eq(3)
      gapped = false
      i = 1
      while i < 32
        if plan["unit_vars"][i] > plan["unit_vars"][i - 1] + 1
          gapped = true
        i += 1
      expect(gapped).to eq(true)

    it "rejects a gate-count match with one wrong xorshift-fold wire" ->
      # Every variable remains defined by a valid XOR/AND/OR gate and all
      # operation counts are unchanged. Only exact wire-graph recognition
      # keeps this near-shape from entering the forced full-domain lane.
      formula = wassat_parse_cnf_native(port_xs_fixture(false, true))
      plan = wassat_xs32_circuit_plan(formula["nvars"], formula)
      expect(plan == nil).to eq(true)

    it "leaves an exhausted bounded xorshift partition non-decisive" ->
      # The AX fixture target is not reached by input zero. A finite partition
      # miss writes neither the local nor the race stop cell and can never be
      # mistaken for an UNSAT certificate.
      race_stop = i64[4]
      local_stop = i64[4]
      found = i64[1]
      target = 0x141dbeaf ## i64
      hit = wassat_xs32_partition(
        target, 1, 2, 0, 1, race_stop, local_stop, found, 0
      )
      expect(hit).to eq(0)
      expect(found[0]).to eq(0)
      expect(wassat_stop_requested?(local_stop)).to eq(false)
      expect(wassat_stop_requested?(race_stop)).to eq(false)

    it "materializes a raw artifact before handing it to GPU SLS" ->
      # No Metal device is required for this regression: the old bug was the
      # coordinator constructing the GPU formula from raw art["clauses"] == [].
      art = {
        "clauses": [], "fncl": 3, "fsynth": true,
        "fla": i64[5], "fcs": i64[3], "fcl": i64[3],
        "falive": i64[1], "ftaut": i64[1]
      }
      art["fla"][0] = 1
      art["fla"][1] = -1
      art["fla"][2] = 2
      art["fla"][3] = -2
      art["fla"][4] = 3
      art["fcs"][0] = 0
      art["fcs"][1] = 1
      art["fcs"][2] = 3
      art["fcl"][0] = 1
      art["fcl"][1] = 2
      art["fcl"][2] = 2
      expect(art["clauses"].size).to eq(0)
      gpu_formula = wassat_gpu_formula(art, 3)
      expect(gpu_formula["clauses"].size).to eq(3)
      expect(gpu_formula["clauses"][0]).to eq([1])

    it "retires a 200M-flip SLS arm when bounded CDCL work is exhausted" ->
      f = wassat_parse_cnf_native(PORT_SLS_UNSAT)
      art = wassat_raw_artifact(f, f["nvars"])
      race = wassat_race_build(f["nvars"], art, 1, f, nil, 0, 0, 1)
      wassat_race_add_sls(race, 200000000, 3, art)
      r = wassat_race_run(race, 1)
      sls_base = (race["threads"] + 2) * (f["nvars"] + 8)
      expect(r["status"]).to eq(0)
      expect(r["conflicts"]).to eq(1)
      expect(r["conflict_budget"][0]).to eq(1)
      charged = 0
      slot = 1
      while slot < r["conflict_budget"].size
        charged += r["conflict_budget"][slot]
        slot += 1
      expect(charged).to eq(r["conflict_budget"][0])
      expect(wassat_stop_requested?(race["stop"])).to eq(true)
      flips = race["res"][sls_base + f["nvars"] + 4]
      expect(flips <= WASSAT_SLS_REPAIR_PREFIX_FLIPS).to eq(true)

    it "answers UNSAT through the thread race with sharing stats" ->
      cnf_path = "/tmp/pspec_search_unsat.cnf"
      z = write_file(cnf_path, port_search_unsat)
      ok = port_exit_code(PORT_BIN + " portfolio " + cnf_path + " --fast --threads 3 > /tmp/pspec_fast1.out 2>&1")
      expect(ok).to eq(20)
      out = read_file("/tmp/pspec_fast1.out")
      expect(out.index("s UNSATISFIABLE") != nil).to eq(true)
      expect(out.index("exported=") != nil).to eq(true)

    it "answers SAT with a model verified against the original formula" ->
      cnf_path = "/tmp/pspec_fast_sat.cnf"
      z = write_file(cnf_path, PORT_SAT)
      ok = port_exit_code(PORT_BIN + " portfolio " + cnf_path + " --fast --threads 3 > /tmp/pspec_fast2.out 2>&1")
      expect(ok).to eq(10)
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

  context "clause-sharing accounting" ->
    it "credits only clauses the importer actually installs" ->
      # A committed one-slot ring authored by arm 0. First offer an already
      # satisfied clause to arm 1: it is consumed but must not reward its
      # author.
      satisfied_ring = i64[15]
      satisfied_ring[0] = 1
      satisfied_ring[8] = 1
      satisfied_ring[9] = 0
      satisfied_ring[10] = 2
      satisfied_ring[11] = 1
      satisfied_ring[12] = 2
      satisfied_credit = i64[2]
      satisfied = Wassat.new(2, [[1]], WASSAT_PROOF_NONE, 0)
      satisfied.enable_sharing(satisfied_ring, 1, 4, 1, false)
      satisfied.set_share_credit(satisfied_credit)
      expect(satisfied.share_import).to eq(0)
      expect(satisfied_credit[0]).to eq(0)

      # The same ring shape over an open formula installs the clause. The
      # importer continues normally (share_import returns only conflicts) and
      # the author's credit advances exactly once.
      installed_ring = i64[15]
      installed_ring[0] = 1
      installed_ring[8] = 1
      installed_ring[9] = 0
      installed_ring[10] = 2
      installed_ring[11] = 1
      installed_ring[12] = 2
      installed_credit = i64[2]
      installed = Wassat.new(2, [], WASSAT_PROOF_NONE, 0)
      installed.enable_sharing(installed_ring, 1, 4, 1, false)
      installed.set_share_credit(installed_credit)
      expect(installed.share_import).to eq(0)
      expect(installed_credit[0]).to eq(1)

  context "degenerate input" ->
    it "answers a preprocessing-refutable formula without spawning arms" ->
      z = write_file("/tmp/pspec_triv.cnf", "p cnf 1 2\n1 0\n-1 0\n")
      ok = port_run("/tmp/pspec_triv.cnf", "/tmp/pspec_triv.wrat", "/tmp/pspec_race3")
      expect(ok).to eq(20)
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
      # a deadline stop is UNKNOWN, which is exit 0 and not a verdict code
      expect(ok).to eq(0)
      out = read_file("/tmp/pspec_race_deadline.out")
      expect(out.index("s UNKNOWN") != nil).to eq(true)
      expect(out.index("deadline") != nil).to eq(true)
      expect(read_file(proof_path)).to eq(nil)

spec_summary
