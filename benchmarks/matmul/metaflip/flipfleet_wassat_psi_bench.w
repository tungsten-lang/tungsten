# Native Wassat trial on Metaflip's exact psi quotient.
#
# This cross-bit benchmark builds the formula through Metaflip, solves the
# dumped DIMACS through Wassat, then pins Wassat's complete model back onto an
# independent Metaflip solver state so the ordinary psi decoder and exhaustive
# tensor gate remain authoritative.

use ../../../bits/tungsten-metaflip/lib/metaflip/proof
use ../../../bits/tungsten-wassat/lib/wassat

-> wpt_expect(label, condition) (String bool) i64
  if !condition
    << "WASSAT_PSI_FAIL " + label
    exit(1)
  1

-> wpt_build(n, m, pairs, fixed, path, seed) (i64 i64 i64 i64 String i64)
  max_vars = 60000 ## i64
  clause_words = 3000000 ## i64
  sat = i64[metaflip_proof_cdcl_state_size(max_vars, clause_words)]
  if metaflip_proof_cdcl_init(sat, max_vars, seed) != 1
    return 0 - 1
  if metaflip_proof_psi_encode_quotient_matmul(sat, n, m, pairs, fixed) != 1
    return 0 - 2
  written = metaflip_proof_cdcl_dump_dimacs(sat, path) ## i64
  if written < 0
    return 0 - 3
  written

-> wpt_solve_and_gate(n, m, pairs, fixed, path, expect_sat, seed) (i64 i64 i64 i64 String i64 i64) i64
  max_vars = 60000 ## i64
  clause_words = 3000000 ## i64
  sat = i64[metaflip_proof_cdcl_state_size(max_vars, clause_words)]
  if metaflip_proof_cdcl_init(sat, max_vars, seed) != 1
    return 0 - 1
  if metaflip_proof_psi_encode_quotient_matmul(sat, n, m, pairs, fixed) != 1
    return 0 - 2
  written = metaflip_proof_cdcl_dump_dimacs(sat, path) ## i64
  if written < 0
    return 0 - 3

  no_assumptions = i64[1]
  native_started = ccall("__w_clock_ms") ## i64
  native_status = metaflip_proof_cdcl_solve(sat, no_assumptions, 0, 400000) ## i64
  native_elapsed = ccall("__w_clock_ms") - native_started ## i64
  native_sat = native_status == 1 ? 1 : 0 ## i64
  << "FFCDCL_PSI_RESULT n=" + n.to_s() + " m=" + m.to_s() + " pairs=" + pairs.to_s() + " fixed=" + fixed.to_s() + " clauses=" + written.to_s() + " status=" + native_status.to_s() + " sat=" + native_sat.to_s() + " conflicts=" + metaflip_proof_cdcl_conflicts(sat).to_s() + " decisions=" + metaflip_proof_cdcl_decisions(sat).to_s() + " ms=" + native_elapsed.to_s()
  if native_status != (expect_sat == 1 ? 1 : 0 - 1)
    return 0 - 8

  started = ccall("__w_clock_ms") ## i64
  result = wassat_solve_opts(read_file(path), false)
  elapsed = ccall("__w_clock_ms") - started ## i64
  sat_flag = result["sat"] ? 1 : 0 ## i64
  << "WASSAT_PSI_RESULT n=" + n.to_s() + " m=" + m.to_s() + " pairs=" + pairs.to_s() + " fixed=" + fixed.to_s() + " vars=" + result["model"].size.to_s() + " clauses=" + written.to_s() + " sat=" + sat_flag.to_s() + " conflicts=" + result["conflicts"].to_s() + " decisions=" + result["decisions"].to_s() + " ms=" + elapsed.to_s()
  if sat_flag != expect_sat
    return 0 - 4
  if sat_flag == 0
    return 1

  # Pin the complete Wassat model as assumptions into the independently built
  # Metaflip state. This simultaneously rechecks every DIMACS clause and makes
  # the existing decoder available without trusting Wassat internals.
  model = result["model"]
  assumptions = i64[model.size]
  i = 0 ## i64
  while i < model.size
    lit = model[i] ## i64
    if lit > 0
      assumptions[i] = 2 * lit
    else
      assumptions[i] = 2 * (0 - lit) + 1
    i += 1
  if metaflip_proof_cdcl_solve(sat, assumptions, model.size, 1000) != 1
    return 0 - 5

  rank = 2 * pairs + fixed ## i64
  out_u = i64[rank + 4]
  out_v = i64[rank + 4]
  out_w = i64[rank + 4]
  decoded = ffpsi_decode(sat, n, m, pairs, fixed, out_u, out_v, out_w) ## i64
  if decoded != rank
    return 0 - 6
  if metaflip_proof_psi_verify(out_u, out_v, out_w, decoded, n, m) != 1
    return 0 - 7
  << "WASSAT_PSI_GATE rank=" + decoded.to_s() + " exact=1"
  1

