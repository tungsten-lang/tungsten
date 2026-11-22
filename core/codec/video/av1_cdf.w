# core/codec/video/av1_cdf — AV1 CDF storage and the symbol (range) decoder.
#
# All adaptive CDFs of a frame context live in one i32[] "store": each CDF of
# N symbols occupies N+1 slots (N cumulative values ending 32768, then the
# adaptation counter), exactly the spec's layout, so saving/loading/copying a
# frame context is one array copy. AV1_CDF_LAYOUT maps a name to
# [offset, symbols, count] (count = number of CDFs of that name).
#
# Symbol decoder state: st = i64[8]: 0 SymbolValue, 1 SymbolRange,
# 2 SymbolMaxBits, 3 bit position, 4 disable_cdf_update.

use av1_tables

# name, default table, symbols per cdf, copies (MV contexts)
AV1_CDF_NONCOEFF = [
  [:y_mode, AV1_DEFAULT_Y_MODE_CDF, 13, 1],
  [:uv_mode_cfl_not_allowed, AV1_DEFAULT_UV_MODE_CFL_NOT_ALLOWED_CDF, 13, 1],
  [:uv_mode_cfl_allowed, AV1_DEFAULT_UV_MODE_CFL_ALLOWED_CDF, 14, 1],
  [:angle_delta, AV1_DEFAULT_ANGLE_DELTA_CDF, 7, 1],
  [:intrabc, AV1_DEFAULT_INTRABC_CDF, 2, 1],
  [:partition_w8, AV1_DEFAULT_PARTITION_W8_CDF, 4, 1],
  [:partition_w16, AV1_DEFAULT_PARTITION_W16_CDF, 10, 1],
  [:partition_w32, AV1_DEFAULT_PARTITION_W32_CDF, 10, 1],
  [:partition_w64, AV1_DEFAULT_PARTITION_W64_CDF, 10, 1],
  [:partition_w128, AV1_DEFAULT_PARTITION_W128_CDF, 8, 1],
  [:segment_id, AV1_DEFAULT_SEGMENT_ID_CDF, 8, 1],
  [:segment_id_predicted, AV1_DEFAULT_SEGMENT_ID_PREDICTED_CDF, 2, 1],
  [:tx_8x8, AV1_DEFAULT_TX_8X8_CDF, 2, 1],
  [:tx_16x16, AV1_DEFAULT_TX_16X16_CDF, 3, 1],
  [:tx_32x32, AV1_DEFAULT_TX_32X32_CDF, 3, 1],
  [:tx_64x64, AV1_DEFAULT_TX_64X64_CDF, 3, 1],
  [:txfm_split, AV1_DEFAULT_TXFM_SPLIT_CDF, 2, 1],
  [:filter_intra_mode, AV1_DEFAULT_FILTER_INTRA_MODE_CDF, 5, 1],
  [:filter_intra, AV1_DEFAULT_FILTER_INTRA_CDF, 2, 1],
  [:interp_filter, AV1_DEFAULT_INTERP_FILTER_CDF, 3, 1],
  [:motion_mode, AV1_DEFAULT_MOTION_MODE_CDF, 3, 1],
  [:new_mv, AV1_DEFAULT_NEW_MV_CDF, 2, 1],
  [:zero_mv, AV1_DEFAULT_ZERO_MV_CDF, 2, 1],
  [:ref_mv, AV1_DEFAULT_REF_MV_CDF, 2, 1],
  [:compound_mode, AV1_DEFAULT_COMPOUND_MODE_CDF, 8, 1],
  [:drl_mode, AV1_DEFAULT_DRL_MODE_CDF, 2, 1],
  [:is_inter, AV1_DEFAULT_IS_INTER_CDF, 2, 1],
  [:comp_mode, AV1_DEFAULT_COMP_MODE_CDF, 2, 1],
  [:skip_mode, AV1_DEFAULT_SKIP_MODE_CDF, 2, 1],
  [:skip, AV1_DEFAULT_SKIP_CDF, 2, 1],
  [:comp_ref, AV1_DEFAULT_COMP_REF_CDF, 2, 1],
  [:comp_bwd_ref, AV1_DEFAULT_COMP_BWD_REF_CDF, 2, 1],
  [:single_ref, AV1_DEFAULT_SINGLE_REF_CDF, 2, 1],
  [:mv_joint, AV1_DEFAULT_MV_JOINT_CDF, 4, 2],
  [:mv_class, AV1_DEFAULT_MV_CLASS_CDF, 11, 2],
  [:mv_class0_bit, AV1_DEFAULT_MV_CLASS0_BIT_CDF, 2, 4],
  [:mv_fr, AV1_DEFAULT_MV_FR_CDF, 4, 2],
  [:mv_class0_fr, AV1_DEFAULT_MV_CLASS0_FR_CDF, 4, 2],
  [:mv_class0_hp, AV1_DEFAULT_MV_CLASS0_HP_CDF, 2, 4],
  [:mv_sign, AV1_DEFAULT_MV_SIGN_CDF, 2, 4],
  [:mv_bit, AV1_DEFAULT_MV_BIT_CDF, 2, 4],
  [:mv_hp, AV1_DEFAULT_MV_HP_CDF, 2, 4],
  [:palette_y_mode, AV1_DEFAULT_PALETTE_Y_MODE_CDF, 2, 1],
  [:palette_uv_mode, AV1_DEFAULT_PALETTE_UV_MODE_CDF, 2, 1],
  [:palette_y_size, AV1_DEFAULT_PALETTE_Y_SIZE_CDF, 7, 1],
  [:palette_uv_size, AV1_DEFAULT_PALETTE_UV_SIZE_CDF, 7, 1],
  [:palette_2_y_color, AV1_DEFAULT_PALETTE_SIZE_2_Y_COLOR_CDF, 2, 1],
  [:palette_3_y_color, AV1_DEFAULT_PALETTE_SIZE_3_Y_COLOR_CDF, 3, 1],
  [:palette_4_y_color, AV1_DEFAULT_PALETTE_SIZE_4_Y_COLOR_CDF, 4, 1],
  [:palette_5_y_color, AV1_DEFAULT_PALETTE_SIZE_5_Y_COLOR_CDF, 5, 1],
  [:palette_6_y_color, AV1_DEFAULT_PALETTE_SIZE_6_Y_COLOR_CDF, 6, 1],
  [:palette_7_y_color, AV1_DEFAULT_PALETTE_SIZE_7_Y_COLOR_CDF, 7, 1],
  [:palette_8_y_color, AV1_DEFAULT_PALETTE_SIZE_8_Y_COLOR_CDF, 8, 1],
  [:palette_2_uv_color, AV1_DEFAULT_PALETTE_SIZE_2_UV_COLOR_CDF, 2, 1],
  [:palette_3_uv_color, AV1_DEFAULT_PALETTE_SIZE_3_UV_COLOR_CDF, 3, 1],
  [:palette_4_uv_color, AV1_DEFAULT_PALETTE_SIZE_4_UV_COLOR_CDF, 4, 1],
  [:palette_5_uv_color, AV1_DEFAULT_PALETTE_SIZE_5_UV_COLOR_CDF, 5, 1],
  [:palette_6_uv_color, AV1_DEFAULT_PALETTE_SIZE_6_UV_COLOR_CDF, 6, 1],
  [:palette_7_uv_color, AV1_DEFAULT_PALETTE_SIZE_7_UV_COLOR_CDF, 7, 1],
  [:palette_8_uv_color, AV1_DEFAULT_PALETTE_SIZE_8_UV_COLOR_CDF, 8, 1],
  [:delta_q, AV1_DEFAULT_DELTA_Q_CDF, 4, 1],
  [:delta_lf, AV1_DEFAULT_DELTA_LF_CDF, 4, 1],
  [:delta_lf_multi, AV1_DEFAULT_DELTA_LF_CDF, 4, 4],
  [:intra_tx_set1, AV1_DEFAULT_INTRA_TX_TYPE_SET1_CDF, 7, 1],
  [:intra_tx_set2, AV1_DEFAULT_INTRA_TX_TYPE_SET2_CDF, 5, 1],
  [:inter_tx_set1, AV1_DEFAULT_INTER_TX_TYPE_SET1_CDF, 16, 1],
  [:inter_tx_set2, AV1_DEFAULT_INTER_TX_TYPE_SET2_CDF, 12, 1],
  [:inter_tx_set3, AV1_DEFAULT_INTER_TX_TYPE_SET3_CDF, 2, 1],
  [:use_obmc, AV1_DEFAULT_USE_OBMC_CDF, 2, 1],
  [:inter_intra, AV1_DEFAULT_INTER_INTRA_CDF, 2, 1],
  [:comp_ref_type, AV1_DEFAULT_COMP_REF_TYPE_CDF, 2, 1],
  [:cfl_sign, AV1_DEFAULT_CFL_SIGN_CDF, 8, 1],
  [:uni_comp_ref, AV1_DEFAULT_UNI_COMP_REF_CDF, 2, 1],
  [:wedge_inter_intra, AV1_DEFAULT_WEDGE_INTER_INTRA_CDF, 2, 1],
  [:comp_group_idx, AV1_DEFAULT_COMP_GROUP_IDX_CDF, 2, 1],
  [:compound_idx, AV1_DEFAULT_COMPOUND_IDX_CDF, 2, 1],
  [:compound_type, AV1_DEFAULT_COMPOUND_TYPE_CDF, 2, 1],
  [:inter_intra_mode, AV1_DEFAULT_INTER_INTRA_MODE_CDF, 4, 1],
  [:wedge_index, AV1_DEFAULT_WEDGE_INDEX_CDF, 16, 1],
  [:cfl_alpha, AV1_DEFAULT_CFL_ALPHA_CDF, 16, 1],
  [:use_wiener, AV1_DEFAULT_USE_WIENER_CDF, 2, 1],
  [:use_sgrproj, AV1_DEFAULT_USE_SGRPROJ_CDF, 2, 1],
  [:restoration_type, AV1_DEFAULT_RESTORATION_TYPE_CDF, 3, 1],
  [:intra_frame_y_mode, AV1_DEFAULT_INTRA_FRAME_Y_MODE_CDF, 13, 1]
]

