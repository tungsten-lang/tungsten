# core/codec/image/jxr — JPEG XR / HD Photo decoder (ITU-T T.832 | ISO/IEC 29199-2).
#
# Accepts the HD Photo / JPEG XR container (a little-endian TIFF-like IFD
# with the 0xBC01 pixel format GUID, 0xBCC0/0xBCC1 image and 0xBCC2/0xBCC3
# planar-alpha offsets) and bare "WMPHOTO" codestreams. The codestream is
# parsed by jxr_mb / jxr_parse (spatial and frequency ordering, tiles, index
# tables, DC/LP/HP bands with FLEXBITS, all adaptive VLC / scan / prediction
# machinery) and rebuilt by jxr_xform (dequantisation, inverse PCT and the
# overlap filters). This file does the output formatting: chroma upsampling
# (the bilinear filter jxrlib uses), the YCoCg-R / YUVK colour transforms,
# the per-bit-depth bias / scale / clip step of T.832 clause 9.11, and the
# mapping of every output format (BD1/5/8/10/16/565, 16-bit signed fixed
# point, half and single float, RGBE, CMYK, N-channel) down to straight sRGB
# RGBA8. Linear (fixed / float) formats are clipped to [0, 1] and sRGB-encoded.

use core/codec/image
use jxr_xform

-> jxr_bytes(b)
  if b.is_a?(String)
    return ccall("w_string_bytes_view", b) ## u8[]
  if b.is_a?(Array)
    u = u8[b.size]
    i = 0
    while i < b.size
      u[i] = b[i]
      i += 1
    return u
  b

-> jxr_sniff?(b)
  n = b.size
  return false if n < 4
  return true if b[0] == 0x49 && b[1] == 0x49 && b[2] == 0xBC && (b[3] == 0x01 || b[3] == 0x00)
  n >= 8 && b[0] == 0x57 && b[1] == 0x4D && b[2] == 0x50 && b[3] == 0x48 && b[4] == 0x4F && b[5] == 0x54 && b[6] == 0x4F && b[7] == 0x00

-> jxr_u16(s, o)
  return 0 if o + 2 > s.size
  s[o] | (s[o + 1] << 8)

-> jxr_u32(s, o)
  return 0 if o + 4 > s.size
  s[o] | (s[o + 1] << 8) | (s[o + 2] << 16) | (s[o + 3] << 24)

# Container IFD → {image offset, size, alpha offset, alpha size, transform, guid last byte}
-> jxr_container(s)
  r = {img: -1, img_len: 0, alpha: -1, alpha_len: 0, xform: -1, pf: -1}
  ifd = jxr_u32(s, 4)
  jxr_fail("bad IFD offset") if ifd < 8 || ifd + 2 > s.size
  n = jxr_u16(s, ifd)
  i = 0
  while i < n
    e = ifd + 2 + i * 12
    break if e + 12 > s.size
    tag = jxr_u16(s, e)
    typ = jxr_u16(s, e + 2)
    cnt = jxr_u32(s, e + 4)
    val = jxr_u32(s, e + 8)
    val = jxr_u16(s, e + 8) if typ == 3 && cnt == 1
    val = s[e + 8] if typ == 1 && cnt == 1
    if tag == 0xBCC0
      r[:img] = val
    elsif tag == 0xBCC1
      r[:img_len] = val
    elsif tag == 0xBCC2
      r[:alpha] = val
    elsif tag == 0xBCC3
      r[:alpha_len] = val
    elsif tag == 0xBC02
      r[:xform] = val
    elsif tag == 0xBC01 && cnt == 16 && val + 16 <= s.size
      r[:pf] = s[val + 15]
    i += 1
  r

