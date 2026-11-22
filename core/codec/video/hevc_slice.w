# core/codec/video/hevc_slice — HEVC slice segment data decoding (7.3.8, 9.3): the
# coding tree unit loop body, SAO syntax, coding quadtree, coding unit,
# prediction / transform trees and residual coding, with intra prediction and
# inverse transforms applied as each transform unit is parsed.
#
# Everything here is typed functions over a handful of flat arrays:
#   d   u8[]  slice segment data (rbsp)
#   cab i64[] CABAC engine + contexts (core/codec/video/hevc_cabac.w)
#   st  i64[] decoder registers (HS_*): SPS/PPS/slice parameters, CU state
#   tb  i32[] constant tables (core/codec/video/hevc_tables.w)
#   mp  i32[] per-4x4 maps and per-CTB arrays (offsets in st[HS_M_*])
#   px  u16[] picture buffer(s): the current picture's planes start at
#             st[HS_PY], st[HS_PCB], st[HS_PCR]; inter prediction reads
#             reference pictures from the same buffer (the DPB)
#   cf  i32[] scratch: coefficients, transform temp, reference samples,
#             scaling factors (HF_*)

use hevc_cabac

# ---- st registers
HS_W = 0
HS_H = 1
HS_CT = 2
HS_SSX = 3
HS_SSY = 4
HS_BDY = 5
HS_BDC = 6
HS_CTB = 7
HS_MINCB = 8
HS_MINTB = 9
HS_MAXTB = 10
HS_THD_INTRA = 11
HS_THD_INTER = 12
HS_SL = 13
HS_AMP = 14
HS_SAO_EN = 15
HS_PCM = 16
HS_PCM_BDY = 17
HS_PCM_BDC = 18
HS_PCM_MIN = 19
HS_PCM_MAX = 20
HS_PCM_LFDIS = 21
HS_STRONG = 22
HS_TS_ROT = 23
HS_TS_CTX = 24
HS_IMPL_RDPCM = 25
HS_EXPL_RDPCM = 26
HS_SMOOTH_DIS = 27
HS_PERSIST_RICE = 28
HS_CTBW = 29
HS_CTBH = 30
HS_W4 = 31
HS_H4 = 32
HS_SIGNHIDE = 33
HS_CIP = 34
HS_TS = 35
HS_LOG2MAXTS = 36
HS_CUQPD = 37
HS_LOG2QG = 38
HS_CBOFF = 39
HS_CROFF = 40
HS_TQB = 41
HS_CROSS = 42
HS_CQPO_LIST = 43
HS_LOG2CQPO = 44
HS_CQPO_LEN = 45
HS_SAO_SHY = 46
HS_SAO_SHC = 47
HS_PARMRG = 48
HS_STYPE = 49
HS_SQP = 50
HS_SAO_L = 51
HS_SAO_C = 52
HS_SCBOFF = 53
HS_SCROFF = 54
HS_CQPO_EN = 55
HS_SLICE_ADDR = 56
HS_MAXMERGE = 57
HS_NREF0 = 58
HS_NREF1 = 59
HS_MVDL1Z = 60
HS_PY = 61
HS_PCB = 62
HS_PCR = 63
HS_CW = 64
HS_CH = 65
HS_M_DEPTH = 66
HS_M_IPM = 67
HS_M_FLAGS = 68
HS_M_QP = 69
HS_M_EDGE = 70
HS_M_ZS = 71
HS_C_SADDR = 72
HS_C_TILE = 73
HS_C_SAO = 74
HS_C_SIDX = 75
# CU / CTB state
HS_CTB_RS = 80
HS_CTB_X = 81
HS_CTB_Y = 82
HS_CU_TQB = 83
HS_CU_PRED = 84
HS_CU_PART = 85
HS_QPY = 86
HS_QPY_PRED = 87
HS_LAST_QPY = 88
HS_QPD_CODED = 89
HS_QPD_VAL = 90
HS_CQPO_CODED = 91
HS_CUQPO_CB = 92
HS_CUQPO_CR = 93
HS_IPM = 94
HS_IPMC = 98
HS_CHROMA_SYN = 102
HS_MERGE = 106
HS_SAO_LUMA_ON = 107
HS_SLICE_IDX = 108
HS_ERROR = 109
HS_RES_SCALE = 110
HS_INTRA_SPLIT = 111
HS_MAX_TDEPTH = 112
HS_CTB_TS = 113
HS_C_RS2TS = 114
HS_TILE_X0 = 115
HS_TILE_Y0 = 116
HS_TILE_X1 = 117
HS_TILE_Y1 = 118
HS_CQPO_CB = 120
HS_CQPO_CR = 126
# inter prediction registers live in core/codec/video/hevc_inter.w (HS_I_*, 160+)
HS_SIZE = 640

