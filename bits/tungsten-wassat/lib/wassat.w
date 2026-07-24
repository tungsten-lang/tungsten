# Tungsten Wassat -- a SAT solver that shows its work.
#
# Wassat decides propositional satisfiability and, when a formula is
# unsatisfiable, emits a refutation that an independent checker can replay.
#
# The solver refuses to run without an explicit mode. `--proof` (or `--drat`)
# answers with a checkable certificate and restricts the engine to
# transformations whose proof obligations are implemented; `--fast` may use
# every technique and returns answers that are trusted, not proven. The
# difference between the two is whether an UNSAT answer can be independently
# verified, and that should never be implicit.
#
# Usage:
#   wassat <problem.cnf> --proof <path>    solve; write a hinted .wrat proof
#   wassat <problem.cnf> --drat <path>     solve; write a plain .drat proof
#   wassat <problem.cnf> --fast            solve; no certificate
#   wassat <problem.cnf> --proof -         print the proof to stdout
#   wassat version
#   wassat help

use version
use cnf
use solver
use preprocess
use sls
use sls_gpu
use trim
use explain
use portfolio

-> wassat_print_usage
  << "Tungsten Wassat [WASSAT_VERSION] -- SAT solver with checkable proofs"
  << ""
  # Note: square brackets are string interpolation in Tungsten, so usage
  # text spells optional arguments without them.
  << "USAGE"
  << "    wassat <problem.cnf> --proof <path>     certificate-backed answers"
  << "    wassat <problem.cnf> --lrat <path>      certificate-backed, LRAT dialect"
  << "    wassat <problem.cnf> --drat <path>      certificate-backed, plain DRAT"
  << "    wassat <problem.cnf> --fast             trusted answers, no certificate"
  << "    wassat version"
  << "    wassat help"
  << ""
  << "A mode is required: --proof (or --drat) proves UNSAT answers and"
  << "restricts the engine to proof-covered techniques; --fast enables every"
  << "technique and its UNSAT answers are trusted, not proven."
  << ""
  << "OUTPUT"
  << "    s SATISFIABLE   with a `v` model line"
  << "    s UNSATISFIABLE with a refutation when a proof path is given"
  << "    s UNKNOWN       when --conflicts stops a bounded search"
  << ""
  << "Use `-` as the path to write the proof to stdout."
  << ""
  << "--lookahead <n> scores n candidate variables by one-step rollout"
  << "(trial propagation) before each decision. Helps markedly on random"
  << "instances, hurts on structured ones. Default 0 = activity branching."
  << "--conflicts <n> returns s UNKNOWN after n conflicts (default unlimited)."

# Parse and validate command-line arguments. Flags may appear before or after
# the input path (benchmark harnesses append the path last). A typo in a
# search limit must never silently turn a bounded job into an unlimited one.
-> wassat_cli_options(args)
  out = {
    "input": nil,
    "proof": nil,
    "drat": nil,
    "lrat": nil,
    "fast": false,
    "lookahead": 0,
    "conflicts": 0
  }
  seen = {}
  i = 0
  while i < args.size
    flag = args[i]
    if flag.starts_with?("--")
      unless flag == "--proof" || flag == "--drat" || flag == "--lrat" || flag == "--lookahead" || flag == "--conflicts" || flag == "--fast"
        raise "unknown Wassat option: [flag]"
      raise "duplicate Wassat option: [flag]" if seen[flag] == true
      seen[flag] = true
      if flag == "--fast"
        out["fast"] = true
        i += 1
      else
        raise "missing value after [flag]" if i + 1 >= args.size
        value = args[i + 1]
        raise "missing value after [flag]" if value.starts_with?("--")
        if flag == "--proof"
          out["proof"] = value
        elsif flag == "--drat"
          out["drat"] = value
        elsif flag == "--lrat"
          out["lrat"] = value
        else
          raise "[flag] requires a non-negative decimal integer, got '[value]'" unless wassat_unsigned_decimal?(value)
          if flag == "--lookahead"
            out["lookahead"] = value.to_i
          else
            out["conflicts"] = value.to_i
        i += 2
    else
      raise "unexpected extra argument '[flag]' (input is '[out["input"]]')" unless out["input"] == nil
      out["input"] = flag
      i += 1
  raise "missing input formula" if out["input"] == nil
  if out["proof"] != nil && out["lrat"] != nil
    raise "--proof and --lrat are two renderings of one hinted stream; choose one"
  hinted = out["proof"]
  hinted = out["lrat"] if hinted == nil
  if hinted != nil && hinted == out["drat"]
    raise "hinted and DRAT outputs need different destinations"
  if out["fast"] && (out["proof"] != nil || out["drat"] != nil || out["lrat"] != nil)
    raise "--fast forgoes certificates; drop --fast or the proof options"
  if !out["fast"] && out["proof"] == nil && out["drat"] == nil && out["lrat"] == nil
    raise "choose a mode: --proof/--lrat/--drat <path> for checkable answers, --fast for trusted ones"
  out

