# Focused packaged regression for the generic in-process proof solver.

use ../lib/metaflip

-> proof_cdcl_expect(label, condition) (String bool) i64
  if !condition
    << "PROOF_CDCL_FAIL " + label
    exit(1)
  1

none = i64[1]

# Reserved arena capacity must not become logical search state. Only x1 and
# x2 occur, so the live-top decision heap must stop at variable two.
headroom = i64[metaflip_proof_cdcl_state_size(4096, 4096)]
z = proof_cdcl_expect("headroom init", metaflip_proof_cdcl_init(headroom, 4096, 7101) == 1) ## i64
pair = i64[2]
pair[0] = 2
pair[1] = 4
z = proof_cdcl_expect("headroom clause", metaflip_proof_cdcl_add_clause(headroom, pair, 2) == 1)
z = proof_cdcl_expect("live top variable", metaflip_proof_cdcl_top_var(headroom) == 2)
z = proof_cdcl_expect("headroom SAT", metaflip_proof_cdcl_solve(headroom, none, 0, 0) == 1)
z = proof_cdcl_expect("no capacity decisions", metaflip_proof_cdcl_decisions(headroom) <= 2)

# Native XOR ingestion: with x1=x2=0, x1^x2^x3=1 forces x3=1.
xor_sat = i64[metaflip_proof_cdcl_state_size(8, 4096)]
z = proof_cdcl_expect("xor init", metaflip_proof_cdcl_init(xor_sat, 8, 7102) == 1)
unit = i64[1]
unit[0] = 3
z = proof_cdcl_expect("pin x1 false", metaflip_proof_cdcl_add_clause(xor_sat, unit, 1) == 1)
unit[0] = 5
z = proof_cdcl_expect("pin x2 false", metaflip_proof_cdcl_add_clause(xor_sat, unit, 1) == 1)
xvars = i64[3]
xvars[0] = 1
xvars[1] = 2
xvars[2] = 3
z = proof_cdcl_expect("xor add", metaflip_proof_cdcl_add_xor(xor_sat, xvars, 3, 1) == 1)
z = proof_cdcl_expect("xor SAT", metaflip_proof_cdcl_solve(xor_sat, none, 0, 0) == 1)
z = proof_cdcl_expect("xor model", metaflip_proof_cdcl_value(xor_sat, 1) == 0 && metaflip_proof_cdcl_value(xor_sat, 2) == 0 && metaflip_proof_cdcl_value(xor_sat, 3) == 1)

# Incremental assumptions and failed-core extraction over (not a or not b).
incremental = i64[metaflip_proof_cdcl_state_size(4, 4096)]
z = proof_cdcl_expect("incremental init", metaflip_proof_cdcl_init(incremental, 4, 7103) == 1)
nand = i64[2]
nand[0] = 3
nand[1] = 5
z = proof_cdcl_expect("nand add", metaflip_proof_cdcl_add_clause(incremental, nand, 2) == 1)
assume = i64[2]
assume[0] = 2
assume[1] = 4
z = proof_cdcl_expect("assumption UNSAT", metaflip_proof_cdcl_solve(incremental, assume, 2, 0) == 0 - 1)
core = i64[4]
core_count = metaflip_proof_cdcl_failed_assumptions(incremental, core, 4) ## i64
z = proof_cdcl_expect("failed core", core_count >= 1 && core_count <= 2)
assume[0] = 3
assume[1] = 5
z = proof_cdcl_expect("reused database SAT", metaflip_proof_cdcl_solve(incremental, assume, 2, 0) == 1)

<< "proof_cdcl_test: all checks passed"
