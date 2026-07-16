# Planted regressions plus bounded real-frontier smokes for the two-parent
# sector-swap suture crossover (move 8).  Pure CPU, no solver, no GPU, no
# live fleet.  Run from the repo root (lexer tables are CWD-relative).
#
# Plants: S is the naive 2x2 scheme (rank 8); T variants apply known exact
# flip rewrites (two terms sharing u: (u,v1,w1),(u,v2,w2) becomes
# (u,v1,w1^w2),(u,v1^v2,w2)).  Choosing an output-cell sector that captures
# only part of a rewrite forces a nonzero defect of known small rank, so the
# suture provably fires and the rank arithmetic is checked exactly.

use flipfleet_sector_suture

-> ffsst_expect(label, condition) (String bool) i64
  if !condition
    << "SECTOR_SUTURE_FAIL " + label
    exit(1)
  1

# Naive 2x2 terms in (i,k,j) order: u = A(i,k), v = B(k,j), w = C(i,j).
-> ffsst_fill_naive2(us, vs, ws) (i64[] i64[] i64[]) i64
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

cap2 = ffw_default_capacity(2) ## i64
size2 = ffw_state_size(cap2) ## i64

su = i64[8]
sv = i64[8]
sw = i64[8]
z = ffsst_fill_naive2(su, sv, sw) ## i64
state_s = i64[size2]
z = ffsst_expect("plant S init", ffw_init_terms_cap(state_s, su, sv, sw, 8, 2, cap2, 501, 0, 1, 1, 1) == 8)
z = ffsst_expect("plant S exact", ffw_verify_best_exact(state_s, 2) == 1)

# T1 = S with one flip at A(0,0): (1,1,1),(1,2,2) -> (1,1,3),(1,3,2).
t1u = i64[8]
t1v = i64[8]
t1w = i64[8]
z = ffsst_fill_naive2(t1u, t1v, t1w)
t1v[0] = 1
t1w[0] = 3
t1v[1] = 3
t1w[1] = 2
state_t1 = i64[size2]
z = ffsst_expect("plant T1 init", ffw_init_terms_cap(state_t1, t1u, t1v, t1w, 8, 2, cap2, 503, 0, 1, 1, 1) == 8)
z = ffsst_expect("plant T1 exact", ffw_verify_best_exact(state_t1, 2) == 1)

ou = i64[19]
ov = i64[19]
ow = i64[19]
meta = i64[16]

# Sector helper coverage.
z = ffsst_expect("sector count 2x2", ffss_sector_count(2, 2) == 8)
z = ffsst_expect("sector cell mask", ffss_sector_mask(2, 2, 0) == 1 && ffss_sector_mask(2, 2, 3) == 8)
z = ffsst_expect("sector column mask", ffss_sector_mask(2, 2, 4) == 5 && ffss_sector_mask(2, 2, 5) == 10)
z = ffsst_expect("sector row mask", ffss_sector_mask(2, 2, 6) == 3 && ffss_sector_mask(2, 2, 7) == 12)
z = ffsst_expect("sector out of range", ffss_sector_mask(2, 2, 8) == 0)
z = ffsst_expect("selector inside", ffss_selects(3, 3, 1) == 1 && ffss_selects(3, 1, 1) == 0 && ffss_selects(3, 1, 0) == 1)

# Case A: sigma = everything (intersect on all four output cells).
# Child must be exactly T1: zero defect, empty suture.
r = ffss_cross(state_s, state_t1, 15, 0, ou, ov, ow, meta) ## i64
z = ffsst_expect("sigma everything rank", r == 8)
z = ffsst_expect("sigma everything sectors", meta[0] == 8 && meta[1] == 8)
z = ffsst_expect("sigma everything defect", meta[3] == 0 && meta[4] == 0 && meta[5] == 0 && meta[12] == 0)
z = ffsst_expect("sigma everything gate", meta[10] == 1)
i = 0 ## i64
while i < 8
  z = ffsst_expect("sigma everything is T", ffss_term_in(ou, ov, ow, r, t1u[i], t1v[i], t1w[i]) == 1)
  i += 1

