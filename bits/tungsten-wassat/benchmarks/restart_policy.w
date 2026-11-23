# Research driver for restart_policy.py. Keeps learned clauses between
# requests and reports cumulative counters before the next root backjump.
use ../lib/wassat

-> duration_kernel(path, proof)
  f = wassat_parse_cnf_file_native(path)
  solver = Wassat.new(f["nvars"], wassat_formula_clauses(f), WASSAT_PROOF_DRAT, 0)
  solver.enable_focused_only
  solver.stream_proofs(nil, proof)
  while true
    command = gets()
    return 0 if command == nil || command == ""
    fields = command.split(" ")
    return 0 unless fields.size == 2
    arm = fields[0].to_i; budget = fields[1].to_i
    return 0 unless (arm == 0 || arm == 1) && budget > 0
    if arm == 0
      solver.disable_vmtf
    else
      solver.enable_vmtf
    r = solver.solve_budget(budget)
    status = r["status"]; conflicts = r["conflicts"]; decisions = r["decisions"]
    z = ccall("__w_eprint", "slice [status] [conflicts] [decisions]\n")
    if status == 1
      raise "invalid model" unless wassat_model_satisfies?(f, r["model"])
      wassat_print_sat_model(r["model"], false)
      return 10
    elsif status == -1
      solver.flush_proof_sinks
      << "s UNSATISFIABLE"
      return 20
    solver.backjump(0)
  0

av = argv()
exit(duration_kernel(av[0],av[1]))
