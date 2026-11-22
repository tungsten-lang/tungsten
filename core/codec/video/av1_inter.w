# core/codec/video/av1_inter — AV1 inter mode info (spec 5.11.18-5.11.33), motion vector
# prediction (7.10.2: find_mv_stack, temporal candidates, extra search,
# contexts), warp sample search (7.10.4), motion field estimation (7.9),
# motion field storage (7.19) and intra block copy mode info. Reopens
# Av1Decoder; motion compensation lives in core/codec/video/av1_mc.w.
#
# Mode numbering follows the spec: intra modes 0..13 (13 = UV_CFL_PRED),
# NEARESTMV 14, NEARMV 15, GLOBALMV 16, NEWMV 17, NEAREST_NEARESTMV 18,
# NEAR_NEARMV 19, NEAREST_NEWMV 20, NEW_NEARESTMV 21, NEAR_NEWMV 22,
# NEW_NEARMV 23, GLOBAL_GLOBALMV 24, NEW_NEWMV 25.
#
# Per-4x4 arrays (frame_begin): @a_ref0 / @a_ref1 (RefFrames, -2 = not yet
# written this frame), @a_mvs (Mvs, 4 per position: list0 row/col, list1
# row/col), @a_interp (InterpFilters, 2 per position), @a_cgi / @a_cidx
# (CompGroupIdxs / CompoundIdxs).

use av1_tables
use av1_mc