# coefficient cdfs: table holds 4 q contexts
AV1_CDF_COEFF = [
  [:txb_skip, AV1_DEFAULT_TXB_SKIP_CDF, 2],
  [:eob_pt_16, AV1_DEFAULT_EOB_PT_16_CDF, 5],
  [:eob_pt_32, AV1_DEFAULT_EOB_PT_32_CDF, 6],
  [:eob_pt_64, AV1_DEFAULT_EOB_PT_64_CDF, 7],
  [:eob_pt_128, AV1_DEFAULT_EOB_PT_128_CDF, 8],
  [:eob_pt_256, AV1_DEFAULT_EOB_PT_256_CDF, 9],
  [:eob_pt_512, AV1_DEFAULT_EOB_PT_512_CDF, 10],
  [:eob_pt_1024, AV1_DEFAULT_EOB_PT_1024_CDF, 11],
  [:eob_extra, AV1_DEFAULT_EOB_EXTRA_CDF, 2],
  [:dc_sign, AV1_DEFAULT_DC_SIGN_CDF, 2],
  [:coeff_base_eob, AV1_DEFAULT_COEFF_BASE_EOB_CDF, 3],
  [:coeff_base, AV1_DEFAULT_COEFF_BASE_CDF, 4],
  [:coeff_br, AV1_DEFAULT_COEFF_BR_CDF, 4]
]

