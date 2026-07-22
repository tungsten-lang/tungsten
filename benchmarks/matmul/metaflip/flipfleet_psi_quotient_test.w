# Planted regressions plus bounded smokes for the transpose-involution
# quotient (move 4).  Pure CPU, in-process CDCL only.  Run from the repo
# root.
#
# Plants, in order: psi is verified numerically as an automorphism on
# Strassen and naive <2,2,2> (image gates exactly); the census finds
# Strassen = 2 pairs + 3 fixed and naive = 2 pairs + 4 fixed; the (2,4)
# rank-8 and (2,3) rank-7 existence cells are SAT with gated witnesses,
# while the fixed-cell rank consequence closes (3,1).  The (3,0) rank-6
# cell is the independent planted UNSAT (rank 6 < R(2x2) = 7); and the
# <2,5,2> rank-17/18 target cells run as budget-bounded probes with honest
# labels.

use flipfleet_psi_quotient

-> ffpst_expect(label, condition) (String bool) i64
  if !condition
    << "PSI_QUOTIENT_FAIL " + label
    exit(1)
  1

-> ffpst_fill_strassen(us, vs, ws) (i64[] i64[] i64[]) i64
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
  7

-> ffpst_pair_psi_mask(mask, n, m) (i64 i64 i64) i64
  width = 2 * n * m + n * n ## i64
  out = 0 ## i64
  pos = 0 ## i64
  while pos < width
    if ((mask >> pos) & 1) == 1
      mapped = ffpsi_pair_psi_var(1, pos, n, m) - 1 ## i64
      out = out | (1 << mapped)
    pos += 1
  out

-> ffpst_mask_lex_le(left, right, width) (i64 i64 i64) i64
  pos = 0 ## i64
  while pos < width
    a = (left >> pos) & 1 ## i64
    b = (right >> pos) & 1 ## i64
    if a < b
      return 1
    if a > b
      return 0
    pos += 1
  1

su = i64[16]
sv = i64[16]
sw = i64[16]
r = ffpst_fill_strassen(su, sv, sw) ## i64
z = ffpst_expect("strassen exact by direct verifier", ffpsi_verify_rect(su, sv, sw, 7, 2, 2, 2) == 1)

# --- psi is an automorphism -----------------------------------------------------
iu = i64[16]
iv = i64[16]
iw = i64[16]
i = 0 ## i64
while i < 7
  iu[i] = ffpsi_apply_u(su[i], sv[i], sw[i], 2, 2)
  iv[i] = ffpsi_apply_v(su[i], sv[i], sw[i], 2, 2)
  iw[i] = ffpsi_apply_w(su[i], sv[i], sw[i], 2, 2)
  i += 1
z = ffpst_expect("psi image of strassen exact", ffpsi_verify_rect(iu, iv, iw, 7, 2, 2, 2) == 1)
z = ffpst_expect("psi fixes M1", ffpsi_is_fixed(9, 9, 9, 2, 2) == 1)
z = ffpst_expect("psi involution", ffpsi_apply_u(iu[3], iv[3], iw[3], 2, 2) == su[3] && ffpsi_apply_v(iu[3], iv[3], iw[3], 2, 2) == sv[3] && ffpsi_apply_w(iu[3], iv[3], iw[3], 2, 2) == sw[3])
z = ffpst_expect("coefficient quotient orbit counts", ffpsi_cell_orbit_count(2, 2) == 36 && ffpsi_cell_orbit_count(2, 5) == 210)
cell = 0 ## i64
while cell < 400
  mate = ffpsi_cell_mate(cell, 2, 5) ## i64
  z = ffpst_expect("coefficient action is involutive", mate >= 0 && mate < 400 && ffpsi_cell_mate(mate, 2, 5) == cell)
  cell += 1

# The primitive-variable orientation map is the same involution as the term
# action.  Exhaustive 2x2 masks establish that at least one orientation is
# canonical, and that both are admitted exactly for self-fixed generators.
z = ffpst_expect("pair psi map endpoints", ffpsi_pair_psi_var(100, 0, 2, 5) == 110 && ffpsi_pair_psi_var(100, 9, 2, 5) == 119)
z = ffpst_expect("pair psi map swaps factors", ffpsi_pair_psi_var(100, 10, 2, 5) == 100 && ffpsi_pair_psi_var(100, 19, 2, 5) == 109)
z = ffpst_expect("pair psi map transposes w", ffpsi_pair_psi_var(100, 20, 2, 5) == 120 && ffpsi_pair_psi_var(100, 21, 2, 5) == 122 && ffpsi_pair_psi_var(100, 22, 2, 5) == 121 && ffpsi_pair_psi_var(100, 23, 2, 5) == 123)
z = ffpst_expect("reduced orientation widths", ffpsi_pair_orientation_width(2, 2) == 5 && ffpsi_pair_orientation_width(2, 5) == 11)
pos = 0 ## i64
while pos < 24
  mapped = ffpsi_pair_psi_var(100, pos, 2, 5) - 100 ## i64
  z = ffpst_expect("pair psi variable map involution", mapped >= 0 && mapped < 24 && ffpsi_pair_psi_var(100, mapped, 2, 5) == 100 + pos)
  pos += 1
