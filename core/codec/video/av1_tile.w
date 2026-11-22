# core/codec/video/av1_tile — AV1 tile decoding: superblock / partition walk, intra mode
# info, palette, transform sizes and types, coefficient reading (spec
# sections 5.11, 8.3). Reopens Av1Decoder.

use av1_tables
use av1_cdf

# typed copies of hot lookup tables
-> av1_i32(a)
  out = i32[a.size]
  i = 0
  while i < a.size
    out[i] = a[i]
    i += 1
  out

AV1_BW4 = av1_i32(AV1_NUM_4X4_BLOCKS_WIDE)
AV1_BH4 = av1_i32(AV1_NUM_4X4_BLOCKS_HIGH)
AV1_MIWL = av1_i32(AV1_MI_WIDTH_LOG2)
AV1_MIHL = av1_i32(AV1_MI_HEIGHT_LOG2)
AV1_TXW = av1_i32(AV1_TX_WIDTH)
AV1_TXH = av1_i32(AV1_TX_HEIGHT)
AV1_TXWL = av1_i32(AV1_TX_WIDTH_LOG2)
AV1_TXHL = av1_i32(AV1_TX_HEIGHT_LOG2)
AV1_SIG_REF = av1_i32(AV1_SIG_REF_DIFF_OFFSET)
AV1_CB_CTX_OFF = av1_i32(AV1_COEFF_BASE_CTX_OFFSET)
AV1_MAG_REF = av1_i32(AV1_MAG_REF_OFFSET_WITH_TX_CLASS)

# scan tables by tx size and kind (0 default, 1 mrow, 2 mcol); nil if none
-> av1_build_scans
  d = [AV1_DEFAULT_SCAN_4X4, AV1_DEFAULT_SCAN_8X8, AV1_DEFAULT_SCAN_16X16, AV1_DEFAULT_SCAN_32X32, AV1_DEFAULT_SCAN_32X32,
       AV1_DEFAULT_SCAN_4X8, AV1_DEFAULT_SCAN_8X4, AV1_DEFAULT_SCAN_8X16, AV1_DEFAULT_SCAN_16X8, AV1_DEFAULT_SCAN_16X32,
       AV1_DEFAULT_SCAN_32X16, AV1_DEFAULT_SCAN_32X32, AV1_DEFAULT_SCAN_32X32, AV1_DEFAULT_SCAN_4X16, AV1_DEFAULT_SCAN_16X4,
       AV1_DEFAULT_SCAN_8X32, AV1_DEFAULT_SCAN_32X8, AV1_DEFAULT_SCAN_16X32, AV1_DEFAULT_SCAN_32X16]
  r = [AV1_MROW_SCAN_4X4, AV1_MROW_SCAN_8X8, AV1_MROW_SCAN_16X16, nil, nil, AV1_MROW_SCAN_4X8, AV1_MROW_SCAN_8X4,
       AV1_MROW_SCAN_8X16, AV1_MROW_SCAN_16X8, nil, nil, nil, nil, AV1_MROW_SCAN_4X16, AV1_MROW_SCAN_16X4, nil, nil, nil, nil]
  c = [AV1_MCOL_SCAN_4X4, AV1_MCOL_SCAN_8X8, AV1_MCOL_SCAN_16X16, nil, nil, AV1_MCOL_SCAN_4X8, AV1_MCOL_SCAN_8X4,
       AV1_MCOL_SCAN_8X16, AV1_MCOL_SCAN_16X8, nil, nil, nil, nil, AV1_MCOL_SCAN_4X16, AV1_MCOL_SCAN_16X4, nil, nil, nil, nil]
  out = []
  [d, r, c].each ->(l)
    out.push(l.map(->(x) x == nil ? nil : av1_i32(x)))
  out

AV1_SCANS = av1_build_scans()

-> av1_tables_init
  nil

