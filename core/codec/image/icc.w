# core/codec/image/icc — just enough ICC colour management to bring decoded pixels to sRGB.
#
# Shared by the image decoders (JPEG APP2, PNG iCCP, WebP ICCP, AVIF/HEIF colr).
#
#   p = icc_parse(bytes, off, len)   bytes: u8[]; the profile is bytes[off, off+len).
#                                    → IccProfile, or nil when the profile is not one
#                                    this module can apply: only matrix/TRC profiles
#                                    are supported (RGB: rXYZ/gXYZ/bXYZ + rTRC/gTRC/bTRC;
#                                    GRAY: kTRC), with curv (identity, gamma or table)
#                                    or para (types 0-4) curves, plus LUT profiles
#                                    whose A2B0 is lut8 (mft1), lut16 (mft2) or lutAtoB
#                                    (mAB) with a Lab or XYZ PCS, for RGB, GRAY and
#                                    CMYK data. Other device spaces give nil.
#   icc_srgb?(p)                     true when p is close enough to sRGB (colorants
#                                    within 0.002, curves within 0.6/255) that the
#                                    conversion can be skipped
#   icc_apply(p, rgba, npix)         convert npix straight RGBA8 pixels in place from
#                                    p's space to sRGB (alpha untouched). For a GRAY
#                                    profile the pixels are expected to be grey (R=G=B)
#                                    and become grey sRGB.
#   icc_apply_cmyk(p, ink, out, npix)  CMYK ink (u8[] 4 per pixel, 0 = no ink, ICC
#                                    convention) → straight sRGB RGBA8 in out (alpha 255),
#                                    for a CMYK profile with a LUT A2B0 (p.cmyk? true)
#   p.cmyk?                          true for a CMYK LUT profile (use icc_apply_cmyk)
#   p.gray?                          true for a GRAY (kTRC) profile
#   p.name                           the profile description ('desc' ASCII part) or ""
#
# Method: each channel is linearised through a 256-entry f64 LUT built from its
# TRC, the linear RGB goes through one 3x3 matrix M = inverse(sRGB colorants) x
# (profile colorants) — both sets are the D50-adapted PCS colorants the ICC
# spec stores, so no explicit Bradford step is needed — and is re-encoded with
# the sRGB curve through a 16384-entry LUT. Values are clamped to [0, 1]
# (out-of-gamut colours clip, as with a relative-colorimetric intent).

use core/codec/image
use core/codec/cicp

+ IccProfile
  rw :gray, :mat, :lut_r, :lut_g, :lut_b, :name, :lut, :cmyk

  -> new
    @gray = false
    @mat = nil
    @lut_r = nil
    @lut_g = nil
    @lut_b = nil
    @name = ""
    @lut = nil
    @cmyk = false

  -> gray?
    @gray

  -> cmyk?
    @cmyk

# A sampled A2B0 pipeline. Every stage is pre-sampled: input curves at the 256
# 8-bit codes (as grid coordinates 0..1), output stages as 4096-entry tables.
#   intab f64[nin*256], grid i64[4], clut f64[prod(grid)*nout] (0..1),
#   post1 f64[nout*4096] (mft output tables / mAB M curves), mat f64[12] (mAB
#   matrix + offsets), post2 f64[nout*4096] (mAB B curves); flags i64[8]:
#   0 nin, 1 nout, 2 has post1, 3 has matrix, 4 has post2, 5 PCS (0 XYZ,
#   1 Lab v4, 2 Lab legacy 16-bit), 6 has clut
+ IccLut
  rw :intab, :grid, :clut, :post1, :mat, :post2, :flags

  -> new
    @intab = nil
    @grid = i64[4]
    @clut = f64[1]
    @post1 = f64[1]
    @mat = f64[12]
    @post2 = f64[1]
    @flags = i64[8]

# sRGB colorants as the sRGB IEC61966-2.1 profile stores them (D50 PCS).
ICC_SRGB_D50 = [~0.4360747, ~0.3850649, ~0.1430804, ~0.2225045, ~0.7168786, ~0.0606169, ~0.0139322, ~0.0971045, ~0.7141733]