-> wpt_ff_open(pairs, budget) (i64 i64) i64
  fixed = 17 - 2 * pairs ## i64
  max_vars = 60000 ## i64
  # Preserve the same 96-word-per-conflict headroom used by ffpsi_solve.
  clause_words = 3000000 + 96 * budget ## i64
  sat = i64[metaflip_proof_cdcl_state_size(max_vars, clause_words)]
  if metaflip_proof_cdcl_init(sat, max_vars, 88200 + pairs) != 1
    return 0 - 1
  if metaflip_proof_psi_encode_quotient_matmul(sat, 2, 5, pairs, fixed) != 1
    return 0 - 2
  none = i64[1]
  started = ccall("__w_clock_ms") ## i64
  status = metaflip_proof_cdcl_solve(sat, none, 0, budget) ## i64
  elapsed = ccall("__w_clock_ms") - started ## i64
  << "FFCDCL_PSI_OPEN pairs=" + pairs.to_s() + " fixed=" + fixed.to_s() + " status=" + status.to_s() + " conflicts=" + metaflip_proof_cdcl_conflicts(sat).to_s() + " decisions=" + metaflip_proof_cdcl_decisions(sat).to_s() + " ms=" + elapsed.to_s()
  1

args = argv()
mode = "controls" ## String
mode = args[0] if args.size > 0

if mode == "ff-open"
  pairs = 7 ## i64
  if args.size > 1
    pairs = args[1].to_i
  budget = 60000 ## i64
  if args.size > 2
    budget = args[2].to_i
  z = wpt_expect("ff open probe", wpt_ff_open(pairs, budget) == 1) ## i64
elsif mode == "export-open"
  pairs = 7 ## i64
  if args.size > 1
    pairs = args[1].to_i
  fixed = 17 - 2 * pairs ## i64
  path = "/tmp/wassat_psi252_r17_c" + pairs.to_s() + "f" + fixed.to_s() + ".cnf" ## String
  clauses = wpt_build(2, 5, pairs, fixed, path, 88100 + pairs) ## i64
  z = wpt_expect("open export", clauses > 0) ## i64
  << "WASSAT_PSI_EXPORT pairs=" + pairs.to_s() + " fixed=" + fixed.to_s() + " clauses=" + clauses.to_s() + " path=" + path
else
  z = wpt_expect("rank7 SAT + exact gate", wpt_solve_and_gate(2, 2, 2, 3, "/tmp/wassat_psi_222_c2f3.cnf", 1, 88001) == 1) ## i64
  z = wpt_expect("rank6 UNSAT", wpt_solve_and_gate(2, 2, 3, 0, "/tmp/wassat_psi_222_c3f0.cnf", 0, 88002) == 1)
  z = wpt_expect("one-fixed rank7 UNSAT", wpt_solve_and_gate(2, 2, 3, 1, "/tmp/wassat_psi_222_c3f1.cnf", 0, 88003) == 1)
  z = wpt_expect("252 c8f1 UNSAT", wpt_solve_and_gate(2, 5, 8, 1, "/tmp/wassat_psi_252_c8f1.cnf", 0, 88004) == 1)
  << "wassat_psi_trial: all controls passed"