+ Av1Decoder
  # ------------------------------------------------------------ frame setup

  -> inter_frame_begin(n)
    av1_fill_i32(@a_ref0, n, -2)
    @a_ref1 = i32[n]
    av1_fill_i32(@a_ref1, n, -1)
    @a_mvs = i32[n * 4]
    @a_interp = u8[n * 2]
    @a_cgi = u8[n]
    @a_cidx = u8[n]
    if @ref_stack == nil
      @ref_stack = i32[40]
      @weight_stack = i32[10]
      @gmv = i32[4]
      @mv = i32[4]
      @pred_mv = i32[4]
      @drl_ctx = i32[10]
      @cand_list = i32[40]
      @rcnt = i32[8]
      @ref_id_mvs = i32[8]
      @ref_diff_mvs = i32[8]
      @comb_mvs = i32[8]
      @lwp = i64[6]
      @interp = [0, 0]
      mc_begin()
    @motion_mode = 0
    @interintra = 0
    @compound_type = 2
    @wedge_interintra = 0
    @interintra_mode = 0
    @wedge_index = 0
    @wedge_sign = 0
    @mask_type = 0
    @comp_group_idx = 0
    @compound_idx = 1
    @num_samples = 0
    @local_valid = 0
    @is_inter_intra = false
    @mfmv = nil if @use_ref_frame_mvs == 0
    l = AV1_CDF_LAYOUT
    @o_y_mode = l[:y_mode][0]
    @o_comp_mode = l[:comp_mode][0]
    @o_comp_ref_type = l[:comp_ref_type][0]
    @o_uni_comp_ref = l[:uni_comp_ref][0]
    @o_comp_ref = l[:comp_ref][0]
    @o_comp_bwd_ref = l[:comp_bwd_ref][0]
    @o_single_ref = l[:single_ref][0]
    @o_compound_mode = l[:compound_mode][0]
    @o_new_mv = l[:new_mv][0]
    @o_zero_mv = l[:zero_mv][0]
    @o_ref_mv = l[:ref_mv][0]
    @o_drl = l[:drl_mode][0]
    @o_interp = l[:interp_filter][0]
    @o_motion_mode = l[:motion_mode][0]
    @o_use_obmc = l[:use_obmc][0]
    @o_inter_intra = l[:inter_intra][0]
    @o_ii_mode = l[:inter_intra_mode][0]
    @o_wedge_ii = l[:wedge_inter_intra][0]
    @o_wedge_index = l[:wedge_index][0]
    @o_compound_type = l[:compound_type][0]
    @o_cgi = l[:comp_group_idx][0]
    @o_cidx = l[:compound_idx][0]
    @o_mv_joint = l[:mv_joint][0]
    @o_mv_class = l[:mv_class][0]
    @o_mv_class0_bit = l[:mv_class0_bit][0]
    @o_mv_class0_fr = l[:mv_class0_fr][0]
    @o_mv_class0_hp = l[:mv_class0_hp][0]
    @o_mv_fr = l[:mv_fr][0]
    @o_mv_hp = l[:mv_hp][0]
    @o_mv_sign = l[:mv_sign][0]
    @o_mv_bit = l[:mv_bit][0]
    nil

  # Store the inter block state for the 4x4 positions of the block (the
  # first loop of decode_block, before compute_prediction).
  -> store_block_refs(r, c, rmax, cmax)
    mis = @mis
    is_comp = @ref_frame1 > 0
    mv = @mv
    yy = r
    while yy < rmax
      o = yy * mis
      xx = c
      while xx < cmax
        k = o + xx
        @a_ref1[k] = @ref_frame1
        if @is_inter == 1
          if @use_intrabc == 0
            @a_cgi[k] = @comp_group_idx
            @a_cidx[k] = @compound_idx
          @a_interp[k * 2] = @interp[0]
          @a_interp[k * 2 + 1] = @interp[1]
          @a_mvs[k * 4] = mv[0]
          @a_mvs[k * 4 + 1] = mv[1]
          if is_comp
            @a_mvs[k * 4 + 2] = mv[2]
            @a_mvs[k * 4 + 3] = mv[3]
        xx += 1
      yy += 1
    nil

  # ------------------------------------------------------------ inter frame mode info

  -> inter_frame_mode_info
    @use_intrabc = 0
    mis = @mis
    r = @mi_row
    c = @mi_col
    @left_ref0 = 0
    @left_ref1 = -1
    @above_ref0 = 0
    @above_ref1 = -1
    if @avail_l
      k = r * mis + c - 1
      @left_ref0 = @a_ref0[k]
      @left_ref1 = @a_ref1[k]
    if @avail_u
      k = (r - 1) * mis + c
      @above_ref0 = @a_ref0[k]
      @above_ref1 = @a_ref1[k]
    @left_intra = @left_ref0 <= 0
    @above_intra = @above_ref0 <= 0
    @left_single = @left_ref1 <= 0
    @above_single = @above_ref1 <= 0
    @skip = 0
    inter_segment_id(1)
    read_skip_mode()
    if @skip_mode == 1
      @skip = 1
    else
      read_skip()
    inter_segment_id(0) if @seg_id_pre_skip == 0
    @lossless = @lossless_array[@segment_id]
    read_cdef()
    read_delta_qindex()
    read_delta_lf()
    @read_deltas = false
    read_is_inter()
    @motion_mode = 0
    @interintra = 0
    @compound_type = 2
    if @is_inter == 1
      inter_block_mode_info()
    else
      intra_block_mode_info()
    nil

  -> inter_segment_id(pre_skip)
    if @segmentation_enabled == 1
      pred = get_segment_id()
      if @segmentation_update_map == 1
        if pre_skip == 1 && @seg_id_pre_skip == 0
          @segment_id = 0
          return nil
        if pre_skip == 0
          if @skip == 1
            set_seg_pred_ctx(0)
            read_segment_id()
            return nil
        if @segmentation_temporal_update == 1
          ctx = @left_seg_pred[@mi_row] + @above_seg_pred[@mi_col]
          sp = sym(@o_seg_pred + ctx * 3, 2)
          if sp == 1
            @segment_id = pred
          else
            read_segment_id()
          set_seg_pred_ctx(sp)
        else
          read_segment_id()
      else
        @segment_id = pred
    else
      @segment_id = 0
    nil

  -> set_seg_pred_ctx(v)
    i = 0
    while i < @bw4
      @above_seg_pred[@mi_col + i] = v
      i += 1
    i = 0
    while i < @bh4
      @left_seg_pred[@mi_row + i] = v
      i += 1
    nil

  -> get_segment_id
    prev = @prev_segment_ids
    return 0 if prev == nil
    xm = av1_min(@mi_cols - @mi_col, @bw4)
    ym = av1_min(@mi_rows - @mi_row, @bh4)
    seg = 7
    y = 0
    while y < ym
      o = (@mi_row + y) * @mis + @mi_col
      x = 0
      while x < xm
        v = prev[o + x]
        seg = v if v < seg
        x += 1
      y += 1
    seg

  -> read_skip_mode
    @skip_mode = 0
    if seg_feature_active(6) || seg_feature_active(5) || seg_feature_active(7) || @skip_mode_present == 0 || @bw4 < 2 || @bh4 < 2
      return nil
    ctx = 0
    ctx += @a_skip_modes[(@mi_row - 1) * @mis + @mi_col] if @avail_u
    ctx += @a_skip_modes[@mi_row * @mis + @mi_col - 1] if @avail_l
    @skip_mode = sym(@o_skip_mode + ctx * 3, 2)
    nil

  -> read_is_inter
    if @skip_mode == 1
      @is_inter = 1
    elsif seg_feature_active(5)
      @is_inter = @feature_data[@segment_id][5] != 0 ? 1 : 0
    elsif seg_feature_active(7)
      @is_inter = 1
    else
      ctx = 0
      if @avail_u && @avail_l
        if @left_intra && @above_intra
          ctx = 3
        elsif @left_intra || @above_intra
          ctx = 1
      elsif @avail_u || @avail_l
        ctx = 2 * ((@avail_u ? @above_intra : @left_intra) ? 1 : 0)
      @is_inter = sym(@o_is_inter + ctx * 3, 2)
    nil

  -> intra_block_mode_info
    @ref_frame0 = 0
    @ref_frame1 = -1
    @y_mode = sym(@o_y_mode + AV1_SIZE_GROUP[@mi_size] * 14, 13)
    intra_angle_info_y()
    intra_uv_and_rest()
    nil

  -> inter_block_mode_info
    @palette_size_y = 0
    @palette_size_uv = 0
    @use_filter_intra = 0
    read_ref_frames()
    is_comp = @ref_frame1 > 0 ? 1 : 0
    find_mv_stack(is_comp)
    if @skip_mode == 1
      @y_mode = 18
    elsif seg_feature_active(6) || seg_feature_active(7)
      @y_mode = 16
    elsif is_comp == 1
      ctx = AV1_COMPOUND_MODE_CTX_MAP[(@ref_mv_context >> 1) * 5 + av1_min(@new_mv_context, 4)]
      @y_mode = 18 + sym(@o_compound_mode + ctx * 9, 8)
    else
      if sym(@o_new_mv + @new_mv_context * 3, 2) == 0
        @y_mode = 17
      elsif sym(@o_zero_mv + @zero_mv_context * 3, 2) == 0
        @y_mode = 16
      else
        @y_mode = sym(@o_ref_mv + @ref_mv_context * 3, 2) == 0 ? 14 : 15
    @ref_mv_idx = 0
    ym = @y_mode
    if ym == 17 || ym == 25
      idx = 0
      while idx < 2
        if @num_mv_found > idx + 1
          drl = sym(@o_drl + @drl_ctx[idx] * 3, 2)
          if drl == 0
            @ref_mv_idx = idx
            break
          @ref_mv_idx = idx + 1
        idx += 1
    elsif ym == 15 || ym == 19 || ym == 22 || ym == 23
      @ref_mv_idx = 1
      idx = 1
      while idx < 3
        if @num_mv_found > idx + 1
          drl = sym(@o_drl + @drl_ctx[idx] * 3, 2)
          if drl == 0
            @ref_mv_idx = idx
            break
          @ref_mv_idx = idx + 1
        idx += 1
    assign_mv(is_comp)
    read_interintra_mode(is_comp)
    read_motion_mode(is_comp)
    read_compound_type(is_comp)
    if @interpolation_filter == 4
      ndir = @enable_dual_filter == 1 ? 2 : 1
      dir = 0
      while dir < ndir
        if needs_interp_filter()
          @interp[dir] = sym(@o_interp + interp_ctx(dir) * 4, 3)
        else
          @interp[dir] = 0
        dir += 1
      @interp[1] = @interp[0] if @enable_dual_filter == 0
    else
      @interp[0] = @interpolation_filter
      @interp[1] = @interpolation_filter
    nil

  -> needs_interp_filter
    large = av1_min(@bw4, @bh4) >= 2
    if @skip_mode == 1 || @motion_mode == 2
      false
    elsif large && @y_mode == 16
      @gm_type[@ref_frame0] == 1
    elsif large && @y_mode == 24
      @gm_type[@ref_frame0] == 1 || @gm_type[@ref_frame1] == 1
    else
      true

  -> interp_ctx(dir)
    ctx = ((dir & 1) * 2 + (@ref_frame1 > 0 ? 1 : 0)) * 4
    lt = 3
    at = 3
    mis = @mis
    if @avail_l
      k = @mi_row * mis + @mi_col - 1
      lt = @a_interp[k * 2 + dir] if @a_ref0[k] == @ref_frame0 || @a_ref1[k] == @ref_frame0
    if @avail_u
      k = (@mi_row - 1) * mis + @mi_col
      at = @a_interp[k * 2 + dir] if @a_ref0[k] == @ref_frame0 || @a_ref1[k] == @ref_frame0
    if lt == at
      ctx += lt
    elsif lt == 3
      ctx += at
    elsif at == 3
      ctx += lt
    else
      ctx += 3
    ctx

  # ------------------------------------------------------------ reference frames

  -> count_refs_init
    cn = @rcnt
    i = 0
    while i < 8
      cn[i] = 0
      i += 1
    if @avail_u
      cn[@above_ref0] = cn[@above_ref0] + 1 if @above_ref0 > 0
      cn[@above_ref1] = cn[@above_ref1] + 1 if @above_ref1 > 0
    if @avail_l
      cn[@left_ref0] = cn[@left_ref0] + 1 if @left_ref0 > 0
      cn[@left_ref1] = cn[@left_ref1] + 1 if @left_ref1 > 0
    nil

  -> read_ref_frames
    if @skip_mode == 1
      @ref_frame0 = @skip_mode_frame[0]
      @ref_frame1 = @skip_mode_frame[1]
      return nil
    if seg_feature_active(5)
      @ref_frame0 = @feature_data[@segment_id][5]
      @ref_frame1 = -1
      return nil
    if seg_feature_active(6) || seg_feature_active(7)
      @ref_frame0 = 1
      @ref_frame1 = -1
      return nil
    count_refs_init()
    cn = @rcnt
    comp_mode = 0
    if @reference_select == 1 && av1_min(@bw4, @bh4) >= 2
      comp_mode = sym(@o_comp_mode + comp_mode_ctx() * 3, 2)
    if comp_mode == 1
      crt = sym(@o_comp_ref_type + comp_ref_type_ctx() * 3, 2)
      if crt == 0
        ctx = av1_ref_count_ctx(cn[1] + cn[2] + cn[3] + cn[4], cn[5] + cn[6] + cn[7])
        if sym(@o_uni_comp_ref + (ctx * 3) * 3, 2) == 1
          @ref_frame0 = 5
          @ref_frame1 = 7
        else
          ctx = av1_ref_count_ctx(cn[2], cn[3] + cn[4])
          if sym(@o_uni_comp_ref + (ctx * 3 + 1) * 3, 2) == 1
            ctx = av1_ref_count_ctx(cn[3], cn[4])
            if sym(@o_uni_comp_ref + (ctx * 3 + 2) * 3, 2) == 1
              @ref_frame0 = 1
              @ref_frame1 = 4
            else
              @ref_frame0 = 1
              @ref_frame1 = 3
          else
            @ref_frame0 = 1
            @ref_frame1 = 2
      else
        ctx = av1_ref_count_ctx(cn[1] + cn[2], cn[3] + cn[4])
        if sym(@o_comp_ref + (ctx * 3) * 3, 2) == 0
          ctx = av1_ref_count_ctx(cn[1], cn[2])
          @ref_frame0 = sym(@o_comp_ref + (ctx * 3 + 1) * 3, 2) == 1 ? 2 : 1
        else
          ctx = av1_ref_count_ctx(cn[3], cn[4])
          @ref_frame0 = sym(@o_comp_ref + (ctx * 3 + 2) * 3, 2) == 1 ? 4 : 3
        ctx = av1_ref_count_ctx(cn[5] + cn[6], cn[7])
        if sym(@o_comp_bwd_ref + (ctx * 2) * 3, 2) == 0
          ctx = av1_ref_count_ctx(cn[5], cn[6])
          @ref_frame1 = sym(@o_comp_bwd_ref + (ctx * 2 + 1) * 3, 2) == 1 ? 6 : 5
        else
          @ref_frame1 = 7
    else
      ctx = av1_ref_count_ctx(cn[1] + cn[2] + cn[3] + cn[4], cn[5] + cn[6] + cn[7])
      if sym(@o_single_ref + (ctx * 6) * 3, 2) == 1
        ctx = av1_ref_count_ctx(cn[5] + cn[6], cn[7])
        if sym(@o_single_ref + (ctx * 6 + 1) * 3, 2) == 0
          ctx = av1_ref_count_ctx(cn[5], cn[6])
          @ref_frame0 = sym(@o_single_ref + (ctx * 6 + 5) * 3, 2) == 1 ? 6 : 5
        else
          @ref_frame0 = 7
      else
        ctx = av1_ref_count_ctx(cn[1] + cn[2], cn[3] + cn[4])
        if sym(@o_single_ref + (ctx * 6 + 2) * 3, 2) == 1
          ctx = av1_ref_count_ctx(cn[3], cn[4])
          @ref_frame0 = sym(@o_single_ref + (ctx * 6 + 4) * 3, 2) == 1 ? 4 : 3
        else
          ctx = av1_ref_count_ctx(cn[1], cn[2])
          @ref_frame0 = sym(@o_single_ref + (ctx * 6 + 3) * 3, 2) == 1 ? 2 : 1
      @ref_frame1 = -1
    nil

  -> comp_mode_ctx
    au = @avail_u
    al = @avail_l
    if au && al
      if @above_single && @left_single
        av1_check_backward(@above_ref0) ^ av1_check_backward(@left_ref0)
      elsif @above_single
        2 + ((av1_check_backward(@above_ref0) == 1 || @above_intra) ? 1 : 0)
      elsif @left_single
        2 + ((av1_check_backward(@left_ref0) == 1 || @left_intra) ? 1 : 0)
      else
        4
    elsif au
      @above_single ? av1_check_backward(@above_ref0) : 3
    elsif al
      @left_single ? av1_check_backward(@left_ref0) : 3
    else
      1

  -> comp_ref_type_ctx
    a0 = @above_ref0
    a1 = @above_ref1
    l0 = @left_ref0
    l1 = @left_ref1
    au = @avail_u
    al = @avail_l
    acomp = au && !@above_intra && !@above_single
    lcomp = al && !@left_intra && !@left_single
    auni = acomp && av1_samedir(a0, a1)
    luni = lcomp && av1_samedir(l0, l1)
    if au && !@above_intra && al && !@left_intra
      samedir = av1_samedir(a0, l0) ? 1 : 0
      if !acomp && !lcomp
        1 + 2 * samedir
      elsif !acomp
        luni ? 3 + samedir : 1
      elsif !lcomp
        auni ? 3 + samedir : 1
      else
        if !auni && !luni
          0
        elsif !auni || !luni
          2
        else
          3 + (((a0 == 5) == (l0 == 5)) ? 1 : 0)
    elsif au && al
      if acomp
        1 + 2 * (auni ? 1 : 0)
      elsif lcomp
        1 + 2 * (luni ? 1 : 0)
      else
        2
    elsif acomp
      4 * (auni ? 1 : 0)
    elsif lcomp
      4 * (luni ? 1 : 0)
    else
      2

  # ------------------------------------------------------------ motion vectors

  -> assign_mv(is_comp)
    i = 0
    while i < 1 + is_comp
      cm = 17
      cm = get_mode(i) if @use_intrabc == 0
      st = @ref_stack
      if @use_intrabc == 1
        @pred_mv[0] = st[0]
        @pred_mv[1] = st[1]
        if @pred_mv[0] == 0 && @pred_mv[1] == 0
          @pred_mv[0] = st[4]
          @pred_mv[1] = st[5]
        if @pred_mv[0] == 0 && @pred_mv[1] == 0
          sb4 = @sb128 == 1 ? 32 : 16
          if @mi_row - sb4 < @mi_row_start
            @pred_mv[0] = 0
            @pred_mv[1] = 0 - (sb4 * 4 + 256) * 8
          else
            @pred_mv[0] = 0 - (sb4 * 4 * 8)
            @pred_mv[1] = 0
      elsif cm == 16
        @pred_mv[i * 2] = @gmv[i * 2]
        @pred_mv[i * 2 + 1] = @gmv[i * 2 + 1]
      else
        pos = cm == 14 ? 0 : @ref_mv_idx
        pos = 0 if cm == 17 && @num_mv_found <= 1
        @pred_mv[i * 2] = st[pos * 4 + i * 2]
        @pred_mv[i * 2 + 1] = st[pos * 4 + i * 2 + 1]
      if cm == 17
        read_mv(i)
      else
        @mv[i * 2] = @pred_mv[i * 2]
        @mv[i * 2 + 1] = @pred_mv[i * 2 + 1]
      i += 1
    nil

  -> get_mode(ref_list)
    ym = @y_mode
    if ref_list == 0
      if ym < 18
        ym
      elsif ym == 25 || ym == 21 || ym == 23
        17
      elsif ym == 18 || ym == 20
        14
      elsif ym == 19 || ym == 22
        15
      else
        16
    else
      if ym == 25 || ym == 20 || ym == 22
        17
      elsif ym == 18 || ym == 21
        14
      elsif ym == 19 || ym == 23
        15
      else
        16

  -> read_mv(ref)
    ctx = @use_intrabc == 1 ? 1 : 0
    d0 = 0
    d1 = 0
    joint = sym(@o_mv_joint + ctx * 5, 4)
    d0 = read_mv_component(ctx, 0) if joint == 2 || joint == 3
    d1 = read_mv_component(ctx, 1) if joint == 1 || joint == 3
    @mv[ref * 2] = @pred_mv[ref * 2] + d0
    @mv[ref * 2 + 1] = @pred_mv[ref * 2 + 1] + d1
    nil

  -> read_mv_component(ctx, comp)
    cc = ctx * 2 + comp
    sign = sym(@o_mv_sign + cc * 3, 2)
    cls = sym(@o_mv_class + ctx * 24 + comp * 12, 11)
    mag = 0
    if cls == 0
      c0b = sym(@o_mv_class0_bit + cc * 3, 2)
      fr = 3
      fr = sym(@o_mv_class0_fr + ctx * 20 + comp * 10 + c0b * 5, 4) if @force_integer_mv == 0
      hp = 1
      hp = sym(@o_mv_class0_hp + cc * 3, 2) if @allow_high_precision_mv == 1
      mag = ((c0b << 3) | (fr << 1) | hp) + 1
    else
      d = 0
      i = 0
      while i < cls
        b = sym(@o_mv_bit + cc * 30 + i * 3, 2)
        d = d | (b << i)
        i += 1
      mag = 2 << (cls + 2)
      fr = 3
      fr = sym(@o_mv_fr + ctx * 10 + comp * 5, 4) if @force_integer_mv == 0
      hp = 1
      hp = sym(@o_mv_hp + cc * 3, 2) if @allow_high_precision_mv == 1
      mag += ((d << 3) | (fr << 1) | hp) + 1
    sign == 1 ? 0 - mag : mag

  # ------------------------------------------------------------ interintra / motion mode / compound

  -> read_interintra_mode(is_comp)
    @interintra = 0
    ms = @mi_size
    if @skip_mode == 0 && @enable_interintra == 1 && is_comp == 0 && ms >= 3 && ms <= 9
      ctx = AV1_SIZE_GROUP[ms] - 1
      @interintra = sym(@o_inter_intra + ctx * 3, 2)
      if @interintra == 1
        @interintra_mode = sym(@o_ii_mode + ctx * 5, 4)
        @ref_frame1 = 0
        @angle_delta_y = 0
        @angle_delta_uv = 0
        @use_filter_intra = 0
        @wedge_interintra = sym(@o_wedge_ii + ms * 3, 2)
        if @wedge_interintra == 1
          @wedge_index = sym(@o_wedge_index + ms * 17, 16)
          @wedge_sign = 0
    nil

  -> read_motion_mode(is_comp)
    @motion_mode = 0
    return nil if @skip_mode == 1
    return nil if @is_motion_mode_switchable == 0
    return nil if av1_min(@bw4, @bh4) < 2
    if @force_integer_mv == 0 && (@y_mode == 16 || @y_mode == 24)
      return nil if @gm_type[@ref_frame0] > 1
    return nil if is_comp == 1 || @ref_frame1 == 0 || !has_overlappable_candidates()
    find_warp_samples()
    if @force_integer_mv == 1 || @num_samples == 0 || @allow_warped_motion == 0 || is_scaled(@ref_frame0)
      @motion_mode = sym(@o_use_obmc + @mi_size * 3, 2)
    else
      @motion_mode = sym(@o_motion_mode + @mi_size * 4, 3)
    nil

  -> is_scaled(rf)
    k = @ref_frame_idx[rf - 1]
    fw = @frame_width
    fh = @frame_height
    xs = ((@ref_upscaled_w[k] << 14) + (fw / 2)) / fw
    ys = ((@ref_frame_h[k] << 14) + (fh / 2)) / fh
    xs != 16384 || ys != 16384

  -> read_compound_type(is_comp)
    @comp_group_idx = 0
    @compound_idx = 1
    if @skip_mode == 1
      @compound_type = 2
      return nil
    if is_comp == 1
      n = AV1_WEDGE_BITS[@mi_size]
      @comp_group_idx = sym(@o_cgi + comp_group_ctx() * 3, 2) if @enable_masked_compound == 1
      if @comp_group_idx == 0
        if @enable_jnt_comp == 1
          @compound_idx = sym(@o_cidx + compound_idx_ctx() * 3, 2)
          @compound_type = @compound_idx == 1 ? 2 : 4
        else
          @compound_type = 2
      else
        if n == 0
          @compound_type = 1
        else
          @compound_type = sym(@o_compound_type + @mi_size * 3, 2)
      if @compound_type == 0
        @wedge_index = sym(@o_wedge_index + @mi_size * 17, 16)
        @wedge_sign = lit(1)
      elsif @compound_type == 1
        @mask_type = lit(1)
    else
      if @interintra == 1
        @compound_type = @wedge_interintra == 1 ? 0 : 3
      else
        @compound_type = 2
    nil

  -> comp_group_ctx
    ctx = 0
    mis = @mis
    if @avail_u
      if !@above_single
        ctx += @a_cgi[(@mi_row - 1) * mis + @mi_col]
      elsif @above_ref0 == 7
        ctx += 3
    if @avail_l
      if !@left_single
        ctx += @a_cgi[@mi_row * mis + @mi_col - 1]
      elsif @left_ref0 == 7
        ctx += 3
    av1_min(5, ctx)

  -> compound_idx_ctx
    fwd = av1_abs(get_relative_dist(@order_hints[@ref_frame0], @order_hint))
    bck = av1_abs(get_relative_dist(@order_hints[@ref_frame1], @order_hint))
    ctx = fwd == bck ? 3 : 0
    mis = @mis
    if @avail_u
      if !@above_single
        ctx += @a_cidx[(@mi_row - 1) * mis + @mi_col]
      elsif @above_ref0 == 7
        ctx += 1
    if @avail_l
      if !@left_single
        ctx += @a_cidx[@mi_row * mis + @mi_col - 1]
      elsif @left_ref0 == 7
        ctx += 1
    ctx

  # ------------------------------------------------------------ intra block copy

  -> intrabc_mode_info
    @is_inter = 1
    @y_mode = 0
    @uv_mode = 0
    @motion_mode = 0
    @compound_type = 2
    @interintra = 0
    @palette_size_y = 0
    @palette_size_uv = 0
    @use_filter_intra = 0
    @interp[0] = 3
    @interp[1] = 3
    @ref_frame0 = 0
    @ref_frame1 = -1
    find_mv_stack(0)
    assign_mv(0)
    nil

  # ------------------------------------------------------------ find_mv_stack (7.10.2)

  -> find_mv_stack(is_comp)
    bw4 = @bw4
    bh4 = @bh4
    @num_mv_found = 0
    @new_mv_count = 0
    @gmv[2] = 0
    @gmv[3] = 0
    setup_global_mv(0)
    setup_global_mv(1) if is_comp == 1
    @found_match = 0
    scan_row(-1, is_comp)
    found_above = @found_match
    @found_match = 0
    scan_col(-1, is_comp)
    found_left = @found_match
    @found_match = 0
    scan_point(-1, bw4, is_comp) if av1_max(bw4, bh4) <= 16
    found_above = 1 if @found_match == 1
    @close_matches = found_above + found_left
    num_nearest = @num_mv_found
    num_new = @new_mv_count
    ws = @weight_stack
    i = 0
    while i < num_nearest
      ws[i] = ws[i] + 640
      i += 1
    @zero_mv_context = 0
    temporal_scan(is_comp) if @use_ref_frame_mvs == 1
    scan_point(-1, -1, is_comp)
    found_above = 1 if @found_match == 1
    @found_match = 0
    scan_row(-3, is_comp)
    found_above = 1 if @found_match == 1
    @found_match = 0
    scan_col(-3, is_comp)
    found_left = 1 if @found_match == 1
    @found_match = 0
    scan_row(-5, is_comp) if bh4 > 1
    found_above = 1 if @found_match == 1
    @found_match = 0
    scan_col(-5, is_comp) if bw4 > 1
    found_left = 1 if @found_match == 1
    @total_matches = found_above + found_left
    av1_mv_sort(@ref_stack, ws, 0, num_nearest)
    av1_mv_sort(@ref_stack, ws, num_nearest, @num_mv_found)
    extra_search(is_comp) if @num_mv_found < 2
    context_and_clamping(is_comp, num_new)
    nil

  -> setup_global_mv(list)
    rf = list == 0 ? @ref_frame0 : @ref_frame1
    typ = rf > 0 ? @gm_type[rf] : 0
    m0 = 0
    m1 = 0
    if rf <= 0 || typ == 0
      m0 = 0
      m1 = 0
    elsif typ == 1
      gm = @gm_params[rf]
      m0 = gm[0] >> 13
      m1 = gm[1] >> 13
    else
      gm = @gm_params[rf]
      x = @mi_col * 4 + @bw4 * 2 - 1
      y = @mi_row * 4 + @bh4 * 2 - 1
      xc = (gm[2] - 65536) * x + gm[3] * y + gm[0]
      yc = gm[4] * x + (gm[5] - 65536) * y + gm[1]
      if @allow_high_precision_mv == 1
        m0 = av1_round2signed(yc, 13)
        m1 = av1_round2signed(xc, 13)
      else
        m0 = av1_round2signed(yc, 14) * 2
        m1 = av1_round2signed(xc, 14) * 2
    @gmv[list * 2] = av1_lower_mv(m0, @allow_high_precision_mv, @force_integer_mv)
    @gmv[list * 2 + 1] = av1_lower_mv(m1, @allow_high_precision_mv, @force_integer_mv)
    nil

  -> scan_row(delta_row, is_comp)
    bw4 = @bw4
    end4 = av1_min(av1_min(bw4, @mi_cols - @mi_col), 16)
    delta_col = 0
    step16 = bw4 >= 16
    far = delta_row < -1
    if far
      delta_row += @mi_row & 1
      delta_col = 1 - (@mi_col & 1)
    i = 0
    while i < end4
      r = @mi_row + delta_row
      c = @mi_col + delta_col + i
      break if !is_inside(r, c)
      len = av1_min(bw4, AV1_BW4[@a_mi_sizes[r * @mis + c]])
      len = av1_max(2, len) if far
      len = av1_max(4, len) if step16
      add_ref_mv_candidate(r, c, is_comp, len * 2)
      i += len
    nil

  -> scan_col(delta_col, is_comp)
    bh4 = @bh4
    end4 = av1_min(av1_min(bh4, @mi_rows - @mi_row), 16)
    delta_row = 0
    step16 = bh4 >= 16
    far = delta_col < -1
    if far
      delta_row = 1 - (@mi_row & 1)
      delta_col += @mi_col & 1
    i = 0
    while i < end4
      r = @mi_row + delta_row + i
      c = @mi_col + delta_col
      break if !is_inside(r, c)
      len = av1_min(bh4, AV1_BH4[@a_mi_sizes[r * @mis + c]])
      len = av1_max(2, len) if far
      len = av1_max(4, len) if step16
      add_ref_mv_candidate(r, c, is_comp, len * 2)
      i += len
    nil

  -> scan_point(delta_row, delta_col, is_comp)
    r = @mi_row + delta_row
    c = @mi_col + delta_col
    if is_inside(r, c) && @a_ref0[r * @mis + c] != -2
      add_ref_mv_candidate(r, c, is_comp, 4)
    nil

  -> add_ref_mv_candidate(r, c, is_comp, weight)
    k = r * @mis + c
    return nil if @a_is_inters[k] == 0
    if is_comp == 0
      search_stack(k, 0, weight) if @a_ref0[k] == @ref_frame0
      search_stack(k, 1, weight) if @a_ref1[k] == @ref_frame0
    elsif @a_ref0[k] == @ref_frame0 && @a_ref1[k] == @ref_frame1
      compound_search_stack(k, weight)
    nil

  -> search_stack(k, cand_list, weight)
    cm = @a_y_modes[k]
    cs = @a_mi_sizes[k]
    large = av1_min(AV1_BW4[cs], AV1_BH4[cs]) >= 2
    m0 = 0
    m1 = 0
    if (cm == 16 || cm == 24) && @gm_type[@ref_frame0] > 1 && large
      m0 = @gmv[0]
      m1 = @gmv[1]
    else
      m0 = @a_mvs[k * 4 + cand_list * 2]
      m1 = @a_mvs[k * 4 + cand_list * 2 + 1]
    hp = @allow_high_precision_mv
    imv = @force_integer_mv
    m0 = av1_lower_mv(m0, hp, imv)
    m1 = av1_lower_mv(m1, hp, imv)
    @new_mv_count += 1 if av1_has_newmv(cm)
    @found_match = 1
    n = av1_stack_add1(@ref_stack, @weight_stack, @num_mv_found, m0, m1, weight)
    @num_mv_found = n
    nil

  -> compound_search_stack(k, weight)
    mv = @a_mvs
    a0 = mv[k * 4]
    a1 = mv[k * 4 + 1]
    b0 = mv[k * 4 + 2]
    b1 = mv[k * 4 + 3]
    cm = @a_y_modes[k]
    if cm == 24
      if @gm_type[@ref_frame0] > 1
        a0 = @gmv[0]
        a1 = @gmv[1]
      if @gm_type[@ref_frame1] > 1
        b0 = @gmv[2]
        b1 = @gmv[3]
    hp = @allow_high_precision_mv
    imv = @force_integer_mv
    a0 = av1_lower_mv(a0, hp, imv)
    a1 = av1_lower_mv(a1, hp, imv)
    b0 = av1_lower_mv(b0, hp, imv)
    b1 = av1_lower_mv(b1, hp, imv)
    @found_match = 1
    @num_mv_found = av1_stack_add2(@ref_stack, @weight_stack, @num_mv_found, a0, a1, b0, b1, weight)
    @new_mv_count += 1 if av1_has_newmv(cm)
    nil

  -> temporal_scan(is_comp)
    bw4 = @bw4
    bh4 = @bh4
    sw = bw4 >= 16 ? 4 : 2
    sh = bh4 >= 16 ? 4 : 2
    mh = av1_min(bh4, 16)
    mw = av1_min(bw4, 16)
    dr = 0
    while dr < mh
      dc = 0
      while dc < mw
        add_tpl_ref_mv(dr, dc, is_comp)
        dc += sw
      dr += sh
    if bh4 >= 2 && bh4 < 16 && bw4 >= 2 && bw4 < 16
      add_tpl_ref_mv(bh4, -2, is_comp) if check_sb_border(bh4, -2)
      add_tpl_ref_mv(bh4, bw4, is_comp) if check_sb_border(bh4, bw4)
      add_tpl_ref_mv(bh4 - 2, bw4, is_comp) if check_sb_border(bh4 - 2, bw4)
    nil

  -> check_sb_border(dr, dc)
    r = (@mi_row & 15) + dr
    c = (@mi_col & 15) + dc
    r >= 0 && r < 16 && c >= 0 && c < 16

  -> add_tpl_ref_mv(dr, dc, is_comp)
    r = (@mi_row + dr) | 1
    c = (@mi_col + dc) | 1
    return nil if !is_inside(r, c)
    x8 = c >> 1
    y8 = r >> 1
    w8 = @mi_cols >> 1
    h8 = @mi_rows >> 1
    zero = dr == 0 && dc == 0
    @zero_mv_context = 1 if zero
    mf = @mfmv
    hp = @allow_high_precision_mv
    imv = @force_integer_mv
    b0 = ((@ref_frame0 * h8 + y8) * w8 + x8) * 2
    a0 = mf[b0]
    return nil if a0 == -32768
    a1 = mf[b0 + 1]
    a0 = av1_lower_mv(a0, hp, imv)
    a1 = av1_lower_mv(a1, hp, imv)
    g = @gmv
    if is_comp == 0
      if zero
        @zero_mv_context = (av1_abs(a0 - g[0]) >= 16 || av1_abs(a1 - g[1]) >= 16) ? 1 : 0
      @num_mv_found = av1_stack_add1(@ref_stack, @weight_stack, @num_mv_found, a0, a1, 2)
    else
      b1i = ((@ref_frame1 * h8 + y8) * w8 + x8) * 2
      c0 = mf[b1i]
      return nil if c0 == -32768
      c1 = mf[b1i + 1]
      c0 = av1_lower_mv(c0, hp, imv)
      c1 = av1_lower_mv(c1, hp, imv)
      if zero
        z = av1_abs(a0 - g[0]) >= 16 || av1_abs(a1 - g[1]) >= 16 || av1_abs(c0 - g[2]) >= 16 || av1_abs(c1 - g[3]) >= 16
        @zero_mv_context = z ? 1 : 0
      @num_mv_found = av1_stack_add2(@ref_stack, @weight_stack, @num_mv_found, a0, a1, c0, c1, 2)
    nil

  -> extra_search(is_comp)
    @ref_id_count0 = 0
    @ref_id_count1 = 0
    @ref_diff_count0 = 0
    @ref_diff_count1 = 0
    w4 = av1_min(av1_min(16, @bw4), @mi_cols - @mi_col)
    h4 = av1_min(av1_min(16, @bh4), @mi_rows - @mi_row)
    n4 = av1_min(w4, h4)
    pass = 0
    while pass < 2
      idx = 0
      while idx < n4 && @num_mv_found < 2
        r = pass == 0 ? @mi_row - 1 : @mi_row + idx
        c = pass == 0 ? @mi_col + idx : @mi_col - 1
        break if !is_inside(r, c)
        add_extra_mv_candidate(r, c, is_comp)
        ms = @a_mi_sizes[r * @mis + c]
        idx += pass == 0 ? AV1_BW4[ms] : AV1_BH4[ms]
      pass += 1
    st = @ref_stack
    ws = @weight_stack
    g = @gmv
    if is_comp == 1
      cmb = @comb_mvs
      # combinedMvs[idx][list] stored at idx * 4 + list * 2
      list = 0
      while list < 2
        cnt = 0
        idc = list == 0 ? @ref_id_count0 : @ref_id_count1
        dfc = list == 0 ? @ref_diff_count0 : @ref_diff_count1
        i = 0
        while i < idc
          cmb[cnt * 4 + list * 2] = @ref_id_mvs[list * 4 + i * 2]
          cmb[cnt * 4 + list * 2 + 1] = @ref_id_mvs[list * 4 + i * 2 + 1]
          cnt += 1
          i += 1
        i = 0
        while i < dfc && cnt < 2
          cmb[cnt * 4 + list * 2] = @ref_diff_mvs[list * 4 + i * 2]
          cmb[cnt * 4 + list * 2 + 1] = @ref_diff_mvs[list * 4 + i * 2 + 1]
          cnt += 1
          i += 1
        while cnt < 2
          cmb[cnt * 4 + list * 2] = g[list * 2]
          cmb[cnt * 4 + list * 2 + 1] = g[list * 2 + 1]
          cnt += 1
        list += 1
      n = @num_mv_found
      if n == 1
        src = 0
        if cmb[0] == st[0] && cmb[1] == st[1] && cmb[2] == st[2] && cmb[3] == st[3]
          src = 1
        j = 0
        while j < 4
          st[n * 4 + j] = cmb[src * 4 + j]
          j += 1
        ws[n] = 2
        @num_mv_found = n + 1
      else
        idx = 0
        while idx < 2
          j = 0
          while j < 4
            st[n * 4 + j] = cmb[idx * 4 + j]
            j += 1
          ws[n] = 2
          n += 1
          idx += 1
        @num_mv_found = n
    else
      idx = @num_mv_found
      while idx < 2
        st[idx * 4] = g[0]
        st[idx * 4 + 1] = g[1]
        idx += 1
    nil

  -> add_extra_mv_candidate(r, c, is_comp)
    k = r * @mis + c
    mvs = @a_mvs
    if is_comp == 1
      cl = 0
      while cl < 2
        cr = cl == 0 ? @a_ref0[k] : @a_ref1[k]
        if cr > 0
          list = 0
          while list < 2
            m0 = mvs[k * 4 + cl * 2]
            m1 = mvs[k * 4 + cl * 2 + 1]
            rfl = list == 0 ? @ref_frame0 : @ref_frame1
            idc = list == 0 ? @ref_id_count0 : @ref_id_count1
            dfc = list == 0 ? @ref_diff_count0 : @ref_diff_count1
            if cr == rfl && idc < 2
              @ref_id_mvs[list * 4 + idc * 2] = m0
              @ref_id_mvs[list * 4 + idc * 2 + 1] = m1
              if list == 0
                @ref_id_count0 += 1
              else
                @ref_id_count1 += 1
            elsif dfc < 2
              if @ref_frame_sign_bias[cr] != @ref_frame_sign_bias[rfl]
                m0 = 0 - m0
                m1 = 0 - m1
              @ref_diff_mvs[list * 4 + dfc * 2] = m0
              @ref_diff_mvs[list * 4 + dfc * 2 + 1] = m1
              if list == 0
                @ref_diff_count0 += 1
              else
                @ref_diff_count1 += 1
            list += 1
        cl += 1
    else
      cl = 0
      while cl < 2
        cr = cl == 0 ? @a_ref0[k] : @a_ref1[k]
        if cr > 0
          m0 = mvs[k * 4 + cl * 2]
          m1 = mvs[k * 4 + cl * 2 + 1]
          if @ref_frame_sign_bias[cr] != @ref_frame_sign_bias[@ref_frame0]
            m0 = 0 - m0
            m1 = 0 - m1
          n = @num_mv_found
          idx = 0
          while idx < n
            break if m0 == @ref_stack[idx * 4] && m1 == @ref_stack[idx * 4 + 1]
            idx += 1
          if idx == n
            @ref_stack[idx * 4] = m0
            @ref_stack[idx * 4 + 1] = m1
            @weight_stack[idx] = 2
            @num_mv_found = n + 1
        cl += 1
    nil

  -> context_and_clamping(is_comp, num_new)
    n = @num_mv_found
    ws = @weight_stack
    idx = 0
    while idx < n
      z = 0
      if idx + 1 < n
        w0 = ws[idx]
        w1 = ws[idx + 1]
        if w0 >= 640
          z = 1 if w1 < 640
        else
          z = 2
      @drl_ctx[idx] = z
      idx += 1
    bw = @bw4 * 4
    bh = @bh4 * 4
    top = 0 - ((@mi_row * 4) * 8) - (128 + bh * 8)
    bottom = ((@mi_rows - @bh4 - @mi_row) * 4) * 8 + 128 + bh * 8
    left = 0 - ((@mi_col * 4) * 8) - (128 + bw * 8)
    right = ((@mi_cols - @bw4 - @mi_col) * 4) * 8 + 128 + bw * 8
    st = @ref_stack
    list = 0
    while list < 1 + is_comp
      idx = 0
      while idx < n
        o = idx * 4 + list * 2
        st[o] = av1_clip3(top, bottom, st[o])
        st[o + 1] = av1_clip3(left, right, st[o + 1])
        idx += 1
      list += 1
    tm = @total_matches
    if @close_matches == 0
      @new_mv_context = av1_min(tm, 1)
      @ref_mv_context = tm
    elsif @close_matches == 1
      @new_mv_context = 3 - av1_min(num_new, 1)
      @ref_mv_context = 2 + tm
    else
      @new_mv_context = 5 - av1_min(num_new, 1)
      @ref_mv_context = 5
    nil

  # ------------------------------------------------------------ OBMC / warp candidates

  -> has_overlappable_candidates
    mis = @mis
    if @avail_u
      x4 = @mi_col
      e = av1_min(@mi_cols, @mi_col + @bw4)
      while x4 < e
        return true if @a_ref0[(@mi_row - 1) * mis + (x4 | 1)] > 0
        x4 += 2
    if @avail_l
      y4 = @mi_row
      e = av1_min(@mi_rows, @mi_row + @bh4)
      while y4 < e
        return true if @a_ref0[(y4 | 1) * mis + @mi_col - 1] > 0
        y4 += 2
    false

  -> find_warp_samples
    @num_samples = 0
    @num_samples_scanned = 0
    w4 = @bw4
    h4 = @bh4
    mis = @mis
    do_tl = true
    do_tr = true
    if @avail_u
      sw = AV1_BW4[@a_mi_sizes[(@mi_row - 1) * mis + @mi_col]]
      if w4 <= sw
        co = 0 - (@mi_col & (sw - 1))
        do_tl = false if co < 0
        do_tr = false if co + sw > w4
        add_sample(-1, 0)
      else
        i = 0
        e = av1_min(w4, @mi_cols - @mi_col)
        while i < e
          sw = AV1_BW4[@a_mi_sizes[(@mi_row - 1) * mis + @mi_col + i]]
          step = av1_min(w4, sw)
          add_sample(-1, i)
          i += step
    if @avail_l
      shh = AV1_BH4[@a_mi_sizes[@mi_row * mis + @mi_col - 1]]
      if h4 <= shh
        ro = 0 - (@mi_row & (shh - 1))
        do_tl = false if ro < 0
        add_sample(0, -1)
      else
        i = 0
        e = av1_min(h4, @mi_rows - @mi_row)
        while i < e
          shh = AV1_BH4[@a_mi_sizes[(@mi_row + i) * mis + @mi_col - 1]]
          step = av1_min(h4, shh)
          add_sample(i, -1)
          i += step
    add_sample(-1, -1) if do_tl
    add_sample(-1, w4) if do_tr && av1_max(w4, h4) <= 16
    @num_samples = 1 if @num_samples == 0 && @num_samples_scanned > 0
    nil

  -> add_sample(dr, dc)
    return nil if @num_samples_scanned >= 8
    r = @mi_row + dr
    c = @mi_col + dc
    return nil if !is_inside(r, c)
    mis = @mis
    k = r * mis + c
    return nil if @a_ref0[k] == -2
    return nil if @a_ref0[k] != @ref_frame0
    return nil if @a_ref1[k] != -1
    cs = @a_mi_sizes[k]
    cw4 = AV1_BW4[cs]
    ch4 = AV1_BH4[cs]
    cr = r - (r & (ch4 - 1))
    cc = c - (c & (cw4 - 1))
    mid_y = cr * 4 + ch4 * 2 - 1
    mid_x = cc * 4 + cw4 * 2 - 1
    th = av1_clip3(16, 112, av1_max(@bw4 * 4, @bh4 * 4))
    kc = (cr * mis + cc) * 4
    m0 = @a_mvs[kc]
    m1 = @a_mvs[kc + 1]
    valid = (av1_abs(m0 - @mv[0]) + av1_abs(m1 - @mv[1])) <= th
    @num_samples_scanned += 1
    return nil if !valid && @num_samples_scanned > 1
    cl = @cand_list
    o = @num_samples * 4
    cl[o] = mid_y * 8
    cl[o + 1] = mid_x * 8
    cl[o + 2] = mid_y * 8 + m0
    cl[o + 3] = mid_x * 8 + m1
    @num_samples += 1 if valid
    nil

  # ------------------------------------------------------------ motion field (7.9)

  -> motion_field_estimation
    w8 = @mi_cols >> 1
    h8 = @mi_rows >> 1
    @mfmv = i32[8 * h8 * w8 * 2]
    av1_fill_i32(@mfmv, 8 * h8 * w8 * 2, -32768)
    last_idx = @ref_frame_idx[0]
    cur_gold = @order_hints[4]
    soh = @saved_order_hints[last_idx]
    last_alt = soh == nil ? -1 : soh[7]
    mf_project(1, -1) if last_alt != cur_gold
    stamp = 1
    if get_relative_dist(@order_hints[5], @order_hint) > 0
      stamp -= 1 if mf_project(5, 1)
    if get_relative_dist(@order_hints[6], @order_hint) > 0
      stamp -= 1 if mf_project(6, 1)
    if get_relative_dist(@order_hints[7], @order_hint) > 0 && stamp >= 0
      stamp -= 1 if mf_project(7, 1)
    mf_project(2, -1) if stamp >= 0
    nil

  -> mf_project(src, dst_sign)
    si = @ref_frame_idx[src - 1]
    return false if @ref_mi_rows[si] != @mi_rows || @ref_mi_cols[si] != @mi_cols
    return false if @ref_frame_type[si] == 2 || @ref_frame_type[si] == 0
    srefs = @saved_mf_refs[si]
    smvs = @saved_mf_mvs[si]
    soh = @saved_order_hints[si]
    return false if srefs == nil || soh == nil
    w8 = @mi_cols >> 1
    h8 = @mi_rows >> 1
    # per source ref frame: refOffset (0 = invalid) and per dst: refToDst
    offs = i64[8]
    rtd = i64[8]
    ref_to_cur = get_relative_dist(@order_hints[src], @order_hint)
    r = 1
    while r < 8
      ro = get_relative_dist(@order_hints[src], soh[r])
      valid = av1_abs(ref_to_cur) <= 31 && av1_abs(ro) <= 31 && ro > 0
      offs[r] = valid ? ro : 0
      rtd[r] = get_relative_dist(@order_hint, @order_hints[r])
      r += 1
    av1_mf_project(srefs, smvs, @mfmv, w8, h8, ref_to_cur * dst_sign, dst_sign, offs, rtd, AV1_DIV_MULT_T)
    true

  # Motion field motion vector storage (7.19), kept for odd rows / cols only
  # (the only positions the projection reads), compacted to h8 x w8.
  -> mf_store
    w8 = @mi_cols >> 1
    h8 = @mi_rows >> 1
    refs = i32[w8 * h8]
    mvs = i32[w8 * h8 * 2]
    if !@frame_is_intra
      dist = i64[8]
      r = 1
      while r < 8
        dist[r] = get_relative_dist(@ref_order_hint[@ref_frame_idx[r - 1]], @order_hint)
        r += 1
      av1_mf_store(@a_ref0, @a_ref1, @a_mvs, @mis, w8, h8, dist, refs, mvs)
    else
      av1_fill_i32(refs, w8 * h8, -1)
    @mf_refs = refs
    @mf_mvs = mvs
    nil

