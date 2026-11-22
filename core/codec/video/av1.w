# core/codec/video/av1 — an AV1 decoder (AV1 Bitstream & Decoding Process Specification).
#
# Av1Decoder keeps the decoder state of the specification across temporal
# units: the sequence header, the eight reference frame slots (frame buffers,
# saved CDFs, loop-filter / segmentation / global-motion parameters, order
# hints), so the AVIF still path and video share one decoder:
#
#   d = Av1Decoder.new
#   frames = d.decode(bytes)      # OBUs of one temporal unit → [Av1Frame] shown
#
# This file holds OBU parsing, the sequence header, the uncompressed frame
# header and the reference-frame bookkeeping. Tile decoding lives in
# core/codec/video/av1_tile.w (entropy decoding, mode info, coefficients), prediction in
# core/codec/video/av1_pred.w, inverse transforms in core/codec/video/av1_tx.w and the in-loop filters in
# core/codec/video/av1_filter.w. They reopen the Av1Decoder class.
#
# Coverage: key and intra-only frames with every intra tool (directional,
# smooth, paeth, CFL, palette, intra block copy, filter intra), all transforms,
# quantizer matrices, loop filter, CDEF, loop restoration, superres; 8/10/12
# bit; 4:2:0, 4:2:2, 4:4:4, monochrome; inter frames with every inter tool
# (core/codec/video/av1_inter.w, core/codec/video/av1_mc.w) and film grain synthesis on output (core/codec/video/av1_grain.w).

use core/codec/image/heif
use core/codec/media
use av1_tables
use av1_cdf
use av1_tile
use av1_pred
use av1_tx
use av1_filter
use av1_inter
use av1_grain

+ Av1Error < StandardError
+ Av1Unsupported < Av1Error

AV1_KEY_FRAME = 0
AV1_INTER_FRAME = 1
AV1_INTRA_ONLY_FRAME = 2
AV1_SWITCH_FRAME = 3
AV1_PRIMARY_REF_NONE = 7

# A decoded frame: planes are u16[] with stride pw[p]; width/height are the
# upscaled frame size; render_w/h the intended display size.
+ Av1Frame
  rw :width, :height, :bit_depth, :ssx, :ssy, :mono, :planes, :strides, :heights, :render_w, :render_h
  rw :cp, :tc, :mc, :full_range, :frame_type, :show

  -> new(@width, @height, @bit_depth, @ssx, @ssy, @mono, aw, ah)
    # aw/ah: allocated luma size (≥ width/height, superblock aligned)
    cw = (aw + @ssx) >> @ssx
    ch = (ah + @ssy) >> @ssy
    @strides = [aw, cw, cw]
    @heights = [ah, ch, ch]
    np = @mono ? 1 : 3
    @planes = []
    k = 0
    while k < np
      @planes.push(u16[@strides[k] * @heights[k]])
      k += 1
    @render_w = @width
    @render_h = @height
    @cp = 2
    @tc = 2
    @mc = 2
    @full_range = false
    @frame_type = 0
    @show = true