# ---- cf scratch
HF_COEF = 0
HF_TMP = 1024
HF_RES = 2048
HF_REF = 3072
HF_CSBF = 3584
HF_SIG = 3648
HF_RESY = 3712
HF_SF = 4800
HF_P0 = 13000
HF_P1 = 17100
HF_PT = 21200
HF_MC = 25800
HF_PS = 26000
HF_SIZE = 31300

# ---- map flags
HM_INTRA = 1
HM_SKIP = 2
HM_PCM = 4
HM_TQB = 8
HM_NZ = 16
HM_INTER = 32

# ---------------------------------------------------------------- availability (6.4.1)

-> hv_avail(st, mp, xc, yc, xn, yn) (i64[] i32[] i64 i64 i64 i64) i64
  if xn < 0 || yn < 0 || xn >= st[HS_W] || yn >= st[HS_H]
    return 0
  w4 = (st[HS_W4]) ## i64
  zo = (st[HS_M_ZS]) ## i64
  if mp[zo + (yn >> 2) * w4 + (xn >> 2)] > mp[zo + (yc >> 2) * w4 + (xc >> 2)]
    return 0
  l = (st[HS_CTB]) ## i64
  cw = (st[HS_CTBW]) ## i64
  cn = ((yn >> l) * cw + (xn >> l)) ## i64
  cc = ((yc >> l) * cw + (xc >> l)) ## i64
  if cn == cc
    return 1
  sa = (st[HS_C_SADDR]) ## i64
  if mp[sa + cn] != mp[sa + cc]
    return 0
  ti = (st[HS_C_TILE]) ## i64
  if mp[ti + cn] != mp[ti + cc]
    return 0
  1

-> hv_fill_map(mp, off, w4, x0, y0, w, h, v) (i32[] i64 i64 i64 i64 i64 i64 i64) i64
  y = (y0 >> 2) ## i64
  ye = ((y0 + h + 3) >> 2) ## i64
  xs = (x0 >> 2) ## i64
  xe = ((x0 + w + 3) >> 2) ## i64
  while y < ye
    o = (off + y * w4) ## i64
    x = (xs) ## i64
    while x < xe
      mp[o + x] = v
      x += 1
    y += 1
  0

-> hv_or_map(mp, off, w4, x0, y0, w, h, v) (i32[] i64 i64 i64 i64 i64 i64 i64) i64
  y = (y0 >> 2) ## i64
  ye = ((y0 + h + 3) >> 2) ## i64
  xs = (x0 >> 2) ## i64
  xe = ((x0 + w + 3) >> 2) ## i64
  while y < ye
    o = (off + y * w4) ## i64
    x = (xs) ## i64
    while x < xe
      mp[o + x] = mp[o + x] | v
      x += 1
    y += 1
  0

# ---------------------------------------------------------------- SAO syntax (7.3.8.3)

# per CTB: 3 components x 7 ints: type, band position / eo class, offsets[4] (scaled), unused
-> hv_sao(d, cab, st, tb, mp) (u8[] i64[] i64[] i32[] i32[]) i64
  rs = (st[HS_CTB_RS]) ## i64
  cw = (st[HS_CTBW]) ## i64
  rx = (rs % cw) ## i64
  ry = (rs / cw) ## i64
  so = (st[HS_C_SAO]) ## i64
  base = (so + rs * 21) ## i64
  ml = 0 ## i64
  mu = 0 ## i64
  sa = (st[HS_C_SADDR]) ## i64
  ti = (st[HS_C_TILE]) ## i64
  if rx > 0
    lin = mp[sa + rs - 1] == st[HS_SLICE_ADDR]
    # left CTB must be in the same slice *segment*: CtbAddrInRs-1 >= SliceAddrRs is
    # implied by same slice address and raster order within a segment.
    if lin && mp[ti + rs - 1] == mp[ti + rs]
      ml = hv_bin(cab, d, tb, HC_SAO_MERGE)
  if ry > 0 && ml == 0
    uin = mp[sa + rs - cw] == st[HS_SLICE_ADDR]
    if uin && mp[ti + rs - cw] == mp[ti + rs]
      mu = hv_bin(cab, d, tb, HC_SAO_MERGE)
  if ml != 0 || mu != 0
    src = (so + (rs - 1) * 21) ## i64
    src = so + (rs - cw) * 21 if mu != 0
    k = 0 ## i64
    while k < 21
      mp[base + k] = mp[src + k]
      k += 1
    return 0
  k = 0 ## i64
  while k < 21
    mp[base + k] = 0
    k += 1
  nc = 3 ## i64
  nc = 1 if st[HS_CT] == 0
  c = 0 ## i64
  while c < nc
    en = 0 ## i64
    en = 1 if c == 0 && st[HS_SAO_L] != 0
    en = 1 if c > 0 && st[HS_SAO_C] != 0
    if en != 0
      o = (base + c * 7) ## i64
      typ = 0 ## i64
      if c == 2
        typ = mp[base + 7]
      else
        if hv_bin(cab, d, tb, HC_SAO_TYPE) != 0
          typ = hv_bypass(cab, d) == 0 ? 1 : 2
      mp[o] = typ
      if typ != 0
        bd = (c == 0 ? st[HS_BDY] : st[HS_BDC]) ## i64
        bdm = (bd) ## i64
        bdm = 10 if bdm > 10
        cmax = ((1 << (bdm - 5)) - 1) ## i64
        sh = (c == 0 ? st[HS_SAO_SHY] : st[HS_SAO_SHC]) ## i64
        i = 0 ## i64
        while i < 4
          v = 0 ## i64
          while v < cmax && hv_bypass(cab, d) != 0
            v += 1
          mp[o + 2 + i] = v
          i += 1
        if typ == 1
          i = 0
          while i < 4
            if mp[o + 2 + i] != 0 && hv_bypass(cab, d) != 0
              mp[o + 2 + i] = 0 - mp[o + 2 + i]
            i += 1
          mp[o + 1] = hv_bypass_n(cab, d, 5)
        else
          mp[o + 4] = 0 - mp[o + 4]
          mp[o + 5] = 0 - mp[o + 5]
          if c == 0
            mp[o + 1] = hv_bypass_n(cab, d, 2)
          elsif c == 1
            mp[o + 1] = hv_bypass_n(cab, d, 2)
          else
            mp[o + 1] = mp[base + 8]
        i = 0
        while i < 4
          mp[o + 2 + i] = mp[o + 2 + i] << sh
          i += 1
    c += 1
  0

