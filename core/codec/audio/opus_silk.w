# core/codec/audio/opus_silk — the SILK layer of the Opus decoder (RFC 6716 §4.2), a
# port of the libopus fixed-point SILK decoder (bit-exact integer math):
# side information and excitation decoding, NLSF -> LPC, LTP/LPC synthesis,
# stereo unmixing, packet-loss concealment, comfort noise and the SILK
# resampler (up2 HQ + fractional FIR) to 48 kHz.
#
# Per-channel state lives in an i64[] `ds` (layout below) plus a few arrays;
# all integer math is done in i64 with explicit int16/int32 wrapping where C
# relies on it.
#
# ds layout:
#   0 prev_gain_Q16  1 lagPrev  2 LastGainIndex  3 fs_kHz  4 fs_API_hz
#   5 nb_subfr  6 frame_length  7 subfr_length  8 ltp_mem_length  9 LPC_order
#   10 first_frame_after_reset  11 nFramesDecoded  12 nFramesPerPacket
#   13 ec_prevSignalType  14 ec_prevLagIndex  15 LBRR_flag  16 lossCnt
#   17 prevSignalType  20..22 VAD_flags  23..25 LBRR_flags
#   indices: 30..33 GainsIndices  34..37 LTPIndex  38..54 NLSFIndices
#     55 lagIndex 56 contourIndex 57 signalType 58 quantOffsetType
#     59 NLSFInterpCoef_Q2 60 PERIndex 61 LTP_scaleIndex 62 Seed
#   PLC: 70 pitchL_Q8 71..75 LTPCoef_Q14 76..91 prevLPC_Q12 92 last_frame_lost
#     93 rand_seed 94 randScale_Q14 95 conc_energy 96 conc_energy_shift
#     97 prevLTP_scale_Q14 98..99 prevGain_Q16 100 fs_kHz 101 nb_subfr
#     102 subfr_length
#   CNG: 110..125 smth_NLSF_Q15 126..141 synth_state 142 smth_Gain_Q16
#     143 rand_seed 144 fs_kHz
#   150..165 prevNLSF_Q15  170..185 sLPC_Q14_buf
#   resampler: 190..195 sIIR 196..203 sFIR 204..251 delayBuf 252 batchSize
#     253 invRatio_Q16 254 Fs_in_kHz 255 Fs_out_kHz 256 inputDelay 257 function
# ctrl layout: 0..3 pitchL 4..7 Gains_Q16 8..23 PredCoef_Q12[0]
#   24..39 PredCoef_Q12[1] 40..59 LTPCoef_Q14 60 LTP_scale_Q14

use core/codec/media
use opus_rangedec
use opus_tables

SILK_DS_N = 260

# ---------------------------------------------------------------- fixed point

-> silk_s16(x) (i64) i64
  ((x + 32768) & 65535) - 32768

-> silk_w32(x) (i64) i64
  ((x + 2147483648) & 4294967295) - 2147483648

-> silk_sat16(x) (i64) i64
  return 32767 if x > 32767
  return -32768 if x < -32768
  x

-> silk_sat32(x) (i64) i64
  return 2147483647 if x > 2147483647
  return -2147483648 if x < -2147483648
  x

-> silk_smulwb(a, b) (i64 i64) i64
  (a * silk_s16(b)) >> 16

-> silk_smlawb(a, b, c) (i64 i64 i64) i64
  a + ((b * silk_s16(c)) >> 16)

-> silk_smulww(a, b) (i64 i64) i64
  (a * b) >> 16

-> silk_smlaww(a, b, c) (i64 i64 i64) i64
  a + ((b * c) >> 16)

-> silk_smulbb(a, b) (i64 i64) i64
  silk_s16(a) * silk_s16(b)

-> silk_smultt(a, b) (i64 i64) i64
  (a >> 16) * (b >> 16)

-> silk_rshift_round(a, sh) (i64 i64) i64
  return (a >> 1) + (a & 1) if sh == 1
  ((a >> (sh - 1)) + 1) >> 1

-> silk_lshift32(a, sh) (i64 i64) i64
  silk_w32(a << sh)

-> silk_lshift_sat32(a, sh) (i64 i64) i64
  lo = -2147483648 >> sh
  hi = 2147483647 >> sh
  v = a
  v = hi if v > hi
  v = lo if v < lo
  silk_w32(v << sh)

-> silk_clz32(x) (i64) i64
  return 32 if x == 0
  32 - ec_ilog(x & 4294967295)

-> silk_abs(x) (i64) i64
  return 0 - x if x < 0
  x

-> silk_rand(seed) (i64) i64
  silk_w32(907633515 + seed * 196314165)

-> silk_inverse32_varq(b32, qres) (i64 i64) i64
  b_headrm = silk_clz32(silk_abs(b32)) - 1
  b32_nrm = silk_lshift32(b32, b_headrm)
  b32_inv = 536870911 / (b32_nrm >> 16)
  result = b32_inv << 16
  err_q32 = silk_lshift32((536870912 - silk_smulwb(b32_nrm, b32_inv)), 3)
  result = silk_smlaww(result, err_q32, b32_inv)
  lshift = 61 - b_headrm - qres
  if lshift <= 0
    return silk_lshift_sat32(result, 0 - lshift)
  return result >> lshift if lshift < 32
  0

-> silk_div32_varq(a32, b32, qres) (i64 i64 i64) i64
  a_headrm = silk_clz32(silk_abs(a32)) - 1
  a32_nrm = silk_lshift32(a32, a_headrm)
  b_headrm = silk_clz32(silk_abs(b32)) - 1
  b32_nrm = silk_lshift32(b32, b_headrm)
  b32_inv = 536870911 / (b32_nrm >> 16)
  result = silk_smulwb(a32_nrm, b32_inv)
  a32_nrm = silk_w32(a32_nrm - silk_w32(((b32_nrm * result) >> 32) << 3))
  result = silk_smlawb(result, a32_nrm, b32_inv)
  lshift = 29 + a_headrm - b_headrm - qres
  if lshift < 0
    return silk_lshift_sat32(result, 0 - lshift)
  return result >> lshift if lshift < 32
  0

-> silk_sqrt_approx(x) (i64) i64
  return 0 if x <= 0
  lz = silk_clz32(x)
  # silk_ROR32(x, 24 - lz) & 0x7f
  r = 24 - lz
  ux = x & 4294967295
  rot = 0 ## i64
  if r == 0
    rot = ux
  elsif r < 0
    m = 0 - r
    rot = ((ux << m) | (ux >> (32 - m))) & 4294967295
  else
    rot = ((ux << (32 - r)) | (ux >> r)) & 4294967295
  frac = rot & 127
  y = 46214 ## i64
  y = 32768 if (lz & 1) != 0
  y = y >> (lz >> 1)
  silk_smlawb(y, y, silk_smulbb(213, frac))

-> silk_log2lin(inlog) (i64) i64
  return 0 if inlog < 0
  return 2147483647 if inlog >= 3967
  out = 1 << (inlog >> 7)
  frac = inlog & 127
  if inlog < 2048
    out = out + ((out * silk_smlawb(frac, silk_smulbb(frac, 128 - frac), -174)) >> 7)
  else
    out = out + (out >> 7) * silk_smlawb(frac, silk_smulbb(frac, 128 - frac), -174)
  out

# energy, shift of x[off..off+len) -> out[0], out[1]
-> silk_sum_sqr_shift(x, off, len, out) (i64[] i64 i64 i64[]) i64
  shft = 31 - silk_clz32(len)
  nrg = len
  i = 0 ## i64
  while i < len - 1
    t = (silk_smulbb(x[off + i], x[off + i]) + silk_smulbb(x[off + i + 1], x[off + i + 1])) & 4294967295
    nrg = silk_w32(nrg + (t >> shft))
    i += 2
  if i < len
    t = silk_smulbb(x[off + i], x[off + i]) & 4294967295
    nrg = silk_w32(nrg + (t >> shft))
  shft = shft + 3 - silk_clz32(nrg)
  shft = 0 if shft < 0
  nrg = 0
  i = 0
  while i < len - 1
    t = (silk_smulbb(x[off + i], x[off + i]) + silk_smulbb(x[off + i + 1], x[off + i + 1])) & 4294967295
    nrg = silk_w32(nrg + (t >> shft))
    i += 2
  if i < len
    t = silk_smulbb(x[off + i], x[off + i]) & 4294967295
    nrg = silk_w32(nrg + (t >> shft))
  out[0] = nrg
  out[1] = shft
  0

# ---------------------------------------------------------------- LPC tools

-> silk_bwexpander(ar, off, d, chirp0) (i64[] i64 i64 i64) i64
  chirp = chirp0
  cm1 = chirp - 65536
  i = 0 ## i64
  while i < d - 1
    ar[off + i] = silk_s16(silk_rshift_round(chirp * ar[off + i], 16))
    chirp += silk_rshift_round(chirp * cm1, 16)
    i += 1
  ar[off + d - 1] = silk_s16(silk_rshift_round(chirp * ar[off + d - 1], 16))
  0

