# core/codec/image/jxl_render — JPEG XL frame rendering: chroma upsampling, restoration
# filters (Gaborish, EPF), upsampling, patches, splines, noise, colour
# transforms (XYB → linear sRGB, YCbCr → RGB), blending/compositing of frames
# and the final conversion to 8-bit sRGB RGBA.

use core/codec/image
use jxl_ans
use jxl_features

# ---------------------------------------------------------------- colour

-> jxr_srgb_enc(v) (f64) f64
  return ~0.0 if v <= ~0.0
  return ~1.0 if v >= ~1.0
  if v <= ~0.0031308
    return v * ~12.92
  ~1.055 * Math.exp(Math.log(v) / ~2.4) - ~0.055

-> jxr_srgb_dec(v) (f64) f64
  if v <= ~0.04045
    return v / ~12.92
  Math.exp(Math.log((v + ~0.055) / ~1.055) * ~2.4)

# Lookup table for linear [0,1] → sRGB-encoded, 4096 + 1 entries.
JXR_LUT = [nil]

-> jxr_lut
  if JXR_LUT[0] == nil
    t = f64[16385]
    i = 0
    while i <= 16384
      t[i] = jxr_srgb_enc(i / ~16384.0)
      i += 1
    JXR_LUT[0] = t
  JXR_LUT[0]

# XYB → linear sRGB (in place: x,y,b become r,g,b), then sRGB-encode.
-> jxr_xyb_to_srgb(px, py, pb, n, mt, bias, cb, lut, tm, al, unpre) (f64[] f64[] f64[] i64 f64[] f64[] f64[] f64[] f64 f64[] i64) i64
  i = 0 ## i64
  while i < n
    x = px[i]
    y = py[i]
    b = pb[i]
    gr = y + x - cb[0]
    gg = y - x - cb[1]
    gb = b - cb[2]
    mr = gr * gr * gr + bias[0]
    mg = gg * gg * gg + bias[1]
    mb = gb * gb * gb + bias[2]
    r = mt[0] * mr + mt[1] * mg + mt[2] * mb
    g = mt[3] * mr + mt[4] * mg + mt[5] * mb
    bb = mt[6] * mr + mt[7] * mg + mt[8] * mb
    if tm > ~0.0
      # simple HDR → SDR tone map on luminance
      l = ~0.2126 * r + ~0.7152 * g + ~0.0722 * bb
      if l > ~0.0
        s = (~1.0 + l * tm) / (~1.0 + l)
        r = r * s / (~1.0 + l * tm) * (~1.0 + tm)
        g = g * s / (~1.0 + l * tm) * (~1.0 + tm)
        bb = bb * s / (~1.0 + l * tm) * (~1.0 + tm)
    if unpre == 1
      av = al[i]
      if av > ~0.000000015
        r = r / av
        g = g / av
        bb = bb / av
    px[i] = jxr_lut_enc(r, lut)
    py[i] = jxr_lut_enc(g, lut)
    pb[i] = jxr_lut_enc(bb, lut)
    i += 1
  0

-> jxr_lut_enc(v, lut) (f64 f64[]) f64
  if v <= ~0.0
    return ~0.0
  if v >= ~1.0
    return ~1.0
  if v < ~0.0031308
    return v * ~12.92
  f = v * ~16384.0
  k = f ## i64
  t = f - k
  lut[k] + (lut[k + 1] - lut[k]) * t

-> jxr_ycbcr(pcb, py, pcr, n) (f64[] f64[] f64[] i64) i64
  i = 0 ## i64
  while i < n
    cb = pcb[i]
    y = py[i] + ~0.5019607843137255
    cr = pcr[i]
    r = y + ~1.402 * cr
    g = y - ~0.344136286201022 * cb - ~0.714136286201022 * cr
    b = y + ~1.772 * cb
    pcb[i] = r
    py[i] = g
    pcr[i] = b
    i += 1
  0

# Transfer function of a (non-XYB) image → sRGB-encoded values in place.
-> jxr_tf_to_srgb(p, n, tf, gamma, lut, tm) (f64[] i64 i64 f64 f64[] f64) i64
  i = 0 ## i64
  while i < n
    v = p[i]
    lin = v
    if tf == 8
      lin = v
    elsif tf == 0
      if v <= ~0.0
        lin = ~0.0
      else
        lin = Math.exp(Math.log(v) / gamma)
    elsif tf == 1
      if v < ~0.081
        lin = v / ~4.5
      else
        lin = Math.exp(Math.log((v + ~0.099) / ~1.099) / ~0.45)
    elsif tf == 17
      if v <= ~0.0
        lin = ~0.0
      else
        lin = Math.exp(Math.log(v) * ~2.6)
    elsif tf == 16
      lin = jxr_pq_to_linear(v) * tm
    elsif tf == 18
      lin = jxr_hlg_to_linear(v)
    p[i] = jxr_lut_enc(lin, lut)
    i += 1
  0