# ---------------------------------------------------------------- coding quadtree

-> hv_cqt(d, cab, st, tb, mp, px, cf, x0, y0, log2, depth) (u8[] i64[] i64[] i32[] i32[] u16[] i32[] i64 i64 i64 i64) i64
  s = (1 << log2) ## i64
  split = 0 ## i64
  if x0 + s <= st[HS_W] && y0 + s <= st[HS_H] && log2 > st[HS_MINCB]
    ctx = 0 ## i64
    w4 = (st[HS_W4]) ## i64
    dm = (st[HS_M_DEPTH]) ## i64
    if hv_avail(st, mp, x0, y0, x0 - 1, y0) != 0 && mp[dm + (y0 >> 2) * w4 + ((x0 - 1) >> 2)] > depth
      ctx += 1
    if hv_avail(st, mp, x0, y0, x0, y0 - 1) != 0 && mp[dm + ((y0 - 1) >> 2) * w4 + (x0 >> 2)] > depth
      ctx += 1
    split = hv_bin(cab, d, tb, HC_SPLIT_CU + ctx)
  elsif log2 > st[HS_MINCB]
    split = 1
  if st[HS_CUQPD] != 0 && log2 >= st[HS_LOG2QG]
    st[HS_QPD_CODED] = 0
    st[HS_QPD_VAL] = 0
    hv_qp_pred(st, mp, x0, y0)
  if st[HS_CQPO_EN] != 0 && log2 >= st[HS_LOG2CQPO]
    st[HS_CQPO_CODED] = 0
  if split != 0
    h = (s >> 1) ## i64
    hv_cqt(d, cab, st, tb, mp, px, cf, x0, y0, log2 - 1, depth + 1)
    if x0 + h < st[HS_W]
      hv_cqt(d, cab, st, tb, mp, px, cf, x0 + h, y0, log2 - 1, depth + 1)
    if y0 + h < st[HS_H]
      hv_cqt(d, cab, st, tb, mp, px, cf, x0, y0 + h, log2 - 1, depth + 1)
    if x0 + h < st[HS_W] && y0 + h < st[HS_H]
      hv_cqt(d, cab, st, tb, mp, px, cf, x0 + h, y0 + h, log2 - 1, depth + 1)
    return 0
  if st[HS_CUQPD] == 0
    st[HS_QPY_PRED] = st[HS_SQP]
  hv_cu(d, cab, st, tb, mp, px, cf, x0, y0, log2, depth)