# Parse and reconstruct the codestream at byte offset off.
-> jxr_codestream(src, off)
  br = i64[4]
  br[0] = off * 8
  im = jxr_image_header(src, br)
  im.pl = jxr_plane_header(src, br, im, false)
  ntiles = im.tcols * im.trows
  im.pl.alloc(im.nmb, im.mbw, ntiles)
  if im.has_alpha?
    im.alpha = jxr_plane_header(src, br, im, true)
    im.alpha.alloc(im.nmb, im.mbw, ntiles)
  im.itab = jxr_index_table(src, br, im)
  if env("JXR_DEBUG") != nil
    p = im.pl
    << "jxr: [im.w]x[im.h] ocf=[im.ocf] bd=[im.bd] clr=[p.clr] nch=[p.nch] bands=[p.bands] scaled=[p.scaled] overlap=[im.overlap] freq=[im.freq?] tiles=[im.tcols]x[im.trows] hard=[im.no_tile_ovl] xform=[im.xform] alpha=[im.has_alpha?] f2=[im.f2] dcuni=[p.dc_uni] lpuni=[p.lp_uni] hpuni=[p.hp_uni] dcq=[p.dcq[0]],[p.dcq[1]] lpq=[p.lpq[0]] hpq=[p.hpq[0]] shift=[p.shift_bits] win=[im.wleft],[im.wtop] ext=[im.ew]x[im.eh]"
  sub = jxr_vlw(src, br)
  if sub > 0
    rd = 0
    if sub >= 4
      last = 0
      while last == 0 && rd < sub
        jxr_get(src, br, 16)
        jxr_get(src, br, 15)
        last = jxr_get(src, br, 1)
        rd += 4
    br[0] = br[0] + (sub - rd) * 8 if sub > rd
  br[1] = br[0] >> 3
  jxr_decode_tiles(src, br, im)
  im

# ---------------------------------------------------------------- output kernels

# jxrlib's chroma interpolation: samples sit on even positions, odd ones are
# the rounded mean of their neighbours, the last one repeats.
-> jxr_upsample_h(src, sw, h, dst) (i32[] i64 i64 i32[]) i64
  dw = sw * 2
  y = 0 ## i64
  while y < h
    s = y * sw
    d = y * dw
    x = 0 ## i64
    while x < sw
      dst[d + 2 * x] = src[s + x]
      x += 1
    x = 0
    while x < sw - 1
      dst[d + 2 * x + 1] = (src[s + x] + src[s + x + 1] + 1) >> 1
      x += 1
    dst[d + dw - 1] = src[s + sw - 1]
    y += 1
  0

-> jxr_upsample_v(src, w, sh, dst) (i32[] i64 i64 i32[]) i64
  y = 0 ## i64
  while y < sh
    s = y * w
    d = 2 * y * w
    x = 0 ## i64
    while x < w
      dst[d + x] = src[s + x]
      x += 1
    if y + 1 < sh
      x = 0
      while x < w
        dst[d + w + x] = (src[s + x] + src[s + w + x] + 1) >> 1
        x += 1
    else
      x = 0
      while x < w
        dst[d + w + x] = src[s + x]
        x += 1
    y += 1
  0

-> jxr_ycocg(y, u, v, n) (i32[] i32[] i32[] i64) i64
  i = 0 ## i64
  while i < n
    vy = y[i]
    vu = u[i]
    vv = v[i]
    g = vy - ((0 - vu) >> 1)
    r = g - vu - ((vv + 1) >> 1)
    y[i] = r
    u[i] = g
    v[i] = vv + r
    i += 1
  0

-> jxr_yuvk_cmyk(y, u, v, kk, n) (i32[] i32[] i32[] i32[] i64) i64
  i = 0 ## i64
  while i < n
    vy = y[i]
    vu = u[i]
    vv = v[i]
    k = kk[i] + (vy >> 1)
    m = k - vy - (vu >> 1)
    c = vu + m + (vv >> 1)
    y[i] = c
    u[i] = m
    v[i] = c - vv
    kk[i] = k
    i += 1
  0

