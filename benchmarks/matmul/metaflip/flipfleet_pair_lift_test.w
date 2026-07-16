# Planted regressions plus a bounded real-frontier smoke for the pair-lift
# crossover (move 10).  Pure CPU.  Run from the repo root.
#
# Plants, in order: lifting naive+naive <2,2,2> gives an exact <2,2,4>
# rank-16 scheme whose zero-walk harvest returns both parents verbatim
# (distance 0); a single forced cross flip projects straight back to the
# parents (the documented no-op trap, asserted as distance 0); the
# Strassen+naive lift (rank 15) walks and harvests with both children
# gated; and the two checked-in <2,2,5> rank-18 doors lift to <2,2,10> for
# a 200k-move smoke whose mixing depth, harvests, and child distances are
# reported honestly (projection-unwind is the expected negative).

use flipfleet_pair_lift
use metaflip_rect_worker

-> ffplt_expect(label, condition) (String bool) i64
  if !condition
    << "PAIR_LIFT_FAIL " + label
    exit(1)
  1

-> ffplt_fill_naive(us, vs, ws) (i64[] i64[] i64[]) i64
  us[0] = 1
  vs[0] = 1
  ws[0] = 1
  us[1] = 1
  vs[1] = 2
  ws[1] = 2
  us[2] = 2
  vs[2] = 4
  ws[2] = 1
  us[3] = 2
  vs[3] = 8
  ws[3] = 2
  us[4] = 4
  vs[4] = 1
  ws[4] = 4
  us[5] = 4
  vs[5] = 2
  ws[5] = 8
  us[6] = 8
  vs[6] = 4
  ws[6] = 4
  us[7] = 8
  vs[7] = 8
  ws[7] = 8
  8

-> ffplt_fill_strassen(us, vs, ws) (i64[] i64[] i64[]) i64
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

xu = i64[64]
xv = i64[64]
xw = i64[64]
yu = i64[64]
yv = i64[64]
yw = i64[64]
c1u = i64[80]
c1v = i64[80]
c1w = i64[80]
c2u = i64[80]
c2v = i64[80]
c2w = i64[80]
meta = i64[20]

# --- lift identity + zero-walk harvest -------------------------------------------
r = ffplt_fill_naive(xu, xv, xw) ## i64
r = ffplt_fill_naive(yu, yv, yw)
lu = i64[20]
lv = i64[20]
lw = i64[20]
lifted = ffpl_lift(xu, xv, xw, 8, yu, yv, yw, 8, 2, 2, 2, lu, lv, lw) ## i64
z = ffplt_expect("lift count", lifted == 16)
z = ffplt_expect("lift exact as <2,2,4>", ffpl_verify_rect(lu, lv, lw, 16, 2, 2, 4) == 1)
ok = ffpl_run(xu, xv, xw, 8, yu, yv, yw, 8, 2, 2, 2, 0, 0, 9901, c1u, c1v, c1w, c2u, c2v, c2w, meta) ## i64
z = ffplt_expect("zero-walk children gate", ok == 1 && meta[9] == 1 && meta[13] == 1)
z = ffplt_expect("zero-walk children are parents", meta[10] == 0 && meta[14] == 0)

# --- the single-cross-flip no-op trap ----------------------------------------------
# Apply exactly ONE cross flip by hand on the lift (X term 0 and Y term 0
# share u = 1), then project: both mixed terms must project straight back
# to the parent terms -- the documented projection-unwind, measured.
lifted = ffpl_lift(xu, xv, xw, 8, yu, yv, yw, 8, 2, 2, 2, lu, lv, lw)
lw[0] = lw[0] ^ lw[8]
lv[8] = lv[8] ^ lv[0]
z = ffplt_expect("manual cross flip exact", ffpl_verify_rect(lu, lv, lw, 16, 2, 2, 4) == 1)
z = ffplt_expect("manual cross flip mixes", ffpl_mixed_count(lv, lw, 16, 2, 2, 2) == 2)
c1 = ffpl_project(lu, lv, lw, 16, 2, 2, 2, 0, c1u, c1v, c1w) ## i64
c2 = ffpl_project(lu, lv, lw, 16, 2, 2, 2, 1, c2u, c2v, c2w) ## i64
z = ffplt_expect("trap children gate", ffpl_verify_rect(c1u, c1v, c1w, c1, 2, 2, 2) == 1 && ffpl_verify_rect(c2u, c2v, c2w, c2, 2, 2, 2) == 1)
z = ffplt_expect("single cross flip unwinds", ffpl_distance(c1u, c1v, c1w, c1, xu, xv, xw, 8) == 0 && ffpl_distance(c2u, c2v, c2w, c2, yu, yv, yw, 8) == 0)
<< "PAIR_LIFT_TRAP mixed=2 d(child1,X)=0 d(child2,Y)=0 (the documented projection-unwind, measured)"