ICC_STATE = [nil]

# The decoders' output space lives in core/codec/cicp (icc_set_target,
# icc_target, icc_note_converted). Display P3 colorants, D50-adapted (Apple's
# Display P3 profile):
ICC_P3_D50 = [~0.5151215, ~0.2919769, ~0.1571045, ~0.2411957, ~0.6922455, ~0.0665741, ~-0.0010529, ~0.0418854, ~0.7840729]
ICC_INV_FOR = [nil]

-> icc_target_d50
  ICC_TARGET[0] == "display_p3" ? ICC_P3_D50 : ICC_SRGB_D50


-> icc_s15(a, o)
  v = img_be32(a, o)
  v = v - 4294967296 if v >= 2147483648
  v / ~65536.0

-> icc_tag_sig(a, o)
  s = ""
  k = 0
  while k < 4
    s = s + a[o + k].chr
    k += 1
  s

-> icc_srgb_encode(l)
  return ~0.0 if l <= ~0.0
  return ~1.0 if l >= ~1.0
  return l * ~12.92 if l <= ~0.0031308
  ~1.055 * Math.pow(l, ~1.0 / ~2.4) - ~0.055

-> icc_srgb_decode(v)
  return v / ~12.92 if v <= ~0.04045
  Math.pow((v + ~0.055) / ~1.055, ~2.4)

# The 16384-entry linear → sRGB 8-bit table, built once.
-> icc_enc_lut
  if ICC_STATE[0] == nil
    t = u8[16384]
    i = 0
    while i < 16384
      v = (icc_srgb_encode(i / ~16383.0) * ~255.0 + ~0.5).to_i
      v = 255 if v > 255
      t[i] = v
      i += 1
    ICC_STATE[0] = t
  ICC_STATE[0]

# A curve tag at a[o] (curv or para) → f64[256] linear values for codes 0..255, or nil.
-> icc_curve(a, o, size)
  icc_curve_n(a, o, size, 256)

# Byte length of the curv/para element at a[o] (padded to 4), or 0.
-> icc_curve_len(a, o)
  typ = icc_tag_sig(a, o)
  len = 0
  if typ == "curv"
    len = 12 + img_be32(a, o + 8) * 2
  elsif typ == "para"
    np = [1, 3, 4, 5, 7]
    f = img_be16(a, o + 8)
    return 0 if f > 4
    len = 12 + np[f] * 4
  (len + 3) / 4 * 4

# The curve sampled at m evenly spaced inputs 0..1 → f64[m], or nil.
-> icc_curve_n(a, o, size, m)
  return nil if size < 12 || o + 12 > a.size
  typ = icc_tag_sig(a, o)
  lut = f64[m]
  if typ == "curv"
    n = img_be32(a, o + 8)
    return nil if size < 12 + n * 2 || o + 12 + n * 2 > a.size
    i = 0
    while i < m
      x = i / ((m - 1) * ~1.0)
      y = x
      if n == 1
        g = img_be16(a, o + 12) / ~256.0
        y = Math.pow(x, g)
      elsif n > 1
        p = x * (n - 1)
        k = p.to_i
        k = n - 2 if k > n - 2
        f = p - k
        y0 = img_be16(a, o + 12 + k * 2) / ~65535.0
        y1 = img_be16(a, o + 14 + k * 2) / ~65535.0
        y = y0 + (y1 - y0) * f
      lut[i] = y
      i += 1
    return lut
  if typ == "para"
    fnt = img_be16(a, o + 8)
    np = [1, 3, 4, 5, 7]
    return nil if fnt > 4 || size < 12 + np[fnt] * 4
    g = icc_s15(a, o + 12)
    pa = ~1.0
    pb = ~0.0
    pc = ~0.0
    pd = ~0.0
    pe = ~0.0
    pf = ~0.0
    if fnt >= 1
      pa = icc_s15(a, o + 16)
      pb = icc_s15(a, o + 20)
    pc = icc_s15(a, o + 24) if fnt >= 2
    pd = icc_s15(a, o + 28) if fnt >= 3
    if fnt == 4
      pe = icc_s15(a, o + 32)
      pf = icc_s15(a, o + 36)
    i = 0
    while i < m
      x = i / ((m - 1) * ~1.0)
      y = ~0.0
      if fnt == 0
        y = Math.pow(x, g)
      elsif fnt == 1 || fnt == 2
        lim = pa == ~0.0 ? ~0.0 : (~0.0 - pb) / pa
        if x >= lim
          t = pa * x + pb
          y = t > ~0.0 ? Math.pow(t, g) : ~0.0
        y = y + pc if fnt == 2
        y = pc if fnt == 2 && x < lim
      else
        if x >= pd
          t = pa * x + pb
          y = t > ~0.0 ? Math.pow(t, g) : ~0.0
          y = y + pe if fnt == 4
        else
          y = pc * x
          y = y + pf if fnt == 4
      y = ~0.0 if y < ~0.0
      y = ~1.0 if y > ~1.0
      lut[i] = y
      i += 1
    return lut
  nil