# ---------------------------------------------------------------- free helpers

-> av1_round2signed(x, n)
  x >= 0 ? (x + (1 << (n - 1))) >> n : 0 - ((0 - x + (1 << (n - 1))) >> n)

-> av1_lower_mv(v, hp, imv)
  return v if hp == 1
  if imv == 1
    a = v < 0 ? 0 - v : v
    ai = (a + 3) >> 3
    return v > 0 ? ai << 3 : 0 - (ai << 3)
  if (v & 1) != 0
    return v > 0 ? v - 1 : v + 1
  v

-> av1_has_newmv(m)
  m == 17 || m == 25 || m == 22 || m == 23 || m == 20 || m == 21

-> av1_ref_count_ctx(c0, c1)
  c0 < c1 ? 0 : (c0 == c1 ? 1 : 2)

-> av1_check_backward(rf)
  rf >= 5 && rf <= 7 ? 1 : 0

-> av1_samedir(a, b)
  (a >= 5) == (b >= 5)

-> av1_fill_i32(a, n, v) (i32[] i64 i64) i64
  i = 0 ## i64
  while i < n
    a[i] = v
    i += 1
  0

# stack entry idx: st[idx * 4 + list * 2 + comp]
-> av1_stack_add1(st, ws, n, m0, m1, weight) (i32[] i32[] i64 i64 i64 i64) i64
  idx = 0 ## i64
  while idx < n
    a = st[idx * 4] ## i64
    b = st[idx * 4 + 1] ## i64
    if a == m0 && b == m1
      ws[idx] = ws[idx] + weight
      return n
    idx += 1
  if n < 8
    st[n * 4] = m0
    st[n * 4 + 1] = m1
    ws[n] = weight
    return n + 1
  n