# The mode a parsed option set selects: "proof" or "fast". `--drat` implies
# proof mode -- it produces a certificate, just in the plain dialect.
-> wassat_mode_of(options)
  options["fast"] ? "fast" : "proof"

# Two paths name the same file when the strings match or when both exist
# with the same (device, inode) identity — which catches symlink and
# hardlink aliases, not just spelling. The identity probe is compiled-CLI
# only; the string check short-circuits first so library callers with
# equal paths never reach the ccall.
-> wassat_same_file?(a, b)
  return true if a == b
  ida = ccall("__w_file_id", a)
  idb = ccall("__w_file_id", b)
  ida != nil && idb != nil && ida == idb

# Truncate requested certificate destinations before solving. Otherwise a SAT,
# UNKNOWN, parse failure, or interrupted rerun can leave an older refutation at
# the requested path and make it look like evidence for the current formula.
# Callers must have READ the input already: an aliased destination is
# detected here, but even a missed alias must never truncate an unread input.
-> wassat_prepare_output(path, input_path, label)
  unless path == nil || path == "-"
    raise "[label] output must not overwrite the input formula" if wassat_same_file?(path, input_path)
    raise "cannot prepare [label] output at '[path]'" unless write_file(path, "")
  0

# Status, model, and comment lines go to stderr whenever a certificate is
# being written to stdout, so the streamed proof is standalone.
-> wassat_status(quiet, text)
  if quiet
    z = ccall("__w_eprint", text + "\n")
  else
    << text
  0

# Report malformed input as a clean diagnostic rather than a backtrace. The
# parser is deliberately strict -- a DIMACS file whose clause count disagrees
# with its header is far more likely to be truncated or to carry trailing
# junk than to be the formula the caller meant to solve.
-> wassat_run_file(args)
  begin
    wassat_run_file_checked(args)
  rescue e
    << "c error: [e]"
    << "s UNKNOWN"
    exit(1)

# Report a probe-process win: reconstruct the reduced-formula model (or
# accept the trusted UNSAT), verify, print. Returns 0 on success, 1 when
# the status file is unreadable (caller falls through to its own solve).
-> wassat_report_probe_win(prc, probe_out, light_stack, formula, art, start_ms)
  if prc == 20
    << "s UNSATISFIABLE"
    << "c mode: fast (raced: light probe)"
    << "c stats restarts=0 reduces=0 " + wassat_pre_stats_text(art["stats"], ccall("__w_clock_ms") - start_ms)
    return 0
  line = read_file(probe_out)
  return 1 if line == nil
  reduced_model = []
  wassat_tokenize(line).each -> (tk)
    v = tk.to_i
    reduced_model.push(v) unless v == 0 || tk == "0"
  return 1 if reduced_model.empty?
  model = wassat_reconstruct_model(light_stack, reduced_model, formula["nvars"])
  unless wassat_model_satisfies?(formula, model)
    raise "internal error: probe model does not satisfy the input formula"
  print("s SATISFIABLE\nv " + model.join(" ") + " 0\n")
  << "c mode: fast (raced: light probe)"
  << "c stats restarts=0 reduces=0 " + wassat_pre_stats_text(art["stats"], ccall("__w_clock_ms") - start_ms)
  0