-> icc_parse(a, off, len)
  begin
    return icc_parse_raw(a, off, len)
  rescue e
    return nil

-> icc_parse_raw(a, off, len)
  return nil if len < 132 || off + len > a.size
  space = icc_tag_sig(a, off + 16)
  pcs = icc_tag_sig(a, off + 20)
  return nil if pcs != "XYZ " && pcs != "Lab "
  return nil if space != "RGB " && space != "GRAY" && space != "CMYK"
  n = img_be32(a, off + 128)
  return nil if n > 200 || 132 + n * 12 > len
  tags = {}
  i = 0
  while i < n
    e = off + 132 + i * 12
    to = img_be32(a, e + 4)
    ts = img_be32(a, e + 8)
    if to + ts <= len
      tags[icc_tag_sig(a, e)] = [off + to, ts]
    i += 1
  p = IccProfile.new
  d = tags["desc"]
  if d != nil && icc_tag_sig(a, d[0]) == "desc"
    nl = img_be32(a, d[0] + 8)
    s = ""
    k = 0
    while k < nl - 1 && k < 64 && d[0] + 12 + k < a.size
      s = s + a[d[0] + 12 + k].chr
      k += 1
    p.name = s
  # matrix/TRC first (exact and cheap); otherwise a LUT A2B0
  if space == "CMYK" || pcs == "Lab " || (space == "GRAY" && tags["kTRC"] == nil) || (space == "RGB " && tags["rTRC"] == nil)
    t = tags["A2B0"]
    return nil if t == nil
    nin = space == "CMYK" ? 4 : (space == "GRAY" ? 1 : 3)
    lut = icc_parse_lut(a, t[0], t[1], nin, pcs == "Lab ")
    return nil if lut == nil
    p.lut = lut
    p.cmyk = space == "CMYK"
    p.gray = space == "GRAY"
    return p
  if space == "GRAY"
    k = tags["kTRC"]
    return nil if k == nil
    lut = icc_curve(a, k[0], k[1])
    return nil if lut == nil
    p.gray = true
    p.lut_r = lut
    p.lut_g = lut
    p.lut_b = lut
    m = f64[9]
    m[0] = ~1.0
    m[4] = ~1.0
    m[8] = ~1.0
    p.mat = m
    return p
  names = ["rXYZ", "gXYZ", "bXYZ", "rTRC", "gTRC", "bTRC"]
  ok = true
  names.each ->(nm)
    t = tags[nm]
    ok = false if t == nil
  return nil if !ok
  # colorant columns
  src = [~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0, ~0.0]
  c = 0
  while c < 3
    t = tags[names[c]]
    return nil if t[1] < 20 || icc_tag_sig(a, t[0]) != "XYZ "
    src[c] = icc_s15(a, t[0] + 8)
    src[3 + c] = icc_s15(a, t[0] + 12)
    src[6 + c] = icc_s15(a, t[0] + 16)
    c += 1
  inv = icc_inv3(icc_target_d50())
  return nil if inv == nil
  m = f64[9]
  r = 0
  while r < 3
    c = 0
    while c < 3
      s = ~0.0
      k = 0
      while k < 3
        s = s + inv[r * 3 + k] * src[k * 3 + c]
        k += 1
      m[r * 3 + c] = s
      c += 1
    r += 1
  p.mat = m
  p.lut_r = icc_curve(a, tags["rTRC"][0], tags["rTRC"][1])
  p.lut_g = icc_curve(a, tags["gTRC"][0], tags["gTRC"][1])
  p.lut_b = icc_curve(a, tags["bTRC"][0], tags["bTRC"][1])
  return nil if p.lut_r == nil || p.lut_g == nil || p.lut_b == nil
  p