-> jxr_pq_to_linear(v) (f64) f64
  if v <= ~0.0
    return ~0.0
  m1 = ~0.1593017578125
  m2 = ~78.84375
  c1 = ~0.8359375
  c2 = ~18.8515625
  c3 = ~18.6875
  e = Math.exp(Math.log(v) / m2)
  num = e - c1
  num = ~0.0 if num < ~0.0
  den = c2 - c3 * e
  Math.exp(Math.log(num / den) / m1)

-> jxr_hlg_to_linear(v) (f64) f64
  if v <= ~0.0
    return ~0.0
  if v <= ~0.5
    return v * v / ~3.0
  a = ~0.17883277
  b = ~0.28466892
  c = ~0.55991073
  (Math.exp((v - c) / a) + b) / ~12.0

# ---------------------------------------------------------------- resampling helpers

# Nearest/box chroma upsampling for subsampled YCbCr channels (libjxl uses a
# 3/4-1/4 linear filter; we do the same).
-> jxr_up_h(s, sw, h, o, ow) (f64[] i64 i64 f64[] i64) i64
  y = 0 ## i64
  while y < h
    sb = y * sw
    ob = y * ow
    x = 0 ## i64
    while x < sw
      c = s[sb + x]
      l = c
      if x > 0
        l = s[sb + x - 1]
      r = c
      if x + 1 < sw
        r = s[sb + x + 1]
      if 2 * x < ow
        o[ob + 2 * x] = ~0.25 * l + ~0.75 * c
      if 2 * x + 1 < ow
        o[ob + 2 * x + 1] = ~0.75 * c + ~0.25 * r
      x += 1
    y += 1
  0

-> jxr_up_v(s, w, sh, o, oh) (f64[] i64 i64 f64[] i64) i64
  y = 0 ## i64
  while y < sh
    ym = y - 1
    ym = 0 if ym < 0
    yp = y + 1
    yp = sh - 1 if yp >= sh
    x = 0 ## i64
    while x < w
      c = s[y * w + x]
      u = s[ym * w + x]
      dn = s[yp * w + x]
      if 2 * y < oh
        o[2 * y * w + x] = ~0.25 * u + ~0.75 * c
      if 2 * y + 1 < oh
        o[(2 * y + 1) * w + x] = ~0.75 * c + ~0.25 * dn
      x += 1
    y += 1
  0

# plane [arr, w, h] → upsampled to (tw, th) by repeated 2x steps.
-> jxr_chroma_up(pl, hs, vs, tw, th)
  a = pl[0]
  w = pl[1]
  h = pl[2]
  if hs > 0
    nw = w * 2
    nw = tw if nw > tw && tw > w
    o = f64[nw * h]
    jxr_up_h(a, w, h, o, nw)
    a = o
    w = nw
  if vs > 0
    nh = h * 2
    nh = th if nh > th && th > h
    o = f64[w * nh]
    jxr_up_v(a, w, h, o, nh)
    a = o
    h = nh
  [a, w, h]

# ---------------------------------------------------------------- compositing

-> jxr_new_canvas(m)
  n = m.width * m.height
  planes = []
  k = 0
  while k < 3 + m.ec.size
    planes.push(f64[n])
    k += 1
  planes

-> jxr_clone_canvas(c)
  out = []
  c.each ->(p)
    q = f64[p.size]
    jxr_copy_f(q, p, p.size)
    out.push(q)
  out

-> jxr_copy_f(d, s, n) (f64[] f64[] i64) i64
  i = 0 ## i64
  while i < n
    d[i] = s[i]
    i += 1
  0

