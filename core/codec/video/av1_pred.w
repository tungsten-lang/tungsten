# core/codec/video/av1_pred — AV1 intra prediction (spec 7.11.2): edge preparation,
# intra edge filter / upsampling, directional, DC, smooth, paeth, recursive
# filter intra, chroma-from-luma and palette prediction. Writes straight into
# the current frame's u16 planes. Reopens Av1Decoder.

use av1_tables

AV1_EOFF = 16

-> av1_pred_smw
  out = i32[128]
  # concatenated Sm_Weights tables: offset for log2 n is n (4→4, 8→8, ...)
  t = [AV1_SM_WEIGHTS_TX_4X4, AV1_SM_WEIGHTS_TX_8X8, AV1_SM_WEIGHTS_TX_16X16, AV1_SM_WEIGHTS_TX_32X32, AV1_SM_WEIGHTS_TX_64X64]
  k = 0
  while k < 5
    n = 4 << k
    i = 0
    while i < n
      out[n + i] = t[k][i]
      i += 1
    k += 1
  out

-> av1_pred_i32(a)
  out = i32[a.size]
  i = 0
  while i < a.size
    out[i] = a[i]
    i += 1
  out

AV1_SM_W = av1_pred_smw()
AV1_DR_DERIV = av1_pred_i32(AV1_DR_INTRA_DERIVATIVE)
AV1_FI_TAPS = av1_pred_i32(AV1_INTRA_FILTER_TAPS)
AV1_EDGE_KERNEL = av1_pred_i32(AV1_INTRA_EDGE_KERNEL)

