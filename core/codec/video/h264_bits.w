# core/codec/video/h264_bits — H.264 NAL units, the RBSP bit reader and the parameter
# set / slice header syntax (ITU-T H.264 sections 7.3 and 7.4).

use h264_tables

+ H264Error < StandardError
  rw :message

  -> new(@message)

  -> to_s
    @message

# Strip emulation-prevention bytes (00 00 03) from src[start...stop]. The
# result carries 8 zero bytes of padding so readers can fetch whole words
# without bounds checks; H264Bits takes the real length separately.
-> h264_unescape(src, start, stop) (u8[] i64 i64) u8[]
  n = 0 ## i64
  zeros = 0 ## i64
  i = start
  while i < stop
    b = src[i]
    if zeros >= 2 && b == 3
      zeros = 0
    else
      n += 1
      if b == 0
        zeros += 1
      else
        zeros = 0
    i += 1
  out = u8[n + 16]
  zeros = 0
  i = start
  o = 0 ## i64
  while i < stop
    b = src[i]
    if zeros >= 2 && b == 3
      zeros = 0
    else
      out[o] = b
      o += 1
      if b == 0
        zeros += 1
      else
        zeros = 0
    i += 1
  out

# Unescaped payload length is the buffer size minus the 16 padding bytes.
-> h264_rbsp_len(b) (u8[]) i64
  b.size - 16

# Find Annex B start codes; returns [start, stop, start, stop, …] payload spans.
-> h264_annexb_spans(src, len)
  spans = []
  i = 0
  first = -1
  while i + 2 < len
    if src[i] == 0 && src[i + 1] == 0 && src[i + 2] == 1
      if first >= 0
        e = i
        # trailing zero bytes belong to the next start code (zero_byte)
        while e > first && src[e - 1] == 0
          e -= 1
        spans.push(first)
        spans.push(e)
      first = i + 3
      i += 3
    else
      i += 1
  if first >= 0
    e = len
    while e > first && src[e - 1] == 0
      e -= 1
    spans.push(first)
    spans.push(e)
  spans

# Length-prefixed NAL units (avcC samples).
-> h264_length_spans(src, len, nls)
  spans = []
  i = 0
  while i + nls <= len
    n = 0
    k = 0
    while k < nls
      n = (n << 8) | src[i + k]
      k += 1
    i += nls
    break if n <= 0 || i + n > len
    spans.push(i)
    spans.push(i + n)
    i += n
  spans

# MSB-first bit reader over an unescaped RBSP.
+ H264Bits
  rw :pos, :b, :nbytes

  -> new(@b, @nbytes)
    @pos = 0
    # position of the rbsp_stop_one_bit, for more_rbsp_data
    e = @nbytes - 1
    while e >= 0 && @b[e] == 0
      e -= 1
    if e < 0
      @stop = 0
    else
      v = @b[e]
      t = 0
      while (v & 1) == 0
        v = v >> 1
        t += 1
      @stop = e * 8 + 7 - t

  -> u(n) (i64) i64
    return 0 if n == 0
    b = @b
    p = @pos >> 3
    v = (b[p] << 48) | (b[p + 1] << 40) | (b[p + 2] << 32) | (b[p + 3] << 24) | (b[p + 4] << 16) | (b[p + 5] << 8) | b[p + 6]
    r = (v >> (56 - (@pos & 7) - n)) & ((1 << n) - 1)
    @pos = @pos + n
    r

  -> peek(n) (i64) i64
    b = @b
    p = @pos >> 3
    v = (b[p] << 48) | (b[p + 1] << 40) | (b[p + 2] << 32) | (b[p + 3] << 24) | (b[p + 4] << 16) | (b[p + 5] << 8) | b[p + 6]
    (v >> (56 - (@pos & 7) - n)) & ((1 << n) - 1)

  -> skip(n) (i64) i64
    @pos = @pos + n
    0

  -> flag (i64) i64
    u(1)

  -> ue (i64) i64
    lz = 0 ## i64
    v = peek(32)
    if v == 0
      # very long code: count bit by bit
      while u(1) == 0 && lz < 63
        lz += 1
      return 0 if lz > 31
      return (1 << lz) - 1 + u(lz)
    while (v & 0x80000000) == 0
      v = v << 1
      lz += 1
    @pos = @pos + lz + 1
    (1 << lz) - 1 + u(lz)

  -> se (i64) i64
    k = ue
    if (k & 1) == 1
      (k + 1) >> 1
    else
      0 - (k >> 1)

  -> te(range) (i64) i64
    if range > 1
      ue
    else
      1 - u(1)

  -> byte_aligned? (i64) i64
    (@pos & 7) == 0 ? 1 : 0

  -> align (i64) i64
    @pos = (@pos + 7) & (0 - 8)
    0

  -> more_rbsp_data? (i64) i64
    @pos < @stop ? 1 : 0

  -> bits_left (i64) i64
    @nbytes * 8 - @pos

  -> byte_pos (i64) i64
    @pos >> 3