# QP predictor for the quantization group at (xq, yq) (8.6.1).
-> hv_qp_pred(st, mp, xq, yq) (i64[] i32[] i64 i64) i64
  prev = (st[HS_LAST_QPY]) ## i64
  w4 = (st[HS_W4]) ## i64
  qo = (st[HS_M_QP]) ## i64
  l = (st[HS_CTB]) ## i64
  cw = (st[HS_CTBW]) ## i64
  ctb = ((yq >> l) * cw + (xq >> l)) ## i64
  qa = (prev) ## i64
  if hv_avail(st, mp, xq, yq, xq - 1, yq) != 0 && ((yq >> l) * cw + ((xq - 1) >> l)) == ctb
    qa = mp[qo + (yq >> 2) * w4 + ((xq - 1) >> 2)]
  qb = (prev) ## i64
  if hv_avail(st, mp, xq, yq, xq, yq - 1) != 0 && (((yq - 1) >> l) * cw + (xq >> l)) == ctb
    qb = mp[qo + ((yq - 1) >> 2) * w4 + (xq >> 2)]
  st[HS_QPY_PRED] = (qa + qb + 1) >> 1
  0

-> hv_set_qpy(st) (i64[]) i64
  off = (6 * (st[HS_BDY] - 8)) ## i64
  st[HS_QPY] = ((st[HS_QPY_PRED] + st[HS_QPD_VAL] + 52 + 2 * off) % (52 + off)) - off
  0

# ---------------------------------------------------------------- coding unit (7.3.8.5)

-> hv_cu(d, cab, st, tb, mp, px, cf, x0, y0, log2, depth) (u8[] i64[] i64[] i32[] i32[] u16[] i32[] i64 i64 i64 i64) i64
  s = (1 << log2) ## i64
  w4 = (st[HS_W4]) ## i64
  hv_set_qpy(st)
  tqb = 0 ## i64
  if st[HS_TQB] != 0
    tqb = hv_bin(cab, d, tb, HC_TQ_BYPASS)
  st[HS_CU_TQB] = tqb
  st[HS_CUQPO_CB] = 0 if st[HS_CQPO_EN] == 0
  st[HS_CUQPO_CR] = 0 if st[HS_CQPO_EN] == 0
  hv_fill_map(mp, st[HS_M_DEPTH], w4, x0, y0, s, s, depth)
  skip = 0 ## i64
  if st[HS_STYPE] != 2
    ctx = 0 ## i64
    fo = (st[HS_M_FLAGS]) ## i64
    if hv_avail(st, mp, x0, y0, x0 - 1, y0) != 0 && (mp[fo + (y0 >> 2) * w4 + ((x0 - 1) >> 2)] & HM_SKIP) != 0
      ctx += 1
    if hv_avail(st, mp, x0, y0, x0, y0 - 1) != 0 && (mp[fo + ((y0 - 1) >> 2) * w4 + (x0 >> 2)] & HM_SKIP) != 0
      ctx += 1
    skip = hv_bin(cab, d, tb, HC_CU_SKIP + ctx)
  flags = 0 ## i64
  flags = HM_TQB if tqb != 0
  if skip != 0
    flags = flags | HM_SKIP | HM_INTER
    hv_fill_map(mp, st[HS_M_FLAGS], w4, x0, y0, s, s, flags)
    hv_fill_map(mp, st[HS_M_IPM], w4, x0, y0, s, s, 1)
    st[HS_CU_PRED] = 0
    st[HS_CU_PART] = 0
    hv_inter_pu(d, cab, st, tb, mp, px, cf, x0, y0, s, s, x0, y0, s, 0, 1)
    hv_mark_cu_edges(st, mp, x0, y0, s)
    hv_fill_map(mp, st[HS_M_QP], w4, x0, y0, s, s, st[HS_QPY])
    st[HS_LAST_QPY] = st[HS_QPY]
    return 0
  intra = 1 ## i64
  if st[HS_STYPE] != 2
    intra = hv_bin(cab, d, tb, HC_PRED_MODE)
  st[HS_CU_PRED] = intra
  part = 0 ## i64
  if intra != 0
    if log2 == st[HS_MINCB]
      part = hv_bin(cab, d, tb, HC_PART_MODE) == 0 ? 3 : 0
  else
    part = hv_part_mode_inter(d, cab, st, tb, log2)
  st[HS_CU_PART] = part
  if intra != 0
    flags = flags | HM_INTRA
  else
    flags = flags | HM_INTER
  pcm = 0 ## i64
  if intra != 0
    if part == 0 && st[HS_PCM] != 0 && log2 >= st[HS_PCM_MIN] && log2 <= st[HS_PCM_MAX]
      pcm = hv_term(cab, d)
    if pcm != 0
      flags = flags | HM_PCM
    hv_fill_map(mp, st[HS_M_FLAGS], w4, x0, y0, s, s, flags)
    if pcm != 0
      hv_fill_map(mp, st[HS_M_IPM], w4, x0, y0, s, s, 1)
      hv_pcm(d, cab, st, px, x0, y0, log2)
      hv_mark_cu_edges(st, mp, x0, y0, s)
      hv_fill_map(mp, st[HS_M_QP], w4, x0, y0, s, s, st[HS_QPY])
      st[HS_LAST_QPY] = st[HS_QPY]
      return 0
    hv_intra_modes(d, cab, st, tb, mp, x0, y0, log2, part)
  else
    hv_fill_map(mp, st[HS_M_FLAGS], w4, x0, y0, s, s, flags)
    hv_fill_map(mp, st[HS_M_IPM], w4, x0, y0, s, s, 1)
    hv_inter_cu(d, cab, st, tb, mp, px, cf, x0, y0, log2, part)
  rqt = 1 ## i64
  if intra == 0 && !(part == 0 && st[HS_MERGE] != 0)
    rqt = hv_bin(cab, d, tb, HC_RQT_ROOT)
  hv_mark_cu_edges(st, mp, x0, y0, s)
  if rqt != 0
    st[HS_INTRA_SPLIT] = (intra != 0 && part == 3) ? 1 : 0
    if intra != 0
      st[HS_MAX_TDEPTH] = st[HS_THD_INTRA] + st[HS_INTRA_SPLIT]
    else
      st[HS_MAX_TDEPTH] = st[HS_THD_INTER]
    hv_tt(d, cab, st, tb, mp, px, cf, x0, y0, x0, y0, log2, 0, 0, 1, 1)
  hv_fill_map(mp, st[HS_M_QP], w4, x0, y0, s, s, st[HS_QPY])
  st[HS_LAST_QPY] = st[HS_QPY]
  0

