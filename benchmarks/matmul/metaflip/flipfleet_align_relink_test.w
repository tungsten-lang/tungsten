# Planted regressions plus a bounded real-frontier smoke for align-then-relink
# pair convergence (move 12).  Pure CPU.  Run from the repo root.
#
# Plants, in order: overlap/distance counters on hand-built sets; a planted
# ORBIT EQUIVALENCE (S2 = row-swap sandwich image of Strassen, an exact
# automorphism the aligner's own generator set contains, so alignment must
# recover overlap == rank and PROVE equivalence); union nullity rising
# one-for-one with matched pairs; a planted one-flip pair that relink must
# reach at beta 0 (barrier height 0); and the honest d450/d677 4x4 rank-47
# bounded smoke (proven-inequivalent orbits: every result is a one-sided
# bound, reported as such).

use flipfleet_align_relink

-> ffart_expect(label, condition) (String bool) i64
  if !condition
    << "ALIGN_RELINK_FAIL " + label
    exit(1)
  1

# Strassen over GF(2), 2x2 masks (u bit i*2+j on A, v bit j*2+k on B,
# w bit i*2+k on the output cell).
-> ffart_fill_strassen(us, vs, ws) (i64[] i64[] i64[]) i64
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

# Swap the two I-rows of a 2x2 mask laid out with the I index major
# (bits 0,1 <-> bits 2,3).  Applying this to u and w of every term is the
# sandwich (P = row swap, Q = id, R = id): an exact matmul automorphism.
-> ffart_swap_rows(mask) (i64) i64
  ((mask & 3) << 2) | ((mask >> 2) & 3)

cap2 = ffw_default_capacity(2) ## i64
su = i64[8]
sv = i64[8]
sw = i64[8]
r = ffart_fill_strassen(su, sv, sw) ## i64

# --- counters on hand-built sets --------------------------------------------
z = ffart_expect("self overlap", ffar_overlap_count(su, sv, sw, 7, su, sv, sw, 7) == 7)
z = ffart_expect("self distance", ffar_distance(su, sv, sw, 7, su, sv, sw, 7) == 0)

tu = i64[8]
tv = i64[8]
tw = i64[8]
i = 0 ## i64
while i < 7
  tu[i] = ffart_swap_rows(su[i])
  tv[i] = sv[i]
  tw[i] = ffart_swap_rows(sw[i])
  i += 1
state_s = i64[ffw_state_size(cap2)]
state_t = i64[ffw_state_size(cap2)]
z = ffart_expect("strassen init", ffw_init_terms_cap(state_s, su, sv, sw, 7, 2, cap2, 901, 0, 1, 1, 1) == 7)
z = ffart_expect("strassen exact", ffw_verify_best_exact(state_s, 2) == 1)
z = ffart_expect("swap image init", ffw_init_terms_cap(state_t, tu, tv, tw, 7, 2, cap2, 903, 0, 1, 1, 1) == 7)
z = ffart_expect("swap image exact", ffw_verify_best_exact(state_t, 2) == 1)
d0 = ffar_distance(su, sv, sw, 7, tu, tv, tw, 7) ## i64
z = ffart_expect("swap image moved terms", d0 > 0)

# --- union nullity before alignment -----------------------------------------
nmeta = i64[8]
null_before = ffar_union_nullity(su, sv, sw, 7, tu, tv, tw, 7, 2, nmeta) ## i64
z = ffart_expect("union nullity precondition", null_before >= 1)

# --- planted orbit equivalence: alignment must prove it ----------------------
ops = i64[16]
doms = i64[16]
srcs = i64[16]
tgts = i64[16]
out_state = i64[ffw_state_size(cap2)]
ameta = i64[16]
overlap = ffar_align(state_s, state_t, 2, cap2, 4000, 8, 905, 1, ops, doms, srcs, tgts, out_state, ameta) ## i64
z = ffart_expect("alignment proves equivalence", overlap == 7)
z = ffart_expect("alignment distance zero", ameta[1] == 0)
z = ffart_expect("alignment image gated", ameta[6] == 1)
z = ffart_expect("alignment no verify failures", ameta[8] == 0)
gu = i64[8]
gv = i64[8]
gw = i64[8]
gcount = ffw_export_current(out_state, gu, gv, gw) ## i64
null_after = ffar_union_nullity(su, sv, sw, 7, gu, gv, gw, 7, 2, nmeta) ## i64
z = ffart_expect("aligned union nullity >= rank", null_after >= 7)
z = ffart_expect("alignment raises nullity", null_after > null_before)
<< "ALIGN_RELINK_PLANT overlap=" + overlap.to_s() + " word_len=" + ameta[2].to_s() + " tried=" + ameta[3].to_s() + " null_before=" + null_before.to_s() + " null_after=" + null_after.to_s()

