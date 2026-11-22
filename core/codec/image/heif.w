# core/codec/image/heif — the HEIF / ISOBMFF still-image container (ISO/IEC 23008-12,
# MIAF), shared by AVIF (AV1 payloads) and HEIC (HEVC payloads).
#
# heif_parse(bytes) reads ftyp + meta (hdlr, pitm, iinf, iloc, iprp/ipco/ipma,
# iref, idat) into a HeifFile. heif_decode(bytes) decodes the primary item:
# grids of tiles are stitched in Y'CbCr, an alpha auxiliary item (auxC alpha
# URN, premultiplied via 'prem') is attached, the picture is converted to sRGB
# RGBA8 (core/codec/image/heif_color.w) and clap / irot / imir are applied in ipma order.
#
# Codecs plug in through HEIF_CODECS: item type ("av01", "hvc1") →
# ->(file, item, data) returning a HeifPic. The AV1 and HEVC decoders register
# themselves there, so this file never names a codec implementation.
#
# Files without a usable meta primary item (animated AVIF, 'avis' with only a
# moov track) fall back to the first sample of the first video track.

use core/codec/image
use heif_color

+ HeifError < ImageError

# A decoded picture in planar Y'CbCr: planes are u16[] (any bit depth),
# stride == plane width. ssx/ssy: chroma subsampling shifts; mono: no chroma.
# cicp: [primaries, transfer, matrix, full_range] from the bitstream (nil when
# the bitstream says nothing).
+ HeifPic
  rw :width, :height, :bit_depth, :ssx, :ssy, :mono, :planes, :cicp, :tile_w, :tile_h

  -> new(@width, @height, @bit_depth, @ssx, @ssy, @mono)
    @cicp = nil
    @tile_w = 0
    @tile_h = 0
    cw = (@width + (1 << @ssx) - 1) >> @ssx
    ch = (@height + (1 << @ssy) - 1) >> @ssy
    if @mono
      @planes = [u16[@width * @height]]
    else
      @planes = [u16[@width * @height], u16[cw * ch], u16[cw * ch]]

  -> cw
    (@width + (1 << @ssx) - 1) >> @ssx

  -> ch
    (@height + (1 << @ssy) - 1) >> @ssy

  # plane width / height for plane p
  -> pw(p)
    p == 0 ? @width : cw()

  -> ph(p)
    p == 0 ? @height : ch()

HEIF_CODECS = {}

-> heif_codec_register(item_type, dec)
  HEIF_CODECS[item_type] = dec

+ HeifItem
  rw :id, :type, :name, :props, :method, :extents, :base, :refs, :hidden, :content_type

  -> new(@id)
    @type = ""
    @name = ""
    @props = []
    @method = 0
    @extents = []
    @base = 0
    @refs = {}
    @hidden = false
    @content_type = nil

  # first property of box type t, or nil
  -> prop(t)
    i = 0
    while i < @props.size
      return @props[i] if @props[i].type == t
      i += 1
    nil

  -> ref(t)
    r = @refs[t]
    r == nil ? [] : r

# One property box from ipco: type (4cc) plus parsed fields in a hash.
+ HeifProp
  rw :type, :f, :essential

  -> new(@type, @f)
    @essential = false

+ HeifFile
  rw :bytes, :brands, :major, :items, :primary, :idat, :ipco, :moov_track

  -> new(@bytes)
    @brands = []
    @major = ""
    @items = {}
    @primary = nil
    @idat = nil
    @ipco = []
    @moov_track = nil

  -> item(id)
    @items[id]

  # items whose `t` reference points at id (e.g. auxl/prem/cdsc from others)
  -> referrers(id, t)
    out = []
    @items.each ->(k, it)
      r = it.refs[t]
      out.push(it) if r != nil && r.include?(id)
    out

# ---------------------------------------------------------------- bytes

-> hf_u8(a, o)
  a[o]

-> hf_u16(a, o)
  (a[o] << 8) | a[o + 1]

-> hf_u32(a, o)
  (a[o] << 24) | (a[o + 1] << 16) | (a[o + 2] << 8) | a[o + 3]

-> hf_u64(a, o)
  (hf_u32(a, o) << 32) | hf_u32(a, o + 4)