# Render the decoded frame (d.planes / d.ecplanes) and composite it onto the
# canvas. Returns the new canvas (or the old one for reference-only frames).
-> jxr_composite(d, canvas)
  m = d.m
  f = d.f
  canvas = jxr_new_canvas(m) if canvas == nil
  pl = d.planes
  # chroma upsampling (YCbCr)
  if f.ycbcr
    k = 0
    while k < 3
      hs = jxl_ycc_hshift(f, k)
      vs = jxl_ycc_vshift(f, k)
      pl[k] = jxr_chroma_up(pl[k], hs, vs, f.fw, f.fh) if hs > 0 || vs > 0
      k += 1
  # restoration filters
  jxr_gaborish(d, pl) if f.gab
  jxr_epf(d, pl) if f.epf_iters > 0
  ec = d.ecplanes
  # extra channel upsampling to the colour resolution
  k = 0
  while k < ec.size
    e = ec[k]
    if e[1] < f.fw || e[2] < f.fh
      ec[k] = jxr_upsample(d, e, f.ec_up[k] / f.upsampling, f.fw, f.fh)
    k += 1
  jxf_patches(d, pl, ec) if f.patches? && d.patches != nil
  jxf_splines(d, pl) if f.splines? && d.splines != nil
  # colour upsampling
  fw = f.fw * f.upsampling
  fh = f.fh * f.upsampling
  if f.upsampling > 1
    k = 0
    while k < 3
      pl[k] = jxr_upsample(d, pl[k], f.upsampling, f.width, f.height)
      k += 1
    k = 0
    while k < ec.size
      ec[k] = jxr_upsample(d, ec[k], f.upsampling, f.width, f.height)
      k += 1
  jxf_noise(d, pl) if f.noise? && d.noise != nil
  # LF frames are stored pre-colour-transform for later frames
  if f.type == 1
    d.lf_frames[f.lf_level - 1] = [pl, ec]
    return canvas
  can_ref = !f.is_last && f.type != 1 && (f.duration == 0 || f.save_as_ref != 0)
  if can_ref && f.save_before_ct
    d.refs[f.save_as_ref] = jxr_frame_as_canvas(d, pl, ec)
  # colour transform
  jxr_color_transform(d, pl, ec)
  if f.type == 2
    d.refs[f.save_as_ref] = jxr_frame_as_canvas(d, pl, ec) if !f.save_before_ct
    return canvas
  out = jxr_blend(d, canvas, pl, ec)
  if can_ref && !f.save_before_ct
    d.refs[f.save_as_ref] = jxr_clone_canvas(out)
  out

# A reference frame image sized like the canvas: [planes…] at image size,
# with the frame placed at its origin (used for patches / blending sources).
-> jxr_frame_as_canvas(d, pl, ec)
  m = d.m
  f = d.f
  c = jxr_new_canvas(m)
  k = 0
  while k < 3
    jxr_place(c[k], m.width, m.height, pl[k][0], pl[k][1], pl[k][2], f.x0, f.y0)
    k += 1
  k = 0
  while k < ec.size
    jxr_place(c[3 + k], m.width, m.height, ec[k][0], ec[k][1], ec[k][2], f.x0, f.y0)
    k += 1
  c

-> jxr_place(dst, dw, dh, s, sw, sh, x0, y0) (f64[] i64 i64 f64[] i64 i64 i64 i64) i64
  y = 0 ## i64
  while y < sh
    ty = y + y0
    if ty >= 0 && ty < dh
      x = 0 ## i64
      while x < sw
        tx = x + x0
        if tx >= 0 && tx < dw
          dst[ty * dw + tx] = s[y * sw + x]
        x += 1
    y += 1
  0

-> jxr_color_transform(d, pl, ec)
  m = d.m
  f = d.f
  n = pl[0][1] * pl[0][2]
  lut = jxr_lut()
  if m.xyb
    mt = f64[9]
    sc = ~255.0 / m.intensity
    tm = ~0.0
    k = 0
    while k < 9
      mt[k] = m.opsin_inv[k] * sc
      k += 1
    if m.intensity > ~255.0
      # luminance up to intensity/255 times SDR white: compress
      mt2 = f64[9]
      k = 0
      while k < 9
        mt2[k] = m.opsin_inv[k] * (~255.0 / m.intensity) * (m.intensity / ~203.0)
        k += 1
      mt = mt2
      tm = ~203.0 / m.intensity
    bias = f64[3]
    cb = f64[3]
    k = 0
    while k < 3
      bias[k] = m.opsin_bias[k]
      cb[k] = Math.cbrt(m.opsin_bias[k])
      k += 1
    al = f64[1]
    unpre = 0
    ai = m.alpha_index
    if ai >= 0 && m.ec[ai][:premul] && ec[ai][1] == pl[0][1] && ec[ai][2] == pl[0][2]
      al = ec[ai][0]
      unpre = 1
    if m.gray?
      # grey XYB images: luminance from the opsin inverse, replicated
      jxr_xyb_to_srgb(pl[0][0], pl[1][0], pl[2][0], n, mt, bias, cb, lut, tm, al, unpre)
      jxr_gray_from_rgb(pl[0][0], pl[1][0], pl[2][0], n)
    else
      jxr_xyb_to_srgb(pl[0][0], pl[1][0], pl[2][0], n, mt, bias, cb, lut, tm, al, unpre)
    return 0
  if f.ycbcr
    jxr_ycbcr(pl[0][0], pl[1][0], pl[2][0], n)
  if m.tf != 13
    tmv = ~1.0
    tmv = ~10000.0 / ~203.0 if m.tf == 16
    g = ~1.0
    g = m.gamma / ~10000000.0 if m.tf == 0
    same = pl[0][0] == pl[1][0]
    jxr_tf_to_srgb(pl[0][0], n, m.tf, g, lut, tmv)
    if !same
      jxr_tf_to_srgb(pl[1][0], n, m.tf, g, lut, tmv)
      jxr_tf_to_srgb(pl[2][0], n, m.tf, g, lut, tmv)
  0