-> av1_stack_add2(st, ws, n, a0, a1, b0, b1, weight) (i32[] i32[] i64 i64 i64 i64 i64 i64) i64
  idx = 0 ## i64
  while idx < n
    o = (idx * 4) ## i64
    x0 = st[o] ## i64
    x1 = st[o + 1] ## i64
    x2 = st[o + 2] ## i64
    x3 = st[o + 3] ## i64
    if x0 == a0 && x1 == a1 && x2 == b0 && x3 == b1
      ws[idx] = ws[idx] + weight
      return n
    idx += 1
  if n < 8
    st[n * 4] = a0
    st[n * 4 + 1] = a1
    st[n * 4 + 2] = b0
    st[n * 4 + 3] = b1
    ws[n] = weight
    return n + 1
  n

# stable bubble sort by weight (descending) of stack entries start...end
-> av1_mv_sort(st, ws, start, e) (i32[] i32[] i64 i64) i64
  while e > start
    ne = (start) ## i64
    idx = (start + 1) ## i64
    while idx < e
      wa = ws[idx - 1] ## i64
      wb = ws[idx] ## i64
      if wa < wb
        ws[idx - 1] = wb
        ws[idx] = wa
        j = 0 ## i64
        while j < 4
          t = st[(idx - 1) * 4 + j] ## i64
          st[(idx - 1) * 4 + j] = st[idx * 4 + j]
          st[idx * 4 + j] = t
          j += 1
        ne = idx
      idx += 1
    e = ne
  0