-> icc_inv3(m)
  a = m[0]
  b = m[1]
  c = m[2]
  d = m[3]
  e = m[4]
  f = m[5]
  g = m[6]
  h = m[7]
  i = m[8]
  det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
  return nil if det.abs < ~0.000000001
  [(e * i - f * h) / det, (c * h - b * i) / det, (b * f - c * e) / det,
   (f * g - d * i) / det, (a * i - c * g) / det, (c * d - a * f) / det,
   (d * h - e * g) / det, (b * g - a * h) / det, (a * e - b * d) / det]

-> icc_srgb?(p)
  return false if p == nil || p.lut != nil
  m = p.mat
  k = 0
  while k < 9
    want = (k == 0 || k == 4 || k == 8) ? ~1.0 : ~0.0
    return false if (m[k] - want).abs > ~0.002
    k += 1
  luts = [p.lut_r, p.lut_g, p.lut_b]
  ok = true
  luts.each ->(l)
    i = 0
    while i < 256
      ok = false if (icc_srgb_decode(i / ~255.0) - l[i]).abs * ~255.0 > ~0.6 && (icc_srgb_encode(l[i]) * ~255.0 - i).abs > ~0.6
      i += 1
  ok

-> icc_apply(p, rgba, npix)
  return nil if p == nil || p.cmyk
  icc_note_converted()
  if p.lut != nil
    l = p.lut
    icc_lut_px(rgba, 4, rgba, npix, l.intab, l.grid, l.clut, l.post1, l.mat, l.post2, l.flags, icc_srgb_inv(), icc_enc_lut())
    return nil
  icc_apply_px(rgba, npix, p.lut_r, p.lut_g, p.lut_b, p.mat, icc_enc_lut())
  nil

-> icc_apply_px(px, n, lr, lg, lb, m, enc) (u8[] i64 f64[] f64[] f64[] f64[] u8[]) i64
  m0 = m[0]
  m1 = m[1]
  m2 = m[2]
  m3 = m[3]
  m4 = m[4]
  m5 = m[5]
  m6 = m[6]
  m7 = m[7]
  m8 = m[8]
  i = 0 ## i64
  o = 0 ## i64
  while i < n
    r = lr[px[o]]
    g = lg[px[o + 1]]
    b = lb[px[o + 2]]
    x = m0 * r + m1 * g + m2 * b
    y = m3 * r + m4 * g + m5 * b
    z = m6 * r + m7 * g + m8 * b
    xi = (x * ~16383.0 + ~0.5) ## i64
    yi = (y * ~16383.0 + ~0.5) ## i64
    zi = (z * ~16383.0 + ~0.5) ## i64
    xi = 0 if xi < 0
    yi = 0 if yi < 0
    zi = 0 if zi < 0
    xi = 16383 if xi > 16383
    yi = 16383 if yi > 16383
    zi = 16383 if zi > 16383
    px[o] = enc[xi]
    px[o + 1] = enc[yi]
    px[o + 2] = enc[zi]
    i += 1
    o += 4
  0

# ---------------------------------------------------------------------------
# LUT (A2B0) profiles
# ---------------------------------------------------------------------------