-> jxr_gray_from_rgb(r, g, b, n) (f64[] f64[] f64[] i64) i64
  i = 0 ## i64
  while i < n
    v = r[i]
    g[i] = v
    b[i] = v
    i += 1
  0

# Blend the frame onto the canvas (libjxl BlendingStage semantics); returns
# the new image-sized canvas.
-> jxr_blend(d, canvas, pl, ec)
  m = d.m
  f = d.f
  nec = ec.size
  W = 0
  out = []
  # background per channel
  k = 0
  while k < 3 + nec
    info = f.blend
    info = f.ec_blend[k - 3] if k >= 3
    ref = d.refs[info[3]]
    if ref == nil
      out.push(f64[m.width * m.height])
    else
      q = f64[m.width * m.height]
      jxr_copy_f(q, ref[k], m.width * m.height)
      out.push(q)
    k += 1
  # overlap of the frame with the image
  x0 = f.x0
  y0 = f.y0
  fw = pl[0][1]
  fh = pl[0][2]
  ox = x0
  ox = 0 if ox < 0
  oy = y0
  oy = 0 if oy < 0
  ex = x0 + fw
  ex = m.width if ex > m.width
  ey = y0 + fh
  ey = m.height if ey > m.height
  return out if ex <= ox || ey <= oy
  w = ex - ox
  h = ey - oy
  bgs = []
  fgs = []
  k = 0
  while k < 3 + nec
    b = f64[w * h]
    jxf_get_rect(b, out[k], m.width, ox, oy, w, h)
    bgs.push(b)
    g = f64[w * h]
    if k < 3
      jxf_get_rect(g, pl[k][0], pl[k][1], ox - x0, oy - y0, w, h)
    else
      jxf_get_rect(g, ec[k - 3][0], ec[k - 3][1], ox - x0, oy - y0, w, h)
    fgs.push(g)
    k += 1
  bmap = [1, 2, 4, 6, 3]
  infos = [[bmap[f.blend[0]], f.blend[1], f.blend[2]]]
  f.ec_blend.each ->(e)
    infos.push([bmap[e[0]], e[1], e[2]])
  res = jxf_perform_blending(bgs, fgs, infos, m, w * h)
  k = 0
  while k < 3 + nec
    jxf_put_rect(out[k], m.width, ox, oy, w, h, res[k])
    k += 1
  out

# ---------------------------------------------------------------- output

-> jxr_to_u8(v) (f64) i64
  k = (v * ~255.0 + ~0.5) ## i64
  k = 0 if v != v
  k = 0 if k < 0
  k = 255 if k > 255
  k

-> jxr_pack(r, g, b, a, out, n, has_a, premul) (f64[] f64[] f64[] f64[] u8[] i64 i64 i64) i64
  i = 0 ## i64
  while i < n
    av = ~1.0
    if has_a == 1
      av = a[i]
      av = ~0.0 if av < ~0.0
      av = ~1.0 if av > ~1.0
    rv = r[i]
    gv = g[i]
    bv = b[i]
    if premul == 1 && av > ~0.0
      rv = rv / av
      gv = gv / av
      bv = bv / av
    out[i * 4] = jxr_to_u8(rv)
    out[i * 4 + 1] = jxr_to_u8(gv)
    out[i * 4 + 2] = jxr_to_u8(bv)
    out[i * 4 + 3] = jxr_to_u8(av)
    i += 1
  0