+ Av1Decoder
  # ------------------------------------------------------------ frame setup

  # Allocate the frame buffer and per-4x4 state for a new frame.
  -> frame_begin
    al = @sb128 == 1 ? 128 : 64
    aw = ((@mi_cols * 4 + al - 1) / al) * al + 32
    ah = ((@mi_rows * 4 + al - 1) / al) * al + 32
    @cur = Av1Frame.new(@upscaled_width, @frame_height, @bit_depth, @ssx, @ssy, @mono, aw, ah)
    @cur.frame_type = @frame_type
    @cur.render_w = @render_width
    @cur.render_h = @render_height
    @cur.cp = @seq[:cp]
    @cur.tc = @seq[:tc]
    @cur.mc = @seq[:mc]
    @cur.full_range = @seq[:color_range] == 1
    @fw = aw
    @fh = ah
    n = @mi_rows * @mi_cols
    @mis = @mi_cols
    @a_y_modes = u8[n]
    @a_uv_modes = u8[n]
    @a_ref0 = i32[n]
    @a_mi_sizes = u8[n]
    @a_skips = u8[n]
    @a_is_inters = u8[n]
    @a_tx_sizes = u8[n]
    @a_inter_tx_sizes = u8[n]
    @a_seg_ids = u8[n]
    @a_pal_sizes0 = u8[n]
    @a_pal_sizes1 = u8[n]
    @a_pal_colors0 = u16[n * 8]
    @a_pal_colors1 = u16[n * 8]
    @a_delta_lf = i32[n * 4]
    @a_tx_types = u8[n]
    @a_lf_tx = [u8[n], u8[n], u8[n]]
    @a_cdef_idx = i32[n]
    @a_skip_modes = u8[n]
    @segment_ids = @a_seg_ids
    inter_frame_begin(n)
    @delta_lf = [0, 0, 0, 0]
    # loop restoration units per plane
    @lr_type = []
    @lr_wiener = []
    @lr_sgr_set = []
    @lr_sgr_xqd = []
    @lr_unit_rows = []
    @lr_unit_cols = []
    p = 0
    while p < @num_planes
      sx = p == 0 ? 0 : @ssx
      sy = p == 0 ? 0 : @ssy
      us = @loop_restoration_size[p]
      ur = av1_count_units(us, av1_round2(@frame_height, sy))
      uc = av1_count_units(us, av1_round2(@upscaled_width, sx))
      @lr_unit_rows.push(ur)
      @lr_unit_cols.push(uc)
      @lr_type.push(u8[ur * uc])
      @lr_wiener.push(i32[ur * uc * 6])
      @lr_sgr_set.push(u8[ur * uc])
      @lr_sgr_xqd.push(i32[ur * uc * 2])
      p += 1
    # dequant: per segment [plane][dc, ac]
    @quant = i32[1024]
    @dequant_buf = i32[4096]
    @st = i64[8]
    @block_decoded = [u8[34 * 34], u8[34 * 34], u8[34 * 34]]
    @color_map_y = u8[64 * 64]
    @color_map_uv = u8[64 * 64]
    @cdf_offsets_ready = false
    cdf_offsets()
    recon_begin()
    nil

  -> cdf_offsets
    l = AV1_CDF_LAYOUT
    @o_y_mode = l[:y_mode][0]
    @o_uv_nocfl = l[:uv_mode_cfl_not_allowed][0]
    @o_uv_cfl = l[:uv_mode_cfl_allowed][0]
    @o_angle = l[:angle_delta][0]
    @o_intrabc = l[:intrabc][0]
    @o_part = [0, l[:partition_w8][0], l[:partition_w16][0], l[:partition_w32][0], l[:partition_w64][0], l[:partition_w128][0]]
    @o_seg = l[:segment_id][0]
    @o_seg_pred = l[:segment_id_predicted][0]
    @o_tx = [l[:tx_8x8][0], l[:tx_16x16][0], l[:tx_32x32][0], l[:tx_64x64][0]]
    @o_txfm_split = l[:txfm_split][0]
    @o_fi_mode = l[:filter_intra_mode][0]
    @o_fi = l[:filter_intra][0]
    @o_skip = l[:skip][0]
    @o_skip_mode = l[:skip_mode][0]
    @o_pal_y_mode = l[:palette_y_mode][0]
    @o_pal_uv_mode = l[:palette_uv_mode][0]
    @o_pal_y_size = l[:palette_y_size][0]
    @o_pal_uv_size = l[:palette_uv_size][0]
    @o_pal_y_color = [0, 0, l[:palette_2_y_color][0], l[:palette_3_y_color][0], l[:palette_4_y_color][0], l[:palette_5_y_color][0], l[:palette_6_y_color][0], l[:palette_7_y_color][0], l[:palette_8_y_color][0]]
    @o_pal_uv_color = [0, 0, l[:palette_2_uv_color][0], l[:palette_3_uv_color][0], l[:palette_4_uv_color][0], l[:palette_5_uv_color][0], l[:palette_6_uv_color][0], l[:palette_7_uv_color][0], l[:palette_8_uv_color][0]]
    @o_delta_q = l[:delta_q][0]
    @o_delta_lf = l[:delta_lf][0]
    @o_delta_lf_multi = l[:delta_lf_multi][0]
    @o_intra_tx1 = l[:intra_tx_set1][0]
    @o_intra_tx2 = l[:intra_tx_set2][0]
    @o_inter_tx1 = l[:inter_tx_set1][0]
    @o_inter_tx2 = l[:inter_tx_set2][0]
    @o_inter_tx3 = l[:inter_tx_set3][0]
    @o_cfl_sign = l[:cfl_sign][0]
    @o_cfl_alpha = l[:cfl_alpha][0]
    @o_use_wiener = l[:use_wiener][0]
    @o_use_sgrproj = l[:use_sgrproj][0]
    @o_restoration_type = l[:restoration_type][0]
    @o_ify = l[:intra_frame_y_mode][0]
    @o_txb_skip = l[:txb_skip][0]
    @o_eob_pt = [l[:eob_pt_16][0], l[:eob_pt_32][0], l[:eob_pt_64][0], l[:eob_pt_128][0], l[:eob_pt_256][0], l[:eob_pt_512][0], l[:eob_pt_1024][0]]
    @o_eob_extra = l[:eob_extra][0]
    @o_dc_sign = l[:dc_sign][0]
    @o_cb_eob = l[:coeff_base_eob][0]
    @o_cb = l[:coeff_base][0]
    @o_br = l[:coeff_br][0]
    @o_is_inter = l[:is_inter][0]
    nil

  # ------------------------------------------------------------ tiles

  -> decode_tile_at(pos, size, r0, r1, c0, c1)
    @mi_row_start = r0
    @mi_row_end = r1
    @mi_col_start = c0
    @mi_col_end = c1
    @current_q_index = @base_q_idx
    @tcdf = av1_cdf_copy(@cdf)
    # TileIntraFrameYModeCdf always starts from the default table
    av1_copy_i32(AV1_CDF[2], @o_ify, @tcdf, @o_ify, AV1_DEFAULT_INTRA_FRAME_Y_MODE_CDF.size)
    @d = @data
    av1_sym_init(@st, @d, pos, size, @disable_cdf_update)
    decode_tile()
    if @disable_frame_end_update_cdf == 0 && @tile_num == @context_update_tile_id
      @saved_tile_cdf = @tcdf
    nil

  -> decode_tile
    # clear_above_context
    w = @mi_cols + 32
    @above_level = [u8[w], u8[w], u8[w]]
    @above_dc = [u8[w], u8[w], u8[w]]
    @above_seg_pred = u8[w]
    @delta_lf = [0, 0, 0, 0]
    @ref_sgr_xqd = [[-32, 31], [-32, 31], [-32, 31]]
    @ref_lr_wiener = [[[3, -7, 15], [3, -7, 15]], [[3, -7, 15], [3, -7, 15]], [[3, -7, 15], [3, -7, 15]]]
    sb_size = @sb128 == 1 ? 15 : 12
    sb4 = AV1_BW4[sb_size]
    h = @mi_rows + 32
    r = @mi_row_start
    while r < @mi_row_end
      @left_level = [u8[h], u8[h], u8[h]]
      @left_dc = [u8[h], u8[h], u8[h]]
      @left_seg_pred = u8[h]
      c = @mi_col_start
      while c < @mi_col_end
        @read_deltas = @delta_q_present == 1
        clear_cdef(r, c)
        clear_block_decoded_flags(r, c, sb4)
        read_lr(r, c, sb_size)
        decode_partition(r, c, sb_size)
        c += sb4
      r += sb4
    nil

  -> clear_block_decoded_flags(r, c, sb4)
    p = 0
    while p < @num_planes
      sx = p > 0 ? @ssx : 0
      sy = p > 0 ? @ssy : 0
      sbw4 = (@mi_col_end - c) >> sx
      sbh4 = (@mi_row_end - r) >> sy
      av1_clear_bd(@block_decoded[p], sb4 >> sx, sb4 >> sy, sbw4, sbh4)
      p += 1
    nil

  -> clear_cdef(r, c)
    @a_cdef_idx[r * @mis + c] = -1
    if @sb128 == 1
      if c + 16 < @mi_cols
        @a_cdef_idx[r * @mis + c + 16] = -1
      if r + 16 < @mi_rows
        @a_cdef_idx[(r + 16) * @mis + c] = -1
        @a_cdef_idx[(r + 16) * @mis + c + 16] = -1 if c + 16 < @mi_cols

  -> is_inside(r, c)
    c >= @mi_col_start && c < @mi_col_end && r >= @mi_row_start && r < @mi_row_end

  # ------------------------------------------------------------ symbols

  -> sym(off, n)
    av1_sym(@st, @d, @tcdf, off, n)

  -> lit(n)
    av1_lit(@st, @d, n)

  -> sym_ns(n)
    w = 0
    x = n
    while x != 0
      x = x >> 1
      w += 1
    m = (1 << w) - n
    v = lit(w - 1)
    return v if v < m
    e = lit(1)
    (v << 1) - m + e

  # ------------------------------------------------------------ partition

  -> decode_partition(r, c, bsize)
    return nil if r >= @mi_rows || c >= @mi_cols
    avail_u = is_inside(r - 1, c)
    avail_l = is_inside(r, c - 1)
    num4 = AV1_BW4[bsize]
    half = num4 >> 1
    quarter = half >> 1
    has_rows = (r + half) < @mi_rows
    has_cols = (c + half) < @mi_cols
    partition = 3
    if bsize < 3
      partition = 0
    else
      bsl = AV1_MIWL[bsize]
      above = avail_u && AV1_MIWL[@a_mi_sizes[(r - 1) * @mis + c]] < bsl ? 1 : 0
      left = avail_l && AV1_MIHL[@a_mi_sizes[r * @mis + c - 1]] < bsl ? 1 : 0
      ctx = left * 2 + above
      nsym = bsl == 1 ? 4 : (bsl == 5 ? 8 : 10)
      off = @o_part[bsl] + ctx * (nsym + 1)
      if has_rows && has_cols
        partition = sym(off, nsym)
      elsif has_cols
        partition = split_or(off, bsize, true) == 1 ? 3 : 1
      elsif has_rows
        partition = split_or(off, bsize, false) == 1 ? 3 : 2
      else
        partition = 3
    sub = AV1_PARTITION_SUBSIZE[partition * 22 + bsize]
    split = AV1_PARTITION_SUBSIZE[3 * 22 + bsize]
    case partition
      when 0
        decode_block(r, c, sub)
      when 1
        decode_block(r, c, sub)
        decode_block(r + half, c, sub) if has_rows
      when 2
        decode_block(r, c, sub)
        decode_block(r, c + half, sub) if has_cols
      when 3
        decode_partition(r, c, sub)
        decode_partition(r, c + half, sub)
        decode_partition(r + half, c, sub)
        decode_partition(r + half, c + half, sub)
      when 4
        decode_block(r, c, split)
        decode_block(r, c + half, split)
        decode_block(r + half, c, sub)
      when 5
        decode_block(r, c, sub)
        decode_block(r + half, c, split)
        decode_block(r + half, c + half, split)
      when 6
        decode_block(r, c, split)
        decode_block(r + half, c, split)
        decode_block(r, c + half, sub)
      when 7
        decode_block(r, c, sub)
        decode_block(r, c + half, split)
        decode_block(r + half, c + half, split)
      when 8
        decode_block(r, c, sub)
        decode_block(r + quarter, c, sub)
        decode_block(r + quarter * 2, c, sub)
        decode_block(r + quarter * 3, c, sub) if r + quarter * 3 < @mi_rows
      else
        decode_block(r, c, sub)
        decode_block(r, c + quarter, sub)
        decode_block(r, c + quarter * 2, sub)
        decode_block(r, c + quarter * 3, sub) if c + quarter * 3 < @mi_cols
    nil

  # split_or_horz (horz true) / split_or_vert from the partition cdf at off
  -> split_or(off, bsize, horz)
    cdf = @tcdf
    psum = 0
    parts = horz ? [2, 3, 4, 6, 7] : [1, 3, 4, 5, 6]
    parts.each ->(p)
      psum += av1_pprob(cdf, off, p)
    if bsize != 15
      psum += av1_pprob(cdf, off, horz ? 9 : 8)
    # build a temporary 2-symbol cdf; it is not adapted (spec: constructed each time)
    tmp = i32[3]
    tmp[0] = 32768 - psum
    tmp[1] = 32768
    tmp[2] = 0
    st = @st
    old = st[4]
    st[4] = 1
    v = av1_sym(st, @d, tmp, 0, 2)
    st[4] = old
    v

  # ------------------------------------------------------------ block

  -> decode_block(r, c, sub)
    @mi_row = r
    @mi_col = c
    @mi_size = sub
    bw4 = AV1_BW4[sub]
    bh4 = AV1_BH4[sub]
    @bw4 = bw4
    @bh4 = bh4
    if bh4 == 1 && @ssy == 1 && (r & 1) == 0
      @has_chroma = false
    elsif bw4 == 1 && @ssx == 1 && (c & 1) == 0
      @has_chroma = false
    else
      @has_chroma = @num_planes > 1
    @avail_u = is_inside(r - 1, c)
    @avail_l = is_inside(r, c - 1)
    @avail_u_chroma = @avail_u
    @avail_l_chroma = @avail_l
    if @has_chroma
      @avail_u_chroma = is_inside(r - 2, c) if @ssy == 1 && bh4 == 1
      @avail_l_chroma = is_inside(r, c - 2) if @ssx == 1 && bw4 == 1
    else
      @avail_u_chroma = false
      @avail_l_chroma = false
    @palette_size_y = 0
    @palette_size_uv = 0
    @use_filter_intra = 0
    @is_inter = 0
    @use_intrabc = 0
    @ref_frame0 = 0
    @ref_frame1 = -1
    @skip_mode = 0
    if @frame_is_intra
      intra_frame_mode_info()
    else
      inter_frame_mode_info()
    palette_tokens()
    read_block_tx_size()
    reset_block_context(bw4, bh4) if @skip == 1
    mis = @mis
    y = 0
    rmax = r + bh4
    rmax = @mi_rows if rmax > @mi_rows
    cmax = c + bw4
    cmax = @mi_cols if cmax > @mi_cols
    yy = r
    while yy < rmax
      xx = c
      o = yy * mis
      while xx < cmax
        @a_y_modes[o + xx] = @y_mode
        @a_uv_modes[o + xx] = @uv_mode if @ref_frame0 == 0 && @has_chroma
        @a_ref0[o + xx] = @ref_frame0
        xx += 1
      yy += 1
    store_block_refs(r, c, rmax, cmax)
    compute_prediction() if @is_inter == 1
    residual()
    yy = r
    while yy < rmax
      xx = c
      o = yy * mis
      while xx < cmax
        k = o + xx
        @a_is_inters[k] = @is_inter
        @a_skip_modes[k] = @skip_mode
        @a_skips[k] = @skip
        @a_tx_sizes[k] = @tx_size
        @a_mi_sizes[k] = @mi_size
        @a_seg_ids[k] = @segment_id
        @a_pal_sizes0[k] = @palette_size_y
        @a_pal_sizes1[k] = @palette_size_uv
        i = 0
        while i < @palette_size_y
          @a_pal_colors0[k * 8 + i] = @palette_colors_y[i]
          i += 1
        i = 0
        while i < @palette_size_uv
          @a_pal_colors1[k * 8 + i] = @palette_colors_u[i]
          i += 1
        i = 0
        while i < 4
          @a_delta_lf[k * 4 + i] = @delta_lf[i]
          i += 1
        xx += 1
      yy += 1
    nil

  -> reset_block_context(bw4, bh4)
    np = @has_chroma ? 3 : 1
    p = 0
    while p < np
      sx = p > 0 ? @ssx : 0
      sy = p > 0 ? @ssy : 0
      i = @mi_col >> sx
      e = (@mi_col + bw4) >> sx
      while i < e
        @above_level[p][i] = 0
        @above_dc[p][i] = 0
        i += 1
      i = @mi_row >> sy
      e = (@mi_row + bh4) >> sy
      while i < e
        @left_level[p][i] = 0
        @left_dc[p][i] = 0
        i += 1
      p += 1
    nil

  # ------------------------------------------------------------ intra mode info

  -> intra_frame_mode_info
    @skip = 0
    intra_segment_id() if @seg_id_pre_skip == 1
    @skip_mode = 0
    read_skip()
    intra_segment_id() if @seg_id_pre_skip == 0
    read_cdef()
    read_delta_qindex()
    read_delta_lf()
    @read_deltas = false
    @ref_frame0 = 0
    @ref_frame1 = -1
    @use_intrabc = 0
    if @allow_intrabc == 1
      @use_intrabc = sym(@o_intrabc, 2)
    if @use_intrabc == 1
      intrabc_mode_info()
      return nil
    @is_inter = 0
    mis = @mis
    am = @avail_u ? @a_y_modes[(@mi_row - 1) * mis + @mi_col] : 0
    lm = @avail_l ? @a_y_modes[@mi_row * mis + @mi_col - 1] : 0
    actx = AV1_INTRA_MODE_CONTEXT[am]
    lctx = AV1_INTRA_MODE_CONTEXT[lm]
    @y_mode = sym(@o_ify + (actx * 5 + lctx) * 14, 13)
    intra_angle_info_y()
    intra_uv_and_rest()
    nil

  # uv mode, cfl, palette, filter intra (shared by intra and inter frames)
  -> intra_uv_and_rest
    @uv_mode = 0
    @angle_delta_uv = 0
    if @has_chroma
      cfl_ok = false
      if @lossless && get_plane_residual_size(@mi_size, 1) == 0
        cfl_ok = true
      elsif !@lossless && av1_max(AV1_BW4[@mi_size], AV1_BH4[@mi_size]) <= 8
        cfl_ok = true
      if cfl_ok
        @uv_mode = sym(@o_uv_cfl + @y_mode * 15, 14)
      else
        @uv_mode = sym(@o_uv_nocfl + @y_mode * 14, 13)
      read_cfl_alphas() if @uv_mode == 13
      intra_angle_info_uv()
    @palette_size_y = 0
    @palette_size_uv = 0
    if @mi_size >= 3 && AV1_BW4[@mi_size] <= 16 && AV1_BH4[@mi_size] <= 16 && @allow_screen_content_tools == 1
      palette_mode_info()
    filter_intra_mode_info()

  -> intra_segment_id
    if @segmentation_enabled == 1
      read_segment_id()
    else
      @segment_id = 0
    @lossless = @lossless_array[@segment_id]

  -> read_segment_id
    mis = @mis
    r = @mi_row
    c = @mi_col
    prev_ul = (@avail_u && @avail_l) ? @a_seg_ids[(r - 1) * mis + c - 1] : -1
    prev_u = @avail_u ? @a_seg_ids[(r - 1) * mis + c] : -1
    prev_l = @avail_l ? @a_seg_ids[r * mis + c - 1] : -1
    pred = 0
    if prev_u == -1
      pred = prev_l == -1 ? 0 : prev_l
    elsif prev_l == -1
      pred = prev_u
    else
      pred = prev_ul == prev_u ? prev_u : prev_l
    if @skip == 1
      @segment_id = pred
    else
      ctx = 0
      if prev_ul < 0
        ctx = 0
      elsif prev_ul == prev_u && prev_ul == prev_l
        ctx = 2
      elsif prev_ul == prev_u || prev_ul == prev_l || prev_u == prev_l
        ctx = 1
      v = sym(@o_seg + ctx * 9, 8)
      @segment_id = av1_neg_deinterleave(v, pred, @last_active_seg_id + 1)
    nil

  -> seg_feature_active(feature)
    @segmentation_enabled == 1 && @feature_enabled[@segment_id][feature] == 1

  -> read_skip
    if @seg_id_pre_skip == 1 && seg_feature_active(6)
      @skip = 1
    else
      mis = @mis
      ctx = 0
      ctx += @a_skips[(@mi_row - 1) * mis + @mi_col] if @avail_u
      ctx += @a_skips[@mi_row * mis + @mi_col - 1] if @avail_l
      @skip = sym(@o_skip + ctx * 3, 2)
    nil

  -> read_cdef
    return nil if @skip == 1 || @coded_lossless || @enable_cdef == 0 || @allow_intrabc == 1
    r = @mi_row & (0 - 16)
    c = @mi_col & (0 - 16)
    k = r * @mis + c
    if @a_cdef_idx[k] == -1
      v = lit(@cdef_bits)
      @a_cdef_idx[k] = v
      w4 = @bw4
      h4 = @bh4
      i = r
      while i < r + h4
        j = c
        while j < c + w4
          @a_cdef_idx[i * @mis + j] = v if i < @mi_rows && j < @mi_cols
          j += 16
        i += 16
    nil

  -> read_delta_qindex
    sb_size = @sb128 == 1 ? 15 : 12
    return nil if @mi_size == sb_size && @skip == 1
    if @read_deltas
      a = sym(@o_delta_q, 4)
      if a == 3
        rb = lit(3) + 1
        a = lit(rb) + (1 << rb) + 1
      if a != 0
        s = lit(1)
        red = s == 1 ? 0 - a : a
        @current_q_index = av1_clip3(1, 255, @current_q_index + (red << @delta_q_res))
    nil

  -> read_delta_lf
    sb_size = @sb128 == 1 ? 15 : 12
    return nil if @mi_size == sb_size && @skip == 1
    if @read_deltas && @delta_lf_present == 1
      cnt = 1
      cnt = (@num_planes > 1 ? 4 : 2) if @delta_lf_multi == 1
      i = 0
      while i < cnt
        off = @delta_lf_multi == 1 ? @o_delta_lf_multi + i * 5 : @o_delta_lf
        a = sym(off, 4)
        if a == 3
          n = lit(3) + 1
          a = lit(n) + (1 << n) + 1
        if a != 0
          s = lit(1)
          red = s == 1 ? 0 - a : a
          @delta_lf[i] = av1_clip3(-63, 63, @delta_lf[i] + (red << @delta_lf_res))
        i += 1
    nil

  -> intra_angle_info_y
    @angle_delta_y = 0
    if @mi_size >= 3 && @y_mode >= 1 && @y_mode <= 8
      @angle_delta_y = sym(@o_angle + (@y_mode - 1) * 8, 7) - 3

  -> intra_angle_info_uv
    @angle_delta_uv = 0
    if @mi_size >= 3 && @uv_mode >= 1 && @uv_mode <= 8
      @angle_delta_uv = sym(@o_angle + (@uv_mode - 1) * 8, 7) - 3

  -> read_cfl_alphas
    signs = sym(@o_cfl_sign, 8)
    su = (signs + 1) / 3
    sv = (signs + 1) % 3
    @cfl_alpha_u = 0
    @cfl_alpha_v = 0
    if su != 0
      ctx = (su - 1) * 3 + sv
      a = 1 + sym(@o_cfl_alpha + ctx * 17, 16)
      @cfl_alpha_u = su == 1 ? 0 - a : a
    if sv != 0
      ctx = (sv - 1) * 3 + su
      a = 1 + sym(@o_cfl_alpha + ctx * 17, 16)
      @cfl_alpha_v = sv == 1 ? 0 - a : a
    nil

  -> filter_intra_mode_info
    @use_filter_intra = 0
    if @enable_filter_intra == 1 && @y_mode == 0 && @palette_size_y == 0 && av1_max(AV1_BW4[@mi_size], AV1_BH4[@mi_size]) <= 8
      @use_filter_intra = sym(@o_fi + @mi_size * 3, 2)
      @filter_intra_mode = sym(@o_fi_mode, 5) if @use_filter_intra == 1
    nil

  # ------------------------------------------------------------ palette

  -> palette_mode_info
    bsize_ctx = AV1_MIWL[@mi_size] + AV1_MIHL[@mi_size] - 2
    mis = @mis
    bd = @bit_depth
    if @y_mode == 0
      ctx = 0
      ctx += 1 if @avail_u && @a_pal_sizes0[(@mi_row - 1) * mis + @mi_col] > 0
      ctx += 1 if @avail_l && @a_pal_sizes0[@mi_row * mis + @mi_col - 1] > 0
      if sym(@o_pal_y_mode + (bsize_ctx * 3 + ctx) * 3, 2) == 1
        @palette_size_y = sym(@o_pal_y_size + bsize_ctx * 8, 7) + 2
        cache = get_palette_cache(0)
        cols = []
        i = 0
        while i < cache.size && cols.size < @palette_size_y
          cols.push(cache[i]) if lit(1) == 1
          i += 1
        if cols.size < @palette_size_y
          cols.push(lit(bd))
        pbits = 0
        if cols.size < @palette_size_y
          pbits = bd - 3 + lit(2)
        while cols.size < @palette_size_y
          dl = lit(pbits) + 1
          v = av1_clip1(cols[cols.size - 1] + dl, bd)
          cols.push(v)
          rng = (1 << bd) - v - 1
          pbits = av1_min(pbits, av1_ceil_log2(rng))
        @palette_colors_y = cols.sort
    if @has_chroma && @uv_mode == 0
      ctx = @palette_size_y > 0 ? 1 : 0
      if sym(@o_pal_uv_mode + ctx * 3, 2) == 1
        @palette_size_uv = sym(@o_pal_uv_size + bsize_ctx * 8, 7) + 2
        cache = get_palette_cache(1)
        cols = []
        i = 0
        while i < cache.size && cols.size < @palette_size_uv
          cols.push(cache[i]) if lit(1) == 1
          i += 1
        if cols.size < @palette_size_uv
          cols.push(lit(bd))
        pbits = 0
        if cols.size < @palette_size_uv
          pbits = bd - 3 + lit(2)
        while cols.size < @palette_size_uv
          dl = lit(pbits)
          v = av1_clip1(cols[cols.size - 1] + dl, bd)
          cols.push(v)
          rng = (1 << bd) - v
          pbits = av1_min(pbits, av1_ceil_log2(rng))
        @palette_colors_u = cols.sort
        vs = []
        if lit(1) == 1
          minb = bd - 4
          mx = 1 << bd
          pbits = minb + lit(2)
          vs.push(lit(bd))
          i = 1
          while i < @palette_size_uv
            dv = lit(pbits)
            if dv != 0
              dv = 0 - dv if lit(1) == 1
            val = vs[i - 1] + dv
            val += mx if val < 0
            val -= mx if val >= mx
            vs.push(av1_clip1(val, bd))
            i += 1
        else
          i = 0
          while i < @palette_size_uv
            vs.push(lit(bd))
            i += 1
        @palette_colors_v = vs
    nil

  -> get_palette_cache(plane)
    mis = @mis
    r = @mi_row
    c = @mi_col
    sizes = plane == 0 ? @a_pal_sizes0 : @a_pal_sizes1
    colors = plane == 0 ? @a_pal_colors0 : @a_pal_colors1
    above_n = 0
    above_n = sizes[(r - 1) * mis + c] if ((r * 4) % 64) != 0
    left_n = 0
    left_n = sizes[r * mis + c - 1] if @avail_l
    ab = (r - 1) * mis + c
    lb = r * mis + c - 1
    ai = 0
    li = 0
    out = []
    while ai < above_n && li < left_n
      ac = colors[ab * 8 + ai]
      lc = colors[lb * 8 + li]
      if lc < ac
        out.push(lc) if out.size == 0 || lc != out[out.size - 1]
        li += 1
      else
        out.push(ac) if out.size == 0 || ac != out[out.size - 1]
        ai += 1
        li += 1 if lc == ac
    while ai < above_n
      v = colors[ab * 8 + ai]
      ai += 1
      out.push(v) if out.size == 0 || v != out[out.size - 1]
    while li < left_n
      v = colors[lb * 8 + li]
      li += 1
      out.push(v) if out.size == 0 || v != out[out.size - 1]
    out

  -> palette_tokens
    bh = AV1_BH4[@mi_size] * 4
    bw = AV1_BW4[@mi_size] * 4
    osh = av1_min(bh, (@mi_rows - @mi_row) * 4)
    osw = av1_min(bw, (@mi_cols - @mi_col) * 4)
    if @palette_size_y > 0
      read_color_map(@color_map_y, @palette_size_y, bw, bh, osw, osh, @o_pal_y_color[@palette_size_y])
    if @palette_size_uv > 0
      bh = bh >> @ssy
      bw = bw >> @ssx
      osh = osh >> @ssy
      osw = osw >> @ssx
      if bw < 4
        bw += 2
        osw += 2
      if bh < 4
        bh += 2
        osh += 2
      read_color_map(@color_map_uv, @palette_size_uv, bw, bh, osw, osh, @o_pal_uv_color[@palette_size_uv])
    nil

  # color maps are stored with stride 64
  -> read_color_map(m, n, bw, bh, osw, osh, coff)
    m[0] = sym_ns(n)
    order = i32[8]
    scores = i32[8]
    i = 1
    while i < osh + osw - 1
      j = av1_min(i, osw - 1)
      jmin = av1_max(0, i - osh + 1)
      while j >= jmin
        hash = av1_pal_ctx(m, i - j, j, n, order, scores)
        ctx = AV1_PALETTE_COLOR_CONTEXT[hash]
        idx = sym(coff + ctx * (n + 1), n)
        m[(i - j) * 64 + j] = order[idx]
        j -= 1
      i += 1
    i = 0
    while i < osh
      j = osw
      while j < bw
        m[i * 64 + j] = m[i * 64 + osw - 1]
        j += 1
      i += 1
    i = osh
    while i < bh
      j = 0
      while j < bw
        m[i * 64 + j] = m[(osh - 1) * 64 + j]
        j += 1
      i += 1
    nil

  # ------------------------------------------------------------ tx size

  -> read_block_tx_size
    bw4 = @bw4
    bh4 = @bh4
    mis = @mis
    if @tx_mode == 2 && @mi_size > 0 && @is_inter == 1 && @skip == 0 && !@lossless
      max_tx = AV1_MAX_TX_SIZE_RECT[@mi_size]
      tw4 = AV1_TXW[max_tx] >> 2
      th4 = AV1_TXH[max_tx] >> 2
      row = @mi_row
      while row < @mi_row + bh4
        col = @mi_col
        while col < @mi_col + bw4
          read_var_tx_size(row, col, max_tx, 0)
          col += tw4
        row += th4
    else
      read_tx_size(@skip == 0 || @is_inter == 0)
      row = @mi_row
      rmax = av1_min(@mi_row + bh4, @mi_rows)
      cmax = av1_min(@mi_col + bw4, @mi_cols)
      while row < rmax
        col = @mi_col
        while col < cmax
          @a_inter_tx_sizes[row * mis + col] = @tx_size
          col += 1
        row += 1
    nil

  -> read_tx_size(allow_select)
    if @lossless
      @tx_size = 0
      return nil
    max_rect = AV1_MAX_TX_SIZE_RECT[@mi_size]
    max_depth = AV1_MAX_TX_DEPTH[@mi_size]
    @tx_size = max_rect
    if @mi_size > 0 && allow_select && @tx_mode == 2
      ctx = tx_depth_ctx(max_rect)
      k = max_depth > 4 ? 4 : max_depth
      depth = 0
      if k <= 1
        depth = sym(@o_tx[0] + ctx * 3, 2)
      else
        depth = sym(@o_tx[k - 1] + ctx * 4, 3)
      i = 0
      while i < depth
        @tx_size = AV1_SPLIT_TX_SIZE[@tx_size]
        i += 1
    nil

  -> tx_depth_ctx(max_rect)
    mis = @mis
    mtw = AV1_TXW[max_rect]
    mth = AV1_TXH[max_rect]
    aw = 0
    lh = 0
    if @avail_u
      k = (@mi_row - 1) * mis + @mi_col
      if @a_is_inters[k] == 1
        aw = AV1_BW4[@a_mi_sizes[k]] * 4
      else
        aw = get_above_tx_width(@mi_row, @mi_col)
    if @avail_l
      k = @mi_row * mis + @mi_col - 1
      if @a_is_inters[k] == 1
        lh = AV1_BH4[@a_mi_sizes[k]] * 4
      else
        lh = get_left_tx_height(@mi_row, @mi_col)
    (aw >= mtw ? 1 : 0) + (lh >= mth ? 1 : 0)

  -> get_above_tx_width(row, col)
    mis = @mis
    if row == @mi_row
      if !@avail_u
        return 64
      k = (row - 1) * mis + col
      if @a_skips[k] == 1 && @a_is_inters[k] == 1
        return AV1_BW4[@a_mi_sizes[k]] * 4
    AV1_TXW[@a_inter_tx_sizes[(row - 1) * mis + col]]

  -> get_left_tx_height(row, col)
    mis = @mis
    if col == @mi_col
      if !@avail_l
        return 64
      k = row * mis + col - 1
      if @a_skips[k] == 1 && @a_is_inters[k] == 1
        return AV1_BH4[@a_mi_sizes[k]] * 4
    AV1_TXH[@a_inter_tx_sizes[row * mis + col - 1]]

  -> read_var_tx_size(row, col, tx_sz, depth)
    return nil if row >= @mi_rows || col >= @mi_cols
    split = 0
    if tx_sz != 0 && depth != 2
      above = get_above_tx_width(row, col) < AV1_TXW[tx_sz] ? 1 : 0
      left = get_left_tx_height(row, col) < AV1_TXH[tx_sz] ? 1 : 0
      size = av1_min(64, av1_max(AV1_BW4[@mi_size], AV1_BH4[@mi_size]) * 4)
      max_tx = av1_find_tx_size(size, size)
      up = AV1_TX_SIZE_SQR_UP[tx_sz]
      ctx = (up != max_tx ? 1 : 0) * 3 + (4 - max_tx) * 6 + above + left
      split = sym(@o_txfm_split + ctx * 3, 2)
    w4 = AV1_TXW[tx_sz] >> 2
    h4 = AV1_TXH[tx_sz] >> 2
    if split == 1
      st = AV1_SPLIT_TX_SIZE[tx_sz]
      sw = AV1_TXW[st] >> 2
      sh = AV1_TXH[st] >> 2
      i = 0
      while i < h4
        j = 0
        while j < w4
          read_var_tx_size(row + i, col + j, st, depth + 1)
          j += sw
        i += sh
    else
      i = 0
      while i < h4
        j = 0
        while j < w4
          @a_inter_tx_sizes[(row + i) * @mis + col + j] = tx_sz if row + i < @mi_rows && col + j < @mi_cols
          j += 1
        i += 1
      @tx_size = tx_sz
    nil

  # ------------------------------------------------------------ residual

  -> get_plane_residual_size(subsize, plane)
    sx = plane > 0 ? @ssx : 0
    sy = plane > 0 ? @ssy : 0
    AV1_SUBSAMPLED_SIZE[subsize * 4 + sx * 2 + sy]

  -> get_tx_size(plane, tx_sz)
    return tx_sz if plane == 0
    uv = AV1_MAX_TX_SIZE_RECT[get_plane_residual_size(@mi_size, plane)]
    if AV1_TXW[uv] == 64 || AV1_TXH[uv] == 64
      return 9 if AV1_TXW[uv] == 16
      return 10 if AV1_TXH[uv] == 16
      return 3
    uv

  -> residual
    sb_mask = @sb128 == 1 ? 31 : 15
    wch = av1_max(1, AV1_BW4[@mi_size] >> 4)
    hch = av1_max(1, AV1_BH4[@mi_size] >> 4)
    chunk_size = (wch > 1 || hch > 1) ? 12 : @mi_size
    cy = 0
    while cy < hch
      cx = 0
      while cx < wch
        mrc = @mi_row + (cy << 4)
        mcc = @mi_col + (cx << 4)
        np = @has_chroma ? 3 : 1
        p = 0
        while p < np
          tx_sz = @lossless ? 0 : get_tx_size(p, @tx_size)
          step_x = AV1_TXW[tx_sz] >> 2
          step_y = AV1_TXH[tx_sz] >> 2
          psz = get_plane_residual_size(chunk_size, p)
          n4w = AV1_BW4[psz]
          n4h = AV1_BH4[psz]
          sx = p > 0 ? @ssx : 0
          sy = p > 0 ? @ssy : 0
          if @is_inter == 1 && !@lossless && p == 0
            transform_tree((mcc >> sx) * 4, (mrc >> sy) * 4, n4w * 4, n4h * 4)
          else
            bxb = (@mi_col >> sx) * 4
            byb = (@mi_row >> sy) * 4
            y = 0
            while y < n4h
              x = 0
              while x < n4w
                transform_block(p, bxb, byb, tx_sz, x + ((cx << 4) >> sx), y + ((cy << 4) >> sy))
                x += step_x
              y += step_y
          p += 1
        cx += 1
      cy += 1
    nil

  -> transform_tree(sx0, sy0, w, h)
    return nil if sx0 >= @mi_cols * 4 || sy0 >= @mi_rows * 4
    row = sy0 >> 2
    col = sx0 >> 2
    ltx = @a_inter_tx_sizes[row * @mis + col]
    lw = AV1_TXW[ltx]
    lh = AV1_TXH[ltx]
    if w <= lw && h <= lh
      transform_block(0, sx0, sy0, av1_find_tx_size(w, h), 0, 0)
    elsif w > h
      transform_tree(sx0, sy0, w / 2, h)
      transform_tree(sx0 + w / 2, sy0, w / 2, h)
    elsif w < h
      transform_tree(sx0, sy0, w, h / 2)
      transform_tree(sx0, sy0 + h / 2, w, h / 2)
    else
      transform_tree(sx0, sy0, w / 2, h / 2)
      transform_tree(sx0 + w / 2, sy0, w / 2, h / 2)
      transform_tree(sx0, sy0 + h / 2, w / 2, h / 2)
      transform_tree(sx0 + w / 2, sy0 + h / 2, w / 2, h / 2)
    nil

  -> transform_block(plane, bx, by, tx_sz, x, y)
    start_x = bx + 4 * x
    start_y = by + 4 * y
    sx = plane > 0 ? @ssx : 0
    sy = plane > 0 ? @ssy : 0
    row = (start_y << sy) >> 2
    col = (start_x << sx) >> 2
    sb_mask = @sb128 == 1 ? 31 : 15
    sbr = row & sb_mask
    sbc = col & sb_mask
    step_x = AV1_TXW[tx_sz] >> 2
    step_y = AV1_TXH[tx_sz] >> 2
    max_x = (@mi_cols * 4) >> sx
    max_y = (@mi_rows * 4) >> sy
    return nil if start_x >= max_x || start_y >= max_y
    bdec = @block_decoded[plane]
    if @is_inter == 0
      if (plane == 0 && @palette_size_y > 0) || (plane != 0 && @palette_size_uv > 0)
        predict_palette(plane, start_x, start_y, x, y, tx_sz)
      else
        is_cfl = plane > 0 && @uv_mode == 13
        mode = plane == 0 ? @y_mode : (is_cfl ? 0 : @uv_mode)
        log2w = AV1_TXWL[tx_sz]
        log2h = AV1_TXHL[tx_sz]
        have_left = (plane == 0 ? @avail_l : @avail_l_chroma) || x > 0
        have_above = (plane == 0 ? @avail_u : @avail_u_chroma) || y > 0
        ar = bdec[((sbr >> sy) - 1 + 1) * 34 + (sbc >> sx) + step_x + 1] == 1
        bl = bdec[((sbr >> sy) + step_y + 1) * 34 + (sbc >> sx) - 1 + 1] == 1
        predict_intra(plane, start_x, start_y, have_left, have_above, ar, bl, mode, log2w, log2h)
        predict_cfl(plane, start_x, start_y, tx_sz) if is_cfl
      if plane == 0
        @max_luma_w = start_x + step_x * 4
        @max_luma_h = start_y + step_y * 4
    if @skip == 0
      eob = coeffs(plane, start_x, start_y, tx_sz)
      reconstruct(plane, start_x, start_y, tx_sz) if eob > 0
    lft = @a_lf_tx[plane]
    i = 0
    while i < step_y
      j = 0
      while j < step_x
        rr = (row >> sy) + i
        cc = (col >> sx) + j
        lft[rr * @mis + cc] = tx_sz if rr < @mi_rows && cc < @mi_cols
        bdec[((sbr >> sy) + i + 1) * 34 + (sbc >> sx) + j + 1] = 1 if (sbr >> sy) + i < 33 && (sbc >> sx) + j < 33
        j += 1
      i += 1
    nil

  # ------------------------------------------------------------ transform type

  -> get_tx_set(tx_sz)
    sqr = AV1_TX_SIZE_SQR[tx_sz]
    up = AV1_TX_SIZE_SQR_UP[tx_sz]
    return 0 if up > 3
    if @is_inter == 1
      return 3 if @reduced_tx_set == 1 || up == 3
      return 2 if sqr == 2
      return 1
    return 0 if up == 3
    return 2 if @reduced_tx_set == 1
    return 2 if sqr == 2
    1

  -> read_transform_type(x4, y4, tx_sz)
    set = get_tx_set(tx_sz)
    tt = 0
    qi = @segmentation_enabled == 1 ? get_qindex(true, @segment_id, @current_q_index) : @base_q_idx
    if set > 0 && qi > 0
      sqr = AV1_TX_SIZE_SQR[tx_sz]
      if @is_inter == 1
        if set == 1
          tt = AV1_TX_TYPE_INTER_INV_SET1[sym(@o_inter_tx1 + sqr * 17, 16)]
        elsif set == 2
          tt = AV1_TX_TYPE_INTER_INV_SET2[sym(@o_inter_tx2, 12)]
        else
          tt = AV1_TX_TYPE_INTER_INV_SET3[sym(@o_inter_tx3 + sqr * 3, 2)]
      else
        idir = @use_filter_intra == 1 ? AV1_FILTER_INTRA_MODE_TO_INTRA_DIR[@filter_intra_mode] : @y_mode
        if set == 1
          tt = AV1_TX_TYPE_INTRA_INV_SET1[sym(@o_intra_tx1 + (sqr * 13 + idir) * 8, 7)]
        else
          tt = AV1_TX_TYPE_INTRA_INV_SET2[sym(@o_intra_tx2 + (sqr * 13 + idir) * 6, 5)]
    w4 = AV1_TXW[tx_sz] >> 2
    h4 = AV1_TXH[tx_sz] >> 2
    i = 0
    while i < h4
      j = 0
      while j < w4
        @a_tx_types[(y4 + i) * @mis + x4 + j] = tt if y4 + i < @mi_rows && x4 + j < @mi_cols
        j += 1
      i += 1
    nil

  -> compute_tx_type(plane, tx_sz, bx4, by4)
    up = AV1_TX_SIZE_SQR_UP[tx_sz]
    return 0 if @lossless || up > 3
    set = get_tx_set(tx_sz)
    if plane == 0
      return @a_tx_types[by4 * @mis + bx4]
    tt = 0
    if @is_inter == 1
      x4 = av1_max(@mi_col, bx4 << @ssx)
      y4 = av1_max(@mi_row, by4 << @ssy)
      tt = @a_tx_types[y4 * @mis + x4]
    else
      tt = AV1_MODE_TO_TXFM[@uv_mode]
    return 0 if !av1_tx_in_set(@is_inter == 1, set, tt)
    tt

  # ------------------------------------------------------------ coefficients

  -> coeffs(plane, start_x, start_y, tx_sz)
    x4 = start_x >> 2
    y4 = start_y >> 2
    w4 = AV1_TXW[tx_sz] >> 2
    h4 = AV1_TXH[tx_sz] >> 2
    tx_sz_ctx = (AV1_TX_SIZE_SQR[tx_sz] + AV1_TX_SIZE_SQR_UP[tx_sz] + 1) >> 1
    ptype = plane > 0 ? 1 : 0
    seg_eob = (tx_sz == 17 || tx_sz == 18) ? 512 : av1_min(1024, AV1_TXW[tx_sz] * AV1_TXH[tx_sz])
    q = @quant
    av1_zero_i32(q, seg_eob)
    eob = 0
    cul = 0
    dc_cat = 0
    max_x4 = @mi_cols
    max_y4 = @mi_rows
    if plane > 0
      max_x4 = max_x4 >> @ssx
      max_y4 = max_y4 >> @ssy
    al = @above_level[plane]
    ad = @above_dc[plane]
    ll = @left_level[plane]
    ld = @left_dc[plane]
    # all_zero context
    ctx = 0
    bsize = get_plane_residual_size(@mi_size, plane)
    bw = AV1_BW4[bsize] * 4
    bh = AV1_BH4[bsize] * 4
    w = AV1_TXW[tx_sz]
    h = AV1_TXH[tx_sz]
    if plane == 0
      top = 0
      left = 0
      k = 0
      while k < w4
        top = av1_max(top, al[x4 + k]) if x4 + k < max_x4
        k += 1
      k = 0
      while k < h4
        left = av1_max(left, ll[y4 + k]) if y4 + k < max_y4
        k += 1
      if bw == w && bh == h
        ctx = 0
      elsif top == 0 && left == 0
        ctx = 1
      elsif top == 0 || left == 0
        ctx = 2 + (av1_max(top, left) > 3 ? 1 : 0)
      elsif av1_max(top, left) <= 3
        ctx = 4
      elsif av1_min(top, left) <= 3
        ctx = 5
      else
        ctx = 6
    else
      above = 0
      left = 0
      k = 0
      while k < w4
        if x4 + k < max_x4
          above = above | al[x4 + k] | ad[x4 + k]
        k += 1
      k = 0
      while k < h4
        if y4 + k < max_y4
          left = left | ll[y4 + k] | ld[y4 + k]
        k += 1
      ctx = (above != 0 ? 1 : 0) + (left != 0 ? 1 : 0) + 7
      ctx += 3 if bw * bh > w * h
    all_zero = sym(@o_txb_skip + (tx_sz_ctx * 13 + ctx) * 3, 2)
    if all_zero == 1
      if plane == 0
        i = 0
        while i < h4
          j = 0
          while j < w4
            @a_tx_types[(y4 + i) * @mis + x4 + j] = 0 if y4 + i < @mi_rows && x4 + j < @mi_cols
            j += 1
          i += 1
      @plane_tx_type = 0
    else
      read_transform_type(x4, y4, tx_sz) if plane == 0
      @plane_tx_type = compute_tx_type(plane, tx_sz, x4, y4)
      ptt = @plane_tx_type
      scan = get_scan(tx_sz)
      tx_class = av1_tx_class(ptt)
      eob_multi = av1_min(AV1_TXWL[tx_sz], 5) + av1_min(AV1_TXHL[tx_sz], 5) - 4
      ectx = tx_class == 0 ? 0 : 1
      eob_pt = 0
      if eob_multi <= 4
        nsym = eob_multi + 5
        eob_pt = sym(@o_eob_pt[eob_multi] + (ptype * 2 + ectx) * (nsym + 1), nsym) + 1
      else
        nsym = eob_multi + 5
        eob_pt = sym(@o_eob_pt[eob_multi] + ptype * (nsym + 1), nsym) + 1
      eob = eob_pt < 2 ? eob_pt : ((1 << (eob_pt - 2)) + 1)
      eob_shift = eob_pt - 3
      if eob_shift >= 0
        ex = sym(@o_eob_extra + ((tx_sz_ctx * 2 + ptype) * 9 + eob_pt - 3) * 3, 2)
        eob += (1 << eob_shift) if ex == 1
        i = 1
        lim = av1_max(0, eob_pt - 2)
        while i < lim
          eob_shift = lim - 1 - i
          eob += (1 << eob_shift) if lit(1) == 1
          i += 1
      adj = AV1_ADJUSTED_TX_SIZE[tx_sz]
      bwl = AV1_TXWL[adj]
      height = AV1_TXH[adj]
      cbe = @o_cb_eob + (tx_sz_ctx * 2 + ptype) * 4 * 4
      cbo = @o_cb + (tx_sz_ctx * 2 + ptype) * 42 * 5
      bro = @o_br + (av1_min(tx_sz_ctx, 3) * 2 + ptype) * 21 * 5
      # dc sign context
      dcs = 0
      k = 0
      while k < w4
        if x4 + k < max_x4
          s = ad[x4 + k]
          dcs -= 1 if s == 1
          dcs += 1 if s == 2
        k += 1
      k = 0
      while k < h4
        if y4 + k < max_y4
          s = ld[y4 + k]
          dcs -= 1 if s == 1
          dcs += 1 if s == 2
        k += 1
      dctx = dcs < 0 ? 1 : (dcs > 0 ? 2 : 0)
      dco = @o_dc_sign + (ptype * 3 + dctx) * 3
      res = av1_read_coefs(@st, @d, @tcdf, q, scan, eob, bwl, height, tx_class, tx_sz, cbe, cbo, bro, dco, AV1_SIG_REF, AV1_CB_CTX_OFF, AV1_MAG_REF)
      cul = res >> 2
      dc_cat = res & 3
    k = 0
    while k < w4
      al[x4 + k] = cul
      ad[x4 + k] = dc_cat
      k += 1
    k = 0
    while k < h4
      ll[y4 + k] = cul
      ld[y4 + k] = dc_cat
      k += 1
    @eob = eob
    eob

  -> get_scan(tx_sz)
    return AV1_SCANS[0][9] if tx_sz == 17
    return AV1_SCANS[0][10] if tx_sz == 18
    return AV1_SCANS[0][3] if AV1_TX_SIZE_SQR_UP[tx_sz] == 4
    ptt = @plane_tx_type
    return AV1_SCANS[0][tx_sz] if ptt == 9
    if ptt == 10 || ptt == 12 || ptt == 14
      return AV1_SCANS[1][tx_sz]
    if ptt == 11 || ptt == 13 || ptt == 15
      return AV1_SCANS[2][tx_sz]
    AV1_SCANS[0][tx_sz]

  # ------------------------------------------------------------ loop restoration syntax

  -> read_lr(r, c, bsize)
    return nil if @allow_intrabc == 1
    w = AV1_BW4[bsize]
    h = AV1_BH4[bsize]
    p = 0
    while p < @num_planes
      if @frame_restoration_type[p] != 0
        sx = p == 0 ? 0 : @ssx
        sy = p == 0 ? 0 : @ssy
        us = @loop_restoration_size[p]
        urows = @lr_unit_rows[p]
        ucols = @lr_unit_cols[p]
        urs = (r * (4 >> sy) + us - 1) / us
        ure = av1_min(urows, ((r + h) * (4 >> sy) + us - 1) / us)
        num = 4 >> sx
        den = us
        if @use_superres == 1
          num = (4 >> sx) * @superres_denom
          den = us * 8
        ucs = (c * num + den - 1) / den
        uce = av1_min(ucols, ((c + w) * num + den - 1) / den)
        ur = urs
        while ur < ure
          uc = ucs
          while uc < uce
            read_lr_unit(p, ur, uc)
            uc += 1
          ur += 1
      p += 1
    nil

  -> read_lr_unit(p, ur, uc)
    frt = @frame_restoration_type[p]
    rt = 0
    if frt == 1
      rt = sym(@o_use_wiener, 2) == 1 ? 1 : 0
    elsif frt == 2
      rt = sym(@o_use_sgrproj, 2) == 1 ? 2 : 0
    else
      rt = sym(@o_restoration_type, 3)
    k = ur * @lr_unit_cols[p] + uc
    @lr_type[p][k] = rt
    if rt == 1
      pass = 0
      while pass < 2
        first = 0
        if p > 0
          first = 1
          @lr_wiener[p][k * 6 + pass * 3] = 0
        j = first
        while j < 3
          mn = AV1_WIENER_TAPS_MIN[j]
          mx = AV1_WIENER_TAPS_MAX[j]
          kk = AV1_WIENER_TAPS_K[j]
          v = decode_signed_subexp_with_ref_bool(mn, mx + 1, kk, @ref_lr_wiener[p][pass][j])
          @lr_wiener[p][k * 6 + pass * 3 + j] = v
          @ref_lr_wiener[p][pass][j] = v
          j += 1
        pass += 1
    elsif rt == 2
      set = lit(4)
      @lr_sgr_set[p][k] = set
      i = 0
      while i < 2
        radius = AV1_SGR_PARAMS[set * 4 + i * 2]
        mn = AV1_SGRPROJ_XQD_MIN[i]
        mx = AV1_SGRPROJ_XQD_MAX[i]
        v = 0
        if radius != 0
          v = decode_signed_subexp_with_ref_bool(mn, mx + 1, 4, @ref_sgr_xqd[p][i])
        elsif i == 1
          v = av1_clip3(mn, mx, (1 << 7) - @ref_sgr_xqd[p][0])
        @lr_sgr_xqd[p][k * 2 + i] = v
        @ref_sgr_xqd[p][i] = v
        i += 1
    nil

  -> decode_signed_subexp_with_ref_bool(low, high, k, r)
    decode_unsigned_subexp_with_ref_bool(high - low, k, r - low) + low

  -> decode_unsigned_subexp_with_ref_bool(mx, k, r)
    v = decode_subexp_bool(mx, k)
    if (r << 1) <= mx
      av1_inverse_recenter(r, v)
    else
      mx - 1 - av1_inverse_recenter(mx - 1 - r, v)

  -> decode_subexp_bool(num_syms, k)
    i = 0
    mk = 0
    while true
      b2 = i > 0 ? k + i - 1 : k
      a = 1 << b2
      if num_syms <= mk + 3 * a
        return sym_ns(num_syms - mk) + mk
      if lit(1) == 1
        i += 1
        mk += a
      else
        return lit(b2) + mk