# Scaling list syntax (7.3.2.1.1.1); fills lst[off...off+n] in zig-zag order.
# Returns 1 when useDefaultScalingMatrixFlag is set.
-> h264_scaling_list(r, lst, off, n)
  last = 8
  nxt = 8
  j = 0
  use_def = 0
  while j < n
    if nxt != 0
      delta = r.se
      nxt = (last + delta + 256) % 256
      use_def = 1 if j == 0 && nxt == 0
    v = nxt == 0 ? last : nxt
    lst[off + j] = v
    last = v
    j += 1
  use_def

+ H264SPS
  rw :profile, :level, :id, :chroma_format, :separate_planes, :bit_depth, :bit_depth_c, :bypass, :log2_max_frame_num, :poc_type, :log2_max_poc_lsb, :delta_always_zero, :offset_non_ref, :offset_top_bottom, :poc_cycle, :max_refs, :gaps_allowed, :mbw, :mbh_map, :frame_mbs_only, :mbaff, :direct8x8, :crop, :sl4, :sl8, :has_matrix, :vui_colour, :primaries, :transfer, :matrix, :full_range, :num_reorder, :max_dec_buf, :has_restrict, :mbh, :timing

  -> new
    @chroma_format = 1
    @separate_planes = 0
    @bit_depth = 8
    @bit_depth_c = 8
    @bypass = 0
    @crop = [0, 0, 0, 0]
    @sl4 = i64[96]
    @sl8 = i64[384]
    @has_matrix = 0
    @vui_colour = 0
    @primaries = 2
    @transfer = 2
    @matrix = 2
    @full_range = 0
    @num_reorder = -1
    @max_dec_buf = -1
    @has_restrict = 0
    @poc_cycle = []
    @timing = nil

  -> .parse(r)
    s = H264SPS.new
    s.profile = r.u(8)
    r.u(8)
    s.level = r.u(8)
    s.id = r.ue
    p = s.profile
    flat_lists(s.sl4, s.sl8)
    if p == 100 || p == 110 || p == 122 || p == 244 || p == 44 || p == 83 || p == 86 || p == 118 || p == 128 || p == 138 || p == 139 || p == 134 || p == 135
      s.chroma_format = r.ue
      s.separate_planes = r.u(1) if s.chroma_format == 3
      s.bit_depth = r.ue + 8
      s.bit_depth_c = r.ue + 8
      s.bypass = r.u(1)
      if r.u(1) == 1
        s.has_matrix = 1
        nl = s.chroma_format == 3 ? 12 : 8
        i = 0
        while i < nl
          present = r.u(1)
          if i < 6
            if present == 1
              if h264_scaling_list(r, s.sl4, i * 16, 16) == 1
                h264_copy_default4(s.sl4, i)
            else
              # fall-back rule A
              if i == 0 || i == 3
                h264_copy_default4(s.sl4, i)
              else
                k = 0
                while k < 16
                  s.sl4[i * 16 + k] = s.sl4[(i - 1) * 16 + k]
                  k += 1
          else
            j = i - 6
            if present == 1
              if h264_scaling_list(r, s.sl8, j * 64, 64) == 1
                h264_copy_default8(s.sl8, j)
            else
              if j < 2
                h264_copy_default8(s.sl8, j)
              else
                k = 0
                while k < 64
                  s.sl8[j * 64 + k] = s.sl8[(j - 2) * 64 + k]
                  k += 1
          i += 1
    s.log2_max_frame_num = r.ue + 4
    s.poc_type = r.ue
    s.delta_always_zero = 0
    s.offset_non_ref = 0
    s.offset_top_bottom = 0
    s.log2_max_poc_lsb = 0
    if s.poc_type == 0
      s.log2_max_poc_lsb = r.ue + 4
    elsif s.poc_type == 1
      s.delta_always_zero = r.u(1)
      s.offset_non_ref = r.se
      s.offset_top_bottom = r.se
      n = r.ue
      cyc = []
      n.times ->
        cyc.push(r.se)
      s.poc_cycle = cyc
    s.max_refs = r.ue
    s.gaps_allowed = r.u(1)
    s.mbw = r.ue + 1
    s.mbh_map = r.ue + 1
    s.frame_mbs_only = r.u(1)
    s.mbaff = 0
    s.mbaff = r.u(1) if s.frame_mbs_only == 0
    s.mbh = s.mbh_map * (2 - s.frame_mbs_only)
    s.direct8x8 = r.u(1)
    if r.u(1) == 1
      cl = r.ue
      cr = r.ue
      ct = r.ue
      cb = r.ue
      ux = 1
      uy = 2 - s.frame_mbs_only
      if s.chroma_format == 1
        ux = 2
        uy = 2 * (2 - s.frame_mbs_only)
      elsif s.chroma_format == 2
        ux = 2
      s.crop = [cl * ux, cr * ux, ct * uy, cb * uy]
    if r.u(1) == 1
      s.parse_vui(r)
    s

  -> parse_vui(r)
    if r.u(1) == 1
      ar = r.u(8)
      if ar == 255
        r.u(16)
        r.u(16)
    if r.u(1) == 1
      r.u(1)
    if r.u(1) == 1
      r.u(3)
      @full_range = r.u(1)
      if r.u(1) == 1
        @vui_colour = 1
        @primaries = r.u(8)
        @transfer = r.u(8)
        @matrix = r.u(8)
    if r.u(1) == 1
      r.ue
      r.ue
    if r.u(1) == 1
      nu = r.u(32)
      ts = r.u(32)
      r.u(1)
      @timing = [nu, ts]
    nal_hrd = r.u(1)
    skip_hrd(r) if nal_hrd == 1
    vcl_hrd = r.u(1)
    skip_hrd(r) if vcl_hrd == 1
    r.u(1) if nal_hrd == 1 || vcl_hrd == 1
    r.u(1)
    if r.u(1) == 1
      @has_restrict = 1
      r.u(1)
      r.ue
      r.ue
      r.ue
      r.ue
      @num_reorder = r.ue
      @max_dec_buf = r.ue

  -> skip_hrd(r)
    cnt = r.ue + 1
    r.u(4)
    r.u(4)
    cnt.times ->
      r.ue
      r.ue
      r.u(1)
    r.u(5)
    r.u(5)
    r.u(5)
    r.u(5)

