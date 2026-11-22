# core/codec/image/jxl_vardct — JPEG XL VarDCT: LF/HF global data, dequantisation
# matrices, coefficient orders, LF groups (DC, chroma-from-luma, block
# strategies, quant field), pass groups (HF coefficients) and the inverse
# transforms for all 27 block strategies (DCT 2x2 … 256x256, Hornuss, AFV).
# Coefficient storage and transposition conventions follow J40.

use jxl_ans
use jxl_modular

JXV_LIB_PARAMS = [~3150.0, ~560.0, ~512.0, ~0.0, ~0.0, ~-2.0, ~-0.4, ~-0.3, ~-1.0, ~-0.4, ~-0.3, ~0.0, ~-0.4, ~-0.3, ~-1.0, ~-2.0, ~-0.3, ~-2.0, ~280.0, ~60.0, ~18.0, ~3160.0, ~864.0, ~200.0, ~3160.0, ~864.0, ~200.0, ~3840.0, ~960.0, ~640.0, ~2560.0, ~640.0, ~320.0, ~1280.0, ~320.0, ~128.0, ~640.0, ~180.0, ~64.0, ~480.0, ~140.0, ~32.0, ~300.0, ~120.0, ~16.0, ~1.0, ~1.0, ~1.0, ~1.0, ~1.0, ~1.0, ~2200.0, ~392.0, ~112.0, ~0.0, ~0.0, ~-0.25, ~0.0, ~0.0, ~-0.25, ~0.0, ~0.0, ~-0.5, ~8996.8725711814115328, ~3191.48366296844234752, ~1157.50408145487200256, ~-1.3000777393353804, ~-0.67424582104194355, ~-2.0531423165804414, ~-0.49424529824571225, ~-0.80745813428471001, ~-1.4, ~-0.439093774457103443, ~-0.44925837484843441, ~-0.50687130033378396, ~-0.6350101832695744, ~-0.35865440981033403, ~-0.42708730624733904, ~-0.90177264050827612, ~-0.31322389111877305, ~-1.4856834539296244, ~-1.6162099239887414, ~-0.37615025315725483, ~-4.9209142884401604, ~15718.40830982518931456, ~7305.7636810695983104, ~3803.53173721215041536, ~-1.025, ~-0.8041958212306401, ~-3.060733579805728, ~-0.98, ~-0.7633036457487539, ~-2.0413270132490346, ~-0.9012, ~-0.55660379990111464, ~-2.0235650159727417, ~-0.4, ~-0.49785304658857626, ~-0.5495389509954993, ~-0.48819395464, ~-0.43699592683512467, ~-0.4, ~-0.421064, ~-0.40180866526242109, ~-0.4, ~-0.27, ~-0.27321683125358037, ~-0.3, ~7240.7734393502, ~1448.15468787004, ~506.854140754517, ~-0.7, ~-0.5, ~-1.4, ~-0.7, ~-0.5, ~-0.2, ~-0.2, ~-0.5, ~-0.5, ~-0.2, ~-0.2, ~-0.5, ~-0.2, ~-0.2, ~-1.5, ~-0.5, ~-0.2, ~-3.6, ~16283.2494710648897, ~5089.15750884921511936, ~3397.77603275308720128, ~-1.7812845336559429, ~-0.320049391452786891, ~-0.321327362693153371, ~-1.6309059012653515, ~-0.35362849922161446, ~-0.34507619223117997, ~-1.0382179034313539, ~-0.30340000000000003, ~-0.70340000000000003, ~-0.85, ~-0.61, ~-0.9, ~-0.7, ~-0.5, ~-1.0, ~-0.9, ~-0.5, ~-1.0, ~-1.2360638576849587, ~-0.6, ~-1.1754605576265209, ~13844.97076442300573, ~4798.964084220744293, ~1807.236946760964614, ~-0.97113799999999995, ~-0.61125308982767057, ~-1.2, ~-0.658, ~-0.83770786552491361, ~-1.2, ~-0.42026, ~-0.79014862079498627, ~-0.7, ~-0.22712, ~-0.2692727459704829, ~-0.7, ~-0.2206, ~-0.38272769465388551, ~-0.7, ~-0.226, ~-0.22924222653091453, ~-0.4, ~-0.6, ~-0.20719098826199578, ~-0.5, ~1.0, ~1.0, ~1.0, ~2198.050556016380522, ~764.3655248643528689, ~527.107573587542228, ~-0.96269623020744692, ~-0.92630200888366945, ~-1.4594385811273854, ~-0.76194253026666783, ~-0.9675229603596517, ~-1.450082094097871593, ~-0.6551140670773547, ~-0.27845290869168118, ~-1.5843722511996204, ~3072.0, ~1024.0, ~384.0, ~3072.0, ~1024.0, ~384.0, ~256.0, ~50.0, ~12.0, ~256.0, ~50.0, ~12.0, ~256.0, ~50.0, ~12.0, ~414.0, ~58.0, ~22.0, ~0.0, ~0.0, ~-0.25, ~0.0, ~0.0, ~-0.25, ~0.0, ~0.0, ~-0.25, ~2198.050556016380522, ~764.3655248643528689, ~527.107573587542228, ~-0.96269623020744692, ~-0.92630200888366945, ~-1.4594385811273854, ~-0.76194253026666783, ~-0.9675229603596517, ~-1.450082094097871593, ~-0.6551140670773547, ~-0.27845290869168118, ~-1.5843722511996204, ~2200.0, ~392.0, ~112.0, ~0.0, ~0.0, ~-0.25, ~0.0, ~0.0, ~-0.25, ~0.0, ~0.0, ~-0.5, ~21266.16652984486, ~7750.191483900904, ~4043.0237800984773, ~-1.025, ~-0.3041958212306401, ~-1.2, ~-0.78, ~0.3633036457487539, ~-1.2, ~-0.65012, ~-0.35660379990111464, ~-0.8, ~-0.19041574084286472, ~-0.3443074455424403, ~-0.7, ~-0.20819395464, ~-0.33699592683512467, ~-0.7, ~-0.421064, ~-0.30180866526242109, ~-0.4, ~-0.32733845535848671, ~-0.27321683125358037, ~-0.5, ~15358.898049332398, ~5597.360516150653, ~2919.9616189600115, ~-1.025, ~-0.3041958212306401, ~-1.2, ~-0.78, ~0.3633036457487539, ~-1.2, ~-0.65012, ~-0.35660379990111464, ~-0.8, ~-0.19041574084286472, ~-0.3443074455424403, ~-0.7, ~-0.20819395464, ~-0.33699592683512467, ~-0.7, ~-0.421064, ~-0.30180866526242109, ~-0.4, ~-0.32733845535848671, ~-0.27321683125358037, ~-0.5, ~42532.33305968972, ~15500.382967801808, ~8086.047560196955, ~-1.025, ~-0.3041958212306401, ~-1.2, ~-0.78, ~0.3633036457487539, ~-1.2, ~-0.65012, ~-0.35660379990111464, ~-0.8, ~-0.19041574084286472, ~-0.3443074455424403, ~-0.7, ~-0.20819395464, ~-0.33699592683512467, ~-0.7, ~-0.421064, ~-0.30180866526242109, ~-0.4, ~-0.32733845535848671, ~-0.27321683125358037, ~-0.5, ~30717.796098664796, ~11194.721032301306, ~5839.923237920023, ~-1.025, ~-0.3041958212306401, ~-1.2, ~-0.78, ~0.3633036457487539, ~-1.2, ~-0.65012, ~-0.35660379990111464, ~-0.8, ~-0.19041574084286472, ~-0.3443074455424403, ~-0.7, ~-0.20819395464, ~-0.33699592683512467, ~-0.7, ~-0.421064, ~-0.30180866526242109, ~-0.4, ~-0.32733845535848671, ~-0.27321683125358037, ~-0.5, ~85064.66611937944, ~31000.765935603617, ~16172.09512039391, ~-1.025, ~-0.3041958212306401, ~-1.2, ~-0.78, ~0.3633036457487539, ~-1.2, ~-0.65012, ~-0.35660379990111464, ~-0.8, ~-0.19041574084286472, ~-0.3443074455424403, ~-0.7, ~-0.20819395464, ~-0.33699592683512467, ~-0.7, ~-0.421064, ~-0.30180866526242109, ~-0.4, ~-0.32733845535848671, ~-0.27321683125358037, ~-0.5, ~61435.59219732959, ~22389.442064602612, ~11679.846475840046, ~-1.025, ~-0.3041958212306401, ~-1.2, ~-0.78, ~0.3633036457487539, ~-1.2, ~-0.65012, ~-0.35660379990111464, ~-0.8, ~-0.19041574084286472, ~-0.3443074455424403, ~-0.7, ~-0.20819395464, ~-0.33699592683512467, ~-0.7, ~-0.421064, ~-0.30180866526242109, ~-0.4, ~-0.32733845535848671, ~-0.27321683125358037, ~-0.5]

