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
  << "    wrat to-drat <problem.cnf> <hinted-proof> <output.drat>"
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

# Replay before publishing. DRAT deletions need the live clause body for
# each proof id. Use the same database that validates the hinted additions.
-> wrat_export_drat(cnf_path, proof_path, dest)
  target = ccall("__w_file_id", dest)
  inputs = [cnf_path, proof_path]
  inputs.each -> (path)
    raise "output aliases an input" if dest == path || (target != nil && target == ccall("__w_file_id", path))
  mapping = File.mmap(proof_path)
  tmp = nil
  fp = nil
  begin
    scanner = wrat_scanner_for_mmap(mapping)
    raise "expected a hinted proof" unless scanner.hinted?
    ck = wrat_checker_for(wrat_parse_cnf(read_file(cnf_path)), scanner.format)
    ck.start_check
    tmp = ccall("__w_temp_file_for", dest)
    raise "could not reserve output" if tmp == nil
    fp = ccall("__w_file_handle_open", tmp, "wb")
    raise "could not open output" if fp == nil
    while scanner.advance
      continue if ck.check_done
      if scanner.kind == "d"
        scanner.hints.each -> (cid)
          body = ck.lits_for_id(cid)
          if body != nil
            line = body.empty? ? "d 0\n" : "d [body.join(" ")] 0\n"
            raise "short write" unless ccall("__w_file_handle_write", fp, line) == line.size
            ck.delete_id(cid)
      else
        raise "duplicate proof id [scanner.id]" if ck.slot_for_id(scanner.id) >= 0
        ck.consume_step("a", scanner.id, scanner.lits, scanner.hints)
        raise ck.check_reason if ck.check_done && !ck.check_verified
        line = scanner.lits.empty? ? "0\n" : "[scanner.lits.join(" ")] 0\n"
        raise "short write" unless ccall("__w_file_handle_write", fp, line) == line.size
    raise ck.check_reason unless ck.check_verified
    closed = ccall("__w_file_handle_close", fp)
    fp = nil
    raise "could not flush output" unless closed
    raise "could not publish output" unless ccall("__w_rename", tmp, dest)
    tmp = nil
    ck.check_count
  ensure
    z = ccall("__w_file_handle_close", fp) if fp != nil
    z = ccall("__w_unlink", tmp) if tmp != nil
    mapping.close

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
  elsif cmd == "to-drat"
    if args.size != 4
      wrat_print_usage
      exit(1)
    begin
      count = wrat_export_drat(args[1], args[2], args[3])
      << "c exported [count] checked additions"
    rescue e
      << "c export failed: [e]"
      exit(1)
  elsif cmd == "pack" && args.size >= 3
    exit(wrat_pack_files(args[1], args[2]))
  elsif args.size >= 2
    exit(wrat_check_files(args[0], args[1]))
  else
    wrat_print_usage
    exit(1)