-> silk_bwexpander_32(ar, d, chirp0) (i64[] i64 i64) i64
  chirp = chirp0
  cm1 = chirp - 65536
  i = 0 ## i64
  while i < d - 1
    ar[i] = silk_smulww(chirp, ar[i])
    chirp += silk_rshift_round(chirp * cm1, 16)
    i += 1
  ar[d - 1] = silk_smulww(chirp, ar[d - 1])
  0

-> silk_lpc_inv_pred_gain_qa(a, order) (i64[] i64) i64
  inv_gain = 1073741824 ## i64
  alimit = 16773022 ## i64
  k = order - 1
  while k > 0
    return 0 if a[k] > alimit || a[k] < 0 - alimit
    rc_q31 = 0 - silk_lshift32(a[k], 7)
    rc_mult1 = 1073741824 - ((rc_q31 * rc_q31) >> 32)
    inv_gain = silk_lshift32((inv_gain * rc_mult1) >> 32, 2)
    return 0 if inv_gain < 107374
    mult2q = 32 - silk_clz32(silk_abs(rc_mult1))
    rc_mult2 = silk_inverse32_varq(rc_mult1, mult2q + 30)
    n = 0 ## i64
    while n < ((k + 1) >> 1)
      tmp1 = a[n]
      tmp2 = a[k - n - 1]
      t = silk_sat32(tmp1 - silk_rshift_round(tmp2 * rc_q31, 31))
      t64 = silk_rshift_round(t * rc_mult2, mult2q)
      return 0 if t64 > 2147483647 || t64 < -2147483648
      a[n] = t64
      t = silk_sat32(tmp2 - silk_rshift_round(tmp1 * rc_q31, 31))
      t64 = silk_rshift_round(t * rc_mult2, mult2q)
      return 0 if t64 > 2147483647 || t64 < -2147483648
      a[k - n - 1] = t64
      n += 1
    k -= 1
  return 0 if a[0] > alimit || a[0] < 0 - alimit
  rc_q31 = 0 - silk_lshift32(a[0], 7)
  rc_mult1 = 1073741824 - ((rc_q31 * rc_q31) >> 32)
  inv_gain = silk_lshift32((inv_gain * rc_mult1) >> 32, 2)
  return 0 if inv_gain < 107374
  inv_gain

-> silk_lpc_inverse_pred_gain(a_q12, off, order) (i64[] i64 i64) i64
  tmp = i64[16]
  dc = 0 ## i64
  k = 0 ## i64
  while k < order
    dc += a_q12[off + k]
    tmp[k] = silk_lshift32(a_q12[off + k], 12)
    k += 1
  return 0 if dc >= 4096
  silk_lpc_inv_pred_gain_qa(tmp, order)

-> silk_lpc_fit(a_qout, ooff, a_qin, qout, qin, d) (i64[] i64 i64[] i64 i64 i64) i64
  idx = 0 ## i64
  i = 0 ## i64
  while i < 10
    maxabs = 0 ## i64
    k = 0 ## i64
    while k < d
      av = silk_abs(a_qin[k])
      if av > maxabs
        maxabs = av
        idx = k
      k += 1
    maxabs = silk_rshift_round(maxabs, qin - qout)
    if maxabs > 32767
      maxabs = 163838 if maxabs > 163838
      chirp = 65470 - (((maxabs - 32767) << 14) / ((maxabs * (idx + 1)) >> 2))
      silk_bwexpander_32(a_qin, d, chirp)
    else
      break
    i += 1
  if i == 10
    k = 0
    while k < d
      a_qout[ooff + k] = silk_sat16(silk_rshift_round(a_qin[k], qin - qout))
      a_qin[k] = a_qout[ooff + k] << (qin - qout)
      k += 1
  else
    k = 0
    while k < d
      a_qout[ooff + k] = silk_s16(silk_rshift_round(a_qin[k], qin - qout))
      k += 1
  0

-> silk_nlsf2a_find_poly(out, c, coff, dd) (i64[] i64[] i64 i64) i64
  out[0] = 65536
  out[1] = 0 - c[coff]
  k = 1 ## i64
  while k < dd
    ftmp = c[coff + 2 * k]
    out[k + 1] = (out[k - 1] << 1) - silk_rshift_round(ftmp * out[k], 16)
    n = k
    while n > 1
      out[n] = out[n] + out[n - 2] - silk_rshift_round(ftmp * out[n - 1], 16)
      n -= 1
    out[1] = out[1] - ftmp
    k += 1
  0

# NLSF (Q15, nlsf[noff..]) -> a_Q12 (a[aoff..]), order d
-> silk_nlsf2a(a, aoff, nlsf, noff, d, costab) (i64[] i64 i64[] i64 i64 i64[]) i64
  ord = i64[16]
  if d == 16
    ord[0] = 0
    ord[1] = 15
    ord[2] = 8
    ord[3] = 7
    ord[4] = 4
    ord[5] = 11
    ord[6] = 12
    ord[7] = 3
    ord[8] = 2
    ord[9] = 13
    ord[10] = 10
    ord[11] = 5
    ord[12] = 6
    ord[13] = 9
    ord[14] = 14
    ord[15] = 1
  else
    ord[0] = 0
    ord[1] = 9
    ord[2] = 6
    ord[3] = 3
    ord[4] = 4
    ord[5] = 5
    ord[6] = 8
    ord[7] = 1
    ord[8] = 2
    ord[9] = 7
  cos_lsf = i64[16]
  k = 0 ## i64
  while k < d
    f_int = nlsf[noff + k] >> 8
    f_frac = nlsf[noff + k] - (f_int << 8)
    cos_val = costab[f_int]
    delta = costab[f_int + 1] - cos_val
    cos_lsf[ord[k]] = silk_rshift_round((cos_val << 8) + delta * f_frac, 4)
    k += 1
  dd = d >> 1
  p = i64[9]
  q = i64[9]
  silk_nlsf2a_find_poly(p, cos_lsf, 0, dd)
  silk_nlsf2a_find_poly(q, cos_lsf, 1, dd)
  a32 = i64[16]
  k = 0
  while k < dd
    ptmp = p[k + 1] + p[k]
    qtmp = q[k + 1] - q[k]
    a32[k] = 0 - qtmp - ptmp
    a32[d - k - 1] = qtmp - ptmp
    k += 1
  silk_lpc_fit(a, aoff, a32, 12, 17, d)
  i = 0 ## i64
  while silk_lpc_inverse_pred_gain(a, aoff, d) == 0 && i < 16
    silk_bwexpander_32(a32, d, 65536 - (2 << i))
    k = 0
    while k < d
      a[aoff + k] = silk_s16(silk_rshift_round(a32[k], 5))
      k += 1
    i += 1
  0

-> silk_nlsf_stabilize(nlsf, noff, dmin, l) (i64[] i64 i64[] i64) i64
  loops = 0 ## i64
  while loops < 20
    min_diff = nlsf[noff] - dmin[0]
    ii = 0 ## i64
    i = 1 ## i64
    while i <= l - 1
      diff = nlsf[noff + i] - (nlsf[noff + i - 1] + dmin[i])
      if diff < min_diff
        min_diff = diff
        ii = i
      i += 1
    diff = 32768 - (nlsf[noff + l - 1] + dmin[l])
    if diff < min_diff
      min_diff = diff
      ii = l
    return 0 if min_diff >= 0
    if ii == 0
      nlsf[noff] = dmin[0]
    elsif ii == l
      nlsf[noff + l - 1] = 32768 - dmin[l]
    else
      min_center = 0 ## i64
      k = 0 ## i64
      while k < ii
        min_center += dmin[k]
        k += 1
      min_center += dmin[ii] >> 1
      max_center = 32768 ## i64
      k = l
      while k > ii
        max_center -= dmin[k]
        k -= 1
      max_center -= dmin[ii] >> 1
      c = silk_rshift_round(nlsf[noff + ii - 1] + nlsf[noff + ii], 1)
      if min_center > max_center
        c = min_center if c > min_center
        c = max_center if c < max_center
      else
        c = max_center if c > max_center
        c = min_center if c < min_center
      c = silk_s16(c)
      nlsf[noff + ii - 1] = c - (dmin[ii] >> 1)
      nlsf[noff + ii] = nlsf[noff + ii - 1] + dmin[ii]
    loops += 1
  # fall back: sort and clamp
  i = 1
  while i < l
    v = nlsf[noff + i]
    j = i - 1
    while j >= 0 && v < nlsf[noff + j]
      nlsf[noff + j + 1] = nlsf[noff + j]
      j -= 1
    nlsf[noff + j + 1] = v
    i += 1
  nlsf[noff] = dmin[0] if dmin[0] > nlsf[noff]
  i = 1
  while i < l
    m = silk_sat16(nlsf[noff + i - 1] + dmin[i])
    nlsf[noff + i] = m if m > nlsf[noff + i]
    i += 1
  m = 32768 - dmin[l]
  nlsf[noff + l - 1] = m if m < nlsf[noff + l - 1]
  i = l - 2
  while i >= 0
    m = nlsf[noff + i + 1] - dmin[i + 1]
    nlsf[noff + i] = m if m < nlsf[noff + i]
    i -= 1
  0