JXV_AFV_BASIS = [~0.25000000, ~0.87690293, ~0.00000000, ~0.00000000, ~0.00000000, ~-0.41053776, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.25000000, ~0.22065181, ~0.00000000, ~0.00000000, ~-0.70710678, ~0.62354854, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.25000000, ~-0.10140050, ~0.40670076, ~-0.21255748, ~0.00000000, ~-0.06435072, ~-0.45175566, ~-0.30468475, ~0.30179295, ~0.40824829, ~0.17478670, ~-0.21105601, ~-0.14266085, ~-0.13813540, ~-0.17437603, ~0.11354987, ~0.25000000, ~-0.10140050, ~0.44444817, ~0.30854971, ~0.00000000, ~-0.06435072, ~0.15854504, ~0.51126161, ~0.25792363, ~0.00000000, ~0.08126112, ~0.18567181, ~-0.34164468, ~0.33022826, ~0.07027907, ~-0.07417505, ~0.25000000, ~0.22065181, ~0.00000000, ~0.00000000, ~0.70710678, ~0.62354854, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.00000000, ~0.25000000, ~-0.10140050, ~0.00000000, ~0.47067023, ~0.00000000, ~-0.06435072, ~-0.04038515, ~0.00000000, ~0.16272340, ~0.00000000, ~0.00000000, ~0.00000000, ~0.73674975, ~0.08755115, ~-0.29210266, ~0.19402893, ~0.25000000, ~-0.10140050, ~0.19574399, ~-0.16212052, ~0.00000000, ~-0.06435072, ~0.00741823, ~-0.29048013, ~0.09520023, ~0.00000000, ~-0.36753980, ~0.49215859, ~0.24627108, ~-0.07946707, ~0.36238173, ~-0.43519050, ~0.25000000, ~-0.10140050, ~0.29291001, ~0.00000000, ~0.00000000, ~-0.06435072, ~0.39351034, ~-0.06578702, ~0.00000000, ~-0.40824829, ~-0.30788221, ~-0.38525014, ~-0.08574019, ~-0.46133749, ~0.00000000, ~0.21918685, ~0.25000000, ~-0.10140050, ~-0.40670076, ~-0.21255748, ~0.00000000, ~-0.06435072, ~-0.45175566, ~0.30468475, ~0.30179295, ~-0.40824829, ~-0.17478670, ~0.21105601, ~-0.14266085, ~-0.13813540, ~-0.17437603, ~0.11354987, ~0.25000000, ~-0.10140050, ~-0.19574399, ~-0.16212052, ~0.00000000, ~-0.06435072, ~0.00741823, ~0.29048013, ~0.09520023, ~0.00000000, ~0.36753980, ~-0.49215859, ~0.24627108, ~-0.07946707, ~0.36238173, ~-0.43519050, ~0.25000000, ~-0.10140050, ~0.00000000, ~-0.47067023, ~0.00000000, ~-0.06435072, ~0.11074166, ~0.00000000, ~-0.16272340, ~0.00000000, ~0.00000000, ~0.00000000, ~0.14883399, ~0.49724647, ~0.29210266, ~0.55504438, ~0.25000000, ~-0.10140050, ~0.11379074, ~-0.14642919, ~0.00000000, ~-0.06435072, ~0.08298163, ~-0.23889774, ~-0.35312385, ~-0.40824829, ~0.48266891, ~0.17419413, ~-0.04768680, ~0.12538059, ~-0.43266080, ~-0.25468277, ~0.25000000, ~-0.10140050, ~-0.44444817, ~0.30854971, ~0.00000000, ~-0.06435072, ~0.15854504, ~-0.51126161, ~0.25792363, ~0.00000000, ~-0.08126112, ~-0.18567181, ~-0.34164468, ~0.33022826, ~0.07027907, ~-0.07417505, ~0.25000000, ~-0.10140050, ~-0.29291001, ~0.00000000, ~0.00000000, ~-0.06435072, ~0.39351034, ~0.06578702, ~0.00000000, ~0.40824829, ~0.30788221, ~0.38525014, ~-0.08574019, ~-0.46133749, ~0.00000000, ~0.21918685, ~0.25000000, ~-0.10140050, ~-0.11379074, ~-0.14642919, ~0.00000000, ~-0.06435072, ~0.08298163, ~0.23889774, ~-0.35312385, ~0.40824829, ~-0.48266891, ~-0.17419413, ~-0.04768680, ~0.12538059, ~-0.43266080, ~-0.25468277, ~0.25000000, ~-0.10140050, ~0.00000000, ~0.42511496, ~0.00000000, ~-0.06435072, ~-0.45175566, ~0.00000000, ~-0.60358590, ~0.00000000, ~0.00000000, ~0.00000000, ~-0.14266085, ~-0.13813540, ~0.34875205, ~0.11354987]

# DctSelect: [log_rows, log_columns, param_idx, order_idx] for the 27 strategies.
JXV_DCT_SELECT = [[3, 3, 0, 0], [3, 3, 1, 1], [3, 3, 2, 1], [3, 3, 3, 1], [4, 4, 4, 2], [5, 5, 5, 3], [4, 3, 6, 4], [3, 4, 6, 4], [5, 3, 7, 5], [3, 5, 7, 5], [5, 4, 8, 6], [4, 5, 8, 6], [3, 3, 9, 1], [3, 3, 9, 1], [3, 3, 10, 1], [3, 3, 10, 1], [3, 3, 10, 1], [3, 3, 10, 1], [6, 6, 11, 7], [6, 5, 12, 8], [5, 6, 12, 8], [7, 7, 13, 9], [7, 6, 14, 10], [6, 7, 14, 10], [8, 8, 15, 11], [8, 7, 16, 12], [7, 8, 16, 12]]

# DCT params: [log_rows, log_columns, def_offset, def_mode, def_n, def_m]
# modes: 1 Hornuss, 2 DCT2, 3 DCT4, 4 DCT4x8, 5 AFV, 6 DCT, 7 RAW
JXV_DCT_PARAMS = [[3, 3, 0, 6, 6, 0], [3, 3, 6, 1, 0, 0], [3, 3, 9, 2, 0, 0], [3, 3, 15, 3, 4, 0], [4, 4, 21, 6, 7, 0], [5, 5, 28, 6, 8, 0], [3, 4, 36, 6, 7, 0], [3, 5, 43, 6, 8, 0], [4, 5, 51, 6, 8, 0], [3, 3, 59, 4, 4, 0], [3, 3, 64, 5, 4, 4], [6, 6, 81, 6, 8, 0], [5, 6, 89, 6, 8, 0], [7, 7, 97, 6, 8, 0], [6, 7, 105, 6, 8, 0], [8, 8, 113, 6, 8, 0], [7, 8, 121, 6, 8, 0]]

JXV_LOG_ORDER = [[3, 3], [3, 3], [4, 4], [5, 5], [3, 4], [3, 5], [4, 5], [6, 6], [5, 6], [7, 7], [6, 7], [8, 8], [7, 8]]

JXV_FREQ_CTX = [0, 0, 2, 4, 6, 8, 10, 12, 14, 16, 18, 20, 22, 24, 26, 28, 30, 30, 32, 32, 34, 34, 36, 36, 38, 38, 40, 40, 42, 42, 44, 44, 46, 46, 46, 46, 48, 48, 48, 48, 50, 50, 50, 50, 52, 52, 52, 52, 54, 54, 54, 54, 56, 56, 56, 56, 58, 58, 58, 58, 60, 60, 60, 60]
JXV_NNZ_CTX = [0, 0, 62, 124, 124, 186, 186, 186, 186, 246, 246, 246, 246, 304, 304, 304, 304, 304, 304, 304, 304, 360, 360, 360, 360, 360, 360, 360, 360, 360, 360, 360, 360, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412, 412]

JXV_DEFAULT_BLKCTX = [0, 1, 2, 2, 3, 3, 4, 5, 6, 6, 6, 6, 6, 7, 8, 9, 9, 10, 11, 12, 13, 14, 14, 14, 14, 14, 7, 8, 9, 9, 10, 11, 12, 13, 14, 14, 14, 14, 14]

JXV_STATE = [nil, nil, nil, nil, nil, nil]

-> jxv_i64(a)
  t = i64[a.size]
  i = 0
  while i < a.size
    t[i] = a[i]
    i += 1
  t

-> jxv_f64(a)
  t = f64[a.size]
  i = 0
  while i < a.size
    t[i] = a[i]
    i += 1
  t

# Tables: [0] half secants f64[256], [1] LF→LLF scales f64[64], [2] AFV basis,
# [3] freq ctx i64[64], [4] nnz ctx i64[64]
-> jxv_tables
  if JXV_STATE[0] == nil
    hs = f64[256]
    n = 1
    while n < 8
      k = 0
      while k < (1 << n)
        hs[(1 << n) + k] = ~1.0 / (~2.0 * Math.cos((k + ~0.5) / (1 << (n + 1)) * ~3.141592653589793))
        k += 1
      n += 1
    JXV_STATE[0] = hs
    sc = f64[64]
    nn = 1
    while nn < 64
      k = 0
      while k < nn
        a = k * ~3.141592653589793
        v = Math.cos(a / (16 * nn)) * Math.cos(a / (8 * nn)) * Math.cos(a / (4 * nn)) * nn
        sc[nn + k] = ~1.0 / v
        k += 1
      nn = nn * 2
    JXV_STATE[1] = sc
    JXV_STATE[2] = jxv_f64(JXV_AFV_BASIS)
    JXV_STATE[3] = jxv_i64(JXV_FREQ_CTX)
    JXV_STATE[4] = jxv_i64(JXV_NNZ_CTX)
  JXV_STATE

# ---------------------------------------------------------------- DCT

# 1-D inverse DCT of length 2^t: out[oo..] from in[io..] (in is clobbered).
-> jxv_idct(o, oo, s, io, t, hs) (f64[] i64 f64[] i64 i64 f64[]) i64
  if t == 0
    o[oo] = s[io]
    return 0
  if t == 1
    x = s[io]
    y = s[io + 1]
    o[oo] = x + y
    o[oo + 1] = x - y
    return 0
  n = 1 << t
  h = n >> 1
  i = 0 ## i64
  while i < h
    o[oo + i] = s[io + 2 * i]
    i += 1
  o[oo + h] = ~1.4142135623730951 * s[io + 1]
  i = 1
  while i < h
    o[oo + h + i] = s[io + 2 * i - 1] + s[io + 2 * i + 1]
    i += 1
  jxv_idct(s, io, o, oo, t - 1, hs)
  jxv_idct(s, io + h, o, oo + h, t - 1, hs)
  i = 0
  while i < h
    m = hs[h + i]
    x = s[io + i]
    y = s[io + h + i] * m
    o[oo + i] = x + y
    o[oo + n - 1 - i] = x - y
    i += 1
  0

