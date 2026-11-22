# core/codec/image/gif — GIF87a/GIF89a decoder in Tungsten, with animation.
#
# LZW (variable code size, clear/end codes, deferred clear), global/local
# colour tables, interlacing, Graphic Control Extension (transparency, delay,
# disposal: none / background / previous), NETSCAPE2.0 / ANIMEXTS1.0 loop
# counts. Frames are composited onto a transparent canvas the size of the
# logical screen, as browsers do (the background colour index is ignored).
# Truncated data decodes as far as it goes.
#
#   gif_sniff?(bytes)   "GIF87a" / "GIF89a"
#   gif_decode(bytes)   → Bitmap; animations fill frames/loop_count

# Stop compositing more frames once they would hold this many bytes.

use core/codec/image

GIF_MAX_ANIM_BYTES = 400000000

-> gif_sniff?(b)
  b.size >= 6 && b[0] == 71 && b[1] == 73 && b[2] == 70 && b[3] == 56 && (b[4] == 55 || b[4] == 57) && b[5] == 97

# A colour table at a[off] of n entries → u8[1024] RGBA (alpha 255).
-> gif_table(a, off, n) (u8[] i64 i64) u8[]
  t = u8[1024]
  i = 0 ## i64
  while i < 256
    if i < n && off + i * 3 + 2 < a.size
      t[i * 4] = a[off + i * 3]
      t[i * 4 + 1] = a[off + i * 3 + 1]
      t[i * 4 + 2] = a[off + i * 3 + 2]
    t[i * 4 + 3] = 255
    i += 1
  t