-> av1_mv_proj(mv, num, den, dm) (i64 i64 i64 i32[]) i64
  cd = (den < 31 ? den : 31) ## i64
  cn = (num) ## i64
  cn = -31 if cn < -31
  cn = 31 if cn > 31
  d = dm[cd] ## i64
  x = (mv * cn * d) ## i64
  s = 0 ## i64
  if x >= 0
    s = (x + 8192) >> 14
  else
    s = 0 - ((0 - x + 8192) >> 14)
  s = -16383 if s < -16383
  s = 16383 if s > 16383
  s

-> av1_mf_pos(v8, delta, dst_sign, max8, max_off8) (i64 i64 i64 i64 i64) i64
  base8 = ((v8 >> 3) << 3) ## i64
  off8 = 0 ## i64
  if delta >= 0
    off8 = delta >> 6
  else
    off8 = 0 - ((0 - delta) >> 6)
  v = (v8 + dst_sign * off8) ## i64
  if v < 0 || v >= max8 || v < base8 - max_off8 || v >= base8 + 8 + max_off8
    return -1
  v

# projection (7.9.2) of one source frame's saved motion field into mf
-> av1_mf_project(srefs, smvs, mf, w8, h8, num, dst_sign, offs, rtd, dm) (i32[] i32[] i32[] i64 i64 i64 i64 i64[] i64[] i32[]) i64
  y8 = 0 ## i64
  plane = (w8 * h8 * 2) ## i64
  while y8 < h8
    x8 = 0 ## i64
    while x8 < w8
      k = (y8 * w8 + x8) ## i64
      sr = srefs[k] ## i64
      if sr > 0
        ro = (offs[sr]) ## i64
        if ro > 0
          m0 = smvs[k * 2] ## i64
          m1 = smvs[k * 2 + 1] ## i64
          p0 = (av1_mv_proj(m0, num, ro, dm)) ## i64
          p1 = (av1_mv_proj(m1, num, ro, dm)) ## i64
          py = (av1_mf_pos(y8, p0, dst_sign, h8, 0)) ## i64
          px = (av1_mf_pos(x8, p1, dst_sign, w8, 8)) ## i64
          if py >= 0 && px >= 0
            dst = 1 ## i64
            while dst < 8
              t = (rtd[dst]) ## i64
              o = (dst * plane + (py * w8 + px) * 2) ## i64
              mf[o] = av1_mv_proj(m0, t, ro, dm)
              mf[o + 1] = av1_mv_proj(m1, t, ro, dm)
              dst += 1
      x8 += 1
    y8 += 1
  0

