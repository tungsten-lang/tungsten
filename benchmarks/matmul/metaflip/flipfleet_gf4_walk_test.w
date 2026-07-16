# Planted regressions plus a bounded smoke for the GF(4) Frobenius walk
# (move 7).  Pure CPU.  Run from the repo root.
#
# Plants, in order: the full GF(4) multiplication table; conjugation is an
# involution fixing GF(2); gauge canonicalization preserves the tensor;
# Strassen as an all-rational GF(4) scheme (exact, Frobenius-closed,
# descended cost 7); harvest 1 reproduces exact GF(2) Strassen; harvest 2
# packs to the exact <2,2,4> rank-14 block record (verified by the lane's
# own rectangular gate); a planted genuine conjugate pair (one Strassen
# term split as w*t + (w+1)*t) whose Karatsuba harvest collapses back to
# exact rank 7; and a bounded gauge-aware walk on <2,2,2> that must keep
# every accepted state exact.

use flipfleet_gf4_walk

-> ffg4t_expect(label, condition) (String bool) i64
  if !condition
    << "GF4_WALK_FAIL " + label
    exit(1)
  1

# --- field table ------------------------------------------------------------------
# 0=0, 1=1, 2=w, 3=w+1.  w*w = w+1, w*(w+1) = 1, (w+1)*(w+1) = w.
z = ffg4t_expect("mul table", ffg4_mul(0, 3) == 0 && ffg4_mul(1, 2) == 2 && ffg4_mul(2, 2) == 3 && ffg4_mul(2, 3) == 1 && ffg4_mul(3, 3) == 2)
z = ffg4t_expect("inverses", ffg4_mul(2, ffg4_inv(2)) == 1 && ffg4_mul(3, ffg4_inv(3)) == 1 && ffg4_inv(1) == 1)
z = ffg4t_expect("conj involution", ffg4_conj_scalar(ffg4_conj_scalar(2)) == 2 && ffg4_conj_scalar(1) == 1 && ffg4_conj_scalar(0) == 0)
z = ffg4t_expect("conj is frobenius", ffg4_conj_scalar(2) == ffg4_mul(2, 2))

# --- Strassen as all-rational GF(4) -------------------------------------------------
tu_a = i64[32]
tu_b = i64[32]
tv_a = i64[32]
tv_b = i64[32]
tw_a = i64[32]
tw_b = i64[32]
su = i64[8]
sv = i64[8]
sw = i64[8]
su[0] = 9
sv[0] = 9
sw[0] = 9
su[1] = 12
sv[1] = 1
sw[1] = 12
su[2] = 1
sv[2] = 10
sw[2] = 10
su[3] = 8
sv[3] = 5
sw[3] = 5
su[4] = 3
sv[4] = 8
sw[4] = 3
su[5] = 5
sv[5] = 3
sw[5] = 8
su[6] = 10
sv[6] = 12
sw[6] = 1
i = 0 ## i64
while i < 7
  tu_a[i] = su[i]
  tu_b[i] = 0
  tv_a[i] = sv[i]
  tv_b[i] = 0
  tw_a[i] = sw[i]
  tw_b[i] = 0
  i += 1
z = ffg4t_expect("strassen exact over GF(4)", ffg4_verify_exact(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, 7, 2, 2, 2) == 1)
z = ffg4t_expect("strassen frobenius closed", ffg4_verify_frobenius_closed(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, 7, 4, 4) == 1)
profile = i64[4]
cost = ffg4_census(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, 7, 4, 4, profile) ## i64
z = ffg4t_expect("strassen census", profile[0] == 7 && profile[1] == 0 && cost == 7)

# --- gauge canonicalization preserves the tensor -------------------------------------
# Scale term 3 by (w, w+1, e) with e = inv(w * (w+1)) = inv(1) = 1.
tu_a[3] = ffg4_scale_a(su[3], 0, 2)
tu_b[3] = ffg4_scale_b(su[3], 0, 2)
tv_a[3] = ffg4_scale_a(sv[3], 0, 3)
tv_b[3] = ffg4_scale_b(sv[3], 0, 3)
z = ffg4t_expect("scaled scheme still exact", ffg4_verify_exact(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, 7, 2, 2, 2) == 1)
z = ffg4t_expect("canonicalize works", ffg4_canonicalize_term(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, 3, 4, 4) == 1)
z = ffg4t_expect("canonical form is rational form", tu_a[3] == su[3] && tu_b[3] == 0 && tv_a[3] == sv[3] && tv_b[3] == 0 && tw_a[3] == sw[3] && tw_b[3] == 0)
z = ffg4t_expect("canonicalized still exact", ffg4_verify_exact(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, 7, 2, 2, 2) == 1)

# --- harvest 1 on all-rational Strassen ------------------------------------------------
out_u = i64[32]
out_v = i64[32]
out_w = i64[32]
hmeta = i64[8]
emitted = ffg4_harvest_trace(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, 7, 4, 4, out_u, out_v, out_w, hmeta) ## i64
z = ffg4t_expect("trace emits 7", emitted == 7 && hmeta[0] == 7 && hmeta[1] == 0)
cap2 = ffw_default_capacity(2) ## i64
gate = i64[ffw_state_size(cap2)]
z = ffg4t_expect("trace loads", ffw_init_terms_cap(gate, out_u, out_v, out_w, 7, 2, cap2, 4401, 0, 1, 1, 1) == 7)
z = ffg4t_expect("trace gates", ffw_verify_current_exact(gate, 2) == 1)

