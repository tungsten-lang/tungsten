# core/codec/image/jp2 — JPEG 2000 decoder (ITU-T T.800 / ISO 15444-1, JP2 and the
# JPX boxes a browser meets).
#
# jp2_decode(bytes) → Bitmap. Accepts a JP2/JPX file (boxes: jp2h with ihdr,
# colr, pclr, cmap, cdef, res; jp2c) or a raw J2K codestream (FF 4F FF 51).
#
# Codestream: SIZ, COD/COC, QCD/QCC, RGN, POC, PPM/PPT, TLM/PLM/PLT/CRG/COM
# (skipped), tiles in any number of tile-parts, all five progression orders
# with POC progression changes, precincts, code-blocks, tag trees, packet
# headers (SOP/EPH), tier 1 in jp2_t1 (MQ + EBCOT, all mode switches) and the
# 5/3 / 9/7 inverse DWT in jp2_dwt; RCT/ICT, DC level shift, sub-sampled
# components, any bit depth scaled to 8 bits, sYCC, greyscale, palette,
# channel definitions (alpha, premultiplied alpha), the JPX YCC/CMYK
# enumerated spaces, and restricted ICC profiles (grey or matrix/TRC RGB,
# through core/codec/image/icc). The picture is produced on component 0's sampling grid,
# as ImageIO does. Truncated streams decode as far as the data goes (the
# missing packets just lower the quality); other damage raises ImageError.

use core/codec/image
use icc
use jp2_t1
use jp2_dwt

+ J2Cp
  rw :nl, :xcb, :ycb, :sty, :rev, :ppx, :ppy

  -> new(@nl, @xcb, @ycb, @sty, @rev)
    @ppx = []
    @ppy = []
    i = 0
    while i <= @nl
      @ppx.push(15)
      @ppy.push(15)
      i += 1

+ J2Qp
  rw :style, :guard, :eps, :mu

  -> new(@style, @guard)
    @eps = []
    @mu = []

# Coding-style state for the main header or one tile.
+ J2Hdr
  rw :scod, :prog, :layers, :mct, :cp, :coc, :qcd, :qcc, :rgn, :poc

  -> new(nc)
    @scod = nil
    @prog = 0
    @layers = 1
    @mct = 0
    @cp = nil
    @qcd = nil
    @coc = Array.new(nc, nil)
    @qcc = Array.new(nc, nil)
    @rgn = Array.new(nc, nil)
    @poc = []

+ J2Tile
  rw :idx, :hdr, :chunks, :ppt, :ppm, :nparts

  -> new(@idx, nc)
    @hdr = J2Hdr.new(nc)
    @chunks = []
    @ppt = []
    @ppm = []
    @nparts = 0

+ J2Block
  rw :x0, :y0, :x1, :y1, :inc, :lblock, :zbp, :npass, :segl, :segp, :segm, :chunks, :nnew

  -> new(@x0, @y0, @x1, @y1)
    @inc = false
    @lblock = 3
    @zbp = 0
    @npass = 0
    @segl = []
    @segp = []
    @segm = []
    @chunks = []
    @nnew = []

+ J2Tag
  rw :par, :val, :low, :stk, :n

  -> new(w, h)
    ws = [w]
    hs = [h]
    n = w * h
    cw = w
    ch = h
    while cw > 1 || ch > 1
      cw = (cw + 1) >> 1
      ch = (ch + 1) >> 1
      ws.push(cw)
      hs.push(ch)
      n += cw * ch
    @n = n
    @par = i64[n]
    @val = i64[n]
    @low = i64[n]
    @stk = i64[ws.size + 2]
    off = 0
    lv = 0
    while lv < ws.size
      lw = ws[lv]
      lh = hs[lv]
      noff = off + lw * lh
      y = 0
      while y < lh
        x = 0
        while x < lw
          i = off + y * lw + x
          if lv + 1 < ws.size
            @par[i] = noff + (y >> 1) * ws[lv + 1] + (x >> 1)
          else
            @par[i] = -1
          @val[i] = 1 << 40
          x += 1
        y += 1
      off = noff
      lv += 1

  # 1 if the leaf's value is below thr (decoding as many bits as needed).
  -> decode(b, st, leaf, thr)
    j2_tagdec(@par, @val, @low, @stk, b, st, leaf, thr)

  -> value(leaf)
    @val[leaf]

+ J2Band
  rw :x0, :y0, :x1, :y1, :orient, :mb, :delta, :xoff, :yoff, :cbw, :cbh

  -> new(@x0, @y0, @x1, @y1, @orient)

+ J2Prec
  rw :blocks, :incl, :zbt

  -> new
    @blocks = []
    @incl = []
    @zbt = []

+ J2Res
  rw :x0, :y0, :x1, :y1, :pw, :ph, :ppx, :ppy, :precs, :bands

  -> new(@x0, @y0, @x1, @y1)
    @precs = []
    @bands = []

# ---------------------------------------------------------------- bit I/O

-> j2_fail(msg)
  << "jp2: " + msg if env("JP2_DEBUG") != nil
  raise ImageError, "jp2: " + msg

-> j2_u16(b, p) (u8[] i64) i64
  (b[p] << 8) | b[p + 1]

-> j2_u32(b, p) (u8[] i64) i64
  (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3]

# Packet-header bit reader with 0xFF bit stuffing. st: [pos, ct, last, end].
-> j2_bit(b, st) (u8[] i64[]) i64
  ct = st[1]
  if ct == 0
    if st[2] == 0xFF
      ct = 7
    else
      ct = 8
    pos = st[0]
    by = 0 ## i64
    by = b[pos] if pos < st[3]
    st[2] = by
    st[0] = pos + 1
  ct -= 1
  st[1] = ct
  (st[2] >> ct) & 1

-> j2_bits(b, st, n) (u8[] i64[] i64) i64
  v = 0 ## i64
  i = 0 ## i64
  while i < n
    v = (v << 1) | j2_bit(b, st)
    i += 1
  v

-> j2_align(b, st) (u8[] i64[]) i64
  if st[2] == 0xFF
    st[0] = st[0] + 1
  st[1] = 0
  st[2] = 0
  0

-> j2_tagdec(par, val, low, stk, b, st, leaf, thr) (i64[] i64[] i64[] i64[] u8[] i64[] i64 i64) i64
  depth = 0 ## i64
  n = leaf
  while n >= 0
    stk[depth] = n
    depth += 1
    n = par[n]
  lo = 0 ## i64
  while depth > 0
    depth -= 1
    n = stk[depth]
    if lo > low[n]
      low[n] = lo
    else
      lo = low[n]
    while lo < thr && lo < val[n]
      if j2_bit(b, st) == 1
        val[n] = lo
      else
        lo += 1
    low[n] = lo
  return 1 if val[leaf] < thr
  0