-> hf_i32(a, o)
  v = hf_u32(a, o)
  v >= 2147483648 ? v - 4294967296 : v

-> hf_uint(a, o, n)
  return 0 if n == 0
  return hf_u16(a, o) if n == 2
  return hf_u32(a, o) if n == 4
  return hf_u64(a, o) if n == 8
  return a[o] if n == 1
  raise HeifError.new("heif: bad field size")

-> hf_tag(a, o)
  a[o].chr + a[o + 1].chr + a[o + 2].chr + a[o + 3].chr

# NUL-terminated string at o, bounded by e; returns [string, next offset]
-> hf_cstr(a, o, e)
  s = ""
  while o < e && a[o] != 0
    s = s + a[o].chr
    o += 1
  [s, o + 1]

-> hf_slice(a, o, n)
  out = ByteArray.new(n)
  hf_copy(a, o, out, 0, n)
  out

-> hf_copy(src, so, dst, d0, n) (u8[] i64 u8[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[d0 + i] = src[so + i]
    i += 1
  n

# Boxes in [o, e): Array of [type, payload_start, end].
-> hf_boxes(a, o, e)
  out = []
  while o + 8 <= e
    size = hf_u32(a, o)
    t = hf_tag(a, o + 4)
    h = 8
    if size == 1
      raise HeifError.new("heif: truncated box") if o + 16 > e
      size = hf_u64(a, o + 8)
      h = 16
    elsif size == 0
      size = e - o
    if t == "uuid"
      h += 16
    raise HeifError.new("heif: bad box size") if size < h || o + size > e
    out.push([t, o + h, o + size])
    o += size
  out

-> hf_find(boxes, t)
  i = 0
  while i < boxes.size
    return boxes[i] if boxes[i][0] == t
    i += 1
  nil

# ---------------------------------------------------------------- sniffing

-> hf_brands(b)
  return nil if b.size < 16
  return nil if hf_tag(b, 4) != "ftyp"
  size = hf_u32(b, 0)
  size = b.size if size > b.size
  return nil if size < 16
  out = [hf_tag(b, 8)]
  o = 16
  while o + 4 <= size
    out.push(hf_tag(b, o))
    o += 4
  out

-> heif_avif_sniff?(b)
  br = hf_brands(b)
  return false if br == nil
  br.include?("avif") || br.include?("avis")

HF_HEIC_BRANDS = ["heic", "heix", "hevc", "hevx", "heim", "heis", "hevm", "hevs"]

-> heif_heic_sniff?(b)
  br = hf_brands(b)
  return false if br == nil
  return false if br.include?("avif") || br.include?("avis")
  i = 0
  while i < HF_HEIC_BRANDS.size
    return true if br.include?(HF_HEIC_BRANDS[i])
    i += 1
  # generic mif1/msf1: decode when the primary item is HEVC
  if br.include?("mif1") || br.include?("msf1")
    begin
      f = heif_parse(b)
      it = f.primary == nil ? nil : f.item(f.primary)
      return false if it == nil
      return true if it.type == "hvc1" || it.type == "hev1"
      if it.type == "grid"
        t = it.ref("dimg")
        if t.size > 0
          ti = f.item(t[0])
          return ti != nil && (ti.type == "hvc1" || ti.type == "hev1")
    rescue e
      return false
  false

# ---------------------------------------------------------------- parsing

-> heif_parse(b)
  f = HeifFile.new(b)
  top = hf_boxes(b, 0, b.size)
  ft = hf_find(top, "ftyp")
  raise HeifError.new("heif: no ftyp") if ft == nil
  f.major = hf_tag(b, ft[1])
  o = ft[1] + 8
  while o + 4 <= ft[2]
    f.brands.push(hf_tag(b, o))
    o += 4
  f.brands.push(f.major) if !f.brands.include?(f.major)
  meta = hf_find(top, "meta")
  hf_parse_meta(f, b, meta[1] + 4, meta[2]) if meta != nil
  moov = hf_find(top, "moov")
  f.moov_track = hf_parse_moov(b, moov[1], moov[2]) if moov != nil
  f

-> hf_parse_meta(f, b, o, e)
  boxes = hf_boxes(b, o, e)
  hd = hf_find(boxes, "hdlr")
  if hd != nil
    h = hf_tag(b, hd[1] + 8)
    raise HeifError.new("heif: meta handler is " + h) if h != "pict"
  pm = hf_find(boxes, "pitm")
  if pm != nil
    v = b[pm[1]]
    f.primary = v == 0 ? hf_u16(b, pm[1] + 4) : hf_u32(b, pm[1] + 4)
  ii = hf_find(boxes, "iinf")
  hf_parse_iinf(f, b, ii[1], ii[2]) if ii != nil
  il = hf_find(boxes, "iloc")
  hf_parse_iloc(f, b, il[1], il[2]) if il != nil
  id = hf_find(boxes, "idat")
  f.idat = [id[1], id[2]] if id != nil
  ir = hf_find(boxes, "iref")
  hf_parse_iref(f, b, ir[1], ir[2]) if ir != nil
  ip = hf_find(boxes, "iprp")
  hf_parse_iprp(f, b, ip[1], ip[2]) if ip != nil
  nil

-> hf_get_item(f, id)
  it = f.items[id]
  if it == nil
    it = HeifItem.new(id)
    f.items[id] = it
  it

-> hf_parse_iinf(f, b, o, e)
  v = b[o]
  p = o + 4
  p += v == 0 ? 2 : 4
  boxes = hf_boxes(b, p, e)
  boxes.each ->(bx)
    if bx[0] == "infe"
      q = bx[1]
      iv = b[q]
      flags = (b[q + 1] << 16) | (b[q + 2] << 8) | b[q + 3]
      q += 4
      if iv >= 2
        id = 0
        if iv == 2
          id = hf_u16(b, q)
          q += 2
        else
          id = hf_u32(b, q)
          q += 4
        q += 2
        it = hf_get_item(f, id)
        it.type = hf_tag(b, q)
        it.hidden = (flags & 1) != 0
        q += 4
        r = hf_cstr(b, q, bx[2])
        it.name = r[0]
        if it.type == "mime"
          r2 = hf_cstr(b, r[1], bx[2])
          it.content_type = r2[0]
      else
        id = hf_u16(b, q)
        it = hf_get_item(f, id)
        it.type = "old"
  nil

-> hf_parse_iloc(f, b, o, e)
  v = b[o]
  p = o + 4
  osz = b[p] >> 4
  lsz = b[p] & 15
  bsz = b[p + 1] >> 4
  isz = (v == 1 || v == 2) ? (b[p + 1] & 15) : 0
  p += 2
  n = 0
  if v < 2
    n = hf_u16(b, p)
    p += 2
  else
    n = hf_u32(b, p)
    p += 4
  k = 0
  while k < n
    id = 0
    if v < 2
      id = hf_u16(b, p)
      p += 2
    else
      id = hf_u32(b, p)
      p += 4
    it = hf_get_item(f, id)
    if v == 1 || v == 2
      it.method = hf_u16(b, p) & 15
      p += 2
    p += 2
    it.base = hf_uint(b, p, bsz)
    p += bsz
    ec = hf_u16(b, p)
    p += 2
    ext = []
    j = 0
    while j < ec
      p += isz
      off = hf_uint(b, p, osz)
      p += osz
      len = hf_uint(b, p, lsz)
      p += lsz
      ext.push([off, len])
      j += 1
    it.extents = ext
    k += 1
  nil

-> hf_parse_iref(f, b, o, e)
  v = b[o]
  w = v == 0 ? 2 : 4
  hf_boxes(b, o + 4, e).each ->(bx)
    q = bx[1]
    from = hf_uint(b, q, w)
    q += w
    cnt = hf_u16(b, q)
    q += 2
    to = []
    j = 0
    while j < cnt
      to.push(hf_uint(b, q, w))
      q += w
      j += 1
    it = hf_get_item(f, from)
    old = it.refs[bx[0]]
    if old == nil
      it.refs[bx[0]] = to
    else
      to.each ->(x) old.push(x)
  nil

-> hf_parse_iprp(f, b, o, e)
  boxes = hf_boxes(b, o, e)
  pc = hf_find(boxes, "ipco")
  return nil if pc == nil
  props = []
  hf_boxes(b, pc[1], pc[2]).each ->(bx)
    props.push(hf_parse_prop(b, bx[0], bx[1], bx[2]))
  f.ipco = props
  boxes.each ->(bx)
    if bx[0] == "ipma"
      q = bx[1]
      v = b[q]
      flags = b[q + 3]
      q += 4
      n = hf_u32(b, q)
      q += 4
      k = 0
      while k < n
        id = 0
        if v < 1
          id = hf_u16(b, q)
          q += 2
        else
          id = hf_u32(b, q)
          q += 4
        it = hf_get_item(f, id)
        ac = b[q]
        q += 1
        j = 0
        while j < ac
          ess = false
          idx = 0
          if (flags & 1) != 0
            x = hf_u16(b, q)
            q += 2
            ess = (x & 0x8000) != 0
            idx = x & 0x7fff
          else
            x = b[q]
            q += 1
            ess = (x & 0x80) != 0
            idx = x & 0x7f
          if idx > 0 && idx <= props.size
            pr = props[idx - 1]
            # share the parsed fields, but record essential per association
            p2 = HeifProp.new(pr.type, pr.f)
            p2.essential = ess
            it.props.push(p2)
          j += 1
        k += 1
  nil

-> hf_parse_prop(b, t, o, e)
  h = {}
  case t
    when "ispe"
      h[:w] = hf_u32(b, o + 4)
      h[:h] = hf_u32(b, o + 8)
    when "pixi"
      n = b[o + 4]
      bits = []
      j = 0
      while j < n
        bits.push(b[o + 5 + j])
        j += 1
      h[:bits] = bits
    when "colr"
      ct = hf_tag(b, o)
      h[:kind] = ct
      if ct == "nclx"
        h[:cp] = hf_u16(b, o + 4)
        h[:tc] = hf_u16(b, o + 6)
        h[:mc] = hf_u16(b, o + 8)
        h[:full] = (b[o + 10] & 0x80) != 0
      elsif ct == "rICC" || ct == "prof"
        h[:icc] = hf_slice(b, o + 4, e - o - 4)
    when "irot"
      h[:angle] = b[o] & 3
    when "imir"
      h[:axis] = b[o] & 1
    when "clap"
      h[:wn] = hf_u32(b, o)
      h[:wd] = hf_u32(b, o + 4)
      h[:hn] = hf_u32(b, o + 8)
      h[:hd] = hf_u32(b, o + 12)
      h[:xn] = hf_i32(b, o + 16)
      h[:xd] = hf_u32(b, o + 20)
      h[:yn] = hf_i32(b, o + 24)
      h[:yd] = hf_u32(b, o + 28)
    when "auxC"
      r = hf_cstr(b, o + 4, e)
      h[:urn] = r[0]
    when "av1C", "hvcC"
      h[:data] = hf_slice(b, o, e - o)
    when "lsel"
      h[:layer] = hf_u16(b, o)
  HeifProp.new(t, h)

# The bytes of an item (all extents, construction method 0 = file, 1 = idat).
-> heif_item_data(f, it)
  b = f.bytes
  total = 0
  it.extents.each ->(x) total += x[1]
  if it.extents.size == 1 && it.extents[0][1] == 0
    # length 0: to the end of the file / idat
    src_end = it.method == 1 ? f.idat[1] - f.idat[0] : b.size
    total = src_end - it.base - it.extents[0][0]
    it.extents = [[it.extents[0][0], total]]
  out = ByteArray.new(total)
  d = 0
  it.extents.each ->(x)
    o = it.base + x[0]
    if it.method == 1
      raise HeifError.new("heif: idat item without idat") if f.idat == nil
      o += f.idat[0]
      raise HeifError.new("heif: idat extent out of range") if o + x[1] > f.idat[1]
    elsif it.method != 0
      raise HeifError.new("heif: unsupported construction method")
    raise HeifError.new("heif: extent out of range") if o < 0 || o + x[1] > b.size
    hf_copy(b, o, out, d, x[1])
    d += x[1]
  out

# ---------------------------------------------------------------- moov (first sample)

# For sequence files with no usable meta: [codec 4cc, config bytes, sample bytes, w, h].
-> hf_parse_moov(b, o, e)
  hf_boxes(b, o, e).each ->(tk)
    if tk[0] == "trak"
      r = hf_parse_trak(b, tk[1], tk[2])
      return r if r != nil
  nil

-> hf_child(b, bx, path)
  cur = bx
  path.each ->(t)
    cur = cur == nil ? nil : hf_find(hf_boxes(b, cur[1], cur[2]), t)
  cur

-> hf_parse_trak(b, o, e)
  tr = ["trak", o, e]
  hd = hf_child(b, tr, ["mdia", "hdlr"])
  return nil if hd == nil
  h = hf_tag(b, hd[1] + 8)
  return nil if h != "pict" && h != "vide"
  stbl = hf_child(b, tr, ["mdia", "minf", "stbl"])
  return nil if stbl == nil
  kids = hf_boxes(b, stbl[1], stbl[2])
  sd = hf_find(kids, "stsd")
  return nil if sd == nil
  ents = hf_boxes(b, sd[1] + 8, sd[2])
  return nil if ents.size == 0
  en = ents[0]
  codec = en[0]
  w = hf_u16(b, en[1] + 24)
  ht = hf_u16(b, en[1] + 26)
  sub = hf_boxes(b, en[1] + 78, en[2])
  cfg = nil
  sub.each ->(s)
    cfg = hf_slice(b, s[1], s[2] - s[1]) if s[0] == "av1C" || s[0] == "hvcC"
  sz = hf_find(kids, "stsz")
  return nil if sz == nil
  ssz = hf_u32(b, sz[1] + 4)
  ssz = hf_u32(b, sz[1] + 12) if ssz == 0
  co = hf_find(kids, "stco")
  off = 0
  if co != nil
    off = hf_u32(b, co[1] + 8)
  else
    c6 = hf_find(kids, "co64")
    return nil if c6 == nil
    off = hf_u64(b, c6[1] + 8)
  return nil if off + ssz > b.size
  [codec, cfg, hf_slice(b, off, ssz), w, ht]

# ---------------------------------------------------------------- decoding

-> hf_check_essential(it)
  it.props.each ->(p)
    if p.essential
      known = ["ispe", "pixi", "colr", "irot", "imir", "clap", "auxC", "av1C", "hvcC", "lsel", "a1op", "a1lx", "oinf", "rloc", "tols", "udes", "rref"]
      raise HeifError.new("heif: unsupported essential property " + p.type) if !known.include?(p.type)
  nil

# Decode a coded or derived (grid, iden) item to a HeifPic.
-> hf_decode_item(f, it, depth)
  raise HeifError.new("heif: derivation too deep") if depth > 8
  hf_check_essential(it)
  if it.type == "grid"
    return hf_decode_grid(f, it, depth)
  if it.type == "iden"
    src = it.ref("dimg")
    raise HeifError.new("heif: iden without source") if src.size != 1
    return hf_decode_item(f, f.item(src[0]), depth + 1)
  dec = HEIF_CODECS[it.type]
  if dec == nil && it.type == "hev1"
    dec = HEIF_CODECS["hvc1"]
  raise HeifError.new("heif: unsupported item type " + it.type) if dec == nil
  dec.call(f, it, heif_item_data(f, it))

-> hf_decode_grid(f, it, depth)
  d = heif_item_data(f, it)
  raise HeifError.new("heif: short grid") if d.size < 8
  fl = d[1]
  rows = d[2] + 1
  cols = d[3] + 1
  ow = 0
  oh = 0
  if (fl & 1) != 0
    ow = hf_u32(d, 4)
    oh = hf_u32(d, 8)
  else
    ow = hf_u16(d, 4)
    oh = hf_u16(d, 6)
  tiles = it.ref("dimg")
  raise HeifError.new("heif: grid has [tiles.size] tiles, wants [rows * cols]") if tiles.size != rows * cols
  raise HeifError.new("heif: grid too large") if ow <= 0 || oh <= 0 || ow * oh > 400000000
  out = nil
  tw = 0
  th = 0
  r = 0
  while r < rows
    c = 0
    while c < cols
      t = f.item(tiles[r * cols + c])
      raise HeifError.new("heif: missing tile") if t == nil
      p = hf_decode_item(f, t, depth + 1)
      if out == nil
        tw = p.width
        th = p.height
        out = HeifPic.new(ow, oh, p.bit_depth, p.ssx, p.ssy, p.mono)
        out.cicp = p.cicp
        out.tile_w = tw
        out.tile_h = th
      raise HeifError.new("heif: grid tiles differ") if p.bit_depth != out.bit_depth || p.ssx != out.ssx || p.ssy != out.ssy || p.mono != out.mono
      hf_blit_pic(p, out, c * tw, r * th)
      c += 1
    r += 1
  out

# Copy tile p into out at (x0, y0), clipped.
-> hf_blit_pic(p, out, x0, y0)
  np = out.planes.size
  k = 0
  while k < np
    sx = k == 0 ? 0 : out.ssx
    sy = k == 0 ? 0 : out.ssy
    hf_blit_plane(p.planes[k], p.pw(k), p.ph(k), out.planes[k], out.pw(k), out.ph(k), x0 >> sx, y0 >> sy)
    k += 1
  nil

-> hf_blit_plane(src, sw, sh, dst, dw, dh, x0, y0) (u16[] i64 i64 u16[] i64 i64 i64 i64) i64
  w = sw
  w = dw - x0 if x0 + w > dw
  h = sh
  h = dh - y0 if y0 + h > dh
  y = 0 ## i64
  while y < h
    so = y * sw
    d0 = (y0 + y) * dw + x0
    x = 0 ## i64
    while x < w
      dst[d0 + x] = src[so + x]
      x += 1
    y += 1
  0

# The alpha auxiliary item for item id, or nil.
-> hf_alpha_item(f, id)
  f.referrers(id, "auxl").each ->(a)
    c = a.prop("auxC")
    if c != nil
      u = c.f[:urn]
      return a if u == "urn:mpeg:mpegB:cicp:systems:auxiliary:alpha" || u == "urn:mpeg:hevc:2015:auxid:1"
  nil

-> heif_decode(bytes)
  f = heif_parse(bytes)
  it = f.primary == nil ? nil : f.item(f.primary)
  if it == nil
    return hf_decode_track(f) if f.moov_track != nil
    raise HeifError.new("heif: no primary item")
  pic = hf_decode_item(f, it, 0)
  # the ispe of a grid / coded item is the authoritative size
  colr = hf_item_colr(f, it)
  dw = pic.width
  dh = pic.height
  cl = it.prop("clap")
  if cl != nil && cl.f[:wd] > 0 && cl.f[:hd] > 0
    dw = cl.f[:wn] / cl.f[:wd]
    dh = cl.f[:hn] / cl.f[:hd]
  bm = heif_pic_to_bitmap(pic, colr[0], colr[1], dw, dh, (f.brands.include?("miaf") && f.major != "msf1") ? 6 : 1)
  ai = hf_alpha_item(f, it.id)
  if ai != nil
    ap = hf_decode_item(f, ai, 0)
    premult = f.referrers(ai.id, "prem").size > 0 || it.ref("prem").include?(ai.id)
    acolr = hf_item_colr(f, ai)
    full = true
    if acolr[0] != nil
      full = acolr[0][3]
    elsif ap.cicp != nil
      full = ap.cicp[3]
    heif_apply_alpha(bm, ap, full, premult)
  hf_apply_transforms(bm, it)

-> hf_decode_track(f)
  t = f.moov_track
  dec = HEIF_CODECS["track:" + t[0]]
  raise HeifError.new("heif: unsupported track codec " + t[0]) if dec == nil
  pic = dec.call(t[1], t[2])
  heif_pic_to_bitmap(pic, nil, nil)

# [nclx [cp, tc, mc, full] or nil, icc bytes or nil] for an item; a grid's own
# colr wins, else the first tile's.
-> hf_item_colr(f, it)
  nclx = nil
  icc = nil
  it.props.each ->(p)
    if p.type == "colr"
      if p.f[:kind] == "nclx"
        nclx = [p.f[:cp], p.f[:tc], p.f[:mc], p.f[:full]] if nclx == nil
      elsif p.f[:icc] != nil
        icc = p.f[:icc] if icc == nil
  if nclx == nil && icc == nil && (it.type == "grid" || it.type == "iden")
    t = it.ref("dimg")
    if t.size > 0 && f.item(t[0]) != nil
      return hf_item_colr(f, f.item(t[0]))
  [nclx, icc]

# ---------------------------------------------------------------- transforms

-> hf_apply_transforms(bm, it)
  i = 0
  while i < it.props.size
    p = it.props[i]
    if p.type == "clap"
      bm = hf_clap(bm, p.f)
    elsif p.type == "irot"
      bm = hf_rotate(bm, p.f[:angle])
    elsif p.type == "imir"
      bm = hf_mirror(bm, p.f[:axis])
    i += 1
  bm

-> hf_clap(bm, c)
  return bm if c[:wd] == 0 || c[:hd] == 0 || c[:xd] == 0 || c[:yd] == 0
  cw = c[:wn] / c[:wd]
  ch = c[:hn] / c[:hd]
  # centre offset: (W-1)/2 + horizOff, left = centre - (cw-1)/2, in exact rationals
  # left*2*xd*... computed with integers: left = ((W - cw) * xd + 2 * xn) / (2 * xd)
  left = ((bm.width - cw) * c[:xd] + 2 * c[:xn] + c[:xd]) / (2 * c[:xd])
  top = ((bm.height - ch) * c[:yd] + 2 * c[:yn] + c[:yd]) / (2 * c[:yd])
  return bm if cw <= 0 || ch <= 0 || left < 0 || top < 0 || left + cw > bm.width || top + ch > bm.height
  return bm if cw == bm.width && ch == bm.height
  out = Bitmap.new(cw, ch)
  y = 0
  while y < ch
    hf_copy(bm.rgba, ((top + y) * bm.width + left) * 4, out.rgba, y * cw * 4, cw * 4)
    y += 1
  out

# irot: anticlockwise rotation by angle * 90 degrees.
-> hf_rotate(bm, angle)
  return bm if angle == 0
  w = bm.width
  h = bm.height
  nw = angle == 2 ? w : h
  nh = angle == 2 ? h : w
  out = Bitmap.new(nw, nh)
  hf_rot_px(bm.rgba, w, h, out.rgba, angle)
  out

-> hf_rot_px(src, w, h, dst, angle) (u8[] i64 i64 u8[] i64) i64
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      d = 0 ## i64
      if angle == 1
        # anticlockwise 90: (x, y) -> (y, w-1-x), new width h
        d = ((w - 1 - x) * h + y) * 4
      elsif angle == 2
        d = ((h - 1 - y) * w + (w - 1 - x)) * 4
      else
        # 270 anticlockwise = 90 clockwise: (x, y) -> (h-1-y, x)
        d = (x * h + (h - 1 - y)) * 4
      s = (y * w + x) * 4
      dst[d] = src[s]
      dst[d + 1] = src[s + 1]
      dst[d + 2] = src[s + 2]
      dst[d + 3] = src[s + 3]
      x += 1
    y += 1
  0

# imir axis 0: mirror top-to-bottom; 1: mirror left-to-right (what libavif,
# libheif and the link-u transform tests use).
-> hf_mirror(bm, axis)
  out = Bitmap.new(bm.width, bm.height)
  hf_mir_px(bm.rgba, bm.width, bm.height, out.rgba, axis)
  out

-> hf_mir_px(src, w, h, dst, axis) (u8[] i64 i64 u8[] i64) i64
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      s = (y * w + x) * 4
      d = 0 ## i64
      if axis == 1
        d = (y * w + (w - 1 - x)) * 4
      else
        d = ((h - 1 - y) * w + x) * 4
      dst[d] = src[s]
      dst[d + 1] = src[s + 1]
      dst[d + 2] = src[s + 2]
      dst[d + 3] = src[s + 3]
      x += 1
    y += 1
  0

img_register("avif", ->(b) heif_avif_sniff?(b), ->(b) heif_decode(b))
img_register("heic", ->(b) heif_heic_sniff?(b), ->(b) heif_decode(b))