# --- Strassen + naive lift -----------------------------------------------------------
r = ffplt_fill_strassen(xu, xv, xw)
ok = ffpl_run(xu, xv, xw, 7, yu, yv, yw, 8, 2, 2, 2, 50000, 4, 9905, c1u, c1v, c1w, c2u, c2v, c2w, meta)
z = ffplt_expect("strassen+naive children gate", ok == 1 && meta[9] == 1 && meta[13] == 1)
z = ffplt_expect("strassen+naive lifted rank", meta[0] == 15)
<< "PAIR_LIFT_MIX pair=strassen+naive fired=" + meta[2].to_s() + " cross=" + meta[4].to_s() + " peak_mixed=" + meta[5].to_s() + " harvest_mixed=" + meta[6].to_s() + " forced=" + meta[7].to_s() + " c1=" + meta[8].to_s() + " d(c1,X)=" + meta[10].to_s() + " c2=" + meta[12].to_s() + " d(c2,Y)=" + meta[14].to_s() + " ms=" + meta[17].to_s()

# --- <2,2,5> doors to <2,2,10> ----------------------------------------------------------
cap = ffr_default_capacity(2, 2, 5) ## i64
sta = i64[ffr_state_size(cap)]
stb = i64[ffr_state_size(cap)]
ra = ffr_load_scheme_cap(sta, "benchmarks/matmul/metaflip/matmul_2x2x5_rank18_d84_gf2.txt", 2, 2, 5, cap, 9907, 0, 1, 1, 1) ## i64
rb = ffr_load_scheme_cap(stb, "benchmarks/matmul/metaflip/matmul_2x2x5_rank18_d88_gf2.txt", 2, 2, 5, cap, 9909, 0, 1, 1, 1) ## i64
if ra == 18 && rb == 18
  ca = ffw_export_current(sta, xu, xv, xw) ## i64
  cb = ffw_export_current(stb, yu, yv, yw) ## i64
  z = ffplt_expect("doors export", ca == 18 && cb == 18)
  ok = ffpl_run(xu, xv, xw, 18, yu, yv, yw, 18, 2, 2, 5, 200000, 4, 9911, c1u, c1v, c1w, c2u, c2v, c2w, meta)
  z = ffplt_expect("door children gate", ok == 1 && meta[9] == 1 && meta[13] == 1)
  << "PAIR_LIFT_SMOKE pair=225_d84xd88 lifted=" + meta[0].to_s() + " fired=" + meta[2].to_s() + " cross=" + meta[4].to_s() + " peak_mixed=" + meta[5].to_s() + " harvest_mixed=" + meta[6].to_s() + " forced=" + meta[7].to_s() + " c1=" + meta[8].to_s() + " d(c1,X)=" + meta[10].to_s() + " d(c1,Y)=" + meta[11].to_s() + " c2=" + meta[12].to_s() + " d(c2,Y)=" + meta[14].to_s() + " d(c2,X)=" + meta[15].to_s() + " ms=" + meta[17].to_s()
else
  << "PAIR_LIFT_SMOKE 225 doors not loadable (ra=" + ra.to_s() + " rb=" + rb.to_s() + "), skipping frontier leg"

<< "flipfleet_pair_lift_test: all checks passed"