# Column-wise IDCT on a view (2^logw columns, 2^logh rows): out = IDCT(in)
# along the vertical axis. tmp/tmp2 are scratch vectors (>= 256).
-> jxv_idct_cols(o, s, logw, logh, tmp, tmp2, hs) (f64[] f64[] i64 i64 f64[] f64[] f64[]) i64
  w = 1 << logw
  h = 1 << logh
  if logh == 0
    i = 0 ## i64
    while i < w
      o[i] = s[i]
      i += 1
    return 0
  c = 0 ## i64
  while c < w
    r = 0 ## i64
    while r < h
      tmp[r] = s[r * w + c]
      r += 1
    jxv_idct(tmp2, 0, tmp, 0, logh, hs)
    r = 0
    while r < h
      o[r * w + c] = tmp2[r]
      r += 1
    c += 1
  0

# dst = transpose(src) where src has 2^logh rows of 2^logw columns.
-> jxv_transpose(d, s, logw, logh) (f64[] f64[] i64 i64) i64
  w = 1 << logw
  h = 1 << logh
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      d[x * h + y] = s[y * w + x]
      x += 1
    y += 1
  0

-> jxv_copy(d, s, n) (f64[] f64[] i64) i64
  i = 0 ## i64
  while i < n
    d[i] = s[i]
    i += 1
  0

# J40's inverse_dct2d: buf (coefficients, possibly transposed) → samples
# (2^lr rows x 2^lc columns, row-major) in buf.
-> jxv_idct2d(buf, scr, lr, lc, tmp, tmp2, hs) (f64[] f64[] i64 i64 f64[] f64[] f64[]) i64
  n = 1 << (lr + lc)
  if lc > lr
    jxv_transpose(scr, buf, lc, lr)
  else
    jxv_copy(scr, buf, n)
  # scr: logw = lr, logh = lc
  jxv_idct_cols(buf, scr, lr, lc, tmp, tmp2, hs)
  jxv_transpose(scr, buf, lr, lc)
  # scr: logw = lc, logh = lr
  jxv_idct_cols(buf, scr, lc, lr, tmp, tmp2, hs)
  0

# Forward DCT (unscaled: X_k = c_k * sum x cos, c_0 = 1, c_k = sqrt 2) along
# the vertical axis of a view.
-> jxv_fdct_cols(o, s, logw, logh) (f64[] f64[] i64 i64) i64
  w = 1 << logw
  h = 1 << logh
  c = 0 ## i64
  while c < w
    k = 0 ## i64
    while k < h
      sum = ~0.0
      r = 0 ## i64
      while r < h
        sum += s[r * w + c] * Math.cos(~3.141592653589793 * k * (2 * r + 1) / (2 * h))
        r += 1
      if k > 0
        sum = sum * ~1.4142135623730951
      o[k * w + c] = sum
      k += 1
    c += 1
  0

# LLF coefficients from the DC values of a varblock (J40's
# forward_dct2d_scaled_for_llf): buf holds 2^lr rows x 2^lc columns of DC.
-> jxv_llf_from_dc(buf, scr, lr, lc, sc) (f64[] f64[] i64 i64 f64[]) i64
  n = 1 << (lr + lc)
  # bufv: logw = lc, logh = lr
  jxv_fdct_cols(scr, buf, lc, lr)
  jxv_transpose(buf, scr, lc, lr)
  # buf: logw = lr, logh = lc
  jxv_fdct_cols(scr, buf, lr, lc)
  # scr: logw = lr, logh = lc
  w = 1 << lr
  h = 1 << lc
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      scr[y * w + x] = scr[y * w + x] * sc[w + x] * sc[h + y]
      x += 1
    y += 1
  if lc > lr
    jxv_transpose(buf, scr, lr, lc)
  else
    jxv_copy(buf, scr, n)
  0

# DCT2x2 helper (J40 aux_inverse_dct11).
-> jxv_aux11(o, s, x, y, s2) (f64[] f64[] i64 i64 i64) i64
  p = y * 8 + x
  q = (y * 2) * 8 + (x * 2)
  c00 = s[p]
  c01 = s[p + s2]
  c10 = s[p + s2 * 8]
  c11 = s[p + s2 * 9]
  o[q] = c00 + c01 + c10 + c11
  o[q + 1] = c00 + c01 - c10 - c11
  o[q + 8] = c00 - c01 + c10 - c11
  o[q + 9] = c00 - c01 - c10 + c11
  0

-> jxv_idct11(buf, scr) (f64[] f64[]) i64
  jxv_aux11(buf, buf, 0, 0, 1)
  jxv_copy(scr, buf, 64)
  y = 0 ## i64
  while y < 2
    x = 0 ## i64
    while x < 2
      jxv_aux11(scr, buf, x, y, 2)
      x += 1
    y += 1
  y = 0
  while y < 4
    x = 0 ## i64
    while x < 4
      jxv_aux11(buf, scr, x, y, 4)
      x += 1
    y += 1
  0

# 1-D IDCT of length 2^t applied to `rep` interleaved columns (stride rep).
-> jxv_idct_rep(o, s, t, rep, tmp, tmp2, hs) (f64[] f64[] i64 i64 f64[] f64[] f64[]) i64
  n = 1 << t
  c = 0 ## i64
  while c < rep
    r = 0 ## i64
    while r < n
      tmp[r] = s[r * rep + c]
      r += 1
    jxv_idct(tmp2, 0, tmp, 0, t, hs)
    r = 0
    while r < n
      o[r * rep + c] = tmp2[r]
      r += 1
    c += 1
  0

-> jxv_idct22(buf, scr, tmp, tmp2, hs) (f64[] f64[] f64[] f64[] f64[]) i64
  jxv_aux11(buf, buf, 0, 0, 1)
  jxv_idct_rep(scr, buf, 2, 16, tmp, tmp2, hs)
  y = 0 ## i64
  while y < 8
    x = 0 ## i64
    while x < 8
      buf[x * 8 + y] = scr[y * 8 + x]
      x += 1
    y += 1
  jxv_idct_rep(scr, buf, 2, 16, tmp, tmp2, hs)
  y = 0
  while y < 4
    x = 0 ## i64
    while x < 4
      buf[y * 8 + x] = scr[(y * 2) * 8 + (x * 2)]
      buf[y * 8 + (x + 4)] = scr[(y * 2 + 1) * 8 + (x * 2)]
      buf[(y + 4) * 8 + x] = scr[(y * 2) * 8 + (x * 2 + 1)]
      buf[(y + 4) * 8 + (x + 4)] = scr[(y * 2 + 1) * 8 + (x * 2 + 1)]
      x += 1
    y += 1
  0

-> jxv_hornuss(buf, scr) (f64[] f64[]) i64
  jxv_copy(scr, buf, 64)
  jxv_aux11(scr, buf, 0, 0, 1)
  y = 0 ## i64
  while y < 2
    x = 0 ## i64
    while x < 2
      p00 = y * 8 + x
      p11 = (y + 2) * 8 + (x + 2)
      rs = ~0.0
      iy = 0 ## i64
      while iy < 4
        ix = 0 ## i64
        while ix < 4
          rs += scr[(y + iy * 2) * 8 + (x + ix * 2)]
          ix += 1
        iy += 1
      s11 = scr[p00] - (rs - scr[p00]) * ~0.0625
      scr[p00] = scr[p11]
      scr[p11] = ~0.0
      iy = 0
      while iy < 4
        ix = 0
        while ix < 4
          buf[(4 * y + iy) * 8 + (4 * x + ix)] = scr[(y + iy * 2) * 8 + (x + ix * 2)] + s11
          ix += 1
        iy += 1
      x += 1
    y += 1
  0

# DCT8x4 (J40 inverse_dct32): two 4x8 halves from even/odd rows.
-> jxv_idct32(buf, scr, tmp, tmp2, hs) (f64[] f64[] f64[] f64[] f64[]) i64
  t = buf[0] + buf[8]
  buf[8] = buf[0] - buf[8]
  buf[0] = t
  # bufv reshaped to logw 4, logh 2; IDCT along height (4) for 16 columns
  jxv_idct_cols(scr, buf, 4, 2, tmp, tmp2, hs)
  # scratch reshaped to 3,3; transpose into buf (logw 3, logh 3)
  jxv_transpose(buf, scr, 3, 3)
  jxv_idct_cols(scr, buf, 3, 3, tmp, tmp2, hs)
  # odd/even columns to halves
  y = 0 ## i64
  while y < 8
    x = 0 ## i64
    while x < 8
      ox = ((x & 1) << 2) | (x >> 1)
      buf[y * 8 + ox] = scr[y * 8 + x]
      x += 1
    y += 1
  0

# DCT4x8 (J40 inverse_dct23).
-> jxv_idct23(buf, scr, tmp, tmp2, hs) (f64[] f64[] f64[] f64[] f64[]) i64
  jxv_copy(scr, buf, 64)
  scr[0] = buf[0] + buf[8]
  scr[8] = buf[0] - buf[8]
  jxv_transpose(buf, scr, 3, 3)
  jxv_idct_cols(scr, buf, 3, 3, tmp, tmp2, hs)
  jxv_transpose(buf, scr, 3, 3)
  # reshape buf to logw 4, logh 2
  jxv_idct_cols(scr, buf, 4, 2, tmp, tmp2, hs)
  # scratch logw 3 logh 3: odd/even rows to halves
  y = 0 ## i64
  while y < 8
    oy = ((y & 1) << 2) | (y >> 1)
    x = 0 ## i64
    while x < 8
      buf[oy * 8 + x] = scr[y * 8 + x]
      x += 1
    y += 1
  0