# [layout hash, total size, noncoeff default i32[], coeff defaults [4 x [off, i32[]]]]
-> av1_cdf_build
  lay = {}
  off = 0
  noncoeff = []
  AV1_CDF_NONCOEFF.each ->(e)
    tb = e[1]
    copies = e[3]
    lay[e[0]] = [off, e[2], (tb.size / (e[2] + 1)) * copies, tb.size]
    c = 0
    while c < copies
      tb.each ->(v) noncoeff.push(v)
      c += 1
    off += tb.size * copies
  coeff_start = off
  AV1_CDF_COEFF.each ->(e)
    q = e[1].size / 4
    lay[e[0]] = [off, e[2], q / (e[2] + 1), q]
    off += q
  total = off
  base = i32[total]
  i = 0
  while i < noncoeff.size
    base[i] = noncoeff[i]
    i += 1
  qs = []
  qi = 0
  while qi < 4
    a = i32[total - coeff_start]
    p = 0
    AV1_CDF_COEFF.each ->(e)
      tb = e[1]
      q = tb.size / 4
      j = 0
      while j < q
        a[p + j] = tb[qi * q + j]
        j += 1
      p += q
    qs.push(a)
    qi += 1
  [lay, total, base, qs, coeff_start]

AV1_CDF = av1_cdf_build()
AV1_CDF_LAYOUT = AV1_CDF[0]

-> av1_cdf_off(name)
  AV1_CDF_LAYOUT[name][0]

-> av1_cdf_new_noncoeff
  st = i32[AV1_CDF[1]]
  av1_copy_i32(AV1_CDF[2], 0, st, 0, AV1_CDF[4])
  st

-> av1_cdf_init_coeff(st, base_q_idx)
  idx = 3
  if base_q_idx <= 20
    idx = 0
  elsif base_q_idx <= 60
    idx = 1
  elsif base_q_idx <= 120
    idx = 2
  src = AV1_CDF[3][idx]
  av1_copy_i32(src, 0, st, AV1_CDF[4], src.size)

-> av1_cdf_copy(st)
  out = i32[st.size]
  av1_copy_i32(st, 0, out, 0, st.size)
  out