# ---------------------------------------------------------------- free helpers

-> av1_max(a, b)
  a > b ? a : b

-> av1_min(a, b)
  a < b ? a : b

-> av1_round2(x, n)
  return x if n == 0
  (x + (1 << (n - 1))) >> n

-> av1_count_units(us, fs)
  v = (fs + (us >> 1)) / us
  v < 1 ? 1 : v

-> av1_clip1(x, bd)
  mx = (1 << bd) - 1
  x < 0 ? 0 : (x > mx ? mx : x)

-> av1_ceil_log2(x)
  return 0 if x < 2
  i = 1
  p = 2
  while p < x
    i += 1
    p = p << 1
  i

-> av1_find_tx_size(w, h)
  t = 0
  while t < 19
    return t if AV1_TXW[t] == w && AV1_TXH[t] == h
    t += 1
  t

-> av1_tx_class(tt)
  return 2 if tt == 10 || tt == 12 || tt == 14
  return 1 if tt == 11 || tt == 13 || tt == 15
  0

-> av1_tx_in_set(inter, set, tt)
  inter ? AV1_TX_TYPE_IN_SET_INTER[set * 16 + tt] == 1 : AV1_TX_TYPE_IN_SET_INTRA[set * 16 + tt] == 1

-> av1_neg_deinterleave(diff, ref, mx)
  return diff if ref == 0
  return mx - diff - 1 if ref >= mx - 1
  if 2 * ref < mx
    if diff <= 2 * ref
      return (diff & 1) != 0 ? ref + ((diff + 1) >> 1) : ref - (diff >> 1)
    return diff
  if diff <= 2 * (mx - ref - 1)
    return (diff & 1) != 0 ? ref + ((diff + 1) >> 1) : ref - (diff >> 1)
  mx - (diff + 1)

