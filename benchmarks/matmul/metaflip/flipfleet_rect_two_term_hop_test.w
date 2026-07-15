use flipfleet_rect_two_term_repair
use flipfleet_block_composer

-> ffr2tht_expect(label, condition) (String bool) i64
  if !condition
    << "FAIL " + label
    exit(1)
  1

# Deterministic real-floor positive control from the d84 archive.  Pair 0/7
# moves the exact residual from cell 377 to cell 227 with two replacement
# terms; adding the new residual cell reconstructs an exact rank-18 scheme.
us = i64[17]
vs = i64[17]
ws = i64[17]
us[0] = 10
vs[0] = 96
ws[0] = 1
us[1] = 1
vs[1] = 66
ws[1] = 66
us[2] = 8
vs[2] = 33
ws[2] = 33
us[3] = 12
vs[3] = 1
ws[3] = 96
us[4] = 3
vs[4] = 64
ws[4] = 3
us[5] = 10
vs[5] = 768
ws[5] = 256
us[6] = 4
vs[6] = 528
ws[6] = 528
us[7] = 4
vs[7] = 4
ws[7] = 128
us[8] = 2
vs[8] = 128
ws[8] = 4
us[9] = 12
vs[9] = 512
ws[9] = 768
us[10] = 6
vs[10] = 520
ws[10] = 272
us[11] = 1
vs[11] = 4
ws[11] = 4
us[12] = 9
vs[12] = 65
ws[12] = 65
us[13] = 2
vs[13] = 264
ws[13] = 264
us[14] = 3
vs[14] = 8
ws[14] = 24
us[15] = 5
vs[15] = 24
ws[15] = 16
us[16] = 5
vs[16] = 3
ws[16] = 64

target = i64[ffrrw_tensor_words(2, 2, 5)]
z = ffr2tht_expect("build target", ffrrw_build_mmt_target(target, 2, 2, 5) == target.size()) ## i64
residual = i64[target.size()]
z = ffr2tht_expect("source unit floor", ffrrw_build_residual(us, vs, ws, 17, 2, 2, 5, target, residual) == 1 && ffrrw_bit(residual, 377) == 1)
carrier = i64[target.size()]
z = ffrrw_copy(residual, carrier, residual.size())
weight = 1 ## i64
weight = ffrrw_xor_outer_weight(carrier, us[0], vs[0], ws[0], 4, 10, 10, weight)
weight = ffrrw_xor_outer_weight(carrier, us[7], vs[7], ws[7], 4, 10, 10, weight)
carrier[227 / 64] = carrier[227 / 64] ^ (1 << (227 % 64))
du = i64[2]
dv = i64[2]
dw = i64[2]
meta = i64[3]
repair_rank = ffr2tr_decompose(carrier, 2, 2, 5, du, dv, dw, meta) ## i64
z = ffr2tht_expect("two-term carrier", repair_rank == 2 && ffr2tr_rebuild(du, dv, dw, 2, 2, 2, 5, carrier) == 1)

hop_u = i64[17]
hop_v = i64[17]
hop_w = i64[17]
at = 0 ## i64
term = 0 ## i64
while term < 17
  if term != 0 && term != 7
    hop_u[at] = us[term]
    hop_v[at] = vs[term]
    hop_w[at] = ws[term]
    at += 1
  term += 1
term = 0
while term < 2
  hop_u[at] = du[term]
  hop_v[at] = dv[term]
  hop_w[at] = dw[term]
  at += 1
  term += 1
hop_residual = i64[target.size()]
z = ffr2tht_expect("target unit floor", at == 17 && ffrrw_build_residual(hop_u, hop_v, hop_w, 17, 2, 2, 5, target, hop_residual) == 1 && ffrrw_bit(hop_residual, 227) == 1)

scheme = FFBCScheme.new(2, 2, 5, 18)
term = 0
while term < 17
  scheme.us()[term] = hop_u[term]
  scheme.vs()[term] = hop_v[term]
  scheme.ws()[term] = hop_w[term]
  term += 1
scheme.us()[17] = 1 << (227 / 100)
scheme.vs()[17] = 1 << ((227 / 10) % 10)
scheme.ws()[17] = 1 << (227 % 10)
scheme.set_rank(18)
z = ffr2tht_expect("independent exact completion", ffbc_verify_exact(scheme) == 1)

<< "PASS flipfleet rectangular two-term unit hop 377->227"