mask = 0 ## i64
while mask < 4096
  psi_mask = ffpst_pair_psi_mask(mask, 2, 2) ## i64
  forward = ffpst_mask_lex_le(mask, psi_mask, 12) ## i64
  reverse = ffpst_mask_lex_le(psi_mask, mask, 12) ## i64
  z = ffpst_expect("one pair orientation is canonical", forward == 1 || reverse == 1)
  z = ffpst_expect("self-fixed pair admits both orientations", (forward == 1 && reverse == 1) == (mask == psi_mask))
  mask += 1

# --- census ------------------------------------------------------------------------
# By hand: M1 = (9,9,9), M6 = (5,3,8), M7 = (10,12,1) are psi-fixed;
# {M2, M3} and {M4, M5} are conjugate pairs.  7 = 2*2 + 3.
profile = i64[4]
groups = ffpsi_census(su, sv, sw, 7, 2, 2, profile) ## i64
z = ffpst_expect("strassen census", groups == 5 && profile[0] == 2 && profile[1] == 3 && profile[2] == 1)
nu = i64[16]
nv = i64[16]
nw = i64[16]
nu[0] = 1
nv[0] = 1
nw[0] = 1
nu[1] = 1
nv[1] = 2
nw[1] = 2
nu[2] = 2
nv[2] = 4
nw[2] = 1
nu[3] = 2
nv[3] = 8
nw[3] = 2
nu[4] = 4
nv[4] = 1
nw[4] = 4
nu[5] = 4
nv[5] = 2
nw[5] = 8
nu[6] = 8
nv[6] = 4
nw[6] = 4
nu[7] = 8
nv[7] = 8
nw[7] = 8
groups = ffpsi_census(nu, nv, nw, 8, 2, 2, profile)
z = ffpst_expect("naive census", profile[0] == 2 && profile[1] == 4 && profile[2] == 1)

# In-process SBP accounting: two reduced pair-orientation chains, one pair
# sorting chain, and two fixed sorting chains use 33 fresh prefix variables
# and 198 clauses.  The whole-matmul fixed-cell consequences add nine XOR
# variables and 45 Tseitin/guard clauses; the anchor adds exactly the positive
# U(0,0) unit of the last sorted fixed block and no auxiliary.
sat_sbp = i64[ffcdcl_state_size(4096, 200000)]
z = ffpst_expect("SBP accounting init", ffcdcl_init(sat_sbp, 4096, 5499) == 1)
z = ffpst_expect("SBP accounting encode", ffpsi_encode(sat_sbp, 2, 2, 2, 3) == 1)
top_before_sbp = ffcdcl_top_var(sat_sbp) ## i64
clauses_before_sbp = ffcdcl_clause_count(sat_sbp) ## i64
z = ffpst_expect("whole-matmul fixed-cell rank consequences", ffpsi_encode_matmul_rank_consequences(sat_sbp, 2, 2, 2, 3) == 1)
z = ffpst_expect("fixed-cell consequence variable count", ffcdcl_top_var(sat_sbp) - top_before_sbp == 9)
z = ffpst_expect("fixed-cell consequence clause count", ffcdcl_clause_count(sat_sbp) - clauses_before_sbp == 45)
top_before_sbp = ffcdcl_top_var(sat_sbp)
clauses_before_sbp = ffcdcl_clause_count(sat_sbp)
z = ffpst_expect("orientation and sorting encode", ffpsi_encode_sbps(sat_sbp, 2, 2, 2, 3) == 1)
z = ffpst_expect("SBP fresh auxiliary count", ffpsi_sbp_aux_count(2, 2, 2, 3) == 33 && ffcdcl_top_var(sat_sbp) - top_before_sbp == 33)
z = ffpst_expect("SBP clause count", ffcdcl_clause_count(sat_sbp) - clauses_before_sbp == 198)
top_before_anchor = ffcdcl_top_var(sat_sbp) ## i64
clauses_before_anchor = ffcdcl_clause_count(sat_sbp) ## i64
z = ffpst_expect("whole-matmul coordinate anchor", ffpsi_encode_matmul_anchor(sat_sbp, 2, 2, 2, 3) == 1)
z = ffpst_expect("anchor is last fixed U00", ffpsi_fixed_base(2, 2, 4, 4, 4) == 41 && ffcdcl_top_var(sat_sbp) == top_before_anchor && ffcdcl_clause_count(sat_sbp) == clauses_before_anchor + 1)
anchor_neg = i64[1]
anchor_neg[0] = 2 * 41 + 1
z = ffpst_expect("anchor negative control clause", ffcdcl_add_clause(sat_sbp, anchor_neg, 1) == 1)
no_assumptions = i64[1]
z = ffpst_expect("anchor negative control UNSAT", ffcdcl_solve(sat_sbp, no_assumptions, 0, 1000) == 0 - 1)