+ Av1Decoder
  rw :seq, :frames_out

  -> new
    @seq = nil
    @ref_valid = [false, false, false, false, false, false, false, false]
    @ref_frame_id = [0, 0, 0, 0, 0, 0, 0, 0]
    @ref_upscaled_w = [0, 0, 0, 0, 0, 0, 0, 0]
    @ref_frame_w = [0, 0, 0, 0, 0, 0, 0, 0]
    @ref_frame_h = [0, 0, 0, 0, 0, 0, 0, 0]
    @ref_render_w = [0, 0, 0, 0, 0, 0, 0, 0]
    @ref_render_h = [0, 0, 0, 0, 0, 0, 0, 0]
    @ref_mi_cols = [0, 0, 0, 0, 0, 0, 0, 0]
    @ref_mi_rows = [0, 0, 0, 0, 0, 0, 0, 0]
    @ref_frame_type = [0, 0, 0, 0, 0, 0, 0, 0]
    @ref_order_hint = [0, 0, 0, 0, 0, 0, 0, 0]
    @ref_bit_depth = [0, 0, 0, 0, 0, 0, 0, 0]
    @ref_ssx = [0, 0, 0, 0, 0, 0, 0, 0]
    @ref_ssy = [0, 0, 0, 0, 0, 0, 0, 0]
    @ref_frames = [nil, nil, nil, nil, nil, nil, nil, nil]
    @saved_cdfs = [nil, nil, nil, nil, nil, nil, nil, nil]
    @saved_gm = [nil, nil, nil, nil, nil, nil, nil, nil]
    @saved_lf_ref = [nil, nil, nil, nil, nil, nil, nil, nil]
    @saved_lf_mode = [nil, nil, nil, nil, nil, nil, nil, nil]
    @saved_feat_en = [nil, nil, nil, nil, nil, nil, nil, nil]
    @saved_feat_data = [nil, nil, nil, nil, nil, nil, nil, nil]
    @saved_seg_ids = [nil, nil, nil, nil, nil, nil, nil, nil]
    @saved_order_hints = [nil, nil, nil, nil, nil, nil, nil, nil]
    @saved_grain = [nil, nil, nil, nil, nil, nil, nil, nil]
    @saved_mf_refs = [nil, nil, nil, nil, nil, nil, nil, nil]
    @saved_mf_mvs = [nil, nil, nil, nil, nil, nil, nil, nil]
    @order_hints = [0, 0, 0, 0, 0, 0, 0, 0]
    @ref_frame_sign_bias = [0, 0, 0, 0, 0, 0, 0, 0]
    @ref_frame_idx = [0, 0, 0, 0, 0, 0, 0]
    @seen_frame_header = false
    @frames_out = []
    @cdf = nil
    @temporal_id = 0
    @spatial_id = 0
    @current_frame_id = 0
    av1_tables_init()

  -> reset
    @ref_valid = [false, false, false, false, false, false, false, false]
    @ref_frames = [nil, nil, nil, nil, nil, nil, nil, nil]
    @seen_frame_header = false
    @frames_out = []

  # ------------------------------------------------------------ bit reader

  -> rb_init(data, pos)
    @data = data
    @bitpos = pos * 8

  -> f(n)
    x = 0
    i = 0
    d = @data
    while i < n
      p = @bitpos
      by = p >> 3
      bit = by < d.size ? (d[by] >> (7 - (p & 7))) & 1 : 0
      x = (x << 1) | bit
      @bitpos = p + 1
      i += 1
    x

  -> su(n)
    v = f(n)
    sm = 1 << (n - 1)
    v -= 2 * sm if (v & sm) != 0
    v

  -> ns(n)
    w = 0
    x = n
    while x != 0
      x = x >> 1
      w += 1
    m = (1 << w) - n
    v = f(w - 1)
    return v if v < m
    e = f(1)
    (v << 1) - m + e

  -> le(n)
    t = 0
    i = 0
    while i < n
      t += f(8) << (i * 8)
      i += 1
    t

  -> leb128
    v = 0
    i = 0
    while i < 8
      b = f(8)
      v = v | ((b & 0x7f) << (i * 7))
      return v if (b & 0x80) == 0
      i += 1
    v

  -> uvlc
    lz = 0
    while f(1) == 0
      lz += 1
      return 4294967295 if lz >= 32
    return 0 if lz == 0
    f(lz) + (1 << lz) - 1

  -> byte_align
    @bitpos = (@bitpos + 7) & (0 - 8)

  # ------------------------------------------------------------ OBUs

  # Decode one temporal unit (a sequence of OBUs, low-overhead format).
  # Returns the frames output (shown) while decoding it.
  -> decode(data)
    @frames_out = []
    pos = 0
    n = data.size
    while pos < n
      rb_init(data, pos)
      f(1)
      obu_type = f(4)
      ext = f(1)
      has_size = f(1)
      f(1)
      if ext == 1
        @temporal_id = f(3)
        @spatial_id = f(2)
        f(3)
      sz = 0
      if has_size == 1
        sz = leb128()
      else
        sz = n - pos - 1 - ext
      start = @bitpos >> 3
      raise Av1Error.new("av1: OBU overruns the data") if start + sz > n
      drop = false
      if obu_type != 1 && obu_type != 2 && @seq != nil && @op_idc != 0 && ext == 1
        in_t = (@op_idc >> @temporal_id) & 1
        in_s = (@op_idc >> (@spatial_id + 8)) & 1
        drop = in_t == 0 || in_s == 0
      if !drop
        case obu_type
          when 1
            sequence_header_obu()
          when 2
            @seen_frame_header = false
          when 3, 7
            frame_header_obu(start, sz)
          when 4
            tile_group_obu(start, sz)
          when 6
            frame_obu(start, sz)
      pos = start + sz
    @frames_out

  # ------------------------------------------------------------ sequence header

  -> sequence_header_obu
    s = {}
    s[:profile] = f(3)
    s[:still] = f(1)
    s[:reduced] = f(1)
    s[:timing_info] = 0
    s[:decoder_model_info] = 0
    s[:equal_picture_interval] = 0
    op_idc = [0]
    if s[:reduced] == 1
      f(5)
    else
      s[:timing_info] = f(1)
      if s[:timing_info] == 1
        f(32)
        f(32)
        s[:equal_picture_interval] = f(1)
        uvlc() if s[:equal_picture_interval] == 1
        s[:decoder_model_info] = f(1)
        if s[:decoder_model_info] == 1
          s[:buffer_delay_length] = f(5) + 1
          f(32)
          s[:buffer_removal_time_length] = f(5) + 1
          s[:frame_presentation_time_length] = f(5) + 1
      idd = f(1)
      cnt = f(5) + 1
      op_idc = []
      s[:dm_present] = []
      i = 0
      while i < cnt
        op_idc.push(f(12))
        lvl = f(5)
        f(1) if lvl > 7
        dmp = 0
        if s[:decoder_model_info] == 1
          dmp = f(1)
          if dmp == 1
            n = s[:buffer_delay_length]
            f(n)
            f(n)
            f(1)
        s[:dm_present].push(dmp)
        if idd == 1
          f(4) if f(1) == 1
        i += 1
    s[:op_idc] = op_idc
    @op_idc = op_idc[0]
    s[:fw_bits] = f(4) + 1
    s[:fh_bits] = f(4) + 1
    s[:max_w] = f(s[:fw_bits]) + 1
    s[:max_h] = f(s[:fh_bits]) + 1
    s[:frame_id_numbers] = s[:reduced] == 1 ? 0 : f(1)
    if s[:frame_id_numbers] == 1
      s[:delta_frame_id_len] = f(4) + 2
      s[:frame_id_len] = f(3) + 1 + s[:delta_frame_id_len]
    s[:sb128] = f(1)
    s[:filter_intra] = f(1)
    s[:intra_edge] = f(1)
    s[:interintra] = 0
    s[:masked_compound] = 0
    s[:warped_motion] = 0
    s[:dual_filter] = 0
    s[:order_hint] = 0
    s[:jnt_comp] = 0
    s[:ref_frame_mvs] = 0
    s[:force_sct] = 2
    s[:force_imv] = 2
    s[:order_hint_bits] = 0
    if s[:reduced] == 0
      s[:interintra] = f(1)
      s[:masked_compound] = f(1)
      s[:warped_motion] = f(1)
      s[:dual_filter] = f(1)
      s[:order_hint] = f(1)
      if s[:order_hint] == 1
        s[:jnt_comp] = f(1)
        s[:ref_frame_mvs] = f(1)
      if f(1) == 1
        s[:force_sct] = 2
      else
        s[:force_sct] = f(1)
      if s[:force_sct] > 0
        if f(1) == 1
          s[:force_imv] = 2
        else
          s[:force_imv] = f(1)
      else
        s[:force_imv] = 2
      s[:order_hint_bits] = f(3) + 1 if s[:order_hint] == 1
    s[:superres] = f(1)
    s[:cdef] = f(1)
    s[:restoration] = f(1)
    # color_config
    hbd = f(1)
    bd = 8
    if s[:profile] == 2 && hbd == 1
      bd = f(1) == 1 ? 12 : 10
    elsif s[:profile] <= 2
      bd = hbd == 1 ? 10 : 8
    s[:bit_depth] = bd
    mono = s[:profile] == 1 ? 0 : f(1)
    s[:mono] = mono
    s[:num_planes] = mono == 1 ? 1 : 3
    cp = 2
    tc = 2
    mc = 2
    if f(1) == 1
      cp = f(8)
      tc = f(8)
      mc = f(8)
    s[:cp] = cp
    s[:tc] = tc
    s[:mc] = mc
    s[:sep_uv_dq] = 0
    if mono == 1
      s[:color_range] = f(1)
      s[:ssx] = 1
      s[:ssy] = 1
    elsif cp == 1 && tc == 13 && mc == 0
      s[:color_range] = 1
      s[:ssx] = 0
      s[:ssy] = 0
      s[:sep_uv_dq] = f(1)
    else
      s[:color_range] = f(1)
      if s[:profile] == 0
        s[:ssx] = 1
        s[:ssy] = 1
      elsif s[:profile] == 1
        s[:ssx] = 0
        s[:ssy] = 0
      else
        if bd == 12
          s[:ssx] = f(1)
          s[:ssy] = s[:ssx] == 1 ? f(1) : 0
        else
          s[:ssx] = 1
          s[:ssy] = 0
      s[:csp] = f(2) if s[:ssx] == 1 && s[:ssy] == 1
      s[:sep_uv_dq] = f(1)
    s[:film_grain] = f(1)
    @seq = s
    seq_cache()
    nil

  # copy hot sequence fields into ivars
  -> seq_cache
    s = @seq
    @bit_depth = s[:bit_depth]
    @ssx = s[:ssx]
    @ssy = s[:ssy]
    @num_planes = s[:num_planes]
    @mono = s[:mono] == 1
    @sb128 = s[:sb128]
    @enable_filter_intra = s[:filter_intra]
    @enable_intra_edge = s[:intra_edge]
    @enable_order_hint = s[:order_hint]
    @order_hint_bits = s[:order_hint_bits]
    @enable_cdef = s[:cdef]
    @enable_restoration = s[:restoration]
    @enable_superres = s[:superres]
    @enable_dual_filter = s[:dual_filter]
    @enable_interintra = s[:interintra]
    @enable_masked_compound = s[:masked_compound]
    @enable_jnt_comp = s[:jnt_comp]
    nil

  # ------------------------------------------------------------ frame header

  -> frame_header_obu(start, sz)
    if @seen_frame_header
      # frame_header_copy: identical to the one already parsed
      return nil
    @seen_frame_header = true
    uncompressed_header()
    if @show_existing_frame == 1
      show_existing()
      @seen_frame_header = false
    else
      @tile_num = 0
      @seen_frame_header = true
    nil

  -> frame_obu(start, sz)
    s0 = @bitpos
    frame_header_obu(start, sz)
    byte_align()
    hb = (@bitpos - s0) >> 3
    tile_group_obu(@bitpos >> 3, sz - hb)

  -> get_relative_dist(a, b)
    return 0 if @enable_order_hint == 0
    diff = a - b
    m = 1 << (@order_hint_bits - 1)
    (diff & (m - 1)) - (diff & m)

  -> uncompressed_header
    s = @seq
    raise Av1Error.new("av1: frame before sequence header") if s == nil
    id_len = s[:frame_id_numbers] == 1 ? s[:frame_id_len] : 0
    all_frames = 255
    @show_existing_frame = 0
    if s[:reduced] == 1
      @frame_type = AV1_KEY_FRAME
      @frame_is_intra = true
      @show_frame = 1
      @showable_frame = 0
      @error_resilient_mode = 1
    else
      @show_existing_frame = f(1)
      if @show_existing_frame == 1
        @frame_to_show_map_idx = f(3)
        if s[:decoder_model_info] == 1 && s[:equal_picture_interval] == 0
          f(s[:frame_presentation_time_length])
        @refresh_frame_flags = 0
        f(id_len) if id_len > 0
        @frame_type = @ref_frame_type[@frame_to_show_map_idx]
        @refresh_frame_flags = all_frames if @frame_type == AV1_KEY_FRAME
        return nil
      @frame_type = f(2)
      @frame_is_intra = @frame_type == AV1_INTRA_ONLY_FRAME || @frame_type == AV1_KEY_FRAME
      @show_frame = f(1)
      if @show_frame == 1 && s[:decoder_model_info] == 1 && s[:equal_picture_interval] == 0
        f(s[:frame_presentation_time_length])
      if @show_frame == 1
        @showable_frame = @frame_type != AV1_KEY_FRAME ? 1 : 0
      else
        @showable_frame = f(1)
      if @frame_type == AV1_SWITCH_FRAME || (@frame_type == AV1_KEY_FRAME && @show_frame == 1)
        @error_resilient_mode = 1
      else
        @error_resilient_mode = f(1)
    if @frame_type == AV1_KEY_FRAME && @show_frame == 1
      i = 0
      while i < 8
        @ref_valid[i] = false
        @ref_order_hint[i] = 0
        i += 1
      i = 1
      while i < 8
        @order_hints[i] = 0
        i += 1
    @disable_cdf_update = f(1)
    if s[:force_sct] == 2
      @allow_screen_content_tools = f(1)
    else
      @allow_screen_content_tools = s[:force_sct]
    if @allow_screen_content_tools == 1
      if s[:force_imv] == 2
        @force_integer_mv = f(1)
      else
        @force_integer_mv = s[:force_imv]
    else
      @force_integer_mv = 0
    @force_integer_mv = 1 if @frame_is_intra
    if id_len > 0
      @current_frame_id = f(id_len)
      # mark_ref_frames
      diff_len = s[:delta_frame_id_len]
      i = 0
      while i < 8
        cf = @current_frame_id
        if cf > (1 << diff_len)
          @ref_valid[i] = false if @ref_frame_id[i] > cf || @ref_frame_id[i] < cf - (1 << diff_len)
        else
          @ref_valid[i] = false if @ref_frame_id[i] > cf && @ref_frame_id[i] < (1 << id_len) + cf - (1 << diff_len)
        i += 1
    else
      @current_frame_id = 0
    if @frame_type == AV1_SWITCH_FRAME
      @frame_size_override_flag = 1
    elsif s[:reduced] == 1
      @frame_size_override_flag = 0
    else
      @frame_size_override_flag = f(1)
    @order_hint = f(@order_hint_bits)
    if @frame_is_intra || @error_resilient_mode == 1
      @primary_ref_frame = AV1_PRIMARY_REF_NONE
    else
      @primary_ref_frame = f(3)
    if s[:decoder_model_info] == 1
      if f(1) == 1
        op = 0
        while op < s[:op_idc].size
          if s[:dm_present][op] == 1
            idc = s[:op_idc][op]
            in_t = (idc >> @temporal_id) & 1
            in_s = (idc >> (@spatial_id + 8)) & 1
            f(s[:buffer_removal_time_length]) if idc == 0 || (in_t == 1 && in_s == 1)
          op += 1
    @allow_high_precision_mv = 0
    @use_ref_frame_mvs = 0
    @allow_intrabc = 0
    if @frame_type == AV1_SWITCH_FRAME || (@frame_type == AV1_KEY_FRAME && @show_frame == 1)
      @refresh_frame_flags = all_frames
    else
      @refresh_frame_flags = f(8)
    if !@frame_is_intra || @refresh_frame_flags != all_frames
      if @error_resilient_mode == 1 && @enable_order_hint == 1
        i = 0
        while i < 8
          roh = f(@order_hint_bits)
          if roh != @ref_order_hint[i]
            @ref_valid[i] = false
            # the spec allows decoders to synthesise a frame here; we just mark it
          i += 1
    if @frame_is_intra
      frame_size()
      render_size()
      if @allow_screen_content_tools == 1 && @upscaled_width == @frame_width
        @allow_intrabc = f(1)
    else
      @frame_refs_short_signaling = 0
      if @enable_order_hint == 1
        @frame_refs_short_signaling = f(1)
        if @frame_refs_short_signaling == 1
          @last_frame_idx = f(3)
          @gold_frame_idx = f(3)
          set_frame_refs()
      i = 0
      while i < 7
        @ref_frame_idx[i] = f(3) if @frame_refs_short_signaling == 0
        f(s[:delta_frame_id_len]) if id_len > 0
        i += 1
      if @frame_size_override_flag == 1 && @error_resilient_mode == 0
        frame_size_with_refs()
      else
        frame_size()
        render_size()
      if @force_integer_mv == 1
        @allow_high_precision_mv = 0
      else
        @allow_high_precision_mv = f(1)
      if f(1) == 1
        @interpolation_filter = 4
      else
        @interpolation_filter = f(2)
      @is_motion_mode_switchable = f(1)
      if @error_resilient_mode == 1 || s[:ref_frame_mvs] == 0
        @use_ref_frame_mvs = 0
      else
        @use_ref_frame_mvs = f(1)
      i = 0
      while i < 7
        rf = 1 + i
        hint = @ref_order_hint[@ref_frame_idx[i]]
        @order_hints[rf] = hint
        if @enable_order_hint == 0
          @ref_frame_sign_bias[rf] = 0
        else
          @ref_frame_sign_bias[rf] = get_relative_dist(hint, @order_hint) > 0 ? 1 : 0
        i += 1
    if s[:reduced] == 1 || @disable_cdf_update == 1
      @disable_frame_end_update_cdf = 1
    else
      @disable_frame_end_update_cdf = f(1)
    if @primary_ref_frame == AV1_PRIMARY_REF_NONE
      @cdf = av1_cdf_new_noncoeff()
      setup_past_independence()
    else
      load_cdfs(@ref_frame_idx[@primary_ref_frame])
      load_previous()
    motion_field_estimation() if @use_ref_frame_mvs == 1
    tile_info()
    quantization_params()
    segmentation_params()
    # delta_q_params
    @delta_q_res = 0
    @delta_q_present = 0
    @delta_q_present = f(1) if @base_q_idx > 0
    @delta_q_res = f(2) if @delta_q_present == 1
    # delta_lf_params
    @delta_lf_present = 0
    @delta_lf_res = 0
    @delta_lf_multi = 0
    if @delta_q_present == 1
      @delta_lf_present = f(1) if @allow_intrabc == 0
      if @delta_lf_present == 1
        @delta_lf_res = f(2)
        @delta_lf_multi = f(1)
    if @primary_ref_frame == AV1_PRIMARY_REF_NONE
      av1_cdf_init_coeff(@cdf, @base_q_idx)
    else
      load_previous_segment_ids()
    @coded_lossless = true
    @lossless_array = [false, false, false, false, false, false, false, false]
    @seg_qm_level = [[0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0], [0, 0, 0, 0, 0, 0, 0, 0]]
    sid = 0
    while sid < 8
      q = get_qindex(true, sid, 0)
      ll = q == 0 && @delta_q_y_dc == 0 && @delta_q_u_ac == 0 && @delta_q_u_dc == 0 && @delta_q_v_ac == 0 && @delta_q_v_dc == 0
      @lossless_array[sid] = ll
      @coded_lossless = false if !ll
      if @using_qmatrix == 1
        @seg_qm_level[0][sid] = ll ? 15 : @qm_y
        @seg_qm_level[1][sid] = ll ? 15 : @qm_u
        @seg_qm_level[2][sid] = ll ? 15 : @qm_v
      sid += 1
    @all_lossless = @coded_lossless && @frame_width == @upscaled_width
    loop_filter_params()
    cdef_params()
    lr_params()
    # read_tx_mode: 0 ONLY_4X4, 1 TX_MODE_LARGEST, 2 TX_MODE_SELECT
    if @coded_lossless
      @tx_mode = 0
    else
      @tx_mode = f(1) == 1 ? 2 : 1
    # frame_reference_mode
    @reference_select = @frame_is_intra ? 0 : f(1)
    skip_mode_params()
    if @frame_is_intra || @error_resilient_mode == 1 || s[:warped_motion] == 0
      @allow_warped_motion = 0
    else
      @allow_warped_motion = f(1)
    @reduced_tx_set = f(1)
    global_motion_params()
    film_grain_params()
    nil

  -> frame_size
    s = @seq
    if @frame_size_override_flag == 1
      @frame_width = f(s[:fw_bits]) + 1
      @frame_height = f(s[:fh_bits]) + 1
    else
      @frame_width = s[:max_w]
      @frame_height = s[:max_h]
    superres_params()
    compute_image_size()

  -> render_size
    if f(1) == 1
      @render_width = f(16) + 1
      @render_height = f(16) + 1
    else
      @render_width = @upscaled_width
      @render_height = @frame_height

  -> frame_size_with_refs
    found = 0
    i = 0
    while i < 7
      found = f(1)
      if found == 1
        k = @ref_frame_idx[i]
        @upscaled_width = @ref_upscaled_w[k]
        @frame_width = @upscaled_width
        @frame_height = @ref_frame_h[k]
        @render_width = @ref_render_w[k]
        @render_height = @ref_render_h[k]
        break
      i += 1
    if found == 0
      frame_size()
      render_size()
    else
      superres_params()
      compute_image_size()

  -> superres_params
    @use_superres = @enable_superres == 1 ? f(1) : 0
    if @use_superres == 1
      @superres_denom = f(3) + 9
    else
      @superres_denom = 8
    @upscaled_width = @frame_width
    @frame_width = (@upscaled_width * 8 + (@superres_denom >> 1)) / @superres_denom

  -> compute_image_size
    @mi_cols = 2 * ((@frame_width + 7) >> 3)
    @mi_rows = 2 * ((@frame_height + 7) >> 3)

  -> setup_past_independence
    @feature_enabled = av1_zero2(8, 8)
    @feature_data = av1_zero2(8, 8)
    @prev_segment_ids = nil
    @prev_gm_params = av1_gm_identity()
    @loop_filter_delta_enabled = 1
    @loop_filter_ref_deltas = [1, 0, 0, 0, -1, 0, -1, -1]
    @loop_filter_mode_deltas = [0, 0]
    nil

  -> load_cdfs(ctx)
    src = @saved_cdfs[ctx]
    raise Av1Error.new("av1: missing reference CDFs") if src == nil
    @cdf = av1_cdf_copy(src)
    av1_cdf_clear_counts(@cdf)

  -> load_previous
    prev = @ref_frame_idx[@primary_ref_frame]
    @prev_gm_params = av1_copy2(@saved_gm[prev])
    @loop_filter_ref_deltas = @saved_lf_ref[prev].dup
    @loop_filter_mode_deltas = @saved_lf_mode[prev].dup
    @feature_enabled = av1_copy2(@saved_feat_en[prev])
    @feature_data = av1_copy2(@saved_feat_data[prev])
    nil

  -> load_previous_segment_ids
    prev = @ref_frame_idx[@primary_ref_frame]
    @prev_segment_ids = nil
    if @segmentation_enabled == 1
      k = prev
      if @ref_mi_cols[k] == @mi_cols && @ref_mi_rows[k] == @mi_rows && @saved_seg_ids[k] != nil
        @prev_segment_ids = @saved_seg_ids[k]
    nil

  -> tile_info
    sb_cols = @sb128 == 1 ? ((@mi_cols + 31) >> 5) : ((@mi_cols + 15) >> 4)
    sb_rows = @sb128 == 1 ? ((@mi_rows + 31) >> 5) : ((@mi_rows + 15) >> 4)
    sb_shift = @sb128 == 1 ? 5 : 4
    sb_size = sb_shift + 2
    max_tw_sb = 4096 >> sb_size
    max_ta_sb = (4096 * 2304) >> (2 * sb_size)
    min_log2_tc = av1_tile_log2(max_tw_sb, sb_cols)
    max_log2_tc = av1_tile_log2(1, sb_cols < 64 ? sb_cols : 64)
    max_log2_tr = av1_tile_log2(1, sb_rows < 64 ? sb_rows : 64)
    min_log2_tiles = av1_tile_log2(max_ta_sb, sb_rows * sb_cols)
    min_log2_tiles = min_log2_tc if min_log2_tc > min_log2_tiles
    @mi_col_starts = []
    @mi_row_starts = []
    if f(1) == 1
      @tile_cols_log2 = min_log2_tc
      while @tile_cols_log2 < max_log2_tc
        break if f(1) == 0
        @tile_cols_log2 += 1
      tw = (sb_cols + (1 << @tile_cols_log2) - 1) >> @tile_cols_log2
      st = 0
      while st < sb_cols
        @mi_col_starts.push(st << sb_shift)
        st += tw
      @mi_col_starts.push(@mi_cols)
      @tile_cols = @mi_col_starts.size - 1
      min_log2_tr = min_log2_tiles - @tile_cols_log2
      min_log2_tr = 0 if min_log2_tr < 0
      @tile_rows_log2 = min_log2_tr
      while @tile_rows_log2 < max_log2_tr
        break if f(1) == 0
        @tile_rows_log2 += 1
      th = (sb_rows + (1 << @tile_rows_log2) - 1) >> @tile_rows_log2
      st = 0
      while st < sb_rows
        @mi_row_starts.push(st << sb_shift)
        st += th
      @mi_row_starts.push(@mi_rows)
      @tile_rows = @mi_row_starts.size - 1
    else
      widest = 0
      st = 0
      while st < sb_cols
        @mi_col_starts.push(st << sb_shift)
        mw = sb_cols - st
        mw = max_tw_sb if mw > max_tw_sb
        size = ns(mw) + 1
        widest = size if size > widest
        st += size
      @mi_col_starts.push(@mi_cols)
      @tile_cols = @mi_col_starts.size - 1
      @tile_cols_log2 = av1_tile_log2(1, @tile_cols)
      if min_log2_tiles > 0
        max_ta_sb = (sb_rows * sb_cols) >> (min_log2_tiles + 1)
      else
        max_ta_sb = sb_rows * sb_cols
      max_th = max_ta_sb / widest
      max_th = 1 if max_th < 1
      st = 0
      while st < sb_rows
        @mi_row_starts.push(st << sb_shift)
        mh = sb_rows - st
        mh = max_th if mh > max_th
        size = ns(mh) + 1
        st += size
      @mi_row_starts.push(@mi_rows)
      @tile_rows = @mi_row_starts.size - 1
      @tile_rows_log2 = av1_tile_log2(1, @tile_rows)
    if @tile_cols_log2 > 0 || @tile_rows_log2 > 0
      @context_update_tile_id = f(@tile_rows_log2 + @tile_cols_log2)
      @tile_size_bytes = f(2) + 1
    else
      @context_update_tile_id = 0
    nil

  -> read_delta_q
    f(1) == 1 ? su(7) : 0

  -> quantization_params
    @base_q_idx = f(8)
    @delta_q_y_dc = read_delta_q()
    @delta_q_u_dc = 0
    @delta_q_u_ac = 0
    @delta_q_v_dc = 0
    @delta_q_v_ac = 0
    if @num_planes > 1
      diff_uv = @seq[:sep_uv_dq] == 1 ? f(1) : 0
      @delta_q_u_dc = read_delta_q()
      @delta_q_u_ac = read_delta_q()
      if diff_uv == 1
        @delta_q_v_dc = read_delta_q()
        @delta_q_v_ac = read_delta_q()
      else
        @delta_q_v_dc = @delta_q_u_dc
        @delta_q_v_ac = @delta_q_u_ac
    @using_qmatrix = f(1)
    @qm_y = 15
    @qm_u = 15
    @qm_v = 15
    if @using_qmatrix == 1
      @qm_y = f(4)
      @qm_u = f(4)
      if @seq[:sep_uv_dq] == 0
        @qm_v = @qm_u
      else
        @qm_v = f(4)
    nil

  -> segmentation_params
    @segmentation_enabled = f(1)
    @segmentation_update_map = 0
    @segmentation_temporal_update = 0
    if @segmentation_enabled == 1
      upd = 0
      if @primary_ref_frame == AV1_PRIMARY_REF_NONE
        @segmentation_update_map = 1
        @segmentation_temporal_update = 0
        upd = 1
      else
        @segmentation_update_map = f(1)
        @segmentation_temporal_update = f(1) if @segmentation_update_map == 1
        upd = f(1)
      if upd == 1
        i = 0
        while i < 8
          j = 0
          while j < 8
            en = f(1)
            @feature_enabled[i][j] = en
            v = 0
            if en == 1
              bits = AV1_SEGMENTATION_FEATURE_BITS[j]
              lim = AV1_SEGMENTATION_FEATURE_MAX[j]
              if AV1_SEGMENTATION_FEATURE_SIGNED[j] == 1
                v = av1_clip3(0 - lim, lim, su(1 + bits))
              else
                v = av1_clip3(0, lim, f(bits))
            @feature_data[i][j] = v
            j += 1
          i += 1
    else
      @feature_enabled = av1_zero2(8, 8)
      @feature_data = av1_zero2(8, 8)
    @seg_id_pre_skip = 0
    @last_active_seg_id = 0
    i = 0
    while i < 8
      j = 0
      while j < 8
        if @feature_enabled[i][j] == 1
          @last_active_seg_id = i
          @seg_id_pre_skip = 1 if j >= 5
        j += 1
      i += 1
    nil

  # get_qindex( ignoreDeltaQ, segmentId ) with CurrentQIndex passed in.
  -> get_qindex(ignore_dq, sid, cur_q)
    if @segmentation_enabled == 1 && @feature_enabled[sid][0] == 1
      data = @feature_data[sid][0]
      q = @base_q_idx + data
      q = cur_q + data if !ignore_dq && @delta_q_present == 1
      return av1_clip3(0, 255, q)
    return cur_q if !ignore_dq && @delta_q_present == 1
    @base_q_idx

  -> loop_filter_params
    @loop_filter_level = [0, 0, 0, 0]
    @loop_filter_sharpness = 0
    if @coded_lossless || @allow_intrabc == 1
      @loop_filter_ref_deltas = [1, 0, 0, 0, -1, 0, -1, -1]
      @loop_filter_mode_deltas = [0, 0]
      return nil
    @loop_filter_level[0] = f(6)
    @loop_filter_level[1] = f(6)
    if @num_planes > 1
      if @loop_filter_level[0] != 0 || @loop_filter_level[1] != 0
        @loop_filter_level[2] = f(6)
        @loop_filter_level[3] = f(6)
    @loop_filter_sharpness = f(3)
    @loop_filter_delta_enabled = f(1)
    if @loop_filter_delta_enabled == 1
      if f(1) == 1
        i = 0
        while i < 8
          @loop_filter_ref_deltas[i] = su(7) if f(1) == 1
          i += 1
        i = 0
        while i < 2
          @loop_filter_mode_deltas[i] = su(7) if f(1) == 1
          i += 1
    nil

  -> cdef_params
    @cdef_bits = 0
    @cdef_y_pri = [0]
    @cdef_y_sec = [0]
    @cdef_uv_pri = [0]
    @cdef_uv_sec = [0]
    @cdef_damping = 3
    @cdef_on = false
    if @coded_lossless || @allow_intrabc == 1 || @enable_cdef == 0
      return nil
    @cdef_on = true
    @cdef_damping = f(2) + 3
    @cdef_bits = f(2)
    n = 1 << @cdef_bits
    @cdef_y_pri = []
    @cdef_y_sec = []
    @cdef_uv_pri = []
    @cdef_uv_sec = []
    i = 0
    while i < n
      @cdef_y_pri.push(f(4))
      v = f(2)
      v += 1 if v == 3
      @cdef_y_sec.push(v)
      if @num_planes > 1
        @cdef_uv_pri.push(f(4))
        v = f(2)
        v += 1 if v == 3
        @cdef_uv_sec.push(v)
      else
        @cdef_uv_pri.push(0)
        @cdef_uv_sec.push(0)
      i += 1
    nil

  -> lr_params
    @frame_restoration_type = [0, 0, 0]
    @uses_lr = false
    @loop_restoration_size = [256, 256, 256]
    if @all_lossless || @allow_intrabc == 1 || @enable_restoration == 0
      return nil
    uses_chroma = false
    i = 0
    while i < @num_planes
      t = AV1_REMAP_LR_TYPE[f(2)]
      @frame_restoration_type[i] = t
      if t != 0
        @uses_lr = true
        uses_chroma = true if i > 0
      i += 1
    if @uses_lr
      sh = 0
      if @sb128 == 1
        sh = f(1) + 1
      else
        sh = f(1)
        sh += f(1) if sh == 1
      @loop_restoration_size[0] = 256 >> (2 - sh)
      uv = 0
      uv = f(1) if @ssx == 1 && @ssy == 1 && uses_chroma
      @loop_restoration_size[1] = @loop_restoration_size[0] >> uv
      @loop_restoration_size[2] = @loop_restoration_size[0] >> uv
    nil

  -> skip_mode_params
    allowed = false
    @skip_mode_frame = [0, 0]
    if !@frame_is_intra && @reference_select == 1 && @enable_order_hint == 1
      fwd = -1
      bwd = -1
      fwd_h = 0
      bwd_h = 0
      i = 0
      while i < 7
        rh = @ref_order_hint[@ref_frame_idx[i]]
        if get_relative_dist(rh, @order_hint) < 0
          if fwd < 0 || get_relative_dist(rh, fwd_h) > 0
            fwd = i
            fwd_h = rh
        elsif get_relative_dist(rh, @order_hint) > 0
          if bwd < 0 || get_relative_dist(rh, bwd_h) < 0
            bwd = i
            bwd_h = rh
        i += 1
      if fwd < 0
        allowed = false
      elsif bwd >= 0
        allowed = true
        @skip_mode_frame = [1 + (fwd < bwd ? fwd : bwd), 1 + (fwd > bwd ? fwd : bwd)]
      else
        sec = -1
        sec_h = 0
        i = 0
        while i < 7
          rh = @ref_order_hint[@ref_frame_idx[i]]
          if get_relative_dist(rh, fwd_h) < 0
            if sec < 0 || get_relative_dist(rh, sec_h) > 0
              sec = i
              sec_h = rh
          i += 1
        if sec >= 0
          allowed = true
          @skip_mode_frame = [1 + (fwd < sec ? fwd : sec), 1 + (fwd > sec ? fwd : sec)]
    @skip_mode_present = allowed ? f(1) : 0
    nil

  -> global_motion_params
    @gm_type = [0, 0, 0, 0, 0, 0, 0, 0]
    @gm_params = av1_gm_identity()
    return nil if @frame_is_intra
    rf = 1
    while rf <= 7
      typ = 0
      if f(1) == 1
        if f(1) == 1
          typ = 2
        else
          typ = f(1) == 1 ? 1 : 3
      @gm_type[rf] = typ
      if typ >= 2
        read_global_param(typ, rf, 2)
        read_global_param(typ, rf, 3)
        if typ == 3
          read_global_param(typ, rf, 4)
          read_global_param(typ, rf, 5)
        else
          @gm_params[rf][4] = 0 - @gm_params[rf][3]
          @gm_params[rf][5] = @gm_params[rf][2]
      if typ >= 1
        read_global_param(typ, rf, 0)
        read_global_param(typ, rf, 1)
      rf += 1
    nil

  -> read_global_param(typ, rf, idx)
    abs_bits = 12
    prec_bits = 15
    if idx < 2
      if typ == 1
        hp = @allow_high_precision_mv == 1 ? 0 : 1
        abs_bits = 9 - hp
        prec_bits = 3 - hp
      else
        abs_bits = 12
        prec_bits = 6
    prec_diff = 16 - prec_bits
    rnd = (idx % 3) == 2 ? (1 << 16) : 0
    sub = (idx % 3) == 2 ? (1 << prec_bits) : 0
    mx = 1 << abs_bits
    r = (@prev_gm_params[rf][idx] >> prec_diff) - sub
    @gm_params[rf][idx] = (decode_signed_subexp_with_ref(0 - mx, mx + 1, r) << prec_diff) + rnd

  -> decode_signed_subexp_with_ref(low, high, r)
    decode_unsigned_subexp_with_ref(high - low, r - low) + low

  -> decode_unsigned_subexp_with_ref(mx, r)
    v = decode_subexp(mx)
    if (r << 1) <= mx
      av1_inverse_recenter(r, v)
    else
      mx - 1 - av1_inverse_recenter(mx - 1 - r, v)

  -> decode_subexp(num_syms)
    i = 0
    mk = 0
    k = 3
    while true
      b2 = i > 0 ? k + i - 1 : k
      a = 1 << b2
      if num_syms <= mk + 3 * a
        return ns(num_syms - mk) + mk
      if f(1) == 1
        i += 1
        mk += a
      else
        return f(b2) + mk

  -> film_grain_params
    @apply_grain = 0
    @grain = nil
    s = @seq
    return nil if s[:film_grain] == 0 || (@show_frame == 0 && @showable_frame == 0)
    @apply_grain = f(1)
    return nil if @apply_grain == 0
    g = {}
    g[:seed] = f(16)
    upd = @frame_type == AV1_INTER_FRAME ? f(1) : 1
    if upd == 0
      idx = f(3)
      seed = g[:seed]
      old = @saved_grain[idx]
      raise Av1Error.new("av1: missing film grain reference") if old == nil
      g = old.dup
      g[:seed] = seed
      @grain = g
      return nil
    ny = f(4)
    g[:y_points] = []
    i = 0
    while i < ny
      g[:y_points].push([f(8), f(8)])
      i += 1
    g[:cfl] = @mono ? 0 : f(1)
    g[:cb_points] = []
    g[:cr_points] = []
    if !(@mono || g[:cfl] == 1 || (@ssx == 1 && @ssy == 1 && ny == 0))
      n = f(4)
      i = 0
      while i < n
        g[:cb_points].push([f(8), f(8)])
        i += 1
      n = f(4)
      i = 0
      while i < n
        g[:cr_points].push([f(8), f(8)])
        i += 1
    g[:scaling_shift] = f(2) + 8
    lag = f(2)
    g[:lag] = lag
    npl = 2 * lag * (lag + 1)
    npc = npl
    g[:ar_y] = []
    if ny > 0
      npc = npl + 1
      i = 0
      while i < npl
        g[:ar_y].push(f(8) - 128)
        i += 1
    g[:ar_cb] = []
    g[:ar_cr] = []
    if g[:cfl] == 1 || g[:cb_points].size > 0
      i = 0
      while i < npc
        g[:ar_cb].push(f(8) - 128)
        i += 1
    if g[:cfl] == 1 || g[:cr_points].size > 0
      i = 0
      while i < npc
        g[:ar_cr].push(f(8) - 128)
        i += 1
    g[:ar_shift] = f(2) + 6
    g[:grain_scale_shift] = f(2)
    if g[:cb_points].size > 0
      g[:cb_mult] = f(8)
      g[:cb_luma_mult] = f(8)
      g[:cb_offset] = f(9)
    if g[:cr_points].size > 0
      g[:cr_mult] = f(8)
      g[:cr_luma_mult] = f(8)
      g[:cr_offset] = f(9)
    g[:overlap] = f(1)
    g[:clip_restricted] = f(1)
    @grain = g
    nil

  # set frame refs process (7.8)
  -> set_frame_refs
    i = 0
    while i < 7
      @ref_frame_idx[i] = -1
      i += 1
    @ref_frame_idx[0] = @last_frame_idx
    @ref_frame_idx[3] = @gold_frame_idx
    used = [false, false, false, false, false, false, false, false]
    used[@last_frame_idx] = true
    used[@gold_frame_idx] = true
    cur = 1 << (@order_hint_bits - 1)
    sh = []
    i = 0
    while i < 8
      sh.push(cur + get_relative_dist(@ref_order_hint[i], @order_hint))
      i += 1
    # ALTREF: latest backward
    ref = -1
    best = 0
    i = 0
    while i < 8
      h = sh[i]
      if !used[i] && h >= cur && (ref < 0 || h >= best)
        ref = i
        best = h
      i += 1
    if ref >= 0
      @ref_frame_idx[6] = ref
      used[ref] = true
    # BWDREF then ALTREF2: earliest backward
    [4, 5].each ->(slot)
      ref = -1
      best = 0
      i = 0
      while i < 8
        h = sh[i]
        if !used[i] && h >= cur && (ref < 0 || h < best)
          ref = i
          best = h
        i += 1
      if ref >= 0
        @ref_frame_idx[slot] = ref
        used[ref] = true
    # remaining: latest forward, in Ref_Frame_List order
    AV1_REF_FRAME_LIST.each ->(rf)
      if @ref_frame_idx[rf - 1] < 0
        ref = -1
        best = 0
        i = 0
        while i < 8
          h = sh[i]
          if !used[i] && h < cur && (ref < 0 || h >= best)
            ref = i
            best = h
          i += 1
        if ref >= 0
          @ref_frame_idx[rf - 1] = ref
          used[ref] = true
    ref = -1
    best = 0
    i = 0
    while i < 8
      h = sh[i]
      if ref < 0 || h < best
        ref = i
        best = h
      i += 1
    i = 0
    while i < 7
      @ref_frame_idx[i] = ref if @ref_frame_idx[i] < 0
      i += 1
    nil

  # ------------------------------------------------------------ tile groups

  -> tile_group_obu(start, sz)
    rb_init(@data, start)
    num_tiles = @tile_cols * @tile_rows
    s0 = @bitpos
    tse = 0
    tse = f(1) if num_tiles > 1
    tg_start = 0
    tg_end = num_tiles - 1
    if num_tiles > 1 && tse == 1
      bits = @tile_cols_log2 + @tile_rows_log2
      tg_start = f(bits)
      tg_end = f(bits)
    byte_align()
    sz -= (@bitpos - s0) >> 3
    pos = @bitpos >> 3
    if tg_start == 0
      frame_begin()
    tn = tg_start
    while tn <= tg_end
      tile_row = tn / @tile_cols
      tile_col = tn % @tile_cols
      tsize = 0
      if tn == tg_end
        tsize = sz
      else
        rb_init(@data, pos)
        tsize = le(@tile_size_bytes) + 1
        pos += @tile_size_bytes
        sz -= tsize + @tile_size_bytes
      raise Av1Error.new("av1: tile overruns tile group") if tsize < 0 || pos + tsize > @data.size
      @tile_num = tn
      decode_tile_at(pos, tsize, @mi_row_starts[tile_row], @mi_row_starts[tile_row + 1], @mi_col_starts[tile_col], @mi_col_starts[tile_col + 1])
      pos += tsize
      tn += 1
    if tg_end == num_tiles - 1
      if @disable_frame_end_update_cdf == 0
        @cdf = @saved_tile_cdf
        av1_cdf_clear_counts(@cdf)
      decode_frame_wrapup()
      @seen_frame_header = false
    nil

  # ------------------------------------------------------------ frame end

  -> show_existing
    k = @frame_to_show_map_idx
    fr = @ref_frames[k]
    raise Av1Error.new("av1: show_existing_frame of an empty slot") if fr == nil
    if @frame_type == AV1_KEY_FRAME
      # reference frame loading process, then refresh all slots with it
      @upscaled_width = @ref_upscaled_w[k]
      @frame_width = @ref_frame_w[k]
      @frame_height = @ref_frame_h[k]
      @render_width = @ref_render_w[k]
      @render_height = @ref_render_h[k]
      @mi_cols = @ref_mi_cols[k]
      @mi_rows = @ref_mi_rows[k]
      @order_hint = @ref_order_hint[k]
      @cur = fr
      @gm_params = av1_copy2(@saved_gm[k])
      @cdf = av1_cdf_copy(@saved_cdfs[k])
      av1_cdf_clear_counts(@cdf)
      @loop_filter_ref_deltas = @saved_lf_ref[k].dup
      @loop_filter_mode_deltas = @saved_lf_mode[k].dup
      @feature_enabled = av1_copy2(@saved_feat_en[k])
      @feature_data = av1_copy2(@saved_feat_data[k])
      @segment_ids = @saved_seg_ids[k]
      @grain = @saved_grain[k]
      @order_hints = @saved_order_hints[k].dup
      @mf_refs = @saved_mf_refs[k]
      @mf_mvs = @saved_mf_mvs[k]
      @show_frame = 1
      reference_update()
    g = @saved_grain[k]
    if @seq[:film_grain] == 1 && g != nil
      fr = av1_apply_grain(fr, g, @seq[:mc])
    @frames_out.push(fr)
    nil

  -> decode_frame_wrapup
    post_filters()
    if @segmentation_enabled == 1 && @segmentation_update_map == 0 && @prev_segment_ids != nil
      @segment_ids = @prev_segment_ids
    mf_store()
    reference_update()
    if @show_frame == 1
      @cur.show = true
      if @apply_grain == 1 && @grain != nil
        @frames_out.push(av1_apply_grain(@cur, @grain, @seq[:mc]))
      else
        @frames_out.push(@cur)
    nil

  -> reference_update
    i = 0
    while i < 8
      if ((@refresh_frame_flags >> i) & 1) == 1
        @ref_valid[i] = true
        @ref_frame_id[i] = @current_frame_id
        @ref_upscaled_w[i] = @upscaled_width
        @ref_frame_w[i] = @frame_width
        @ref_frame_h[i] = @frame_height
        @ref_render_w[i] = @render_width
        @ref_render_h[i] = @render_height
        @ref_mi_cols[i] = @mi_cols
        @ref_mi_rows[i] = @mi_rows
        @ref_frame_type[i] = @frame_type
        @ref_ssx[i] = @ssx
        @ref_ssy[i] = @ssy
        @ref_bit_depth[i] = @bit_depth
        @ref_order_hint[i] = @order_hint
        @saved_order_hints[i] = @order_hints.dup
        @ref_frames[i] = @cur
        @saved_gm[i] = av1_copy2(@gm_params)
        @saved_seg_ids[i] = @segment_ids
        @saved_mf_refs[i] = @mf_refs
        @saved_mf_mvs[i] = @mf_mvs
        @saved_cdfs[i] = av1_cdf_copy(@cdf)
        @saved_grain[i] = @grain
        @saved_lf_ref[i] = @loop_filter_ref_deltas.dup
        @saved_lf_mode[i] = @loop_filter_mode_deltas.dup
        @saved_feat_en[i] = av1_copy2(@feature_enabled)
        @saved_feat_data[i] = av1_copy2(@feature_data)
      i += 1
    nil


