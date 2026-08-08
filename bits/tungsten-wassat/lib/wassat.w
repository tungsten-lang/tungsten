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
use atomic_stop
use solver
use local_core
use multiplier
use fermat
use sum_of_three_cubes
use mdp
use automata_sync
use latin_csp
use ternary_affine
use ais
use coloring
use covering
use directed_kernel
use edge_matching
use sliding_puzzle
use stedman
use hantzsche_wendt
use knight_tour
use preprocess
use sls
use sls_gpu
use trim
use explain
use portfolio

# Allocate one bounded CDCL stage from the aggregate --conflicts budget.
# A zero total is the public unlimited value; a zero return for a finite total
# means every conflict ticket has already been consumed.
-> wassat_stage_conflict_cap(total, used, ceiling)
  return ceiling if total == 0
  return 0 if used >= total
  remaining = total - used
  remaining < ceiling ? remaining : ceiling

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
-> wassat_report_probe_win(prc, probe_out, light_stack, formula, art, start_ms, prior_conflicts = 0)
  if prc == 20
    << "s UNSATISFIABLE"
    << "c mode: fast (raced: light probe)"
    << "c conflicts: [prior_conflicts], decisions: 0"
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
  print(wassat_sat_text(model))
  << "c mode: fast (raced: light probe)"
  << "c conflicts: [prior_conflicts], decisions: 0"
  << "c stats restarts=0 reduces=0 " + wassat_pre_stats_text(art["stats"], ccall("__w_clock_ms") - start_ms)
  0