-> wassat_run_file_checked(args)
  options = wassat_cli_options(args)
  probe_p = nil
  probe_out = nil
  light_stack = nil
  input = options["input"]
  wrat_out = options["proof"]
  wrat_out = options["lrat"] if wrat_out == nil
  # LRAT is the hinted stream without the wrat header; everything else about
  # emission, streaming, and checking is identical (wrat reads both).
  header_wanted = options["proof"] != nil
  drat_out = options["drat"]
  quiet = wrat_out == "-" || drat_out == "-"
  # Raw DRAT records each learned clause directly; the hinted stream carries
  # antecedent chains derived from conflict analysis. If both are requested
  # they are emitted natively in lockstep.
  proof_mode = WASSAT_PROOF_NONE
  proof_mode = WASSAT_PROOF_DRAT unless drat_out == nil
  proof_mode = WASSAT_PROOF_WRAT unless wrat_out == nil
  # Read the formula BEFORE touching any destination; only then truncate.
  tprof = wassat_prof_clock
  cnf_text = read_file(input)
  raise "cannot read input formula '[input]'" if cnf_text == nil
  wassat_prepare_output(wrat_out, input, "WRAT")
  wassat_prepare_output(drat_out, input, "DRAT")
  formula = wassat_parse_cnf_native(cnf_text)
  tprof = wassat_prof("cli.parse", tprof)

  # Preprocess once, above solver construction. The artifact carries the
  # reduced clauses with their global proof ids, the elimination stack for
  # model reconstruction, and the certificate prefix for every derivation.
  # The trusted path is CHEAP-FIRST: light phases (~150ms even on
  # 100k-clause inputs) strip the implication shell that stalls local
  # search, an SLS burst hunts a model there, and the expensive
  # subsumption/BVE rounds run only when the burst misses. The certificate
  # path keeps the single-shot run().
  t0 = ccall("__w_clock_ms")
  pre = WassatPreprocess.new(formula["nvars"], formula["clauses"], proof_mode)
  pre.enable_dual_emission if proof_mode == WASSAT_PROOF_WRAT && drat_out != nil
  art = nil
  if proof_mode == WASSAT_PROOF_NONE
    art = pre.run_light_flat(formula)
    tprof = wassat_prof("cli.light", tprof)
    if art["status"] == 0
      # The burst pays only on kernels local search can actually crack —
      # measured: hits on small kernels (ibm-2), never on 100k-clause
      # ones, where the SLS constructor's normalization alone costs more
      # than the CDCL probe.
      burst0 = { "sat": false }
      if art["clauses"].size > 0 && art["clauses"].size <= 50000
        reduced0 = { "nvars": formula["nvars"], "clauses": art["clauses"] }
        burst0 = wassat_sls_solve(reduced0, 60000, 7)
      tprof = wassat_prof("cli.sls_burst", tprof)
      if burst0["sat"]
        model = wassat_reconstruct_model(art["stack"], burst0["model"], formula["nvars"])
        unless wassat_model_satisfies?(formula, model)
          raise "internal error: SLS burst model does not satisfy the input formula"
        pre_ms0 = ccall("__w_clock_ms") - t0
        print("s SATISFIABLE\nv " + model.join(" ") + " 0\n")
        << "c mode: fast (light+sls burst)"
        << "c conflicts: 0, decisions: 0"
        << "c stats restarts=0 reduces=0 flips=[burst0["flips"]] " + wassat_pre_stats_text(art["stats"], pre_ms0)
        return 0
      # Race a probe PROCESS on the light kernel while this process pays
      # for the heavy rounds and the full solve. A process, not a thread:
      # the main thread must not dispatch while worker threads run
      # (inline caches are process-global), but OS isolation makes the
      # probe free — its miss costs nothing serial but the artifact write.
      light_stack = art["stack"]
      probe_p = nil
      probe_out = nil
      # only worth its ~60ms serial overhead (artifact write + spawn) when
      # the heavy rounds + solve it overlaps are big
      begin
        # Opt-in (WASSAT_RACE=1): on instances where the probe rarely wins
        # it is pure core contention against the main solve — measured
        # net-negative on loaded machines (ibm-12 serial 1.68s vs raced
        # 1.9-4.6s). Worth revisiting with a win-prediction heuristic.
        raise "race disabled" unless env("WASSAT_RACE") == "1"
        raise "small instance; skip race" if formula["clauses"].size <= 50000
        race_dir = "/tmp/wassat-lightrace-" + input.split("/").last.replace(".cnf", "")
        z = ccall("__w_system", "mkdir -p " + race_dir)
        rp = race_dir + "/reduced.cnf"
        gp = race_dir + "/gids.txt"
        probe_out = race_dir + "/probe.out"
        z = ccall("__w_system", "rm -f " + probe_out)
        if wassat_write_artifact_files(formula["nvars"], art, rp, gp)
          probe_p = Process.spawn([wassat_own_binary, "--worker", rp, "--gids", gp,
                                   "--status", probe_out, "--arm", "probe"])
      rescue e
        probe_p = nil

      # Serial light probe (flat-load, so construction is native): many
      # structured instances decide within a few thousand conflicts on the
      # light kernel and skip the heavy rounds entirely (ibm-6: 1.3k).
      # Kernel size does NOT predict probe wins (ibm-6 at 368k clauses
      # decides in ~2.5k conflicts; ibm-12 at 195k never does) — so the
      # probe always runs with a small budget: a win skips the heavy
      # rounds outright, a miss costs ~0.15s.
      if probe_p == nil
        sprobe = Wassat.from_flat(formula["nvars"], art, 0)
        # time-boxed in conflict slices: wins arrive fast when they arrive
        # at all, and a miss is capped at ~120ms instead of a full
        # conflict budget's worth of work on a big kernel
        probe_t0 = ccall("__w_clock_ms")
        # On a raw kernel the probe is a bounded first shot: easy kernels
        # (ibm-6/10 class) decide inside it, and a miss falls through to
        # the diversified thread race below. On a preprocessed kernel it
        # stays a cheap scout whose miss pays for the heavy rounds.
        probe_wall = 120
        probe_cap = 4000
        if art["raw"] == true
          probe_wall = 150
          probe_cap = options["conflicts"] > 0 ? options["conflicts"] : 2000
        if env("WASSAT_PROBE_MS") != nil
          probe_wall = env("WASSAT_PROBE_MS").to_i
          probe_cap = probe_wall * 40
        spr = sprobe.solve_budget(512)
        while spr["status"] == 0 && spr["conflicts"] < probe_cap && ccall("__w_clock_ms") - probe_t0 < probe_wall
          spr = sprobe.solve_budget(512)
        tprof = wassat_prof("cli.serial_probe", tprof)
        if spr["status"] != 0
          pre_msq = ccall("__w_clock_ms") - t0
          if spr["status"] == 1
            model = wassat_reconstruct_model(light_stack, spr["model"], formula["nvars"])
            tprof = wassat_prof("cli.reconstruct", tprof)
            unless wassat_model_satisfies?(formula, model)
              raise "internal error: light-probe model does not satisfy the input formula"
            tprof = wassat_prof("cli.verify", tprof)
            print("s SATISFIABLE\nv " + model.join(" ") + " 0\n")
            tprof = wassat_prof("cli.vline", tprof)
          else
            << "s UNSATISFIABLE"
          mode_tag = art["raw"] == true ? "raw cdcl" : "light+cdcl probe"
          << "c mode: fast ([mode_tag])"
          << "c conflicts: [spr["conflicts"]], decisions: [spr["decisions"]], props: [spr["props"]]"
          << "c stats restarts=[spr["restarts"]] reduces=[spr["reduces"]] " + wassat_pre_stats_text(art["stats"], pre_msq)
          return 0

      if art["raw"] == true
        arms = 8
        arms = env("WASSAT_ARMS").to_i if env("WASSAT_ARMS") != nil
        if arms > 1
          rr = wassat_raw_race(formula["nvars"], art, arms)
          tprof = wassat_prof("cli.raw_race", tprof)
          if rr["status"] != 0
            pre_msr = ccall("__w_clock_ms") - t0
            if rr["status"] == 1
              model = wassat_reconstruct_model(light_stack, rr["model"], formula["nvars"])
              unless wassat_model_satisfies?(formula, model)
                raise "internal error: race arm's model does not satisfy the input formula"
              print("s SATISFIABLE\nv " + model.join(" ") + " 0\n")
            else
              << "s UNSATISFIABLE"
            << "c mode: fast (raw cdcl race, arm [rr["winner"]])"
            << "c conflicts: [rr["conflicts"]], decisions: 0, props: 0"
            << "c stats restarts=0 reduces=0 " + wassat_pre_stats_text(art["stats"], pre_msr)
            return 0
      art = pre.run_heavy
      tprof = wassat_prof("cli.heavy", tprof)
      # did the probe already win while we preprocessed?
      if probe_p != nil
        prc = probe_p.poll
        if prc != nil && (prc == 10 || prc == 20)
          r2 = wassat_report_probe_win(prc, probe_out, light_stack, formula, art, t0)
          return 0 if r2 == 0
          probe_p = nil
  else
    art = pre.run
  pre_ms = ccall("__w_clock_ms") - t0
  pstats = wassat_pre_stats_text(art["stats"], pre_ms)

  if art["status"] == -1
    # Refuted during preprocessing; the prefix is the whole certificate.
    # Certificates reach durable storage BEFORE the verdict is announced: a
    # failed write must never leave "s UNSATISFIABLE" beside an incomplete
    # proof.
    wtext = ""
    dtext = ""
    unless wrat_out == nil
      whead = header_wanted ? "wrat 1\n" : ""
      wtext = whead + art["wrat"].join("\n") + "\n"
      unless wrat_out == "-"
        raise "proof write failed at '[wrat_out]'" unless write_file(wrat_out, wtext)
    unless drat_out == nil
      dtext = art["drat"].empty? ? "" : art["drat"].join("\n") + "\n"
      unless drat_out == "-"
        raise "proof write failed at '[drat_out]'" unless write_file(drat_out, dtext)
    wassat_status(quiet, "s UNSATISFIABLE")
    wassat_status(quiet, "c mode: [wassat_mode_of(options)]")
    wassat_status(quiet, "c conflicts: 0, decisions: 0")
    wassat_status(quiet, "c stats restarts=0 reduces=0 " + pstats)
    print(wtext) if wrat_out == "-"
    print(dtext) if drat_out == "-"
    return 0

  s = nil
  if proof_mode == WASSAT_PROOF_NONE
    # trusted path: ingest the preprocessor's flat mirrors natively
    s = Wassat.from_flat(formula["nvars"], art, options["lookahead"])
    tprof = wassat_prof("cli.from_flat", tprof)
  else
    s = Wassat.new(formula["nvars"], art["clauses"], proof_mode, options["lookahead"])
    s.seed_proof_ids(art["gids"], art["next_gid"])

  # File destinations stream during search so certificate memory stays flat;
  # `-` destinations render from the in-memory arrays after the fact. When
  # both dialects are requested they are emitted natively in lockstep. The
  # coordinator owns the certificate: the preprocessing prefix goes to each
  # sink before the solver appends a single line.
  wrat_stream = nil
  wrat_stream = wrat_out unless wrat_out == nil || wrat_out == "-"
  drat_stream = nil
  drat_stream = drat_out unless drat_out == nil || drat_out == "-"
  s.stream_proofs(wrat_stream, drat_stream) unless wrat_stream == nil && drat_stream == nil
  s.enable_dual_drat if proof_mode == WASSAT_PROOF_WRAT && drat_out != nil
  unless wrat_stream == nil
    whead = header_wanted ? "wrat 1\n" : ""
    whead = whead + art["wrat"].join("\n") + "\n" unless art["wrat"].empty?
    raise "proof write failed at '[wrat_stream]'" unless whead == "" || wassat_append_text(wrat_stream, whead)
    s.wrat_header_written
  unless drat_stream == nil || art["drat"].empty?
    dhead = art["drat"].join("\n") + "\n"
    raise "proof write failed at '[drat_stream]'" unless wassat_append_text(drat_stream, dhead)

  result = s.solve_budget(options["conflicts"])
  tprof = wassat_prof("cli.solve", tprof)
  if probe_p != nil
    if result["status"] == 0
      prc = probe_p.poll
      if prc != nil && (prc == 10 || prc == 20)
        r2 = wassat_report_probe_win(prc, probe_out, light_stack, formula, art, t0)
        return 0 if r2 == 0
    z = probe_p.kill
    prc = probe_p.poll
    if prc == nil
      z = ccall("__w_sleep_ms", 30)
      prc = probe_p.poll
      z = probe_p.kill(9) if prc == nil
      prc = probe_p.wait
  # A run that did not end UNSAT truncates its sink destinations at once: a
  # partial refutation must never survive on disk, whatever happens later.
  s.abort_proof_sinks unless result["status"] == -1

  # Output integrity: the reconstructed model is verified against the
  # ORIGINAL formula before anything is reported. A failing model is a
  # solver or reconstruction bug and must surface as a hard error here,
  # never as a wrong `v` line a harness might trust.
  if result["status"] == 1
    result["model"] = wassat_reconstruct_model(art["stack"], result["model"], formula["nvars"])
    tprof = wassat_prof("cli.reconstruct", tprof)
    unless wassat_model_satisfies?(formula, result["model"])
      raise "internal error: model does not satisfy the input formula"

  # On UNSAT the certificate is flushed to durable storage BEFORE the
  # verdict is announced: a failed flush raises here and the run reports an
  # error, never "s UNSATISFIABLE" beside an incomplete proof.
  s.flush_proof_sinks if result["status"] == -1

  # Trim the trailing newline: wassat_result_text ends with one and
  # wassat_status appends its own.
  rtext = wassat_result_text(result)
  wassat_status(quiet, rtext.slice(0, rtext.size - 1))
  wassat_status(quiet, "c mode: [wassat_mode_of(options)]")
  wassat_status(quiet, "c conflicts: [result["conflicts"]], decisions: [result["decisions"]]")
  wassat_status(quiet, "c stats restarts=[result["restarts"]] reduces=[result["reduces"]] " + pstats)

  if result["status"] == -1
    unless wrat_out == nil
      if wrat_out == "-"
        lines = wassat_concat_arrays(art["wrat"], result["proof"])
        whead = header_wanted ? "wrat 1\n" : ""
        print(whead + lines.join("\n") + "\n")
    unless drat_out == nil
      if drat_out == "-"
        dlines = wassat_concat_arrays(art["drat"], result["drat"])
        print(dlines.empty? ? "" : dlines.join("\n") + "\n")
  0

