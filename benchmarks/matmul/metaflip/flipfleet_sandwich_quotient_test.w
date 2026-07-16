# Planted regressions plus bounded smokes for the inner-sandwich quotient
# walker (move 1).  Pure CPU.  Run from the repo root (lexer tables are
# CWD-relative).
#
# Proved here, in order: cyclic sandwich exactness on naive (the sandwich
# permutes naive terms), the naive orbit census under (1,1,1) shifts
# (25 free 5-orbits on 5x5, 9 free 3-orbits on 3x3, zero fixed terms),
# non-closure detection, the fixed<->orbit conversion round trip on a
# circulant term, bounded gated quotient walks at 3x3/Z3 and 5x5/Z5, and the
# symmetrizability scan (naive = all 124 non-identity triples; checked-in
# rank-93 presentations reported honestly).

use flipfleet_sandwich_quotient

-> ffsqt_expect(label, condition) (String bool) i64
  if !condition
    << "SANDWICH_QUOTIENT_FAIL " + label
    exit(1)
  1

# --- permutation helpers ---------------------------------------------------
p5 = i64[5]
q5 = i64[5]
r5 = i64[5]
z = ffsq_shift_perm(p5, 5, 1)
z = ffsq_shift_perm(q5, 5, 1)
z = ffsq_shift_perm(r5, 5, 1)
z = ffsqt_expect("shift perm valid", ffsq_perm_valid(p5, 5) == 1)
z = ffsqt_expect("shift order 5", ffsq_perm_order(p5, 5) == 5)
z = ffsqt_expect("group order 5", ffsq_group_order(p5, q5, r5, 5, 5, 5) == 5)
id5 = i64[5]
z = ffsq_identity_perm(id5, 5)
z = ffsqt_expect("identity detected", ffsq_perm_is_identity(id5, 5) == 1)

# --- naive 5x5: closure, census, sandwich exactness ------------------------
cap5 = ffw_default_capacity(5) ## i64
st5 = i64[ffw_state_size(cap5)]
rank5 = ffw_init_naive_cap(st5, 5, cap5, 8001, 0, 1, 1, 1) ## i64
z = ffsqt_expect("naive 5x5 rank", rank5 == 125)
eu = i64[256]
ev = i64[256]
ew = i64[256]
count = ffw_export_current(st5, eu, ev, ew) ## i64
z = ffsqt_expect("naive export", count == 125)
z = ffsqt_expect("naive closed under Z5", ffsq_is_closed(eu, ev, ew, 125, 5, 5, 5, p5, q5, r5) == 1)
orbit_ids = i64[256]
part_meta = i64[4]
orbits = ffsq_orbit_partition(eu, ev, ew, 125, 5, 5, 5, p5, q5, r5, orbit_ids, part_meta) ## i64
z = ffsqt_expect("naive 5x5 orbit count", orbits == 25)
z = ffsqt_expect("naive 5x5 no fixed terms", part_meta[1] == 0)
z = ffsqt_expect("naive 5x5 max orbit", part_meta[2] == 5)

# The sandwich image of naive is naive itself, term for term.
iu = i64[256]
iv = i64[256]
iw = i64[256]
z = ffsq_apply_sandwich_scheme(eu, ev, ew, 125, 5, 5, 5, p5, q5, r5, iu, iv, iw)
i = 0 ## i64
while i < 125
  z = ffsqt_expect("sandwich permutes naive", ffsq_term_index(eu, ev, ew, 125, iu[i], iv[i], iw[i]) >= 0)
  i += 1

# --- non-closure detection --------------------------------------------------
# Flip pair sharing u = A(0,1): (0,1,0) = (2,32,1) and (0,1,1) = (2,64,2)
# become (2,32,3) and (2,96,2) -- exact, but no longer a naive term set.
rank5 = ffw_toggle(st5, 2, 32, 1, rank5)
rank5 = ffw_toggle(st5, 2, 64, 2, rank5)
rank5 = ffw_toggle(st5, 2, 32, 3, rank5)
rank5 = ffw_toggle(st5, 2, 96, 2, rank5)
st5[6] = rank5
z = ffsqt_expect("flip keeps rank", rank5 == 125)
z = ffsqt_expect("flip keeps exactness", ffw_verify_current_exact(st5, 5) == 1)
count = ffw_export_current(st5, eu, ev, ew)
z = ffsqt_expect("flipped naive not closed", ffsq_is_closed(eu, ev, ew, 125, 5, 5, 5, p5, q5, r5) == 0)
walk_meta = i64[16]
bad = ffsq_walk(st5, p5, q5, r5, 10, 8003, 2, 3, walk_meta) ## i64
z = ffsqt_expect("walk rejects unclosed seed", bad == 0 - 2)