-> jxr_orient(src, w, h, o, dst) (u8[] i64 i64 i64 u8[]) i64
  # o: 1..8 per EXIF; output dims are (h, w) for 5..8
  ow = w
  oh = h
  if o >= 5
    ow = h
    oh = w
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      tx = x
      ty = y
      if o == 2
        tx = w - 1 - x
      elsif o == 3
        tx = w - 1 - x
        ty = h - 1 - y
      elsif o == 4
        ty = h - 1 - y
      elsif o == 5
        tx = y
        ty = x
      elsif o == 6
        tx = h - 1 - y
        ty = x
      elsif o == 7
        tx = h - 1 - y
        ty = w - 1 - x
      elsif o == 8
        tx = y
        ty = w - 1 - x
      si = (y * w + x) * 4
      di = (ty * ow + tx) * 4
      dst[di] = src[si]
      dst[di + 1] = src[si + 1]
      dst[di + 2] = src[si + 2]
      dst[di + 3] = src[si + 3]
      x += 1
    y += 1
  0

-> jxr_to_bitmap(d, canvas)
  m = d.m
  w = m.width
  h = m.height
  n = w * h
  out = ByteArray.new(n * 4)
  ai = m.alpha_index
  a = f64[1]
  has_a = 0
  premul = 0
  if ai >= 0
    a = canvas[3 + ai]
    has_a = 1
    premul = 1 if m.ec[ai][:premul] && !m.xyb
  cr = canvas[0]
  cg = canvas[1]
  cb = canvas[2]
  si = 0
  while si < m.ec.size
    e = m.ec[si]
    if e[:type] == 2 && e[:spot] != nil
      if cr == canvas[0]
        cr = f64[n]
        cg = f64[n]
        cb = f64[n]
        jxr_copy_f(cr, canvas[0], n)
        jxr_copy_f(cg, canvas[1], n)
        jxr_copy_f(cb, canvas[2], n)
      sp = e[:spot]
      jxr_spot(cr, cg, cb, canvas[3 + si], n, sp[0], sp[1], sp[2], sp[3])
    si += 1
  jxr_pack(cr, cg, cb, a, out, n, has_a, premul)
  jxr_apply_icc(m, canvas, out, n) if !m.xyb && m.icc_prof != nil && img_colour?
  o = m.orientation
  if o == 1
    return Bitmap.new(w, h, out)
  dst = ByteArray.new(n * 4)
  jxr_orient(out, w, h, o, dst)
  return Bitmap.new(h, w, dst) if o >= 5
  Bitmap.new(w, h, dst)

# Colour-manage non-XYB pixels that carry an ICC profile (via core/codec/image/icc).
-> jxr_apply_icc(m, canvas, out, n)
  p = m.icc_prof
  if p.cmyk?
    ki = -1
    i = 0
    while i < m.ec.size
      ki = i if m.ec[i][:type] == 4
      i += 1
    return 0 if ki < 0
    ink = u8[n * 4]
    jxr_cmyk_ink(out, canvas[3 + ki], ink, n)
    alpha = u8[n]
    jxr_save_alpha(out, alpha, n)
    icc_apply_cmyk(p, ink, out, n)
    jxr_restore_alpha(out, alpha, n)
    return 0
  return 0 if icc_srgb?(p)
  icc_apply(p, out, n)
  0

-> jxr_cmyk_ink(px, k, ink, n) (u8[] f64[] u8[] i64) i64
  i = 0 ## i64
  while i < n
    ink[i * 4] = 255 - px[i * 4]
    ink[i * 4 + 1] = 255 - px[i * 4 + 1]
    ink[i * 4 + 2] = 255 - px[i * 4 + 2]
    ink[i * 4 + 3] = 255 - jxr_to_u8(k[i])
    i += 1
  0

-> jxr_save_alpha(px, a, n) (u8[] u8[] i64) i64
  i = 0 ## i64
  while i < n
    a[i] = px[i * 4 + 3]
    i += 1
  0

-> jxr_restore_alpha(px, a, n) (u8[] u8[] i64) i64
  i = 0 ## i64
  while i < n
    px[i * 4 + 3] = a[i]
    i += 1
  0

-> jxr_spot(r, g, b, v, n, sr, sg, sb, sol) (f64[] f64[] f64[] f64[] i64 f64 f64 f64 f64) i64
  i = 0 ## i64
  while i < n
    mix = sol * v[i]
    r[i] = mix * sr + (~1.0 - mix) * r[i]
    g[i] = mix * sg + (~1.0 - mix) * g[i]
    b[i] = mix * sb + (~1.0 - mix) * b[i]
    i += 1
  0