-> av1_mf_store(ref0, ref1, mvs, mis, w8, h8, dist, refs, out) (i32[] i32[] i32[] i64 i64 i64 i64[] i32[] i32[]) i64
  y8 = 0 ## i64
  while y8 < h8
    x8 = 0 ## i64
    while x8 < w8
      k = ((2 * y8 + 1) * mis + 2 * x8 + 1) ## i64
      o = (y8 * w8 + x8) ## i64
      refs[o] = -1
      out[o * 2] = 0
      out[o * 2 + 1] = 0
      list = 0 ## i64
      while list < 2
        r = 0 ## i64
        if list == 0
          r = ref0[k]
        else
          r = ref1[k]
        if r > 0
          if dist[r] < 0
            m0 = mvs[k * 4 + list * 2] ## i64
            m1 = mvs[k * 4 + list * 2 + 1] ## i64
            a0 = (m0 < 0 ? 0 - m0 : m0) ## i64
            a1 = (m1 < 0 ? 0 - m1 : m1) ## i64
            if a0 <= 4095 && a1 <= 4095
              refs[o] = r
              out[o * 2] = m0
              out[o * 2 + 1] = m1
        list += 1
      x8 += 1
    y8 += 1
  0

-> av1_inter_i32(a)
  out = i32[a.size]
  i = 0
  while i < a.size
    out[i] = a[i]
    i += 1
  out

AV1_DIV_MULT_T = av1_inter_i32(AV1_DIV_MULT)