# Case B: sigma = nothing.  Child must be exactly S.
r = ffss_cross(state_s, state_t1, 0, 0, ou, ov, ow, meta)
z = ffsst_expect("sigma nothing rank", r == 8)
z = ffsst_expect("sigma nothing sectors", meta[0] == 0 && meta[1] == 0)
z = ffsst_expect("sigma nothing defect", meta[3] == 0 && meta[4] == 0)
z = ffsst_expect("sigma nothing gate", meta[10] == 1)
i = 0
while i < 8
  z = ffsst_expect("sigma nothing is S", ffss_term_in(ou, ov, ow, r, su[i], sv[i], sw[i]) == 1)
  i += 1

# Case C: intersect on output cell (0,0) (mask 1).  S_sigma = two terms
# with w bit 0; T_sigma = the flipped (1,1,3) plus the shared (2,4,1).
# Defect = 1 x 1 x 2, one coefficient, rank 1; suture (1,1,2) is
# off-dictionary; child rank 8 - 2 + 2 + 1 = 9 and must gate exactly.
r = ffss_cross(state_s, state_t1, 1, 0, ou, ov, ow, meta)
z = ffsst_expect("partial capture rank", r == 9)
z = ffsst_expect("partial capture sectors", meta[0] == 2 && meta[1] == 2 && meta[2] == 0)
z = ffsst_expect("partial capture defect", meta[3] == 1 && meta[4] == 1 && meta[12] == 2)
z = ffsst_expect("partial capture suture", meta[5] == 1 && meta[6] == 1 && meta[13] == 0)
z = ffsst_expect("partial capture off dictionary", meta[7] == 1)
z = ffsst_expect("partial capture arithmetic", meta[8] == 9 && meta[9] == 9)
z = ffsst_expect("partial capture gate", meta[10] == 1 && meta[11] > 0)
z = ffsst_expect("partial capture suture term", ffss_term_in(ou, ov, ow, r, 1, 1, 2) == 1)
z = ffsst_expect("partial capture swapped term", ffss_term_in(ou, ov, ow, r, 1, 1, 3) == 1)
z = ffsst_expect("partial capture removed term", ffss_term_in(ou, ov, ow, r, 1, 1, 1) == 0)

# Case D: inside mode on cell (0,0).  In S both w == 1 terms are inside; in
# T1 only (2,4,1) (the flipped w = 3 escapes).  Defect = 1 x 1 x 1, rank 1,
# suture (1,1,1) is on-dictionary and the child folds back to S at rank
# 8 - 2 + 1 + 1 = 8.
r = ffss_cross(state_s, state_t1, 1, 1, ou, ov, ow, meta)
z = ffsst_expect("inside mode rank", r == 8)
z = ffsst_expect("inside mode sectors", meta[0] == 2 && meta[1] == 1)
z = ffsst_expect("inside mode defect", meta[3] == 1 && meta[4] == 1)
z = ffsst_expect("inside mode on dictionary", meta[7] == 0)
z = ffsst_expect("inside mode arithmetic", meta[8] == 8 && meta[9] == 8)
z = ffsst_expect("inside mode gate", meta[10] == 1)
i = 0
while i < 8
  z = ffsst_expect("inside mode is S", ffss_term_in(ou, ov, ow, r, su[i], sv[i], sw[i]) == 1)
  i += 1

# Case E: T2 = S with flips at A(0,0) and A(1,1); intersect sector over
# output cells (0,0) and (1,0) (mask 5) captures half of each rewrite.
# Defect = 1x1x2 + 8x4x8: two independent u-slices, rank exactly 2; the
# complete rank-two recognizer must mint both sutures off-dictionary and
# the child gates at 8 - 4 + 4 + 2 = 10.
t2u = i64[8]
t2v = i64[8]
t2w = i64[8]
z = ffsst_fill_naive2(t2u, t2v, t2w)
t2v[0] = 1
t2w[0] = 3
t2v[1] = 3
t2w[1] = 2
t2v[6] = 4
t2w[6] = 12
t2v[7] = 12
t2w[7] = 8
state_t2 = i64[size2]
z = ffsst_expect("plant T2 init", ffw_init_terms_cap(state_t2, t2u, t2v, t2w, 8, 2, cap2, 505, 0, 1, 1, 1) == 8)
z = ffsst_expect("plant T2 exact", ffw_verify_best_exact(state_t2, 2) == 1)
r = ffss_cross(state_s, state_t2, 5, 0, ou, ov, ow, meta)
z = ffsst_expect("rank two defect rank", r == 10)
z = ffsst_expect("rank two defect sectors", meta[0] == 4 && meta[1] == 4)
z = ffsst_expect("rank two defect weight", meta[3] == 2 && meta[4] == 2 && meta[12] == 2)
z = ffsst_expect("rank two defect suture", meta[5] == 2 && meta[6] == 2 && meta[13] == 0)
z = ffsst_expect("rank two defect off dictionary", meta[7] == 2)
z = ffsst_expect("rank two defect arithmetic", meta[8] == 10 && meta[9] == 10)
z = ffsst_expect("rank two defect gate", meta[10] == 1)
z = ffsst_expect("rank two defect suture a", ffss_term_in(ou, ov, ow, r, 1, 1, 2) == 1)
z = ffsst_expect("rank two defect suture b", ffss_term_in(ou, ov, ow, r, 8, 4, 8) == 1)

