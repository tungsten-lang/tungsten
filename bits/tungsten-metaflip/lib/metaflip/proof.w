# Public proof-library facade.
#
# The generic CDCL state is a caller-owned flat i64[] arena. Variables are
# one-based; a positive literal for variable v is 2*v and its negation is
# 2*v+1. `metaflip_proof_cdcl_solve` returns 1 (SAT), -1 (UNSAT), -2
# (budget/arena exhausted), or -3 (malformed input). A conflict budget below
# one is unlimited. Reserved capacity is not treated as logical formula state:
# the decision heap is rebuilt only through the highest referenced variable.
#
# The psi API proves or finds decompositions invariant under
#   (U,V,W) -> (V^T,U^T,W^T)
# for <n,m,n> matrix multiplication. The quotient encoder constrains one row
# per exact coefficient orbit; the full encoder retains all coefficient rows
# as an independent control. Both complete matmul encoders include sound
# generator ordering, pair orientation, the whole-target coordinate anchor,
# and the n=2 fixed-cell rank consequences. Arbitrary target tensors use only
# target-independent symmetry breaking.

use proof/cdcl
use proof/psi

# --- generic incremental CDCL -------------------------------------------------

-> metaflip_proof_cdcl_state_size(max_vars, max_clause_words) (i64 i64) i64
  ffcdcl_state_size(max_vars, max_clause_words)

-> metaflip_proof_cdcl_init(st, max_vars, seed) (i64[] i64 i64) i64
  ffcdcl_init(st, max_vars, seed)

-> metaflip_proof_cdcl_add_clause(st, lits, count) (i64[] i64[] i64) i64
  ffcdcl_add_clause(st, lits, count)

-> metaflip_proof_cdcl_add_xor(st, vars, count, rhs) (i64[] i64[] i64 i64) i64
  ffcdcl_add_xor(st, vars, count, rhs)

-> metaflip_proof_cdcl_solve(st, assumptions, count, conflict_budget) (i64[] i64[] i64 i64) i64
  ffcdcl_solve(st, assumptions, count, conflict_budget)

-> metaflip_proof_cdcl_value(st, variable) (i64[] i64) i64
  ffcdcl_value(st, variable)

-> metaflip_proof_cdcl_failed_assumptions(st, out_vars, capacity) (i64[] i64[] i64) i64
  ffcdcl_failed_assumptions(st, out_vars, capacity)

-> metaflip_proof_cdcl_reset(st) (i64[]) i64
  ffcdcl_reset(st)

-> metaflip_proof_cdcl_mark(st) (i64[]) i64
  ffcdcl_mark(st)

-> metaflip_proof_cdcl_release(st, mark) (i64[] i64) i64
  ffcdcl_release(st, mark)

-> metaflip_proof_cdcl_top_var(st) (i64[]) i64
  ffcdcl_top_var(st)

-> metaflip_proof_cdcl_conflicts(st) (i64[]) i64
  ffcdcl_conflicts(st)

-> metaflip_proof_cdcl_decisions(st) (i64[]) i64
  ffcdcl_decisions(st)

-> metaflip_proof_cdcl_clause_count(st) (i64[]) i64
  ffcdcl_clause_count(st)

-> metaflip_proof_cdcl_learnt_count(st) (i64[]) i64
  ffcdcl_learnt_count(st)

-> metaflip_proof_cdcl_dump_dimacs(st, path) (i64[] String) i64
  ffcdcl_dump_dimacs(st, path)

# --- exact psi quotient -------------------------------------------------------

-> metaflip_proof_psi_apply_u(u, v, w, n, m) (i64 i64 i64 i64 i64) i64
  ffpsi_apply_u(u, v, w, n, m)

-> metaflip_proof_psi_apply_v(u, v, w, n, m) (i64 i64 i64 i64 i64) i64
  ffpsi_apply_v(u, v, w, n, m)

-> metaflip_proof_psi_apply_w(u, v, w, n, m) (i64 i64 i64 i64 i64) i64
  ffpsi_apply_w(u, v, w, n, m)

-> metaflip_proof_psi_census(us, vs, ws, rank, n, m, profile) (i64[] i64[] i64[] i64 i64 i64 i64[]) i64
  ffpsi_census(us, vs, ws, rank, n, m, profile)

-> metaflip_proof_psi_verify(us, vs, ws, count, n, m) (i64[] i64[] i64[] i64 i64 i64) i64
  ffpsi_verify_rect(us, vs, ws, count, n, m, n)

-> metaflip_proof_psi_cell_mate(cell, n, m) (i64 i64 i64) i64
  ffpsi_cell_mate(cell, n, m)

-> metaflip_proof_psi_cell_orbit_count(n, m) (i64 i64) i64
  ffpsi_cell_orbit_count(n, m)

# Encode every coefficient row, then add only whole-matmul-safe symmetry and
# rank consequences. This is the independent control for the compact quotient.
-> metaflip_proof_psi_encode_full_matmul(sat, n, m, pairs, fixed) (i64[] i64 i64 i64 i64) i64
  if ffpsi_encode(sat, n, m, pairs, fixed) != 1
    return 0
  ffpsi_encode_matmul_sbps(sat, n, m, pairs, fixed)

# Encode one representative of each exact coefficient-cell orbit, including
# fixed-cell pair cancellation, then add the same whole-target consequences.
-> metaflip_proof_psi_encode_quotient_matmul(sat, n, m, pairs, fixed) (i64[] i64 i64 i64 i64) i64
  if ffpsi_encode_matmul_quotient(sat, n, m, pairs, fixed) != 1
    return 0
  ffpsi_encode_matmul_sbps(sat, n, m, pairs, fixed)

# Encode an arbitrary psi-invariant dense target bitset. The target-independent
# pair orientation and generator ordering remain sound; whole-matmul anchors
# and fixed-cell rank consequences are intentionally omitted.
-> metaflip_proof_psi_encode_target(sat, n, m, pairs, fixed, target) (i64[] i64 i64 i64 i64 i64[]) i64
  if ffpsi_encode_target(sat, n, m, pairs, fixed, target) != 1
    return 0
  ffpsi_encode_sbps(sat, n, m, pairs, fixed)

# Solve one whole-matmul psi cell with the exact coefficient quotient.
# meta[0..7] = top variable, clauses, status, conflicts, raw terms,
# compact rank, exact-gate flag, elapsed milliseconds.
-> metaflip_proof_psi_solve(n, m, pairs, fixed, conflict_budget, seed, out_u, out_v, out_w, meta) (i64 i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  ffpsi_solve(n, m, pairs, fixed, conflict_budget, seed, out_u, out_v, out_w, meta)