# --- existence cells for <2,2,2> ------------------------------------------------------
out_u = i64[32]
out_v = i64[32]
out_w = i64[32]
meta = i64[16]
rank8 = ffpsi_solve(2, 2, 2, 4, 200000, 5501, out_u, out_v, out_w, meta) ## i64
z = ffpst_expect("(2,4) rank-8 cell SAT", meta[2] == 1)
z = ffpst_expect("(2,4) witness gates", meta[6] == 1 && rank8 >= 7 && rank8 <= 8)
<< "PSI_CELL c=2 f=4 rank=" + rank8.to_s() + " vars=" + meta[0].to_s() + " clauses=" + meta[1].to_s() + " conflicts=" + meta[3].to_s() + " ms=" + meta[7].to_s()

# Strassen itself witnesses (c=2, f=3), so this remains a planted SAT control
# after pair orientation, pair/fixed sorting, and the coordinate anchor.
rank7 = ffpsi_solve(2, 2, 2, 3, 400000, 5503, out_u, out_v, out_w, meta) ## i64
z = ffpst_expect("(2,3) rank-7 cell SAT", meta[2] == 1)
z = ffpst_expect("(2,3) witness gates at 7", meta[6] == 1 && rank7 == 7)
cens = ffpsi_census(out_u, out_v, out_w, 7, 2, 2, profile) ## i64
z = ffpst_expect("(2,3) witness is psi-symmetric", profile[2] == 1 && profile[1] >= 1)
<< "PSI_CELL c=2 f=3 rank=" + rank7.to_s() + " pairs=" + profile[0].to_s() + " fixed=" + profile[1].to_s() + " conflicts=" + meta[3].to_s() + " ms=" + meta[7].to_s()

# (3,1) is impossible: one fixed W diagonal cannot span the two-dimensional
# fixed-cell target.
rank7b = ffpsi_solve(2, 2, 3, 1, 200000, 5504, out_u, out_v, out_w, meta) ## i64
label31 = "indeterminate" ## String
if meta[2] == 1
  label31 = "sat"
if meta[2] == 0 - 1
  label31 = "certified-unsat-psi-class"
z = ffpst_expect("(3,1) probe terminates", rank7b >= 0)
if rank7b > 0
  z = ffpst_expect("(3,1) hit gates", meta[6] == 1 && rank7b == 7)
<< "PSI_CELL c=3 f=1 verdict=" + label31 + " rank=" + rank7b.to_s() + " conflicts=" + meta[3].to_s() + " ms=" + meta[7].to_s()

# The corresponding rank-6 cell remains a planted UNSAT control after the
# reduced pair-orientation leaders; f=0 also checks the no-anchor boundary.
rank6 = ffpsi_solve(2, 2, 3, 0, 400000, 5505, out_u, out_v, out_w, meta) ## i64
z = ffpst_expect("(3,0) rank-6 cell UNSAT", rank6 == 0 && meta[2] == 0 - 1)
<< "PSI_CELL c=3 f=0 verdict=certified-unsat conflicts=" + meta[3].to_s() + " ms=" + meta[7].to_s()

