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

-> wassat_print_usage
  << "Tungsten Wassat [WASSAT_VERSION] -- SAT solver with checkable proofs"
  << ""
  # Note: square brackets are string interpolation in Tungsten, so usage
  # text spells optional arguments without them.
  << "USAGE"
  << "    wassat <problem.cnf> --proof <path>     certificate-backed answers"
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
    "fast": false,
    "lookahead": 0,
    "conflicts": 0
  }
  seen = {}
  i = 0
  while i < args.size
    flag = args[i]
    if flag.starts_with?("--")
      unless flag == "--proof" || flag == "--drat" || flag == "--lookahead" || flag == "--conflicts" || flag == "--fast"
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
  if out["proof"] != nil && out["proof"] == out["drat"]
    raise "--proof and --drat need different destinations"
  if out["fast"] && (out["proof"] != nil || out["drat"] != nil)
    raise "--fast forgoes certificates; drop --fast or the proof options"
  if !out["fast"] && out["proof"] == nil && out["drat"] == nil
    raise "choose a mode: --proof <path> (or --drat <path>) for checkable answers, --fast for trusted ones"
  out

# The mode a parsed option set selects: "proof" or "fast". `--drat` implies
# proof mode -- it produces a certificate, just in the plain dialect.
-> wassat_mode_of(options)
  options["fast"] ? "fast" : "proof"

# Truncate requested certificate destinations before solving. Otherwise a SAT,
# UNKNOWN, parse failure, or interrupted rerun can leave an older refutation at
# the requested path and make it look like evidence for the current formula.
-> wassat_prepare_output(path, input_path, label)
  unless path == nil || path == "-"
    raise "[label] output must not overwrite the input formula" if path == input_path
    raise "cannot prepare [label] output at '[path]'" unless write_file(path, "")
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

-> wassat_run_file_checked(args)
  options = wassat_cli_options(args)
  input = options["input"]
  wrat_out = options["proof"]
  drat_out = options["drat"]
  wassat_prepare_output(wrat_out, input, "WRAT")
  wassat_prepare_output(drat_out, input, "DRAT")
  # Raw DRAT records learned clauses directly. Hinted WRAT costs a replayed
  # propagation per learned clause; request it only for --proof. If both
  # outputs are requested, the hinted proof can also be rendered as DRAT.
  proof_mode = WASSAT_PROOF_NONE
  proof_mode = WASSAT_PROOF_DRAT unless drat_out == nil
  proof_mode = WASSAT_PROOF_WRAT unless wrat_out == nil
  cnf_text = read_file(input)
  raise "cannot read input formula '[input]'" if cnf_text == nil
  formula = wassat_parse_cnf(cnf_text)
  s = Wassat.new(formula["nvars"], formula["clauses"], proof_mode, options["lookahead"])
  result = s.solve_budget(options["conflicts"])

  # Output integrity: a model is verified against the ORIGINAL formula before
  # anything is reported. A failing model is a solver bug and must surface as
  # a hard error here, never as a wrong `v` line a harness might trust.
  if result["status"] == 1
    unless wassat_model_satisfies?(formula, result["model"])
      raise "internal error: model does not satisfy the input formula"

  print(wassat_result_text(result))
  << "c mode: [wassat_mode_of(options)]"
  << "c conflicts: [result["conflicts"]], decisions: [result["decisions"]]"
  << "c stats restarts=[result["restarts"]] reduces=[result["reduces"]]"

  if result["status"] == -1
    unless wrat_out == nil
      text = wassat_proof_text(result)
      if wrat_out == "-"
        print(text)
      else
        raise "proof write failed at '[wrat_out]'" unless write_file(wrat_out, text)
    unless drat_out == nil
      dtext = wassat_drat_text(result)
      if drat_out == "-"
        print(dtext)
      else
        raise "proof write failed at '[drat_out]'" unless write_file(drat_out, dtext)
  0

# Dispatch recognized command-line arguments. The executable entry point calls
# this explicitly; importing `use wassat` is side-effect free.
-> wassat_run_cli(args)
  cmd = nil
  cmd = args[0] if args.size > 0

  if cmd == "version" || cmd == "--version" || cmd == "-v"
    << "Tungsten Wassat [WASSAT_VERSION]"
  elsif cmd == "help" || cmd == "--help" || cmd == "-h"
    wassat_print_usage
  elsif args.size >= 1
    wassat_run_file(args)
  else
    wassat_print_usage
    exit(1)
