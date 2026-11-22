# core/codec/image/pnm — Netpbm decoders: PBM/PGM/PPM (P1–P6, ASCII and binary, maxval
# up to 65535), PAM (P7: BLACKANDWHITE, GRAYSCALE, RGB and their _ALPHA
# variants, any depth 1–4) and PFM (Pf/PF float, either byte order; values
# are scene-linear and tone-mapped via core/codec/image/imgfloat). Only the first image
# of a multi-image file is decoded.
#
#   pnm_sniff?(bytes)   "P1".."P7", "Pf", "PF" followed by whitespace
#   pnm_decode(bytes)   → Bitmap

use core/codec/image
use imgfloat

-> pnm_sniff?(b)
  return false if b.size < 3 || b[0] != 80
  c = b[1]
  ok = (c >= 49 && c <= 55) || c == 102 || c == 70
  ok && pnm_ws?(b[2])

-> pnm_ws?(c) (i64) bool
  c == 32 || c == 9 || c == 10 || c == 13 || c == 11 || c == 12

# Header tokenizer state: [pos]. Skips whitespace and # comments.
-> pnm_skip(a, p) (u8[] i64) i64
  n = a.size
  while p < n
    c = a[p] ## i64
    if c == 35
      while p < n && a[p] != 10 && a[p] != 13
        p += 1
    elsif pnm_ws?(c)
      p += 1
    else
      return p
  p

# [value, next pos] of an unsigned decimal at p (after skipping), value -1 if none.
-> pnm_int(a, pos)
  p = pnm_skip(a, pos)
  v = -1
  while p < a.size && a[p] >= 48 && a[p] <= 57
    v = 0 if v < 0
    v = v * 10 + a[p] - 48
    p += 1
    img_fail("pnm: number too large") if v > 100000000
  [v, p]

-> pnm_token(a, pos)
  p = pnm_skip(a, pos)
  s = StringBuffer()
  while p < a.size && !pnm_ws?(a[p])
    s.append(a[p].chr)
    p += 1
  [s.to_s, p]

-> pnm_decode(data)
  a = img_bytes(data)
  img_fail("pnm: not a Netpbm image") if !pnm_sniff?(a)
  kind = a[1]
  return pnm_pfm(a) if kind == 102 || kind == 70
  w = 0
  h = 0
  maxv = 1
  depth = 1
  alpha = false
  p = 2
  if kind == 55
    tupl = ""
    while true
      t = pnm_token(a, p)
      p = t[1]
      k = t[0]
      break if k == "ENDHDR" || k == ""
      if k == "TUPLTYPE"
        t2 = pnm_token(a, p)
        p = t2[1]
        tupl = t2[0]
      else
        v = pnm_int(a, p)
        p = v[1]
        w = v[0] if k == "WIDTH"
        h = v[0] if k == "HEIGHT"
        depth = v[0] if k == "DEPTH"
        maxv = v[0] if k == "MAXVAL"
    # one newline after ENDHDR
    p += 1 if p < a.size && (a[p] == 10 || a[p] == 13)
    alpha = depth == 2 || depth == 4 || tupl.ends_with?("_ALPHA")
    img_fail("pnm: bad PAM depth") if depth < 1 || depth > 4
  else
    v = pnm_int(a, p)
    w = v[0]
    v = pnm_int(a, v[1])
    h = v[0]
    p = v[1]
    if kind != 49 && kind != 52
      v = pnm_int(a, p)
      maxv = v[0]
      p = v[1]
    depth = (kind == 51 || kind == 54) ? 3 : 1
    # exactly one whitespace byte before binary data
    p += 1 if kind >= 52 && p < a.size
  img_fail("pnm: bad maxval") if maxv < 1 || maxv > 65535
  img_check_size(w, h)
  bm = Bitmap.new(w, h)
  ascii = kind <= 51
  bits = kind == 49 || kind == 52
  # Gather samples into a u16 plane (bit images: 1 = black).
  ns = w * h * depth
  s = u16[ns]
  if bits && !ascii
    pnm_bits(a, p, s, w, h)
    maxv = 1
  elsif ascii
    pnm_ascii(a, p, s, ns, bits)
  else
    pnm_binary(a, p, s, ns, maxv > 255 ? 2 : 1)
  pnm_expand(s, w * h, depth, alpha, maxv, bits, bm.rgba)
  bm