# Case F: T4 = S with all four flips; the same mask-5 sector now captures
# four independent defect atoms (U-flattening dimension 4), beyond the
# rank-3 recognizer reach: the move must abstain, not guess.
t4u = i64[8]
t4v = i64[8]
t4w = i64[8]
z = ffsst_fill_naive2(t4u, t4v, t4w)
t4v[0] = 1
t4w[0] = 3
t4v[1] = 3
t4w[1] = 2
t4v[2] = 4
t4w[2] = 3
t4v[3] = 12
t4w[3] = 2
t4v[4] = 1
t4w[4] = 12
t4v[5] = 3
t4w[5] = 8
t4v[6] = 4
t4w[6] = 12
t4v[7] = 12
t4w[7] = 8
state_t4 = i64[size2]
z = ffsst_expect("plant T4 init", ffw_init_terms_cap(state_t4, t4u, t4v, t4w, 8, 2, cap2, 507, 0, 1, 1, 1) == 8)
z = ffsst_expect("plant T4 exact", ffw_verify_best_exact(state_t4, 2) == 1)
r = ffss_cross(state_s, state_t4, 5, 0, ou, ov, ow, meta)
z = ffsst_expect("abstain result", r == 0)
z = ffsst_expect("abstain defect", meta[4] == 0 - 1 && meta[14] == 1)

# Case G: invalid inputs.
state_s3 = i64[ffw_state_size(ffw_default_capacity(3))]
z = ffsst_expect("plant 3x3 naive", ffw_init_naive_cap(state_s3, 3, ffw_default_capacity(3), 509, 0, 1, 1, 1) == 27)
r = ffss_cross(state_s, state_s3, 1, 0, ou, ov, ow, meta)
z = ffsst_expect("shape mismatch rejected", r == 0 - 1 && meta[14] == 3)
r = ffss_cross_terms(su, sv, sw, 8, t1u, t1v, t1w, 8, 2, 2, 2, 1, 2, ou, ov, ow, meta)
z = ffsst_expect("bad mode rejected", r == 0 - 1 && meta[14] == 3)
r = ffss_cross_terms(su, sv, sw, 8, t1u, t1v, t1w, 8, 2, 2, 2, 999, 0, ou, ov, ow, meta)
z = ffsst_expect("bad mask rejected", r == 0 - 1 && meta[14] == 3)

# Publication dance: stale output cleared, valid child re-parses and
# re-gates, tampered child is refused and leaves nothing behind.
child_path = "/tmp/ffss_test_child.txt"
r = ffss_cross(state_s, state_t1, 1, 0, ou, ov, ow, meta)
z = ffsst_expect("publish source rank", r == 9)
z = ffsst_expect("stale write", write_file(child_path, "stale content"))
z = ffsst_expect("publish accepts", ffss_publish(ou, ov, ow, r, 2, 2, 2, child_path, 605) == 9)
state_reload = i64[size2]
z = ffsst_expect("publish reload", ffw_load_scheme_cap(state_reload, child_path, 2, cap2, 607, 0, 1, 1, 1) == 9)
z = ffsst_expect("publish regate", ffw_verify_best_exact(state_reload, 2) == 1)
bad_u = i64[19]
i = 0
while i < r
  bad_u[i] = ou[i]
  i += 1