-> av1_copy_i32(src, so, dst, d0, n) (i32[] i64 i32[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[d0 + i] = src[so + i]
    i += 1
  n

# Zero the counter slot of every cdf (load_cdfs / frame end).
-> av1_cdf_clear_counts(st)
  AV1_CDF_LAYOUT.each ->(k, v)
    av1_clear_cnt(st, v[0], v[1] + 1, v[2])
  nil

-> av1_clear_cnt(st, off, stride, n) (i32[] i64 i64 i64) i64
  i = 0 ## i64
  while i < n
    st[off + i * stride + stride - 1] = 0
    i += 1
  0

# ---------------------------------------------------------------- symbol decoder

-> av1_rd_bits(d, pos, n, endpos) (u8[] i64 i64 i64) i64
  x = 0 ## i64
  i = 0 ## i64
  while i < n
    p = (pos + i) ## i64
    bit = 0 ## i64
    if p < endpos
      bit = (d[p >> 3] >> (7 - (p & 7))) & 1
    x = (x << 1) | bit
    i += 1
  x

# st: 0 value, 1 range, 2 maxbits, 3 bitpos, 4 disable update, 5 end bitpos
-> av1_sym_init(st, d, pos, sz, disable) (i64[] u8[] i64 i64 i64) i64
  nb = (sz * 8) ## i64
  nb = 15 if nb > 15
  st[3] = pos * 8
  st[5] = (pos + sz) * 8
  buf = (av1_rd_bits(d, st[3], nb, st[5])) ## i64
  st[3] = st[3] + nb
  padded = (buf << (15 - nb)) ## i64
  st[0] = 32767 ^ padded
  st[1] = 32768
  st[2] = 8 * sz - 15
  st[4] = disable
  0

-> av1_floor_log2(x) (i64) i64
  s = 0 ## i64
  while x > 1
    x = x >> 1
    s += 1
  s

-> av1_renorm(st, d, rng, val) (i64[] u8[] i64 i64) i64
  bits = (15 - av1_floor_log2(rng)) ## i64
  rng = rng << bits
  mb = (st[2]) ## i64
  nb = (bits) ## i64
  if mb < nb
    nb = mb
  nb = 0 if nb < 0
  nd = (av1_rd_bits(d, st[3], nb, st[5])) ## i64
  st[3] = st[3] + nb
  padded = (nd << (bits - nb)) ## i64
  st[0] = padded ^ (((val + 1) << bits) - 1)
  st[1] = rng
  st[2] = mb - bits
  0

# read_symbol on cdf[off .. off+n] (n symbols)
-> av1_sym(st, d, cdf, off, n) (i64[] u8[] i32[] i64 i64) i64
  rng = (st[1]) ## i64
  val = (st[0]) ## i64
  cur = (rng) ## i64
  prev = (rng) ## i64
  sym = -1 ## i64
  r8 = (rng >> 8) ## i64
  while true
    sym += 1
    prev = cur
    fv = (32768 - cdf[off + sym]) ## i64
    cur = ((r8 * (fv >> 6)) >> 1) + 4 * (n - sym - 1)
    break if val >= cur
  av1_renorm(st, d, prev - cur, val - cur)
  if st[4] == 0
    cnt = (cdf[off + n]) ## i64
    rate = (3 + (cnt > 15 ? 1 : 0) + (cnt > 31 ? 1 : 0)) ## i64
    rate += n >= 4 ? 2 : (n >= 2 ? 1 : 0)
    i = 0 ## i64
    while i < n - 1
      c = (cdf[off + i]) ## i64
      if i >= sym
        cdf[off + i] = c + ((32768 - c) >> rate)
      else
        cdf[off + i] = c - (c >> rate)
      i += 1
    cdf[off + n] = cnt + (cnt < 32 ? 1 : 0)
  sym

-> av1_bool(st, d) (i64[] u8[]) i64
  rng = (st[1]) ## i64
  val = (st[0]) ## i64
  r8 = (rng >> 8) ## i64
  cur = ((r8 * (16384 >> 6)) >> 1) ## i64
  cur += 4
  if val < cur
    # symbol 1? no: symbol 0 continues while val < cur
    cur2 = 0 ## i64
    # second iteration: f = 0 → cur2 = 0
    av1_renorm(st, d, cur - cur2, val - cur2)
    return 1
  av1_renorm(st, d, rng - cur, val - cur)
  0

-> av1_lit(st, d, n) (i64[] u8[] i64) i64
  x = 0 ## i64
  i = 0 ## i64
  while i < n
    x = 2 * x + av1_bool(st, d)
    i += 1
  x

# exit_symbol: returns nothing (tile sizes are explicit)
