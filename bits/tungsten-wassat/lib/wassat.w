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
use policy
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
  << "    wassat portfolio <problem.cnf> --proof <path>"
  << "    wassat portfolio <problem.cnf> --fast --threads <n>"
  << "    wassat sls <problem.cnf> --flips <n> --seed <n>"
  << "    wassat trim <proof.wrat> --out <path> --drat <path>"
  << "    wassat explain <proof.wrat> --labels <path>"
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
  << "EXIT CODES (SAT Competition convention)"
  << "    10  SATISFIABLE      20  UNSATISFIABLE"
  << "     0  UNKNOWN, help, or version"
  << "     1  usage or input error (2 from --worker)"
  << ""
  << "Use `-` as the path to write the proof to stdout."
  << ""
  << "MAIN OPTIONS"
  << "--conflicts <n> returns s UNKNOWN after n conflicts (default unlimited)."
  << "Search techniques and branching policy are selected automatically from"
  << "the parsed formula shape; there are no algorithm-tuning switches."
  << ""
  << "PORTFOLIO OPTIONS"
  << "--proof <path> is required in proof mode; --fast selects the shared"
  << "in-process race. --threads <n> defaults to 4, --timeout-ms <n> defaults"
  << "to 300000, --no-share disables learned-clause sharing, and --gpu adds"
  << "a model-only Metal arm to --fast. --dir chooses a work-directory parent."
  << ""
  << "SLS OPTIONS"
  << "--flips <n>, --seed <n>, and --pre are CPU controls. --gpu selects the"
  << "Metal fleet; --walkers <n> and --noise <0..256> apply only with --gpu."

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
    "conflicts": 0
  }
  seen = {}
  i = 0
  while i < args.size
    flag = args[i]
    if flag.starts_with?("--")
      unless flag == "--proof" || flag == "--drat" || flag == "--lrat" || flag == "--conflicts" || flag == "--fast"
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
          out["conflicts"] = wassat_decimal_in_range(flag, value, 0, 2000000000)
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

# Validate requested certificate destinations before solving. Otherwise an
# aliased output could replace the formula it is meant to certify.
# Callers must have READ the input already: an aliased destination is
# detected here, but even a missed alias must never truncate an unread input.
-> wassat_prepare_output(path, input_path, label)
  unless path == nil || path == "-"
    raise "[label] output must not overwrite the input formula" if wassat_same_file?(path, input_path)
  0

-> wassat_clear_output(path, input_path, label)
  unless path == nil || path == "-"
    wassat_prepare_output(path, input_path, label)
    raise "cannot clear stale [label] output at '[path]'" unless ccall("__w_unlink", path)
  0

# After the caller has cleared any stale final, reserve a unique temporary file
# beside it. Search streams only to the temporary path; a terminal UNSAT
# publishes it atomically after a successful flush.
-> wassat_reserve_output(path, input_path, label)
  return nil if path == nil
  return "-" if path == "-"
  wassat_prepare_output(path, input_path, label)
  tmp = ccall("__w_temp_file_for", path)
  raise "cannot reserve [label] output beside '[path]'" if tmp == nil
  tmp

-> wassat_publish_output(tmp, final_path, label)
  return 0 if final_path == nil || final_path == "-"
  raise "[label] flush failed at '[tmp]'" unless ccall("__w_fsync_path", tmp)
  raise "[label] publish failed at '[final_path]'" unless ccall("__w_rename", tmp, final_path)
  raise "[label] directory flush failed at '[final_path]'" unless ccall("__w_fsync_parent", final_path)
  0

