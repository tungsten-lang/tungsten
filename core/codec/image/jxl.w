# core/codec/image/jxl — JPEG XL decoder (ISO/IEC 18181), pure Tungsten.
#
# jxl_decode(bytes) → Bitmap. Handles the naked codestream (FF 0A) and the
# ISOBMFF container (jxlc / jxlp boxes). Decodes modular and VarDCT frames,
# LF frames, patches, splines, noise, restoration filters, upsampling,
# blending and animation, then converts XYB / YCbCr / RGB to 8-bit sRGB
# (HDR transfer functions are tone-mapped down) and applies the orientation.
#
# Files: jxl_ans (bit reader, entropy codes), jxl_modular (MA trees,
# predictors, transforms), jxl_vardct (VarDCT: quantisation, coefficient
# orders, block decoding, IDCT), jxl_render (filters, features, colour).

use core/codec/image
use jxl_ans
use jxl_modular
use jxl_vardct
use jxl_render
use jxl_icc
use icc

# ---------------------------------------------------------------- container

-> jxl_sniff?(b)
  n = b.size
  return true if n >= 2 && b[0] == 0xFF && b[1] == 0x0A
  n >= 12 && b[0] == 0 && b[1] == 0 && b[2] == 0 && b[3] == 12 && b[4] == 0x4A && b[5] == 0x58 && b[6] == 0x4C && b[7] == 0x20 && b[8] == 0x0D && b[9] == 0x0A && b[10] == 0x87 && b[11] == 0x0A

-> jxl_u8(b)
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

-> jxl_be32(b, p)
  (b[p] << 24) | (b[p + 1] << 16) | (b[p + 2] << 8) | b[p + 3]