-> gif_decode(data)
  a = img_bytes(data)
  img_fail("gif: not a GIF") if !gif_sniff?(a)
  n = a.size
  img_fail("gif: truncated header") if n < 13
  sw = img_le16(a, 6)
  sh = img_le16(a, 8)
  flags = a[10]
  pos = 13
  gct = nil
  if (flags & 0x80) != 0
    gn = (1 ## i64) << ((flags & 7) + 1)
    gct = gif_table(a, pos, gn)
    pos += gn * 3
  # GCE state for the next image
  trans = -1
  delay = 0
  dispose = 0
  gce = false
  loops = nil
  frames = []        # [x, y, w, h, indices u8[], table, trans, delay, dispose]
  while pos < n
    b = a[pos]
    if b == 0x3B
      break
    elsif b == 0x21
      break if pos + 2 > n
      label = a[pos + 1]
      p = pos + 2
      if label == 0xF9 && p + 5 < n && a[p] >= 4
        f = a[p + 1]
        dispose = (f >> 2) & 7
        delay = img_le16(a, p + 2) * 10
        trans = (f & 1) != 0 ? a[p + 4] : -1
        gce = true
      elsif label == 0xFF && p + 12 < n && a[p] == 11
        id = gif_str(a, p + 1, 11)
        if (id == "NETSCAPE2.0" || id == "ANIMEXTS1.0") && p + 16 < n && a[p + 12] >= 3 && a[p + 13] == 1
          lc = img_le16(a, p + 14)
          loops = lc == 0 ? 0 : lc + 1
      pos = gif_skip_blocks(a, p)
    elsif b == 0x2C
      break if pos + 10 > n
      fx = img_le16(a, pos + 1)
      fy = img_le16(a, pos + 3)
      fw = img_le16(a, pos + 5)
      fh = img_le16(a, pos + 7)
      ff = a[pos + 9]
      pos += 10
      table = gct
      if (ff & 0x80) != 0
        ln = (1 ## i64) << ((ff & 7) + 1)
        table = gif_table(a, pos, ln)
        pos += ln * 3
      break if pos >= n
      mcs = a[pos]
      pos += 1
      stop = gif_skip_blocks(a, pos)
      if fw > 0 && fh > 0 && fw * fh <= IMG_MAX_PIXELS
        lz = gif_gather(a, pos, stop)
        idx = u8[fw * fh]
        got = 0
        if mcs >= 1 && mcs <= 11
          got = gif_lzw(lz, mcs, idx, fw * fh)
        valid = i32[fh]
        gif_valid_rows(valid, fw, fh, got)
        if (ff & 0x40) != 0
          idx = gif_deinterlace(idx, fw, fh, valid)
        table = gif_table(a, 0, 0) if table == nil
        frames.push([fx, fy, fw, fh, idx, table, trans, delay, dispose, valid, gce])
      pos = stop
      trans = -1
      delay = 0
      dispose = 0
      gce = false
    else
      # Unknown byte: browsers stop here and show what they have.
      break
  if frames.size == 0
    # No (non-empty) image: a transparent logical screen.
    img_check_size(sw, sh)
    return Bitmap.new(sw, sh)
  if sw == 0 || sh == 0
    frames.each ->(f)
      sw = f[0] + f[2] if f[0] + f[2] > sw
      sh = f[1] + f[3] if f[1] + f[3] > sh
  img_check_size(sw, sh)
  canvas = u8[sw * sh * 4]
  out = []
  bytes = 0
  i = 0
  while i < frames.size && bytes <= GIF_MAX_ANIM_BYTES
    f = frames[i]
    saved = nil
    saved = img_copy(canvas) if f[8] == 3
    gif_draw(canvas, sw, sh, f[4], f[0], f[1], f[2], f[3], f[5], f[6], f[9])
    if i > 0 && !f[10] && loops == nil
      # Extra images with no Graphic Control Extension add to the current
      # frame (tiled or high-colour stills), they don't start a new one.
      out[out.size - 1][0] = Bitmap.new(sw, sh, img_copy(canvas))
    else
      out.push([Bitmap.new(sw, sh, img_copy(canvas)), f[7]])
      bytes += sw * sh * 4
    if f[8] == 2
      img_fill_rect(canvas, sw, sh, f[0], f[1], f[2], f[3], 0)
    elsif f[8] == 3
      canvas = saved
    i += 1
  res = Bitmap.new(sw, sh, out[0][0].rgba)
  if out.size > 1
    res.frames = out
    res.loop_count = loops == nil ? 1 : loops
  res

-> gif_str(a, off, len)
  s = ""
  i = 0
  while i < len
    s = s + a[off + i].chr
    i += 1
  s

# Position after the data sub-blocks starting at a[p] (and their terminator).
-> gif_skip_blocks(a, p) (u8[] i64) i64
  n = a.size
  while p < n
    k = a[p]
    return p + 1 if k == 0
    p += k + 1
  n

# Concatenate the sub-blocks in a[p, stop) into one u8[].
-> gif_gather(a, p, stop) (u8[] i64 i64) u8[]
  total = 0 ## i64
  q = p
  while q < stop && q < a.size
    k = a[q]
    break if k == 0
    total += k
    q += k + 1
  out = u8[total]
  o = 0 ## i64
  q = p
  while q < stop && q < a.size
    k = a[q]
    break if k == 0
    j = 0 ## i64
    while j < k && q + 1 + j < a.size
      out[o] = a[q + 1 + j]
      o += 1
      j += 1
    q += k + 1
  out

# LZW-decode src into out[0...count]; returns how many indices were written.
-> gif_lzw(src, mcs, out, count) (u8[] i64 u8[] i64) i64
  prefix = i32[4096]
  suffix = u8[4096]
  stack = u8[4097]
  clear = (1 ## i64) << mcs
  eoi = clear + 1
  size = mcs + 1
  mask = ((1 ## i64) << size) - 1
  avail = clear + 2
  old = -1 ## i64
  first = 0 ## i64
  bits = 0 ## i64
  acc = 0 ## i64
  p = 0 ## i64
  n = src.size
  o = 0 ## i64
  c = 0 ## i64
  while c < clear
    prefix[c] = -1
    suffix[c] = c
    c += 1
  while o < count
    while bits < size && p < n
      acc = acc | (src[p] << bits)
      bits += 8
      p += 1
    break if bits < size
    code = acc & mask
    acc = acc >> size
    bits -= size
    if code == clear
      size = mcs + 1
      mask = ((1 ## i64) << size) - 1
      avail = clear + 2
      old = -1
    elsif code == eoi
      break
    elsif old == -1
      break if code >= clear
      out[o] = code
      o += 1
      old = code
      first = code
    else
      in_code = code
      sp = 0 ## i64
      if code >= avail
        break if code > avail
        stack[sp] = first
        sp += 1
        code = old
      while code >= clear && sp < 4096
        stack[sp] = suffix[code]
        sp += 1
        code = prefix[code]
      first = code
      stack[sp] = code
      sp += 1
      if avail < 4096
        prefix[avail] = old
        suffix[avail] = first
        avail += 1
        if (avail & mask) == 0 && avail < 4096
          size += 1
          mask = ((1 ## i64) << size) - 1
      while sp > 0 && o < count
        sp -= 1
        out[o] = stack[sp]
        o += 1
      old = in_code
  o

# valid[r] = how many pixels of decoded row r (in stream order) arrived.
-> gif_valid_rows(valid, w, h, got) (i32[] i64 i64 i64) i64
  r = 0 ## i64
  while r < h
    v = got - r * w
    v = 0 if v < 0
    v = w if v > w
    valid[r] = v
    r += 1
  0

# Reorder interlaced rows (and their valid counts) into display order.
-> gif_deinterlace(idx, w, h, valid) (u8[] i64 i64 i32[]) u8[]
  out = u8[w * h]
  ordered = i32[h]
  row = 0 ## i64
  pass = 0 ## i64
  while pass < 4
    y = 0 ## i64
    step = 8 ## i64
    if pass == 1
      y = 4
    elsif pass == 2
      y = 2
      step = 4
    elsif pass == 3
      y = 1
      step = 2
    while y < h
      src = row * w
      dst = y * w
      x = 0 ## i64
      while x < w
        out[dst + x] = idx[src + x]
        x += 1
      ordered[y] = valid[row]
      row += 1
      y += step
    pass += 1
  y2 = 0 ## i64
  while y2 < h
    valid[y2] = ordered[y2]
    y2 += 1
  out

# Paint the arrived pixels of a frame onto the canvas (transparent index skipped).
-> gif_draw(canvas, cw, ch, idx, fx, fy, fw, fh, table, trans, valid) (u8[] i64 i64 u8[] i64 i64 i64 i64 u8[] i64 i32[]) i64
  y = 0 ## i64
  while y < fh
    cy = fy + y
    if cy >= ch
      return 0
    lim = valid[y]
    x = 0 ## i64
    while x < lim
      k = y * fw + x
      cx = fx + x
      if cx < cw
        v = idx[k]
        if v != trans
          o = (cy * cw + cx) * 4
          q = v * 4
          canvas[o] = table[q]
          canvas[o + 1] = table[q + 1]
          canvas[o + 2] = table[q + 2]
          canvas[o + 3] = 255
      x += 1
    y += 1
  0

img_register("gif", ->(b) gif_sniff?(b), ->(b) gif_decode(b))