# CU boundary = transform/prediction edge for deblocking (left and top)
-> hv_mark_cu_edges(st, mp, x0, y0, s) (i64[] i32[] i64 i64 i64) i64
  w4 = (st[HS_W4]) ## i64
  eo = (st[HS_M_EDGE]) ## i64
  if (x0 & 7) == 0
    y = 0 ## i64
    while y < s && y0 + y < st[HS_H]
      i = (eo + ((y0 + y) >> 2) * w4 + (x0 >> 2)) ## i64
      mp[i] = mp[i] | 3
      y += 4
  if (y0 & 7) == 0
    x = 0 ## i64
    while x < s && x0 + x < st[HS_W]
      i = eo + (y0 >> 2) * w4 + ((x0 + x) >> 2)
      mp[i] = mp[i] | 12
      x += 4
  0

-> hv_part_mode_inter(d, cab, st, tb, log2) (u8[] i64[] i64[] i32[] i64) i64
  if hv_bin(cab, d, tb, HC_PART_MODE) != 0
    return 0
  if log2 == st[HS_MINCB]
    if hv_bin(cab, d, tb, HC_PART_MODE + 1) != 0
      return 1
    if log2 == 3
      return 2
    if hv_bin(cab, d, tb, HC_PART_MODE + 2) != 0
      return 2
    return 3
  amp = (st[HS_AMP]) ## i64
  if hv_bin(cab, d, tb, HC_PART_MODE + 1) != 0
    if amp == 0
      return 1
    if hv_bin(cab, d, tb, HC_PART_MODE + 3) != 0
      return 1
    return hv_bypass(cab, d) == 0 ? 4 : 5
  if amp == 0
    return 2
  if hv_bin(cab, d, tb, HC_PART_MODE + 3) != 0
    return 2
  hv_bypass(cab, d) == 0 ? 6 : 7

# PCM samples (7.3.8.7): raw bits right after the pcm_flag terminate bin.
-> hv_pcm(d, cab, st, px, x0, y0, log2) (u8[] i64[] i64[] u16[] i64 i64 i64) i64
  pos = (cab[HB_POS] * 8) ## i64
  s = (1 << log2) ## i64
  w = (st[HS_W]) ## i64
  bdy = (st[HS_PCM_BDY]) ## i64
  y = 0 ## i64
  while y < s
    x = 0 ## i64
    while x < s
      v = (hv_getbits(d, cab[HB_END], pos, bdy)) ## i64
      pos += bdy
      px[st[HS_PY] + (y0 + y) * w + x0 + x] = v << (st[HS_BDY] - bdy)
      x += 1
    y += 1
  if st[HS_CT] != 0
    cwid = (st[HS_CW]) ## i64
    sw = (s >> st[HS_SSX]) ## i64
    sh = (s >> st[HS_SSY]) ## i64
    bdc = (st[HS_PCM_BDC]) ## i64
    c = 0 ## i64
    while c < 2
      po = (c == 0 ? st[HS_PCB] : st[HS_PCR]) ## i64
      y = 0
      while y < sh
        x = 0
        while x < sw
          v = hv_getbits(d, cab[HB_END], pos, bdc)
          pos += bdc
          px[po + ((y0 >> st[HS_SSY]) + y) * cwid + (x0 >> st[HS_SSX]) + x] = v << (st[HS_BDC] - bdc)
          x += 1
        y += 1
      c += 1
  hv_cabac_start(cab, d, (pos + 7) >> 3, cab[HB_END])
  0