# Sample a table of n entries (u8 when w == 1, u16 when 2) at a[o] at the 256 input codes.
-> icc_tab256(a, o, n, w, dst, doff)
  i = 0
  while i < 256
    p = i * (n - 1) / ~255.0
    k = p.to_i
    k = n - 2 if k > n - 2
    k = 0 if k < 0
    f = p - k
    y0 = ~0.0
    y1 = ~0.0
    if w == 1
      y0 = a[o + k] / ~255.0
      y1 = a[o + k + (n > 1 ? 1 : 0)] / ~255.0
    else
      y0 = img_be16(a, o + k * 2) / ~65535.0
      y1 = img_be16(a, o + (k + (n > 1 ? 1 : 0)) * 2) / ~65535.0
    dst[doff + i] = y0 + (y1 - y0) * f
    i += 1
  nil

# Sample a table of n entries at 4096 evenly spaced inputs.
-> icc_tab4096(a, o, n, w, dst, doff)
  i = 0
  while i < 4096
    p = i * (n - 1) / ~4095.0
    k = p.to_i
    k = n - 2 if k > n - 2
    k = 0 if k < 0
    f = p - k
    y0 = ~0.0
    y1 = ~0.0
    if w == 1
      y0 = a[o + k] / ~255.0
      y1 = a[o + k + (n > 1 ? 1 : 0)] / ~255.0
    else
      y0 = img_be16(a, o + k * 2) / ~65535.0
      y1 = img_be16(a, o + (k + (n > 1 ? 1 : 0)) * 2) / ~65535.0
    dst[doff + i] = y0 + (y1 - y0) * f
    i += 1
  nil

-> icc_parse_lut(a, o, size, nin, lab)
  typ = icc_tag_sig(a, o)
  lut = IccLut.new
  fl = lut.flags
  return nil if size < 32
  if typ == "mft1" || typ == "mft2"
    w = typ == "mft1" ? 1 : 2
    ni = a[o + 8]
    no = a[o + 9]
    g = a[o + 10]
    return nil if ni != nin || no != 3 || g < 2
    n_in = 256
    n_out = 256
    q = o + 48
    if w == 2
      n_in = img_be16(a, o + 48)
      n_out = img_be16(a, o + 50)
      q = o + 52
    return nil if n_in < 2 || n_out < 2
    cells = 1
    k = 0
    while k < ni
      cells = cells * g
      k += 1
    need = 48 + (w == 2 ? 4 : 0) + (ni * n_in + cells * no + no * n_out) * w
    return nil if need > size
    intab = f64[ni * 256]
    k = 0
    while k < ni
      icc_tab256(a, q + k * n_in * w, n_in, w, intab, k * 256)
      k += 1
    q += ni * n_in * w
    lut.intab = intab
    k = 0
    while k < 4
      lut.grid[k] = k < ni ? g : 1
      k += 1
    clut = f64[cells * no]
    k = 0
    while k < cells * no
      clut[k] = w == 1 ? a[q + k] / ~255.0 : img_be16(a, q + k * 2) / ~65535.0
      k += 1
    lut.clut = clut
    q += cells * no * w
    post = f64[no * 4096]
    k = 0
    while k < no
      icc_tab4096(a, q + k * n_out * w, n_out, w, post, k * 4096)
      k += 1
    lut.post1 = post
    fl[0] = ni
    fl[1] = no
    fl[2] = 1
    fl[5] = lab ? (w == 2 ? 2 : 1) : 0
    fl[6] = 1
    return lut
  if typ == "mAB "
    ni = a[o + 8]
    no = a[o + 9]
    return nil if ni != nin || no != 3
    ob = img_be32(a, o + 12)
    om = img_be32(a, o + 16)
    omc = img_be32(a, o + 20)
    oc = img_be32(a, o + 24)
    oa = img_be32(a, o + 28)
    return nil if ob == 0
    # A curves → intab
    intab = f64[ni * 256]
    if oa != 0
      q = o + oa
      k = 0
      while k < ni
        c = icc_curve_n(a, q, size - (q - o), 256)
        return nil if c == nil
        j = 0
        while j < 256
          intab[k * 256 + j] = c[j]
          j += 1
        q += icc_curve_len(a, q)
        k += 1
    else
      k = 0
      while k < ni * 256
        intab[k] = (k % 256) / ~255.0
        k += 1
    lut.intab = intab
    if oc != 0
      q = o + oc
      cells = 1
      k = 0
      while k < 4
        gk = k < ni ? a[q + k] : 1
        return nil if k < ni && gk < 2
        lut.grid[k] = gk
        cells = cells * gk
        k += 1
      prec = a[q + 16]
      return nil if prec != 1 && prec != 2
      return nil if oc + 20 + cells * no * prec > size
      clut = f64[cells * no]
      d = q + 20
      k = 0
      while k < cells * no
        clut[k] = prec == 1 ? a[d + k] / ~255.0 : img_be16(a, d + k * 2) / ~65535.0
        k += 1
      lut.clut = clut
      fl[6] = 1
    else
      return nil if ni != no
    if om != 0 && omc != 0
      post = f64[no * 4096]
      q = o + omc
      k = 0
      while k < no
        c = icc_curve_n(a, q, size - (q - o), 4096)
        return nil if c == nil
        j = 0
        while j < 4096
          post[k * 4096 + j] = c[j]
          j += 1
        q += icc_curve_len(a, q)
        k += 1
      lut.post1 = post
      fl[2] = 1
      k = 0
      while k < 12
        lut.mat[k] = icc_s15(a, o + om + k * 4)
        k += 1
      fl[3] = 1
    post = f64[no * 4096]
    q = o + ob
    k = 0
    while k < no
      c = icc_curve_n(a, q, size - (q - o), 4096)
      return nil if c == nil
      j = 0
      while j < 4096
        post[k * 4096 + j] = c[j]
        j += 1
      q += icc_curve_len(a, q)
      k += 1
    lut.post2 = post
    fl[4] = 1
    fl[0] = ni
    fl[1] = no
    fl[5] = lab ? 1 : 0
    return lut
  nil