+ Av1Decoder
  -> recon_begin
    @edge_above = i32[320]
    @edge_left = i32[320]
    @edge_tmp = i32[320]
    nil

  -> predict_intra(plane, x, y, have_left, have_above, have_ar, have_bl, mode, log2w, log2h)
    fr = @cur
    pl = fr.planes[plane]
    stride = fr.strides[plane]
    w = 1 << log2w
    h = 1 << log2h
    max_x = (@mi_cols * 4) - 1
    max_y = (@mi_rows * 4) - 1
    if plane > 0
      max_x = ((@mi_cols * 4) >> @ssx) - 1
      max_y = ((@mi_rows * 4) >> @ssy) - 1
    ab = @edge_above
    lf = @edge_left
    hl = have_left ? 1 : 0
    ha = have_above ? 1 : 0
    av1_intra_edges(pl, stride, x, y, w, h, hl, ha, have_ar ? 1 : 0, have_bl ? 1 : 0, max_x, max_y, @bit_depth, ab, lf)
    bd = @bit_depth
    if plane == 0 && @use_filter_intra == 1
      av1_pred_filter(pl, stride, x, y, w, h, ab, lf, AV1_FI_TAPS, @filter_intra_mode, bd)
    elsif mode >= 1 && mode <= 8
      angle_delta = plane == 0 ? @angle_delta_y : @angle_delta_uv
      p_angle = AV1_MODE_TO_ANGLE[mode] + angle_delta * 3
      ua = 0
      ul = 0
      if @enable_intra_edge == 1
        if p_angle != 90 && p_angle != 180
          if p_angle > 90 && p_angle < 180 && (w + h) >= 24
            s = lf[AV1_EOFF] * 5 + ab[AV1_EOFF - 1] * 6 + ab[AV1_EOFF] * 5
            v = (s + 8) >> 4
            lf[AV1_EOFF - 1] = v
            ab[AV1_EOFF - 1] = v
          ft = intra_filter_type(plane)
          if have_above
            strength = av1_edge_strength(w, h, ft, p_angle - 90)
            npx = av1_min(w, max_x - x + 1) + (p_angle < 90 ? h : 0) + 1
            av1_edge_filter(ab, npx, strength, AV1_EDGE_KERNEL, @edge_tmp)
          if have_left
            strength = av1_edge_strength(w, h, ft, p_angle - 180)
            npx = av1_min(h, max_y - y + 1) + (p_angle > 180 ? w : 0) + 1
            av1_edge_filter(lf, npx, strength, AV1_EDGE_KERNEL, @edge_tmp)
        ft2 = intra_filter_type(plane)
        ua = av1_use_upsample(w, h, ft2, p_angle - 90)
        npx = w + (p_angle < 90 ? h : 0)
        av1_edge_upsample(ab, npx, bd, @edge_tmp) if ua == 1
        ul = av1_use_upsample(w, h, ft2, p_angle - 180)
        npx = h + (p_angle > 180 ? w : 0)
        av1_edge_upsample(lf, npx, bd, @edge_tmp) if ul == 1
      dx = 0
      dy = 0
      if p_angle < 90
        dx = AV1_DR_DERIV[p_angle]
      elsif p_angle > 90 && p_angle < 180
        dx = AV1_DR_DERIV[180 - p_angle]
      if p_angle > 90 && p_angle < 180
        dy = AV1_DR_DERIV[p_angle - 90]
      elsif p_angle > 180
        dy = AV1_DR_DERIV[270 - p_angle]
      av1_pred_dir(pl, stride, x, y, w, h, ab, lf, p_angle, dx, dy, ua, ul)
    elsif mode == 9 || mode == 10 || mode == 11
      av1_pred_smooth(pl, stride, x, y, w, h, ab, lf, mode, AV1_SM_W)
    elsif mode == 0
      av1_pred_dc(pl, stride, x, y, w, h, log2w, log2h, ab, lf, hl, ha, bd)
    else
      av1_pred_paeth(pl, stride, x, y, w, h, ab, lf)
    nil

  -> intra_filter_type(plane)
    above_s = false
    left_s = false
    mis = @mis
    if (plane == 0 ? @avail_u : @avail_u_chroma)
      r = @mi_row - 1
      c = @mi_col
      if plane > 0
        c += 1 if @ssx == 1 && (@mi_col & 1) == 0
        r -= 1 if @ssy == 1 && (@mi_row & 1) == 1
      above_s = is_smooth(r, c, plane)
    if (plane == 0 ? @avail_l : @avail_l_chroma)
      r = @mi_row
      c = @mi_col - 1
      if plane > 0
        c -= 1 if @ssx == 1 && (@mi_col & 1) == 1
        r += 1 if @ssy == 1 && (@mi_row & 1) == 0
      left_s = is_smooth(r, c, plane)
    (above_s || left_s) ? 1 : 0

  -> is_smooth(r, c, plane)
    k = r * @mis + c
    mode = 0
    if plane == 0
      mode = @a_y_modes[k]
    else
      return false if @a_ref0[k] > 0
      mode = @a_uv_modes[k]
    mode == 9 || mode == 10 || mode == 11

  -> predict_cfl(plane, sx0, sy0, tx_sz)
    fr = @cur
    alpha = plane == 1 ? @cfl_alpha_u : @cfl_alpha_v
    av1_pred_cfl(fr.planes[plane], fr.strides[plane], fr.planes[0], fr.strides[0], sx0, sy0, AV1_TXW[tx_sz], AV1_TXH[tx_sz], AV1_TXWL[tx_sz] + AV1_TXHL[tx_sz], @ssx, @ssy, @max_luma_w, @max_luma_h, alpha, @bit_depth)
    nil

  -> predict_palette(plane, sx0, sy0, x, y, tx_sz)
    fr = @cur
    pal = plane == 0 ? @palette_colors_y : (plane == 1 ? @palette_colors_u : @palette_colors_v)
    m = plane == 0 ? @color_map_y : @color_map_uv
    pl = fr.planes[plane]
    stride = fr.strides[plane]
    w = AV1_TXW[tx_sz]
    h = AV1_TXH[tx_sz]
    pt = i32[8]
    i = 0
    while i < pal.size
      pt[i] = pal[i]
      i += 1
    av1_pred_pal(pl, stride, sx0, sy0, w, h, m, x * 4, y * 4, pt)
    nil

# ---------------------------------------------------------------- typed kernels