-> av1_pprob(cdf, off, p) (i32[] i64 i64) i64
  prev = (p > 0 ? cdf[off + p - 1] : 0) ## i64
  cdf[off + p] - prev

-> av1_zero_i32(a, n) (i32[] i64) i64
  i = 0 ## i64
  while i < n
    a[i] = 0
    i += 1
  0

-> av1_clear_bd(b, w4, h4, sbw4, sbh4) (u8[] i64 i64 i64 i64) i64
  # BlockDecoded[y][x] for y, x in -1..sb4 stored at (y + 1) * 34 + x + 1
  y = -1 ## i64
  while y <= h4
    x = -1 ## i64
    while x <= w4
      v = 0 ## i64
      if y < 0 && x < sbw4
        v = 1
      elsif x < 0 && y < sbh4
        v = 1
      b[(y + 1) * 34 + x + 1] = v
      x += 1
    y += 1
  b[(h4 + 1) * 34] = 0
  0

-> av1_pal_ctx(m, r, c, n, order, scores) (u8[] i64 i64 i64 i32[] i32[]) i64
  i = 0 ## i64
  while i < 8
    scores[i] = 0
    order[i] = i
    i += 1
  if c > 0
    nb = (m[r * 64 + c - 1]) ## i64
    scores[nb] = scores[nb] + 2
  if r > 0 && c > 0
    nb = m[(r - 1) * 64 + c - 1]
    scores[nb] = scores[nb] + 1
  if r > 0
    nb = m[(r - 1) * 64 + c]
    scores[nb] = scores[nb] + 2
  i = 0
  while i < 3
    mxs = (scores[i]) ## i64
    mxi = (i) ## i64
    j = (i + 1) ## i64
    while j < n
      if scores[j] > mxs
        mxs = scores[j]
        mxi = j
      j += 1
    if mxi != i
      mxs = scores[mxi]
      mco = (order[mxi]) ## i64
      k = (mxi) ## i64
      while k > i
        scores[k] = scores[k - 1]
        order[k] = order[k - 1]
        k -= 1
      scores[i] = mxs
      order[i] = mco
    i += 1
  scores[0] * 1 + scores[1] * 2 + scores[2] * 2