-> icc_apply_cmyk(p, ink, out, npix)
  icc_note_converted()
  l = p.lut
  icc_lut_px(ink, 4, out, npix, l.intab, l.grid, l.clut, l.post1, l.mat, l.post2, l.flags, icc_srgb_inv(), icc_enc_lut())
  nil

# Inverse of the sRGB D50 colorant matrix, as f64[9].
-> icc_srgb_inv
  if ICC_STATE.size >= 2 && ICC_INV_FOR[0] != icc_target()
    ICC_STATE.pop
  if ICC_STATE.size < 2
    ICC_INV_FOR[0] = icc_target()
    inv = icc_inv3(icc_target_d50())
    m = f64[9]
    k = 0
    while k < 9
      m[k] = inv[k]
      k += 1
    ICC_STATE.push(m)
  ICC_STATE[1]

-> icc_tab_at(t, base, xin) (f64[] i64 f64) f64
  # (a local copy: reassigning an f64 parameter miscompiles, see the report)
  x = xin
  x = ~0.0 if x < ~0.0
  x = ~1.0 if x > ~1.0
  pz = x * ~4095.0
  k = pz.to_i
  k = 4094 if k > 4094
  f = pz - k
  t[base + k] + (t[base + k + 1] - t[base + k]) * f

-> icc_lab_f(t) (f64) f64
  return t * t * t if t > ~0.20689655172413793
  ~0.12841854934601665 * (t - ~0.13793103448275862)