-> jxr_shift_clip(p, n, add, scale, sb, lo, hi) (i32[] i64 i64 i64 i64 i64 i64) i64
  i = 0 ## i64
  while i < n
    v = ((p[i] + add) >> scale) << sb
    v = hi if v > hi
    v = lo if v < lo
    p[i] = v
    i += 1
  0

-> jxr_shift_only(p, n, add, scale) (i32[] i64 i64 i64) i64
  i = 0 ## i64
  while i < n
    p[i] = (p[i] + add) >> scale
    i += 1
  0

# Map clipped output integers of one channel to 8 bits, into dst (u8[], stride
# 4 per pixel at channel c) over the visible window. mode: 0 = 8-bit, 1 = n-bit
# integer (maxv), 2 = linear fixed point (frac bits in arg), 3 = half,
# 4 = float (arg = len_mantissa, arg2 = exp_bias), 5 = inverted 1-bit.
-> jxr_put8(p, ps, x0, y0, w, h, dst, c, mode, maxv, arg, arg2, lut, pm) (i32[] i64 i64 i64 i64 i64 u8[] i64 i64 i64 i64 i64 u8[] i64) i64
  one = 1 ## i64
  y = 0 ## i64
  while y < h
    s = (y0 + y) * ps + x0
    d = y * w * 4 + c
    x = 0 ## i64
    while x < w
      v = p[s + x]
      o = 0 ## i64
      if mode == 0
        o = v
      elsif mode == 1
        o = (v * 255 + (maxv >> 1)) / maxv
      elsif mode == 5
        o = 255 - v * 255
      else
        f = ~0.0
        if mode == 2
          f = (v ## f64) / (((one << arg) ## i64) ## f64)
        elsif mode == 3
          a = v
          a = 0 - a if a < 0
          a = 0x7FFF if a > 0x7FFF
          e = a >> 10
          m = a & 1023
          if e == 0
            f = (m ## f64) / ~16777216.0
          elsif e == 31
            f = ~1.0
          else
            f = (((m + 1024) ## f64) / ~1024.0) * Math.pow(~2.0, ((e - 15) ## f64))
          f = ~0.0 - f if v < 0
        else
          a = v
          a = 0 - a if a < 0
          ex = a >> arg
          m = a & ((one << arg) - 1)
          if ex == 0
            ex = 1
          else
            m = m | (one << arg)
          f = (m ## f64) * Math.pow(~2.0, ((ex - arg2 - arg) ## f64))
          f = ~0.0 - f if v < 0
        if c == 3
          f = ~0.0 if f < ~0.0
          f = ~1.0 if f > ~1.0
          o = ((f * ~255.0 + ~0.5) ## i64)
        else
          if pm == 1
            av = dst[d - c + 3]
            f = f * ~255.0 / (av ## f64) if av > 0
          f = ~0.0 if f < ~0.0
          f = ~1.0 if f > ~1.0
          o = lut[((f * ~16383.0 + ~0.5) ## i64)]
      o = 0 if o < 0
      o = 255 if o > 255
      dst[d] = o
      d += 4
      x += 1
    y += 1
  0

-> jxr_srgb_lut
  lut = u8[16384]
  i = 0
  while i < 16384
    l = (i ## f64) / ~16383.0
    s = ~0.0
    if l <= ~0.0031308
      s = l * ~12.92
    else
      s = ~1.055 * Math.pow(l, ~1.0 / ~2.4) - ~0.055
    lut[i] = ((s * ~255.0 + ~0.5) ## i64)
    i += 1
  lut

-> jxr_fill(dst, n, c, v) (u8[] i64 i64 i64) i64
  i = c
  while i < n * 4
    dst[i] = v
    i += 4
  0

-> jxr_copy_ch(dst, n, from, to) (u8[] i64 i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[i * 4 + to] = dst[i * 4 + from]
    i += 1
  0

-> jxr_cmyk_rgb(dst, kk, ks, x0, y0, w, h) (u8[] u8[] i64 i64 i64 i64 i64) i64
  i = 0 ## i64
  n = w * h
  while i < n
    k = 255 - kk[i]
    dst[i * 4] = ((255 - dst[i * 4]) * k + 127) / 255
    dst[i * 4 + 1] = ((255 - dst[i * 4 + 1]) * k + 127) / 255
    dst[i * 4 + 2] = ((255 - dst[i * 4 + 2]) * k + 127) / 255
    i += 1
  0

-> jxr_unpremultiply(dst, n) (u8[] i64) i64
  i = 0 ## i64
  while i < n
    a = dst[i * 4 + 3]
    if a > 0 && a < 255
      c = 0 ## i64
      while c < 3
        v = (dst[i * 4 + c] * 255 + (a >> 1)) / a
        v = 255 if v > 255
        dst[i * 4 + c] = v
        c += 1
    i += 1
  0

# Output parameters for a bit depth: [bias, round, lo, hi, mode, maxv, arg]
-> jxr_depth_params(bd, scaled, pl)
  rnd = 0
  rnd = 3 if scaled == 1
  if bd == 0 || bd == 15
    r4 = 0
    r4 = 4 if scaled == 1
    mode = 1
    mode = 5 if bd == 15
    return [0, r4, 0, 1, mode, 1, 0]
  return [128, rnd, 0, 255, 0, 255, 0] if bd == 1
  if bd == 2
    r4 = 0
    r4 = 4 if scaled == 1
    return [32768, r4, 0, 65535, 1, 65535, 0]
  return [0, rnd, -32768, 32767, 2, 0, 13] if bd == 3
  return [0, rnd, -2147483648, 2147483647, 2, 0, 24] if bd == 6
  return [0, rnd, 0, 0, 3, 0, 0] if bd == 4
  return [0, rnd, 0, 0, 4, 0, pl.len_mant] if bd == 7
  return [16, rnd, 0, 31, 1, 31, 0] if bd == 8
  return [512, rnd, 0, 1023, 1, 1023, 0] if bd == 9
  return [32, rnd, 0, 31, 1, 31, 0] if bd == 10
  jxr_fail("reserved bit depth")

# Scale one reconstructed channel to output integers (clause 9.11).
-> jxr_scale_channel(p, n, bd, pl, prm, cmyk_k, green565)
  scale = 0
  scale = 3 if pl.scaled == 1
  sb = pl.shift_bits
  bias = prm[0]
  rnd = prm[1]
  if bd == 4 || bd == 7
    jxr_shift_only(p, n, rnd, scale)
  elsif cmyk_k != 0
    add = ((bias >> (sb + 1)) << scale)
    add = 0 - add if cmyk_k == 2
    jxr_shift_clip(p, n, add + rnd, scale, sb, prm[2], prm[3])
  elsif bd == 10
    if green565
      jxr_shift_clip(p, n, (bias << scale) + rnd, scale, 0, 0, 63)
    else
      jxr_shift_clip(p, n, (bias << scale) + rnd, scale + 1, 0, 0, 31)
  else
    jxr_shift_clip(p, n, ((bias >> sb) << scale) + rnd, scale, sb, prm[2], prm[3])

-> jxr_channel_out(p, ps, im, dst, c, prm, pl, lut, pm, maxv)
  mode = prm[4]
  arg2 = 0
  arg2 = pl.exp_bias if mode == 4
  jxr_put8(p, ps, im.wleft, im.wtop, im.w, im.h, dst, c, mode, maxv, prm[6], arg2, lut, pm)

# Decode a separate (planar) alpha codestream to an 8-bit plane.
-> jxr_planar_alpha(src, off, im)
  a = jxr_codestream(src, off)
  jxr_fail("planar alpha size mismatch") if a.w != im.w || a.h != im.h
  r = jxr_reconstruct(a, a.pl)
  p = r[0][0]
  n = r[1][0] * r[2][0]
  prm = jxr_depth_params(a.bd, a.pl.scaled, a.pl)
  jxr_scale_channel(p, n, a.bd, a.pl, prm, 0, false)
  [p, r[1][0], a, prm]

# Orientation (the JPEG XR / HD Photo transformation codes): bit 2 rotates
# 90 degrees clockwise, then bit 0 flips vertically and bit 1 horizontally.
-> jxr_apply_xform(bm, xf)
  return bm if xf == 0
  w = bm.width
  h = bm.height
  out = jxr_xform_pixels(bm.rgba, w, h, xf)
  if (xf & 4) != 0
    return Bitmap.new(h, w, out)
  Bitmap.new(w, h, out)

-> jxr_xform_pixels(src, w, h, xf) (u8[] i64 i64 i64) u8[]
  rot = (xf & 4) != 0
  ow = w
  oh = h
  if rot
    ow = h
    oh = w
  out = u8[w * h * 4]
  oy = 0 ## i64
  while oy < oh
    ox = 0 ## i64
    while ox < ow
      px = ox
      py = oy
      px = ow - 1 - ox if (xf & 2) != 0
      py = oh - 1 - oy if (xf & 1) != 0
      sx = px
      sy = py
      if rot
        sx = py
        sy = h - 1 - px
      s = (sy * w + sx) * 4
      d = (oy * ow + ox) * 4
      out[d] = src[s]
      out[d + 1] = src[s + 1]
      out[d + 2] = src[s + 2]
      out[d + 3] = src[s + 3]
      ox += 1
    oy += 1
  out

-> jxr_decode(b)
  src = jxr_bytes(b)
  off = 0
  ct = nil
  if src[0] == 0x49
    ct = jxr_container(src)
    off = ct[:img]
    jxr_fail("no image data") if off < 0 || off >= src.size
  im = jxr_codestream(src, off)
  pl = im.pl
  r = jxr_reconstruct(im, pl)
  bufs = r[0]
  pw = r[1][0]
  ph = r[2][0]
  n = pw * ph
  clr = pl.clr
  ocf = im.ocf
  bd = im.bd
  yuv_out = ocf == 1 || ocf == 2 || ocf == 3
  if (clr == 1 || clr == 2) && ocf != 0
    ch = 1
    while ch < 3
      src_c = bufs[ch]
      cw = r[1][ch]
      chh = r[2][ch]
      if clr == 1
        tmp = i32[cw * chh * 2]
        jxr_upsample_v(src_c, cw, chh, tmp)
        full = i32[n]
        jxr_upsample_h(tmp, cw, chh * 2, full)
        bufs[ch] = full
      else
        full = i32[n]
        jxr_upsample_h(src_c, cw, chh, full)
        bufs[ch] = full
      ch += 1
  if (clr == 1 || clr == 2 || clr == 3) && !yuv_out && ocf != 0
    jxr_ycocg(bufs[0], bufs[1], bufs[2], n)
  is_cmyk = clr == 4 && ocf != 5
  jxr_yuvk_cmyk(bufs[0], bufs[1], bufs[2], bufs[3], n) if is_cmyk
  prm = jxr_depth_params(bd, pl.scaled, pl)
  nch = pl.nch
  nch = 1 if ocf == 0
  ch = 0
  while ch < nch && ch < 4
    kflag = 0
    if is_cmyk
      kflag = 1
      kflag = 2 if ch == 3
    jxr_scale_channel(bufs[ch], n, bd, pl, prm, kflag, ch == 1)
    ch += 1
  ow = im.w
  oh = im.h
  out = u8[ow * oh * 4]
  lut = jxr_srgb_lut
  has_alpha = im.alpha != nil || (ct != nil && ct[:alpha] > 0 && ct[:alpha] < src.size)
  premul = (im.f2 & 0x02) != 0
  if ct != nil
    pf = ct[:pf]
    premul = true if pf == 0x10 || pf == 0x17 || pf == 0x1A
  premul = false if !has_alpha
  # premultiplied linear formats are divided by alpha before sRGB encoding
  pm = 0
  pm = 1 if premul && prm[4] >= 2 && prm[4] <= 4
  # alpha: interleaved plane, planar codestream, or opaque
  if im.alpha != nil
    ra = jxr_reconstruct(im, im.alpha)
    ap = ra[0][0]
    # Interleaved alpha is formatted with the primary plane's scaling and
    # shift, rounded by half a step (+4) where the colour planes use +3
    # (jxrlib's outputMBRowAlpha).
    aprm = jxr_depth_params(bd, pl.scaled, pl)
    aprm[1] = 0
    aprm[1] = 4 if pl.scaled == 1
    jxr_scale_channel(ap, n, bd, pl, aprm, 0, false)
    jxr_channel_out(ap, pw, im, out, 3, aprm, pl, lut, 0, aprm[5])
  elsif ct != nil && ct[:alpha] > 0 && ct[:alpha] < src.size
    pa = jxr_planar_alpha(src, ct[:alpha], im)
    a_im = pa[2]
    jxr_put8(pa[0], pa[1], a_im.wleft, a_im.wtop, im.w, im.h, out, 3, pa[3][4], pa[3][5], pa[3][6], a_im.pl.exp_bias, lut, 0)
  else
    jxr_fill(out, ow * oh, 3, 255)
  if ocf == 0 || nch == 1
    jxr_channel_out(bufs[0], pw, im, out, 0, prm, pl, lut, pm, prm[5])
    jxr_copy_ch(out, ow * oh, 0, 1)
    jxr_copy_ch(out, ow * oh, 0, 2)
  elsif bd == 10
    swap = (im.f2 & 0x04) == 0
    ri = 0
    bi = 2
    if swap
      ri = 2
      bi = 0
    jxr_channel_out(bufs[0], pw, im, out, ri, prm, pl, lut, pm, 31)
    jxr_channel_out(bufs[1], pw, im, out, 1, prm, pl, lut, pm, 63)
    jxr_channel_out(bufs[2], pw, im, out, bi, prm, pl, lut, pm, 31)
  elsif clr == 4 || ocf == 4 || ocf == 5
    # CMYK (or CMYK direct): build C, M, Y into RGB slots, K separately
    jxr_channel_out(bufs[0], pw, im, out, 0, prm, pl, lut, pm, prm[5])
    jxr_channel_out(bufs[1], pw, im, out, 1, prm, pl, lut, pm, prm[5])
    jxr_channel_out(bufs[2], pw, im, out, 2, prm, pl, lut, pm, prm[5])
    kb = u8[ow * oh * 4]
    jxr_channel_out(bufs[3], pw, im, kb, 0, prm, pl, lut, 0, prm[5])
    kk = u8[ow * oh]
    i = 0
    while i < ow * oh
      kk[i] = kb[i * 4]
      i += 1
    jxr_cmyk_rgb(out, kk, ow, 0, 0, ow, oh)
  else
    swap = (bd == 8 || bd == 9) && (im.f2 & 0x04) == 0
    ri = 0
    bi = 2
    if swap
      ri = 2
      bi = 0
    jxr_channel_out(bufs[0], pw, im, out, ri, prm, pl, lut, pm, prm[5])
    jxr_channel_out(bufs[1], pw, im, out, 1, prm, pl, lut, pm, prm[5])
    jxr_channel_out(bufs[2], pw, im, out, bi, prm, pl, lut, pm, prm[5])
  jxr_unpremultiply(out, ow * oh) if premul && pm == 0
  bm = Bitmap.new(ow, oh, out)
  # jxrlib: the container's transformation tag wins; a container without one
  # means no transformation (Vista behaviour, the codestream's own field is
  # ignored); a bare codestream uses its SPATIAL_XFRM field.
  xf = im.xform
  if ct != nil
    xf = 0
    xf = ct[:xform] if ct[:xform] >= 0 && ct[:xform] < 8
  jxr_apply_xform(bm, xf)

img_register("jxr", ->(b) jxr_sniff?(b), ->(b) jxr_decode(b))