-> jxv_afv(buf, scr, flipx, flipy, tmp, tmp2, hs, basis) (f64[] f64[] i64 i64 f64[] f64[] f64[] f64[]) i64
  y = 0 ## i64
  while y < 8
    x = 0 ## i64
    while x < 8
      scr[(x % 2) * 16 + (y / 2) * 4 + (x / 2)] = buf[y * 8 + x]
      x += 1
    y += 2
  y = 1
  while y < 8
    x = 0 ## i64
    while x < 8
      scr[32 + x * 4 + (y / 2)] = buf[y * 8 + x]
      x += 1
    y += 2
  scr[0] = (buf[0] + buf[1] + buf[8]) * ~4.0
  scr[16] = buf[0] - buf[1] + buf[8]
  scr[32] = buf[0] - buf[8]
  # AFV 4x4
  i = 0 ## i64
  while i < 16
    sum = ~0.0
    j = 0 ## i64
    while j < 16
      sum += scr[j] * basis[i * 16 + j]
      j += 1
    buf[i] = sum
    i += 1
  # DCT22: 4-point IDCT across 4 columns (rows of length 4, stride 4)
  jxv_sub_idct(buf, 16, scr, 16, 2, 4, tmp, tmp2, hs)
  jxv_sub_idct(buf, 32, scr, 32, 3, 4, tmp, tmp2, hs)
  y = 0
  while y < 4
    x = 0 ## i64
    while x < 4
      scr[y * 4 + x] = buf[y * 4 + x]
      scr[16 + x * 4 + y] = buf[16 + y * 4 + x]
      x += 1
    y += 1
  y = 0
  while y < 8
    x = 0 ## i64
    while x < 4
      scr[32 + x * 8 + y] = buf[32 + y * 4 + x]
      x += 1
    y += 1
  jxv_sub_idct(buf, 16, scr, 16, 2, 4, tmp, tmp2, hs)
  jxv_sub_idct(buf, 32, scr, 32, 2, 8, tmp, tmp2, hs)
  k = 16 ## i64
  while k < 64
    scr[k] = buf[k]
    k += 1
  y = 0
  while y < 4
    afy = y
    afy = 7 - y if flipy == 1
    afv22pos = afy * 8
    dct22pos = (flipy * 4 + y) * 8 + ((1 - flipx) * 4)
    dct23pos = ((1 - flipy) * 4 + y) * 8
    x = 0 ## i64
    while x < 4
      fx = x
      fx = 7 - x if flipx == 1
      buf[afv22pos + fx] = scr[y * 4 + x]
      buf[dct22pos + x] = scr[16 + y * 4 + x]
      x += 1
    x = 0
    while x < 8
      buf[dct23pos + x] = scr[32 + y * 8 + x]
      x += 1
    y += 1
  0

# J40 inverse_dct(out, in, t, rep) on sub-arrays at offsets.
-> jxv_sub_idct(o, oo, s, so, t, rep, tmp, tmp2, hs) (f64[] i64 f64[] i64 i64 i64 f64[] f64[] f64[]) i64
  n = 1 << t
  c = 0 ## i64
  while c < rep
    r = 0 ## i64
    while r < n
      tmp[r] = s[so + r * rep + c]
      r += 1
    jxv_idct(tmp2, 0, tmp, 0, t, hs)
    r = 0
    while r < n
      o[oo + r * rep + c] = tmp2[r]
      r += 1
    c += 1
  0

# ---------------------------------------------------------------- natural order

-> jxv_natural_order(lr, lc)
  key = lr * 16 + lc
  JXV_STATE[5] = {} if JXV_STATE[5] == nil
  cache = JXV_STATE[5]
  return cache[key] if cache[key] != nil
  size = 1 << (lr + lc)
  ls = lc - lr
  r8 = 1 << (lr - 3)
  c8 = 1 << (lc - 3)
  order = i32[size]
  o = 0
  y = 0
  while y < r8
    x = 0
    while x < c8
      order[o] = (y << lc) | x
      o += 1
      x += 1
    y += 1
  key1 = 1 << (lc - 3)
  while o < size
    x0 = key1 & ((1 << ls) - 1)
    y0 = key1 >> ls
    x1 = key1
    y1 = 0
    if x1 >= (1 << lc)
      ex = (x1 - ((1 << lc) - 1) + (1 << ls) - 1) >> ls
      x1 -= ex << ls
      y1 += ex
    if y0 >= (1 << lr)
      ex = y0 - ((1 << lr) - 1)
      x0 += ex << ls
      y0 -= ex
    if (key1 & 1) == 1
      x = x1
      y = y1
      while x >= x0
        if y >= r8 || x >= c8
          order[o] = (y << lc) | x
          o += 1
        x -= 1 << ls
        y += 1
    else
      x = x0
      y = y0
      while x <= x1
        if y >= r8 || x >= c8
          order[o] = (y << lc) | x
          o += 1
        x += 1 << ls
        y -= 1
    key1 += 1
  cache[key] = order
  order

# ---------------------------------------------------------------- dequant matrices

+ JxVd
  rw :global_scale, :quant_lf, :bctx, :nb_bctx, :lf_thr, :qf_thr, :base_x, :base_b
  rw :inv_cf, :x_lf, :b_lf, :bw, :bh, :dc, :dcw, :dch, :qdc, :acs, :qf, :sharp
  rw :ytox, :ytob, :tw, :th, :dq, :dq_enc, :hf_presets, :orders, :coef_cs
  rw :coeffs, :hs, :vs, :sigma, :cb

-> jxv_read_dq(src, br, d, rows, cols, sidx)
  mode = jb_u(src, br, 3)
  if mode == 7
    den = jb_f16(src, br)
    jxl_fail("dq denominator") if den == ~0.0
    chs = [JxCh.new(cols, rows), JxCh.new(cols, rows), JxCh.new(cols, rows)]
    gi = JxMImg.new(chs, 8)
    jxm_read_header(src, br, gi)
    jxm_alloc(gi)
    jxm_decode_channels(src, br, gi, sidx, 1 << 30, d.gtree)
    jxm_inverse(gi)
    w = f64[3 * rows * cols]
    c = 0
    while c < 3
      k = 0
      while k < rows * cols
        qv = gi.ch[c].d[k]
        jxl_fail("dq raw value") if qv == 0
        w[c * rows * cols + k] = ~1.0 / (den * qv)
        k += 1
      c += 1
    return [7, w]
  if mode == 0
    return [0, nil]
  hw = [[0, 0, 0, 0], [1, 3, 3, 0], [1, 6, 6, 0], [1, 2, 2, 1], [1, 1, 0, 1], [1, 9, 6, 2], [0, 0, 0, 1]][mode]
  jxl_fail("dq matrix size") if hw[0] == 1 && (rows != 8 || cols != 8)
  # params: list of [p0, p1, p2] rows
  params = []
  j = 0
  while j < hw[1]
    params.push([~0.0, ~0.0, ~0.0])
    j += 1
  c = 0
  while c < 3
    j = 0
    while j < hw[1]
      v = jb_f16(src, br)
      v = v * ~64.0 if j < hw[2]
      params[j][c] = v
      j += 1
    c += 1
  n = 0
  mm = 0
  i = 0
  while i < hw[3]
    cnt = jb_u(src, br, 4) + 1
    if i == 0
      n = cnt
    else
      mm = cnt
    base = params.size
    j = 0
    while j < cnt
      params.push([~0.0, ~0.0, ~0.0])
      j += 1
    c = 0
    while c < 3
      j = 0
      while j < cnt
        v = jb_f16(src, br)
        v = v * ~64.0 if j == 0
        params[base + j][c] = v
        j += 1
      c += 1
    i += 1
  [mode, params, n, mm]

-> jxv_interp(pos, bands, c, len)
  return bands[0][c] if len == 1
  sp = pos * (len - 1)
  si = sp.to_i
  si = len - 2 if si > len - 2
  fr = sp - si
  a = bands[si][c]
  b = bands[si + 1][c]
  a * Math.exp(Math.log(b / a) * fr)

-> jxv_bands(params, off, n)
  out = []
  i = 0
  while i < n
    out.push([~0.0, ~0.0, ~0.0])
    i += 1
  c = 0
  while c < 3
    out[0][c] = params[off][c]
    jxl_fail("dq band") if out[0][c] <= ~0.0
    i = 1
    while i < n
      v = params[off + i][c]
      if v > ~0.0
        out[i][c] = out[i - 1][c] * (~1.0 + v)
      else
        out[i][c] = out[i - 1][c] / (~1.0 - v)
      jxl_fail("dq band") if out[i][c] <= ~0.0
      i += 1
    c += 1
  out

# weights[c][y*cols+x] for a DCT matrix from bands
-> jxv_dct_weights(rows, cols, bands, len)
  out = [f64[rows * cols], f64[rows * cols], f64[rows * cols]]
  ir = ~1.0 / (rows - 1)
  ic = ~1.0 / (cols - 1)
  c = 0
  while c < 3
    y = 0
    while y < rows
      x = 0
      while x < cols
        dx = x * ic
        dy = y * ir
        dd = Math.sqrt(dx * dx + dy * dy)
        out[c][y * cols + x] = jxv_interp(dd / ~1.414214562373095, bands, c, len)
        x += 1
      y += 1
    c += 1
  out

JXV_AFV_FREQS = [~0.000000000, ~0.373436417, ~0.320380100, ~0.379332596, ~0.066671353, ~0.259756761, ~0.530035651, ~0.789731061, ~0.149436598, ~0.559318823, ~0.669198646, ~0.999999917]
JXV_AFV_MAP = [60, 32, 62, 33, 48, 34, 49, 35, 0, 1, 2, 3, 4, 5, 6, 7, 61, 36, 63, 37, 50, 38, 51, 39, 8, 9, 10, 11, 12, 13, 14, 15, 52, 40, 53, 41, 54, 42, 55, 43, 16, 17, 18, 19, 20, 21, 22, 23, 56, 44, 57, 45, 58, 46, 59, 47, 24, 25, 26, 27, 28, 29, 30, 31]
JXV_DCT2_MAP = [0, 0, 2, 2, 4, 4, 4, 4, 0, 1, 2, 2, 4, 4, 4, 4, 2, 2, 3, 3, 4, 4, 4, 4, 2, 2, 3, 3, 4, 4, 4, 4, 4, 4, 4, 4, 5, 5, 5, 5, 4, 4, 4, 4, 5, 5, 5, 5, 4, 4, 4, 4, 5, 5, 5, 5, 4, 4, 4, 4, 5, 5, 5, 5]