# --- planted one-flip pair: relink reaches at beta 0 -------------------------
# Flip on the shared factor u = 9 of terms 0 (9,9,9) and none other... use
# naive 2x2 instead: terms (1,1,1) and (1,2,2) share u = 1; the flip child
# set replaces them by (1,1,3) and (1,3,2).
nu = i64[8]
nv = i64[8]
nw = i64[8]
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
fu = i64[8]
fv = i64[8]
fw = i64[8]
i = 0
while i < 8
  fu[i] = nu[i]
  fv[i] = nv[i]
  fw[i] = nw[i]
  i += 1
fv[0] = 1
fw[0] = 3
fv[1] = 3
fw[1] = 2
rmeta = i64[20]
approach = ffar_relink(nu, nv, nw, 8, fu, fv, fw, 8, 2, cap2, 20000, 0, 400, 907, 1000000, 0, "", 1, rmeta) ## i64
z = ffart_expect("relink reaches flip pair", approach == 0)
z = ffart_expect("relink barrier zero", rmeta[5] == 1 && rmeta[6] == 0)
z = ffart_expect("relink bookkeeping clean", rmeta[12] == 0)
z = ffart_expect("relink end exact", rmeta[15] == 1)
<< "ALIGN_RELINK_FLIP approach=" + approach.to_s() + " moves=" + rmeta[2].to_s() + " accepted=" + rmeta[3].to_s() + " beta_at_reach=" + rmeta[6].to_s()

# --- honest real smoke: the two inequivalent 4x4 rank-47 orbits --------------
cap4 = ffw_default_capacity(4) ## i64
sa = i64[ffw_state_size(cap4)]
sb = i64[ffw_state_size(cap4)]
ra = ffw_load_scheme_cap(sa, "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt", 4, cap4, 911, 0, 1, 1, 1) ## i64
rb = ffw_load_scheme_cap(sb, "benchmarks/matmul/metaflip/matmul_4x4_rank47_d677_flips_gf2.txt", 4, cap4, 913, 0, 1, 1, 1) ## i64
z = ffart_expect("d450 loads", ra == 47)
z = ffart_expect("d677 loads", rb == 47)
au = i64[64]
av = i64[64]
aw = i64[64]
bu = i64[64]
bv = i64[64]
bw = i64[64]
ca = ffw_export_current(sa, au, av, aw) ## i64
cb = ffw_export_current(sb, bu, bv, bw) ## i64
null44_before = ffar_union_nullity(au, av, aw, 47, bu, bv, bw, 47, 4, nmeta) ## i64
out_state4 = i64[ffw_state_size(cap4)]
overlap44 = ffar_align(sa, sb, 4, cap4, 1200, 8, 917, 0, ops, doms, srcs, tgts, out_state4, ameta) ## i64
z = ffart_expect("d450xd677 align clean", overlap44 >= 0)
z = ffart_expect("d450xd677 image gated", ameta[6] == 1)
hu = i64[64]
hv = i64[64]
hw = i64[64]
gcount = ffw_export_current(out_state4, hu, hv, hw)
null44_after = ffar_union_nullity(au, av, aw, 47, hu, hv, hw, 47, 4, nmeta) ## i64
<< "ALIGN_RELINK_SMOKE pair=d450xd677 overlap=" + overlap44.to_s() + " of 47 (one-sided) start_distance=" + ameta[0].to_s() + " best_distance=" + ameta[1].to_s() + " tried=" + ameta[3].to_s() + " null_before=" + null44_before.to_s() + " null_after=" + null44_after.to_s()

rmeta20 = i64[20]
approach44 = ffar_relink(au, av, aw, 47, hu, hv, hw, 47, 4, cap4, 60000, 2, 3000, 919, 1000000, 0, "", 0, rmeta20) ## i64
<< "ALIGN_RELINK_DEBUG start=" + rmeta20[0].to_s() + " closest=" + rmeta20[1].to_s() + " moves=" + rmeta20[2].to_s() + " acc=" + rmeta20[3].to_s() + " rej=" + rmeta20[4].to_s() + " book=" + rmeta20[12].to_s() + " caps=" + rmeta20[17].to_s() + " maxrank=" + rmeta20[10].to_s() + " endexact=" + rmeta20[15].to_s()
z = ffart_expect("relink 44 clean", approach44 >= 0)
z = ffart_expect("relink 44 bookkeeping", rmeta20[12] == 0)
z = ffart_expect("relink 44 end exact", rmeta20[15] == 1)
<< "ALIGN_RELINK_SMOKE relink closest_approach=" + approach44.to_s() + " (one-sided) reached=" + rmeta20[5].to_s() + " final_beta=" + rmeta20[7].to_s() + " escalations=" + rmeta20[13].to_s() + " max_rank=" + rmeta20[10].to_s()

<< "flipfleet_align_relink_test: all checks passed"
