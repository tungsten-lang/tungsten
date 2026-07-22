# Tungsten Wrat -- a proof checker for UNSAT certificates.
#
# Reads a DIMACS CNF and a refutation, and independently re-derives every
# step.  A solver saying "unsatisfiable" is a claim; a checked proof is
# evidence.  Wrat is deliberately small so that it is auditable: the whole
# checking core is a few hundred lines with no heuristics, and it shares no
# code with Wassat -- that independence is the entire point of a checker.
#
# Supported dialects:
#
#   .wrat   Tungsten-native, hinted (near-linear checking)
#   .lrat   same hinted body, no header
#   .drat   unhinted; checked by full propagation with a RAT fallback
#
# Usage:
#   wrat <problem.cnf> <proof>      check a refutation
#   wrat version                    print the version
#   wrat help                       usage


use version
use dimacs
use proof
use checker

-> wrat_print_usage
  << "Tungsten Wrat [WRAT_VERSION] -- UNSAT proof checker"
  << ""
  << "USAGE"
  << "    wrat <problem.cnf> <proof.wrat|.lrat|.drat>"
  << "    wrat version"
  << "    wrat help"
  << ""
  << "EXIT STATUS"
  << "    0  s VERIFIED"
  << "    1  s NOT VERIFIED"

# Check two files and print a drat-trim-style verdict. Returns the exit code.
-> wrat_check_files(cnf_path, proof_path)
  begin
    wrat_check_files_unchecked(cnf_path, proof_path)
  rescue e
    << "c parse error: [e]"
    << "s NOT VERIFIED"
    1

-> wrat_check_files_unchecked(cnf_path, proof_path)
  cnf = read_file(cnf_path)
  prf = read_file(proof_path)
  result = wrat_verify(cnf, prf)
  << "c format: [result["format"]], steps checked: [result["steps"]]"
  if result["verified"]
    << "s VERIFIED"
    0
  else
    << "c [result["reason"]]"
    << "s NOT VERIFIED"
    1

# wrat.w doubles as the bit manifest, so `use wrat` consumers execute this
# top-level call too -- it therefore acts ONLY on recognized arguments and
# is a silent no-op otherwise.
-> wrat_run_cli(args)
  cmd = nil
  cmd = args[0] if args.size > 0

  if cmd == "version" || cmd == "--version" || cmd == "-v"
    << "Tungsten Wrat [WRAT_VERSION]"
  elsif cmd == "help" || cmd == "--help" || cmd == "-h"
    wrat_print_usage
  elsif args.size >= 2
    exit(wrat_check_files(args[0], args[1]))

wrat_run_cli(argv())
