# Planted regressions plus bounded smokes for Hamming-ball anchored rank
# descent (move 11).  Pure CPU, in-process CDCL only.  Run from the repo
# root.
#
# Plants, in order: the split-above-Strassen anchor (rank 8, one flip above
# the optimum) must be UNSAT-CERTIFIED at radius 0 and SAT at radius 1 with
# the decoded scheme gating at rank 7; the sweep is deterministic under a
# fixed seed and builds its instance exactly once; the naive 2x2 anchor
# sweep and the naive 3x3 bounded probe report their statuses honestly with
# the certified/indeterminate labels.

use flipfleet_ball_sat

-> ffbst_expect(label, condition) (String bool) i64
  if !condition
    << "BALL_SAT_FAIL " + label
    exit(1)
  1

# Strassen with slot 0 split (u = 9 -> 1 | 8): exact rank 8, one two-to-one
# reduction above the rank-7 optimum.
-> ffbst_fill_anchor(us, vs, ws) (i64[] i64[] i64[]) i64
  us[0] = 1
  vs[0] = 9
  ws[0] = 9
  us[1] = 8
  vs[1] = 9
  ws[1] = 9
  us[2] = 12
  vs[2] = 1
  ws[2] = 12
  us[3] = 1
  vs[3] = 10
  ws[3] = 10
  us[4] = 8
  vs[4] = 5
  ws[4] = 5
  us[5] = 3
  vs[5] = 8
  ws[5] = 3
  us[6] = 5
  vs[6] = 3
  ws[6] = 8
  us[7] = 10
  vs[7] = 12
  ws[7] = 1
  8

au = i64[16]
av = i64[16]
aw = i64[16]
r = ffbst_fill_anchor(au, av, aw) ## i64

out_u = i64[16]
out_v = i64[16]
out_w = i64[16]
per_radius = i64[64]
meta = i64[16]

# --- planted descent ----------------------------------------------------------
hit = ffbs_sweep_terms(au, av, aw, 8, 2, 0, 1, 4, 200000, 3301, out_u, out_v, out_w, per_radius, meta) ## i64
z = ffbst_expect("planted hit rank", hit == 7)
z = ffbst_expect("planted radius-0 certified UNSAT", per_radius[0] == 0 && per_radius[1] == 0 - 1)
z = ffbst_expect("planted first SAT radius", meta[4] == 1)
z = ffbst_expect("planted decode count", meta[5] == 7)
z = ffbst_expect("planted gate", meta[7] == 1 && meta[6] == 7)
z = ffbst_expect("planted no indeterminate", meta[11] == 0)
z = ffbst_expect("planted one build", meta[9] == 1)
<< "BALL_SAT_PLANT hit=" + hit.to_s() + " first_sat_b=" + meta[4].to_s() + " vars=" + meta[1].to_s() + " clauses=" + meta[2].to_s() + " conflicts=" + meta[8].to_s() + " ms=" + meta[12].to_s()

# --- determinism ----------------------------------------------------------------
per2 = i64[64]
meta2 = i64[16]
hit2 = ffbs_sweep_terms(au, av, aw, 8, 2, 0, 1, 4, 200000, 3301, out_u, out_v, out_w, per2, meta2) ## i64
z = ffbst_expect("deterministic hit", hit2 == hit)
i = 0 ## i64
while i < meta2[3] * 3
  z = ffbst_expect("deterministic sweep", per2[i] == per_radius[i])
  i += 1

# --- naive 2x2 anchor sweep -------------------------------------------------------
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
hitn = ffbs_sweep_terms(nu, nv, nw, 8, 2, 4, 4, 16, 200000, 3305, out_u, out_v, out_w, per_radius, meta) ## i64
z = ffbst_expect("naive sweep terminates", hitn >= 0)
if hitn > 0
  z = ffbst_expect("naive hit gates", meta[7] == 1 && meta[6] == hitn && hitn <= 7)
<< "BALL_SAT_NAIVE22 hit=" + hitn.to_s() + " first_sat_b=" + meta[4].to_s() + " probes=" + meta[3].to_s() + " certified=" + meta[10].to_s() + " indeterminate=" + meta[11].to_s() + " conflicts=" + meta[8].to_s() + " ms=" + meta[12].to_s()

# --- path driver + publish dance ---------------------------------------------------
anchor_path = "/tmp/ffbs_test_anchor.txt"
out_path = "/tmp/ffbs_test_out.txt"
cap2 = ffw_default_capacity(2) ## i64
st = i64[ffw_state_size(cap2)]
z = ffbst_expect("anchor init", ffw_init_terms_cap(st, au, av, aw, 8, 2, cap2, 3307, 0, 1, 1, 1) == 8)
z = ffbst_expect("anchor dump", ffw_dump_best(st, anchor_path) == 8)
hitp = ffbs_sweep(anchor_path, 2, 0, 1, 4, 200000, 3309, out_path, per_radius, meta) ## i64
z = ffbst_expect("driver hit", hitp == 7)
reload = i64[ffw_state_size(cap2)]
z = ffbst_expect("driver output reloads", ffw_load_scheme_cap(reload, out_path, 2, cap2, 3311, 0, 1, 1, 1) == 7)
z = ffbst_expect("driver output exact", ffw_verify_best_exact(reload, 2) == 1)

# --- naive 3x3 bounded probe --------------------------------------------------------
cap3 = ffw_default_capacity(3) ## i64
st3 = i64[ffw_state_size(cap3)]
r3 = ffw_init_naive_cap(st3, 3, cap3, 3313, 0, 1, 1, 1) ## i64
n3path = "/tmp/ffbs_test_naive3.txt"
z = ffbst_expect("naive3 dump", ffw_dump_best(st3, n3path) == 27)
hit3 = ffbs_sweep(n3path, 3, 4, 4, 4, 20000, 3315, "", per_radius, meta) ## i64
z = ffbst_expect("naive3 probe terminates", hit3 >= 0)
label = "indeterminate" ## String
if per_radius[1] == 1
  label = "sat"
if per_radius[1] == 0 - 1
  label = "certified-unsat-r4-slot-aligned"
<< "BALL_SAT_NAIVE33 hit=" + hit3.to_s() + " b=4 verdict=" + label + " vars=" + meta[1].to_s() + " clauses=" + meta[2].to_s() + " conflicts=" + meta[8].to_s() + " ms=" + meta[12].to_s()

<< "flipfleet_ball_sat_test: all checks passed"
