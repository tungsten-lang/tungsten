# Focused packaged regression for the exact psi coefficient-orbit quotient.

use ../lib/metaflip/proof

-> proof_psi_expect(label, condition) (String bool) i64
  if !condition
    << "PROOF_PSI_FAIL " + label
    exit(1)
  1

us = i64[16]
vs = i64[16]
ws = i64[16]
# Strassen in the packaged U/V/W mask convention.
us[0] = 9
vs[0] = 9
ws[0] = 9
us[1] = 12
vs[1] = 1
ws[1] = 12
us[2] = 1
vs[2] = 10
ws[2] = 10
us[3] = 8
vs[3] = 5
ws[3] = 5
us[4] = 3
vs[4] = 8
ws[4] = 3
us[5] = 5
vs[5] = 3
ws[5] = 8
us[6] = 10
vs[6] = 12
ws[6] = 1

z = proof_psi_expect("strassen exact", metaflip_proof_psi_verify(us, vs, ws, 7, 2, 2) == 1) ## i64
profile = i64[4]
groups = metaflip_proof_psi_census(us, vs, ws, 7, 2, 2, profile) ## i64
z = proof_psi_expect("strassen psi census", groups == 5 && profile[0] == 2 && profile[1] == 3 && profile[2] == 1)
z = proof_psi_expect("coefficient orbit counts", metaflip_proof_psi_cell_orbit_count(2, 2) == 36 && metaflip_proof_psi_cell_orbit_count(2, 5) == 210)
cell = 0 ## i64
while cell < 400
  mate = metaflip_proof_psi_cell_mate(cell, 2, 5) ## i64
  z = proof_psi_expect("cell action involution", mate >= 0 && mate < 400 && metaflip_proof_psi_cell_mate(mate, 2, 5) == cell)
  cell += 1

# Preserve the complete-row control path: all 64 coefficient rows plus sound
# whole-matmul symmetry/rank consequences remain satisfiable at Strassen rank.
full = i64[metaflip_proof_cdcl_state_size(4096, 1000000)]
z = proof_psi_expect("full-row init", metaflip_proof_cdcl_init(full, 4096, 7201) == 1)
z = proof_psi_expect("full-row encode", metaflip_proof_psi_encode_full_matmul(full, 2, 2, 2, 3) == 1)
none = i64[1]
z = proof_psi_expect("full-row Strassen cell SAT", metaflip_proof_cdcl_solve(full, none, 0, 400000) == 1)

# The exact quotient must independently return and exhaustively gate a rank-7
# witness for the same cell.
out_u = i64[32]
out_v = i64[32]
out_w = i64[32]
meta = i64[16]
rank7 = metaflip_proof_psi_solve(2, 2, 2, 3, 400000, 7202, out_u, out_v, out_w, meta) ## i64
z = proof_psi_expect("quotient rank7 SAT", rank7 == 7 && meta[2] == 1 && meta[6] == 1)
z = proof_psi_expect("quotient witness exact", metaflip_proof_psi_verify(out_u, out_v, out_w, rank7, 2, 2) == 1)

# Whole-target fixed-cell rank consequences close the impossible one-fixed-term
# rank-7 partition immediately; rank 6 remains the independent UNSAT control.
rank31 = metaflip_proof_psi_solve(2, 2, 3, 1, 200000, 7203, out_u, out_v, out_w, meta) ## i64
z = proof_psi_expect("one-fixed rank consequence UNSAT", rank31 == 0 && meta[2] == 0 - 1)
rank6 = metaflip_proof_psi_solve(2, 2, 3, 0, 400000, 7204, out_u, out_v, out_w, meta) ## i64
z = proof_psi_expect("rank6 UNSAT", rank6 == 0 && meta[2] == 0 - 1)

<< "proof_psi_test: all checks passed"