# out[off+d .. off+len) = in filtered; out[off..off+d) = 0
-> silk_lpc_analysis_filter(out, ooff, inp, ioff, b, boff, len, d) (i64[] i64 i64[] i64 i64[] i64 i64 i64) i64
  ix = d
  while ix < len
    p = ioff + ix - 1
    acc = 0 ## i64
    j = 0 ## i64
    while j < d
      acc += inp[p - j] * b[boff + j]
      j += 1
    acc = silk_w32(acc)
    o = silk_w32((inp[p + 1] << 12) - acc)
    out[ooff + ix] = silk_sat16(silk_rshift_round(o, 12))
    ix += 1
  j = 0
  while j < d
    out[ooff + j] = 0
    j += 1
  0

# ---------------------------------------------------------------- decoding

-> silk_nlsf_cb(order)
  if order == 16
    return [SILK_NLSF_CB1_WB_Q8, SILK_NLSF_CB1_WB_WGHT_Q9, SILK_NLSF_CB1_ICDF_WB, SILK_NLSF_PRED_WB_Q8, SILK_NLSF_CB2_SELECT_WB, SILK_NLSF_CB2_ICDF_WB, SILK_NLSF_DELTA_MIN_WB_Q15, 9830]
  [SILK_NLSF_CB1_NB_MB_Q8, SILK_NLSF_CB1_WGHT_Q9, SILK_NLSF_CB1_ICDF_NB_MB, SILK_NLSF_PRED_NB_MB_Q8, SILK_NLSF_CB2_SELECT_NB_MB, SILK_NLSF_CB2_ICDF_NB_MB, SILK_NLSF_DELTA_MIN_NB_MB_Q15, 11796]

-> silk_nlsf_unpack(ec_ix, pred_q8, sel, pred, order, cb1_index) (i64[] i64[] i64[] i64[] i64 i64) i64
  p = cb1_index * order / 2
  i = 0 ## i64
  while i < order
    entry = sel[p]
    p += 1
    ec_ix[i] = ((entry >> 1) & 7) * 9
    pred_q8[i] = pred[i + (entry & 1) * (order - 1)]
    ec_ix[i + 1] = ((entry >> 5) & 7) * 9
    pred_q8[i + 1] = pred[i + ((entry >> 4) & 1) * (order - 1) + 1]
    i += 2
  0

-> silk_decode_indices(st, buf, ds, frame_index, decode_lbrr, cond)
  if decode_lbrr != 0 || ds[20 + frame_index] != 0
    ix = ec_dec_icdf(st, buf, SILK_TYPE_OFFSET_VAD_ICDF, 0, 8) + 2
  else
    ix = ec_dec_icdf(st, buf, SILK_TYPE_OFFSET_NO_VAD_ICDF, 0, 8)
  sig = ix >> 1
  ds[57] = sig
  ds[58] = ix & 1
  nb = ds[5]
  if cond == 2
    ds[30] = ec_dec_icdf(st, buf, SILK_DELTA_GAIN_ICDF, 0, 8)
  else
    g = ec_dec_icdf(st, buf, SILK_GAIN_ICDF, sig * 8, 8) << 3
    ds[30] = g + ec_dec_icdf(st, buf, SILK_UNIFORM8_ICDF, 0, 8)
  i = 1
  while i < nb
    ds[30 + i] = ec_dec_icdf(st, buf, SILK_DELTA_GAIN_ICDF, 0, 8)
    i += 1
  order = ds[9]
  cb = silk_nlsf_cb(order)
  ds[38] = ec_dec_icdf(st, buf, cb[2], (sig >> 1) * 32, 8)
  ec_ix = i64[16]
  pred_q8 = i64[16]
  silk_nlsf_unpack(ec_ix, pred_q8, cb[4], cb[3], order, ds[38])
  i = 0
  while i < order
    ix = ec_dec_icdf(st, buf, cb[5], ec_ix[i], 8)
    if ix == 0
      ix -= ec_dec_icdf(st, buf, SILK_NLSF_EXT_ICDF, 0, 8)
    elsif ix == 8
      ix += ec_dec_icdf(st, buf, SILK_NLSF_EXT_ICDF, 0, 8)
    ds[39 + i] = ix - 4
    i += 1
  if nb == 4
    ds[59] = ec_dec_icdf(st, buf, SILK_NLSF_INTERPOLATION_FACTOR_ICDF, 0, 8)
  else
    ds[59] = 4
  if sig == 2
    absolute = 1
    if cond == 2 && ds[13] == 2
      d = ec_dec_icdf(st, buf, SILK_PITCH_DELTA_ICDF, 0, 8)
      if d > 0
        d -= 9
        ds[55] = silk_s16(ds[14] + d)
        absolute = 0
    if absolute != 0
      fs = ds[3]
      lag = ec_dec_icdf(st, buf, SILK_PITCH_LAG_ICDF, 0, 8) * (fs >> 1)
      if fs == 16
        lag += ec_dec_icdf(st, buf, SILK_UNIFORM8_ICDF, 0, 8)
      elsif fs == 12
        lag += ec_dec_icdf(st, buf, SILK_UNIFORM6_ICDF, 0, 8)
      else
        lag += ec_dec_icdf(st, buf, SILK_UNIFORM4_ICDF, 0, 8)
      ds[55] = lag
    ds[14] = ds[55]
    if ds[3] == 8
      if nb == 4
        ds[56] = ec_dec_icdf(st, buf, SILK_PITCH_CONTOUR_NB_ICDF, 0, 8)
      else
        ds[56] = ec_dec_icdf(st, buf, SILK_PITCH_CONTOUR_10_MS_NB_ICDF, 0, 8)
    else
      if nb == 4
        ds[56] = ec_dec_icdf(st, buf, SILK_PITCH_CONTOUR_ICDF, 0, 8)
      else
        ds[56] = ec_dec_icdf(st, buf, SILK_PITCH_CONTOUR_10_MS_ICDF, 0, 8)
    per = ec_dec_icdf(st, buf, SILK_LTP_PER_INDEX_ICDF, 0, 8)
    ds[60] = per
    tab = SILK_LTP_GAIN_ICDF_0
    tab = SILK_LTP_GAIN_ICDF_1 if per == 1
    tab = SILK_LTP_GAIN_ICDF_2 if per == 2
    k = 0
    while k < nb
      ds[34 + k] = ec_dec_icdf(st, buf, tab, 0, 8)
      k += 1
    if cond == 0
      ds[61] = ec_dec_icdf(st, buf, SILK_LTPSCALE_ICDF, 0, 8)
    else
      ds[61] = 0
  ds[13] = sig
  ds[62] = ec_dec_icdf(st, buf, SILK_UNIFORM4_ICDF, 0, 8)

-> silk_decode_split(st, buf, p, table, offs, out, o1, o2) (i64[] u8[] i64 u8[] i64[] i64[] i64 i64) i64
  if p > 0
    v = ec_dec_icdf(st, buf, table, offs[p], 8)
    out[o1] = v
    out[o2] = p - v
  else
    out[o1] = 0
    out[o2] = 0
  0

-> silk_shell_decoder(st, buf, pulses, po, p4, t0, t1, t2, t3, offs) (i64[] u8[] i64[] i64 i64 u8[] u8[] u8[] u8[] i64[]) i64
  # tmp layout: p3 at 0..1, p2 at 2..5, p1 at 6..13
  t = i64[14]
  silk_decode_split(st, buf, p4, t3, offs, t, 0, 1)
  silk_decode_split(st, buf, t[0], t2, offs, t, 2, 3)
  silk_decode_split(st, buf, t[2], t1, offs, t, 6, 7)
  silk_decode_split(st, buf, t[6], t0, offs, pulses, po + 0, po + 1)
  silk_decode_split(st, buf, t[7], t0, offs, pulses, po + 2, po + 3)
  silk_decode_split(st, buf, t[3], t1, offs, t, 8, 9)
  silk_decode_split(st, buf, t[8], t0, offs, pulses, po + 4, po + 5)
  silk_decode_split(st, buf, t[9], t0, offs, pulses, po + 6, po + 7)
  silk_decode_split(st, buf, t[1], t2, offs, t, 4, 5)
  silk_decode_split(st, buf, t[4], t1, offs, t, 10, 11)
  silk_decode_split(st, buf, t[10], t0, offs, pulses, po + 8, po + 9)
  silk_decode_split(st, buf, t[11], t0, offs, pulses, po + 10, po + 11)
  silk_decode_split(st, buf, t[5], t1, offs, t, 12, 13)
  silk_decode_split(st, buf, t[12], t0, offs, pulses, po + 12, po + 13)
  silk_decode_split(st, buf, t[13], t0, offs, pulses, po + 14, po + 15)
  0

