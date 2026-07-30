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
#   .wratb  packed Tungsten-native hints (same checks, smaller and streamable)
#   .lrat   same hinted body, no header
#   .drat   unhinted; checked by watched propagation with a RAT fallback
#
# Usage:
#   wrat <problem.cnf> <proof>      check a refutation
#   wrat pack <proof> <proof.wratb> pack hinted WRAT/LRAT
#   wrat version                    print the version
#   wrat help                       usage


use version
use dimacs
use proof
use stream
use packed
use checker

-> wrat_print_usage
  << "Tungsten Wrat [WRAT_VERSION] -- UNSAT proof checker"
  << ""
  << "USAGE"
  << "    wrat <problem.cnf> <proof.wrat|.lrat|.drat>"
  << "    wrat pack <proof.wrat|.lrat> <proof.wratb>"
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
  prf = File.mmap(proof_path)
  begin
    result = wrat_verify_mmap(cnf, prf)
    << "c format: [result["format"]], steps checked: [result["steps"]]"
    << "c storage: peak [result["peak_live_clauses"]] live clauses / [result["peak_live_literals"]] live literals; record buffers [result["peak_record_literals"]] literals / [result["peak_record_hints"]] hints"
    if result["verified"]
      << "s VERIFIED"
      0
    else
      << "c [result["reason"]]"
      << "s NOT VERIFIED"
      1
  ensure
    prf.close

-> wrat_pack_files(input_path, output_path)
  begin
    info = wrat_pack_file(input_path, output_path)
    << "c packed [info["additions"]] additions and [info["deletions"]] deletions"
    << "c bytes: [info["input_bytes"]] -> [info["output_bytes"]]"
    0
  rescue e
    << "c pack error: [e]"
    1

# Dispatch recognized command-line arguments. The executable entry point
# (bin/wrat.w) calls this explicitly; importing `use wrat` — including from
# another bit's regression specs — is side-effect free.
-> wrat_run_cli(args)
  cmd = nil
  cmd = args[0] if args.size > 0

  if cmd == "version" || cmd == "--version" || cmd == "-v"
    << "Tungsten Wrat [WRAT_VERSION]"
  elsif cmd == "help" || cmd == "--help" || cmd == "-h"
    wrat_print_usage
  elsif cmd == "pack" && args.size >= 3
    exit(wrat_pack_files(args[1], args[2]))
  elsif args.size >= 2
    exit(wrat_check_files(args[0], args[1]))
  else
    wrat_print_usage
    exit(1)