# `wassat sls <cnf> --flips <n> --seed <s>`: run the stochastic local search
# alone. Prints a model (verified against the formula first) or s UNKNOWN --
# local search can never answer UNSATISFIABLE, so no certificate applies.
-> wassat_run_sls(args)
  input = nil
  flips = 10000000
  seed = 1
  pre = false
  gpu = false
  walkers = 256
  noise = 48
  i = 0
  while i < args.size
    flag = args[i]
    if flag == "--flips" || flag == "--seed" || flag == "--walkers" || flag == "--noise"
      raise "missing value after [flag]" if i + 1 >= args.size
      value = args[i + 1]
      raise "[flag] requires a non-negative decimal integer, got '[value]'" unless wassat_unsigned_decimal?(value)
      if flag == "--flips"
        flips = value.to_i
      elsif flag == "--walkers"
        walkers = value.to_i
      elsif flag == "--noise"
        noise = value.to_i
        raise "--noise is out of 256" if noise > 256
      else
        seed = value.to_i
      i += 2
    elsif flag == "--pre"
      pre = true
      i += 1
    elsif flag == "--gpu"
      gpu = true
      i += 1
    elsif flag.starts_with?("--")
      raise "unknown wassat sls option: [flag]"
    else
      raise "unexpected extra argument '[flag]'" unless input == nil
      input = flag
      i += 1
  raise "missing input formula" if input == nil
  cnf_text = read_file(input)
  raise "cannot read input formula '[input]'" if cnf_text == nil
  formula = wassat_parse_cnf(cnf_text)
  r = nil
  if pre
    # SLS over the preprocessed kernel: the structured shell (root
    # implications, substituted equivalences, eliminable variables) is
    # exactly what local search wastes flips rediscovering. The model is
    # reconstructed through the elimination stack and verified against the
    # ORIGINAL formula like every other answer.
    art = wassat_preprocess(cnf_text, WASSAT_PROOF_NONE)
    if art["status"] == -1
      # preprocessing refuted it; SLS has nothing to say beyond UNKNOWN
      << "s UNKNOWN"
      << "c mode: sls"
      << "c stats flips=0 restarts=0 best_unsat=1 seed=[seed]"
      return 0
    reduced = { "nvars": formula["nvars"], "clauses": art["clauses"] }
    r = wassat_sls_dispatch(reduced, flips, seed, gpu, walkers, noise)
    if r["sat"]
      r["model"] = wassat_reconstruct_model(art["stack"], r["model"], formula["nvars"])
  else
    r = wassat_sls_dispatch(formula, flips, seed, gpu, walkers, noise)
  if r["sat"]
    # same output-integrity bar as every other engine: verify against the
    # ORIGINAL formula before reporting
    unless wassat_model_satisfies?(formula, r["model"])
      raise "internal error: SLS model does not satisfy the input formula"
    print("s SATISFIABLE
v " + r["model"].join(" ") + " 0
")
  else
    << "s UNKNOWN"
  << "c mode: sls"
  << "c stats flips=[r["flips"]] restarts=[r["restarts"]] best_unsat=[r["best_unsat"]] seed=[r["seed"]]"
  0

# CPU walker or the GPU fleet, per --gpu. The GPU path reads the Metal
# sidecar the build wrote next to the entry point (override: WASSAT_METAL).
-> wassat_sls_dispatch(formula, flips, seed, gpu, walkers, noise)
  if gpu
    metal_path = env("WASSAT_METAL")
    metal_path = "bin/wassat.metal" if metal_path == nil || metal_path == ""
    chunk = 200000
    chunks = flips / chunk
    chunks = 1 if chunks < 1
    wassat_sls_gpu_solve(formula, walkers, chunk, chunks, seed, noise, metal_path)
  else
    wassat_sls_solve(formula, flips, seed)

# Dispatch recognized command-line arguments. The executable entry point calls
# this explicitly; importing `use wassat` is side-effect free.
-> wassat_run_cli(args)
  cmd = nil
  cmd = args[0] if args.size > 0

  if cmd == "version" || cmd == "--version" || cmd == "-v"
    << "Tungsten Wassat [WASSAT_VERSION]"
  elsif cmd == "help" || cmd == "--help" || cmd == "-h"
    wassat_print_usage
  elsif cmd == "sls"
    rest = []
    i = 1
    while i < args.size
      rest.push(args[i])
      i += 1
    begin
      wassat_run_sls(rest)
    rescue e
      << "c error: [e]"
      << "s UNKNOWN"
      exit(1)
  elsif cmd == "trim"
    rest = []
    i = 1
    while i < args.size
      rest.push(args[i])
      i += 1
    begin
      wassat_run_trim(rest)
    rescue e
      << "c error: [e]"
      exit(1)
  elsif cmd == "explain"
    rest = []
    i = 1
    while i < args.size
      rest.push(args[i])
      i += 1
    begin
      wassat_run_explain(rest)
    rescue e
      << "c error: [e]"
      exit(1)
  elsif cmd == "--worker"
    rest = []
    i = 1
    while i < args.size
      rest.push(args[i])
      i += 1
    begin
      wassat_run_worker(rest)
    rescue e
      << "c worker error: [e]"
      exit(2)
  elsif cmd == "portfolio"
    rest = []
    i = 1
    while i < args.size
      rest.push(args[i])
      i += 1
    begin
      wassat_run_portfolio(rest)
    rescue e
      << "c error: [e]"
      << "s UNKNOWN"
      exit(1)
  elsif args.size >= 1
    wassat_run_file(args)
  else
    wassat_print_usage
    exit(1)