-> silk_decode_pulses(st, buf, pulses, sig, qot, frame_length)
  rli = ec_dec_icdf(st, buf, SILK_RATE_LEVELS_ICDF, (sig >> 1) * 9, 8)
  iter = frame_length >> 4
  iter += 1 if iter * 16 < frame_length
  sum_pulses = i64[iter + 1]
  nls = i64[iter + 1]
  i = 0
  while i < iter
    nls[i] = 0
    sp = ec_dec_icdf(st, buf, SILK_PULSES_PER_BLOCK_ICDF, rli * 18, 8)
    while sp == 17
      nls[i] = nls[i] + 1
      extra = 0
      extra = 1 if nls[i] == 10
      sp = ec_dec_icdf(st, buf, SILK_PULSES_PER_BLOCK_ICDF, 9 * 18 + extra, 8)
    sum_pulses[i] = sp
    i += 1
  i = 0
  while i < iter
    if sum_pulses[i] > 0
      silk_shell_decoder(st, buf, pulses, i * 16, sum_pulses[i], SILK_SHELL_CODE_TABLE0, SILK_SHELL_CODE_TABLE1, SILK_SHELL_CODE_TABLE2, SILK_SHELL_CODE_TABLE3, SILK_SHELL_CODE_TABLE_OFFSETS)
    else
      k = 0
      while k < 16
        pulses[i * 16 + k] = 0
        k += 1
    i += 1
  i = 0
  while i < iter
    if nls[i] > 0
      nl = nls[i]
      k = 0
      while k < 16
        aq = pulses[i * 16 + k]
        j = 0
        while j < nl
          aq = (aq << 1) + ec_dec_icdf(st, buf, SILK_LSB_ICDF, 0, 8)
          j += 1
        pulses[i * 16 + k] = aq
        k += 1
      sum_pulses[i] = sum_pulses[i] | (nl << 5)
    i += 1
  silk_decode_signs(st, buf, pulses, frame_length, sig, qot, sum_pulses, SILK_SIGN_ICDF)

-> silk_decode_signs(st, buf, pulses, length0, sig, qot, sum_pulses, sicdf) (i64[] u8[] i64[] i64 i64 i64 i64[] u8[]) i64
  icdf = u8[2]
  icdf[1] = 0
  base = 7 * (qot + (sig << 1))
  length = (length0 + 8) >> 4
  q = 0 ## i64
  i = 0 ## i64
  while i < length
    p = sum_pulses[i]
    if p > 0
      pm = p & 31
      pm = 6 if pm > 6
      icdf[0] = sicdf[base + pm]
      j = 0 ## i64
      while j < 16
        if pulses[q + j] > 0
          s = ec_dec_icdf(st, buf, icdf, 0, 8)
          pulses[q + j] = pulses[q + j] * ((s << 1) - 1)
        j += 1
    q += 16
    i += 1
  0

-> silk_gains_dequant(ctrl, ds, conditional)
  nb = ds[5]
  k = 0
  while k < nb
    ind = ds[30 + k]
    if k == 0 && conditional == 0
      p = ds[2] - 16
      ds[2] = (ind > p) ? ind : p
    else
      ind_tmp = ind - 4
      thr = 2 * 36 - 64 + ds[2]
      if ind_tmp > thr
        ds[2] = ds[2] + (ind_tmp << 1) - thr
      else
        ds[2] = ds[2] + ind_tmp
    v = ds[2]
    v = 0 if v < 0
    v = 63 if v > 63
    ds[2] = v
    x = silk_smulwb(1907825, v) + 2090
    x = 3967 if x > 3967
    ctrl[4 + k] = silk_log2lin(x)
    k += 1

-> silk_nlsf_decode(nlsf, ds, cb)
  order = ds[9]
  ec_ix = i64[16]
  pred_q8 = i64[16]
  cb1 = ds[38]
  silk_nlsf_unpack(ec_ix, pred_q8, cb[4], cb[3], order, cb1)
  res = i64[16]
  step = cb[7]
  out_q10 = 0
  i = order - 1
  while i >= 0
    pred_q10 = (silk_smulbb(out_q10, pred_q8[i])) >> 8
    out_q10 = ds[39 + i] << 10
    if out_q10 > 0
      out_q10 = out_q10 - 102
    elsif out_q10 < 0
      out_q10 = out_q10 + 102
    out_q10 = silk_smlawb(pred_q10, out_q10, step)
    res[i] = out_q10
    i -= 1
  cbv = cb[0]
  wght = cb[1]
  i = 0
  while i < order
    t = ((res[i] << 14) / wght[cb1 * order + i]) + (cbv[cb1 * order + i] << 7)
    t = 0 if t < 0
    t = 32767 if t > 32767
    nlsf[i] = t
    i += 1
  silk_nlsf_stabilize(nlsf, 0, cb[6], order)

-> silk_decode_parameters(ds, ctrl, cond)
  silk_gains_dequant(ctrl, ds, cond == 2 ? 1 : 0)
  order = ds[9]
  cb = silk_nlsf_cb(order)
  nlsf = i64[16]
  silk_nlsf_decode(nlsf, ds, cb)
  silk_nlsf2a(ctrl, 24, nlsf, 0, order, SILK_LSFCOSTAB_FIX_Q12)
  ds[59] = 4 if ds[10] == 1
  if ds[59] < 4
    nlsf0 = i64[16]
    i = 0
    while i < order
      nlsf0[i] = ds[150 + i] + ((ds[59] * (nlsf[i] - ds[150 + i])) >> 2)
      i += 1
    silk_nlsf2a(ctrl, 8, nlsf0, 0, order, SILK_LSFCOSTAB_FIX_Q12)
  else
    i = 0
    while i < order
      ctrl[8 + i] = ctrl[24 + i]
      i += 1
  i = 0
  while i < order
    ds[150 + i] = nlsf[i]
    i += 1
  if ds[16] != 0
    silk_bwexpander(ctrl, 8, order, 63570)
    silk_bwexpander(ctrl, 24, order, 63570)
  nb = ds[5]
  if ds[57] == 2
    silk_decode_pitch(ds[55], ds[56], ctrl, ds[3], nb)
    per = ds[60]
    cbk = SILK_LTP_GAIN_VQ_0
    cbk = SILK_LTP_GAIN_VQ_1 if per == 1
    cbk = SILK_LTP_GAIN_VQ_2 if per == 2
    k = 0
    while k < nb
      ix = ds[34 + k]
      i = 0
      while i < 5
        ctrl[40 + k * 5 + i] = cbk[ix * 5 + i] << 7
        i += 1
      k += 1
    ctrl[60] = SILK_LTPSCALES_TABLE_Q14[ds[61]]
  else
    k = 0
    while k < nb
      ctrl[k] = 0
      k += 1
    k = 0
    while k < nb * 5
      ctrl[40 + k] = 0
      k += 1
    ds[60] = 0
    ctrl[60] = 0

-> silk_decode_pitch(lag_index, contour, ctrl, fs, nb)
  cbk = nil
  size = 0
  if fs == 8
    if nb == 4
      cbk = SILK_CB_LAGS_STAGE2
      size = 11
    else
      cbk = SILK_CB_LAGS_STAGE2_10_MS
      size = 3
  else
    if nb == 4
      cbk = SILK_CB_LAGS_STAGE3
      size = 34
    else
      cbk = SILK_CB_LAGS_STAGE3_10_MS
      size = 12
  min_lag = 2 * fs
  max_lag = 18 * fs
  lag = min_lag + lag_index
  k = 0
  while k < nb
    v = lag + cbk[k * size + contour]
    v = max_lag if v > max_lag
    v = min_lag if v < min_lag
    ctrl[k] = v
    k += 1

