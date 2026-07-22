# Tungsten Wassat -- a SAT solver that shows its work.
#
# Wassat decides propositional satisfiability and, when a formula is
# unsatisfiable, emits a refutation that an independent checker can replay.
# Proof logging is optional. Hinted `.wrat` carries the unit-propagation chain
# for every derived clause; raw `.drat` is the inexpensive interoperable mode.
#
# Usage:
#   wassat <problem.cnf>                   solve and report
#   wassat <problem.cnf> --proof <path>    also write a hinted .wrat proof
#   wassat <problem.cnf> --drat <path>     write a plain .drat proof
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
  << "    wassat <problem.cnf> --proof <path> --drat <path> --lookahead <n> --conflicts <n>"
  << "    wassat version"
  << "    wassat help"
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

# Parse and validate the options following the input path. A typo in a search
# limit must never silently turn a bounded job into an unlimited one.
-> wassat_cli_options(args)
  out = {
    "proof": nil,
    "drat": nil,
    "lookahead": 0,
    "conflicts": 0
  }
  seen = {}
  i = 1
  while i < args.size
    flag = args[i]
    unless flag == "--proof" || flag == "--drat" || flag == "--lookahead" || flag == "--conflicts"
      raise "unknown Wassat option: [flag]"
    raise "duplicate Wassat option: [flag]" if seen[flag] == true
    raise "missing value after [flag]" if i + 1 >= args.size
    value = args[i + 1]
    raise "missing value after [flag]" if value.starts_with?("--")
    seen[flag] = true
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
  if out["proof"] != nil && out["proof"] == out["drat"]
    raise "--proof and --drat need different destinations"
  out

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
    << "c parse error: [e]"
    << "s UNKNOWN"
    exit(1)

-> wassat_run_file_checked(args)
  options = wassat_cli_options(args)
  wrat_out = options["proof"]
  drat_out = options["drat"]
  wassat_prepare_output(wrat_out, args[0], "WRAT")
  wassat_prepare_output(drat_out, args[0], "DRAT")
  # Raw DRAT records learned clauses directly. Hinted WRAT costs a replayed
  # propagation per learned clause; request it only for --proof. If both
  # outputs are requested, the hinted proof can also be rendered as DRAT.
  proof_mode = WASSAT_PROOF_NONE
  proof_mode = WASSAT_PROOF_DRAT unless drat_out == nil
  proof_mode = WASSAT_PROOF_WRAT unless wrat_out == nil
  width = options["lookahead"]
  cap = options["conflicts"]
  cnf_text = read_file(args[0])
  raise "cannot read input formula '[args[0]]'" if cnf_text == nil
  result = wassat_solve_mode_limited(cnf_text, proof_mode, width, cap)
  print(wassat_result_text(result))
  << "c conflicts: [result["conflicts"]], decisions: [result["decisions"]]"

  if result["status"] == -1
    unless wrat_out == nil
      text = wassat_proof_text(result)
      wrat_out == "-" ? print(text) : write_file(wrat_out, text)
    unless drat_out == nil
      dtext = wassat_drat_text(result)
      drat_out == "-" ? print(dtext) : write_file(drat_out, dtext)
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