-> flat_lists(sl4, sl8)
  i = 0
  while i < 96
    sl4[i] = 16
    i += 1
  i = 0
  while i < 384
    sl8[i] = 16
    i += 1

-> h264_copy_default4(sl4, i)
  base = (i < 3) ? 0 : 16
  k = 0
  while k < 16
    sl4[i * 16 + k] = H264_DEFAULT_SCALING4[base + k]
    k += 1

-> h264_copy_default8(sl8, j)
  base = (j % 2 == 0) ? 0 : 64
  k = 0
  while k < 64
    sl8[j * 64 + k] = H264_DEFAULT_SCALING8[base + k]
    k += 1

+ H264PPS
  rw :id, :sps_id, :cabac, :bottom_poc_present, :num_slice_groups, :sg_type, :sg_run_length, :sg_top_left, :sg_bottom_right, :sg_change_dir, :sg_change_rate, :sg_ids, :num_ref_l0, :num_ref_l1, :weighted_pred, :weighted_bipred, :init_qp, :init_qs, :cqp_off, :cqp_off2, :dbk_control, :constrained_intra, :redundant_present, :transform8x8, :sl4, :sl8, :has_matrix

  -> new
    @transform8x8 = 0
    @has_matrix = 0
    @sl4 = i64[96]
    @sl8 = i64[384]

  -> .parse(r, spss)
    p = H264PPS.new
    p.id = r.ue
    p.sps_id = r.ue
    sps = spss[p.sps_id]
    raise H264Error, "h264: PPS references missing SPS" if sps == nil
    p.cabac = r.u(1)
    p.bottom_poc_present = r.u(1)
    p.num_slice_groups = r.ue + 1
    p.sg_type = 0
    if p.num_slice_groups > 1
      p.sg_type = r.ue
      t = p.sg_type
      if t == 0
        rl = []
        p.num_slice_groups.times ->
          rl.push(r.ue + 1)
        p.sg_run_length = rl
      elsif t == 2
        tl = []
        br = []
        (p.num_slice_groups - 1).times ->
          tl.push(r.ue)
          br.push(r.ue)
        p.sg_top_left = tl
        p.sg_bottom_right = br
      elsif t == 3 || t == 4 || t == 5
        p.sg_change_dir = r.u(1)
        p.sg_change_rate = r.ue + 1
      elsif t == 6
        n = r.ue + 1
        bits = 0
        while (1 << bits) < p.num_slice_groups
          bits += 1
        ids = []
        n.times ->
          ids.push(r.u(bits))
        p.sg_ids = ids
    p.num_ref_l0 = r.ue + 1
    p.num_ref_l1 = r.ue + 1
    p.weighted_pred = r.u(1)
    p.weighted_bipred = r.u(2)
    p.init_qp = 26 + r.se
    p.init_qs = 26 + r.se
    p.cqp_off = r.se
    p.dbk_control = r.u(1)
    p.constrained_intra = r.u(1)
    p.redundant_present = r.u(1)
    p.cqp_off2 = p.cqp_off
    # default: inherit the sequence-level lists
    k = 0
    while k < 96
      p.sl4[k] = sps.sl4[k]
      k += 1
    k = 0
    while k < 384
      p.sl8[k] = sps.sl8[k]
      k += 1
    if r.more_rbsp_data? == 1
      p.transform8x8 = r.u(1)
      if r.u(1) == 1
        p.has_matrix = 1
        nl = 6 + ((sps.chroma_format == 3) ? 6 : 2) * p.transform8x8
        i = 0
        while i < nl
          present = r.u(1)
          if i < 6
            if present == 1
              if h264_scaling_list(r, p.sl4, i * 16, 16) == 1
                h264_copy_default4(p.sl4, i)
            elsif i == 0 || i == 3
              # fall-back rule B: the sequence-level list (Default when the SPS has none)
              if sps.has_matrix == 1
                k = 0
                while k < 16
                  p.sl4[i * 16 + k] = sps.sl4[i * 16 + k]
                  k += 1
              else
                h264_copy_default4(p.sl4, i)
            else
              k = 0
              while k < 16
                p.sl4[i * 16 + k] = p.sl4[(i - 1) * 16 + k]
                k += 1
          else
            j = i - 6
            if present == 1
              if h264_scaling_list(r, p.sl8, j * 64, 64) == 1
                h264_copy_default8(p.sl8, j)
            elsif j < 2
              if sps.has_matrix == 1
                k = 0
                while k < 64
                  p.sl8[j * 64 + k] = sps.sl8[j * 64 + k]
                  k += 1
              else
                h264_copy_default8(p.sl8, j)
            else
              k = 0
              while k < 64
                p.sl8[j * 64 + k] = p.sl8[(j - 2) * 64 + k]
                k += 1
          i += 1
      p.cqp_off2 = r.se
    p