bad_u[0] = 15
z = ffsst_expect("stale rewrite", write_file(child_path, "stale again"))
z = ffsst_expect("tampered publish rejected", ffss_publish(bad_u, ov, ow, r, 2, 2, 2, child_path, 611) == 0 - 1)
z = ffsst_expect("tampered output cleared", ffss_file_has_scheme(child_path) == 0)

# Planted sweep: S x T1 over all 8 sectors x 2 modes x 2 orientations.
# Every non-abstained child must pass the exhaustive gate.
plant_a = "/tmp/ffss_parent_s.txt"
plant_b = "/tmp/ffss_parent_t1.txt"
z = ffsst_expect("plant dump S", ffw_dump_best(state_s, plant_a) == 8)
z = ffsst_expect("plant dump T1", ffw_dump_best(state_t1, plant_b) == 8)
hist = i64[5]
counters = i64[16]
wins = ffss_sweep(plant_a, plant_b, 2, 2, 2, "", hist, counters) ## i64
z = ffsst_expect("planted sweep runs", wins >= 0)
z = ffsst_expect("planted sweep attempts", counters[0] == 32)
z = ffsst_expect("planted sweep coverage", counters[1] + counters[11] == 32)
z = ffsst_expect("planted sweep gates clean", counters[3] == 0 && counters[2] == counters[1])
z = ffsst_expect("planted sweep hist", hist[0] + hist[1] + hist[2] + hist[3] == counters[1] && hist[4] == counters[11])

# Bounded real-frontier smoke 1: the two checked-in 4x4 rank-47
# presentations (square path).  24 sectors x 2 modes x 2 orientations.
p44a = "benchmarks/matmul/metaflip/matmul_4x4_rank47_d450_gf2.txt"
p44b = "benchmarks/matmul/metaflip/matmul_4x4_rank47_d677_flips_gf2.txt"
hist44 = i64[5]
counters44 = i64[16]
wins44 = ffss_sweep(p44a, p44b, 4, 4, 4, "", hist44, counters44) ## i64
z = ffsst_expect("4x4 sweep runs", wins44 >= 0)
z = ffsst_expect("4x4 sweep attempts", counters44[0] == 96)
z = ffsst_expect("4x4 gates clean", counters44[3] == 0 && counters44[2] == counters44[1])
z = ffsst_expect("4x4 coverage", counters44[1] + counters44[11] == 96)
<< "SECTOR_SUTURE_SMOKE pair=4x4_d450xd677 attempts=" + counters44[0].to_s() + " gated=" + counters44[2].to_s() + " abstain=" + counters44[11].to_s() + " h0=" + hist44[0].to_s() + " h1=" + hist44[1].to_s() + " h2=" + hist44[2].to_s() + " h3=" + hist44[3].to_s() + " wins=" + counters44[4].to_s() + " offdict_equal=" + counters44[5].to_s() + " ms=" + counters44[15].to_s()

# Bounded real-frontier smoke 2: two checked-in <2,2,5> rank-18 doors
# (rectangular path).  17 sectors x 2 modes x 2 orientations.
p225a = "benchmarks/matmul/metaflip/matmul_2x2x5_rank18_d84_gf2.txt"
p225b = "benchmarks/matmul/metaflip/matmul_2x2x5_rank18_d88_gf2.txt"
hist225 = i64[5]
counters225 = i64[16]
wins225 = ffss_sweep(p225a, p225b, 2, 2, 5, "", hist225, counters225) ## i64
z = ffsst_expect("225 sweep runs", wins225 >= 0)
z = ffsst_expect("225 sweep attempts", counters225[0] == 68)
z = ffsst_expect("225 gates clean", counters225[3] == 0 && counters225[2] == counters225[1])
z = ffsst_expect("225 coverage", counters225[1] + counters225[11] == 68)
<< "SECTOR_SUTURE_SMOKE pair=225_d84xd88 attempts=" + counters225[0].to_s() + " gated=" + counters225[2].to_s() + " abstain=" + counters225[11].to_s() + " h0=" + hist225[0].to_s() + " h1=" + hist225[1].to_s() + " h2=" + hist225[2].to_s() + " h3=" + hist225[3].to_s() + " wins=" + counters225[4].to_s() + " offdict_equal=" + counters225[5].to_s() + " ms=" + counters225[15].to_s()

<< "flipfleet_sector_suture_test: all checks passed"