# decode_core: synthesis of one frame into xq[xo..xo+frame_length)
-> silk_decode_core(ds, ctrl, xq, xo, pulses, exc, out_buf, qoff) (i64[] i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  ltp_mem = ds[8]
  flen = ds[6]
  slen = ds[7]
  order = ds[9]
  nb = ds[5]
  s_ltp = i64[ltp_mem]
  s_ltp_q15 = i64[ltp_mem + flen]
  res = i64[slen]
  s_lpc = i64[slen + 16]
  a_tmp = i64[16]
  offset_q10 = qoff[(ds[57] >> 1) * 2 + ds[58]]
  interp_flag = 0 ## i64
  interp_flag = 1 if ds[59] < 4
  seed = ds[62]
  i = 0 ## i64
  while i < flen
    seed = silk_rand(seed)
    e = pulses[i] << 14
    if e > 0
      e -= 80 << 4
    elsif e < 0
      e += 80 << 4
    e += offset_q10 << 4
    e = 0 - e if seed < 0
    exc[i] = e
    seed = silk_w32(seed + pulses[i])
    i += 1
  i = 0
  while i < 16
    s_lpc[i] = ds[170 + i]
    i += 1
  pexc = 0 ## i64
  pxq = xo
  s_ltp_idx = ltp_mem
  lag = 0 ## i64
  k = 0 ## i64
  while k < nb
    aoff = 8 + 16 * (k >> 1)
    i = 0
    while i < order
      a_tmp[i] = ctrl[aoff + i]
      i += 1
    boff = 40 + k * 5
    sig = ds[57]
    gain_q10 = ctrl[4 + k] >> 6
    inv_gain = silk_inverse32_varq(ctrl[4 + k], 47)
    gain_adj = 65536 ## i64
    if ctrl[4 + k] != ds[0]
      gain_adj = silk_div32_varq(ds[0], ctrl[4 + k], 16)
      i = 0
      while i < 16
        s_lpc[i] = silk_smulww(gain_adj, s_lpc[i])
        i += 1
    ds[0] = ctrl[4 + k]
    if ds[16] != 0 && ds[17] == 2 && ds[57] != 2 && k < 2
      i = 0
      while i < 5
        ctrl[boff + i] = 0
        i += 1
      ctrl[boff + 2] = 4096
      sig = 2
      ctrl[k] = ds[1]
    if sig == 2
      lag = ctrl[k]
      if k == 0 || (k == 2 && interp_flag != 0)
        start_idx = ltp_mem - lag - order - 2
        if k == 2
          i = 0
          while i < 2 * slen
            out_buf[ltp_mem + i] = xq[xo + i]
            i += 1
        silk_lpc_analysis_filter(s_ltp, start_idx, out_buf, start_idx + k * slen, ctrl, aoff, ltp_mem - start_idx, order)
        if k == 0
          inv_gain = silk_lshift32(silk_smulwb(inv_gain, ctrl[60]), 2)
        i = 0
        while i < lag + 2
          s_ltp_q15[s_ltp_idx - i - 1] = silk_smulwb(inv_gain, s_ltp[ltp_mem - i - 1])
          i += 1
      else
        if gain_adj != 65536
          i = 0
          while i < lag + 2
            s_ltp_q15[s_ltp_idx - i - 1] = silk_smulww(gain_adj, s_ltp_q15[s_ltp_idx - i - 1])
            i += 1
    if sig == 2
      pl = s_ltp_idx - lag + 2
      b0 = ctrl[boff]
      b1 = ctrl[boff + 1]
      b2 = ctrl[boff + 2]
      b3 = ctrl[boff + 3]
      b4 = ctrl[boff + 4]
      i = 0
      while i < slen
        p = 2 ## i64
        p = silk_smlawb(p, s_ltp_q15[pl], b0)
        p = silk_smlawb(p, s_ltp_q15[pl - 1], b1)
        p = silk_smlawb(p, s_ltp_q15[pl - 2], b2)
        p = silk_smlawb(p, s_ltp_q15[pl - 3], b3)
        p = silk_smlawb(p, s_ltp_q15[pl - 4], b4)
        pl += 1
        r = silk_w32(exc[pexc + i] + silk_lshift32(p, 1))
        res[i] = r
        s_ltp_q15[s_ltp_idx] = silk_lshift32(r, 1)
        s_ltp_idx += 1
        i += 1
    else
      i = 0
      while i < slen
        res[i] = exc[pexc + i]
        i += 1
    i = 0
    while i < slen
      p = order >> 1
      j = 0 ## i64
      while j < order
        p = silk_smlawb(p, s_lpc[16 + i - j - 1], a_tmp[j])
        j += 1
      v = silk_sat32(res[i] + silk_lshift_sat32(p, 4))
      s_lpc[16 + i] = v
      xq[pxq + i] = silk_sat16(silk_rshift_round(silk_smulww(v, gain_q10), 8))
      i += 1
    i = 0
    while i < 16
      s_lpc[i] = s_lpc[slen + i]
      i += 1
    pexc += slen
    pxq += slen
    k += 1
  i = 0
  while i < 16
    ds[170 + i] = s_lpc[i]
    i += 1
  0

# ---------------------------------------------------------------- PLC / CNG

-> silk_plc_reset(ds)
  ds[70] = ds[6] << 7
  ds[98] = 65536
  ds[99] = 65536
  ds[102] = 20
  ds[101] = 2

-> silk_plc_update(ds, ctrl)
  ds[17] = ds[57]
  ltp_gain = 0
  nb = ds[5]
  slen = ds[7]
  if ds[57] == 2
    j = 0
    while j * slen < ctrl[nb - 1]
      break if j == nb
      t = 0
      i = 0
      while i < 5
        t += ctrl[40 + (nb - 1 - j) * 5 + i]
        i += 1
      if t > ltp_gain
        ltp_gain = t
        i = 0
        while i < 5
          ds[71 + i] = ctrl[40 + (nb - 1 - j) * 5 + i]
          i += 1
        ds[70] = ctrl[nb - 1 - j] << 8
      j += 1
    i = 0
    while i < 5
      ds[71 + i] = 0
      i += 1
    ds[73] = ltp_gain
    if ltp_gain < 11469
      scale = (11469 << 10) / [ltp_gain, 1].max
      i = 0
      while i < 5
        ds[71 + i] = silk_smulbb(ds[71 + i], scale) >> 10
        i += 1
    elsif ltp_gain > 15565
      scale = (15565 << 14) / [ltp_gain, 1].max
      i = 0
      while i < 5
        ds[71 + i] = silk_smulbb(ds[71 + i], scale) >> 14
        i += 1
  else
    ds[70] = silk_smulbb(ds[3], 18) << 8
    i = 0
    while i < 5
      ds[71 + i] = 0
      i += 1
  i = 0
  while i < ds[9]
    ds[76 + i] = ctrl[24 + i]
    i += 1
  ds[97] = ctrl[60]
  ds[98] = ctrl[4 + nb - 2]
  ds[99] = ctrl[4 + nb - 1]
  ds[102] = slen
  ds[101] = nb

-> silk_plc_conceal(ds, ctrl, frame, fo, exc, out_buf)
  ltp_mem = ds[8]
  flen = ds[6]
  order = ds[9]
  slen = ds[7]
  nb = ds[5]
  s_ltp_q14 = i64[ltp_mem + flen]
  s_ltp = i64[ltp_mem]
  pg0 = ds[98] >> 6
  pg1 = ds[99] >> 6
  if ds[10] != 0
    i = 0
    while i < 16
      ds[76 + i] = 0
      i += 1
  # energies of the last two subframes' excitation
  eb = i64[2 * slen]
  k = 0
  while k < 2
    g = (k == 0) ? pg0 : pg1
    i = 0
    while i < slen
      eb[k * slen + i] = silk_sat16(silk_smulww(exc[i + (k + nb - 2) * slen], g) >> 8)
      i += 1
    k += 1
  e1 = i64[2]
  e2 = i64[2]
  silk_sum_sqr_shift(eb, 0, slen, e1)
  silk_sum_sqr_shift(eb, slen, slen, e2)
  rand_off = 0
  if (e1[0] >> e2[1]) < (e2[0] >> e1[1])
    rand_off = [0, (ds[101] - 1) * ds[102] - 128].max
  else
    rand_off = [0, ds[101] * ds[102] - 128].max
  b = i64[5]
  i = 0
  while i < 5
    b[i] = ds[71 + i]
    i += 1
  rand_scale = ds[94]
  att = [1, ds[16]].min
  harm_gain = (att == 0) ? 32440 : 31130
  rand_gain = 0
  if ds[17] == 2
    rand_gain = (att == 0) ? 31130 : 26214
  else
    rand_gain = (att == 0) ? 32440 : 29491
  silk_bwexpander(ds, 76, order, 64881)
  a_q12 = i64[16]
  i = 0
  while i < order
    a_q12[i] = ds[76 + i]
    i += 1
  if ds[16] == 0
    rand_scale = 16384
    if ds[17] == 2
      i = 0
      while i < 5
        rand_scale -= b[i]
        i += 1
      rand_scale = 3277 if rand_scale < 3277
      rand_scale = silk_s16(silk_smulbb(rand_scale, ds[97]) >> 14)
    else
      inv_gain = silk_lpc_inverse_pred_gain(ds, 76, order)
      down = [(1 << 30) >> 3, inv_gain].min
      down = [(1 << 30) >> 8, down].max
      down = down << 3
      rand_gain = silk_smulwb(down, rand_gain) >> 14
  seed = ds[93]
  lag = silk_rshift_round(ds[70], 8)
  s_idx = ltp_mem
  idx = ltp_mem - lag - order - 2
  silk_lpc_analysis_filter(s_ltp, idx, out_buf, idx, a_q12, 0, ltp_mem - idx, order)
  inv_gain = silk_inverse32_varq(ds[99], 46)
  inv_gain = 1073741823 if inv_gain > 1073741823
  i = idx + order
  while i < ltp_mem
    s_ltp_q14[i] = silk_smulwb(inv_gain, s_ltp[i])
    i += 1
  k = 0
  while k < nb
    pl = s_idx - lag + 2
    i = 0
    while i < slen
      p = 2
      p = silk_smlawb(p, s_ltp_q14[pl], b[0])
      p = silk_smlawb(p, s_ltp_q14[pl - 1], b[1])
      p = silk_smlawb(p, s_ltp_q14[pl - 2], b[2])
      p = silk_smlawb(p, s_ltp_q14[pl - 3], b[3])
      p = silk_smlawb(p, s_ltp_q14[pl - 4], b[4])
      pl += 1
      seed = silk_rand(seed)
      ri = (seed >> 25) & 127
      s_ltp_q14[s_idx] = silk_lshift32(silk_smlawb(p, exc[rand_off + ri], rand_scale), 2)
      s_idx += 1
      i += 1
    j = 0
    while j < 5
      b[j] = silk_smulbb(harm_gain, b[j]) >> 15
      j += 1
    rand_scale = silk_smulbb(rand_scale, rand_gain) >> 15
    ds[70] = silk_smlawb(ds[70], ds[70], 655)
    ds[70] = [ds[70], silk_smulbb(18, ds[3]) << 8].min
    lag = silk_rshift_round(ds[70], 8)
    k += 1
  base = ltp_mem - 16
  i = 0
  while i < 16
    s_ltp_q14[base + i] = ds[170 + i]
    i += 1
  silk_plc_synth(s_ltp_q14, base, a_q12, order, flen, frame, fo, pg1)
  i = 0
  while i < 16
    ds[170 + i] = s_ltp_q14[base + flen + i]
    i += 1
  ds[93] = seed
  ds[94] = rand_scale
  i = 0
  while i < 4
    ctrl[i] = lag
    i += 1

-> silk_plc_synth(s, base, a, order, flen, frame, fo, g) (i64[] i64 i64[] i64 i64 i64[] i64 i64) i64
  i = 0 ## i64
  while i < flen
    p = order >> 1
    j = 0 ## i64
    while j < order
      p = silk_smlawb(p, s[base + 16 + i - j - 1], a[j])
      j += 1
    v = silk_sat32(s[base + 16 + i] + silk_lshift_sat32(p, 4))
    s[base + 16 + i] = v
    frame[fo + i] = silk_sat16(silk_rshift_round(silk_smulww(v, g), 8))
    i += 1
  0

-> silk_plc_glue_frames(ds, frame, fo, length)
  if ds[16] != 0
    r = i64[2]
    silk_sum_sqr_shift(frame, fo, length, r)
    ds[95] = r[0]
    ds[96] = r[1]
    ds[92] = 1
  else
    if ds[92] != 0
      r = i64[2]
      silk_sum_sqr_shift(frame, fo, length, r)
      energy = r[0]
      eshift = r[1]
      if eshift > ds[96]
        ds[95] = ds[95] >> (eshift - ds[96])
      elsif eshift < ds[96]
        energy = energy >> (ds[96] - eshift)
      if energy > ds[95]
        lz = silk_clz32(ds[95]) - 1
        ds[95] = silk_lshift32(ds[95], lz)
        energy = energy >> [24 - lz, 0].max
        frac = ds[95] / [energy, 1].max
        gain = silk_sqrt_approx(frac) << 4
        slope = ((1 << 16) - gain) / length
        slope = slope << 2
        i = 0
        while i < length
          frame[fo + i] = silk_smulwb(gain, frame[fo + i])
          gain += slope
          break if gain > 65536
          i += 1
    ds[92] = 0

-> silk_cng_reset(ds)
  order = ds[9]
  step = 32767 / (order + 1)
  acc = 0
  i = 0
  while i < order
    acc += step
    ds[110 + i] = acc
    i += 1
  ds[142] = 0
  ds[143] = 3176576

-> silk_cng(ds, ctrl, frame, fo, length, exc, cng_exc)
  if ds[3] != ds[144]
    silk_cng_reset(ds)
    ds[144] = ds[3]
  order = ds[9]
  nb = ds[5]
  slen = ds[7]
  if ds[16] == 0 && ds[17] == 0
    i = 0
    while i < order
      ds[110 + i] = ds[110 + i] + silk_smulwb(ds[150 + i] - ds[110 + i], 16348)
      i += 1
    max_gain = 0
    subfr = 0
    i = 0
    while i < nb
      if ctrl[4 + i] > max_gain
        max_gain = ctrl[4 + i]
        subfr = i
      i += 1
    i = (nb - 1) * slen - 1
    while i >= 0
      cng_exc[slen + i] = cng_exc[i]
      i -= 1
    i = 0
    while i < slen
      cng_exc[i] = exc[subfr * slen + i]
      i += 1
    i = 0
    while i < nb
      ds[142] = ds[142] + silk_smulwb(ctrl[4 + i] - ds[142], 4634)
      ds[142] = ctrl[4 + i] if silk_smulww(ds[142], 46396) > ctrl[4 + i]
      i += 1
  if ds[16] != 0
    sig = i64[length + 16]
    gain = silk_smulww(ds[94], ds[99])
    if gain >= (1 << 21) || ds[142] > (1 << 23)
      gain = silk_smultt(gain, gain)
      gain = silk_w32(silk_smultt(ds[142], ds[142]) - silk_lshift32(gain, 5))
      gain = silk_lshift32(silk_sqrt_approx(gain), 16)
    else
      gain = silk_smulww(gain, gain)
      gain = silk_w32(silk_smulww(ds[142], ds[142]) - silk_lshift32(gain, 5))
      gain = silk_lshift32(silk_sqrt_approx(gain), 8)
    gain_q10 = gain >> 6
    mask = 255
    mask = mask >> 1 while mask > length
    seed = ds[143]
    i = 0
    while i < length
      seed = silk_rand(seed)
      sig[16 + i] = cng_exc[(seed >> 24) & mask]
      i += 1
    ds[143] = seed
    a_q12 = i64[16]
    silk_nlsf2a(a_q12, 0, ds, 110, order, SILK_LSFCOSTAB_FIX_Q12)
    i = 0
    while i < 16
      sig[i] = ds[126 + i]
      i += 1
    silk_cng_synth(sig, a_q12, order, length, frame, fo, gain_q10)
    i = 0
    while i < 16
      ds[126 + i] = sig[length + i]
      i += 1
  else
    i = 0
    while i < order
      ds[126 + i] = 0
      i += 1

-> silk_cng_synth(sig, a, order, length, frame, fo, g) (i64[] i64[] i64 i64 i64[] i64 i64) i64
  i = 0 ## i64
  while i < length
    p = order >> 1
    j = 0 ## i64
    while j < order
      p = silk_smlawb(p, sig[16 + i - j - 1], a[j])
      j += 1
    v = silk_sat32(sig[16 + i] + silk_lshift_sat32(p, 4))
    sig[16 + i] = v
    frame[fo + i] = silk_sat16(frame[fo + i] + silk_sat16(silk_rshift_round(silk_smulww(v, g), 8)))
    i += 1
  0

# ---------------------------------------------------------------- resampler

-> silk_resampler_init(ds, fs_in, fs_out)
  i = 190
  while i < 258
    ds[i] = 0
    i += 1
  rid_in = silk_rate_id(fs_in)
  rid_out = silk_rate_id(fs_out)
  dm = [4, 0, 2, 0, 0, 0, 9, 4, 7, 4, 0, 3, 12, 7, 7]
  ds[256] = dm[rid_in * 5 + rid_out]
  ds[254] = fs_in / 1000
  ds[255] = fs_out / 1000
  ds[252] = ds[254] * 10
  up2x = 0
  if fs_out > fs_in
    if fs_out == fs_in * 2
      ds[257] = 1
    else
      ds[257] = 2
      up2x = 1
  elsif fs_out < fs_in
    raise MediaError.new("opus: SILK resampler cannot downsample")
  else
    ds[257] = 0
  inv = (((fs_in << (14 + up2x)) / fs_out) << 2)
  inv += 1 while silk_smulww(inv, fs_out) < (fs_in << up2x)
  ds[253] = inv

-> silk_rate_id(r)
  (((r >> 12) - (r > 16000 ? 1 : 0)) >> (r > 24000 ? 1 : 0)) - 1

-> silk_up2_hq(s, so, out, oo, inp, io, len) (i64[] i64 i64[] i64 i64[] i64 i64) i64
  k = 0 ## i64
  while k < len
    in32 = inp[io + k] << 10
    y = in32 - s[so]
    x = silk_smulwb(y, 1746)
    o1 = s[so] + x
    s[so] = in32 + x
    y = o1 - s[so + 1]
    x = silk_smulwb(y, 14986)
    o2 = s[so + 1] + x
    s[so + 1] = o1 + x
    y = o2 - s[so + 2]
    x = silk_smlawb(y, y, -26453)
    o1 = s[so + 2] + x
    s[so + 2] = o2 + x
    out[oo + 2 * k] = silk_sat16(silk_rshift_round(o1, 10))
    y = in32 - s[so + 3]
    x = silk_smulwb(y, 6854)
    o1 = s[so + 3] + x
    s[so + 3] = in32 + x
    y = o1 - s[so + 4]
    x = silk_smulwb(y, 25769)
    o2 = s[so + 4] + x
    s[so + 4] = o1 + x
    y = o2 - s[so + 5]
    x = silk_smlawb(y, y, -9994)
    o1 = s[so + 5] + x
    s[so + 5] = o2 + x
    out[oo + 2 * k + 1] = silk_sat16(silk_rshift_round(o1, 10))
    k += 1
  0

# IIR_FIR resampler: returns new out position
-> silk_resampler_iir_fir(ds, out, oo0, inp, io0, in_len0, fir, buf) (i64[] i64[] i64 i64[] i64 i64 i64[] i64[]) i64
  oo = oo0
  io = io0
  in_len = in_len0
  batch = ds[252]
  i = 0 ## i64
  while i < 8
    buf[i] = ds[196 + i]
    i += 1
  inc = ds[253]
  n_in = 0 ## i64
  while true
    n_in = in_len
    n_in = batch if batch < n_in
    silk_up2_hq(ds, 190, buf, 8, inp, io, n_in)
    max_index = n_in << 17
    idx = 0 ## i64
    while idx < max_index
      ti = silk_smulwb(idx & 65535, 12)
      bp = idx >> 16
      r = buf[bp] * fir[ti * 4]
      r += buf[bp + 1] * fir[ti * 4 + 1]
      r += buf[bp + 2] * fir[ti * 4 + 2]
      r += buf[bp + 3] * fir[ti * 4 + 3]
      r += buf[bp + 4] * fir[(11 - ti) * 4 + 3]
      r += buf[bp + 5] * fir[(11 - ti) * 4 + 2]
      r += buf[bp + 6] * fir[(11 - ti) * 4 + 1]
      r += buf[bp + 7] * fir[(11 - ti) * 4]
      out[oo] = silk_sat16(silk_rshift_round(r, 15))
      oo += 1
      idx += inc
    io += n_in
    in_len -= n_in
    if in_len > 0
      i = 0
      while i < 8
        buf[i] = buf[(n_in << 1) + i]
        i += 1
    else
      break
  i = 0
  while i < 8
    ds[196 + i] = buf[(n_in << 1) + i]
    i += 1
  oo

-> silk_resampler_run(ds, out, oo, inp, io, in_len, fir, buf) (i64[] i64[] i64 i64[] i64 i64 i64[] i64[]) i64
  fin = ds[254]
  delay = ds[256]
  n = fin - delay
  i = 0 ## i64
  while i < n
    ds[204 + delay + i] = inp[io + i]
    i += 1
  dtmp = i64[48]
  i = 0
  while i < fin
    dtmp[i] = ds[204 + i]
    i += 1
  f = ds[257]
  if f == 2
    silk_resampler_iir_fir(ds, out, oo, dtmp, 0, fin, fir, buf)
    silk_resampler_iir_fir(ds, out, oo + ds[255], inp, io + n, in_len - fin, fir, buf)
  elsif f == 1
    silk_up2_hq(ds, 190, out, oo, dtmp, 0, fin)
    silk_up2_hq(ds, 190, out, oo + ds[255], inp, io + n, in_len - fin)
  else
    i = 0
    while i < fin
      out[oo + i] = dtmp[i]
      i += 1
    i = 0
    while i < in_len - fin
      out[oo + ds[255] + i] = inp[io + n + i]
      i += 1
  i = 0
  while i < delay
    ds[204 + i] = inp[io + in_len - delay + i]
    i += 1
  0

# ---------------------------------------------------------------- stereo

-> silk_stereo_decode_pred(st, buf, pred)
  n = ec_dec_icdf(st, buf, SILK_STEREO_PRED_JOINT_ICDF, 0, 8)
  ix = [[0, 0, n / 5], [0, 0, n - 5 * (n / 5)]]
  k = 0
  while k < 2
    ix[k][0] = ec_dec_icdf(st, buf, SILK_UNIFORM3_ICDF, 0, 8)
    ix[k][1] = ec_dec_icdf(st, buf, SILK_UNIFORM5_ICDF, 0, 8)
    k += 1
  k = 0
  while k < 2
    ix[k][0] = ix[k][0] + 3 * ix[k][2]
    low = SILK_STEREO_PRED_QUANT_Q13[ix[k][0]]
    step = silk_smulwb(SILK_STEREO_PRED_QUANT_Q13[ix[k][0] + 1] - low, 6554)
    pred[k] = low + silk_smulbb(step, 2 * ix[k][1] + 1)
    k += 1
  pred[0] = pred[0] - pred[1]

# x1, x2: mid/side with 2 samples of history at [o1], [o2]
-> silk_stereo_ms_to_lr(ss, x1, o1, x2, o2, pred0in, pred1in, fs_khz, flen) (i64[] i64[] i64 i64[] i64 i64 i64 i64 i64) i64
  x1[o1] = ss[2]
  x1[o1 + 1] = ss[3]
  x2[o2] = ss[4]
  x2[o2 + 1] = ss[5]
  ss[2] = x1[o1 + flen]
  ss[3] = x1[o1 + flen + 1]
  ss[4] = x2[o2 + flen]
  ss[5] = x2[o2 + flen + 1]
  p0 = ss[0]
  p1 = ss[1]
  denom = 65536 / (8 * fs_khz)
  d0 = silk_rshift_round(silk_smulbb(pred0in - ss[0], denom), 16)
  d1 = silk_rshift_round(silk_smulbb(pred1in - ss[1], denom), 16)
  n = 0 ## i64
  while n < 8 * fs_khz
    p0 += d0
    p1 += d1
    sum = silk_lshift32(x1[o1 + n] + x1[o1 + n + 2] + (x1[o1 + n + 1] << 1), 9)
    sum = silk_smlawb(x2[o2 + n + 1] << 8, sum, p0)
    sum = silk_smlawb(sum, x1[o1 + n + 1] << 11, p1)
    x2[o2 + n + 1] = silk_sat16(silk_rshift_round(sum, 8))
    n += 1
  p0 = pred0in
  p1 = pred1in
  while n < flen
    sum = silk_lshift32(x1[o1 + n] + x1[o1 + n + 2] + (x1[o1 + n + 1] << 1), 9)
    sum = silk_smlawb(x2[o2 + n + 1] << 8, sum, p0)
    sum = silk_smlawb(sum, x1[o1 + n + 1] << 11, p1)
    x2[o2 + n + 1] = silk_sat16(silk_rshift_round(sum, 8))
    n += 1
  ss[0] = pred0in
  ss[1] = pred1in
  n = 0
  while n < flen
    s = x1[o1 + n + 1] + x2[o2 + n + 1]
    d = x1[o1 + n + 1] - x2[o2 + n + 1]
    x1[o1 + n + 1] = silk_sat16(s)
    x2[o2 + n + 1] = silk_sat16(d)
    n += 1
  0

# ---------------------------------------------------------------- decoder

+ OpusSilkChan
  ro :ds, :exc, :out_buf, :cng_exc

  -> new
    @ds = i64[SILK_DS_N]
    @exc = i64[320]
    @out_buf = i64[480]
    @cng_exc = i64[320]
    init_state()

  -> init_state
    i = 0
    while i < SILK_DS_N
      @ds[i] = 0
      i += 1
    i = 0
    while i < 320
      @exc[i] = 0
      @cng_exc[i] = 0
      i += 1
    i = 0
    while i < 480
      @out_buf[i] = 0
      i += 1
    @ds[10] = 1
    @ds[0] = 65536
    silk_cng_reset(@ds)
    silk_plc_reset(@ds)

  -> set_fs(fs_khz, fs_api)
    ds = @ds
    ds[7] = 5 * fs_khz
    frame_length = ds[5] * ds[7]
    if ds[3] != fs_khz || ds[4] != fs_api
      silk_resampler_init(ds, fs_khz * 1000, fs_api)
      ds[4] = fs_api
    if ds[3] != fs_khz || frame_length != ds[6]
      if ds[3] != fs_khz
        ds[8] = 20 * fs_khz
        ds[9] = (fs_khz == 16) ? 16 : 10
        ds[10] = 1
        ds[1] = 100
        ds[2] = 10
        ds[17] = 0
        i = 0
        while i < 480
          @out_buf[i] = 0
          i += 1
        i = 0
        while i < 16
          ds[170 + i] = 0
          i += 1
      ds[3] = fs_khz
      ds[6] = frame_length

  # silk_decode_frame
  -> decode_frame(st, buf, out, oo, lost_flag, cond)
    ds = @ds
    l = ds[6]
    ctrl = i64[64]
    ctrl[60] = 0
    if lost_flag == 0 || (lost_flag == 2 && ds[23 + ds[11]] == 1)
      pulses = i64[(l + 15) & -16]
      silk_decode_indices(st, buf, ds, ds[11], lost_flag, cond)
      silk_decode_pulses(st, buf, pulses, ds[57], ds[58], l)
      silk_decode_parameters(ds, ctrl, cond)
      silk_decode_core(ds, ctrl, out, oo, pulses, @exc, @out_buf, SILK_QUANTIZATION_OFFSETS_Q10)
      mv = ds[8] - l
      silk_move_out(@out_buf, out, oo, mv, l)
      plc_check_fs()
      silk_plc_update(ds, ctrl)
      ds[16] = 0
      ds[17] = ds[57]
      ds[10] = 0
    else
      plc_check_fs()
      silk_plc_conceal(ds, ctrl, out, oo, @exc, @out_buf)
      ds[16] = ds[16] + 1
      mv = ds[8] - l
      silk_move_out(@out_buf, out, oo, mv, l)
    silk_cng(ds, ctrl, out, oo, l, @exc, @cng_exc)
    silk_plc_glue_frames(ds, out, oo, l)
    ds[1] = ctrl[ds[5] - 1]
    l

  -> plc_check_fs
    if @ds[3] != @ds[100]
      silk_plc_reset(@ds)
      @ds[100] = @ds[3]

-> silk_move_out(out_buf, out, oo, mv, l) (i64[] i64[] i64 i64 i64) i64
  i = 0 ## i64
  while i < mv
    out_buf[i] = out_buf[l + i]
    i += 1
  i = 0
  while i < l
    out_buf[mv + i] = out[oo + i]
    i += 1
  0

+ OpusSilkDec
  -> new(@channels_api)
    @ch = [OpusSilkChan.new, OpusSilkChan.new]
    @ss = i64[6]
    @n_ch_internal = 1
    @n_ch_api = 0
    @prev_decode_only_middle = 0
    @fir = SILK_RESAMPLER_FRAC_FIR_12
    @rbuf = i64[2 * 160 + 8]

  -> reset
    @ch[0].init_state()
    @ch[1].init_state()
    i = 0
    while i < 6
      @ss[i] = 0
      i += 1
    @n_ch_internal = 1
    @n_ch_api = 0
    @prev_decode_only_middle = 0

  # silk_Decode for one SILK frame (10 or 20 ms). Writes n samples (48 kHz) per
  # API channel interleaved into out (i64 int16 values) at frame offset oo.
  # Returns the number of samples written per channel.
  -> decode(st, buf, lost_flag, new_packet, payload_ms, n_ch_internal, internal_rate, out, oo)
    ch = @ch
    ds0 = ch[0].ds
    if new_packet != 0
      n = 0
      while n < n_ch_internal
        ch[n].ds[11] = 0
        n += 1
    if n_ch_internal > @n_ch_internal
      ch[1].init_state()
    stereo_to_mono = n_ch_internal == 1 && @n_ch_internal == 2 && internal_rate == 1000 * ds0[3]
    if ds0[11] == 0
      n = 0
      while n < n_ch_internal
        ds = ch[n].ds
        if payload_ms == 10
          ds[12] = 1
          ds[5] = 2
        elsif payload_ms == 20
          ds[12] = 1
          ds[5] = 4
        elsif payload_ms == 40
          ds[12] = 2
          ds[5] = 4
        elsif payload_ms == 60
          ds[12] = 3
          ds[5] = 4
        else
          raise MediaError.new("opus: bad SILK frame size")
        fs_khz = (internal_rate >> 10) + 1
        ch[n].set_fs(fs_khz, 48000)
        n += 1
    if @channels_api == 2 && n_ch_internal == 2 && (@n_ch_api == 1 || @n_ch_internal == 1)
      @ss[0] = 0
      @ss[1] = 0
      @ss[4] = 0
      @ss[5] = 0
      i = 190
      while i < 258
        ch[1].ds[i] = ds0[i]
        i += 1
    @n_ch_api = @channels_api
    @n_ch_internal = n_ch_internal
    decode_only_middle = 0
    pred = i64[2]
    if lost_flag != 1 && ds0[11] == 0
      n = 0
      while n < n_ch_internal
        ds = ch[n].ds
        i = 0
        while i < ds[12]
          ds[20 + i] = ec_dec_bit_logp(st, buf, 1)
          i += 1
        ds[15] = ec_dec_bit_logp(st, buf, 1)
        n += 1
      n = 0
      while n < n_ch_internal
        ds = ch[n].ds
        ds[23] = 0
        ds[24] = 0
        ds[25] = 0
        if ds[15] != 0
          if ds[12] == 1
            ds[23] = 1
          else
            tab = (ds[12] == 2) ? SILK_LBRR_FLAGS_2_ICDF : SILK_LBRR_FLAGS_3_ICDF
            sym = ec_dec_icdf(st, buf, tab, 0, 8) + 1
            i = 0
            while i < ds[12]
              ds[23 + i] = (sym >> i) & 1
              i += 1
        n += 1
      if lost_flag == 0
        # skip the LBRR data
        i = 0
        while i < ds0[12]
          n = 0
          while n < n_ch_internal
            ds = ch[n].ds
            if ds[23 + i] != 0
              if n_ch_internal == 2 && n == 0
                silk_stereo_decode_pred(st, buf, pred)
                if ch[1].ds[23 + i] == 0
                  decode_only_middle = ec_dec_icdf(st, buf, SILK_STEREO_ONLY_CODE_MID_ICDF, 0, 8)
              cond = (i > 0 && ds[23 + i - 1] != 0) ? 2 : 0
              silk_decode_indices(st, buf, ds, i, 1, cond)
              pulses = i64[(ds[6] + 15) & -16]
              silk_decode_pulses(st, buf, pulses, ds[57], ds[58], ds[6])
            n += 1
          i += 1
    if n_ch_internal == 2
      if lost_flag == 0 || (lost_flag == 2 && ds0[23 + ds0[11]] == 1)
        silk_stereo_decode_pred(st, buf, pred)
        if (lost_flag == 0 && ch[1].ds[20 + ds0[11]] == 0) || (lost_flag == 2 && ch[1].ds[23 + ds0[11]] == 0)
          decode_only_middle = ec_dec_icdf(st, buf, SILK_STEREO_ONLY_CODE_MID_ICDF, 0, 8)
        else
          decode_only_middle = 0
      else
        pred[0] = @ss[0]
        pred[1] = @ss[1]
    if n_ch_internal == 2 && decode_only_middle == 0 && @prev_decode_only_middle == 1
      c1 = ch[1]
      i = 0
      while i < 480
        c1.out_buf[i] = 0
        i += 1
      i = 0
      while i < 16
        c1.ds[170 + i] = 0
        i += 1
      c1.ds[1] = 100
      c1.ds[2] = 10
      c1.ds[17] = 0
      c1.ds[10] = 1
    flen = ds0[6]
    tmp1 = i64[flen + 2]
    tmp2 = i64[flen + 2]
    tmps = [tmp1, tmp2]
    has_side = 0
    if lost_flag == 0
      has_side = (decode_only_middle == 0) ? 1 : 0
    else
      has_side = (@prev_decode_only_middle == 0 || (n_ch_internal == 2 && lost_flag == 2 && ch[1].ds[23 + ch[1].ds[11]] == 1)) ? 1 : 0
    n_dec = flen
    n = 0
    while n < n_ch_internal
      ds = ch[n].ds
      if n == 0 || has_side != 0
        fi = ds0[11] - n
        cond = 0
        if fi <= 0
          cond = 0
        elsif lost_flag == 2
          cond = (ds[23 + fi - 1] != 0) ? 2 : 0
        elsif n > 0 && @prev_decode_only_middle != 0
          cond = 1
        else
          cond = 2
        n_dec = ch[n].decode_frame(st, buf, tmps[n], 2, lost_flag, cond)
      else
        i = 0
        while i < n_dec
          tmps[n][2 + i] = 0
          i += 1
      ds[11] = ds[11] + 1
      n += 1
    if @channels_api == 2 && n_ch_internal == 2
      silk_stereo_ms_to_lr(@ss, tmp1, 0, tmp2, 0, pred[0], pred[1], ds0[3], n_dec)
    else
      tmp1[0] = @ss[2]
      tmp1[1] = @ss[3]
      @ss[2] = tmp1[n_dec]
      @ss[3] = tmp1[n_dec + 1]
    n_out = (n_dec * 48000) / (ds0[3] * 1000)
    rout = i64[n_out]
    capi = @channels_api
    n = 0
    while n < [capi, n_ch_internal].min
      silk_resampler_run(ch[n].ds, rout, 0, tmps[n], 1, n_dec, @fir, @rbuf)
      silk_interleave_out(out, oo, rout, n_out, n, capi)
      n += 1
    if capi == 2 && n_ch_internal == 1
      if stereo_to_mono
        silk_resampler_run(ch[1].ds, rout, 0, tmp1, 1, n_dec, @fir, @rbuf)
        silk_interleave_out(out, oo, rout, n_out, 1, 2)
      else
        silk_dup_out(out, oo, n_out)
    if lost_flag == 1
      i = 0
      while i < @n_ch_internal
        ch[i].ds[2] = 10
        i += 1
    else
      @prev_decode_only_middle = decode_only_middle
    n_out

-> silk_interleave_out(out, oo, r, n, c, cc) (i64[] i64 i64[] i64 i64 i64) i64
  i = 0 ## i64
  while i < n
    out[(oo + i) * cc + c] = r[i]
    i += 1
  0

-> silk_dup_out(out, oo, n) (i64[] i64 i64) i64
  i = 0 ## i64
  while i < n
    out[(oo + i) * 2 + 1] = out[(oo + i) * 2]
    i += 1
  0