-> jxl_copy_bytes(dst, doff, s, soff, n) (u8[] i64 u8[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[doff + i] = s[soff + i]
    i += 1
  0

# Extract the codestream from the container (or return the naked stream).
-> jxl_codestream(b)
  return b if b[0] == 0xFF && b[1] == 0x0A
  parts = []
  total = 0
  p = 0
  n = b.size
  while p + 8 <= n
    sz = jxl_be32(b, p)
    ty = jxl_be32(b, p + 4)
    hdr = 8
    if sz == 1
      jxl_fail("truncated box") if p + 16 > n
      sz = (jxl_be32(b, p + 8) << 32) | jxl_be32(b, p + 12)
      hdr = 16
    elsif sz == 0
      sz = n - p
    jxl_fail("bad box size") if sz < hdr
    e = p + sz
    e = n if e > n
    if ty == 0x6A786C63
      parts.push([p + hdr, e - p - hdr])
      total += e - p - hdr
    elsif ty == 0x6A786C70
      parts.push([p + hdr + 4, e - p - hdr - 4])
      total += e - p - hdr - 4
    p += sz
  jxl_fail("no codestream box") if parts.size == 0
  return b.slice_view(parts[0][0], parts[0][1]) if parts.size == 1 && false
  cs = u8[total]
  q = 0
  parts.each ->(pt)
    jxl_copy_bytes(cs, q, b, pt[0], pt[1])
    q += pt[1]
  cs

# ---------------------------------------------------------------- headers

+ JxMeta
  rw :width, :height, :orientation, :bpp, :exp_bits, :fp, :mod16, :ec, :xyb
  rw :cspace, :want_icc, :tf, :gamma, :white, :prim, :intensity, :min_nits
  rw :anim, :tps_num, :tps_den, :num_loops, :timecodes, :preview, :pw, :ph
  rw :opsin_inv, :opsin_bias, :quant_bias, :quant_bias_num, :up2, :up4, :up8
  rw :icc, :linear_below, :rel_to_max, :icc_prof

  -> new
    @orientation = 1
    @bpp = 8
    @exp_bits = 0
    @fp = false
    @mod16 = true
    @ec = []
    @xyb = true
    @cspace = 0
    @want_icc = false
    @tf = 13
    @gamma = 0
    @white = 1
    @prim = 1
    @intensity = ~255.0
    @min_nits = ~0.0
    @anim = false
    @num_loops = 0
    @timecodes = false
    @preview = false
    @opsin_inv = [~11.031566901960783, ~-9.866943921568629, ~-0.16462299647058826, ~-3.254147380392157, ~4.418770392156863, ~-0.16462299647058826, ~-3.6588512862745097, ~2.7129230470588235, ~1.9459282392156863]
    @opsin_bias = [~-0.0037930732552754493, ~-0.0037930732552754493, ~-0.0037930732552754493]
    @quant_bias = [~1.0 - ~0.05465007330715401, ~1.0 - ~0.07005449891748593, ~1.0 - ~0.049935103337343655]
    @quant_bias_num = ~0.145
    @up2 = nil
    @up4 = nil
    @up8 = nil
    @icc = nil

  -> gray?
    @cspace == 1

  -> alpha_index
    i = 0
    while i < @ec.size
      return i if @ec[i][:type] == 0
      i += 1
    -1

-> jxl_size_header(src, br)
  div8 = jb_u(src, br, 1)
  h = 0
  if div8 == 1
    h = (jb_u(src, br, 5) + 1) * 8
  else
    h = jb_u32(src, br, 1, 9, 1, 13, 1, 18, 1, 30)
  ratio = jb_u(src, br, 3)
  w = 0
  if ratio == 0
    if div8 == 1
      w = (jb_u(src, br, 5) + 1) * 8
    else
      w = jb_u32(src, br, 1, 9, 1, 13, 1, 18, 1, 30)
  else
    w = jxl_ratio_width(h, ratio)
  [w, h]

-> jxl_ratio_width(h, ratio)
  return h if ratio == 1
  return h * 6 / 5 if ratio == 2
  return h * 4 / 3 if ratio == 3
  return h * 3 / 2 if ratio == 4
  return h * 16 / 9 if ratio == 5
  return h * 5 / 4 if ratio == 6
  h * 2

-> jxl_bit_depth(src, br)
  if jb_u(src, br, 1) == 1
    bpp = jb_u32(src, br, 32, 0, 16, 0, 24, 0, 1, 6)
    eb = jb_u(src, br, 4) + 1
    return [bpp, eb, true]
  [jb_u32(src, br, 8, 0, 10, 0, 12, 0, 1, 6), 0, false]

-> jxl_skip_name(src, br)
  len = jb_u32(src, br, 0, 0, 0, 4, 16, 5, 48, 10)
  jb_skip_bits(src, br, len * 8)
  len

-> jxl_custom_xy(src, br)
  x = jx_unpack_signed(jb_u32(src, br, 0, 19, 0x80000, 19, 0x100000, 20, 0x200000, 21))
  y = jx_unpack_signed(jb_u32(src, br, 0, 19, 0x80000, 19, 0x100000, 20, 0x200000, 21))
  [x / ~100000.0, y / ~100000.0]

-> jxl_read_ec(src, br)
  if jb_u(src, br, 1) == 1
    return {type: 0, bpp: 8, exp_bits: 0, fp: false, dim_shift: 0, premul: false}
  ty = jb_enum(src, br)
  bd = jxl_bit_depth(src, br)
  ds = jb_u32(src, br, 0, 0, 3, 0, 4, 0, 1, 3)
  jxl_skip_name(src, br)
  premul = false
  spot = nil
  if ty == 0
    premul = jb_u(src, br, 1) == 1
  elsif ty == 2
    spot = [jb_f16(src, br), jb_f16(src, br), jb_f16(src, br), jb_f16(src, br)]
  elsif ty == 5
    jb_u32(src, br, 1, 0, 0, 2, 3, 4, 19, 8)
  {type: ty, bpp: bd[0], exp_bits: bd[1], fp: bd[2], dim_shift: ds, premul: premul, spot: spot}

-> jxl_f16_list(src, br, n)
  out = []
  i = 0
  while i < n
    out.push(jb_f16(src, br))
    i += 1
  out

-> jxl_read_metadata(src, br)
  m = JxMeta.new
  sz = jxl_size_header(src, br)
  m.width = sz[0]
  m.height = sz[1]
  if jb_u(src, br, 1) == 0
    extra = jb_u(src, br, 1)
    if extra == 1
      m.orientation = jb_u(src, br, 3) + 1
      jxl_size_header(src, br) if jb_u(src, br, 1) == 1
      if jb_u(src, br, 1) == 1
        m.preview = true
        div8 = jb_u(src, br, 1)
        ph = 0
        if div8 == 1
          ph = jb_u32(src, br, 16, 0, 32, 0, 1, 5, 33, 9) * 8
        else
          ph = jb_u32(src, br, 1, 6, 65, 8, 321, 10, 1345, 12)
        ratio = jb_u(src, br, 3)
        pw = 0
        if ratio == 0
          if div8 == 1
            pw = jb_u32(src, br, 16, 0, 32, 0, 1, 5, 33, 9) * 8
          else
            pw = jb_u32(src, br, 1, 6, 65, 8, 321, 10, 1345, 12)
        else
          pw = jxl_ratio_width(ph, ratio)
        m.pw = pw
        m.ph = ph
      if jb_u(src, br, 1) == 1
        m.anim = true
        m.tps_num = jb_u32(src, br, 100, 0, 1000, 0, 1, 10, 1, 30)
        m.tps_den = jb_u32(src, br, 1, 0, 1001, 0, 1, 8, 1, 10)
        m.num_loops = jb_u32(src, br, 0, 0, 0, 3, 0, 16, 0, 32)
        m.timecodes = jb_u(src, br, 1) == 1
    bd = jxl_bit_depth(src, br)
    m.bpp = bd[0]
    m.exp_bits = bd[1]
    m.fp = bd[2]
    m.mod16 = jb_u(src, br, 1) == 1
    nec = jb_u32(src, br, 0, 0, 1, 0, 2, 4, 1, 12)
    i = 0
    while i < nec
      m.ec.push(jxl_read_ec(src, br))
      i += 1
    m.xyb = jb_u(src, br, 1) == 1
    if jb_u(src, br, 1) == 0
      m.want_icc = jb_u(src, br, 1) == 1
      m.cspace = jb_enum(src, br)
      if !m.want_icc
        if m.cspace != 2
          m.white = jb_enum(src, br)
          m.white = jxl_custom_xy(src, br) if m.white == 2
          if m.cspace != 1
            m.prim = jb_enum(src, br)
            if m.prim == 2
              m.prim = [jxl_custom_xy(src, br), jxl_custom_xy(src, br), jxl_custom_xy(src, br)]
        if m.cspace != 2
          if jb_u(src, br, 1) == 1
            m.gamma = jb_u(src, br, 24)
            m.tf = 0
          else
            m.tf = jb_enum(src, br)
        jb_enum(src, br)
    if extra == 1
      if jb_u(src, br, 1) == 0
        m.intensity = jb_f16(src, br)
        m.min_nits = jb_f16(src, br)
        m.rel_to_max = jb_u(src, br, 1) == 1
        m.linear_below = jb_f16(src, br)
    jb_extensions(src, br)
  # CustomTransformData
  if jb_u(src, br, 1) == 0
    if m.xyb
      if jb_u(src, br, 1) == 0
        m.opsin_inv = jxl_f16_list(src, br, 9)
        m.opsin_bias = jxl_f16_list(src, br, 3)
        m.quant_bias = jxl_f16_list(src, br, 3)
        m.quant_bias_num = jb_f16(src, br)
    cw = jb_u(src, br, 3)
    m.up2 = jxl_f16_list(src, br, 15) if (cw & 1) != 0
    m.up4 = jxl_f16_list(src, br, 55) if (cw & 2) != 0
    m.up8 = jxl_f16_list(src, br, 210) if (cw & 4) != 0
  m

# Decode (and keep) the entropy-coded ICC profile stream.
-> jxl_read_icc(src, br)
  enc_size = jb_u64(src, br)
  cs = jx_read_code(src, br, 41)
  es = jx_stream(src, br, cs)
  win = jx_window(cs)
  out = u8[enc_size + 1]
  b1 = 0
  b2 = 0
  i = 0
  while i < enc_size
    ctx = 0
    if i > 128
      p = b1
      pp = b2
      if p < 16
        ctx = (p < 2) ? p + 3 : 5
      elsif p > 240
        ctx = 6 + (p == 255 ? 1 : 0)
      elsif (p | 32) >= 97 && (p | 32) <= 122
        ctx = 1
      elsif p == 44 || p == 46 || (p >= 48 && p < 58)
        ctx = 2
      else
        ctx = 8
      if pp < 16
        ctx += 16
      elsif pp > 240
        ctx += 24
      elsif (pp | 32) >= 97 && (pp | 32) <= 122
        ctx += 0
      elsif pp == 44 || pp == 46 || (pp >= 48 && pp < 58)
        ctx += 8
      else
        ctx += 32
    v = jx_decode(src, br, cs, es, win, ctx, 0)
    out[i] = v
    b2 = b1
    b1 = v
    i += 1
  jx_finish(src, br, cs, es)
  out

# Rebuild the ICC profile and parse it with the shared icc module (nil when
# it is not a profile core/codec/image/icc.w can apply; pixels are then shown unmanaged).
-> jxl_icc_profile(enc)
  prof = nil
  begin
    bytes = jxi_unpredict(enc, enc.size - 1)
    u = u8[bytes.size]
    i = 0
    while i < bytes.size
      u[i] = bytes[i]
      i += 1
    prof = icc_parse(u, 0, u.size)
  rescue e
    prof = nil
  prof

# ---------------------------------------------------------------- frame header

+ JxFrame
  rw :type, :modular, :flags, :ycbcr, :jpeg_up, :upsampling, :ec_up, :gshift
  rw :x_qm, :b_qm, :num_passes, :shift, :ds, :last_pass, :lf_level, :x0, :y0
  rw :width, :height, :blend, :ec_blend, :duration, :is_last, :save_as_ref
  rw :save_before_ct, :gab, :gab_w, :epf_iters, :epf_sharp, :epf_cs, :epf_qm
  rw :epf_p0, :epf_p2, :epf_bsad, :epf_sigma_mod, :full_frame, :name_len
  rw :gdim, :gw, :gh, :ggw, :ggh, :fw, :fh, :timecode

  -> noise?
    (@flags & 1) != 0
  -> patches?
    (@flags & 2) != 0
  -> splines?
    (@flags & 16) != 0
  -> use_lf_frame?
    (@flags & 32) != 0
  -> skip_lf_smooth?
    (@flags & 128) != 0

-> jxl_blend_info(src, br, nec, full)
  mode = jb_u32(src, br, 0, 0, 1, 0, 2, 0, 3, 2)
  alpha = 0
  clamp = 0
  srcref = 0
  if nec > 0 && (mode == 2 || mode == 3)
    alpha = jb_u32(src, br, 0, 0, 1, 0, 2, 0, 3, 3)
    clamp = jb_u(src, br, 1)
  elsif mode == 4
    clamp = jb_u(src, br, 1)
  if mode != 0 || !full
    srcref = jb_u(src, br, 2)
  [mode, alpha, clamp, srcref]

-> jxl_read_frame_header(src, br, m)
  f = JxFrame.new
  jb_align(br)
  f.type = 0
  f.modular = false
  f.flags = 0
  f.ycbcr = false
  f.jpeg_up = [0, 0, 0]
  f.upsampling = 1
  f.ec_up = []
  m.ec.each ->(e)
    f.ec_up.push(1 << e[:dim_shift])
  f.gshift = 1
  f.x_qm = 3
  f.b_qm = 2
  f.num_passes = 1
  f.shift = [0]
  f.ds = []
  f.last_pass = []
  f.lf_level = 0
  f.x0 = 0
  f.y0 = 0
  f.width = m.width
  f.height = m.height
  f.blend = [0, 0, 0, 0]
  f.ec_blend = []
  m.ec.each ->(e)
    f.ec_blend.push([0, 0, 0, 0])
  f.duration = 0
  f.timecode = 0
  f.is_last = true
  f.save_as_ref = 0
  f.save_before_ct = false
  f.gab = true
  f.gab_w = [~0.115169525, ~0.061248592, ~0.115169525, ~0.061248592, ~0.115169525, ~0.061248592]
  f.epf_iters = 2
  f.epf_sharp = [~0.0, ~1.0 / ~7.0, ~2.0 / ~7.0, ~3.0 / ~7.0, ~4.0 / ~7.0, ~5.0 / ~7.0, ~6.0 / ~7.0, ~1.0]
  f.epf_cs = [~40.0, ~5.0, ~3.5]
  f.epf_qm = ~0.46
  f.epf_p0 = ~0.9
  f.epf_p2 = ~6.5
  f.epf_bsad = ~2.0 / ~3.0
  f.epf_sigma_mod = ~1.0
  f.full_frame = true
  nec = m.ec.size
  if jb_u(src, br, 1) == 0
    f.type = jb_u32(src, br, 0, 0, 1, 0, 2, 0, 3, 0)
    f.modular = jb_u(src, br, 1) == 1
    f.flags = jb_u64(src, br)
    if !m.xyb
      f.ycbcr = jb_u(src, br, 1) == 1
    if (f.flags & 32) == 0
      if f.ycbcr
        f.jpeg_up = [jb_u(src, br, 2), jb_u(src, br, 2), jb_u(src, br, 2)]
      f.upsampling = 1 << jb_u(src, br, 2)
      i = 0
      while i < nec
        ds = m.ec[i][:dim_shift]
        f.ec_up[i] = (1 << jb_u(src, br, 2)) << ds
        i += 1
    if f.modular
      f.gshift = jb_u(src, br, 2)
    elsif m.xyb
      f.x_qm = jb_u(src, br, 3)
      f.b_qm = jb_u(src, br, 3)
    if f.type != 2
      f.num_passes = jb_u32(src, br, 1, 0, 2, 0, 3, 0, 4, 3)
      if f.num_passes != 1
        nds = jb_u32(src, br, 0, 0, 1, 0, 2, 0, 3, 1)
        f.shift = []
        i = 0
        while i < f.num_passes - 1
          f.shift.push(jb_u(src, br, 2))
          i += 1
        f.shift.push(0)
        i = 0
        while i < nds
          f.ds.push(1 << jb_u(src, br, 2))
          i += 1
        i = 0
        while i < nds
          f.last_pass.push(jb_u32(src, br, 0, 0, 1, 0, 2, 0, 0, 3))
          i += 1
    if f.type == 1
      f.lf_level = jb_u32(src, br, 1, 0, 2, 0, 3, 0, 4, 0)
    else
      if jb_u(src, br, 1) == 1
        if f.type == 0 || f.type == 3
          f.x0 = jx_unpack_signed(jb_u32(src, br, 0, 8, 256, 11, 2304, 14, 18688, 30))
          f.y0 = jx_unpack_signed(jb_u32(src, br, 0, 8, 256, 11, 2304, 14, 18688, 30))
        f.width = jb_u32(src, br, 0, 8, 256, 11, 2304, 14, 18688, 30)
        f.height = jb_u32(src, br, 0, 8, 256, 11, 2304, 14, 18688, 30)
        if f.type == 0 || f.type == 3
          f.full_frame = f.x0 <= 0 && f.y0 <= 0 && f.width + f.x0 >= m.width && f.height + f.y0 >= m.height
    if f.type == 0 || f.type == 3
      f.blend = jxl_blend_info(src, br, nec, f.full_frame)
      i = 0
      while i < nec
        f.ec_blend[i] = jxl_blend_info(src, br, nec, f.full_frame)
        i += 1
      if m.anim
        f.duration = jb_u32(src, br, 0, 0, 1, 0, 0, 8, 0, 32)
        f.timecode = jb_u(src, br, 32) if m.timecodes
      f.is_last = jb_u(src, br, 1) == 1
    else
      f.is_last = false
    if f.type != 1 && !f.is_last
      f.save_as_ref = jb_u32(src, br, 0, 0, 1, 0, 2, 0, 3, 0)
    if f.type == 1
      f.save_before_ct = true
    else
      can_ref = !f.is_last && (f.duration == 0 || f.save_as_ref != 0)
      if can_ref && f.blend[0] == 0 && f.full_frame && (f.type == 0 || f.type == 3)
        f.save_before_ct = jb_u(src, br, 1) == 1
      elsif f.type == 2
        f.save_before_ct = jb_u(src, br, 1) == 1
    jxl_skip_name(src, br)
    # RestorationFilter
    if jb_u(src, br, 1) == 0
      f.gab = jb_u(src, br, 1) == 1
      if f.gab && jb_u(src, br, 1) == 1
        f.gab_w = jxl_f16_list(src, br, 6)
      f.epf_iters = jb_u(src, br, 2)
      if f.epf_iters > 0
        if !f.modular && jb_u(src, br, 1) == 1
          f.epf_sharp = jxl_f16_list(src, br, 8)
        if jb_u(src, br, 1) == 1
          f.epf_cs = jxl_f16_list(src, br, 3)
          jb_u(src, br, 32)
        if jb_u(src, br, 1) == 1
          f.epf_qm = jb_f16(src, br) if !f.modular
          f.epf_p0 = jb_f16(src, br)
          f.epf_p2 = jb_f16(src, br)
          f.epf_bsad = jb_f16(src, br)
        f.epf_sigma_mod = jb_f16(src, br) if f.modular
      jb_extensions(src, br)
    jb_extensions(src, br)
  # derived dimensions
  f.gdim = 128 << f.gshift
  up = f.upsampling
  fw = f.width
  fh = f.height
  if f.type == 1
    sc = 1 << (3 * f.lf_level)
    fw = (m.width + sc - 1) / sc
    fh = (m.height + sc - 1) / sc
    f.width = fw
    f.height = fh
  f.fw = (fw + up - 1) / up
  f.fh = (fh + up - 1) / up
  f.gw = (f.fw + f.gdim - 1) / f.gdim
  f.gh = (f.fh + f.gdim - 1) / f.gdim
  f.ggw = (f.fw + 8 * f.gdim - 1) / (8 * f.gdim)
  f.ggh = (f.fh + 8 * f.gdim - 1) / (8 * f.gdim)
  f

# [minShift, maxShift] of modular channels decoded in pass p.
-> jxl_ds_bracket(f, pass)
  maxs = 2
  mins = 3
  i = 0
  while true
    j = 0
    while j < f.ds.size
      if i == f.last_pass[j]
        d = f.ds[j]
        mins = 3 if d == 8
        mins = 2 if d == 4
        mins = 1 if d == 2
        mins = 0 if d == 1
      j += 1
    mins = 0 if i == f.num_passes - 1
    return [mins, maxs] if i == pass
    maxs = mins - 1
    i += 1
  [0, 2]

# TOC → [[offset, size] per section in logical order].
-> jxl_read_toc(src, br, f)
  ng = f.gw * f.gh
  nlf = f.ggw * f.ggh
  nsec = 1
  if !(f.num_passes == 1 && ng == 1)
    nsec = 2 + nlf + f.num_passes * ng
  perm = nil
  if jb_u(src, br, 1) == 1
    cs = jx_read_code(src, br, 8)
    es = jx_stream(src, br, cs)
    win = jx_window(cs)
    perm = jxl_read_perm(src, br, cs, es, win, nsec, 0)
    jx_finish(src, br, cs, es)
  jb_align(br)
  sizes = []
  i = 0
  while i < nsec
    sizes.push(jb_u32(src, br, 0, 10, 1024, 14, 17408, 22, 4211712, 30))
    i += 1
  jb_align(br)
  base = jb_tell(br) / 8
  offs = []
  p = base
  i = 0
  while i < nsec
    offs.push(p)
    p += sizes[i]
    i += 1
  secs = []
  i = 0
  while i < nsec
    secs.push([offs[i], sizes[i]])
    i += 1
  if perm != nil
    # section i in logical order is stored at position perm[i]
    out = []
    i = 0
    while i < nsec
      out.push(secs[perm[i]])
      i += 1
    secs = out
  [secs, p]

# Lehmer-coded permutation of size n (skip leading entries fixed).
-> jxl_read_perm(src, br, cs, es, win, size, skip)
  e = jx_decode(src, br, cs, es, win, jxl_ctx_min7(size), 0)
  jxl_fail("permutation") if e > size - skip
  lehmer = []
  prev = 0
  i = 0
  while i < e
    prev = jx_decode(src, br, cs, es, win, jxl_ctx_min7(prev), 0)
    jxl_fail("permutation") if prev >= size - (skip + i)
    lehmer.push(prev)
    i += 1
  # decode Lehmer code into a permutation
  avail = []
  i = 0
  while i < size
    avail.push(i)
    i += 1
  perm = []
  i = 0
  while i < skip
    perm.push(avail.delete_at(0))
    i += 1
  i = 0
  while i < size - skip
    k = 0
    k = lehmer[i] if i < lehmer.size
    perm.push(avail.delete_at(k))
    i += 1
  perm

-> jxl_ctx_min7(x)
  c = jx_ceil_log2(x + 1)
  c = 7 if c > 7
  c

# ---------------------------------------------------------------- frame decode

# Per-frame decoding state shared by the modular and VarDCT paths.
+ JxDec
  rw :src, :m, :f, :gtree, :gimg, :global_tr, :planes, :ecplanes, :vd, :patches
  rw :splines, :noise, :refs, :lf_frames, :lf_dq, :vis_idx, :nonvis_idx

  -> new(@src, @m)
    @refs = [nil, nil, nil, nil]
    @lf_frames = [nil, nil, nil, nil]
    @vis_idx = 0
    @nonvis_idx = 0

-> jxl_section_br(src, sec)
  jb_new(sec[0], sec[0] + sec[1])

# Decodes one frame; returns the frame's float planes (color 3 + extra).
-> jxl_decode_frame(d, br)
  src = d.src
  m = d.m
  f = jxl_read_frame_header(src, br, m)
  d.f = f
  if (f.is_last || f.duration > 0) && (f.type == 0 || f.type == 3)
    d.vis_idx = d.vis_idx + 1
    d.nonvis_idx = 0
  else
    d.nonvis_idx = d.nonvis_idx + 1
  toc = jxl_read_toc(src, br, f)
  secs = toc[0]
  single = secs.size == 1
  lfg_br = jxl_section_br(src, secs[0])
  # LfGlobal
  jxl_lf_global(d, lfg_br)
  nlf = f.ggw * f.ggh
  ng = f.gw * f.gh
  # LF groups
  i = 0
  while i < nlf
    sbr = lfg_br
    sbr = jxl_section_br(src, secs[1 + i]) if !single
    jxl_lf_group(d, sbr, i)
    i += 1
  # HF global
  hbr = lfg_br
  hbr = jxl_section_br(src, secs[1 + nlf]) if !single
  jxv_hf_global(d, hbr) if !f.modular
  jxv_finalize_lf(d) if !f.modular
  # pass groups
  p = 0
  while p < f.num_passes
    g = 0
    while g < ng
      sbr = lfg_br
      sbr = jxl_section_br(src, secs[2 + nlf + p * ng + g]) if !single
      jxl_pass_group(d, sbr, p, g)
      g += 1
    p += 1
  jxl_finish_frame(d)
  [f, toc[1]]

-> jxl_lf_global(d, br)
  src = d.src
  m = d.m
  f = d.f
  d.patches = nil
  d.splines = nil
  d.noise = nil
  d.patches = jxr_read_patches(d, br) if f.patches?
  d.splines = jxr_read_splines(d, br) if f.splines?
  d.noise = jxr_read_noise(src, br) if f.noise?
  # LfChannelDequantization
  d.lf_dq = [~1.0 / ~4096.0, ~1.0 / ~512.0, ~1.0 / ~256.0]
  if jb_u(src, br, 1) == 0
    d.lf_dq = [jb_f16(src, br) / ~128.0, jb_f16(src, br) / ~128.0, jb_f16(src, br) / ~128.0]
  d.vd = nil
  jxv_lf_global(d, br) if !f.modular
  # global modular image
  nch = 0
  if f.modular
    nch = 3
    nch = 1 if m.gray? && !f.ycbcr && !m.xyb
  chs = []
  i = 0
  while i < nch
    w = f.fw
    h = f.fh
    hs = 0
    vs = 0
    if f.ycbcr
      hs = jxl_ycc_hshift(f, i)
      vs = jxl_ycc_vshift(f, i)
      w = (w + (1 << hs) - 1) >> hs
      h = (h + (1 << vs) - 1) >> vs
    chs.push(JxCh.new(w, h, hs, vs))
    i += 1
  i = 0
  while i < m.ec.size
    ecu = f.ec_up[i]
    w = (f.fw * f.upsampling + ecu - 1) / ecu
    h = (f.fh * f.upsampling + ecu - 1) / ecu
    sh = jx_ceil_log2(ecu) - jx_ceil_log2(f.upsampling)
    chs.push(JxCh.new(w, h, sh, sh))
    i += 1
  d.gtree = nil
  if jb_u(src, br, 1) == 1
    lim = 1024 + f.fw * f.fh * (nch + m.ec.size) / 16
    lim = 4194304 if lim > 4194304
    d.gtree = jxm_read_tree(src, br, lim)
  img = JxMImg.new(chs, m.bpp)
  d.gimg = img
  if chs.size > 0
    jxm_read_header(src, br, img)
    jxm_alloc(img)
    jxm_decode_channels(src, br, img, 0, f.gdim, d.gtree)
  0

# chroma subsampling: jpeg_up value per channel → (hshift, vshift); the
# channel order in the codestream is Cb, Y, Cr (Y first in modular order is
# channel 1).
-> jxl_ycc_hshift(f, c)
  kh = [0, 1, 1, 0]
  mx = 0
  f.jpeg_up.each ->(j)
    mx = kh[j] if kh[j] > mx
  mx - kh[f.jpeg_up[c]]

-> jxl_ycc_vshift(f, c)
  kv = [0, 1, 0, 1]
  mx = 0
  f.jpeg_up.each ->(j)
    mx = kv[j] if kv[j] > mx
  mx - kv[f.jpeg_up[c]]

# Modular sub-image for the channels in [mins, maxs] restricted to rect.
-> jxl_modular_group(d, br, x0, y0, rw, rh, mins, maxs, sidx)
  img = d.gimg
  f = d.f
  chs = img.ch
  c = img.nb_meta
  while c < chs.size && chs[c].w <= f.gdim && chs[c].h <= f.gdim
    c += 1
  sub = []
  where = []
  while c < chs.size
    fc = chs[c]
    s = fc.hs
    s = fc.vs if fc.vs < s
    if s >= mins && s <= maxs
      cx = x0 >> fc.hs
      cy = y0 >> fc.vs
      cw = rw >> fc.hs
      ch = rh >> fc.vs
      cw = fc.w - cx if cx + cw > fc.w
      ch = fc.h - cy if cy + ch > fc.h
      if cw > 0 && ch > 0
        sub.push(JxCh.new(cw, ch, fc.hs, fc.vs))
        where.push([c, cx, cy])
    c += 1
  return 0 if sub.size == 0
  gi = JxMImg.new(sub, img.bitdepth)
  jxm_read_header(d.src, br, gi)
  jxm_alloc(gi)
  jxm_decode_channels(d.src, br, gi, sidx, 1 << 30, d.gtree)
  jxm_inverse(gi)
  k = 0
  while k < where.size
    wv = where[k]
    fc = chs[wv[0]]
    sc = gi.ch[k]
    jxl_paste_i32(fc.d, fc.w, wv[1], wv[2], sc.d, sc.w, sc.h)
    k += 1
  0

-> jxl_paste_i32(dst, dw, x0, y0, s, sw, sh) (i32[] i64 i64 i64 i32[] i64 i64) i64
  y = 0 ## i64
  while y < sh
    db = (y0 + y) * dw + x0
    sb = y * sw
    x = 0 ## i64
    while x < sw
      dst[db + x] = s[sb + x]
      x += 1
    y += 1
  0

-> jxl_lf_group(d, br, idx)
  f = d.f
  gx = idx % f.ggw
  gy = idx / f.ggw
  jxv_lf_group_dc(d, br, idx) if !f.modular && !f.use_lf_frame?
  nlf = f.ggw * f.ggh
  jxl_modular_group(d, br, gx * 8 * f.gdim, gy * 8 * f.gdim, 8 * f.gdim, 8 * f.gdim, 3, 1000, 1 + nlf + idx)
  jxv_lf_group_ac_meta(d, br, idx) if !f.modular
  0

-> jxl_pass_group(d, br, pass, g)
  f = d.f
  gx = g % f.gw
  gy = g / f.gw
  jxv_pass_group(d, br, pass, g) if !f.modular
  bk = jxl_ds_bracket(f, pass)
  nlf = f.ggw * f.ggh
  ng = f.gw * f.gh
  sidx = 1 + 3 * nlf + 17 + ng * pass + g
  jxl_modular_group(d, br, gx * f.gdim, gy * f.gdim, f.gdim, f.gdim, bk[0], bk[1], sidx)
  0

# After all sections: undo global transforms, convert to float planes, run
# the render pipeline for this frame.
-> jxl_finish_frame(d)
  f = d.f
  m = d.m
  img = d.gimg
  jxm_inverse(img) if img.ch.size > 0
  n = f.fw * f.fh
  planes = nil
  if f.modular
    planes = jxl_modular_to_float(d)
  else
    planes = jxv_render(d)
  ec = []
  nc = 0
  if f.modular
    nc = 3
    nc = 1 if m.gray? && !f.ycbcr && !m.xyb
  i = 0
  while i < m.ec.size
    ec.push(jxl_ec_to_float(m.ec[i], img.ch[nc + i]))
    i += 1
  d.planes = planes
  d.ecplanes = ec
  0

-> jxl_int_to_float(s, o, n, factor) (i32[] f64[] i64 f64) i64
  i = 0 ## i64
  while i < n
    v = s[i] ## i64
    o[i] = (v ## f64) * factor
    i += 1
  0

-> jxl_bits_to_float(s, o, n, bits, eb) (i32[] f64[] i64 i64 i64) i64
  mb = bits - eb - 1
  bias = (1 << (eb - 1)) - 1
  i = 0 ## i64
  while i < n
    v = s[i] ## i64
    v = v & ((1 << bits) - 1)
    sign = (v >> (bits - 1)) & 1
    e = (v >> mb) & ((1 << eb) - 1)
    mant = v & ((1 << mb) - 1)
    r = ~0.0
    if e == 0
      r = mant * ~1.0
      k = 1 - bias - mb
      while k < 0
        r = r * ~0.5
        k += 1
    else
      r = (mant + (1 << mb)) * ~1.0
      k = e - bias - mb
      while k > 0
        r = r * ~2.0
        k -= 1
      while k < 0
        r = r * ~0.5
        k += 1
    r = ~0.0 - r if sign == 1
    o[i] = r
    i += 1
  0

-> jxl_ch_to_float(c, bits, eb, fp)
  n = c.w * c.h
  o = f64[n]
  if fp
    jxl_bits_to_float(c.d, o, n, bits, eb)
  else
    jxl_int_to_float(c.d, o, n, ~1.0 / ((1 << bits) - 1))
  o

-> jxl_ec_to_float(e, c)
  [jxl_ch_to_float(c, e[:bpp], e[:exp_bits], e[:fp]), c.w, c.h]

-> jxl_xyb_modular(y, x, b, ox, oy, ob, n, fx, fy, fb) (i32[] i32[] i32[] f64[] f64[] f64[] i64 f64 f64 f64) i64
  i = 0 ## i64
  while i < n
    yy = y[i] ## i64
    xx = x[i] ## i64
    bb = b[i] + yy ## i64
    oy[i] = (yy ## f64) * fy
    ox[i] = (xx ## f64) * fx
    ob[i] = (bb ## f64) * fb
    i += 1
  0

# Modular colour channels → 3 float planes at frame size (subsampled YCbCr
# channels are upsampled later by the render stage).
-> jxl_modular_to_float(d)
  f = d.f
  m = d.m
  img = d.gimg
  if m.xyb
    c0 = img.ch[0]
    c1 = img.ch[1]
    c2 = img.ch[2]
    n = c0.w * c0.h
    ox = f64[n]
    oy = f64[n]
    ob = f64[n]
    jxl_xyb_modular(c0.d, c1.d, c2.d, ox, oy, ob, n, d.lf_dq[0], d.lf_dq[1], d.lf_dq[2])
    return [[ox, c0.w, c0.h], [oy, c0.w, c0.h], [ob, c0.w, c0.h]]
  if m.gray? && !f.ycbcr
    g = jxl_ch_to_float(img.ch[0], m.bpp, m.exp_bits, m.fp)
    c = img.ch[0]
    g2 = f64[g.size]
    g3 = f64[g.size]
    jxr_copy_f(g2, g, g.size)
    jxr_copy_f(g3, g, g.size)
    return [[g, c.w, c.h], [g2, c.w, c.h], [g3, c.w, c.h]]
  out = []
  k = 0
  while k < 3
    c = img.ch[k]
    out.push([jxl_ch_to_float(c, m.bpp, m.exp_bits, m.fp), c.w, c.h])
    k += 1
  out

# ---------------------------------------------------------------- top level

-> jxl_decode(bytes)
  b = jxl_u8(bytes)
  jxl_fail("not a JPEG XL file") if !jxl_sniff?(b)
  src = jxl_codestream(b)
  br = jb_new(0, src.size)
  jxl_fail("bad signature") if jb_u(src, br, 16) != 0x0AFF
  m = jxl_read_metadata(src, br)
  if m.want_icc
    enc = jxl_read_icc(src, br)
    m.icc_prof = jxl_icc_profile(enc)
  d = JxDec.new(src, m)
  if m.preview
    # decode and drop the preview frame
    jb_align(br)
    fi = jxl_frame_skip(d, br)
  frames = []
  canvas = nil
  done = false
  while !done
    jb_align(br)
    r = jxl_decode_frame(d, br)
    f = r[0]
    jb_seek(br, r[1])
    canvas = jxr_composite(d, canvas)
    if f.type == 0 || f.type == 3
      if f.duration > 0 || f.is_last || !m.anim
        frames.push([canvas, f.duration]) if m.anim
    done = f.is_last
    jxl_fail("truncated codestream") if !done && r[1] >= src.size
  bm = jxr_to_bitmap(d, canvas)
  if m.anim && frames.size > 1
    fl = []
    frames.each ->(fr)
      ms = 0
      ms = (fr[1] * 1000 * m.tps_den) / m.tps_num if m.tps_num > 0
      fl.push([jxr_to_bitmap(d, fr[0]), ms])
    bm = fl[0][0]
    bm.frames = fl
    bm.loop_count = m.num_loops
  bm

# Preview frames: parse the header and TOC and jump past the frame.
-> jxl_frame_skip(d, br)
  m = d.m
  saved_w = m.width
  saved_h = m.height
  m.width = m.pw
  m.height = m.ph
  f = jxl_read_frame_header(d.src, br, m)
  d.f = f
  toc = jxl_read_toc(d.src, br, f)
  m.width = saved_w
  m.height = saved_h
  jb_seek(br, toc[1])
  0

img_register("jxl", ->(b) jxl_sniff?(b), ->(b) jxl_decode(b))