# ---------------------------------------------------------------- helpers

-> av1_clip3(lo, hi, x)
  x < lo ? lo : (x > hi ? hi : x)

-> av1_tile_log2(blk, target)
  k = 0
  while (blk << k) < target
    k += 1
  k

-> av1_inverse_recenter(r, v)
  if v > 2 * r
    v
  elsif (v & 1) != 0
    r - ((v + 1) >> 1)
  else
    r + (v >> 1)

-> av1_zero2(a, b)
  out = []
  i = 0
  while i < a
    row = []
    j = 0
    while j < b
      row.push(0)
      j += 1
    out.push(row)
    i += 1
  out

-> av1_copy2(m)
  m.map(->(r) r.dup)

-> av1_gm_identity
  out = []
  i = 0
  while i < 8
    out.push([0, 0, 1 << 16, 0, 0, 1 << 16])
    i += 1
  out

# ---------------------------------------------------------------- AVIF / video glue

# Av1Frame → HeifPic (cropped to the frame size, planes copied tight).
-> av1_frame_to_pic(fr)
  pic = HeifPic.new(fr.width, fr.height, fr.bit_depth, fr.ssx, fr.ssy, fr.mono)
  pic.cicp = [fr.cp, fr.tc, fr.mc, fr.full_range]
  k = 0
  while k < pic.planes.size
    av1_crop_plane(fr.planes[k], fr.strides[k], pic.planes[k], pic.pw(k), pic.ph(k))
    k += 1
  pic