# --- harvest 2: pack Strassen to <2,2,4> rank 14 ----------------------------------------
packed = ffg4_harvest_pack(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, 7, 2, 2, 2, out_u, out_v, out_w) ## i64
z = ffg4t_expect("pack emits 14", packed == 14)
z = ffg4t_expect("pack gates as <2,2,4>", ffg4_verify_rect(out_u, out_v, out_w, 14, 2, 2, 4) == 1)

# --- planted genuine conjugate pair -------------------------------------------------------
# Replace Strassen term 0 by the pair w*t0 + (w+1)*t0 (sum = t0 over GF(4)).
# The two members are conjugates of each other, so the scheme stays exact
# and Frobenius-closed with 6 rational terms + 1 pair (descended cost 9);
# the Karatsuba harvest of this degenerate pair collapses back to t0 and
# the full harvest gates at rank 7.
i = 0
while i < 7
  tu_a[i] = su[i]
  tu_b[i] = 0
  tv_a[i] = sv[i]
  tv_b[i] = 0
  tw_a[i] = sw[i]
  tw_b[i] = 0
  i += 1
# member A = w * t0: scale u by w.  member B = (w+1) * t0.
tu_a[0] = ffg4_scale_a(su[0], 0, 2)
tu_b[0] = ffg4_scale_b(su[0], 0, 2)
tu_a[7] = ffg4_scale_a(su[0], 0, 3)
tu_b[7] = ffg4_scale_b(su[0], 0, 3)
tv_a[7] = sv[0]
tv_b[7] = 0
tw_a[7] = sw[0]
tw_b[7] = 0
z = ffg4t_expect("pair scheme exact", ffg4_verify_exact(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, 8, 2, 2, 2) == 1)
z = ffg4t_expect("pair scheme closed", ffg4_verify_frobenius_closed(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, 8, 4, 4) == 1)
cost = ffg4_census(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, 8, 4, 4, profile)
z = ffg4t_expect("pair census", profile[0] == 6 && profile[1] == 1 && cost == 9)
emitted = ffg4_harvest_trace(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, 8, 4, 4, out_u, out_v, out_w, hmeta)
z = ffg4t_expect("pair harvest emits 7", emitted == 7 && hmeta[1] == 1)
z = ffg4t_expect("pair harvest loads", ffw_init_terms_cap(gate, out_u, out_v, out_w, 7, 2, cap2, 4403, 0, 1, 1, 1) == 7)
z = ffg4t_expect("pair harvest gates", ffw_verify_current_exact(gate, 2) == 1)

# --- bounded gauge-aware walk ----------------------------------------------------------
i = 0
while i < 7
  tu_a[i] = su[i]
  tu_b[i] = 0
  tv_a[i] = sv[i]
  tv_b[i] = 0
  tw_a[i] = sw[i]
  tw_b[i] = 0
  i += 1
wmeta = i64[12]
best = ffg4_walk(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, 7, 2, 2, 2, 20000, 4405, wmeta) ## i64
z = ffg4t_expect("walk clean", best > 0)
z = ffg4t_expect("walk no gate failures", wmeta[4] == 0)
z = ffg4t_expect("walk floor sane", best >= 7 && best <= 7)
z = ffg4t_expect("walk end exact", ffg4_verify_exact(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, wmeta[5], 2, 2, 2) == 1)
<< "GF4_WALK_SMOKE n=2 moves=20000 best_cost=" + best.to_s() + " proposals=" + wmeta[0].to_s() + " fired=" + wmeta[1].to_s() + " accepted=" + wmeta[2].to_s() + " final_count=" + wmeta[5].to_s() + " rational=" + wmeta[8].to_s() + " pairs=" + wmeta[9].to_s()

# Strassen is flip-isolated (all seven u factors projectively distinct), so
# fired must be 0 above.  Naive 2x2 shares u factors, so the fire path must
# exercise there with zero gate failures.
z = ffg4t_expect("strassen flip-isolated", wmeta[1] == 0)
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
i = 0
while i < 8
  tu_a[i] = nu[i]
  tu_b[i] = 0
  tv_a[i] = nv[i]
  tv_b[i] = 0
  tw_a[i] = nw[i]
  tw_b[i] = 0
  i += 1
best2 = ffg4_walk(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, 8, 2, 2, 2, 20000, 4407, wmeta) ## i64
<< "GF4_WALK_NAIVE_DEBUG best=" + best2.to_s() + " proposals=" + wmeta[0].to_s() + " fired=" + wmeta[1].to_s() + " accepted=" + wmeta[2].to_s() + " rejected=" + wmeta[3].to_s() + " gatefail=" + wmeta[4].to_s()
z = ffg4t_expect("naive walk fires", wmeta[1] > 0)
z = ffg4t_expect("naive walk no gate failures", wmeta[4] == 0)
z = ffg4t_expect("naive walk end exact", ffg4_verify_exact(tu_a, tu_b, tv_a, tv_b, tw_a, tw_b, wmeta[5], 2, 2, 2) == 1)
<< "GF4_WALK_SMOKE seed=naive fired=" + wmeta[1].to_s() + " accepted=" + wmeta[2].to_s() + " best_cost=" + best2.to_s() + " final_count=" + wmeta[5].to_s()

<< "flipfleet_gf4_walk_test: all checks passed"