# Read the coefficient levels and signs into q (spec coeffs() loops).
# Returns (culLevel << 2) | dcCategory.
-> av1_read_coefs(st, d, cdf, q, scan, eob, bwl, height, tx_class, tx_sz, cbe, cbo, bro, dco, sig_ref, cb_off, mag_ref) (i64[] u8[] i32[] i32[] i32[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i32[] i32[] i32[]) i64
  width = (1 << bwl) ## i64
  c = (eob - 1) ## i64
  while c >= 0
    pos = (scan[c]) ## i64
    level = 0 ## i64
    row = (pos >> bwl) ## i64
    col = (pos - (row << bwl)) ## i64
    if c == eob - 1
      ctx = 0 ## i64
      if c == 0
        ctx = 0
      elsif c <= (height << bwl) / 8
        ctx = 1
      elsif c <= (height << bwl) / 4
        ctx = 2
      else
        ctx = 3
      level = av1_sym(st, d, cdf, cbe + ctx * 4, 3) + 1
    else
      mag = 0 ## i64
      idx = 0 ## i64
      base = (tx_class * 10) ## i64
      while idx < 5
        rr = (row + sig_ref[base + idx * 2]) ## i64
        cc = (col + sig_ref[base + idx * 2 + 1]) ## i64
        if rr >= 0 && cc >= 0 && rr < height && cc < width
          v = (q[(rr << bwl) + cc]) ## i64
          v = 0 - v if v < 0
          v = 3 if v > 3
          mag += v
        idx += 1
      ctx = (mag + 1) >> 1
      ctx = 4 if ctx > 4
      if tx_class == 0
        if row == 0 && col == 0
          ctx = 0
        else
          r4 = (row > 4 ? 4 : row) ## i64
          c4 = (col > 4 ? 4 : col) ## i64
          ctx += cb_off[tx_sz * 25 + r4 * 5 + c4]
      else
        ix = (tx_class == 2 ? row : col) ## i64
        ix = 2 if ix > 2
        ctx += 26 + ix * 5
      level = av1_sym(st, d, cdf, cbo + ctx * 5, 4)
    if level > 2
      # coeff_br context
      mag = 0 ## i64
      idx = 0 ## i64
      while idx < 3
        rr = row + mag_ref[tx_class * 6 + idx * 2]
        cc = col + mag_ref[tx_class * 6 + idx * 2 + 1]
        if rr >= 0 && cc >= 0 && rr < height && cc < width
          v = q[rr * width + cc]
          v = 15 if v > 15
          mag += v
        idx += 1
      mag = (mag + 1) >> 1
      mag = 6 if mag > 6
      bctx = 0 ## i64
      if pos == 0
        bctx = mag
      elsif tx_class == 0
        if row < 2 && col < 2
          bctx = mag + 7
        else
          bctx = mag + 14
      elsif tx_class == 1
        if col == 0
          bctx = mag + 7
        else
          bctx = mag + 14
      else
        if row == 0
          bctx = mag + 7
        else
          bctx = mag + 14
      k = 0 ## i64
      while k < 4
        br = (av1_sym(st, d, cdf, bro + bctx * 5, 4)) ## i64
        level += br
        break if br < 3
        k += 1
    q[pos] = level
    c -= 1
  cul = 0 ## i64
  dc_cat = 0 ## i64
  c = 0
  while c < eob
    pos = scan[c]
    v = q[pos]
    sign = 0 ## i64
    if v != 0
      if c == 0
        sign = av1_sym(st, d, cdf, dco, 2)
      else
        sign = av1_bool(st, d)
    if v > 14
      length = 0 ## i64
      while true
        length += 1
        break if av1_bool(st, d) == 1
        if length > 32
          break
      x = 1 ## i64
      i = (length - 2) ## i64
      while i >= 0
        x = (x << 1) | av1_bool(st, d)
        i -= 1
      v = x + 14
    if pos == 0 && v > 0
      dc_cat = sign == 1 ? 1 : 2
    v = v & 0xFFFFF
    cul += v
    if sign == 1
      v = 0 - v
    q[pos] = v
    c += 1
  cul = 63 if cul > 63
  (cul << 2) | dc_cat