# src: bpp bytes per pixel (first nin used); out: RGBA8.
-> icc_lut_px(src, bpp, out, n, intab, grid, clut, post1, mat, post2, fl, inv, enc) (u8[] i64 u8[] i64 f64[] i64[] f64[] f64[] f64[] f64[] i64[] f64[] u8[]) i64
  nin = fl[0]
  nout = fl[1]
  st = i64[4]
  st[nin - 1] = nout
  k = nin - 2 ## i64
  while k >= 0
    st[k] = st[k + 1] * grid[k + 1]
    k -= 1
  pos = i64[4]
  fr = f64[4]
  ov = f64[3]
  ncorner = 1 << nin
  i = 0 ## i64
  last = -1 ## i64
  r8 = 0 ## i64
  g8 = 0 ## i64
  b8 = 0 ## i64
  while i < n
    so = i * bpp
    key = 0 ## i64
    k = 0
    while k < nin
      key = (key << 8) | src[so + k]
      k += 1
    if key != last
      last = key
      base = 0 ## i64
      k = 0
      while k < nin
        x = intab[k * 256 + src[so + k]]
        if fl[6] == 1
          gp = x * (grid[k] - 1)
          gi = gp.to_i
          gi = 0 if gi < 0
          gi = grid[k] - 2 if gi > grid[k] - 2
          pos[k] = gi
          fr[k] = gp - gi
          base += gi * st[k]
        else
          fr[k] = x
        k += 1
      if fl[6] == 1
        ov[0] = ~0.0
        ov[1] = ~0.0
        ov[2] = ~0.0
        c = 0 ## i64
        while c < ncorner
          wgt = ~1.0
          idx = base
          k = 0
          while k < nin
            if ((c >> (nin - 1 - k)) & 1) == 1
              wgt = wgt * fr[k]
              idx += st[k]
            else
              wgt = wgt * (~1.0 - fr[k])
            k += 1
          if wgt != ~0.0
            ov[0] = ov[0] + wgt * clut[idx]
            ov[1] = ov[1] + wgt * clut[idx + 1]
            ov[2] = ov[2] + wgt * clut[idx + 2]
          c += 1
      else
        ov[0] = fr[0]
        ov[1] = fr[nin > 1 ? 1 : 0]
        ov[2] = fr[nin > 2 ? 2 : 0]
      v0 = ov[0]
      v1 = ov[1]
      v2 = ov[2]
      if fl[2] == 1
        v0 = icc_tab_at(post1, 0, v0)
        v1 = icc_tab_at(post1, 4096, v1)
        v2 = icc_tab_at(post1, 8192, v2)
      if fl[3] == 1
        a0 = mat[0] * v0 + mat[1] * v1 + mat[2] * v2 + mat[9]
        a1 = mat[3] * v0 + mat[4] * v1 + mat[5] * v2 + mat[10]
        a2 = mat[6] * v0 + mat[7] * v1 + mat[8] * v2 + mat[11]
        v0 = a0
        v1 = a1
        v2 = a2
      if fl[4] == 1
        v0 = icc_tab_at(post2, 0, v0)
        v1 = icc_tab_at(post2, 4096, v1)
        v2 = icc_tab_at(post2, 8192, v2)
      xx = ~0.0
      yy = ~0.0
      zz = ~0.0
      if fl[5] == 0
        xx = v0 * ~1.999969482421875
        yy = v1 * ~1.999969482421875
        zz = v2 * ~1.999969482421875
      else
        sc = fl[5] == 2 ? ~1.003921568627451 : ~1.0
        ll = v0 * sc * ~100.0
        aa = v1 * sc * ~255.0 - ~128.0
        bb = v2 * sc * ~255.0 - ~128.0
        fy = (ll + ~16.0) / ~116.0
        xx = ~0.9642 * icc_lab_f(fy + aa / ~500.0)
        yy = icc_lab_f(fy)
        zz = ~0.8249 * icc_lab_f(fy - bb / ~200.0)
      rl = inv[0] * xx + inv[1] * yy + inv[2] * zz
      gl = inv[3] * xx + inv[4] * yy + inv[5] * zz
      bl = inv[6] * xx + inv[7] * yy + inv[8] * zz
      ri = (rl * ~16383.0 + ~0.5) ## i64
      gi2 = (gl * ~16383.0 + ~0.5) ## i64
      bi = (bl * ~16383.0 + ~0.5) ## i64
      ri = 0 if ri < 0
      gi2 = 0 if gi2 < 0
      bi = 0 if bi < 0
      ri = 16383 if ri > 16383
      gi2 = 16383 if gi2 > 16383
      bi = 16383 if bi > 16383
      r8 = enc[ri]
      g8 = enc[gi2]
      b8 = enc[bi]
    o = i * 4
    out[o] = r8
    out[o + 1] = g8
    out[o + 2] = b8
    out[o + 3] = 255 if nin == 4
    i += 1
  0