-> av1_intra_edges(pl, stride, x, y, w, h, hl, ha, har, hbl, max_x, max_y, bd, ab, lf) (u16[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i32[] i32[]) i64
  o = (16) ## i64
  n = (w + h) ## i64
  i = 0 ## i64
  if ha == 0 && hl == 1
    v = (pl[y * stride + x - 1]) ## i64
    while i < n
      ab[o + i] = v
      i += 1
  elsif ha == 0 && hl == 0
    v = (1 << (bd - 1)) - 1
    while i < n
      ab[o + i] = v
      i += 1
  else
    lim = (x + (har == 1 ? 2 * w : w) - 1) ## i64
    lim = max_x if max_x < lim
    r = ((y - 1) * stride) ## i64
    while i < n
      xx = (x + i) ## i64
      xx = lim if xx > lim
      ab[o + i] = pl[r + xx]
      i += 1
  i = 0
  if hl == 0 && ha == 1
    v = pl[(y - 1) * stride + x]
    while i < n
      lf[o + i] = v
      i += 1
  elsif hl == 0 && ha == 0
    v = (1 << (bd - 1)) + 1
    while i < n
      lf[o + i] = v
      i += 1
  else
    lim = y + (hbl == 1 ? 2 * h : h) - 1
    lim = max_y if max_y < lim
    while i < n
      yy = (y + i) ## i64
      yy = lim if yy > lim
      lf[o + i] = pl[yy * stride + x - 1]
      i += 1
  c = 0 ## i64
  if ha == 1 && hl == 1
    c = pl[(y - 1) * stride + x - 1]
  elsif ha == 1
    c = pl[(y - 1) * stride + x]
  elsif hl == 1
    c = pl[y * stride + x - 1]
  else
    c = 1 << (bd - 1)
  ab[o - 1] = c
  lf[o - 1] = c
  0

-> av1_edge_strength(w, h, ft, delta) (i64 i64 i64 i64) i64
  d = (delta < 0 ? 0 - delta : delta) ## i64
  wh = (w + h) ## i64
  s = 0 ## i64
  if ft == 0
    if wh <= 8
      s = 1 if d >= 56
    elsif wh <= 12
      s = 1 if d >= 40
    elsif wh <= 16
      s = 1 if d >= 40
    elsif wh <= 24
      s = 1 if d >= 8
      s = 2 if d >= 16
      s = 3 if d >= 32
    elsif wh <= 32
      s = 1
      s = 2 if d >= 4
      s = 3 if d >= 32
    else
      s = 3
  else
    if wh <= 8
      s = 1 if d >= 40
      s = 2 if d >= 64
    elsif wh <= 16
      s = 1 if d >= 20
      s = 2 if d >= 48
    elsif wh <= 24
      s = 3 if d >= 4
    else
      s = 3
  s

-> av1_use_upsample(w, h, ft, delta) (i64 i64 i64 i64) i64
  d = (delta < 0 ? 0 - delta : delta) ## i64
  wh = (w + h) ## i64
  if d <= 0 || d >= 40
    return 0
  if ft == 0
    return wh <= 16 ? 1 : 0
  wh <= 8 ? 1 : 0

# Intra edge filter on buf[-1 .. sz-2] (buf index o-1 .. ): edge[i] = buf[i - 1].
-> av1_edge_filter(buf, sz, strength, kern, tmp) (i32[] i64 i64 i32[] i32[]) i64
  return 0 if strength == 0
  o = (16) ## i64
  i = 0 ## i64
  while i < sz
    tmp[i] = buf[o + i - 1]
    i += 1
  kb = ((strength - 1) * 5) ## i64
  i = 1
  while i < sz
    s = 0 ## i64
    j = 0 ## i64
    while j < 5
      k = (i - 2 + j) ## i64
      k = 0 if k < 0
      k = sz - 1 if k > sz - 1
      s += kern[kb + j] * tmp[k]
      j += 1
    buf[o + i - 1] = (s + 8) >> 4
    i += 1
  0

-> av1_edge_upsample(buf, npx, bd, dup) (i32[] i64 i64 i32[]) i64
  o = (16) ## i64
  mx = ((1 << bd) - 1) ## i64
  dup[0] = buf[o - 1]
  i = -1 ## i64
  while i < npx
    dup[i + 2] = buf[o + i]
    i += 1
  dup[npx + 2] = buf[o + npx - 1]
  buf[o - 2] = dup[0]
  i = 0
  while i < npx
    s = (0 - dup[i] + 9 * dup[i + 1] + 9 * dup[i + 2] - dup[i + 3]) ## i64
    s = (s + 8) >> 4
    s = 0 if s < 0
    s = mx if s > mx
    buf[o + 2 * i - 1] = s
    buf[o + 2 * i] = dup[i + 2]
    i += 1
  0

-> av1_pred_dir(pl, stride, x, y, w, h, ab, lf, pa, dx, dy, ua, ul) (u16[] i64 i64 i64 i64 i64 i32[] i32[] i64 i64 i64 i64 i64) i64
  o = (16) ## i64
  i = 0 ## i64
  if pa < 90
    max_base = ((w + h - 1) << ua) ## i64
    while i < h
      idx = ((i + 1) * dx) ## i64
      sh = (((idx << ua) >> 1) & 31) ## i64
      b0 = (idx >> (6 - ua)) ## i64
      r = ((y + i) * stride + x) ## i64
      j = 0 ## i64
      while j < w
        base = (b0 + (j << ua)) ## i64
        v = 0 ## i64
        if base < max_base
          v = (ab[o + base] * (32 - sh) + ab[o + base + 1] * sh + 16) >> 5
        else
          v = ab[o + max_base]
        pl[r + j] = v
        j += 1
      i += 1
  elsif pa > 90 && pa < 180
    lim = (0 - (1 << ua)) ## i64
    while i < h
      r = (y + i) * stride + x
      j = 0 ## i64
      while j < w
        idx = (j << 6) - (i + 1) * dx
        base = idx >> (6 - ua)
        v = 0 ## i64
        if base >= lim
          sh = ((idx << ua) >> 1) & 31
          v = (ab[o + base] * (32 - sh) + ab[o + base + 1] * sh + 16) >> 5
        else
          idx = (i << 6) - (j + 1) * dy
          base = idx >> (6 - ul)
          sh = ((idx << ul) >> 1) & 31
          v = (lf[o + base] * (32 - sh) + lf[o + base + 1] * sh + 16) >> 5
        pl[r + j] = v
        j += 1
      i += 1
  elsif pa > 180
    j = 0 ## i64
    while j < w
      idx = (j + 1) * dy
      sh = ((idx << ul) >> 1) & 31
      b0 = idx >> (6 - ul)
      i = 0
      while i < h
        base = b0 + (i << ul)
        pl[(y + i) * stride + x + j] = (lf[o + base] * (32 - sh) + lf[o + base + 1] * sh + 16) >> 5
        i += 1
      j += 1
  elsif pa == 90
    while i < h
      r = (y + i) * stride + x
      j = 0 ## i64
      while j < w
        pl[r + j] = ab[o + j]
        j += 1
      i += 1
  else
    while i < h
      r = (y + i) * stride + x
      v = lf[o + i]
      j = 0 ## i64
      while j < w
        pl[r + j] = v
        j += 1
      i += 1
  0

-> av1_pred_smooth(pl, stride, x, y, w, h, ab, lf, mode, smw) (u16[] i64 i64 i64 i64 i64 i32[] i32[] i64 i32[]) i64
  o = (16) ## i64
  bl = (lf[o + h - 1]) ## i64
  tr = (ab[o + w - 1]) ## i64
  i = 0 ## i64
  while i < h
    r = ((y + i) * stride + x) ## i64
    wy = (smw[h + i]) ## i64
    j = 0 ## i64
    while j < w
      wx = (smw[w + j]) ## i64
      v = 0 ## i64
      if mode == 9
        sp = (wy * ab[o + j] + (256 - wy) * bl + wx * lf[o + i] + (256 - wx) * tr) ## i64
        v = (sp + 256) >> 9
      elsif mode == 10
        sp = wy * ab[o + j] + (256 - wy) * bl
        v = (sp + 128) >> 8
      else
        sp = wx * lf[o + i] + (256 - wx) * tr
        v = (sp + 128) >> 8
      pl[r + j] = v
      j += 1
    i += 1
  0

-> av1_pred_dc(pl, stride, x, y, w, h, log2w, log2h, ab, lf, hl, ha, bd) (u16[] i64 i64 i64 i64 i64 i64 i64 i32[] i32[] i64 i64 i64) i64
  o = (16) ## i64
  mx = ((1 << bd) - 1) ## i64
  avg = 0 ## i64
  sum = 0 ## i64
  k = 0 ## i64
  if hl == 1 && ha == 1
    while k < h
      sum += lf[o + k]
      k += 1
    k = 0
    while k < w
      sum += ab[o + k]
      k += 1
    sum += (w + h) >> 1
    avg = sum / (w + h)
  elsif hl == 1
    while k < h
      sum += lf[o + k]
      k += 1
    avg = (sum + (h >> 1)) >> log2h
    avg = mx if avg > mx
  elsif ha == 1
    while k < w
      sum += ab[o + k]
      k += 1
    avg = (sum + (w >> 1)) >> log2w
    avg = mx if avg > mx
  else
    avg = 1 << (bd - 1)
  i = 0 ## i64
  while i < h
    r = ((y + i) * stride + x) ## i64
    j = 0 ## i64
    while j < w
      pl[r + j] = avg
      j += 1
    i += 1
  0

-> av1_pred_paeth(pl, stride, x, y, w, h, ab, lf) (u16[] i64 i64 i64 i64 i64 i32[] i32[]) i64
  o = (16) ## i64
  tl = (ab[o - 1]) ## i64
  i = 0 ## i64
  while i < h
    r = ((y + i) * stride + x) ## i64
    lv = (lf[o + i]) ## i64
    j = 0 ## i64
    while j < w
      av = (ab[o + j]) ## i64
      base = (av + lv - tl) ## i64
      pl_ = (base - lv) ## i64
      pl_ = 0 - pl_ if pl_ < 0
      pt = (base - av) ## i64
      pt = 0 - pt if pt < 0
      ptl = (base - tl) ## i64
      ptl = 0 - ptl if ptl < 0
      v = 0 ## i64
      if pl_ <= pt && pl_ <= ptl
        v = lv
      elsif pt <= ptl
        v = av
      else
        v = tl
      pl[r + j] = v
      j += 1
    i += 1
  0

-> av1_pred_filter(pl, stride, x, y, w, h, ab, lf, taps, fmode, bd) (u16[] i64 i64 i64 i64 i64 i32[] i32[] i32[] i64 i64) i64
  o = (16) ## i64
  mx = ((1 << bd) - 1) ## i64
  w4 = (w >> 2) ## i64
  h2 = (h >> 1) ## i64
  p = i32[7]
  i2 = 0 ## i64
  while i2 < h2
    j4 = 0 ## i64
    while j4 < w4
      i = 0 ## i64
      while i < 7
        v = 0 ## i64
        if i < 5
          if i2 == 0
            v = ab[o + (j4 << 2) + i - 1]
          elsif j4 == 0 && i == 0
            v = lf[o + (i2 << 1) - 1]
          else
            v = pl[(y + (i2 << 1) - 1) * stride + x + (j4 << 2) + i - 1]
        else
          if j4 == 0
            v = lf[o + (i2 << 1) + i - 5]
          else
            v = pl[(y + (i2 << 1) + i - 5) * stride + x + (j4 << 2) - 1]
        p[i] = v
        i += 1
      i1 = 0 ## i64
      while i1 < 2
        j1 = 0 ## i64
        while j1 < 4
          pr = 0 ## i64
          tb = ((fmode * 8 + (i1 << 2) + j1) * 7) ## i64
          i = 0
          while i < 7
            pr += taps[tb + i] * p[i]
            i += 1
          v = 0 ## i64
          if pr >= 0
            v = (pr + 8) >> 4
          else
            v = 0 - ((0 - pr + 8) >> 4)
          v = 0 if v < 0
          v = mx if v > mx
          pl[(y + (i2 << 1) + i1) * stride + x + (j4 << 2) + j1] = v
          j1 += 1
        i1 += 1
      j4 += 1
    i2 += 1
  0

-> av1_pred_cfl(cp, cs, lp, ls, sx0, sy0, w, h, l2wh, ssx, ssy, mlw, mlh, alpha, bd) (u16[] i64 u16[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
  mx = ((1 << bd) - 1) ## i64
  lbuf = i32[w * h]
  avg = 0 ## i64
  i = 0 ## i64
  while i < h
    ly = ((sy0 + i) << ssy) ## i64
    lim = (mlh - (1 << ssy)) ## i64
    ly = lim if ly > lim
    j = 0 ## i64
    while j < w
      lx = ((sx0 + j) << ssx) ## i64
      limx = (mlw - (1 << ssx)) ## i64
      lx = limx if lx > limx
      t = 0 ## i64
      dy = 0 ## i64
      while dy <= ssy
        dx = 0 ## i64
        while dx <= ssx
          t += lp[(ly + dy) * ls + lx + dx]
          dx += 1
        dy += 1
      v = (t << (3 - ssx - ssy)) ## i64
      lbuf[i * w + j] = v
      avg += v
      j += 1
    i += 1
  avg = (avg + (1 << (l2wh - 1))) >> l2wh
  i = 0
  while i < h
    j = 0 ## i64
    r = ((sy0 + i) * cs + sx0) ## i64
    while j < w
      dc = (cp[r + j]) ## i64
      m = (alpha * (lbuf[i * w + j] - avg)) ## i64
      sl = 0 ## i64
      if m >= 0
        sl = (m + 32) >> 6
      else
        sl = 0 - ((0 - m + 32) >> 6)
      v = dc + sl
      v = 0 if v < 0
      v = mx if v > mx
      cp[r + j] = v
      j += 1
    i += 1
  0

-> av1_pred_pal(pl, stride, sx0, sy0, w, h, m, mx0, my0, pal) (u16[] i64 i64 i64 i64 i64 u8[] i64 i64 i32[]) i64
  i = 0 ## i64
  while i < h
    j = 0 ## i64
    while j < w
      pl[(sy0 + i) * stride + sx0 + j] = pal[m[(my0 + i) * 64 + mx0 + j]]
      j += 1
    i += 1
  0