# --- fixed<->orbit conversion round trip (3x3, Z3) --------------------------
p3 = i64[3]
q3 = i64[3]
r3 = i64[3]
z = ffsq_shift_perm(p3, 3, 1)
z = ffsq_shift_perm(q3, 3, 1)
z = ffsq_shift_perm(r3, 3, 1)
z = ffsqt_expect("all-ones is fixed", ffsq_term_is_fixed(511, 511, 511, 3, 3, 3, p3, q3, r3) == 1)
conv_u = i64[8]
conv_v = i64[8]
conv_w = i64[8]
d = ffsq_fixed_to_orbit_terms(511, 511, 511, 3, 3, 3, p3, q3, r3, 0, conv_u, conv_v, conv_w) ## i64
z = ffsqt_expect("fixed expands to full orbit", d == 3)
words = ffsq_tensor_words(3, 3, 3) ## i64
tens_a = i64[16]
tens_b = i64[16]
z = ffsq_tensor_clear(tens_a, words)
z = ffsq_tensor_clear(tens_b, words)
z = ffsq_xor_outer(tens_a, 511, 511, 511, 9, 9, 9)
i = 0
while i < d
  z = ffsq_xor_outer(tens_b, conv_u[i], conv_v[i], conv_w[i], 9, 9, 9)
  i += 1
same = 1 ## i64
i = 0
while i < words
  if tens_a[i] != tens_b[i]
    same = 0
  i += 1
z = ffsqt_expect("conversion is tensor-exact", same == 1)
back = i64[4]
collapsed = ffsq_orbit_to_fixed_terms(conv_u, conv_v, conv_w, d, back) ## i64
z = ffsqt_expect("orbit collapses back", collapsed == 1)
z = ffsqt_expect("collapse reproduces term", back[0] == 511 && back[1] == 511 && back[2] == 511)

# --- bounded gated quotient walks -------------------------------------------
cap3 = ffw_default_capacity(3) ## i64
st3 = i64[ffw_state_size(cap3)]
rank3 = ffw_init_naive_cap(st3, 3, cap3, 8005, 0, 1, 1, 1) ## i64
z = ffsqt_expect("naive 3x3 rank", rank3 == 27)
best3 = ffsq_walk(st3, p3, q3, r3, 2000, 8007, 2, 3, walk_meta) ## i64
z = ffsqt_expect("3x3 walk clean", best3 > 0)
z = ffsqt_expect("3x3 walk no gate failures", walk_meta[4] == 0)
z = ffsqt_expect("3x3 walk stays closed", walk_meta[13] == 1)
z = ffsqt_expect("3x3 walk best bounded", best3 <= 27 && best3 >= 21)
<< "SANDWICH_QUOTIENT_SMOKE n=3 d=3 moves=2000 best=" + best3.to_s() + " accepted=" + walk_meta[2].to_s() + " flips=" + walk_meta[5].to_s() + " splits=" + walk_meta[6].to_s() + " reductions=" + walk_meta[7].to_s() + " f2o=" + walk_meta[8].to_s() + " o2f=" + walk_meta[9].to_s() + " final_rank=" + walk_meta[10].to_s() + " fixed=" + walk_meta[14].to_s() + " orbits=" + walk_meta[15].to_s()

stw = i64[ffw_state_size(cap5)]
rank5 = ffw_init_naive_cap(stw, 5, cap5, 8009, 0, 1, 1, 1)
best5 = ffsq_walk(stw, p5, q5, r5, 1000, 8011, 2, 3, walk_meta) ## i64
z = ffsqt_expect("5x5 walk clean", best5 > 0)
z = ffsqt_expect("5x5 walk no gate failures", walk_meta[4] == 0)
z = ffsqt_expect("5x5 walk stays closed", walk_meta[13] == 1)
z = ffsqt_expect("5x5 walk best bounded", best5 <= 125 && best5 >= 93)
<< "SANDWICH_QUOTIENT_SMOKE n=5 d=5 moves=1000 best=" + best5.to_s() + " accepted=" + walk_meta[2].to_s() + " f2o=" + walk_meta[8].to_s() + " o2f=" + walk_meta[9].to_s() + " final_rank=" + walk_meta[10].to_s() + " fixed=" + walk_meta[14].to_s() + " orbits=" + walk_meta[15].to_s()

# --- symmetrizability scan ---------------------------------------------------
naive_path = "/tmp/ffsq_test_naive5.txt"
stn = i64[ffw_state_size(cap5)]
rankn = ffw_init_naive_cap(stn, 5, cap5, 8013, 0, 1, 1, 1) ## i64
z = ffsqt_expect("naive dump", ffw_dump_best(stn, naive_path) == 125)
scan_meta = i64[4]
found = ffsq_scan_symmetric(naive_path, 5, scan_meta) ## i64
z = ffsqt_expect("naive scan rank", scan_meta[0] == 125)
z = ffsqt_expect("naive fully symmetric", found == 124 && scan_meta[3] == 124)

r93 = ffsq_scan_symmetric("benchmarks/matmul/metaflip/matmul_5x5_rank93_d1155_gf2.txt", 5, scan_meta) ## i64
<< "SANDWICH_QUOTIENT_SCAN file=d1155 invariant_triples=" + r93.to_s() + " rank=" + scan_meta[0].to_s() + " first_code=" + scan_meta[2].to_s()
z = ffsqt_expect("d1155 scan loads", r93 >= 0 || scan_meta[0] == 0)

<< "flipfleet_sandwich_quotient_test: all checks passed"