# Luma / chroma intra prediction modes for the CU (7.3.8.5, 8.4.2, 8.4.3).
-> hv_intra_modes(d, cab, st, tb, mp, x0, y0, log2, part) (u8[] i64[] i64[] i32[] i32[] i64 i64 i64 i64) i64
  s = (1 << log2) ## i64
  nb = 1 ## i64
  pb = (s) ## i64
  if part == 3
    nb = 4
    pb = s >> 1
  prev = i64[4]
  i = 0 ## i64
  while i < nb
    prev[i] = hv_bin(cab, d, tb, HC_PREV_INTRA)
    i += 1
  w4 = (st[HS_W4]) ## i64
  io = (st[HS_M_IPM]) ## i64
  fo = (st[HS_M_FLAGS]) ## i64
  i = 0
  while i < nb
    xp = (x0 + (i & 1) * pb) ## i64
    yp = (y0 + (i >> 1) * pb) ## i64
    ca = 1 ## i64
    if hv_avail(st, mp, xp, yp, xp - 1, yp) != 0
      f = (mp[fo + (yp >> 2) * w4 + ((xp - 1) >> 2)]) ## i64
      if (f & HM_INTRA) != 0 && (f & HM_PCM) == 0
        ca = mp[io + (yp >> 2) * w4 + ((xp - 1) >> 2)]
    cb = 1 ## i64
    if hv_avail(st, mp, xp, yp, xp, yp - 1) != 0 && yp - 1 >= ((yp >> st[HS_CTB]) << st[HS_CTB])
      f = mp[fo + ((yp - 1) >> 2) * w4 + (xp >> 2)]
      if (f & HM_INTRA) != 0 && (f & HM_PCM) == 0
        cb = mp[io + ((yp - 1) >> 2) * w4 + (xp >> 2)]
    m0 = 0 ## i64
    m1 = 0 ## i64
    m2 = 0 ## i64
    if ca == cb
      if ca < 2
        m0 = 0
        m1 = 1
        m2 = 26
      else
        m0 = ca
        m1 = 2 + ((ca + 29) % 32)
        m2 = 2 + ((ca - 2 + 1) % 32)
    else
      m0 = ca
      m1 = cb
      if ca != 0 && cb != 0
        m2 = 0
      elsif ca != 1 && cb != 1
        m2 = 1
      else
        m2 = 26
    mode = 0 ## i64
    if prev[i] != 0
      idx = 0 ## i64
      if hv_bypass(cab, d) != 0
        idx = 1
        idx = 2 if hv_bypass(cab, d) != 0
      mode = m0
      mode = m1 if idx == 1
      mode = m2 if idx == 2
    else
      mode = hv_bypass_n(cab, d, 5)
      # sort candidates ascending
      t = 0 ## i64
      if m0 > m1
        t = m0
        m0 = m1
        m1 = t
      if m0 > m2
        t = m0
        m0 = m2
        m2 = t
      if m1 > m2
        t = m1
        m1 = m2
        m2 = t
      mode += 1 if mode >= m0
      mode += 1 if mode >= m1
      mode += 1 if mode >= m2
    st[HS_IPM + i] = mode
    hv_fill_map(mp, io, w4, xp, yp, pb, pb, mode)
    i += 1
  if nb == 1
    st[HS_IPM + 1] = st[HS_IPM]
    st[HS_IPM + 2] = st[HS_IPM]
    st[HS_IPM + 3] = st[HS_IPM]
  ct = (st[HS_CT]) ## i64
  if ct == 0
    return 0
  nc = 1 ## i64
  nc = nb if ct == 3
  i = 0
  while i < nc
    syn = 4 ## i64
    if hv_bin(cab, d, tb, HC_CHROMA_MODE) != 0
      syn = hv_bypass_n(cab, d, 2)
    st[HS_CHROMA_SYN + i] = syn
    lm = (st[HS_IPM + i]) ## i64
    cm = (lm) ## i64
    if syn < 4
      cm = 0
      cm = 26 if syn == 1
      cm = 10 if syn == 2
      cm = 1 if syn == 3
      cm = 34 if cm == lm
    if ct == 2
      cm = tb[HT_MODE422 + cm]
    st[HS_IPMC + i] = cm
    i += 1
  if nc == 1
    st[HS_IPMC + 1] = st[HS_IPMC]
    st[HS_IPMC + 2] = st[HS_IPMC]
    st[HS_IPMC + 3] = st[HS_IPMC]
    st[HS_CHROMA_SYN + 1] = st[HS_CHROMA_SYN]
    st[HS_CHROMA_SYN + 2] = st[HS_CHROMA_SYN]
    st[HS_CHROMA_SYN + 3] = st[HS_CHROMA_SYN]
  0