-> j2_ceilp(a, k) (i64 i64) i64
  one = 1 ## i64
  (a + (one << k) - 1) >> k

-> j2_ceil(a, b) (i64 i64) i64
  q = a / b
  q += 1 if q * b < a
  q

-> j2_floorlog2(n) (i64) i64
  r = 0 ## i64
  while n > 1
    n = n >> 1
    r += 1
  r

-> j2_bytes(b)
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

# Concatenate [buf, off, len] chunks.
-> j2_join(chunks)
  n = 0
  chunks.each ->(c)
    n += c[2]
  out = u8[n + 2]
  p = 0
  chunks.each ->(c)
    j2_copy(c[0], c[1], out, p, c[2])
    p += c[2]
  out

-> j2_copy(src, so, dst, dp, n) (u8[] i64 u8[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[dp + i] = src[so + i]
    i += 1
  0

# ---------------------------------------------------------------- headers

+ J2Image
  rw :w, :h, :x0, :y0, :tw, :th, :tx0, :ty0, :nc, :xr, :yr, :prec, :sgnd, :main, :tiles, :ppm, :ntx, :nty

  -> new
    @xr = []
    @yr = []
    @prec = []
    @sgnd = []
    @tiles = {}
    @ppm = []

-> j2_comp_index(b, p, nc)
  if nc >= 257
    return j2_u16(b, p)
  b[p]

-> j2_read_spcod(b, p, scod_prec, cp)
  cp.nl = b[p]
  cp.xcb = (b[p + 1] & 15) + 2
  cp.ycb = (b[p + 2] & 15) + 2
  cp.sty = b[p + 3]
  cp.rev = b[p + 4]
  cp.ppx = []
  cp.ppy = []
  i = 0
  while i <= cp.nl
    if scod_prec
      v = b[p + 5 + i]
      cp.ppx.push(v & 15)
      cp.ppy.push(v >> 4)
    else
      cp.ppx.push(15)
      cp.ppy.push(15)
    i += 1
  cp

-> j2_read_qcd(b, p, len)
  s = b[p]
  q = J2Qp.new(s & 31, s >> 5)
  i = p + 1
  e = p + len
  if q.style == 0
    while i < e
      q.eps.push(b[i] >> 3)
      q.mu.push(0)
      i += 1
  else
    while i + 1 < e
      v = j2_u16(b, i)
      q.eps.push(v >> 11)
      q.mu.push(v & 2047)
      i += 2
  q

# Parse one marker segment into hdr (main or tile). Returns false for
# markers that don't belong to the header.
-> j2_marker(img, hdr, m, b, p, len, tile)
  nc = img.nc
  if m == 0xFF52
    hdr.scod = b[p]
    hdr.prog = b[p + 1]
    hdr.layers = j2_u16(b, p + 2)
    hdr.mct = b[p + 4]
    cp = J2Cp.new(0, 6, 6, 0, 0)
    hdr.cp = j2_read_spcod(b, p + 5, (b[p] & 1) != 0, cp)
    # a tile COD overrides main-header COCs
    if tile
      i = 0
      while i < nc
        hdr.coc[i] = nil
        i += 1
  elsif m == 0xFF53
    c = j2_comp_index(b, p, nc)
    o = 1
    o = 2 if nc >= 257
    cp = J2Cp.new(0, 6, 6, 0, 0)
    hdr.coc[c] = j2_read_spcod(b, p + o + 1, (b[p + o] & 1) != 0, cp)
  elsif m == 0xFF5C
    hdr.qcd = j2_read_qcd(b, p, len)
    if tile
      i = 0
      while i < nc
        hdr.qcc[i] = nil
        i += 1
  elsif m == 0xFF5D
    c = j2_comp_index(b, p, nc)
    o = 1
    o = 2 if nc >= 257
    hdr.qcc[c] = j2_read_qcd(b, p + o, len - o)
  elsif m == 0xFF5E
    c = j2_comp_index(b, p, nc)
    o = 1
    o = 2 if nc >= 257
    hdr.rgn[c] = b[p + o + 1]
  elsif m == 0xFF5F
    cs = 1
    cs = 2 if nc >= 257
    step = 5 + 2 * cs
    i = p
    while i + step <= p + len
      rs = b[i]
      csp = j2_comp_index(b, i + 1, nc)
      lye = j2_u16(b, i + 1 + cs)
      re = b[i + 3 + cs]
      ce = j2_comp_index(b, i + 4 + cs, nc)
      ce = 256 if ce == 0 && cs == 1
      pr = b[i + 4 + 2 * cs]
      hdr.poc.push([rs, csp, lye, re, ce, pr])
      i += step
  else
    return false
  true

# Effective coding parameters for component c of a tile.
-> j2_cp_for(img, tile, c)
  th = tile.hdr
  return th.coc[c] if th.coc[c] != nil
  return th.cp if th.cp != nil
  mh = img.main
  return mh.coc[c] if mh.coc[c] != nil
  mh.cp

-> j2_qp_for(img, tile, c)
  th = tile.hdr
  return th.qcc[c] if th.qcc[c] != nil
  return th.qcd if th.qcd != nil
  mh = img.main
  return mh.qcc[c] if mh.qcc[c] != nil
  mh.qcd

-> j2_parse(b, start, e)
  img = J2Image.new
  p = start
  j2_fail("no SOC") if j2_u16(b, p) != 0xFF4F
  p += 2
  main = nil
  # main header
  in_main = true
  ppm_data = []
  while in_main
    j2_fail("truncated header") if p + 4 > e
    m = j2_u16(b, p)
    if m == 0xFF90
      in_main = false
    elsif m >= 0xFF30 && m <= 0xFF3F
      p += 2
    else
      len = j2_u16(b, p + 2)
      q = p + 4
      if m == 0xFF51
        img.w = j2_u32(b, q + 2)
        img.h = j2_u32(b, q + 6)
        img.x0 = j2_u32(b, q + 10)
        img.y0 = j2_u32(b, q + 14)
        img.tw = j2_u32(b, q + 18)
        img.th = j2_u32(b, q + 22)
        img.tx0 = j2_u32(b, q + 26)
        img.ty0 = j2_u32(b, q + 30)
        img.nc = j2_u16(b, q + 34)
        i = 0
        while i < img.nc
          ss = b[q + 36 + i * 3]
          img.prec.push((ss & 0x7F) + 1)
          img.sgnd.push(ss >> 7)
          img.xr.push(b[q + 37 + i * 3])
          img.yr.push(b[q + 38 + i * 3])
          i += 1
        main = J2Hdr.new(img.nc)
        img.main = main
      elsif m == 0xFF60
        ppm_data.push([b, q + 1, len - 3])
      elsif main != nil
        j2_marker(img, main, m, b, q, len - 2, false)
      p += 2 + len
  j2_fail("no SIZ") if main == nil
  j2_fail("no COD") if main.cp == nil
  j2_fail("no QCD") if main.qcd == nil
  img.ntx = j2_ceil(img.w - img.tx0, img.tw)
  img.nty = j2_ceil(img.h - img.ty0, img.th)
  # PPM: Nppm-prefixed chunks, one per tile-part in codestream order
  ppm_chunks = []
  if ppm_data.size > 0
    pb = j2_join(ppm_data)
    pe = pb.size - 2
    i = 0
    while i + 4 <= pe
      n = j2_u32(pb, i)
      ppm_chunks.push([pb, i + 4, n])
      i += 4 + n
  tp_count = 0
  # tile-parts
  while p + 2 <= e && j2_u16(b, p) == 0xFF90
    lsot = j2_u16(b, p + 2)
    isot = j2_u16(b, p + 4)
    psot = j2_u32(b, p + 6)
    sot_at = p
    tile = img.tiles[isot]
    if tile == nil
      tile = J2Tile.new(isot, img.nc)
      img.tiles[isot] = tile
    p += 2 + lsot
    body_end = e
    body_end = sot_at + psot if psot != 0
    body_end = e if body_end > e
    while p + 2 <= body_end && j2_u16(b, p) != 0xFF93
      m = j2_u16(b, p)
      if m >= 0xFF30 && m <= 0xFF3F
        p += 2
        next
      len = j2_u16(b, p + 2)
      if m == 0xFF61
        tile.ppt.push([b[p + 4], [b, p + 5, len - 3]])
      else
        j2_marker(img, tile.hdr, m, b, p + 4, len - 2, true)
      p += 2 + len
    p += 2
    tile.chunks.push([b, p, body_end - p]) if body_end > p
    if tp_count < ppm_chunks.size
      tile.ppm.push(ppm_chunks[tp_count])
    tp_count += 1
    tile.nparts = tile.nparts + 1
    p = body_end
    break if psot == 0
  img

# ---------------------------------------------------------------- tile setup

-> j2_build_comp(img, tile, c, tx0, ty0, tx1, ty1)
  cp = j2_cp_for(img, tile, c)
  qp = j2_qp_for(img, tile, c)
  xr = img.xr[c]
  yr = img.yr[c]
  tcx0 = j2_ceil(tx0, xr)
  tcy0 = j2_ceil(ty0, yr)
  tcx1 = j2_ceil(tx1, xr)
  tcy1 = j2_ceil(ty1, yr)
  nl = cp.nl
  roi = tile.hdr.rgn[c]
  roi = img.main.rgn[c] if roi == nil
  roi = 0 if roi == nil
  ress = []
  r = 0
  while r <= nl
    lv = nl - r
    res = J2Res.new(j2_ceilp(tcx0, lv), j2_ceilp(tcy0, lv), j2_ceilp(tcx1, lv), j2_ceilp(tcy1, lv))
    ppx = cp.ppx[r]
    ppy = cp.ppy[r]
    # PPx = 0 is only legal at resolution 0; tolerate it elsewhere as 1
    ppx = 1 if ppx < 1 && r > 0
    ppy = 1 if ppy < 1 && r > 0
    res.ppx = ppx
    res.ppy = ppy
    if res.x1 > res.x0
      res.pw = j2_ceilp(res.x1, ppx) - (res.x0 >> ppx)
    else
      res.pw = 0
    if res.y1 > res.y0
      res.ph = j2_ceilp(res.y1, ppy) - (res.y0 >> ppy)
    else
      res.ph = 0
    # bands
    if r == 0
      res.bands.push(J2Band.new(res.x0, res.y0, res.x1, res.y1, 0))
    else
      nb = nl - r + 1
      o = 1
      while o <= 3
        xob = o & 1
        yob = o >> 1
        bx0 = j2_ceilp(tcx0 - (xob << (nb - 1)), nb)
        by0 = j2_ceilp(tcy0 - (yob << (nb - 1)), nb)
        bx1 = j2_ceilp(tcx1 - (xob << (nb - 1)), nb)
        by1 = j2_ceilp(tcy1 - (yob << (nb - 1)), nb)
        res.bands.push(J2Band.new(bx0, by0, bx1, by1, o))
        o += 1
    # quantisation, code-block sizes, layout offsets
    res.bands.each ->(bd)
      o = bd.orient
      bi = 0
      bi = 3 * (r - 1) + o if r > 0
      eps = 0
      mu = 0
      if qp.style == 1
        eps = qp.eps[0]
        eps = qp.eps[0] - r + 1 if r > 0
        mu = qp.mu[0]
      else
        eps = qp.eps[bi] if bi < qp.eps.size
        mu = qp.mu[bi] if bi < qp.mu.size
      bd.mb = qp.guard + eps - 1 + roi
      gain = 0
      gain = 1 if o == 1 || o == 2
      gain = 2 if o == 3
      rb = img.prec[c] + gain
      bd.delta = (~1.0 + mu / ~2048.0) * Math.pow(~2.0, (rb - eps) * ~1.0)
      if r == 0
        bd.cbw = cp.xcb
        bd.cbw = ppx if ppx < bd.cbw
        bd.cbh = cp.ycb
        bd.cbh = ppy if ppy < bd.cbh
        bd.xoff = 0
        bd.yoff = 0
      else
        bd.cbw = cp.xcb
        bd.cbw = ppx - 1 if ppx - 1 < bd.cbw
        bd.cbh = cp.ycb
        bd.cbh = ppy - 1 if ppy - 1 < bd.cbh
        pr = ress[r - 1]
        bd.xoff = 0
        bd.yoff = 0
        bd.xoff = pr.x1 - pr.x0 if (o & 1) == 1
        bd.yoff = pr.y1 - pr.y0 if o >= 2
    # precincts
    j = 0
    while j < res.ph
      i = 0
      while i < res.pw
        pc = J2Prec.new
        px0 = ((res.x0 >> ppx) + i) << ppx
        py0 = ((res.y0 >> ppy) + j) << ppy
        res.bands.each ->(bd)
          bpx0 = px0
          bpy0 = py0
          bpx1 = px0 + (1 << ppx)
          bpy1 = py0 + (1 << ppy)
          if r > 0
            bpx0 = px0 >> 1
            bpy0 = py0 >> 1
            bpx1 = bpx0 + (1 << (ppx - 1))
            bpy1 = bpy0 + (1 << (ppy - 1))
          bpx0 = bd.x0 if bd.x0 > bpx0
          bpy0 = bd.y0 if bd.y0 > bpy0
          bpx1 = bd.x1 if bd.x1 < bpx1
          bpy1 = bd.y1 if bd.y1 < bpy1
          blocks = []
          if bpx1 > bpx0 && bpy1 > bpy0
            cw = bd.cbw
            chh = bd.cbh
            cx0 = bpx0 >> cw
            cy0 = bpy0 >> chh
            cx1 = j2_ceilp(bpx1, cw)
            cy1 = j2_ceilp(bpy1, chh)
            yy = cy0
            while yy < cy1
              xx = cx0
              while xx < cx1
                bx0 = xx << cw
                by0 = yy << chh
                bx1 = bx0 + (1 << cw)
                by1 = by0 + (1 << chh)
                bx0 = bpx0 if bpx0 > bx0
                by0 = bpy0 if bpy0 > by0
                bx1 = bpx1 if bpx1 < bx1
                by1 = bpy1 if bpy1 < by1
                blocks.push(J2Block.new(bx0, by0, bx1, by1))
                xx += 1
              yy += 1
            pc.incl.push(J2Tag.new(cx1 - cx0, cy1 - cy0))
            pc.zbt.push(J2Tag.new(cx1 - cx0, cy1 - cy0))
          else
            pc.incl.push(nil)
            pc.zbt.push(nil)
          pc.blocks.push(blocks)
        res.precs.push(pc)
        i += 1
      j += 1
    ress.push(res)
    r += 1
  [cp, ress, tcx0, tcy0, tcx1, tcy1, roi]

# ---------------------------------------------------------------- tier 2

# Packet order for a tile: flat [l, r, c, p, …].
-> j2_packet_order(img, tile, comps, tx0, ty0, tx1, ty1)
  hdr = tile.hdr
  prog = img.main.prog
  layers = img.main.layers
  if hdr.cp != nil
    prog = hdr.prog
    layers = hdr.layers
  pocs = hdr.poc
  pocs = img.main.poc if pocs.size == 0
  nc = img.nc
  maxr = 0
  comps.each ->(cm)
    maxr = cm[0].nl + 1 if cm[0].nl + 1 > maxr
  entries = []
  if pocs.size == 0
    entries.push([0, 0, layers, maxr, nc, prog])
  else
    entries = pocs
  # include table: one flag per (layer, c, r, p)
  base = []
  tot = 0
  c = 0
  while c < nc
    row = []
    comps[c][1].each ->(res)
      row.push(tot)
      tot += res.pw * res.ph
    base.push(row)
    c += 1
  inc = u8[tot * layers + 1]
  out = []
  entries.each ->(en)
    rs = en[0]
    cs = en[1]
    lye = en[2]
    lye = layers if lye > layers
    re = en[3]
    re = maxr if re > maxr
    ce = en[4]
    ce = nc if ce > nc
    pr = en[5]
    j2_iter(img, comps, base, inc, tot, out, pr, rs, cs, lye, re, ce, tx0, ty0, tx1, ty1)
  out

-> j2_emit(out, inc, base, tot, l, r, c, p)
  k = l * tot + base[c][r] + p
  if inc[k] == 0
    inc[k] = 1
    out.push(l)
    out.push(r)
    out.push(c)
    out.push(p)

# Precinct index visited at grid point (x, y) for (c, r), or -1.
-> j2_pos_prec(img, cm, c, r, x, y, tx0, ty0)
  cp = cm[0]
  return -1 if r > cp.nl
  res = cm[1][r]
  return -1 if res.pw == 0 || res.ph == 0
  lv = cp.nl - r
  xr = img.xr[c]
  yr = img.yr[c]
  rpx = res.ppx + lv
  rpy = res.ppy + lv
  okx = (x % (xr << rpx)) == 0 || (x == tx0 && ((res.x0 << lv) % (1 << rpx)) != 0)
  oky = (y % (yr << rpy)) == 0 || (y == ty0 && ((res.y0 << lv) % (1 << rpy)) != 0)
  return -1 if !okx || !oky
  pi = (j2_ceil(x, xr << lv) >> res.ppx) - (res.x0 >> res.ppx)
  pj = (j2_ceil(y, yr << lv) >> res.ppy) - (res.y0 >> res.ppy)
  return -1 if pi < 0 || pj < 0 || pi >= res.pw || pj >= res.ph
  pi + pj * res.pw

-> j2_iter(img, comps, base, inc, tot, out, pr, rs, cs, lye, re, ce, tx0, ty0, tx1, ty1)
  if pr == 0 || pr == 1
    # LRCP / RLCP
    outer = lye
    outer = re if pr == 1
    a = 0
    a = rs if pr == 1
    while a < outer
      b = 0
      b = rs if pr == 0
      inner = re
      inner = lye if pr == 1
      while b < inner
        l = a
        r = b
        if pr == 1
          l = b
          r = a
        c = cs
        while c < ce
          cm = comps[c]
          if r <= cm[0].nl
            res = cm[1][r]
            np = res.pw * res.ph
            p = 0
            while p < np
              j2_emit(out, inc, base, tot, l, r, c, p)
              p += 1
          c += 1
        b += 1
      a += 1
    return 0
  # position-driven orders: step sizes
  dx = 0
  dy = 0
  c = cs
  while c < ce
    cm = comps[c]
    r = 0
    while r <= cm[0].nl
      res = cm[1][r]
      lv = cm[0].nl - r
      sx = img.xr[c] << (res.ppx + lv)
      sy = img.yr[c] << (res.ppy + lv)
      dx = sx if dx == 0 || sx < dx
      dy = sy if dy == 0 || sy < dy
      r += 1
    c += 1
  return 0 if dx == 0
  if pr == 2
    r = rs
    while r < re
      y = ty0
      while y < ty1
        x = tx0
        while x < tx1
          c = cs
          while c < ce
            p = j2_pos_prec(img, comps[c], c, r, x, y, tx0, ty0)
            if p >= 0
              l = 0
              while l < lye
                j2_emit(out, inc, base, tot, l, r, c, p)
                l += 1
            c += 1
          x += dx - (x % dx)
        y += dy - (y % dy)
      r += 1
  elsif pr == 3
    y = ty0
    while y < ty1
      x = tx0
      while x < tx1
        c = cs
        while c < ce
          r = rs
          while r < re
            p = j2_pos_prec(img, comps[c], c, r, x, y, tx0, ty0)
            if p >= 0
              l = 0
              while l < lye
                j2_emit(out, inc, base, tot, l, r, c, p)
                l += 1
            r += 1
          c += 1
        x += dx - (x % dx)
      y += dy - (y % dy)
  elsif pr == 4
    c = cs
    while c < ce
      y = ty0
      while y < ty1
        x = tx0
        while x < tx1
          r = rs
          while r < re
            p = j2_pos_prec(img, comps[c], c, r, x, y, tx0, ty0)
            if p >= 0
              l = 0
              while l < lye
                j2_emit(out, inc, base, tot, l, r, c, p)
                l += 1
            r += 1
          x += dx - (x % dx)
        y += dy - (y % dy)
      c += 1
  0

-> j2_npasses(hb, st)
  return 1 if j2_bit(hb, st) == 0
  return 2 if j2_bit(hb, st) == 0
  v = j2_bits(hb, st, 2)
  return 3 + v if v != 3
  v = j2_bits(hb, st, 5)
  return 6 + v if v != 31
  37 + j2_bits(hb, st, 7)

-> j2_seg_max(sty, segm)
  return 1 if (sty & 4) != 0
  if (sty & 1) != 0
    return 10 if segm.size == 0
    pm = segm[segm.size - 1]
    return 2 if pm == 1 || pm == 10
    return 1
  109

# Decode one packet. hs/hst: header stream and its state; data/dst: body
# stream and position ([pos, end]). Returns false when data ran out.
-> j2_packet(cm, r, p, l, sty_sop, sty_eph, hb, hst, data, dpos, sep)
  cp = cm[0]
  res = cm[1][r]
  pc = res.precs[p]
  sty = cp.sty
  # SOP marker in the body stream
  if sty_sop && dpos[0] + 6 <= dpos[1] && data[dpos[0]] == 0xFF && data[dpos[0] + 1] == 0x91
    dpos[0] = dpos[0] + 6
  if !sep
    hst[0] = dpos[0]
    hst[1] = 0
    hst[2] = 0
  return false if hst[0] >= hst[3]
  present = j2_bit(hb, hst)
  if present == 1
    bi = 0
    while bi < res.bands.size
      blocks = pc.blocks[bi]
      k = 0
      while k < blocks.size
        cb = blocks[k]
        cb.nnew = []
        incl = 0
        if !cb.inc
          incl = pc.incl[bi].decode(hb, hst, k, l + 1)
        else
          incl = j2_bit(hb, hst)
        if incl == 1
          if !cb.inc
            t = 1
            zt = pc.zbt[bi]
            while zt.decode(hb, hst, k, t) == 0
              t += 1
            cb.zbp = t - 1
            cb.inc = true
          n = j2_npasses(hb, hst)
          while j2_bit(hb, hst) == 1
            cb.lblock = cb.lblock + 1
          # split the new passes over codeword segments
          while n > 0
            si = cb.segl.size - 1
            if si < 0 || cb.segp[si] >= cb.segm[si]
              cb.segm.push(j2_seg_max(sty, cb.segm))
              cb.segl.push(0)
              cb.segp.push(0)
              si += 1
            room = cb.segm[si] - cb.segp[si]
            take = n
            take = room if room < n
            ln = j2_bits(hb, hst, cb.lblock + j2_floorlog2(take))
            cb.segp[si] = cb.segp[si] + take
            cb.npass = cb.npass + take
            cb.nnew.push(si)
            cb.nnew.push(ln)
            n -= take
        k += 1
      bi += 1
  j2_align(hb, hst)
  if sty_eph && hst[0] + 2 <= hst[3] && hb[hst[0]] == 0xFF && hb[hst[0] + 1] == 0x92
    hst[0] = hst[0] + 2
  dpos[0] = hst[0] if !sep
  if present == 1
    bi = 0
    while bi < res.bands.size
      res_blocks = pc.blocks[bi]
      k = 0
      while k < res_blocks.size
        cb = res_blocks[k]
        nn = cb.nnew
        q = 0
        while q < nn.size
          si = nn[q]
          ln = nn[q + 1]
          ln = dpos[1] - dpos[0] if dpos[0] + ln > dpos[1]
          ln = 0 if ln < 0
          cb.chunks.push([data, dpos[0], ln])
          cb.segl[si] = cb.segl[si] + ln
          dpos[0] = dpos[0] + ln
          q += 2
        cb.nnew = []
        k += 1
      bi += 1
  true

# ---------------------------------------------------------------- tiles

-> j2_decode_tile(img, tile, planes, tb)
  p = tile.idx % img.ntx
  q = tile.idx / img.ntx
  tx0 = img.tx0 + p * img.tw
  ty0 = img.ty0 + q * img.th
  tx1 = tx0 + img.tw
  ty1 = ty0 + img.th
  tx0 = img.x0 if img.x0 > tx0
  ty0 = img.y0 if img.y0 > ty0
  tx1 = img.w if img.w < tx1
  ty1 = img.h if img.h < ty1
  nc = img.nc
  comps = []
  c = 0
  while c < nc
    comps.push(j2_build_comp(img, tile, c, tx0, ty0, tx1, ty1))
    c += 1
  order = j2_packet_order(img, tile, comps, tx0, ty0, tx1, ty1)
  hdr = tile.hdr
  scod = img.main.scod
  mct = img.main.mct
  if hdr.cp != nil
    scod = hdr.scod
    mct = hdr.mct
  sop = (scod & 2) != 0
  eph = (scod & 4) != 0
  data = j2_join(tile.chunks)
  dpos = i64[2]
  dpos[0] = 0
  dpos[1] = data.size - 2
  sep = false
  hb = data
  hst = i64[4]
  if tile.ppm.size > 0
    sep = true
    hb = j2_join(tile.ppm)
  elsif tile.ppt.size > 0
    sep = true
    pts = tile.ppt.sort_by ->(e) e[0]
    hb = j2_join(pts.map ->(e) e[1])
  if sep
    hst[0] = 0
    hst[3] = hb.size - 2
  else
    hst[3] = dpos[1]
  i = 0
  ok = true
  while i < order.size && ok
    l = order[i]
    r = order[i + 1]
    c = order[i + 2]
    pp = order[i + 3]
    ok = j2_packet(comps[c], r, pp, l, sop, eph, hb, hst, data, dpos, sep)
    i += 4
  # tier 1 + dequantisation + inverse DWT per component
  results = []
  c = 0
  while c < nc
    results.push(j2_reconstruct(img, comps[c], c, tb))
    c += 1
  # component transform (first three components, same size)
  if mct != 0 && nc >= 3
    if img.xr[0] == img.xr[1] && img.xr[0] == img.xr[2] && img.yr[0] == img.yr[1] && img.yr[0] == img.yr[2]
      n = results[0][1] * results[0][2]
      if comps[0][0].rev == 1
        j2_rct(results[0][0], results[1][0], results[2][0], n)
      else
        j2_ict(results[0][0], results[1][0], results[2][0], n)
  # store into component planes with the DC level shift
  c = 0
  while c < nc
    cm = comps[c]
    rr = results[c]
    pl = planes[c]
    cx0 = j2_ceil(img.x0, img.xr[c])
    cy0 = j2_ceil(img.y0, img.yr[c])
    pw = j2_ceil(img.w, img.xr[c]) - cx0
    shift = ~0.0
    shift = Math.pow(~2.0, (img.prec[c] - 1) * ~1.0) if img.sgnd[c] == 0
    j2_store(rr[0], rr[1], rr[2], pl, pw, cm[2] - cx0, cm[3] - cy0, shift * ~1.0)
    c += 1
  0

-> j2_store(a, w, h, pl, pw, ox, oy, shift) (f64[] i64 i64 f64[] i64 i64 i64 f64) i64
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    o = (oy + y) * pw + ox
    while x < w
      pl[o + x] = a[y * w + x] + shift
      x += 1
    y += 1
  0

-> j2_rct(a, b, c, n) (f64[] f64[] f64[] i64) i64
  i = 0 ## i64
  while i < n
    y = a[i] ## i64
    u = b[i] ## i64
    v = c[i] ## i64
    g = y - ((u + v) >> 2)
    a[i] = (v + g) * ~1.0
    b[i] = g * ~1.0
    c[i] = (u + g) * ~1.0
    i += 1
  0

-> j2_ict(a, b, c, n) (f64[] f64[] f64[] i64) i64
  i = 0 ## i64
  while i < n
    y = a[i]
    u = b[i]
    v = c[i]
    a[i] = y + ~1.402 * v
    b[i] = y - ~0.34413 * u - ~0.71414 * v
    c[i] = y + ~1.772 * u
    i += 1
  0

# Decode all code-blocks of a component and run the inverse DWT; returns
# [f64 samples, width, height].
-> j2_reconstruct(img, cm, c, tb)
  cp = cm[0]
  ress = cm[1]
  nl = cp.nl
  top = ress[nl]
  w = top.x1 - top.x0
  h = top.y1 - top.y0
  n = w * h
  rev = cp.rev == 1
  ai = nil
  af = nil
  if rev
    ai = i64[n + 1]
  else
    af = f64[n + 1]
  cbmax = (1 << cp.xcb) * (1 << cp.ycb)
  out = i64[cbmax]
  v = i64[cbmax]
  fl = i64[((1 << cp.xcb) + 2) * ((1 << cp.ycb) + 2)]
  cx = i64[19]
  s = i64[8]
  roi = cm[6]
  ress.each ->(res)
    res.precs.each ->(pc)
      bi = 0
      while bi < res.bands.size
        bd = res.bands[bi]
        pc.blocks[bi].each ->(cb)
          if cb.npass > 0
            bw = cb.x1 - cb.x0
            bh = cb.y1 - cb.y0
            d = j2_join(cb.chunks)
            ns = cb.segl.size
            segl = i64[ns + 1]
            segp = i64[ns + 1]
            k = 0
            while k < ns
              segl[k] = cb.segl[k]
              segp[k] = cb.segp[k]
              k += 1
            p0 = bd.mb - cb.zbp - 1
            if p0 >= 0
              j2_t1_decode(d, segl, segp, ns, bw, bh, bd.orient, cp.sty, p0, cb.npass, out, v, fl, cx, s, tb)
              ox = bd.xoff + cb.x0 - bd.x0
              oy = bd.yoff + cb.y0 - bd.y0
              if rev
                j2_put_rev(out, bw, bh, ai, w, ox, oy, roi)
              else
                j2_put_irr(out, bw, bh, af, w, ox, oy, roi, bd.delta * ~0.5)
        bi += 1
  rx0 = i64[nl + 1]
  ry0 = i64[nl + 1]
  rwa = i64[nl + 1]
  rha = i64[nl + 1]
  r = 0
  while r <= nl
    rx0[r] = ress[r].x0
    ry0[r] = ress[r].y0
    rwa[r] = ress[r].x1 - ress[r].x0
    rha[r] = ress[r].y1 - ress[r].y0
    r += 1
  if rev
    j2_idwt53(ai, w, nl, rx0, ry0, rwa, rha)
    af = f64[n + 1]
    j2_i2f(ai, af, n)
  else
    j2_idwt97(af, w, nl, rx0, ry0, rwa, rha)
  [af, w, h]

-> j2_i2f(a, f, n) (i64[] f64[] i64) i64
  i = 0 ## i64
  while i < n
    f[i] = a[i] * ~1.0
    i += 1
  0

-> j2_put_rev(src, bw, bh, a, w, ox, oy, roi) (i64[] i64 i64 i64[] i64 i64 i64 i64) i64
  one = 1 ## i64
  thr = one << (roi + 1)
  y = 0 ## i64
  while y < bh
    x = 0 ## i64
    while x < bw
      v = src[y * bw + x]
      neg = v < 0
      m = v
      m = 0 - v if neg
      m = m >> roi if roi > 0 && m >= thr
      m = m >> 1
      m = 0 - m if neg
      a[(oy + y) * w + ox + x] = m
      x += 1
    y += 1
  0

-> j2_put_irr(src, bw, bh, a, w, ox, oy, roi, step) (i64[] i64 i64 f64[] i64 i64 i64 i64 f64) i64
  one = 1 ## i64
  thr = one << (roi + 1)
  y = 0 ## i64
  while y < bh
    x = 0 ## i64
    while x < bw
      v = src[y * bw + x]
      if roi > 0
        neg = v < 0
        m = v
        m = 0 - v if neg
        m = m >> roi if m >= thr
        v = m
        v = 0 - m if neg
      a[(oy + y) * w + ox + x] = v * step
      x += 1
    y += 1
  0

# ---------------------------------------------------------------- JP2 boxes

+ J2Boxes
  rw :cs, :ce, :enumcs, :icc, :pclr, :cmap, :cdef, :meth

  -> new
    @cs = -1
    @ce = -1
    @enumcs = -1
    @icc = nil
    @pclr = nil
    @cmap = nil
    @cdef = nil
    @meth = 0

-> j2_walk_boxes(b, p, e, bx)
  while p + 8 <= e
    len = j2_u32(b, p)
    typ = j2_u32(b, p + 4)
    hl = 8
    if len == 1
      len = j2_u32(b, p + 12) + (j2_u32(b, p + 8) << 32)
      hl = 16
    len = e - p if len == 0
    break if len < hl
    q = p + hl
    qe = p + len
    qe = e if qe > e
    if typ == 0x6A703268 || typ == 0x72657320 || typ == 0x6A706368 || typ == 0x6A706C68 || typ == 0x63677270
      # super boxes: jp2h, res; JPX jpch (codestream header), jplh
      # (compositing layer header), cgrp (colour group)
      j2_walk_boxes(b, q, qe, bx)
    elsif typ == 0x6A703263
      if bx.cs < 0
        bx.cs = q
        bx.ce = qe
    elsif typ == 0x636F6C72
      if bx.meth == 0
        bx.meth = b[q]
        if b[q] == 1
          bx.enumcs = j2_u32(b, q + 3)
        elsif b[q] == 2 || b[q] == 3
          bx.icc = [b, q + 3, qe - q - 3]
    elsif typ == 0x70636C72
      ne = j2_u16(b, q)
      npc = b[q + 2]
      bits = []
      i = 0
      while i < npc
        bits.push(b[q + 3 + i])
        i += 1
      cols = []
      i = 0
      while i < npc
        cols.push([])
        i += 1
      o = q + 3 + npc
      k = 0
      while k < ne
        i = 0
        while i < npc
          nb = (bits[i] & 0x7F) + 1
          nby = (nb + 7) >> 3
          v = 0
          j = 0
          while j < nby
            v = (v << 8) | b[o]
            o += 1
            j += 1
          cols[i].push(v)
          i += 1
        k += 1
      bx.pclr = [bits, cols]
    elsif typ == 0x636D6170
      m = []
      o = q
      while o + 4 <= qe
        m.push([j2_u16(b, o), b[o + 2], b[o + 3]])
        o += 4
      bx.cmap = m
    elsif typ == 0x63646566
      n = j2_u16(b, q)
      m = []
      i = 0
      while i < n
        o = q + 2 + i * 6
        m.push([j2_u16(b, o), j2_u16(b, o + 2), j2_u16(b, o + 4)])
        i += 1
      bx.cdef = m
    p += len
  0

# ---------------------------------------------------------------- output

# One output channel as f64 samples scaled to 0..255 at component size.
-> j2_scale(pl, n, prec, sgnd, out) (f64[] i64 i64 i64 f64[]) i64
  one = 1 ## i64
  mx = ((one << prec) - 1) * ~1.0
  off = 0.0 ## f64
  off = ((one << (prec - 1)) * ~1.0) if sgnd == 1
  sc = ~255.0 / mx
  i = 0 ## i64
  while i < n
    v = pl[i] + off
    v = ~0.0 if v < ~0.0
    v = mx if v > mx
    out[i] = v * sc
    i += 1
  0

-> j2_palette(pl, n, prec, col, bits, out) (f64[] i64 i64 i64[] i64 f64[]) i64
  ne = col.size
  # an empty palette column (damaged pclr box) maps everything to 0
  n = pl.size if n > pl.size
  n = out.size if n > out.size
  return 0 if ne == 0
  one = 1 ## i64
  sc = ~255.0 / (((one << bits) - 1) * ~1.0)
  i = 0 ## i64
  while i < n
    k = pl[i] ## i64
    k = 0 if k < 0
    k = ne - 1 if k >= ne
    out[i] = col[k] * sc
    i += 1
  0

# Resample a component-sized channel onto the image grid.
-> j2_upsample(src, sw, sh, xr, yr, cx0, cy0, gx0, gy0, gxr, gyr, w, h, dst) (f64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 f64[]) i64
  y = 0 ## i64
  while y < h
    sy = ((gy0 + y) * gyr) / yr - cy0
    sy = 0 if sy < 0
    sy = sh - 1 if sy >= sh
    x = 0 ## i64
    while x < w
      sx = ((gx0 + x) * gxr) / xr - cx0
      sx = 0 if sx < 0
      sx = sw - 1 if sx >= sw
      dst[y * w + x] = src[sy * sw + sx]
      x += 1
    y += 1
  0

-> j2_pack(r, g, bl, a, n, out, ycc, premul) (f64[] f64[] f64[] f64[] i64 u8[] i64 i64) i64
  i = 0 ## i64
  while i < n
    rv = r[i]
    gv = g[i]
    bv = bl[i]
    av = a[i]
    if ycc == 1
      yy = rv
      cb = gv - ~128.0
      cr = bv - ~128.0
      rv = yy + ~1.402 * cr
      gv = yy - ~0.344136 * cb - ~0.714136 * cr
      bv = yy + ~1.772 * cb
    if ycc == 2
      rv = ~255.0 - rv
      gv = ~255.0 - gv
      bv = ~255.0 - bv
    if premul == 1 && av > ~0.0
      f = ~255.0 / av
      rv = rv * f
      gv = gv * f
      bv = bv * f
    ri = (rv + ~0.5) ## i64
    gi = (gv + ~0.5) ## i64
    bi = (bv + ~0.5) ## i64
    ai = (av + ~0.5) ## i64
    ri = 0 if rv < ~0.0
    gi = 0 if gv < ~0.0
    bi = 0 if bv < ~0.0
    ri = 255 if ri > 255
    gi = 255 if gi > 255
    bi = 255 if bi > 255
    ai = 255 if ai > 255
    ai = 0 if av < ~0.0
    out[i * 4] = ri
    out[i * 4 + 1] = gi
    out[i * 4 + 2] = bi
    out[i * 4 + 3] = ai
    i += 1
  0

# c, m, y ← c + k - c*k/255 (the naive device CMYK → CMY step).
-> j2_fold_k(c, m, y, k, n) (f64[] f64[] f64[] f64[] i64) i64
  i = 0 ## i64
  while i < n
    kv = k[i]
    f = ~1.0 - kv / ~255.0
    c[i] = c[i] * f + kv
    m[i] = m[i] * f + kv
    y[i] = y[i] * f + kv
    i += 1
  0

-> j2_fill(a, n, v) (f64[] i64 f64) i64
  i = 0 ## i64
  while i < n
    a[i] = v
    i += 1
  0

# A profile with degenerate colorants (seen in the wild) gives a wild matrix;
# such files are shown unconverted, like other decoders do.
-> j2_icc_sane?(prof)
  return true if prof.gray?
  m = prof.mat
  return false if m == nil
  ok = true
  m.each ->(v)
    ok = false if !(v > ~-8.0 && v < ~8.0)
  ok

-> j2_render(img, planes, bx)
  # The picture is shown on component 0's sampling grid (as ImageIO does);
  # components sampled differently are replicated onto it.
  uniform = true
  c = 1
  while c < img.nc
    uniform = false if img.xr[c] != img.xr[0] || img.yr[c] != img.yr[0]
    c += 1
  gx0 = j2_ceil(img.x0, img.xr[0])
  gy0 = j2_ceil(img.y0, img.yr[0])
  w = j2_ceil(img.w, img.xr[0]) - gx0
  h = j2_ceil(img.h, img.yr[0]) - gy0
  n = w * h
  # channels: [samples f64 (0..255) at component size, comp index]
  chans = []
  if bx != nil && bx.pclr != nil
    bits = bx.pclr[0]
    cols = bx.pclr[1]
    cmap = bx.cmap
    if cmap == nil
      cmap = []
      i = 0
      while i < cols.size
        cmap.push([0, 1, i])
        i += 1
    cmap.each ->(m)
      c = m[0]
      cn = j2_ceil(img.w, img.xr[c]) - j2_ceil(img.x0, img.xr[c])
      cm2 = j2_ceil(img.h, img.yr[c]) - j2_ceil(img.y0, img.yr[c])
      o = f64[cn * cm2 + 1]
      if m[1] == 1
        col = cols[m[2]]
        ca = i64[col.size]
        k = 0
        while k < col.size
          ca[k] = col[k]
          k += 1
        j2_palette(planes[c], cn * cm2, img.prec[c], ca, (bits[m[2]] & 0x7F) + 1, o)
      else
        j2_scale(planes[c], cn * cm2, img.prec[c], img.sgnd[c], o)
      chans.push([o, c])
  else
    c = 0
    while c < img.nc
      cn = j2_ceil(img.w, img.xr[c]) - j2_ceil(img.x0, img.xr[c])
      cm2 = j2_ceil(img.h, img.yr[c]) - j2_ceil(img.y0, img.yr[c])
      o = f64[cn * cm2 + 1]
      j2_scale(planes[c], cn * cm2, img.prec[c], img.sgnd[c], o)
      chans.push([o, c])
      c += 1
  # resample to the image grid
  full = chans.map ->(ch)
    c = ch[1]
    cx0 = j2_ceil(img.x0, img.xr[c])
    cy0 = j2_ceil(img.y0, img.yr[c])
    sw = j2_ceil(img.w, img.xr[c]) - cx0
    sh = j2_ceil(img.h, img.yr[c]) - cy0
    if img.xr[c] == img.xr[0] && img.yr[c] == img.yr[0]
      ch[0]
    else
      d = f64[n + 1]
      j2_upsample(ch[0], sw, sh, img.xr[c], img.yr[c], cx0, cy0, gx0, gy0, img.xr[0], img.yr[0], w, h, d)
      d
  # colour / alpha assignment
  colour = []
  alpha = nil
  premul = 0
  if bx != nil && bx.cdef != nil
    slots = [nil, nil, nil, nil]
    loose = []
    bx.cdef.each ->(e)
      cn = e[0]
      if cn < full.size
        if e[1] == 0 && e[2] >= 1 && e[2] <= 3
          slots[e[2] - 1] = full[cn]
        elsif e[1] == 0
          loose.push(full[cn])
        elsif e[1] == 1 || e[1] == 2
          alpha = full[cn]
          premul = 1 if e[1] == 2
    i = 0
    while i < 3
      if slots[i] == nil && loose.size > 0
        slots[i] = loose[0]
        loose = loose.drop(1)
      colour.push(slots[i]) if slots[i] != nil
      i += 1
  # colour model: 0 RGB/grey, 1 YCbCr (sYCC and the JPX YCC spaces),
  # 2 CMYK / CMY (JPX enumerated spaces 12 and 11)
  ycc = 0
  if bx != nil
    ec = bx.enumcs
    ycc = 1 if ec == 1 || ec == 3 || ec == 4 || ec == 18 || ec == 24
    ycc = 2 if ec == 11 || ec == 12
  # unlabelled 3-component data with sub-sampled chroma is YCbCr (as OpenJPEG assumes)
  ycc = 1 if (bx == nil || bx.enumcs < 0) && img.nc == 3 && img.xr[0] == 1 && img.yr[0] == 1 && (img.xr[1] != 1 || img.yr[1] != 1)
  if colour.size == 0
    grey = full.size < 3
    grey = true if bx != nil && bx.enumcs == 17
    # mixed sampling that isn't Y/Cb/Cr: show the first component (as ImageIO does)
    grey = true if !uniform && ycc == 0 && (bx == nil || bx.pclr == nil)
    full = [full[0]] if grey && !uniform
    if grey
      colour.push(full[0])
      alpha = full[1] if full.size >= 2 && alpha == nil
    elsif ycc == 2 && bx.enumcs == 12 && full.size >= 4
      # CMYK: fold K into the three inks here, the pack step inverts them
      j2_fold_k(full[0], full[1], full[2], full[3], n)
      colour.push(full[0])
      colour.push(full[1])
      colour.push(full[2])
      alpha = full[4] if full.size >= 5 && alpha == nil
    else
      colour.push(full[0])
      colour.push(full[1])
      colour.push(full[2])
      alpha = full[3] if full.size >= 4 && alpha == nil
  if colour.size < 3
    colour = [colour[0], colour[0], colour[0]]
  if alpha == nil
    alpha = f64[n + 1]
    j2_fill(alpha, n, ~255.0)
  out = ByteArray.new(n * 4)
  j2_pack(colour[0], colour[1], colour[2], alpha, n, out, ycc, premul)
  # restricted ICC (grey or matrix/TRC RGB) → sRGB
  if bx != nil && bx.icc != nil
    prof = icc_parse(bx.icc[0], bx.icc[1], bx.icc[2])
    if prof != nil && j2_icc_sane?(prof) && !icc_srgb?(prof)
      icc_apply(prof, out, n)
  Bitmap.new(w, h, out)

# Decode every tile into per-component f64 planes (DC shift applied).
-> j2_planes(b, start, e)
  img = j2_parse(b, start, e)
  j2_fail("bad size") if img.w <= img.x0 || img.h <= img.y0 || img.nc < 1
  j2_fail("image too large") if (img.w - img.x0) * (img.h - img.y0) > 200000000
  tb = j2_tables()
  planes = []
  c = 0
  while c < img.nc
    cw = j2_ceil(img.w, img.xr[c]) - j2_ceil(img.x0, img.xr[c])
    chh = j2_ceil(img.h, img.yr[c]) - j2_ceil(img.y0, img.yr[c])
    planes.push(f64[cw * chh + 1])
    c += 1
  img.tiles.keys.sort.each ->(k)
    j2_decode_tile(img, img.tiles[k], planes, tb)
  [img, planes]

-> j2_decode_cs(b, start, e, bx)
  ip = j2_planes(b, start, e)
  j2_render(ip[0], ip[1], bx)

-> jp2_sniff?(b)
  n = b.size
  return true if n >= 4 && b[0] == 0xFF && b[1] == 0x4F && b[2] == 0xFF && b[3] == 0x51
  n >= 12 && b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 12 && b[4] == 0x6A && b[5] == 0x50 && b[6] == 0x20 && b[7] == 0x20 && b[8] == 0x0D && b[9] == 0x0A && b[10] == 0x87 && b[11] == 0x0A

-> jp2_decode(bytes)
  begin
    j2_decode_bytes(j2_bytes(bytes))
  rescue e
    # corrupt streams surface as an ImageError whatever tripped
    raise e if e.is_a?(ImageError)
    j2_fail("corrupt stream ([e])")

-> j2_decode_bytes(b)
  n = b.size
  if n >= 4 && b[0] == 0xFF && b[1] == 0x4F
    return j2_decode_cs(b, 0, n, nil)
  bx = J2Boxes.new
  j2_walk_boxes(b, 0, n, bx)
  j2_fail("no codestream box") if bx.cs < 0
  j2_decode_cs(b, bx.cs, bx.ce, bx)

img_register("jp2", ->(b) jp2_sniff?(b), ->(b) jp2_decode(b))