-> wassat_discard_output(tmp, final_path)
  if tmp != nil && final_path != nil && final_path != "-" && tmp != final_path
    z = ccall("__w_unlink", tmp)
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
    # SAT Competition convention: 10 = SATISFIABLE, 20 = UNSATISFIABLE,
    # 0 = anything else. Each verdict site below exits with its own code the
    # moment the answer is known — the scout, lucky, local-search and race
    # arms, the preprocessing refutation and the serial solve all finish in
    # different places, and threading a code back out of every one of them
    # would buy nothing over exiting where the answer is.
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
  # Aggregate CDCL conflicts consumed by every search stage (scout probe, raw
  # race, final solve). --conflicts is a cap over their SUM, not a per-stage
  # allowance; 0 stays unlimited.
  budget_used = 0
  input = options["input"]
  wrat_final = options["proof"]
  wrat_final = options["lrat"] if wrat_final == nil
  # LRAT is the hinted stream without the wrat header; everything else about
  # emission, streaming, and checking is identical (wrat reads both).
  header_wanted = options["proof"] != nil
  drat_final = options["drat"]
  quiet = wrat_final == "-" || drat_final == "-"
  # Raw DRAT records each learned clause directly; the hinted stream carries
  # antecedent chains derived from conflict analysis. If both are requested
  # they are emitted natively in lockstep.
  proof_mode = WASSAT_PROOF_NONE
  proof_mode = WASSAT_PROOF_DRAT unless drat_final == nil
  proof_mode = WASSAT_PROOF_WRAT unless wrat_final == nil
  # Read the formula BEFORE touching any destination; only then truncate.
  tprof = wassat_prof_clock
  cnf_text = read_file(input)
  raise "cannot read input formula '[input]'" if cnf_text == nil
  if wrat_final != nil && wrat_final != "-" && drat_final != nil && drat_final != "-"
    raise "hinted and DRAT outputs resolve to the same file" if wassat_same_file?(wrat_final, drat_final)
  # Clear stale finals before parsing, but create no temporary artifact until
  # strict DIMACS validation succeeds. A malformed input therefore leaves
  # neither an old proof nor a leaked temp file.
  wassat_clear_output(wrat_final, input, "WRAT")
  wassat_clear_output(drat_final, input, "DRAT")
  formula = wassat_parse_cnf_native(cnf_text)
  wrat_out = wassat_reserve_output(wrat_final, input, "WRAT")
  drat_out = nil
  begin
    drat_out = wassat_reserve_output(drat_final, input, "DRAT")
  rescue e
    wassat_discard_output(wrat_out, wrat_final)
    raise e
  # from_lens, not new(clauses): identical counters (adopt_counts consumes the
  # same histogram) without walking 10M boxed clauses on the critical path.
  config = WassatConfig.from_lens(formula["nvars"], formula["flat_lens"], formula["flat_ncl"])
  tprof = wassat_prof("cli.parse", tprof)

  # Preprocess once, above solver construction. The artifact carries the
  # reduced clauses with their global proof ids, the elimination stack for
  # model reconstruction, and the certificate prefix for every derivation.
  # The trusted path is CHEAP-FIRST: light phases (~150ms even on
  # 100k-clause inputs) strip the implication shell that stalls local
  # search; bounded CDCL and lucky phases race; expensive subsumption/BVE
  # rounds run only when both miss. The
  # certificate path keeps the single-shot run().
  t0 = ccall("__w_clock_ms")
  pre = WassatPreprocess.new(formula["nvars"], [], proof_mode, formula)
  pre.enable_dual_emission if proof_mode == WASSAT_PROOF_WRAT && drat_final != nil
  art = nil
  if proof_mode == WASSAT_PROOF_NONE
    # A raw kernel runs no preprocessing technique at all, so it does not
    # need the preprocessor: hand the parser's flat arrays straight to the
    # solver (see wassat_raw_artifact).
    if config.race_route?
      art = wassat_raw_artifact(formula, formula["nvars"])
    else
      art = pre.run_light_flat(formula)
    tprof = wassat_prof("cli.light", tprof)
    if art["status"] == 0
      light_stack = art["stack"]
      probe_p = nil
      probe_out = nil
      scout_solver = nil

      # Bounded CDCL scout (flat-load, so construction is native): many
      # structured instances decide within a few thousand conflicts on the
      # light kernel and skip the heavy rounds entirely (ibm-6: 1.3k).
      # Kernel size does NOT predict scout wins (ibm-6 at 368k clauses
      # decides in ~2.5k conflicts; ibm-12 at 195k never does) — so the
      # scout always runs with a small budget: a win skips the heavy
      # rounds outright, a miss costs ~0.15s.
      if probe_p == nil
        # On a raw kernel the scout is a bounded first shot: easy kernels
        # (ibm-6/10 class) decide inside it, and a miss falls through to
        # the diversified thread race below. On a preprocessed kernel it
        # stays a cheap scout whose miss pays for the heavy rounds.
        raw_probe = art["raw"] == true
        probe_wall = config.probe_ms(raw_probe)
        probe_cap = config.probe_conflicts(raw_probe)
        # The scout is the FIRST CDCL stage inside the aggregate --conflicts
        # budget. Cap it (and every slice, including the first) at the
        # requested budget on raw AND reduced kernels, so a small budget is
        # never blown by the fixed 512-conflict first slice.
        probe_cap = options["conflicts"] if options["conflicts"] > 0 && options["conflicts"] < probe_cap
        # SCOUT RACE. Two arms over the same artifact, each on its own solver,
        # concurrently: kissat's lucky phases (the four decision-free dives of
        # lucky.c, its `luckyearly` shot) and the bounded CDCL scout.
        #
        # An arm, not a prologue, because the dives propagate — and propagation
        # permutes clause literals and moves watch entries, which reorders any
        # search that inherits the solver. Measured, keeping the dived solver:
        # the SC2026 miter is answered outright (9.9s -> 0.18s) but bmc-ibm-6
        # regresses 0.062s -> 0.281s on watch order alone. Running them in
        # front of the scout on a throwaway solver fixed that but paid a
        # from_flat for every miss; running them BESIDE it pays nothing at all,
        # and a win stops the scout through the shared cell.
        #
        # Everything the arms need is resolved into locals HERE, on the main
        # thread, so that spawning the second arm dispatches nothing while the
        # first is already running.
        scout_nv = formula["nvars"]
        scout_simplify = config.force_simplify?
        scout_stop = i64[4]
        # Three slots: the lucky arm at 0, the SLS arm at scout_nv + 8, the
        # XOR-refutation arm at 2 * (scout_nv + 8).
        scout_res = i64[3 * (scout_nv + 8)]
        scout_sls_base = scout_nv + 8
        scout_xor_base = 2 * (scout_nv + 8)
        scout_out = []
        # Local search races the SCOUT, not just the raw arms behind it. The
        # scout is bounded by conflicts rather than wall clock on a raw kernel,
        # and on the dense low-variable formulas local search is best at, those
        # 2,000 conflicts are expensive: n320p5q2_n spends 748ms there while the
        # walker reaches a model in 6,610 flips. Racing it means a formula local
        # search cracks is answered before the scout's cap is even approached.
        lucky_h = Thread.new -> wassat_lucky_arm_body(scout_nv, art, scout_res, 0, scout_stop)
        scout_h = Thread.new -> wassat_scout_arm_body(scout_nv, art, scout_stop, probe_cap, probe_wall, raw_probe, scout_simplify, scout_out)
        scout_sls_h = nil
        scout_sls_flips = wassat_sls_arm_flips
        if scout_sls_flips > 0
          scout_sls_h = Thread.new -> wassat_sls_arm_body(scout_nv, formula, scout_res, scout_sls_base, scout_stop, scout_sls_flips, 7)
        # GE over whatever XOR constraint groups the formula carries; refutes
        # tseitin/parity kernels outright. Reads the ORIGINAL clause list, so
        # its verdict is about the input formula whichever rendering the other
        # arms are on.
        scout_xor_h = Thread.new -> wassat_xor_arm_body(scout_nv, formula, scout_res, scout_xor_base, scout_stop)
        z = lucky_h.join
        z = scout_h.join
        # The walker is bounded by THE SCOUT'S LIFETIME, not by a flip budget.
        # Raising the cell here is what makes this arm free: it walks for
        # exactly as long as the scout was going to take anyway, so a miss
        # costs a core for a stage that was already running and never a
        # millisecond of wall clock. It also has to be unconditional -- the
        # scout's usual outcome is status 0 (undecided, hand off to the raw
        # race), which raises nothing, and an arm waiting on a signal that
        # never comes would walk out its whole budget with the join blocked
        # behind it. Measured when it did: bmc-ibm-12 0.7s -> 25s timeout.
        #
        # Rows that need a longer walk are not lost, they are handed to the
        # full SLS arm in the raw race behind this.
        scout_stop[0] = 1
        z = scout_sls_h.join if scout_sls_h != nil
        z = scout_xor_h.join
        # A GE refutation outranks everything: it is a verdict about the whole
        # input, costs zero conflicts, and cannot disagree with any other arm.
        if scout_res[scout_xor_base] == 0 - 1
          pre_msx = ccall("__w_clock_ms") - t0
          << "s UNSATISFIABLE"
          << "c mode: fast (xor refutation, [scout_res[scout_xor_base + scout_nv + 4]] parity rows)"
          << "c conflicts: 0, decisions: 0, props: 0"
          << "c stats restarts=0 reduces=0 " + wassat_pre_stats_text(art["stats"], pre_msx)
          exit(20)
        # A walked model is checked before the scout's verdict for the same
        # reason the lucky one is: same formula, so they cannot disagree, and
        # this one cost no conflicts at all.
        if scout_res[scout_sls_base] == 1
          pre_msw = ccall("__w_clock_ms") - t0
          wmodel = []
          v = 1
          while v <= scout_nv
            wmodel.push(scout_res[scout_sls_base + v] == 1 ? v : 0 - v)
            v += 1
          model = wassat_reconstruct_model(light_stack, wmodel, scout_nv)
          unless wassat_model_satisfies?(formula, model)
            raise "internal error: sls arm model does not satisfy the input formula"
          print("s SATISFIABLE\nv " + model.join(" ") + " 0\n")
          << "c mode: fast (sls arm)"
          << "c conflicts: 0, decisions: 0, flips: [scout_res[scout_sls_base + scout_nv + 4]]"
          << "c stats restarts=0 reduces=0 " + wassat_pre_stats_text(art["stats"], pre_msw)
          exit(10)
        tprof = wassat_prof("cli.scout_race", tprof)
        # A lucky verdict is checked first: it is the same formula the scout
        # is solving, so the two cannot disagree, and the dives reach it with
        # zero conflicts and zero decisions.
        lucky_status = scout_res[0]
        if lucky_status != 0
          pre_msl = ccall("__w_clock_ms") - t0
          if lucky_status == 1
            lmodel = []
            v = 1
            while v <= scout_nv
              lmodel.push(scout_res[v] == 1 ? v : 0 - v)
              v += 1
            model = wassat_reconstruct_model(light_stack, lmodel, scout_nv)
            unless wassat_model_satisfies?(formula, model)
              raise "internal error: lucky model does not satisfy the input formula"
            print("s SATISFIABLE\nv " + model.join(" ") + " 0\n")
          else
            << "s UNSATISFIABLE"
          << "c mode: fast (lucky phases)"
          << "c conflicts: 0, decisions: 0, props: [scout_res[scout_nv + 1]]"
          << "c stats restarts=0 reduces=0 " + wassat_pre_stats_text(art["stats"], pre_msl)
          exit(lucky_status == 1 ? 10 : 20)
        spr = scout_out[0]
        scout_solver = scout_out[1]
        budget_used = spr["conflicts"]
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
          exit(spr["status"] == 1 ? 10 : 20)

      staged_pre = art["raw"] == true && config.stage_pre_after_scout?
      if art["raw"] == true && !staged_pre && (options["conflicts"] == 0 || budget_used < options["conflicts"])
        arms = config.raw_race_arms
        # Preprocessing joins the race as ARMS, each in its own thread, each
        # rendering the formula and then solving what it rendered. Nothing is
        # decided up front and nothing is paid for up front: an instance the
        # raw arms crack in 5k conflicts never waits on a preprocessor, and
        # one that needs elimination gets it concurrently.
        #
        # There is no yield test and no clause-count gate on the RESULT,
        # because the measured families do not separate on yield: bmc-ibm-6
        # substitutes 14.3% of its variables and is 3.5x SLOWER preprocessed,
        # the md5 kernel substitutes 1.6% and is 20x faster, and 3bitadd_31
        # reduces by NOTHING and is 4.6x faster. Racing removes the need to
        # predict, which is the entire design.
        #
        # Two renderings, not one pipeline, because they are separately best:
        # elimination is worth 5.8x on the bitvector kernel smulo016 and costs
        # 50x on the md5 one (5k conflicts light, 255k heavy).
        pre_arms = wassat_pre_arm_count
        # Resource gate, not a yield prediction: two preprocessing passes have
        # stopping points too coarse to bound on very large inputs, so they are
        # not offered inputs they cannot survive (see wassat_pre_max_clauses).
        pre_arms = 0 if formula["flat_ncl"] > wassat_pre_max_clauses
        # The SLS arm makes the race worth building on its own: a formula that
        # local search cracks is answered here even when there is exactly one
        # raw arm and no preprocessing arm.
        sls_flips = wassat_sls_arm_flips
        race = nil
        if arms > 1 || pre_arms > 0 || sls_flips > 0
          continuation = config.continue_scout? ? scout_solver : nil
          continuation_spent = continuation == nil ? 0 : budget_used
          race = wassat_race_build(formula["nvars"], art, arms, formula,
                                   continuation, continuation_spent)
          wassat_race_add_sls(race, sls_flips, 7) if sls_flips > 0
          if pre_arms > 0
            # A preprocessor per arm: two threads rendering through one would
            # race on its arena. Constructed HERE, on the main thread, because
            # construction is the one part that touches the parsed formula's
            # boxed clauses while another arm might be reading them.
            plight = WassatPreprocess.new(formula["nvars"], [], WASSAT_PROOF_NONE, formula)
            plight.set_budget(wassat_pre_light_ticks)
            plight.set_deadline_ms(wassat_pre_stage_ms)
            plight.force_full_pipeline
            wassat_race_add_pre(race, plight, false, "light")
            if pre_arms > 1
              pheavy = WassatPreprocess.new(formula["nvars"], [], WASSAT_PROOF_NONE, formula)
              pheavy.set_budget(wassat_pre_light_ticks + wassat_pre_heavy_ticks)
              pheavy.set_deadline_ms(2 * wassat_pre_stage_ms)
              pheavy.force_full_pipeline
              wassat_race_add_pre(race, pheavy, true, "heavy")
        # Each arm is bounded by what remains of the aggregate budget, so no
        # CDCL path runs past --conflicts (previously the race was unbounded
        # and could answer long after a small --conflicts cap should have
        # returned UNKNOWN). 0 keeps the race unlimited.
        race_budget = options["conflicts"] == 0 ? 0 : options["conflicts"] - budget_used
        rr = nil
        if race != nil
          rr = wassat_race_run(race, race_budget)
          tprof = wassat_prof("cli.raw_race", tprof)
        if rr != nil && rr["status"] != 0
          budget_used += rr["conflicts"]
          pre_msr = ccall("__w_clock_ms") - t0
          # The winner's model is in ITS OWN formula's variable space, so
          # take the stack and the stats of the rendering that won. Each
          # preprocessing arm left both in its private `out` channel.
          pidx = rr["pre_index"]
          won_stack = art["stack"]
          won_stats = art["stats"]
          arm_tag = "arm [rr["winner"]]"
          arm_tag = "sls arm" if rr["sls_won"] == true
          if pidx >= 0
            spec = race["pre"][pidx]
            won_stack = spec["out"][0]
            won_stats = spec["out"][1]
            arm_tag = "[spec["label"]]-preprocessed arm"
          if rr["status"] == 1
            model = wassat_reconstruct_model(won_stack, rr["model"], formula["nvars"])
            unless wassat_model_satisfies?(formula, model)
              raise "internal error: race arm's model does not satisfy the input formula"
            print("s SATISFIABLE\nv " + model.join(" ") + " 0\n")
          else
            << "s UNSATISFIABLE"
          << "c mode: fast (raw cdcl race, [arm_tag])"
          << "c conflicts: [budget_used], decisions: 0, props: 0"
          << "c stats restarts=0 reduces=0 " + wassat_pre_stats_text(won_stats, pre_msr)
          exit(rr["status"] == 1 ? 10 : 20)
        if rr != nil
          budget_used += rr["conflicts"]
      if staged_pre
        pre.force_full_pipeline
        art = pre.run_light_flat(formula)
        art = pre.run_heavy if art["status"] == 0
        tprof = wassat_prof("cli.staged_pre", tprof)
      elsif !config.race_route?
        art = pre.run_heavy
        tprof = wassat_prof("cli.heavy", tprof)
      # did the probe already win while we preprocessed?
      if probe_p != nil
        prc = probe_p.poll
        if prc != nil && (prc == 10 || prc == 20)
          r2 = wassat_report_probe_win(prc, probe_out, light_stack, formula, art, t0)
          if r2 == 0
            exit(prc == 20 ? 20 : 10)
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
    unless wrat_final == nil
      whead = header_wanted ? "wrat 1\n" : ""
      wtext = whead + art["wrat"].join("\n") + "\n"
      unless wrat_final == "-"
        raise "proof write failed at '[wrat_out]'" unless write_file(wrat_out, wtext)
        wassat_publish_output(wrat_out, wrat_final, "WRAT")
    unless drat_final == nil
      dtext = art["drat"].empty? ? "" : art["drat"].join("\n") + "\n"
      unless drat_final == "-"
        raise "proof write failed at '[drat_out]'" unless write_file(drat_out, dtext)
        wassat_publish_output(drat_out, drat_final, "DRAT")
    wassat_status(quiet, "s UNSATISFIABLE")
    wassat_status(quiet, "c mode: [wassat_mode_of(options)]")
    wassat_status(quiet, "c conflicts: 0, decisions: 0")
    wassat_status(quiet, "c stats restarts=0 reduces=0 " + pstats)
    print(wtext) if wrat_final == "-"
    print(dtext) if drat_final == "-"
    exit(20)

  s = nil
  if proof_mode == WASSAT_PROOF_NONE
    # trusted path: ingest the preprocessor's flat mirrors natively
    s = Wassat.from_flat(formula["nvars"], art, 0)
    # This solver only runs when the bounded probe missed — a long search
    # ahead, where chronological backtracking measurably pays (the probe
    # itself must stay plain: fast target-phase dives dislike it).
    s.enable_chrono if art["raw"] == true
    s.simplify_raw if config.force_simplify?
    tprof = wassat_prof("cli.from_flat", tprof)
  else
    s = Wassat.new(formula["nvars"], art["clauses"], proof_mode, 0)
    s.seed_proof_ids(art["gids"], art["next_gid"])

  # File destinations stream during search so certificate memory stays flat;
  # `-` destinations render from the in-memory arrays after the fact. When
  # both dialects are requested they are emitted natively in lockstep. The
  # coordinator owns the certificate: the preprocessing prefix goes to each
  # sink before the solver appends a single line.
  wrat_stream = nil
  wrat_stream = wrat_out unless wrat_final == nil || wrat_final == "-"
  drat_stream = nil
  drat_stream = drat_out unless drat_final == nil || drat_final == "-"
  s.stream_proofs(wrat_stream, drat_stream) unless wrat_stream == nil && drat_stream == nil
  s.enable_dual_drat if proof_mode == WASSAT_PROOF_WRAT && drat_final != nil
  unless wrat_stream == nil
    whead = header_wanted ? "wrat 1\n" : ""
    whead = whead + art["wrat"].join("\n") + "\n" unless art["wrat"].empty?
    raise "proof write failed at '[wrat_stream]'" unless whead == "" || wassat_append_text(wrat_stream, whead)
    s.wrat_header_written
  unless drat_stream == nil || art["drat"].empty?
    dhead = art["drat"].join("\n") + "\n"
    raise "proof write failed at '[drat_stream]'" unless wassat_append_text(drat_stream, dhead)

  # Final search runs on whatever remains of the aggregate budget. If earlier
  # CDCL stages (scout, raw race) already spent it, add no further conflicts —
  # report UNKNOWN. --conflicts 0 stays unlimited.
  final_budget = options["conflicts"]
  skip_final = false
  if options["conflicts"] > 0
    final_budget = options["conflicts"] - budget_used
    skip_final = final_budget <= 0
  result = nil
  if skip_final
    result = s.unknown_result
  else
    result = s.solve_budget(final_budget)
  tprof = wassat_prof("cli.solve", tprof)
  if probe_p != nil
    if result["status"] == 0
      prc = probe_p.poll
      if prc != nil && (prc == 10 || prc == 20)
        r2 = wassat_report_probe_win(prc, probe_out, light_stack, formula, art, t0)
        if r2 == 0
          exit(prc == 20 ? 20 : 10)
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
  if result["status"] != -1
    wassat_discard_output(wrat_out, wrat_final)
    wassat_discard_output(drat_out, drat_final)

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
  if result["status"] == -1
    wassat_publish_output(wrat_out, wrat_final, "WRAT") unless wrat_final == nil || wrat_final == "-"
    wassat_publish_output(drat_out, drat_final, "DRAT") unless drat_final == nil || drat_final == "-"

  # Trim the trailing newline: wassat_result_text ends with one and
  # wassat_status appends its own.
  rtext = wassat_result_text(result)
  # Report conflicts as the aggregate across every CDCL stage so the number
  # is consistent with the --conflicts cap.
  agg_conflicts = result["conflicts"] + budget_used
  wassat_status(quiet, rtext.slice(0, rtext.size - 1))
  wassat_status(quiet, "c mode: [wassat_mode_of(options)]")
  wassat_status(quiet, "c conflicts: [agg_conflicts], decisions: [result["decisions"]]")
  wassat_status(quiet, "c stats restarts=[result["restarts"]] reduces=[result["reduces"]] " + pstats)

  if result["status"] == -1
    unless wrat_final == nil
      if wrat_final == "-"
        lines = wassat_concat_arrays(art["wrat"], result["proof"])
        whead = header_wanted ? "wrat 1\n" : ""
        print(whead + lines.join("\n") + "\n")
    unless drat_final == nil
      if drat_final == "-"
        dlines = wassat_concat_arrays(art["drat"], result["drat"])
        print(dlines.empty? ? "" : dlines.join("\n") + "\n")
  # Block form, NOT `exit(n) if cond`. parse_exit takes its operand with
  # parse_expression, so a trailing modifier binds to the ARGUMENT:
  # `exit(20) if cond` parses as `exit(20 if cond)`, which is `exit(nil)` —
  # an immediate exit 0 — whenever cond is false, silently dropping every
  # statement after it. parse_raise already dodges this by stopping at
  # parse_assignment (see its comment); parse_exit still needs the same fix.
  if result["status"] == 1
    exit(10)
  if result["status"] == -1
    exit(20)
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
  walkers_seen = false
  noise_seen = false
  seen = {}
  i = 0
  while i < args.size
    flag = args[i]
    if flag == "--flips" || flag == "--seed" || flag == "--walkers" || flag == "--noise"
      raise "duplicate wassat sls option: [flag]" if seen[flag] == true
      seen[flag] = true
      raise "missing value after [flag]" if i + 1 >= args.size
      value = args[i + 1]
      if flag == "--flips"
        flips = wassat_decimal_in_range(flag, value, 0, 2000000000)
      elsif flag == "--walkers"
        walkers = wassat_decimal_in_range(flag, value, 1, 4096)
        walkers_seen = true
      elsif flag == "--noise"
        noise = wassat_decimal_in_range(flag, value, 0, 256)
        noise_seen = true
      else
        seed = wassat_decimal_in_range(flag, value, 0, 2147483647)
      i += 2
    elsif flag == "--pre"
      raise "duplicate wassat sls option: [flag]" if seen[flag] == true
      seen[flag] = true
      pre = true
      i += 1
    elsif flag == "--gpu"
      raise "duplicate wassat sls option: [flag]" if seen[flag] == true
      seen[flag] = true
      gpu = true
      i += 1
    elsif flag.starts_with?("--")
      raise "unknown wassat sls option: [flag]"
    else
      raise "unexpected extra argument '[flag]'" unless input == nil
      input = flag
      i += 1
  raise "missing input formula" if input == nil
  raise "--walkers only applies with --gpu" if walkers_seen && !gpu
  raise "--noise only applies with --gpu" if noise_seen && !gpu
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
  # A model is exit 10 like every other engine's; local search can never
  # answer UNSAT, so a miss is UNKNOWN and exits 0.
  if r["sat"]
    exit(10)
  0

# CPU walker or the GPU fleet, per --gpu. The GPU path reads the Metal
# sidecar the build wrote next to the entry point (override: WASSAT_METAL).
-> wassat_sls_dispatch(formula, flips, seed, gpu, walkers, noise)
  if gpu
    metal_path = wassat_metal_path
    wassat_sls_gpu_solve(formula, walkers, flips, seed, noise, metal_path)
  else
    wassat_sls_solve(formula, flips, seed)

# Dispatch recognized command-line arguments. The executable entry point calls
# this explicitly; importing `use wassat` is side-effect free.
# SAT Competition exit-code convention: 10 = SATISFIABLE, 20 =
# UNSATISFIABLE, 0 = anything else (UNKNOWN, usage, refusal). Every
# competition harness and every rival solver uses this; returning 0 for
# both verdicts made wassat unscoreable regardless of correctness.
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
    return wassat_run_file(args)
  else
    wassat_print_usage
    exit(1)