-> wassat_run_file_checked(args)
  options = wassat_cli_options(args)
  probe_p = nil
  probe_out = nil
  light_stack = nil
  # Aggregate CDCL conflicts consumed by every search stage (local core,
  # ordinary scout, raw race, final solve). --conflicts is a cap over their
  # SUM, not a per-stage allowance; 0 stays unlimited.
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
  # Cache the one full clause-shape pass immediately. Exact structural lanes
  # use it for constant-time admission gates, and ordinary routing reuses the
  # same object below instead of rescanning every unrelated formula.
  config = WassatConfig.from_lens(
    formula["nvars"], formula["flat_lens"], formula["flat_ncl"]
  )
  wrat_out = wassat_reserve_output(wrat_final, input, "WRAT")
  drat_out = nil
  begin
    drat_out = wassat_reserve_output(drat_final, input, "DRAT")
  rescue e
    wassat_discard_output(wrat_out, wrat_final)
    raise e
  # The canonical Hantzsche--Wendt instance is a complete group-ring product
  # circuit over two 93-bit supports. Construct Gardam's published unit and
  # inverse from the group law, replay every AND/parity auxiliary, and publish
  # only after checking all original clauses. Its exact header gate is nearly
  # free on every other task, so keep it ahead of broader structural scans.
  if env("WASSAT_HANTZSCHE_WENDT") != "0"
    hw = wassat_hantzsche_wendt_solve(formula)
    tprof = wassat_prof("cli.hantzsche_wendt", tprof)
    if hw["status"] == 1
      unless wassat_model_satisfies?(formula, hw["model"])
        raise "internal error: Hantzsche-Wendt model does not satisfy the input formula"
      wassat_discard_output(wrat_out, wrat_final)
      wassat_discard_output(drat_out, drat_final)
      hwtext = wassat_sat_text(hw["model"])
      wassat_status(quiet, hwtext.slice(0, hwtext.size - 1))
      wassat_status(quiet, "c mode: [wassat_mode_of(options)] (verified Hantzsche-Wendt group-ring unit)")
      wassat_status(quiet, "c hantzsche supports=[hw["support_left"]]+[hw["support_right"]], xor_rows=[hw["xor_rows"]], candidates=[hw["candidates"]]")
      wassat_status(quiet, "c conflicts: [budget_used], decisions: 0, props: 0")
      exit(10)

  # Distance-pruned knight-tour formulas expose exact-one position/square
  # supports and a complete transition fingerprint. Recover the unlabeled
  # knight graph, generate a tour with bounded Warnsdorff search, and complete
  # its small conditioned residual with the compact chronological lane.
  # This remains model-only and fail-closed: recognition, search, completion,
  # and full original-CNF replay must all succeed before publication.
  if (
    env("WASSAT_KNIGHT_TOUR") != "0" &&
    wassat_knight_side(config.max_clause_size) != 0 &&
    (options["conflicts"] == 0 || budget_used < options["conflicts"])
  )
    knight_cap = wassat_stage_conflict_cap(
      options["conflicts"], budget_used, WASSAT_KNIGHT_COMPLETION_CONFLICTS
    )
    knight = wassat_knight_tour_solve_budget(
      formula, knight_cap, WASSAT_KNIGHT_NODE_CAP
    )
    tprof = wassat_prof("cli.knight_tour", tprof)
    budget_used += knight["conflicts"]
    if knight["status"] == 1
      unless wassat_model_satisfies?(formula, knight["model"])
        raise "internal error: knight-tour model does not satisfy the input formula"
      wassat_discard_output(wrat_out, wrat_final)
      wassat_discard_output(drat_out, drat_final)
      kttext = wassat_sat_text(knight["model"])
      wassat_status(quiet, kttext.slice(0, kttext.size - 1))
      wassat_status(quiet, "c mode: [wassat_mode_of(options)] (verified distance-pruned knight tour)")
      wassat_status(quiet, "c knight side=[knight["side"]], positions=[knight["positions"]], tour_nodes=[knight["nodes"]]")
      wassat_status(quiet, "c conflicts: [budget_used], decisions: [knight["decisions"]], props: [knight["props"]]")
      exit(10)

  # The public puzzle32 encoding is a 32-move 5x5 sliding puzzle wrapped in a
  # repeated Tseitin transition circuit. Recover its Manhattan-optimal path,
  # condition an ordinary Wassat query on the 64 action bits, and publish only
  # the complete model after replaying every original clause.
  if env("WASSAT_SLIDING_PUZZLE") != "0" && (options["conflicts"] == 0 || budget_used < options["conflicts"])
    puzzle_cap = wassat_stage_conflict_cap(
      options["conflicts"], budget_used, WASSAT_PUZZLE_COMPLETION_CONFLICTS
    )
    puzzle = wassat_sliding_puzzle_solve_budget(formula, puzzle_cap)
    tprof = wassat_prof("cli.sliding_puzzle", tprof)
    budget_used += puzzle["conflicts"]
    if puzzle["status"] == 1
      unless wassat_model_satisfies?(formula, puzzle["model"])
        raise "internal error: sliding-puzzle model does not satisfy the input formula"
      wassat_discard_output(wrat_out, wrat_final)
      wassat_discard_output(drat_out, drat_final)
      ptext = wassat_sat_text(puzzle["model"])
      wassat_status(quiet, ptext.slice(0, ptext.size - 1))
      wassat_status(quiet, "c mode: [wassat_mode_of(options)] (verified 5x5 sliding-puzzle model)")
      wassat_status(quiet, "c puzzle moves=[puzzle["moves"]], nodes=[puzzle["nodes"]]")
      wassat_status(quiet, "c conflicts: [budget_used], decisions: [puzzle["decisions"]], props: [puzzle["props"]]")
      exit(10)
  # Compact Stedman/Erin triples instances expose a guarded deterministic
  # transition table over six types, one call bit per node, and short sequence
  # labels. Search the induced Hamiltonian cycle, condition ordinary Wassat on
  # its call/type choices, and publish only a replay-verified complete model.
  if env("WASSAT_STEDMAN") != "0" && (options["conflicts"] == 0 || budget_used < options["conflicts"])
    stedman_cap = wassat_stage_conflict_cap(
      options["conflicts"], budget_used, WASSAT_STEDMAN_COMPLETION_CONFLICTS
    )
    stedman = wassat_stedman_solve_budget(
      formula, WASSAT_STEDMAN_NODE_CAP, stedman_cap
    )
    tprof = wassat_prof("cli.stedman", tprof)
    budget_used += stedman["conflicts"]
    if stedman["status"] == 1
      unless wassat_model_satisfies?(formula, stedman["model"])
        raise "internal error: Stedman model does not satisfy the input formula"
      wassat_discard_output(wrat_out, wrat_final)
      wassat_discard_output(drat_out, drat_final)
      sttext = wassat_sat_text(stedman["model"])
      wassat_status(quiet, sttext.slice(0, sttext.size - 1))
      wassat_status(quiet, "c mode: [wassat_mode_of(options)] (verified Stedman triples model)")
      wassat_status(quiet, "c stedman transitions=[stedman["transitions"]], nodes=[stedman["nodes"]]")
      wassat_status(quiet, "c conflicts: [budget_used], decisions: [stedman["decisions"]], props: [stedman["props"]]")
      exit(10)
  # Canonical Fermat encodings expose their fixed difference in a strict
  # square/subtract circuit.  Run this verified model-only route before the
  # bounded local-core search: SAT models need no proof artifact, and a proof
  # invocation should not pay for an unrelated UNSAT search first.
  if env("WASSAT_FERMAT") != "0"
    fermat_model = wassat_fermat_model(formula)
    unless fermat_model.empty?
      unless wassat_model_satisfies?(formula, fermat_model)
        raise "internal error: Fermat circuit model does not satisfy the input formula"
      wassat_discard_output(wrat_out, wrat_final)
      wassat_discard_output(drat_out, drat_final)
      ftext = wassat_sat_text(fermat_model)
      wassat_status(quiet, ftext.slice(0, ftext.size - 1))
      wassat_status(quiet, "c mode: [wassat_mode_of(options)] (verified Fermat circuit model)")
      wassat_status(quiet, "c conflicts: [budget_used], decisions: 0, props: 0")
      exit(10)
  # Three canonical cube circuits followed by a fixed-width adder expose
  # their target in a regular unit suffix. Search a bounded non-negative cube
  # domain, complete the circuit under those operands, and publish only after
  # replaying the full original CNF. Keep this before local-core for the same
  # proof-mode reason as the Fermat model route above.
  if env("WASSAT_SUM3") != "0" && (options["conflicts"] == 0 || budget_used < options["conflicts"])
    sum3_cap = wassat_stage_conflict_cap(
      options["conflicts"], budget_used, WASSAT_SUM3_CONFLICT_CAP
    )
    sum3 = wassat_sum3_solve_budget(formula, sum3_cap)
    budget_used += sum3["conflicts"]
    if sum3["status"] == 1
      unless wassat_model_satisfies?(formula, sum3["model"])
        raise "internal error: sum-of-three-cubes model does not satisfy the input formula"
      wassat_discard_output(wrat_out, wrat_final)
      wassat_discard_output(drat_out, drat_final)
      s3text = wassat_sat_text(sum3["model"])
      wassat_status(quiet, s3text.slice(0, s3text.size - 1))
      wassat_status(quiet, "c mode: [wassat_mode_of(options)] (verified sum-of-three-cubes circuit model)")
      wassat_status(quiet, "c sum3 target=[sum3["target"]], operands=[sum3["x"]],[sum3["y"]],[sum3["z"]]")
      wassat_status(quiet, "c conflicts: [budget_used], decisions: [sum3["decisions"]], props: [sum3["props"]]")
      exit(10)
  # Minimum Disagreement Parity formulas expose complete GF(2) sample chains
  # followed by a canonical unary disagreement counter. Reconstruct the noisy
  # samples, run bounded information-set decoding, and condition an ordinary
  # Wassat query on the recovered hidden/corruption bits. This route is
  # model-only and publishes only after replaying the complete original CNF.
  if env("WASSAT_MDP") != "0"
    if options["conflicts"] == 0 || budget_used < options["conflicts"]
      mdp_cap = wassat_stage_conflict_cap(
        options["conflicts"], budget_used, WASSAT_MDP_CONFLICT_CAP
      )
      mdp = wassat_mdp_solve(formula, mdp_cap)
      tprof = wassat_prof("cli.mdp", tprof)
      budget_used += mdp["conflicts"]
      if mdp["status"] == 1
        unless wassat_model_satisfies?(formula, mdp["model"])
          raise "internal error: MDP model does not satisfy the input formula"
        wassat_discard_output(wrat_out, wrat_final)
        wassat_discard_output(drat_out, drat_final)
        mtext = wassat_sat_text(mdp["model"])
        wassat_status(quiet, mtext.slice(0, mtext.size - 1))
        wassat_status(quiet, "c mode: [wassat_mode_of(options)] (verified MDP model)")
        wassat_status(quiet, "c mdp bits=[mdp["bits"]], samples=[mdp["samples"]], disagreements=[mdp["disagreements"]]/[mdp["tolerated"]], trials=[mdp["trials"]]")
        wassat_status(quiet, "c conflicts: [budget_used], decisions: [mdp["decisions"]], props: [mdp["props"]]")
        exit(10)
  # Large generated instances can contain a compact contradiction among a
  # bounded star of ORIGINAL clauses.  Search that star in complete isolation:
  # SAT/UNKNOWN says nothing about the parent and only consumes budget, while
  # UNSAT lifts monotonically because every axiom is literally a full-formula
  # clause.  Original one-based clause ids and fresh ids above the full input
  # count make the same derivation independently checkable as WRAT/LRAT.
  if env("WASSAT_LOCAL_CORE") != "0" && (options["conflicts"] == 0 || budget_used < options["conflicts"])
    local_cap = wassat_stage_conflict_cap(
      options["conflicts"], budget_used, WASSAT_LOCAL_CORE_CONFLICT_CAP
    )
    local = wassat_local_core_refute(
      formula, proof_mode, local_cap,
      proof_mode == WASSAT_PROOF_WRAT && drat_final != nil
    )
    tprof = wassat_prof("cli.local_core", tprof)
    if local["recognized"]
      budget_used += local["conflicts"]
      if local["status"] == -1
        wtext = ""
        dtext = ""
        unless wrat_final == nil
          whead = header_wanted ? "wrat 1\n" : ""
          wbody = local["proof"].empty? ? "" : local["proof"].join("\n") + "\n"
          wtext = whead + wbody
          unless wrat_final == "-"
            raise "proof write failed at '[wrat_out]'" unless write_file(wrat_out, wtext)
            wassat_publish_output(wrat_out, wrat_final, "WRAT")
        unless drat_final == nil
          dtext = local["drat"].empty? ? "" : local["drat"].join("\n") + "\n"
          unless drat_final == "-"
            raise "proof write failed at '[drat_out]'" unless write_file(drat_out, dtext)
            wassat_publish_output(drat_out, drat_final, "DRAT")
        wassat_status(quiet, "s UNSATISFIABLE")
        wassat_status(quiet, "c mode: [wassat_mode_of(options)] (original-clause local-core refutation)")
        wassat_status(quiet, "c local core clauses=[local["clauses"].size], variables=[local["variables"]], prefix=[local["prefix"]]")
        wassat_status(quiet, "c conflicts: [budget_used], decisions: [local["decisions"]], props: [local["props"]]")
        print(wtext) if wrat_final == "-"
        print(dtext) if drat_final == "-"
        exit(20)
  # from_lens, not new(clauses): identical counters (adopt_counts consumes the
  # same histogram) without walking 10M boxed clauses on the critical path.
  # SAT models are their own certificate, so model-only structural engines run
  # in both modes.  In proof mode they discard the reserved empty proof sinks;
  # an unsuccessful recognition simply falls through to proof-producing CDCL.
  # Internal A/B hooks remain opt-outs, never required configuration.
  if env("WASSAT_MULTIPLIER") != "0"
    multiplier_model = wassat_multiplier_model(formula)
    unless multiplier_model.empty?
      unless wassat_model_satisfies?(formula, multiplier_model)
        raise "internal error: multiplier model does not satisfy the input formula"
      wassat_discard_output(wrat_out, wrat_final)
      wassat_discard_output(drat_out, drat_final)
      mtext = wassat_sat_text(multiplier_model)
      wassat_status(quiet, mtext.slice(0, mtext.size - 1))
      wassat_status(quiet, "c mode: [wassat_mode_of(options)] (verified multiplier circuit model)")
      wassat_status(quiet, "c conflicts: [budget_used], decisions: 0, props: 0")
      exit(10)
  # Bounded synchronizing-automaton encodings expose both transition maps in
  # their clause incidence.  Recover a Černý word directly, expand it to every
  # image/selector variable, and accept only a full original-CNF model.
  if env("WASSAT_AUTOMATA_SYNC") != "0"
    automata_model = wassat_automata_sync_model(formula)
    unless automata_model.empty?
      unless wassat_model_satisfies?(formula, automata_model)
        raise "internal error: synchronizing-automaton model does not satisfy the input formula"
      wassat_discard_output(wrat_out, wrat_final)
      wassat_discard_output(drat_out, drat_final)
      stext = wassat_sat_text(automata_model)
      wassat_status(quiet, stext.slice(0, stext.size - 1))
      wassat_status(quiet, "c mode: [wassat_mode_of(options)] (verified synchronizing-automaton model)")
      wassat_status(quiet, "c conflicts: [budget_used], decisions: 0, props: 0")
      exit(10)
  # Positive width-four domains plus complete negative ternary Latin
  # relations form an exact finite-domain CSP.  The bounded native engine is
  # enabled automatically. SAT models are verified against the original CNF;
  # trusted UNSAT is fast-only until this route emits a proof.
  if env("WASSAT_LATIN_CSP") != "0"
    latin = wassat_latin_csp_solve(formula)
    tprof = wassat_prof("cli.latin_csp", tprof)
    if latin["status"] == 1
      unless wassat_model_satisfies?(formula, latin["model"])
        raise "internal error: Latin CSP model does not satisfy the input formula"
      wassat_discard_output(wrat_out, wrat_final)
      wassat_discard_output(drat_out, drat_final)
      ltext = wassat_sat_text(latin["model"])
      wassat_status(quiet, ltext.slice(0, ltext.size - 1))
      wassat_status(quiet, "c mode: [wassat_mode_of(options)] (exact four-value Latin ternary CSP)")
      wassat_status(quiet, "c latin groups=[latin["groups"]], constraints=[latin["constraints"]], seeds=[latin["seeds"]], nodes=[latin["nodes"]], checks=[latin["checks"]]")
      wassat_status(quiet, "c conflicts: [budget_used], decisions: 0, props: 0")
      exit(10)
    elsif latin["status"] == -1 && proof_mode == WASSAT_PROOF_NONE
      << "s UNSATISFIABLE"
      << "c mode: fast (exact four-value Latin ternary CSP)"
      << "c latin groups=[latin["groups"]], constraints=[latin["constraints"]], seeds=[latin["seeds"]], nodes=[latin["nodes"]], checks=[latin["checks"]]"
      << "c conflicts: [budget_used], decisions: 0, props: 0"
      exit(20)
  # Exact-one triples plus complete forbidden-tuple blocks are a ternary
  # affine system. Strict recognition makes Gaussian elimination exact; the
  # SAT branch is still checked against the original Boolean formula.
  if env("WASSAT_TERNARY_AFFINE") != "0"
    affine = wassat_ternary_affine_solve(formula)
    if affine["status"] == 1
      unless wassat_model_satisfies?(formula, affine["model"])
        raise "internal error: ternary-affine model does not satisfy the input formula"
      wassat_discard_output(wrat_out, wrat_final)
      wassat_discard_output(drat_out, drat_final)
      atext = wassat_sat_text(affine["model"])
      wassat_status(quiet, atext.slice(0, atext.size - 1))
      wassat_status(quiet, "c mode: [wassat_mode_of(options)] (exact ternary affine GF(3) model)")
      wassat_status(quiet, "c affine groups=[affine["groups"]], equations=[affine["equations"]], rank=[affine["rank"]]")
      wassat_status(quiet, "c conflicts: [budget_used], decisions: 0, props: 0")
      exit(10)
    elsif affine["status"] == -1 && proof_mode == WASSAT_PROOF_NONE
      << "s UNSATISFIABLE"
      << "c mode: fast (exact ternary affine GF(3))"
      << "c affine groups=[affine["groups"]], equations=[affine["equations"]], rank=[affine["rank"]]"
      << "c conflicts: [budget_used], decisions: 0, props: 0"
      exit(20)
  # Compact edge-matching instances expose two exact placement partitions and
  # direct one-hot edge colors. Decode their conditioned orientation relations
  # and search the verified square-grid CSP before generic Boolean search.
  if env("WASSAT_EDGE_MATCHING") != "0"
    edge_match = wassat_edge_matching_solve(formula)
    tprof = wassat_prof("cli.edge_matching", tprof)
    if edge_match["status"] == 1
      unless wassat_model_satisfies?(formula, edge_match["model"])
        raise "internal error: edge-matching model does not satisfy the input formula"
      wassat_discard_output(wrat_out, wrat_final)
      wassat_discard_output(drat_out, drat_final)
      etext = wassat_sat_text(edge_match["model"])
      wassat_status(quiet, etext.slice(0, etext.size - 1))
      wassat_status(quiet, "c mode: [wassat_mode_of(options)] (verified compact edge-matching model)")
      wassat_status(quiet, "c edge grid=[edge_match["side"]]x[edge_match["side"]], cells=[edge_match["cells"]], edges=[edge_match["edges"]], nodes=[edge_match["nodes"]]")
      wassat_status(quiet, "c conflicts: [budget_used], decisions: 0, props: 0")
      exit(10)
  # A complete sequential at-most counter plus clique components can carry a
  # direct vertex-cover contradiction. This trusted certificate is exact but
  # has no emitted RUP derivation yet, so proof modes fall through to CDCL.
  if proof_mode == WASSAT_PROOF_NONE && env("WASSAT_AIS") != "0"
    ais = wassat_ais_unsat(formula)
    if ais["status"] == -1
      << "s UNSATISFIABLE"
      << "c mode: fast (exact sequential-counter clique-cover certificate)"
      << "c ais graph_vars=[ais["graph_vars"]], components=[ais["components"]], lower=[ais["lower_bound"]], upper=[ais["upper_bound"]]"
      << "c conflicts: [budget_used], decisions: 0, props: 0"
      exit(20)
  # Internal A/B opt-out; the automatic fast path is enabled by default.
  if proof_mode == WASSAT_PROOF_NONE && env("WASSAT_COLORING") != "0"
    clique_size = wassat_coloring_clique_unsat(formula)
    if clique_size > 0
      << "s UNSATISFIABLE"
      << "c mode: fast (verified [clique_size]-clique / [clique_size - 1]-color obstruction)"
      << "c conflicts: [budget_used], decisions: 0, props: 0"
      exit(20)
  # Exact conflict-constrained covering is a narrow, automatically recognized
  # family.  The deterministic node cap makes an unsuccessful attempt bounded;
  # zero means either a shape miss or cap exhaustion and falls through.
  if proof_mode == WASSAT_PROOF_NONE && env("WASSAT_COVERING") != "0"
    cover = wassat_covering_solve(formula)
    if cover["status"] != 0
      if cover["status"] == 1
        unless wassat_model_satisfies?(formula, cover["model"])
          raise "internal error: conflict-cover model does not satisfy the input formula"
        print(wassat_sat_text(cover["model"]))
      else
        << "s UNSATISFIABLE"
      << "c mode: fast (exact conflict-constrained covering)"
      << "c cover nodes=[cover["nodes"]], forced=[cover["forced"]]"
      << "c conflicts: [budget_used], decisions: 0, props: 0"
      exit(cover["status"] == 1 ? 10 : 20)
  # Ordered directed-kernel formulas decompose over their SCC DAG.  Commit
  # only locally unique components; an exact conditioned SCC refutation can
  # then decide the whole formula while multi-model and capped branches fall
  # through safely.
  if proof_mode == WASSAT_PROOF_NONE && env("WASSAT_DIRECTED_KERNEL") != "0"
    directed = wassat_directed_kernel_solve(formula)
    if directed["status"] != 0
      if directed["status"] == 1
        unless wassat_model_satisfies?(formula, directed["model"])
          raise "internal error: directed-kernel model does not satisfy the input formula"
        print(wassat_sat_text(directed["model"]))
      else
        << "s UNSATISFIABLE"
      << "c mode: fast (exact directed-kernel SCC prefix)"
      << "c directed components=[directed["components"]], checked=[directed["checked"]], unique=[directed["unique"]], multi=[directed["multi"]], nodes=[directed["nodes"]], forced=[directed["forced"]]"
      << "c conflicts: [budget_used], decisions: 0, props: 0"
      exit(directed["status"] == 1 ? 10 : 20)
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
      scout_conflicts = 0

      # Bounded CDCL scout (flat-load, so construction is native): many
      # structured instances decide within a few thousand conflicts on the
      # light kernel and skip the heavy rounds entirely (ibm-6: 1.3k).
      # Kernel size does NOT predict scout wins (ibm-6 at 368k clauses
      # decides in ~2.5k conflicts; ibm-12 at 195k never does) — so the
      # scout always runs with a small budget: a win skips the heavy
      # rounds outright, a miss costs ~0.15s.
      if probe_p == nil && (options["conflicts"] == 0 || budget_used < options["conflicts"])
        # On a raw kernel the scout is a bounded first shot: easy kernels
        # (ibm-6/10 class) decide inside it, and a miss falls through to
        # the diversified thread race below. On a preprocessed kernel it
        # stays a cheap scout whose miss pays for the heavy rounds.
        raw_probe = art["raw"] == true
        probe_wall = config.probe_ms(raw_probe)
        probe_cap = config.probe_conflicts(raw_probe)
        # Cap this stage (and every slice, including the first) at what remains
        # of the aggregate --conflicts budget after any local-core attempt.
        # This applies on raw AND reduced kernels, so a small budget is never
        # blown by the fixed 512-conflict first slice.
        if options["conflicts"] > 0
          remaining = options["conflicts"] - budget_used
          probe_cap = remaining if remaining < probe_cap
        # SCOUT RACE. One or two arms over the same artifact, each on its own
        # solver, concurrently: kissat's lucky phases (the four decision-free
        # dives of lucky.c, its `luckyearly` shot) when formula policy enables
        # them, and the bounded CDCL scout.
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
        scout_lucky = config.use_lucky
        # SLS always consumes an explicit RAW artifact, even when the CDCL
        # scout races a preprocessed rendering. This is built once on the
        # coordinator and shared by the scout and later race walkers.
        walk_art = art
        walk_art = wassat_raw_artifact(formula, scout_nv) unless art["raw"] == true
        scout_stop = i64[4]
        # Finite --conflicts work in the scout stage uses the same exact
        # lock-free ticket discipline as the later race: ordinary scout CDCL
        # owns slot 1 and optional frozen-fringe repair owns slot 2.
        scout_budget = nil
        if options["conflicts"] > 0
          scout_budget = i64[3]
        # Three slots: the lucky arm at 0, the SLS arm at scout_nv + 8, the
        # XOR-refutation arm at 2 * (scout_nv + 8).
        scout_res = i64[3 * (scout_nv + 8)]
        scout_sls_base = scout_nv + 8
        scout_xor_base = 2 * (scout_nv + 8)
        scout_out = []
        # The strict xorshift-circuit recognizer runs on the coordinator before
        # workers start: it touches boxed plan data only here, while the
        # partition workers receive scalars and typed arrays. A miss is nil and
        # leaves the established scout race byte-for-byte unchanged.
        scout_circuit = wassat_xs32_circuit_plan(scout_nv, formula)
        # Local search races the SCOUT, not just the raw arms behind it. The
        # scout is bounded by conflicts rather than wall clock on a raw kernel,
        # and on the dense low-variable formulas local search is best at, those
        # 2,000 conflicts are expensive: n320p5q2_n spends 748ms there while the
        # walker reaches a model in 6,610 flips. Racing it means a formula local
        # search cracks is answered before the scout's cap is even approached.
        lucky_h = nil
        if scout_lucky
          lucky_h = Thread.new -> wassat_lucky_arm_body(scout_nv, art, scout_res, 0, scout_stop)
        scout_h = Thread.new -> wassat_scout_arm_body(
          scout_nv, art, scout_stop, probe_cap, probe_wall, raw_probe,
          scout_simplify, scout_out, scout_budget, probe_cap, 1
        )
        scout_sls_h = nil
        scout_sls_flips = wassat_sls_arm_flips
        scout_sls_arenas = 0
        # Memory ceiling: a walker whose arena would be enormous costs every
        # OTHER arm more than it can win back. See wassat_sls_max_arena_mb.
        scout_sls_flips = 0 unless wassat_sls_arm_memory_allowed?(formula)
        # Count the ordinary CDCL arena and the optional lucky arena beside
        # the proposed walker instead of applying only a per-walker cap. A
        # disabled lucky arm must not consume either memory budget or startup
        # time: its lean from_flat still copies the complete formula.
        scout_cdcl_arenas = scout_lucky ? 2 : 1
        unless wassat_race_memory_fits?(formula, scout_cdcl_arenas, 1, 1)
          scout_sls_flips = 0
        if scout_sls_flips > 0
          scout_sls_arenas = 1
          scout_repair = false
          if System.physical_memory_bytes > 0
            scout_repair = wassat_sls_repair_eligible?(formula)
            scout_repair = wassat_race_memory_fits?(formula, 3, 1, 1) if scout_repair
          scout_sls_h = Thread.new -> wassat_sls_arm_body(
            scout_nv, formula, walk_art, scout_res, scout_sls_base,
            scout_stop, scout_sls_flips, 7, scout_repair, probe_cap,
            scout_budget, probe_cap, 2
          )
        # GE over whatever XOR constraint groups the formula carries; refutes
        # tseitin/parity kernels outright. Reads the ORIGINAL clause list, so
        # its verdict is about the input formula whichever rendering the other
        # arms are on.
        scout_xor_deadline = 0
        if scout_circuit == nil
          scout_xor_deadline = ccall("__w_clock_ms") + WASSAT_XOR_ARM_MAX_MS
        scout_xor_h = Thread.new -> wassat_xor_arm_body(
          scout_nv, formula, scout_res, scout_xor_base, scout_stop, nil,
          scout_circuit, scout_xor_deadline
        )
        z = lucky_h.join if lucky_h != nil
        z = scout_h.join
        # Exact-shape xorshift rows get one bounded full-domain preimage pass.
        # The measured family completes this in less time than generic search,
        # and a no-hit scan remains model-only/non-decisive. Other formulas
        # retain the old immediate cancellation below.
        z = scout_xor_h.join unless scout_circuit == nil
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
        #
        # A strict cluster of near-XOR rows is different: by the time its
        # release-published hint appears, the worker has already proved that
        # each derived row is implied by a uniquely owned binary subclause.
        # Let only that shape finish against its absolute 100ms arm deadline.
        # Ordinary formulas leave the hint at zero and pay no grace wait.
        if scout_circuit == nil && wassat_xor_grace_requested?(scout_res, scout_xor_base, scout_nv)
          z = scout_xor_h.join
        z = wassat_stop_cancel(scout_stop)
        z = scout_sls_h.join if scout_sls_h != nil
        z = scout_xor_h.join if scout_circuit == nil
        # Repair is real CDCL work even though it lives inside the model-only
        # SLS arm. Charge it whether the repair wins or the walk later falls
        # through, and retain the count in every early verdict below.
        if scout_budget == nil
          budget_used += scout_res[scout_sls_base + scout_nv + 7]
        else
          budget_used += ccall("__w_arr_load_acq", scout_budget, 0)
        # A GE refutation outranks everything: it is a verdict about the whole
        # input, costs zero conflicts, and cannot disagree with any other arm.
        if scout_res[scout_xor_base] == 0 - 1
          pre_msx = ccall("__w_clock_ms") - t0
          << "s UNSATISFIABLE"
          << "c mode: fast (xor refutation, [scout_res[scout_xor_base + scout_nv + 4]] parity rows)"
          << "c conflicts: [budget_used], decisions: 0, props: 0"
          << "c stats restarts=0 reduces=0 " + wassat_pre_stats_text(art["stats"], pre_msx)
          exit(20)
        # A consistent parity subsystem supplies a candidate only. The worker
        # publishes SAT after checking that candidate against every ORIGINAL
        # clause, so mixed XOR/non-XOR formulas remain sound without a brittle
        # syntactic coverage test.
        if scout_res[scout_xor_base] == 1
          pre_msx = ccall("__w_clock_ms") - t0
          xmodel = []
          v = 1
          while v <= scout_nv
            xmodel.push(
              scout_res[scout_xor_base + v] == 1 ? v : 0 - v
            )
            v += 1
          unless wassat_model_satisfies?(formula, xmodel)
            raise "internal error: xor arm model does not satisfy the input formula"
          print(wassat_sat_text(xmodel))
          if scout_res[scout_xor_base + scout_nv + 2] == 1
            << "c mode: fast (xorshift circuit model, [scout_res[scout_xor_base + scout_nv + 4]] gates)"
          else
            << "c mode: fast (xor model, [scout_res[scout_xor_base + scout_nv + 4]] parity rows)"
          << "c conflicts: [budget_used], decisions: 0, props: 0"
          << "c stats restarts=0 reduces=0 " + wassat_pre_stats_text(art["stats"], pre_msx)
          exit(10)
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
          print(wassat_sat_text(model))
          smode = "sls arm"
          smode = "sls frozen-fringe repair" if scout_res[scout_sls_base + scout_nv + 1] == 1
          << "c mode: fast ([smode])"
          << "c conflicts: [budget_used], decisions: 0, flips: [scout_res[scout_sls_base + scout_nv + 4]]"
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
            print(wassat_sat_text(model))
          else
            << "s UNSATISFIABLE"
          << "c mode: fast (lucky phases)"
          << "c conflicts: [budget_used], decisions: 0, props: [scout_res[scout_nv + 1]]"
          << "c stats restarts=0 reduces=0 " + wassat_pre_stats_text(art["stats"], pre_msl)
          exit(lucky_status == 1 ? 10 : 20)
        spr = scout_out[0]
        scout_solver = scout_out[1]
        scout_conflicts = spr["conflicts"]
        budget_used += scout_conflicts if scout_budget == nil
        if spr["status"] != 0
          pre_msq = ccall("__w_clock_ms") - t0
          if spr["status"] == 1
            model = wassat_reconstruct_model(light_stack, spr["model"], formula["nvars"])
            tprof = wassat_prof("cli.reconstruct", tprof)
            unless wassat_model_satisfies?(formula, model)
              raise "internal error: light-probe model does not satisfy the input formula"
            tprof = wassat_prof("cli.verify", tprof)
            print(wassat_sat_text(model))
            tprof = wassat_prof("cli.vline", tprof)
          else
            << "s UNSATISFIABLE"
          mode_tag = art["raw"] == true ? "raw cdcl" : "light+cdcl probe"
          << "c mode: fast ([mode_tag])"
          << "c conflicts: [budget_used], decisions: [spr["decisions"]], props: [spr["props"]]"
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
        sls_flips = 0 unless wassat_sls_arm_memory_allowed?(formula)
        # Completed scout allocations are still resident. The race walker is
        # accepted only if every planned raw/preprocessed solver, the scout's
        # ordinary and optional lucky solvers, the retained scout walker, and
        # this second walker fit together below the shared one-third-RAM
        # ceiling.
        race_cdcl_arenas = arms + pre_arms + scout_cdcl_arenas
        unless wassat_race_memory_fits?(
          formula, race_cdcl_arenas, scout_sls_arenas + 1,
          pre_arms + 1
        )
          sls_flips = 0
        race = nil
        if arms > 1 || pre_arms > 0 || sls_flips > 0
          continuation = config.continue_scout? ? scout_solver : nil
          continuation_spent = continuation == nil ? 0 : scout_conflicts
          race = wassat_race_build(formula["nvars"], art, arms, formula,
                                   continuation, continuation_spent, pre_arms,
                                   sls_flips > 0 ? 1 : 0, scout_cdcl_arenas,
                                   scout_sls_arenas, 1)
          wassat_race_add_sls(race, sls_flips, 7, walk_art) if sls_flips > 0
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
        # Every CDCL arm shares one lock-free ticket pool containing what
        # remains of the aggregate budget. The last ticket publishes
        # cancellation after its conflict is fully analyzed, so the race
        # neither multiplies the allowance by arm count nor overshoots it.
        # Zero keeps the race unlimited.
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
          arm_tag = "sls frozen-fringe repair" if rr["sls_repair_won"] == true
          if pidx >= 0
            spec = race["pre"][pidx]
            won_stack = spec["out"][0]
            won_stats = spec["out"][1]
            arm_tag = "[spec["label"]]-preprocessed arm"
          if rr["status"] == 1
            model = wassat_reconstruct_model(won_stack, rr["model"], formula["nvars"])
            unless wassat_model_satisfies?(formula, model)
              raise "internal error: race arm's model does not satisfy the input formula"
            print(wassat_sat_text(model))
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
          r2 = wassat_report_probe_win(prc, probe_out, light_stack, formula, art, t0, budget_used)
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
    wassat_status(quiet, "c conflicts: [budget_used], decisions: 0")
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
        r2 = wassat_report_probe_win(prc, probe_out, light_stack, formula, art, t0, budget_used)
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
    print(wassat_sat_text(r["model"]))
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