-> pnm_bits(a, p, s, w, h) (u8[] i64 u16[] i64 i64) i64
  rb = (w + 7) / 8
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      o = p + y * rb + (x >> 3)
      v = 0 ## i64
      v = (a[o] >> (7 - (x & 7))) & 1 if o < a.size
      s[y * w + x] = v
      x += 1
    y += 1
  0

-> pnm_ascii(a, p, s, ns, bits) (u8[] i64 u16[] i64 bool) i64
  i = 0 ## i64
  n = a.size
  while i < ns && p < n
    c = a[p] ## i64
    if c >= 48 && c <= 57
      if bits
        s[i] = c - 48
        p += 1
      else
        v = 0 ## i64
        while p < n && a[p] >= 48 && a[p] <= 57
          v = v * 10 + a[p] - 48
          v = 65535 if v > 65535
          p += 1
        s[i] = v
      i += 1
    elsif c == 35
      while p < n && a[p] != 10
        p += 1
    else
      p += 1
  i

-> pnm_binary(a, p, s, ns, bps) (u8[] i64 u16[] i64 i64) i64
  i = 0 ## i64
  n = a.size
  while i < ns
    o = p + i * bps
    break if o + bps > n
    s[i] = bps == 2 ? (a[o] << 8) | a[o + 1] : a[o]
    i += 1
  i

-> pnm_sc(v, maxv, half) (i64 i64 i64) i64
  return 255 if v >= maxv
  (v * 255 + half) / maxv

-> pnm_expand(s, npx, depth, alpha, maxv, bits, out) (u16[] i64 i64 bool i64 bool u8[]) i64
  i = 0 ## i64
  half = maxv / 2
  while i < npx
    o = i * 4
    k = i * depth
    if bits
      v = s[k] == 1 ? 0 : 255
      out[o] = v
      out[o + 1] = v
      out[o + 2] = v
      out[o + 3] = 255
    else
      av = 255 ## i64
      s0 = s[k] ## i64
      if depth >= 3
        s1 = s[k + 1] ## i64
        s2 = s[k + 2] ## i64
        out[o] = pnm_sc(s0, maxv, half)
        out[o + 1] = pnm_sc(s1, maxv, half)
        out[o + 2] = pnm_sc(s2, maxv, half)
        if depth == 4 && alpha
          s3 = s[k + 3] ## i64
          av = pnm_sc(s3, maxv, half)
      else
        # PAM BLACKANDWHITE has maxval 1 with 1 = white (unlike PBM)
        g = pnm_sc(s0, maxv, half)
        out[o] = g
        out[o + 1] = g
        out[o + 2] = g
        if depth == 2 && alpha
          s1 = s[k + 1] ## i64
          av = pnm_sc(s1, maxv, half)
      out[o + 3] = av
    i += 1
  0

# PFM: "PF" (RGB) / "Pf" (grey), width height, scale (< 0: little-endian);
# rows bottom to top, binary32 samples.
-> pnm_pfm(a)
  ch = a[1] == 70 ? 3 : 1
  v = pnm_int(a, 2)
  w = v[0]
  v = pnm_int(a, v[1])
  h = v[0]
  t = pnm_token(a, v[1])
  le = t[0].starts_with?("-")
  p = t[1] + 1
  img_check_size(w, h)
  bm = Bitmap.new(w, h)
  tb = imgf_tables()
  pnm_pfm_px(a, p, w, h, ch, le, bm.rgba, tb[0], tb[1])
  bm

-> pnm_pfm_px(a, p, w, h, ch, le, out, p2, lut) (u8[] i64 i64 i64 i64 bool u8[] f64[] u8[]) i64
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      o = p + ((h - 1 - y) * w + x) * ch * 4
      r = ~0.0
      g = ~0.0
      b = ~0.0
      if o + ch * 4 <= a.size
        r = imgf_f32(le ? img_le32(a, o) : img_be32(a, o), p2)
        if ch == 3
          g = imgf_f32(le ? img_le32(a, o + 4) : img_be32(a, o + 4), p2)
          b = imgf_f32(le ? img_le32(a, o + 8) : img_be32(a, o + 8), p2)
        else
          g = r
          b = r
      imgf_px(out, (y * w + x) * 4, r, g, b, ~1.0, lut)
      x += 1
    y += 1
  0

img_register("pnm", ->(b) pnm_sniff?(b), ->(b) pnm_decode(b))