# Compute the weight matrix (f64[3 * size], channel-major) for DCT param idx.
-> jxv_load_dq(idx, enc)
  dp = JXV_DCT_PARAMS[idx]
  rows = 1 << dp[0]
  cols = 1 << dp[1]
  size = rows * cols
  return enc[1] if enc[0] == 7
  mode = enc[0]
  n = 0
  mm = 0
  params = nil
  if mode == 0
    mode = dp[3]
    n = dp[4]
    mm = dp[5]
    params = []
    k = 0
    lim = dp[2] + 64
    lim = 129 if lim > 129
    i = dp[2]
    while i < lim
      params.push([JXV_LIB_PARAMS[i * 3], JXV_LIB_PARAMS[i * 3 + 1], JXV_LIB_PARAMS[i * 3 + 2]])
      i += 1
  else
    params = enc[1]
    n = enc[2]
    mm = enc[3]
  out = f64[3 * size]
  if mode == 6
    bands = jxv_bands(params, 0, n)
    wt = jxv_dct_weights(rows, cols, bands, n)
    c = 0
    while c < 3
      k = 0
      while k < size
        out[c * size + k] = wt[c][k]
        k += 1
      c += 1
  elsif mode == 3
    bands = jxv_bands(params, 2, n)
    wt = jxv_dct_weights(4, 4, bands, n)
    c = 0
    while c < 3
      y = 0
      while y < 8
        x = 0
        while x < 8
          out[c * 64 + y * 8 + x] = wt[c][(y / 2) * 4 + (x / 2)]
          x += 1
        y += 1
      out[c * 64 + 1] = out[c * 64 + 1] / params[0][c]
      out[c * 64 + 8] = out[c * 64 + 8] / params[0][c]
      out[c * 64 + 9] = out[c * 64 + 9] / params[1][c]
      c += 1
  elsif mode == 2
    c = 0
    while c < 3
      k = 0
      while k < 64
        out[c * 64 + k] = params[JXV_DCT2_MAP[k]][c]
        k += 1
      out[c * 64] = ~-1.0
      c += 1
  elsif mode == 1
    c = 0
    while c < 3
      k = 0
      while k < 64
        out[c * 64 + k] = params[0][c]
        k += 1
      out[c * 64] = ~1.0
      out[c * 64 + 1] = params[1][c]
      out[c * 64 + 8] = params[1][c]
      out[c * 64 + 9] = params[2][c]
      c += 1
  elsif mode == 4
    bands = jxv_bands(params, 1, n)
    wt = jxv_dct_weights(4, 8, bands, n)
    c = 0
    while c < 3
      y = 0
      while y < 8
        x = 0
        while x < 8
          out[c * 64 + y * 8 + x] = wt[c][(y / 2) * 8 + x]
          x += 1
        y += 1
      out[c * 64 + 1] = out[c * 64 + 1] / params[0][c]
      c += 1
  elsif mode == 5
    b1 = jxv_bands(params, 9, n)
    w48 = jxv_dct_weights(4, 8, b1, n)
    b2 = jxv_bands(params, 9 + n, mm)
    w44 = jxv_dct_weights(4, 4, b2, mm)
    b3 = jxv_bands(params, 5, 4)
    c = 0
    while c < 3
      scr = f64[64]
      k = 0
      while k < 32
        scr[k] = w48[c][k]
        k += 1
      k = 0
      while k < 16
        scr[32 + k] = w44[c][k]
        k += 1
      scr[0] = params[0][c]
      scr[32] = params[1][c]
      k = 0
      while k < 12
        scr[48 + k] = jxv_interp(JXV_AFV_FREQS[k], b3, c, 4)
        k += 1
      scr[60] = ~1.0
      k = 0
      while k < 3
        scr[61 + k] = params[k + 2][c]
        k += 1
      k = 0
      while k < 64
        out[c * 64 + k] = scr[JXV_AFV_MAP[k]]
        k += 1
      c += 1
  else
    jxl_fail("dq mode")
  out

# ---------------------------------------------------------------- LfGlobal / HfGlobal

-> jxv_lf_global(d, br)
  src = d.src
  f = d.f
  vd = JxVd.new
  d.vd = vd
  vd.global_scale = jb_u32(src, br, 1, 11, 2049, 11, 4097, 12, 8193, 16)
  vd.quant_lf = jb_u32(src, br, 16, 0, 1, 5, 1, 8, 1, 16)
  vd.lf_thr = [[], [], []]
  vd.qf_thr = []
  if jb_u(src, br, 1) == 1
    vd.bctx = JXV_DEFAULT_BLKCTX
    vd.nb_bctx = 15
  else
    sz = 39
    c = 0
    while c < 3
      nt = jb_u(src, br, 4)
      k = 0
      while k < nt
        vd.lf_thr[c].push(jx_unpack_signed(jb_u32(src, br, 0, 4, 16, 8, 272, 16, 65808, 32)))
        k += 1
      sz = sz * (nt + 1)
      c += 1
    nq = jb_u(src, br, 4)
    k = 0
    while k < nq
      vd.qf_thr.push(jb_u32(src, br, 0, 2, 4, 3, 12, 5, 44, 8) + 1)
      k += 1
    sz = sz * (nq + 1)
    jxl_fail("block ctx size") if sz > 39 * 64
    cm = jx_cluster_map(src, br, sz, 16)
    vd.bctx = cm[0]
    vd.nb_bctx = cm[1]
  vd.inv_cf = ~1.0 / ~84.0
  vd.base_x = ~0.0
  vd.base_b = ~1.0
  vd.x_lf = 0
  vd.b_lf = 0
  if jb_u(src, br, 1) == 0
    vd.inv_cf = ~1.0 / jb_u32(src, br, 84, 0, 256, 0, 2, 8, 258, 16)
    vd.base_x = jb_f16(src, br)
    vd.base_b = jb_f16(src, br)
    vd.x_lf = jb_u(src, br, 8) - 128
    vd.b_lf = jb_u(src, br, 8) - 128
  # frame-level block arrays
  bw = (f.fw + 7) / 8
  bh = (f.fh + 7) / 8
  vd.bw = bw
  vd.bh = bh
  nb = bw * bh
  vd.hs = [jxl_ycc_hshift(f, 0), jxl_ycc_hshift(f, 1), jxl_ycc_hshift(f, 2)]
  vd.vs = [jxl_ycc_vshift(f, 0), jxl_ycc_vshift(f, 1), jxl_ycc_vshift(f, 2)]
  vd.dc = []
  vd.dcw = []
  vd.dch = []
  c = 0
  while c < 3
    w = (bw + (1 << vd.hs[c]) - 1) >> vd.hs[c]
    h = (bh + (1 << vd.vs[c]) - 1) >> vd.vs[c]
    vd.dc.push(f64[w * h])
    vd.dcw.push(w)
    vd.dch.push(h)
    c += 1
  vd.qdc = i32[nb]
  vd.acs = i32[nb]
  vd.qf = i32[nb]
  vd.sharp = i32[nb]
  jxv_fill_i32(vd.acs, nb, -1)
  vd.tw = (bw + 7) / 8
  vd.th = (bh + 7) / 8
  vd.ytox = i32[vd.tw * vd.th]
  vd.ytob = i32[vd.tw * vd.th]
  vd.coeffs = [i32[nb * 64], i32[nb * 64], i32[nb * 64]]
  vd.cb = 0
  if f.use_lf_frame?
    lf = d.lf_frames[f.lf_level]
    jxl_fail("missing LF frame") if lf == nil
    c = 0
    while c < 3
      p = lf[0][c]
      jxl_fail("LF frame size mismatch") if p[1] < vd.dcw[c] || p[2] < vd.dch[c]
      jxv_copy_rect(vd.dc[c], vd.dcw[c], vd.dch[c], p[0], p[1])
      c += 1
  0

-> jxv_copy_rect(d, w, h, s, sw) (f64[] i64 i64 f64[] i64) i64
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      d[y * w + x] = s[y * sw + x]
      x += 1
    y += 1
  0

-> jxv_fill_i32(a, n, v) (i32[] i64 i64) i64
  i = 0 ## i64
  while i < n
    a[i] = v
    i += 1
  0

# LF group: quantised DC (YXB order) → dequantised DC with CfL.
-> jxv_lf_group_dc(d, br, idx)
  src = d.src
  f = d.f
  vd = d.vd
  gdb = f.gdim  # LF group is gdim blocks wide (8*gdim pixels)
  gx = idx % f.ggw
  gy = idx / f.ggw
  bx0 = gx * gdb
  by0 = gy * gdb
  rw = vd.bw - bx0
  rw = gdb if rw > gdb
  rh = vd.bh - by0
  rh = gdb if rh > gdb
  extra = jb_u(src, br, 2)
  chs = []
  ci = 0
  while ci < 3
    # modular channel ci holds colour channel c: 0 → Y (c=1), 1 → X (c=0), 2 → B
    c = ci
    c = 1 - ci if ci < 2
    chs.push(JxCh.new(rw >> vd.hs[c], rh >> vd.vs[c]))
    ci += 1
  gi = JxMImg.new(chs, d.m.bpp)
  jxm_read_header(src, br, gi)
  jxm_alloc(gi)
  jxm_decode_channels(src, br, gi, 1 + idx, 1 << 30, d.gtree)
  jxm_inverse(gi)
  mul = ~1.0 / (1 << extra)
  facs = [~0.0, ~0.0, ~0.0]
  c = 0
  while c < 3
    facs[c] = d.lf_dq[c] * ~65536.0 / (vd.global_scale * vd.quant_lf) * mul
    c += 1
  kx = vd.base_x + vd.x_lf * vd.inv_cf
  kb = vd.base_b + vd.b_lf * vd.inv_cf
  is444 = vd.hs[0] == 0 && vd.hs[2] == 0 && vd.vs[0] == 0 && vd.vs[2] == 0 && vd.hs[1] == 0 && vd.vs[1] == 0
  if is444
    jxv_dequant_dc444(gi.ch[1].d, gi.ch[0].d, gi.ch[2].d, vd.dc[0], vd.dc[1], vd.dc[2], vd.bw, bx0, by0, rw, rh, facs[0], facs[1], facs[2], kx, kb)
  else
    c = 0
    while c < 3
      ci = c
      ci = 1 - c if c < 2
      ch = gi.ch[ci]
      jxv_dequant_dc1(ch.d, ch.w, ch.h, vd.dc[c], vd.dcw[c], bx0 >> vd.hs[c], by0 >> vd.vs[c], facs[c])
      c += 1
  # LF context indices (qdc)
  nt0 = vd.lf_thr[0].size
  nt1 = vd.lf_thr[1].size
  nt2 = vd.lf_thr[2].size
  if nt0 + nt1 + nt2 > 0
    yy = 0
    while yy < rh
      xx = 0
      while xx < rw
        qx = gi.ch[1].d[(yy >> vd.vs[0]) * gi.ch[1].w + (xx >> vd.hs[0])]
        qy = gi.ch[0].d[(yy >> vd.vs[1]) * gi.ch[0].w + (xx >> vd.hs[1])]
        qb = gi.ch[2].d[(yy >> vd.vs[2]) * gi.ch[2].w + (xx >> vd.hs[2])]
        bxv = 0
        vd.lf_thr[0].each ->(t)
          bxv += 1 if qx > t
        byv = 0
        vd.lf_thr[1].each ->(t)
          byv += 1 if qy > t
        bbv = 0
        vd.lf_thr[2].each ->(t)
          bbv += 1 if qb > t
        vd.qdc[(by0 + yy) * vd.bw + bx0 + xx] = (bxv * (nt2 + 1) + bbv) * (nt1 + 1) + byv
        xx += 1
      yy += 1
  0