# Slice header (7.3.3), including ref list modification, weights and marking.
+ H264Slice
  rw :first_mb, :type, :pps_id, :frame_num, :field, :bottom, :idr_pic_id, :poc_lsb, :delta_poc_bottom, :delta_poc0, :delta_poc1, :redundant_cnt, :direct_spatial, :num_ref, :mods, :luma_log2, :chroma_log2, :weights, :has_weights, :mmco, :long_term_ref, :no_output_prior, :adaptive_marking, :cabac_init, :qp, :qs, :dbk_idc, :alpha_off, :beta_off, :sg_change_cycle, :nal_ref_idc, :nal_type, :is_idr, :data_bit_pos, :sp_switch

  -> new
    @num_ref = [0, 0]
    @mods = [[], []]
    @mmco = []
    @has_weights = 0
    @weights = nil
    @delta_poc_bottom = 0
    @delta_poc0 = 0
    @delta_poc1 = 0
    @field = 0
    @bottom = 0
    @idr_pic_id = 0
    @poc_lsb = 0
    @redundant_cnt = 0
    @direct_spatial = 0
    @long_term_ref = 0
    @no_output_prior = 0
    @adaptive_marking = 0
    @cabac_init = 0
    @dbk_idc = 0
    @alpha_off = 0
    @beta_off = 0
    @sg_change_cycle = 0

  # slice_type mod 5: 0 P, 1 B, 2 I, 3 SP, 4 SI
  -> p?
    @type == 0 || @type == 3

  -> b?
    @type == 1

  -> i?
    @type == 2 || @type == 4

  -> .parse(r, nal_type, nal_ref_idc, spss, ppss)
    s = H264Slice.new
    s.nal_type = nal_type
    s.nal_ref_idc = nal_ref_idc
    s.is_idr = nal_type == 5 ? 1 : 0
    s.first_mb = r.ue
    s.type = r.ue % 5
    s.pps_id = r.ue
    pps = ppss[s.pps_id]
    raise H264Error, "h264: slice references missing PPS" if pps == nil
    sps = spss[pps.sps_id]
    raise H264Error, "h264: slice references missing SPS" if sps == nil
    r.u(2) if sps.separate_planes == 1
    s.frame_num = r.u(sps.log2_max_frame_num)
    if sps.frame_mbs_only == 0
      s.field = r.u(1)
      s.bottom = r.u(1) if s.field == 1
    s.idr_pic_id = r.ue if s.is_idr == 1
    if sps.poc_type == 0
      s.poc_lsb = r.u(sps.log2_max_poc_lsb)
      s.delta_poc_bottom = r.se if pps.bottom_poc_present == 1 && s.field == 0
    if sps.poc_type == 1 && sps.delta_always_zero == 0
      s.delta_poc0 = r.se
      s.delta_poc1 = r.se if pps.bottom_poc_present == 1 && s.field == 0
    s.redundant_cnt = r.ue if pps.redundant_present == 1
    s.direct_spatial = r.u(1) if s.b?
    s.num_ref = [pps.num_ref_l0, pps.num_ref_l1]
    if s.p? || s.b?
      if r.u(1) == 1
        n0 = r.ue + 1
        n1 = s.num_ref[1]
        n1 = r.ue + 1 if s.b?
        s.num_ref = [n0, n1]
    s.num_ref = [s.num_ref[0], 0] if !s.b?
    s.num_ref = [0, 0] if s.i?
    # ref_pic_list_modification
    if !s.i?
      nl = s.b? ? 2 : 1
      l = 0
      while l < nl
        if r.u(1) == 1
          ms = []
          while true
            op = r.ue
            break if op == 3
            raise H264Error, "h264: bad ref list modification" if op > 5
            ms.push(op)
            ms.push(r.ue)
          s.mods[l] = ms
        l += 1
    if (pps.weighted_pred == 1 && s.p?) || (pps.weighted_bipred == 1 && s.b?)
      s.parse_weights(r, sps)
    if nal_ref_idc != 0
      if s.is_idr == 1
        s.no_output_prior = r.u(1)
        s.long_term_ref = r.u(1)
      else
        s.adaptive_marking = r.u(1)
        if s.adaptive_marking == 1
          ops = []
          while true
            op = r.ue
            break if op == 0
            a1 = 0
            a2 = 0
            a1 = r.ue if op == 1 || op == 3
            a2 = r.ue if op == 2
            a2 = r.ue if op == 3 || op == 6
            a1 = r.ue if op == 4
            ops.push([op, a1, a2])
          s.mmco = ops
    s.cabac_init = r.ue if pps.cabac == 1 && !s.i?
    s.qp = pps.init_qp + r.se
    if s.type == 3 || s.type == 4
      s.sp_switch = r.u(1) if s.type == 3
      s.qs = pps.init_qs + r.se
    if pps.dbk_control == 1
      s.dbk_idc = r.ue
      if s.dbk_idc != 1
        s.alpha_off = r.se * 2
        s.beta_off = r.se * 2
    if pps.num_slice_groups > 1 && pps.sg_type >= 3 && pps.sg_type <= 5
      pic_size = sps.mbw * sps.mbh_map
      units = (pic_size + pps.sg_change_rate - 1) / pps.sg_change_rate + 1
      bits = 0
      while (1 << bits) < units
        bits += 1
      s.sg_change_cycle = r.u(bits)
    s.data_bit_pos = r.pos
    s

  # pred_weight_table: weights[l] = i64[32*6] of (lw, lo, cbw, cbo, crw, cro)
  -> parse_weights(r, sps)
    @has_weights = 1
    @luma_log2 = r.ue
    @chroma_log2 = 0
    @chroma_log2 = r.ue if sps.chroma_format != 0
    ws = [nil, nil]
    nl = b? ? 2 : 1
    l = 0
    while l < nl
      w = i64[32 * 8]
      n = @num_ref[l]
      i = 0
      while i < n
        b = i * 8
        w[b] = 1 << @luma_log2
        w[b + 1] = 0
        w[b + 2] = 1 << @chroma_log2
        w[b + 3] = 0
        w[b + 4] = 1 << @chroma_log2
        w[b + 5] = 0
        w[b + 6] = 0
        w[b + 7] = 0
        if r.u(1) == 1
          w[b] = r.se
          w[b + 1] = r.se
          w[b + 6] = 1
        if sps.chroma_format != 0 && r.u(1) == 1
          w[b + 2] = r.se
          w[b + 3] = r.se
          w[b + 4] = r.se
          w[b + 5] = r.se
          w[b + 7] = 1
        i += 1
      ws[l] = w
      l += 1
    @weights = ws