# ---------------------------------------------------------------- transform tree (7.3.8.8)

# cbfcb / cbfcr: parent's flags (bit0: first, bit1: second (4:2:2) chroma block)
-> hv_tt(d, cab, st, tb, mp, px, cf, x0, y0, xb, yb, log2, depth, blk, pcb, pcr) (u8[] i64[] i64[] i32[] i32[] u16[] i32[] i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  split = 0 ## i64
  intra = (st[HS_CU_PRED]) ## i64
  if log2 <= st[HS_MAXTB] && log2 > st[HS_MINTB] && depth < st[HS_MAX_TDEPTH] && !(st[HS_INTRA_SPLIT] != 0 && depth == 0)
    split = hv_bin(cab, d, tb, HC_SPLIT_TR + 5 - log2)
  else
    inter_split = 0 ## i64
    if st[HS_THD_INTER] == 0 && intra == 0 && st[HS_CU_PART] != 0 && depth == 0
      inter_split = 1
    if log2 > st[HS_MAXTB] || (st[HS_INTRA_SPLIT] != 0 && depth == 0) || inter_split != 0
      split = 1
  ct = (st[HS_CT]) ## i64
  cbfcb = 0 ## i64
  cbfcr = 0 ## i64
  if (log2 > 2 && ct != 0) || ct == 3
    if depth == 0 || pcb != 0
      cbfcb = hv_bin(cab, d, tb, HC_CBF_CHROMA + depth)
      if ct == 2 && (split == 0 || log2 == 3)
        cbfcb = cbfcb | (hv_bin(cab, d, tb, HC_CBF_CHROMA + depth) << 1)
    if depth == 0 || pcr != 0
      cbfcr = hv_bin(cab, d, tb, HC_CBF_CHROMA + depth)
      if ct == 2 && (split == 0 || log2 == 3)
        cbfcr = cbfcr | (hv_bin(cab, d, tb, HC_CBF_CHROMA + depth) << 1)
  elsif ct != 0 && log2 == 2
    # 4x4 luma in 4:2:0 / 4:2:2: chroma coded at the parent (blkIdx 3) with its flags
    cbfcb = pcb
    cbfcr = pcr
  if split != 0
    h = (1 << (log2 - 1)) ## i64
    hv_tt(d, cab, st, tb, mp, px, cf, x0, y0, x0, y0, log2 - 1, depth + 1, 0, cbfcb, cbfcr)
    hv_tt(d, cab, st, tb, mp, px, cf, x0 + h, y0, x0, y0, log2 - 1, depth + 1, 1, cbfcb, cbfcr)
    hv_tt(d, cab, st, tb, mp, px, cf, x0, y0 + h, x0, y0, log2 - 1, depth + 1, 2, cbfcb, cbfcr)
    hv_tt(d, cab, st, tb, mp, px, cf, x0 + h, y0 + h, x0, y0, log2 - 1, depth + 1, 3, cbfcb, cbfcr)
    return 0
  cbfl = 1 ## i64
  if intra != 0 || depth != 0 || cbfcb != 0 || cbfcr != 0
    cbfl = hv_bin(cab, d, tb, HC_CBF_LUMA + (depth == 0 ? 1 : 0))
  hv_tu(d, cab, st, tb, mp, px, cf, x0, y0, xb, yb, log2, depth, blk, cbfl, cbfcb, cbfcr)

# ---------------------------------------------------------------- transform unit (7.3.8.10)

-> hv_tu(d, cab, st, tb, mp, px, cf, x0, y0, xb, yb, log2, depth, blk, cbfl, cbfcb, cbfcr) (u8[] i64[] i64[] i32[] i32[] u16[] i32[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  ct = (st[HS_CT]) ## i64
  intra = (st[HS_CU_PRED]) ## i64
  w4 = (st[HS_W4]) ## i64
  s = (1 << log2) ## i64
  # deblocking: transform edges on the 8x8 grid
  eo = (st[HS_M_EDGE]) ## i64
  if (x0 & 7) == 0
    y = 0 ## i64
    while y < s && y0 + y < st[HS_H]
      ii = (eo + ((y0 + y) >> 2) * w4 + (x0 >> 2)) ## i64
      mp[ii] = mp[ii] | 1
      y += 4
  if (y0 & 7) == 0
    x = 0 ## i64
    while x < s && x0 + x < st[HS_W]
      ii = eo + (y0 >> 2) * w4 + ((x0 + x) >> 2)
      mp[ii] = mp[ii] | 4
      x += 4
  chroma_here = 0 ## i64
  if ct != 0 && (log2 > 2 || ct == 3)
    chroma_here = 1
  elsif ct != 0 && blk == 3
    chroma_here = 2
  cbfc = 0 ## i64
  if ct != 0 && (chroma_here != 0 || log2 == 2)
    cbfc = cbfcb | cbfcr
  # which PB (NxN) this TU belongs to, for intra modes
  pbi = 0 ## i64
  if st[HS_INTRA_SPLIT] != 0
    pbi = hv_pb_index(st, x0, y0, log2, depth)
  if cbfl != 0 || cbfc != 0
    if st[HS_CUQPD] != 0 && st[HS_QPD_CODED] == 0
      v = 0 ## i64
      if hv_bin(cab, d, tb, HC_QPD) != 0
        v = 1
        while v < 5 && hv_bin(cab, d, tb, HC_QPD + 1) != 0
          v += 1
        if v == 5
          k = 0 ## i64
          while hv_bypass(cab, d) != 0
            k += 1
          v += ((1 << k) - 1) + hv_bypass_n(cab, d, k)
      if v != 0 && hv_bypass(cab, d) != 0
        v = 0 - v
      st[HS_QPD_CODED] = 1
      st[HS_QPD_VAL] = v
      hv_set_qpy(st)
    if st[HS_CQPO_EN] != 0 && cbfc != 0 && st[HS_CU_TQB] == 0 && st[HS_CQPO_CODED] == 0
      f = (hv_bin(cab, d, tb, HC_CQPO_F)) ## i64
      if f != 0
        idx = 0 ## i64
        n = (st[HS_CQPO_LEN]) ## i64
        if n > 1
          while idx < n - 1 && hv_bin(cab, d, tb, HC_CQPO_IDX) != 0
            idx += 1
        st[HS_CUQPO_CB] = st[HS_CQPO_CB + idx]
        st[HS_CUQPO_CR] = st[HS_CQPO_CR + idx]
      else
        st[HS_CUQPO_CB] = 0
        st[HS_CUQPO_CR] = 0
      st[HS_CQPO_CODED] = 1
  # luma
  if intra != 0
    hv_intra_pred(st, mp, tb, px, cf, x0, y0, log2, 0, st[HS_IPM + pbi])
  if cbfl != 0
    hv_or_map(mp, st[HS_M_FLAGS], w4, x0, y0, s, s, HM_NZ)
    hv_residual(d, cab, st, tb, mp, px, cf, x0, y0, log2, 0, st[HS_IPM + pbi])
  if chroma_here == 0
    return 0
  # chroma
  xc = (x0) ## i64
  yc = (y0) ## i64
  l2c = (log2 - 1) ## i64
  if ct == 3
    l2c = log2
  if chroma_here == 2
    xc = xb
    yc = yb
    l2c = 2
  cm = (st[HS_IPMC + pbi]) ## i64
  if chroma_here == 2
    cm = st[HS_IPMC]
  # chroma sample position of this block
  cxs = (xc >> st[HS_SSX]) ## i64
  cys = (yc >> st[HS_SSY]) ## i64
  sc = (1 << l2c) ## i64
  nt = 1 ## i64
  nt = 2 if ct == 2
  c = 1 ## i64
  while c <= 2
    cbf = (c == 1 ? cbfcb : cbfcr) ## i64
    st[HS_RES_SCALE] = 0
    if st[HS_CROSS] != 0 && cbfl != 0 && (intra == 0 || st[HS_CHROMA_SYN + pbi] == 4)
      # cross_component_prediction (7.3.8.12)
      la = 0 ## i64
      while la < 4 && hv_bin(cab, d, tb, HC_RES_SCALE + 4 * (c - 1) + la) != 0
        la += 1
      if la != 0
        rs = (1 << (la - 1)) ## i64
        rs = 0 - rs if hv_bin(cab, d, tb, HC_RES_SIGN + c - 1) != 0
        st[HS_RES_SCALE] = rs
    t = 0 ## i64
    while t < nt
      if intra != 0
        hv_intra_pred(st, mp, tb, px, cf, cxs, cys + t * sc, l2c, c, cm)
      if ((cbf >> t) & 1) != 0
        hv_residual(d, cab, st, tb, mp, px, cf, cxs, cys + t * sc, l2c, c, cm)
      elsif st[HS_RES_SCALE] != 0
        hv_ccp_only(st, px, cf, cxs, cys, l2c, c)
      t += 1
    c += 1
  st[HS_RES_SCALE] = 0
  0

-> hv_pb_index(st, x0, y0, log2, depth) (i64[] i64 i64 i64 i64) i64
  # NxN: the CU has size 2^(log2 + depth); PB size is half of it
  cu = (log2 + depth) ## i64
  half = (1 << (cu - 1)) ## i64
  mask = ((1 << cu) - 1) ## i64
  i = 0 ## i64
  i += 1 if (x0 & mask) >= half
  i += 2 if (y0 & mask) >= half
  i