-> jxv_dequant_dc444(qx, qy, qb, dx, dy, db, bw, bx0, by0, rw, rh, fx, fy, fb, kx, kb) (i32[] i32[] i32[] f64[] f64[] f64[] i64 i64 i64 i64 i64 f64 f64 f64 f64 f64) i64
  y = 0 ## i64
  while y < rh
    x = 0 ## i64
    while x < rw
      s = y * rw + x
      o = (by0 + y) * bw + bx0 + x
      iy = qy[s] ## i64
      ix = qx[s] ## i64
      ib = qb[s] ## i64
      vy = (iy ## f64) * fy
      dy[o] = vy
      dx[o] = (ix ## f64) * fx + vy * kx
      db[o] = (ib ## f64) * fb + vy * kb
      x += 1
    y += 1
  0

-> jxv_dequant_dc1(q, w, h, dst, dw, x0, y0, fac) (i32[] i64 i64 f64[] i64 i64 i64 f64) i64
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      qv = q[y * w + x] ## i64
      dst[(y0 + y) * dw + x0 + x] = (qv ## f64) * fac
      x += 1
    y += 1
  0

# LF group: AC metadata (CfL tiles, block strategies, quant field, sharpness).
-> jxv_lf_group_ac_meta(d, br, idx)
  src = d.src
  f = d.f
  vd = d.vd
  gdb = f.gdim
  gx = idx % f.ggw
  gy = idx / f.ggw
  bx0 = gx * gdb
  by0 = gy * gdb
  rw = vd.bw - bx0
  rw = gdb if rw > gdb
  rh = vd.bh - by0
  rh = gdb if rh > gdb
  nlf = f.ggw * f.ggh
  count = jb_u(src, br, jx_ceil_log2(rw * rh)) + 1
  tw = (rw + 7) >> 3
  th = (rh + 7) >> 3
  chs = [JxCh.new(tw, th, 3, 3), JxCh.new(tw, th, 3, 3), JxCh.new(count, 2, 0, 0), JxCh.new(rw, rh, 0, 0)]
  gi = JxMImg.new(chs, d.m.bpp)
  jxm_read_header(src, br, gi)
  jxm_alloc(gi)
  jxm_decode_channels(src, br, gi, 1 + 2 * nlf + idx, 1 << 30, d.gtree)
  jxm_inverse(gi)
  # CfL tiles
  ty = 0
  while ty < th
    tx = 0
    while tx < tw
      o = ((by0 >> 3) + ty) * vd.tw + (bx0 >> 3) + tx
      vd.ytox[o] = jxv_clamp8(gi.ch[0].d[ty * tw + tx])
      vd.ytob[o] = jxv_clamp8(gi.ch[1].d[ty * tw + tx])
      tx += 1
    ty += 1
  r = jxv_place_blocks(gi.ch[2].d, gi.ch[3].d, count, vd.acs, vd.qf, vd.sharp, vd.bw, vd.bh, bx0, by0, rw, rh, f.gdim >> 3)
  jxl_fail("bad block layout ([r])") if r != 0
  0

-> jxv_clamp8(v)
  return -128 if v < -128
  return 127 if v > 127
  v

# acs: -1 unset; top-left blocks hold the strategy; covered blocks hold
# -(top-left index) - 2.
-> jxv_place_blocks(info, sharp, count, acs, qf, shp, bw, bh, bx0, by0, rw, rh, gblk) (i32[] i32[] i64 i32[] i32[] i32[] i64 i64 i64 i64 i64 i64 i64) i64
  cw = i64[27]
  chh = i64[27]
  i = 0 ## i64
  while i < 27
    lr = 0 ## i64
    lc = 0 ## i64
    cw[i] = 1
    chh[i] = 1
    i += 1
  cw[4] = 2
  chh[4] = 2
  cw[5] = 4
  chh[5] = 4
  cw[6] = 1
  chh[6] = 2
  cw[7] = 2
  chh[7] = 1
  cw[8] = 1
  chh[8] = 4
  cw[9] = 4
  chh[9] = 1
  cw[10] = 2
  chh[10] = 4
  cw[11] = 4
  chh[11] = 2
  cw[18] = 8
  chh[18] = 8
  cw[19] = 4
  chh[19] = 8
  cw[20] = 8
  chh[20] = 4
  cw[21] = 16
  chh[21] = 16
  cw[22] = 8
  chh[22] = 16
  cw[23] = 16
  chh[23] = 8
  cw[24] = 32
  chh[24] = 32
  cw[25] = 16
  chh[25] = 32
  cw[26] = 32
  chh[26] = 16
  num = 0 ## i64
  y = 0 ## i64
  while y < rh
    x = 0 ## i64
    while x < rw
      bi = (by0 + y) * bw + bx0 + x
      s = sharp[y * rw + x] ## i64
      if s < 0 || s > 7
        return 1
      shp[bi] = s
      if acs[bi] == -1
        if num >= count
          return 2
        st = info[num] ## i64
        if st < 0 || st > 26
          return 3
        q = info[count + num] ## i64
        q = 0 if q < 0
        q = 255 if q > 255
        ww = cw[st]
        hh = chh[st]
        gx = bx0 + x
        gy = by0 + y
        if (gx / gblk) != ((gx + ww - 1) / gblk) || (gy / gblk) != ((gy + hh - 1) / gblk)
          return 4
        if gx + ww > bw || gy + hh > bh
          return 5
        yy = 0 ## i64
        while yy < hh
          xx = 0 ## i64
          while xx < ww
            k = (gy + yy) * bw + gx + xx
            if acs[k] != -1
              return 6
            acs[k] = 0 - bi - 2
            qf[k] = q + 1
            xx += 1
          yy += 1
        acs[bi] = st
        num += 1
      x += 1
    y += 1
  0

-> jxv_hf_global(d, br)
  src = d.src
  f = d.f
  vd = d.vd
  nlf = f.ggw * f.ggh
  ng = f.gw * f.gh
  encs = []
  if jb_u(src, br, 1) == 1
    i = 0
    while i < 17
      encs.push([0, nil])
      i += 1
  else
    i = 0
    while i < 17
      dp = JXV_DCT_PARAMS[i]
      encs.push(jxv_read_dq(src, br, d, 1 << dp[0], 1 << dp[1], 1 + 3 * nlf + i))
      i += 1
  vd.dq_enc = encs
  vd.dq = [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil]
  vd.hf_presets = jb_u(src, br, jx_ceil_log2(ng)) + 1
  vd.orders = []
  vd.coef_cs = []
  p = 0
  while p < f.num_passes
    used = jb_u32(src, br, 0x5f, 0, 0x13, 0, 0, 0, 0, 13)
    cs = nil
    es = nil
    win = nil
    if used != 0
      cs = jx_read_code(src, br, 8)
      es = jx_stream(src, br, cs)
      win = jx_window(cs)
    po = []
    o = 0
    while o < 13
      lo = JXV_LOG_ORDER[o]
      nat = jxv_natural_order(lo[0], lo[1])
      size = 1 << (lo[0] + lo[1])
      per = []
      c = 0
      while c < 3
        if ((used >> o) & 1) == 1
          perm = jxl_read_perm(src, br, cs, es, win, size, size / 64)
          ordr = i32[size]
          k = 0
          while k < size
            ordr[k] = nat[perm[k]]
            k += 1
          per.push(ordr)
        else
          per.push(nat)
        c += 1
      po.push(per)
      o += 1
    jx_finish(src, br, cs, es) if used != 0
    vd.orders.push(po)
    vd.coef_cs.push(jx_read_code(src, br, 495 * vd.nb_bctx * vd.hf_presets))
    p += 1
  0

# After all LF groups: adaptive DC smoothing.
-> jxv_finalize_lf(d)
  f = d.f
  vd = d.vd
  return 0 if f.skip_lf_smooth? || f.use_lf_frame?
  facs = f64[3]
  c = 0
  while c < 3
    facs[c] = d.lf_dq[c] * ~65536.0 / (vd.global_scale * vd.quant_lf)
    c += 1
  is444 = vd.hs[0] == 0 && vd.hs[2] == 0 && vd.vs[0] == 0 && vd.vs[2] == 0
  if is444
    w = vd.dcw[0]
    h = vd.dch[0]
    return 0 if w <= 2 || h <= 2
    o0 = f64[w * h]
    o1 = f64[w * h]
    o2 = f64[w * h]
    jxv_smooth3(vd.dc[0], vd.dc[1], vd.dc[2], o0, o1, o2, w, h, facs)
    vd.dc = [o0, o1, o2]
  else
    c = 0
    while c < 3
      w = vd.dcw[c]
      h = vd.dch[c]
      if w > 2 && h > 2
        o = f64[w * h]
        jxv_smooth1(vd.dc[c], o, w, h, facs[c])
        vd.dc[c] = o
      c += 1
  0

-> jxv_smooth3(a, b, c, oa, ob, oc, w, h, facs) (f64[] f64[] f64[] f64[] f64[] f64[] i64 i64 f64[]) i64
  w1 = ~0.20345139757231578
  w2 = ~0.0334829185968739
  w0 = ~1.0 - ~4.0 * (w1 + w2)
  jxv_copy(oa, a, w * h)
  jxv_copy(ob, b, w * h)
  jxv_copy(oc, c, w * h)
  y = 1 ## i64
  while y < h - 1
    x = 1 ## i64
    while x < w - 1
      i = y * w + x
      sa = (a[i - w - 1] + a[i - w + 1] + a[i + w - 1] + a[i + w + 1]) * w2 + (a[i - 1] + a[i + 1] + a[i - w] + a[i + w]) * w1 + a[i] * w0
      sb = (b[i - w - 1] + b[i - w + 1] + b[i + w - 1] + b[i + w + 1]) * w2 + (b[i - 1] + b[i + 1] + b[i - w] + b[i + w]) * w1 + b[i] * w0
      sc = (c[i - w - 1] + c[i - w + 1] + c[i + w - 1] + c[i + w + 1]) * w2 + (c[i - 1] + c[i + 1] + c[i - w] + c[i + w]) * w1 + c[i] * w0
      gap = ~0.5
      g = (a[i] - sa) / facs[0]
      g = ~0.0 - g if g < ~0.0
      gap = g if g > gap
      g = (b[i] - sb) / facs[1]
      g = ~0.0 - g if g < ~0.0
      gap = g if g > gap
      g = (c[i] - sc) / facs[2]
      g = ~0.0 - g if g < ~0.0
      gap = g if g > gap
      fct = ~3.0 - ~4.0 * gap
      fct = ~0.0 if fct < ~0.0
      oa[i] = (sa - a[i]) * fct + a[i]
      ob[i] = (sb - b[i]) * fct + b[i]
      oc[i] = (sc - c[i]) * fct + c[i]
      x += 1
    y += 1
  0

-> jxv_smooth1(a, oa, w, h, fac) (f64[] f64[] i64 i64 f64) i64
  w1 = ~0.20345139757231578
  w2 = ~0.0334829185968739
  w0 = ~1.0 - ~4.0 * (w1 + w2)
  jxv_copy(oa, a, w * h)
  y = 1 ## i64
  while y < h - 1
    x = 1 ## i64
    while x < w - 1
      i = y * w + x
      sa = (a[i - w - 1] + a[i - w + 1] + a[i + w - 1] + a[i + w + 1]) * w2 + (a[i - 1] + a[i + 1] + a[i - w] + a[i + w]) * w1 + a[i] * w0
      gap = ~0.5
      g = (a[i] - sa) / fac
      g = ~0.0 - g if g < ~0.0
      gap = g if g > gap
      fct = ~3.0 - ~4.0 * gap
      fct = ~0.0 if fct < ~0.0
      oa[i] = (sa - a[i]) * fct + a[i]
      x += 1
    y += 1
  0

# ---------------------------------------------------------------- pass groups

-> jxv_pass_group(d, br, pass, g)
  src = d.src
  f = d.f
  vd = d.vd
  gblk = f.gdim >> 3
  gx = g % f.gw
  gy = g / f.gw
  bx0 = gx * gblk
  by0 = gy * gblk
  gbw = vd.bw - bx0
  gbw = gblk if gbw > gblk
  gbh = vd.bh - by0
  gbh = gblk if gbh > gblk
  ctxoff = 495 * vd.nb_bctx * jb_u(src, br, jx_ceil_log2(vd.hf_presets))
  cs = vd.coef_cs[pass]
  es = jx_stream(src, br, cs)
  win = jx_window(cs)
  tb = jxv_tables()
  shift = f.shift[pass]
  po = vd.orders[pass]
  nqf = vd.qf_thr.size
  lfsz = (vd.lf_thr[0].size + 1) * (vd.lf_thr[1].size + 1) * (vd.lf_thr[2].size + 1)
  qft = i64[16]
  k = 0
  while k < nqf
    qft[k] = vd.qf_thr[k]
    k += 1
  bctx = jxv_i64(vd.bctx)
  # order arrays packed: per (order idx, channel) an offset into one i32[]
  ooff = i64[39]
  total = 0
  o = 0
  while o < 13
    c = 0
    while c < 3
      ooff[o * 3 + c] = total
      total += po[o][c].size
      c += 1
    o += 1
  allord = i32[total]
  o = 0
  while o < 13
    c = 0
    while c < 3
      src_o = po[o][c]
      jxv_copy_i32(allord, ooff[o * 3 + c], src_o, src_o.size)
      c += 1
    o += 1
  sel = i64[27 * 4]
  k = 0
  while k < 27
    s4 = JXV_DCT_SELECT[k]
    sel[k * 4] = s4[0]
    sel[k * 4 + 1] = s4[1]
    sel[k * 4 + 2] = s4[2]
    sel[k * 4 + 3] = s4[3]
    k += 1
  hsv = i64[3]
  vsv = i64[3]
  c = 0
  while c < 3
    hsv[c] = vd.hs[c]
    vsv[c] = vd.vs[c]
    c += 1
  r = jxv_group_coeffs(src, br, cs, es, win, vd.acs, vd.qf, vd.qdc, vd.coeffs[0], vd.coeffs[1], vd.coeffs[2], vd.bw, bx0, by0, gbw, gbh, ctxoff, vd.nb_bctx, bctx, qft, nqf, lfsz, allord, ooff, sel, shift, tb[3], tb[4], hsv, vsv)
  jxl_fail("bad coefficients ([r])") if r != 0
  jx_finish(src, br, cs, es)
  0

-> jxv_copy_i32(d, off, s, n) (i32[] i64 i32[] i64) i64
  i = 0 ## i64
  while i < n
    d[off + i] = s[i]
    i += 1
  0

# Coefficient address of index k of a varblock with top-left block (bx, by)
# covering (2^lw) blocks per row: slot (k >> 6) in raster order.
-> jxv_group_coeffs(src, br, cs, es, win, acs, qf, qdc, c0, c1, c2, bw, bx0, by0, gbw, gbh, ctxoff, nbc, bctx, qft, nqf, lfsz, allord, ooff, sel, shift, fctx, nctx, hsv, vsv) (u8[] i64[] i32[] i64[] i32[] i32[] i32[] i32[] i32[] i32[] i32[] i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64 i64 i32[] i64[] i64[] i64 i64[] i64[] i64[] i64[]) i64
  nzs = i64[gbw * gbh * 3 + 3]
  cyx = 0 ## i64
  by = 0 ## i64
  while by < gbh
    bx = 0 ## i64
    while bx < gbw
      gbi = (by0 + by) * bw + bx0 + bx
      st = acs[gbi] ## i64
      if st >= 0
        lr = sel[st * 4]
        lc = sel[st * 4 + 1]
        oi = sel[st * 4 + 3]
        lsz = lr + lc
        cwb = 1 << (lc - 3)
        chb = 1 << (lr - 3)
        if lr > lc
          cwb = 1 << (lr - 3)
          chb = 1 << (lc - 3)
        # covered blocks in pixel space
        pcw = 1 << (lc - 3)
        pch = 1 << (lr - 3)
        lcov = lsz - 6
        qv = qf[gbi] ## i64
        qidx = 0 ## i64
        k = 0 ## i64
        while k < nqf
          qidx += 1 if qv > qft[k]
          k += 1
        lfi = qdc[gbi] ## i64
        cyx = 0
        while cyx < 3
          c = 1
          c = 0 if cyx == 1
          c = 2 if cyx == 2
          hs = hsv[c]
          vs = vsv[c]
          skip = 0 ## i64
          if hs > 0 || vs > 0
            if ((bx >> hs) << hs) != bx || ((by >> vs) << vs) != by
              skip = 1
          if skip == 0
            sbx = bx >> hs
            sby = by >> vs
            sgw = (gbw + (1 << hs) - 1) >> hs
            nzb = c * gbw * gbh
            bc = bctx[((cyx * 13 + oi) * (nqf + 1) + qidx) * lfsz + lfi] ## i64
            pred = 32 ## i64
            if sbx > 0
              if sby > 0
                pred = (nzs[nzb + sby * sgw + sbx - 1] + nzs[nzb + (sby - 1) * sgw + sbx] + 1) >> 1
              else
                pred = nzs[nzb + sby * sgw + sbx - 1]
            elsif sby > 0
              pred = nzs[nzb + (sby - 1) * sgw + sbx]
            pc = pred
            pc = 64 if pc > 64
            nzc = pc
            nzc = 4 + pc / 2 if pc >= 8
            nz = jx_decode(src, br, cs, es, win, ctxoff + nzc * nbc + bc, 0)
            size = 1 << lsz
            cov = 1 << lcov
            if nz > size - cov
              return 1
            qnz = (nz + cov - 1) >> lcov
            yy = 0 ## i64
            while yy < pch
              xx = 0 ## i64
              while xx < pcw
                if sby + yy < (gbh + (1 << vs) - 1) >> vs && sbx + xx < sgw
                  nzs[nzb + (sby + yy) * sgw + sbx + xx] = qnz
                xx += 1
              yy += 1
            hbase = ctxoff + 458 * bc + 37 * nbc
            prev = 0 ## i64
            if nz <= size / 16
              prev = 1
            ob = ooff[oi * 3 + c]
            # channel block coordinates for storage
            cbx = (bx0 + bx) >> hs
            cby = (by0 + by) >> vs
            cbw = (bw + (1 << hs) - 1) >> hs
            k = cov
            while k < size && nz > 0
              ctx = hbase + nctx[(nz + cov - 1) >> lcov] + fctx[k >> lcov] + prev
              u = jx_decode(src, br, cs, es, win, ctx, 0)
              if u != 0
                v = 0 ## i64
                if (u & 1) == 1
                  v = 0 - (u >> 1) - 1
                else
                  v = u >> 1
                v = v << shift
                a = allord[ob + k] ## i64
                slot = a >> 6
                sy = slot >> (lc - 3)
                sx = slot & (pcw - 1)
                addr = ((cby + sy) * cbw + cbx + sx) * 64 + (a & 63)
                if c == 0
                  c0[addr] = c0[addr] + v
                elsif c == 1
                  c1[addr] = c1[addr] + v
                else
                  c2[addr] = c2[addr] + v
                prev = 1
                nz -= 1
              else
                prev = 0
              k += 1
            if nz != 0
              return 2
          cyx += 1
      bx += 1
    by += 1
  0

# ---------------------------------------------------------------- reconstruction

-> jxv_zero(a, n) (f64[] i64) i64
  i = 0 ## i64
  while i < n
    a[i] = ~0.0
    i += 1
  0

JXV_DQ_CACHE = [nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil]
JXV_PARAM_OF = [0, 1, 2, 3, 4, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 10, 10, 11, 12, 12, 13, 14, 14, 15, 16, 16]

-> jxv_used_params(acs, n)
  seen = i64[27]
  jxv_mark_used(acs, n, seen)
  used = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
  k = 0
  while k < 27
    used[JXV_PARAM_OF[k]] = 1 if seen[k] == 1
    k += 1
  used

-> jxv_mark_used(acs, n, seen) (i32[] i64 i64[]) i64
  i = 0 ## i64
  while i < n
    a = acs[i] ## i64
    seen[a] = 1 if a >= 0
    i += 1
  0

JXV_QM_SCALE = [~1.5625, ~1.25, ~1.0, ~0.8, ~0.64, ~0.512, ~0.4096, ~0.32768]

# Reconstruct one channel's varblock into the output plane.
-> jxv_block(coef, ycoef, w, size, cbase, ybase, lc, lr, mul, bias, bias_num, kk, use_cfl, scr, cbw, pcw) (i32[] i32[] f64[] i64 i64 i64 i64 i64 f64 f64 f64 f64 i64 f64[] i64 i64) i64
  # cbase/ybase: block index of the top-left block in the channel storage;
  # weights w are already offset by channel.
  k = 0 ## i64
  while k < size
    slot = k >> 6
    sy = slot >> (lc - 3)
    sx = slot & (pcw - 1)
    off = (sy * cbw + sx) * 64 + (k & 63)
    q = coef[cbase * 64 + off] ## i64
    v = ~0.0
    if q != 0
      qf = q ## f64
      if q >= -1 && q <= 1
        v = qf * bias
      else
        v = qf - bias_num / qf
      v = v * mul / w[k]
    scr[k] = v
    k += 1
  0

-> jxv_add_cfl(scr, yscr, size, kk) (f64[] f64[] i64 f64) i64
  i = 0 ## i64
  while i < size
    scr[i] = scr[i] + yscr[i] * kk
    i += 1
  0

-> jxv_put(plane, pw, ph, scr, x0, y0, lc, effw, effh) (f64[] i64 i64 f64[] i64 i64 i64 i64 i64) i64
  y = 0 ## i64
  while y < effh
    x = 0 ## i64
    while x < effw
      plane[(y0 + y) * pw + x0 + x] = scr[(y << lc) | x]
      x += 1
    y += 1
  0

-> jxv_render(d)
  f = d.f
  m = d.m
  vd = d.vd
  tb = jxv_tables()
  hs = tb[0]
  sc = tb[1]
  basis = tb[2]
  # weight matrices
  used = jxv_used_params(vd.acs, vd.bw * vd.bh)
  i = 0
  while i < 17
    if vd.dq[i] == nil && used[i] == 1
      enc = vd.dq_enc[i]
      if enc[0] == 0
        JXV_DQ_CACHE[i] = jxv_load_dq(i, enc) if JXV_DQ_CACHE[i] == nil
        vd.dq[i] = JXV_DQ_CACHE[i]
      else
        vd.dq[i] = jxv_load_dq(i, enc)
    i += 1
  planes = []
  pws = []
  phs = []
  c = 0
  while c < 3
    pw = (f.fw + (1 << vd.hs[c]) - 1) >> vd.hs[c]
    ph = (f.fh + (1 << vd.vs[c]) - 1) >> vd.vs[c]
    planes.push(f64[pw * ph])
    pws.push(pw)
    phs.push(ph)
    c += 1
  xqm = JXV_QM_SCALE[f.x_qm]
  bqm = JXV_QM_SCALE[f.b_qm]
  xqm = ~1.0 if !m.xyb
  bqm = ~1.0 if !m.xyb
  qb = m.quant_bias
  qbn = m.quant_bias_num
  scr = [f64[65536], f64[65536], f64[65536]]
  scr2 = f64[65536]
  ycf = f64[65536]
  llf = f64[1024]
  llf2 = f64[1024]
  tmp = f64[512]
  tmp2 = f64[512]
  is444 = vd.hs[0] == 0 && vd.hs[2] == 0 && vd.vs[0] == 0 && vd.vs[2] == 0 && vd.hs[1] == 0 && vd.vs[1] == 0
  bw = vd.bw
  bh = vd.bh
  by = 0
  while by < bh
    bx = 0
    while bx < bw
      st = vd.acs[by * bw + bx]
      if st >= 0
        sel = JXV_DCT_SELECT[st]
        lr = sel[0]
        lc = sel[1]
        size = 1 << (lr + lc)
        pcw = 1 << (lc - 3)
        pch = 1 << (lr - 3)
        wts = vd.dq[sel[2]]
        qf = vd.qf[by * bw + bx]
        my = ~65536.0 / vd.global_scale / qf
        muls = [my * xqm, my, my * bqm]
        tile = (by >> 3) * vd.tw + (bx >> 3)
        kx = vd.base_x + vd.inv_cf * vd.ytox[tile]
        kb = vd.base_b + vd.inv_cf * vd.ytob[tile]
        # channel order Y first so CfL can use it
        cl = [1, 0, 2]
        cl.each ->(c)
          chs = vd.hs[c]
          cvs = vd.vs[c]
          if ((bx >> chs) << chs) == bx && ((by >> cvs) << cvs) == by
            cbx = bx >> chs
            cby = by >> cvs
            cbw = (bw + (1 << chs) - 1) >> chs
            wsub = jxv_wslice(wts, c, size)
            jxv_block(vd.coeffs[c], vd.coeffs[1], wsub, size, cby * cbw + cbx, 0, lc, lr, muls[c], qb[c], qbn, ~0.0, 0, scr[c], cbw, pcw)
            if is444 && c == 1
              jxv_copy(ycf, scr[1], size)
            elsif is444 && c == 0
              jxv_add_cfl(scr[0], ycf, size, kx)
            elsif is444 && c == 2
              jxv_add_cfl(scr[2], ycf, size, kb)
            # LLF from DC
            dcp = vd.dc[c]
            dcw = vd.dcw[c]
            if lr == 3 && lc == 3
              scr[c][0] = dcp[cby * dcw + cbx]
            else
              yy = 0
              while yy < pch
                xx = 0
                while xx < pcw
                  llf[yy * pcw + xx] = dcp[(cby + yy) * dcw + cbx + xx]
                  xx += 1
                yy += 1
              jxv_llf_from_dc(llf, llf2, lr - 3, lc - 3, sc)
              mn = pch
              mx = pcw
              if pch > pcw
                mn = pcw
                mx = pch
              jxv_put_llf(scr[c], llf, mn, mx)
            jxv_inverse(st, scr[c], scr2, lr, lc, tmp, tmp2, hs, basis)
            px0 = cbx * 8
            py0 = cby * 8
            effw = pws[c] - px0
            effw = (1 << lc) if effw > (1 << lc)
            effh = phs[c] - py0
            effh = (1 << lr) if effh > (1 << lr)
            jxv_put(planes[c], pws[c], phs[c], scr[c], px0, py0, lc, effw, effh) if effw > 0 && effh > 0
      bx += 1
    by += 1
  [[planes[0], pws[0], phs[0]], [planes[1], pws[1], phs[1]], [planes[2], pws[2], phs[2]]]

-> jxv_wslice(w, c, size)
  o = f64[size]
  jxv_copy_off(o, w, c * size, size)
  o

-> jxv_copy_off(d, s, off, n) (f64[] f64[] i64 i64) i64
  i = 0 ## i64
  while i < n
    d[i] = s[off + i]
    i += 1
  0

-> jxv_put_llf(scr, llf, mn, mx) (f64[] f64[] i64 i64) i64
  y = 0 ## i64
  while y < mn
    x = 0 ## i64
    while x < mx
      scr[y * mx * 8 + x] = llf[y * mx + x]
      x += 1
    y += 1
  0

-> jxv_inverse(st, buf, scr, lr, lc, tmp, tmp2, hs, basis) (i64 f64[] f64[] i64 i64 f64[] f64[] f64[] f64[]) i64
  if st == 1
    jxv_hornuss(buf, scr)
  elsif st == 2
    jxv_idct11(buf, scr)
  elsif st == 3
    jxv_idct22(buf, scr, tmp, tmp2, hs)
  elsif st == 12
    jxv_idct23(buf, scr, tmp, tmp2, hs)
  elsif st == 13
    jxv_idct32(buf, scr, tmp, tmp2, hs)
  elsif st == 14
    jxv_afv(buf, scr, 0, 0, tmp, tmp2, hs, basis)
  elsif st == 15
    jxv_afv(buf, scr, 1, 0, tmp, tmp2, hs, basis)
  elsif st == 16
    jxv_afv(buf, scr, 0, 1, tmp, tmp2, hs, basis)
  elsif st == 17
    jxv_afv(buf, scr, 1, 1, tmp, tmp2, hs, basis)
  else
    jxv_idct2d(buf, scr, lr, lc, tmp, tmp2, hs)
  0