-> av1_crop_plane(src, ss, dst, w, h) (u16[] i64 u16[] i64 i64) i64
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      dst[y * w + x] = src[y * ss + x]
      x += 1
    y += 1
  0

# Decode an AVIF item: av1C config OBUs (if any) then the item's OBUs; the
# first shown frame is the picture.
-> av1_decode_still(cfg, data)
  d = Av1Decoder.new
  if cfg != nil && cfg.size > 4
    d.decode(hf_slice(cfg, 4, cfg.size - 4))
  frames = d.decode(data)
  raise HeifError.new("avif: no frame decoded") if frames.size == 0
  av1_frame_to_pic(frames[0])

-> av1_heif_item(f, it, data)
  c = it.prop("av1C")
  av1_decode_still(c == nil ? nil : c.f[:data], data)

heif_codec_register("av01", ->(f, it, data) av1_heif_item(f, it, data))
heif_codec_register("track:av01", ->(cfg, sample) av1_decode_still(cfg, sample))

# mediacore video decoder for "av01".
+ Av1VideoDecoder
  -> new(@cfg)
    @dec = Av1Decoder.new
    ex = @cfg.extra
    if ex != nil && ex.size > 4
      @dec.decode(hf_slice(ex, 4, ex.size - 4))

  -> decode(sample)
    out = []
    @dec.decode(sample.data).each ->(fr)
      out.push(av1_video_frame(fr, sample.pts, sample.duration))
    out

  -> flush
    []

  -> reset
    @dec.reset
    nil

-> av1_video_frame(fr, pts, dur)
  pic = av1_frame_to_pic(fr)
  planes = []
  strides = []
  k = 0
  while k < pic.planes.size
    w = pic.pw(k)
    n = w * pic.ph(k)
    if pic.bit_depth == 8
      b = ByteArray.new(n)
      av1_u16_to_u8(pic.planes[k], b, n)
      planes.push(b)
    else
      planes.push(pic.planes[k])
    strides.push(w)
    k += 1
  chroma = pic.mono ? "400" : (pic.ssx == 1 ? (pic.ssy == 1 ? "420" : "422") : "444")
  vf = VideoFrame.new(pic.width, pic.height, planes, strides, chroma, pic.bit_depth, pts)
  vf.duration = dur
  vf.primaries = fr.cp
  vf.transfer = fr.tc
  vf.matrix = fr.mc
  vf.full_range = fr.full_range
  vf

-> av1_u16_to_u8(a, b, n) (u16[] u8[] i64) i64
  i = 0 ## i64
  while i < n
    b[i] = a[i]
    i += 1
  0

vcodec_register("av01", ->(cfg) Av1VideoDecoder.new(cfg))