# --- <2,5,2> at-scale encoding control ----------------------------------------------------
# Naive <2,5,2> is psi-closed with 5 pairs + 10 fixed terms (i == k fixed).
# Pin every primary variable of the (5,10) cell to the naive witness with
# unit clauses: a sound encoding must propagate to SAT with zero search and
# decode back to an exact rank-20 scheme.  This validates the rectangular
# encoding independently of search hardness, so the negatives below can be
# trusted as certified class results.
sat_pin = i64[ffcdcl_state_size(60000, 900000)]
z = ffpst_expect("pin init", ffcdcl_init(sat_pin, 60000, 5506) == 1)
z = ffpst_expect("pin encode", ffpsi_encode(sat_pin, 2, 5, 5, 10) == 1)
unit = i64[2]
pr = 0 ## i64
while pr < 5
  # Pair representative: naive term (0, pr, 1): u bit pr, v bit 2*pr + 1,
  # w bit 1.
  base = ffpsi_pair_base(pr, 10, 10, 4) ## i64
  pos = 0 ## i64
  while pos < 10
    unit[0] = 2 * (base + pos) + 1
    if pos == pr
      unit[0] = 2 * (base + pos)
    z = ffcdcl_add_clause(sat_pin, unit, 1)
    pos += 1
  pos = 0
  while pos < 10
    unit[0] = 2 * (base + 10 + pos) + 1
    if pos == 2 * pr + 1
      unit[0] = 2 * (base + 10 + pos)
    z = ffcdcl_add_clause(sat_pin, unit, 1)
    pos += 1
  pos = 0
  while pos < 4
    unit[0] = 2 * (base + 20 + pos) + 1
    if pos == 1
      unit[0] = 2 * (base + 20 + pos)
    z = ffcdcl_add_clause(sat_pin, unit, 1)
    pos += 1
  pr += 1
fx = 0 ## i64
while fx < 10
  # Fixed terms: naive (i, j, i) enumerated as fx = i * 5 + j: u bit
  # i*5 + j, w bit i*2 + i = 3*i.
  base = ffpsi_fixed_base(5, fx, 10, 10, 4) ## i64
  i2 = fx / 5 ## i64
  j2 = fx % 5 ## i64
  pos = 0 ## i64
  while pos < 10
    unit[0] = 2 * (base + pos) + 1
    if pos == i2 * 5 + j2
      unit[0] = 2 * (base + pos)
    z = ffcdcl_add_clause(sat_pin, unit, 1)
    pos += 1
  pos = 0
  while pos < 4
    unit[0] = 2 * (base + 10 + pos) + 1
    if pos == 3 * i2
      unit[0] = 2 * (base + 10 + pos)
    z = ffcdcl_add_clause(sat_pin, unit, 1)
    pos += 1
  fx += 1
none = i64[1]
pinned = ffcdcl_solve(sat_pin, none, 0, 100000) ## i64
z = ffpst_expect("pinned naive witness SAT", pinned == 1)
raw = ffpsi_decode(sat_pin, 2, 5, 5, 10, out_u, out_v, out_w) ## i64
z = ffpst_expect("pinned decode count", raw == 20)
z = ffpst_expect("pinned witness exact", ffpsi_verify_rect(out_u, out_v, out_w, 20, 2, 5, 2) == 1)
<< "PSI_252 pinned-naive control sat=" + pinned.to_s() + " terms=" + raw.to_s()

# --- <2,5,2> target probes --------------------------------------------------------------
hit17 = ffpsi_solve(2, 5, 8, 1, 60000, 5507, out_u, out_v, out_w, meta) ## i64
label17 = "indeterminate" ## String
if meta[2] == 1
  label17 = "sat"
if meta[2] == 0 - 1
  label17 = "certified-unsat-psi-class"
<< "PSI_252 c=8 f=1 rank17 verdict=" + label17 + " rank=" + hit17.to_s() + " vars=" + meta[0].to_s() + " clauses=" + meta[1].to_s() + " conflicts=" + meta[3].to_s() + " ms=" + meta[7].to_s()
z = ffpst_expect("252 r17 probe terminates", hit17 >= 0)
if hit17 > 0
  z = ffpst_expect("252 r17 hit gates", meta[6] == 1 && hit17 <= 17)

hit18 = ffpsi_solve(2, 5, 8, 2, 60000, 5509, out_u, out_v, out_w, meta) ## i64
label18 = "indeterminate" ## String
if meta[2] == 1
  label18 = "sat"
if meta[2] == 0 - 1
  label18 = "certified-unsat-psi-class"
<< "PSI_252 c=8 f=2 rank18 verdict=" + label18 + " rank=" + hit18.to_s() + " conflicts=" + meta[3].to_s() + " ms=" + meta[7].to_s()
z = ffpst_expect("252 r18 probe terminates", hit18 >= 0)
if hit18 > 0
  z = ffpst_expect("252 r18 hit gates", meta[6] == 1 && hit18 <= 18)

<< "flipfleet_psi_quotient_test: all checks passed"
