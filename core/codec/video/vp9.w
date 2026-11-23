# core/codec/video/vp9 — VP9 video decoder (profile 0, 8-bit 4:2:0), pure Tungsten.
#
# Registered as "vp09". A sample is one VP9 frame or a superframe (several
# frames with a trailing index); decode returns the shown frames.
# Implements the uncompressed/compressed headers, the boolean decoder,
# forward and backward probability adaptation, partitions, segmentation,
# tiles, intra prediction, 8-tap/bilinear motion compensation with compound
# prediction, all inverse transforms (DCT/ADST 4..32, WHT lossless), the
# loop filter, reference management and show_existing_frame. Decoding is
# bit-exact with libvpx (and with FFmpeg's vp9 decoder, whose behaviour —
# including libvpx's quirks — served as the reference for the edge cases).
#
# Not yet: reference scaling (frame size changes with inter prediction from
# differently sized references), profiles 1-3 (4:4:4/4:2:2/high bit depth).

use core/codec/media
use vp9_tables
use vp9_dsp

+ VP9Error < StandardError
  rw :message

  -> new(@message)

  -> to_s
    @message

+ VP9Frame
  rw :y, :u, :v, :w, :h, :ys, :uvs, :mv, :segmap, :pts, :dur, :ah, :sb_cols, :seg

  -> new(@w, @h)
    @pts = ~0.0
    @dur = ~0.0

# Probability context layout (flattened ProbContext)
VP9P_YMODE = 0
VP9P_UVMODE = 36
VP9P_FILTER = 126
VP9P_MVMODE = 134
VP9P_INTRA = 155
VP9P_COMP = 159
VP9P_SREF = 164
VP9P_CREF = 174
VP9P_TX32 = 179
VP9P_TX16 = 185
VP9P_TX8 = 189
VP9P_SKIP = 191
VP9P_MVJ = 194
VP9P_MVC = 197
VP9P_PART = 263
VP9P_SIZE = 311

VP9_INV_MAP = [7, 20, 33, 46, 59, 72, 85, 98, 111, 124, 137, 150, 163, 176, 189, 202, 215, 228, 241, 254, 1, 2, 3, 4, 5, 6, 8, 9,
  10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 21, 22, 23, 24, 25, 26, 27, 28, 29, 30, 31, 32, 34, 35, 36, 37, 38, 39,
  40, 41, 42, 43, 44, 45, 47, 48, 49, 50, 51, 52, 53, 54, 55, 56, 57, 58, 60, 61, 62, 63, 64, 65, 66, 67, 68, 69,
  70, 71, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95, 96, 97, 99, 100,
  101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 112, 113, 114, 115, 116, 117, 118, 119, 120, 121, 122, 123, 125, 126, 127, 128, 129, 130,
  131, 132, 133, 134, 135, 136, 138, 139, 140, 141, 142, 143, 144, 145, 146, 147, 148, 149, 151, 152, 153, 154, 155, 156, 157, 158, 159, 160,
  161, 162, 164, 165, 166, 167, 168, 169, 170, 171, 172, 173, 174, 175, 177, 178, 179, 180, 181, 182, 183, 184, 185, 186, 187, 188, 190, 191,
  192, 193, 194, 195, 196, 197, 198, 199, 200, 201, 203, 204, 205, 206, 207, 208, 209, 210, 211, 212, 213, 214, 216, 217, 218, 219, 220, 221,
  222, 223, 224, 225, 226, 227, 229, 230, 231, 232, 233, 234, 235, 236, 237, 238, 239, 240, 242, 243, 244, 245, 246, 247, 248, 249, 250, 251,
  252, 253, 253]

VP9_LEFT_PCTX = [0x0, 0x8, 0x0, 0x8, 0xc, 0x8, 0xc, 0xe, 0xc, 0xe, 0xf, 0xe, 0xf]
VP9_ABOVE_PCTX = [0x0, 0x0, 0x8, 0x8, 0x8, 0xc, 0xc, 0xc, 0xe, 0xe, 0xe, 0xf, 0xf]
VP9_MAX_TX = [3, 3, 3, 3, 2, 2, 2, 1, 1, 1, 0, 0, 0]
VP9_SIZE_GROUP = [3, 3, 3, 3, 2, 2, 2, 1, 1, 1]
VP9_INTER_MODE_CTX = [6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5,
  6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5,
  6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5,
  6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5,
  6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5,
  6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5,
  6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5,
  6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5,
  6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5,
  6, 6, 6, 6, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5,
  5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 2, 2, 1, 3,
  5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 2, 2, 1, 3,
  5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 1, 1, 0, 3,
  5, 5, 5, 5, 5, 5, 5, 5, 5, 5, 3, 3, 3, 4]
VP9_MODE_OFF = [3, 0, 0, 1, 0, 0, 0, 0, 0, 0]
# mv_ref_blk_off[bs][8][2] (col, row)
VP9_MVREF_OFF = [3, -1, -1, 3, 4, -1, -1, 4, -1, -1, 0, -1, -1, 0, 6, -1,
  0, -1, -1, 0, 4, -1, -1, 2, -1, -1, 0, -3, -3, 0, 2, -1,
  -1, 0, 0, -1, -1, 4, 2, -1, -1, -1, -3, 0, 0, -3, -1, 2,
  1, -1, -1, 1, 2, -1, -1, 2, -1, -1, 0, -3, -3, 0, -3, -3,
  0, -1, -1, 0, 2, -1, -1, -1, -1, 1, 0, -3, -3, 0, -3, -3,
  -1, 0, 0, -1, -1, 2, -1, -1, 1, -1, -3, 0, 0, -3, -3, -3,
  0, -1, -1, 0, 1, -1, -1, 1, -1, -1, 0, -3, -3, 0, -3, -3,
  0, -1, -1, 0, 1, -1, -1, -1, 0, -2, -2, 0, -2, -1, -1, -2,
  -1, 0, 0, -1, -1, 1, -1, -1, -2, 0, 0, -2, -1, -2, -2, -1,
  0, -1, -1, 0, -1, -1, 0, -2, -2, 0, -1, -2, -2, -1, -2, -2,
  0, -1, -1, 0, -1, -1, 0, -2, -2, 0, -1, -2, -2, -1, -2, -2,
  0, -1, -1, 0, -1, -1, 0, -2, -2, 0, -1, -2, -2, -1, -2, -2,
  0, -1, -1, 0, -1, -1, 0, -2, -2, 0, -1, -2, -2, -1, -2, -2]
VP9_BAND_COUNTS = [1, 2, 3, 4, 3, 3, 0, 0, 1, 2, 3, 4, 11, 43, 0, 0, 1, 2, 3, 4, 11, 235, 0, 0, 1, 2, 3, 4, 11, 1003, 0, 0]
VP9_BWLOG = [0, 0, 1, 1, 1, 2, 2, 2, 3, 3, 3, 4, 4]

# counts layout (offsets into @counts)
VC_SKIP = 0
VC_INTRA = 8
VC_COMP = 16
VC_CREF = 26
VC_SREF = 36
VC_PART = 56
VC_TX32 = 120
VC_TX16 = 128
VC_TX8 = 134
VC_FILTER = 138
VC_MVMODE = 150
VC_MVJ = 178
VC_MVC = 182
VC_YMODE = 284
VC_UVMODE = 324

+ VP9Dec
  rw :frames_out

  -> new(cfg)
    @frames_out = 0
    @refs = [nil, nil, nil, nil, nil, nil, nil, nil]
    @spare = []          # buffer sets [y, u, v, mv, seg] of dead frames, reused (bury_dead)
    @out = []
    @last = nil
    @seg_ref = nil
    @last_invisible = 1
    @last_keyframe = 0
    @prev_seg_update = 0
    @sharp = -1
    @w = 0
    @h = 0
    @keyframe = 0
    @invisible = 0
    @bb = u8[16]
    @bp = 0
    @be = 0
    @bv = 0
    @bc = 0
    @br = 0
    @cur_y = u8[16]
    @cur_u = u8[16]
    @cur_v = u8[16]
    @cur_mv = i32[16]
    @cur_seg = u8[16]
    @ref_seg = u8[16]
    @prev_mv = i32[16]
    @have_prev_mv = 0
    @have_ref_seg = 0
    @lf_thread = nil
    @lf_prog = Atomic.new(0)
    @lf_threads = env("VP9_NO_THREADS") != nil ? 0 : 1
    vp9_alloc_static

  -> vp9_alloc_static
    @p = i64[VP9P_SIZE]
    @cp = i64[1728]
    @ctx_p = i64[4 * VP9P_SIZE]
    @ctx_cp = i64[4 * 1728]
    @defp = i64[VP9P_SIZE]
    vp9_fill(@defp, VP9_DEFAULT_PROBS)
    @defcp = i64[1728]
    vp9_fill(@defcp, VP9_DEFAULT_COEF_PROBS)
    @pareto = i64[2048]
    vp9_fill(@pareto, VP9_PARETO8)
    @kfy = i64[900]
    vp9_fill(@kfy, VP9_KF_YMODE_PROBS)
    @kfuv = i64[90]
    vp9_fill(@kfuv, VP9_KF_UVMODE_PROBS)
    @kfpart = i64[48]
    vp9_fill(@kfpart, VP9_KF_PARTITION_PROBS)
    @bwh = i64[52]
    vp9_fill(@bwh, VP9_BWH)
    @itree = i64[18]
    vp9_fill(@itree, VP9_INTRAMODE_TREE)
    @segtree = i64[14]
    vp9_fill(@segtree, VP9_SEGMENTATION_TREE)
    @parttree = i64[6]
    vp9_fill(@parttree, VP9_PARTITION_TREE)
    @imtree = i64[6]
    vp9_fill(@imtree, VP9_INTER_MODE_TREE)
    @ftree = i64[4]
    vp9_fill(@ftree, VP9_FILTER_TREE)
    @mvjtree = i64[6]
    vp9_fill(@mvjtree, VP9_MV_JOINT_TREE)
    @mvctree = i64[20]
    vp9_fill(@mvctree, VP9_MV_CLASS_TREE)
    @fptree = i64[6]
    vp9_fill(@fptree, VP9_MV_FP_TREE)
    @flut = i64[3]
    vp9_fill(@flut, VP9_FILTER_LUT)
    @txtype = i64[14]
    vp9_fill(@txtype, VP9_INTRA_TXFM_TYPE)
    @imctx = i64[196]
    vp9_fill(@imctx, VP9_INTER_MODE_CTX)
    @mvref_off = i64[208]
    vp9_fill(@mvref_off, VP9_MVREF_OFF)
    @bandc = i64[32]
    vp9_fill(@bandc, VP9_BAND_COUNTS)
    @filters = i64[384]
    vp9_fill(@filters, VP9_SUBPEL_FILTERS)
    @dcq = i64[256]
    @acq = i64[256]
    k = 0
    while k < 256
      @dcq[k] = VP9_DC_QLOOKUP[k]
      @acq[k] = VP9_AC_QLOOKUP[k]
      k += 1
    # scans: [tx][type] → offset into @scans/@nbs; 32x32 uses default only
    @scans = i64[16 + 64 * 3 + 256 * 3 + 1024 + 16 * 2]
    @nbs = i64[2 * (16 * 3 + 64 * 3 + 256 * 3 + 1024)]
    @scan_off = i64[20]
    o = 0
    lists = [[VP9_SCAN_DEFAULT_4X4, VP9_SCAN_COL_4X4, VP9_SCAN_ROW_4X4], [VP9_SCAN_DEFAULT_8X8, VP9_SCAN_COL_8X8, VP9_SCAN_ROW_8X8],
             [VP9_SCAN_DEFAULT_16X16, VP9_SCAN_COL_16X16, VP9_SCAN_ROW_16X16], [VP9_SCAN_DEFAULT_32X32]]
    nbl = [[VP9_NB_DEFAULT_4X4, VP9_NB_COL_4X4, VP9_NB_ROW_4X4], [VP9_NB_DEFAULT_8X8, VP9_NB_COL_8X8, VP9_NB_ROW_8X8],
           [VP9_NB_DEFAULT_16X16, VP9_NB_COL_16X16, VP9_NB_ROW_16X16], [VP9_NB_DEFAULT_32X32]]
    t = 0
    while t < 4
      kinds = lists[t]
      k = 0
      while k < kinds.size
        @scan_off[t * 4 + k] = o
        sc = kinds[k]
        nb = nbl[t][k]
        i = 0
        while i < sc.size
          @scans[o + i] = sc[i]
          @nbs[(o + i) * 2] = nb[i * 2]
          @nbs[(o + i) * 2 + 1] = nb[i * 2 + 1]
          i += 1
        o += sc.size
        k += 1
      t += 1
    # scan type per txtp: DCT_DCT default, DCT_ADST (iadst cols) row?, …
    # ffmpeg's ff_vp9_scans[tx] = { default, col, row, default } indexed by txtp
    @scan_by_type = i64[4]
    @scan_by_type[0] = 0
    @scan_by_type[1] = 1
    @scan_by_type[2] = 2
    @scan_by_type[3] = 0
    @mvscale = i64[6]
    @mvstep = i64[6]
    @emu288 = u8[288 * 288]
    @mc_tmp2 = u8[64 * 140]
    @lim_lut = i64[64]
    @mblim_lut = i64[64]
    @cache = u8[1024]
    @blk = i16[4096]
    @uvblk = i16[2048]
    @eob = i32[256]
    @uveob = i32[128]
    @tx_tmp = i16[1024]
    @tx_out = i16[32]
    @mc_tmp = u8[64 * 72]
    @emu = u8[80 * 80]
    @ia = i64[80]
    @il = i64[64]
    @iv = i64[128]
    @counts = i64[8192]
    @ccoef = i64[1728]
    @ceob = i64[1152]
    @feat = i64[8 * 8]
    @qmul = i64[8 * 4]
    @lflvl = i64[8 * 8]
    @lfdelta_ref = i64[4]
    @lfdelta_mode = i64[2]
    @segprob = i64[7]
    @segpred = i64[3]
    @refidx = i64[3]
    @signbias = i64[3]
    @varcomp = i64[2]
    @bmode = i64[4]
    @bmv = i64[16]
    @bref = i64[2]
    @pmv = i64[2]
    @tile_state = i64[64 * 6]
    @left_part = i64[8]
    @left_skip = i64[8]
    @left_txfm = i64[8]
    @left_mode = i64[16]
    @left_intra = i64[8]
    @left_comp = i64[8]
    @left_ref = i64[8]
    @left_filter = i64[8]
    @left_segpred = i64[8]
    @left_ynnz = i64[16]
    @left_uvnnz = i64[32]
    @left_mv = i64[64]
    @above_part = i64[16]
    0

  -> vp9_fill(r, a)
    i = 0
    while i < a.size
      r[i] = a[i]
      i += 1
    r

  # ------------------------------------------------------------ public API

  -> decode(sample)
    bury_dead()
    d = sample.data
    if d.is_a?(String)
      d = ccall("w_string_bytes_view", d) ## u8[]
    @pts = sample.pts
    @dur = sample.duration
    n = d.size
    # superframe index
    if n > 2
      last = d[n - 1]
      if (last & 0xe0) == 0xc0
        nf = (last & 7) + 1
        bsz = ((last >> 3) & 3) + 1
        isz = 2 + bsz * nf
        if n >= isz && d[n - isz] == last
          p = n - isz + 1
          off = 0
          k = 0
          while k < nf
            sz = 0
            j = 0
            while j < bsz
              sz = sz | (d[p + j] << (8 * j))
              j += 1
            p += bsz
            if sz > 0 && off + sz <= n - isz
              decode_frame(d, off, sz)
            off += sz
            k += 1
          # like libvpx, a superframe yields at most one picture: the last
          # shown frame (spatial SVC layers below the top are not displayed)
          o = @out
          @out = []
          if o.size > 1
            @frames_out -= o.size - 1
            return [o[o.size - 1]]
          return o
    decode_frame(d, 0, n)
    o = @out
    @out = []
    o

  -> flush
    []

  -> reset
    bury_dead()
    @refs = [nil, nil, nil, nil, nil, nil, nil, nil]
    @last = nil
    track_live()
    @have_prev_mv = 0
    @have_ref_seg = 0

  -> emit(f)
    vf = VideoFrame.new(f.w, f.h, [f.y, f.u, f.v], [f.ys, f.uvs, f.uvs], "420", 8, @pts)
    vf.duration = @dur
    vf.matrix = @color_matrix
    vf.primaries = @color_prim
    vf.transfer = @color_trc
    vf.full_range = @full_range == 1
    @out.push(vf)
    @frames_out += 1
    0

  # -------------------------------------------------------- bit reading

  -> gb_bits(n)
    v = 0
    k = 0
    while k < n
      by = @gpos >> 3
      bit = 0
      bit = (@gd[by] >> (7 - (@gpos & 7))) & 1 if by < @gend
      v = (v << 1) | bit
      @gpos += 1
      k += 1
    v

  -> gb_sbits_inv(n)
    v = gb_bits(n)
    gb_bits(1) == 1 ? 0 - v : v

  # Boolean (range) decoder over @bb[@bp...@be].
  -> bd_init(buf, start, size)
    @bb = buf
    @bp = start
    @be = start + size
    @bv = 0
    k = 0
    while k < 2
      @bv = (@bv << 8) | (@bp < @be ? @bb[@bp] : 0)
      @bp += 1
      k += 1
    @bc = 8
    @br = 255
    0

  -> bd(prob) (i64) i64
    split = 1 + (((@br - 1) * prob) >> 8)
    sc = split << @bc
    bit = 0 ## i64
    r = 0 ## i64
    if @bv >= sc
      @bv = @bv - sc
      r = @br - split
      bit = 1
    else
      r = split
    sh = 0 ## i64
    while r < 128
      r = r << 1
      sh += 1
    @br = r
    if sh > 0
      @bc = @bc - sh
      while @bc < 0
        b = 0 ## i64
        b = @bb[@bp] if @bp < @be
        @bp = @bp + 1
        @bv = (@bv << 8) | b
        @bc = @bc + 8
    bit

  -> bd_uint(n) (i64) i64
    v = 0 ## i64
    k = 0 ## i64
    while k < n
      v = (v << 1) | bd(128)
      k += 1
    v

  # Generic tree read: tree[i*2 + bit], probs at pr[po + i].
  -> bd_tree(tree, pr, po) (i64[] i64[] i64) i64
    i = 0 ## i64
    while true
      i = tree[i * 2 + bd(pr[po + i])]
      break if i <= 0
    0 - i

  -> update_prob(p) (i64) i64
    d = 0 ## i64
    if bd(128) == 0
      d = bd_uint(4)
    elsif bd(128) == 0
      d = bd_uint(4) + 16
    elsif bd(128) == 0
      d = bd_uint(5) + 32
    else
      d = bd_uint(7)
      d = (d << 1) - 65 + bd(128) if d >= 65
      d += 64
    m = VP9_INV_MAP[d]
    if p <= 128
      1 + vp9_recenter(m, p - 1)
    else
      255 - vp9_recenter(m, 255 - p)

  -> diff_update(idx)
    @p[idx] = update_prob(@p[idx]) if bd(252) == 1
    0

  -> mv_update(idx)
    @p[idx] = (bd_uint(7) << 1) | 1 if bd(252) == 1
    0

  # ------------------------------------------------------------- headers

  -> decode_frame(d, off, size)
    @gd = d
    @gpos = off * 8
    @gend = off + size
    raise VP9Error.new("vp9: invalid frame marker") if gb_bits(2) != 2
    profile = gb_bits(1)
    profile = profile | (gb_bits(1) << 1)
    profile += gb_bits(1) if profile == 3
    raise VP9Error.new("vp9: profile [profile] not supported") if profile != 0
    if gb_bits(1) == 1
      idx = gb_bits(3)
      f = @refs[idx]
      emit(f) if f != nil
      return 0
    @last_keyframe = @keyframe
    @keyframe = 1 - gb_bits(1)
    prev_invisible = @invisible
    @invisible = 1 - gb_bits(1)
    @errorres = gb_bits(1)
    @use_last_mvs = (@errorres == 0 && prev_invisible == 0) ? 1 : 0
    @intraonly = 0
    resetctx = 0
    w = 0
    h = 0
    if @keyframe == 1
      raise VP9Error.new("vp9: bad sync code") if gb_bits(24) != 0x498342
      read_color
      @refresh = 0xff
      w = gb_bits(16) + 1
      h = gb_bits(16) + 1
      gb_bits(32) if gb_bits(1) == 1
    else
      @intraonly = @invisible == 1 ? gb_bits(1) : 0
      resetctx = @errorres == 1 ? 0 : gb_bits(2)
      if @intraonly == 1
        raise VP9Error.new("vp9: bad sync code") if gb_bits(24) != 0x498342
        @refresh = gb_bits(8)
        w = gb_bits(16) + 1
        h = gb_bits(16) + 1
        gb_bits(32) if gb_bits(1) == 1
      else
        @refresh = gb_bits(8)
        k = 0
        while k < 3
          @refidx[k] = gb_bits(3)
          sb = gb_bits(1)
          @signbias[k] = (sb == 1 && @errorres == 0) ? 1 : 0
          k += 1
        k = 0
        while k < 3
          raise VP9Error.new("vp9: missing reference") if @refs[@refidx[k]] == nil
          k += 1
        found = false
        k = 0
        while k < 3 && !found
          if gb_bits(1) == 1
            w = @refs[@refidx[k]].w
            h = @refs[@refidx[k]].h
            found = true
          k += 1
        if !found
          w = gb_bits(16) + 1
          h = gb_bits(16) + 1
        @use_last_mvs = 0 if @last == nil || @last.w != w || @last.h != h
        gb_bits(32) if gb_bits(1) == 1
        @hp = gb_bits(1)
        @filtermode = gb_bits(1) == 1 ? 4 : gb_bits(2)
        @allowcomp = (@signbias[0] != @signbias[1] || @signbias[0] != @signbias[2]) ? 1 : 0
        if @allowcomp == 1
          if @signbias[0] == @signbias[1]
            @fixcomp = 2
            @varcomp[0] = 0
            @varcomp[1] = 1
          elsif @signbias[0] == @signbias[2]
            @fixcomp = 1
            @varcomp[0] = 0
            @varcomp[1] = 2
          else
            @fixcomp = 0
            @varcomp[0] = 1
            @varcomp[1] = 2
    @refreshctx = @errorres == 1 ? 0 : gb_bits(1)
    @parallel = @errorres == 1 ? 1 : gb_bits(1)
    c = gb_bits(2)
    @ctxid = (@keyframe == 1 || @intraonly == 1) ? 0 : c
    if @keyframe == 1 || @errorres == 1 || @intraonly == 1
      @lfdelta_ref[0] = 1
      @lfdelta_ref[1] = 0
      @lfdelta_ref[2] = -1
      @lfdelta_ref[3] = -1
      @lfdelta_mode[0] = 0
      @lfdelta_mode[1] = 0
      k = 0
      while k < 64
        @feat[k] = 0
        k += 1
    @lf_level = gb_bits(6)
    sharp = gb_bits(3)
    if sharp != @sharp
      i = 1
      while i <= 63
        limit = i
        if sharp > 0
          limit = limit >> ((sharp + 3) >> 2)
          limit = 9 - sharp if limit > 9 - sharp
        limit = 1 if limit < 1
        @lim_lut[i] = limit
        @mblim_lut[i] = 2 * (i + 2) + limit
        i += 1
    @sharp = sharp
    @lfd_enabled = gb_bits(1)
    if @lfd_enabled == 1
      if gb_bits(1) == 1
        k = 0
        while k < 4
          @lfdelta_ref[k] = gb_sbits_inv(6) if gb_bits(1) == 1
          k += 1
        k = 0
        while k < 2
          @lfdelta_mode[k] = gb_sbits_inv(6) if gb_bits(1) == 1
          k += 1
    @yac_qi = gb_bits(8)
    @ydc_qd = gb_bits(1) == 1 ? gb_sbits_inv(4) : 0
    @uvdc_qd = gb_bits(1) == 1 ? gb_sbits_inv(4) : 0
    @uvac_qd = gb_bits(1) == 1 ? gb_sbits_inv(4) : 0
    @lossless = (@yac_qi == 0 && @ydc_qd == 0 && @uvdc_qd == 0 && @uvac_qd == 0) ? 1 : 0
    prev_seg_enabled = @seg_enabled
    prev_seg_update = @seg_update
    @seg_enabled = gb_bits(1)
    @seg_update = 0
    @seg_temporal = 0
    if @seg_enabled == 1
      @seg_update = gb_bits(1)
      if @seg_update == 1
        k = 0
        while k < 7
          @segprob[k] = gb_bits(1) == 1 ? gb_bits(8) : 255
          k += 1
        @seg_temporal = gb_bits(1)
        if @seg_temporal == 1
          k = 0
          while k < 3
            @segpred[k] = gb_bits(1) == 1 ? gb_bits(8) : 255
            k += 1
      if gb_bits(1) == 1
        @seg_abs = gb_bits(1)
        k = 0
        while k < 8
          b = k * 8
          @feat[b] = gb_bits(1)
          @feat[b + 1] = @feat[b] == 1 ? gb_sbits_inv(8) : 0
          @feat[b + 2] = gb_bits(1)
          @feat[b + 3] = @feat[b + 2] == 1 ? gb_sbits_inv(6) : 0
          @feat[b + 4] = gb_bits(1)
          @feat[b + 5] = @feat[b + 4] == 1 ? gb_bits(2) : 0
          @feat[b + 6] = gb_bits(1)
          k += 1
    # quantisers and filter levels per segment
    nseg = @seg_enabled == 1 ? 8 : 1
    k = 0
    while k < nseg
      b = k * 8
      qyac = @yac_qi
      if @seg_enabled == 1 && @feat[b] == 1
        qyac = @seg_abs == 1 ? vp9_clipu8(@feat[b + 1]) : vp9_clipu8(@yac_qi + @feat[b + 1])
      qydc = vp9_clipu8(qyac + @ydc_qd)
      quvdc = vp9_clipu8(qyac + @uvdc_qd)
      quvac = vp9_clipu8(qyac + @uvac_qd)
      qyac = vp9_clipu8(qyac)
      @qmul[k * 4] = @dcq[qydc]
      @qmul[k * 4 + 1] = @acq[qyac]
      @qmul[k * 4 + 2] = @dcq[quvdc]
      @qmul[k * 4 + 3] = @acq[quvac]
      sh = @lf_level >= 32 ? 1 : 0
      lvl = @lf_level
      if @seg_enabled == 1 && @feat[b + 2] == 1
        lvl = @seg_abs == 1 ? vp9_clip6(@feat[b + 3]) : vp9_clip6(@lf_level + @feat[b + 3])
      if @lfd_enabled == 1
        @lflvl[k * 8] = vp9_clip6(lvl + (@lfdelta_ref[0] << sh))
        @lflvl[k * 8 + 1] = @lflvl[k * 8]
        j = 1
        while j < 4
          @lflvl[k * 8 + j * 2] = vp9_clip6(lvl + ((@lfdelta_ref[j] + @lfdelta_mode[0]) << sh))
          @lflvl[k * 8 + j * 2 + 1] = vp9_clip6(lvl + ((@lfdelta_ref[j] + @lfdelta_mode[1]) << sh))
          j += 1
      else
        j = 0
        while j < 8
          @lflvl[k * 8 + j] = lvl
          j += 1
      k += 1
    # frame size / tiles
    set_size(w, h)
    @log2_tc = 0
    while (@sb_cols >> @log2_tc) > 64
      @log2_tc += 1
    mx = 0
    while (@sb_cols >> mx) >= 4
      mx += 1
    mx = mx - 1
    mx = 0 if mx < 0
    while mx > @log2_tc
      if gb_bits(1) == 1
        @log2_tc += 1
      else
        break
    @log2_tr = gb_bits(1)
    @log2_tr += gb_bits(1) if @log2_tr == 1
    # (log2_tile_cols minimum: smallest k with sb_cols >> k <= 64)
    if @keyframe == 0 && @intraonly == 0
      nvalid = 0
      k = 0
      while k < 3
        r = @refs[@refidx[k]]
        if r.w == w && r.h == h
          @mvscale[k * 2] = 0
          @mvscale[k * 2 + 1] = 0
          nvalid += 1
        elsif w * 2 < r.w || h * 2 < r.h || w > 16 * r.w || h > 16 * r.h
          @mvscale[k * 2] = -1
          @mvscale[k * 2 + 1] = -1
        else
          nvalid += 1
          @mvscale[k * 2] = (r.w << 14) / w
          @mvscale[k * 2 + 1] = (r.h << 14) / h
          @mvstep[k * 2] = (16 * @mvscale[k * 2]) >> 14
          @mvstep[k * 2 + 1] = (16 * @mvscale[k * 2 + 1]) >> 14
        k += 1
      raise VP9Error.new("vp9: no valid reference frame") if nvalid == 0
    # probability contexts reset
    if @keyframe == 1 || @errorres == 1 || (@intraonly == 1 && resetctx == 3)
      k = 0
      while k < 4
        vp9_copy(@ctx_p, k * VP9P_SIZE, @defp, 0, VP9P_SIZE)
        vp9_copy(@ctx_cp, k * 1728, @defcp, 0, 1728)
        k += 1
    elsif @intraonly == 1 && resetctx == 2
      vp9_copy(@ctx_p, c * VP9P_SIZE, @defp, 0, VP9P_SIZE)
      vp9_copy(@ctx_cp, c * 1728, @defcp, 0, 1728)
    size2 = gb_bits(16)
    hdr_bytes = ((@gpos + 7) >> 3) - off
    data2 = off + hdr_bytes
    raise VP9Error.new("vp9: bad compressed header size") if data2 + size2 > off + size
    bd_init(d, data2, size2)
    raise VP9Error.new("vp9: marker bit set") if bd(128) == 1
    vp9_copy(@p, 0, @ctx_p, @ctxid * VP9P_SIZE, VP9P_SIZE)
    read_compressed_header
    # segmentation map references (see the module notes)
    retain = @have_ref_seg == 1 && (prev_seg_enabled == 0 || prev_seg_update == 0)
    src_prev = @keyframe == 0 && @intraonly == 0 && @errorres == 0
    if !retain || @keyframe == 1 || @intraonly == 1
      if src_prev && @last != nil && @last.segmap != nil
        # a copy: the map may stay in use after its frame's buffers were recycled
        sm = @last.segmap ## u8[]
        if @ref_seg.size != sm.size
          ccall("w_value_free_w", @ref_seg)
          @ref_seg = u8[sm.size]
        vp9_copy8(@ref_seg, sm, sm.size)
        @have_ref_seg = 1
      else
        @have_ref_seg = 0
    @have_ref_seg = 0 if @last == nil || @last.w != w || @last.h != h
    if src_prev && @last != nil
      @prev_mv = @last.mv
      @have_prev_mv = 1
    else
      @have_prev_mv = 0
    @use_last_mvs = 0 if @have_prev_mv == 0
    decode_tiles(d, data2 + size2, off + size - (data2 + size2))
    # backward adaptation
    if @refreshctx == 1 && @parallel == 0
      adapt_probs
    elsif @refreshctx == 1 && @parallel == 1
      k = 0
      while k < 4
        n = 432
        vp9_copy(@ctx_cp, @ctxid * 1728 + k * 432, @cp, k * 432, 432)
        break if @txmode == k
        k += 1
      vp9_copy(@ctx_p, @ctxid * VP9P_SIZE, @p, 0, VP9P_SIZE)
    if @lf_thread != nil
      @lf_prog.store(@sb_rows)
      @lf_thread.join
      @lf_thread = nil
    elsif @lf_level > 0
      loop_filter_frame
    f = @curf
    k = 0
    while k < 8
      @refs[k] = f if ((@refresh >> k) & 1) == 1
      k += 1
    @last = f
    track_live()
    emit(f) if @invisible == 0
    0

  # Frames no longer referenced (not in a reference slot, not the last frame)
  # are queued and released at the next call (Tungsten has no collector; their
  # planes may have been handed out as this call's output frame).
  -> track_live
    live = []
    k = 0
    while k < 8
      r = @refs[k]
      live.push(r) if r != nil && !live.include?(r)
      k += 1
    live.push(@last) if @last != nil && !live.include?(@last)
    @grave = [] if @grave == nil
    if @live != nil
      @live.each ->(q)
        @grave.push(q) if !live.include?(q) && !@grave.include?(q)
    @live = live
    nil

  -> bury_dead
    if @grave != nil
      @grave.each ->(q)
        if q.y != nil && q.seg != nil && @spare.size < 4 && q.ys == @sb_cols * 64 && q.ah == @sb_rows * 64
          @spare.push([q.y, q.u, q.v, q.mv, q.seg])
        else
          ccall("w_value_free_w", q.y) if q.y != nil
          ccall("w_value_free_w", q.u) if q.u != nil
          ccall("w_value_free_w", q.v) if q.v != nil
          ccall("w_value_free_w", q.mv) if q.mv != nil
          ccall("w_value_free_w", q.seg) if q.seg != nil
        q.seg = nil
        q.segmap = nil
        q.y = nil
        q.u = nil
        q.v = nil
        q.mv = nil
    @grave = []
    nil

  -> read_color
    cs = gb_bits(3)
    @color_space = cs
    @full_range = gb_bits(1)
    @color_matrix = 6
    @color_prim = 6
    @color_trc = 6
    if cs == 2
      @color_matrix = 1
      @color_prim = 1
      @color_trc = 1
    elsif cs == 3
      @color_matrix = 7
      @color_prim = 7
      @color_trc = 7
    elsif cs == 5
      @color_matrix = 9
      @color_prim = 9
      @color_trc = 14
    raise VP9Error.new("vp9: RGB is not supported in profile 0") if cs == 7
    0

  -> set_size(w, h)
    @w = w
    @h = h
    @cols = (w + 7) >> 3
    @rows = (h + 7) >> 3
    nsc = (@cols + 7) >> 3
    nsr = (@rows + 7) >> 3
    if nsc != @sb_cols || nsr != @sb_rows || @above_skip == nil
      @sb_cols = nsc
      @sb_rows = nsr
      n = @sb_cols * 8
      @above_part = i64[n + 8]
      @above_skip = i64[n + 8]
      @above_txfm = i64[n + 8]
      @above_mode = i64[n * 2 + 16]
      @above_intra = i64[n + 8]
      @above_comp = i64[n + 8]
      @above_ref = i64[n + 8]
      @above_filter = i64[n + 8]
      @above_segpred = i64[n + 8]
      @above_ynnz = i64[n * 2 + 16]
      @above_uvnnz = i64[n * 2 + 16]
      @uvo = n + 8
      @above_mv = i64[n * 8 + 64]
      @lf_lvl = u8[@sb_cols * @sb_rows * 64]
      @lf_mask = i32[@sb_cols * @sb_rows * 128]
    # current frame buffers (64-aligned so blocks may overhang the edge)
    f = VP9Frame.new(w, h)
    f.ys = @sb_cols * 64
    f.uvs = @sb_cols * 32
    f.ah = @sb_rows * 64
    f.sb_cols = @sb_cols
    take_buffers()
    f.seg = @cur_seg
    f.y = @cur_y
    f.u = @cur_u
    f.v = @cur_v
    f.mv = @cur_mv
    f.segmap = nil
    f.pts = @pts
    @ys = f.ys
    @uvs = f.uvs
    @curf = f
    0

  # The current frame's buffers: a pooled set of this size, cleared as fresh
  # ones are, or new ones.
  -> take_buffers
    ny = @sb_cols * 64 * @sb_rows * 64
    while @spare.size > 0
      b = @spare.pop
      if b[0].size == ny && b[3].size == @sb_cols * 8 * @sb_rows * 8 * 6
        @cur_y = b[0] ## u8[]
        @cur_u = b[1] ## u8[]
        @cur_v = b[2] ## u8[]
        @cur_mv = b[3] ## i32[]
        @cur_seg = b[4] ## u8[]
        @cur_y.fill(0)
        @cur_u.fill(0)
        @cur_v.fill(0)
        @cur_mv.fill(0)
        @cur_seg.fill(0)
        return 0
      b.each ->(a) ccall("w_value_free_w", a)
    @cur_y = u8[ny]
    @cur_u = u8[@sb_cols * 32 * @sb_rows * 32]
    @cur_v = u8[@sb_cols * 32 * @sb_rows * 32]
    @cur_mv = i32[@sb_cols * 8 * @sb_rows * 8 * 6]
    @cur_seg = u8[@sb_cols * 8 * @sb_rows * 8]
    0

  -> read_compressed_header
    if @lossless == 1
      @txmode = 0
    else
      @txmode = bd_uint(2)
      @txmode += bd(128) if @txmode == 3
      if @txmode == 4
        k = 0
        while k < 2
          diff_update(VP9P_TX8 + k)
          k += 1
        k = 0
        while k < 4
          diff_update(VP9P_TX16 + k)
          k += 1
        k = 0
        while k < 6
          diff_update(VP9P_TX32 + k)
          k += 1
    # coefficient probabilities
    i = 0
    while i < 4
      base = i * 432
      cb = @ctxid * 1728
      if bd(128) == 1
        j = 0
        while j < 2 * 2 * 6 * 6
          band = (j / 6) % 6
          ctx = j % 6
          if !(band == 0 && ctx >= 3)
            n = 0
            while n < 3
              q = base + j * 3 + n
              if bd(252) == 1
                @cp[q] = update_prob(@ctx_cp[cb + q])
              else
                @cp[q] = @ctx_cp[cb + q]
              n += 1
          j += 1
      else
        vp9_copy(@cp, base, @ctx_cp, cb + base, 432)
      break if @txmode == i
      i += 1
    k = 0
    while k < 3
      diff_update(VP9P_SKIP + k)
      k += 1
    @comppred = 0
    if @keyframe == 0 && @intraonly == 0
      k = 0
      while k < 21
        diff_update(VP9P_MVMODE + k)
        k += 1
      if @filtermode == 4
        k = 0
        while k < 8
          diff_update(VP9P_FILTER + k)
          k += 1
      k = 0
      while k < 4
        diff_update(VP9P_INTRA + k)
        k += 1
      if @allowcomp == 1
        @comppred = bd(128)
        @comppred += bd(128) if @comppred == 1
        if @comppred == 2
          k = 0
          while k < 5
            diff_update(VP9P_COMP + k)
            k += 1
      if @comppred != 1
        k = 0
        while k < 5
          diff_update(VP9P_SREF + k * 2)
          diff_update(VP9P_SREF + k * 2 + 1)
          k += 1
      if @comppred != 0
        k = 0
        while k < 5
          diff_update(VP9P_CREF + k)
          k += 1
      k = 0
      while k < 36
        diff_update(VP9P_YMODE + k)
        k += 1
      i = 0
      while i < 4
        j = 0
        while j < 12
          diff_update(VP9P_PART + (3 - i) * 12 + j)
          j += 1
        i += 1
      k = 0
      while k < 3
        mv_update(VP9P_MVJ + k)
        k += 1
      i = 0
      while i < 2
        b = VP9P_MVC + i * 33
        mv_update(b)
        k = 0
        while k < 10
          mv_update(b + 1 + k)
          k += 1
        mv_update(b + 11)
        k = 0
        while k < 10
          mv_update(b + 12 + k)
          k += 1
        i += 1
      i = 0
      while i < 2
        b = VP9P_MVC + i * 33
        k = 0
        while k < 6
          mv_update(b + 22 + k)
          k += 1
        k = 0
        while k < 3
          mv_update(b + 28 + k)
          k += 1
        i += 1
      if @hp == 1
        i = 0
        while i < 2
          b = VP9P_MVC + i * 33
          mv_update(b + 31)
          mv_update(b + 32)
          i += 1
    0

  # ----------------------------------------------------------------- tiles

  -> decode_tiles(d, start, size)
    # reset above contexts and counts
    vp9_zero(@above_part)
    vp9_zero(@above_skip)
    vp9_zero(@above_txfm)
    vp9_zero(@above_intra)
    vp9_zero(@above_comp)
    vp9_zero(@above_ref)
    vp9_zero(@above_filter)
    vp9_set(@above_mode, (@keyframe == 1 || @intraonly == 1) ? 2 : 10)
    vp9_zero(@above_ynnz)
    vp9_zero(@above_uvnnz)
    vp9_zero(@above_segpred)
    vp9_zero(@above_mv)
    vp9_zero(@counts)
    vp9_zero(@ccoef)
    vp9_zero(@ceob)
    m = @lf_mask
    vp9_zero32(m)
    ncols = 1 << @log2_tc
    nrows = 1 << @log2_tr
    # loop filter of SB row r runs on a worker once rows 0..r+1 are decoded
    @lf_thread = nil
    if @lf_level > 0 && @sb_rows >= 3 && @lf_threads == 1
      @lf_prog.store(0)
      me = self
      @lf_thread = Thread.new ->
        me.lf_worker
    pos = start
    rem = size
    tr = 0
    while tr < nrows
      rs = vp9_tile_off(tr, @log2_tr, @sb_rows)
      re = vp9_tile_off(tr + 1, @log2_tr, @sb_rows)
      tc = 0
      while tc < ncols
        tsz = 0
        if tc == ncols - 1 && tr == nrows - 1
          tsz = rem
        else
          tsz = (d[pos] << 24) | (d[pos + 1] << 16) | (d[pos + 2] << 8) | d[pos + 3]
          pos += 4
          rem -= 4
        raise VP9Error.new("vp9: bad tile size") if tsz > rem
        bd_init(d, pos, tsz)
        raise VP9Error.new("vp9: tile marker bit set") if bd(128) == 1
        save_tile(tc)
        pos += tsz
        rem -= tsz
        tc += 1
      row = rs
      while row < re
        tc = 0
        while tc < ncols
          cs = vp9_tile_off(tc, @log2_tc, @sb_cols)
          ce = vp9_tile_off(tc + 1, @log2_tc, @sb_cols)
          @tile_col_start = cs
          load_tile(tc)
          vp9_zero(@left_part)
          vp9_zero(@left_skip)
          vp9_zero(@left_txfm)
          vp9_set(@left_mode, (@keyframe == 1 || @intraonly == 1) ? 2 : 10)
          vp9_zero(@left_intra)
          vp9_zero(@left_comp)
          vp9_zero(@left_ref)
          vp9_zero(@left_filter)
          vp9_zero(@left_ynnz)
          vp9_zero(@left_uvnnz)
          vp9_zero(@left_segpred)
          vp9_zero(@left_mv)
          col = cs
          while col < ce
            decode_sb(row, col, 0)
            col += 8
          save_tile(tc)
          tc += 1
        row += 8
        @lf_prog.store(row >> 3) if @lf_thread != nil
      tr += 1
    @curf.segmap = @cur_seg if @seg_enabled == 1 && (@seg_update == 1 || @keyframe == 1 || @intraonly == 1)
    0

  -> save_tile(tc)
    b = tc * 6
    @tile_state[b] = @bp
    @tile_state[b + 1] = @be
    @tile_state[b + 2] = @bv
    @tile_state[b + 3] = @bc
    @tile_state[b + 4] = @br
    0

  -> load_tile(tc)
    b = tc * 6
    @bp = @tile_state[b]
    @be = @tile_state[b + 1]
    @bv = @tile_state[b + 2]
    @bc = @tile_state[b + 3]
    @br = @tile_state[b + 4]
    0

  # Partition recursion (row/col in 8x8 units, bl = block level 0..3).
  -> decode_sb(row, col, bl)
    c = ((@above_part[col] >> (3 - bl)) & 1) | (((@left_part[row & 7] >> (3 - bl)) & 1) << 1)
    kf = @keyframe == 1 || @intraonly == 1
    pr = kf ? @kfpart : @p
    po = kf ? (bl * 12 + c * 3) : (VP9P_PART + bl * 12 + c * 3)
    hbs = 4 >> bl
    bp = 0
    if bl == 3
      bp = bd_tree(@parttree, pr, po)
      decode_block(row, col, bl, bp)
    elsif col + hbs < @cols
      if row + hbs < @rows
        bp = bd_tree(@parttree, pr, po)
        if bp == 0
          decode_block(row, col, bl, bp)
        elsif bp == 1
          decode_block(row, col, bl, bp)
          decode_block(row + hbs, col, bl, bp)
        elsif bp == 2
          decode_block(row, col, bl, bp)
          decode_block(row, col + hbs, bl, bp)
        else
          decode_sb(row, col, bl + 1)
          decode_sb(row, col + hbs, bl + 1)
          decode_sb(row + hbs, col, bl + 1)
          decode_sb(row + hbs, col + hbs, bl + 1)
      elsif bd(pr[po + 1]) == 1
        bp = 3
        decode_sb(row, col, bl + 1)
        decode_sb(row, col + hbs, bl + 1)
      else
        bp = 1
        decode_block(row, col, bl, bp)
    elsif row + hbs < @rows
      if bd(pr[po + 2]) == 1
        bp = 3
        decode_sb(row, col, bl + 1)
        decode_sb(row + hbs, col, bl + 1)
      else
        bp = 2
        decode_block(row, col, bl, bp)
    else
      bp = 3
      decode_sb(row, col, bl + 1)
    @counts[VC_PART + (bl * 4 + c) * 4 + bp] += 1
    0

  # --------------------------------------------------------------- blocks

  -> decode_block(row, col, bl, bp)
    bs = bl * 3 + bp
    w4 = @bwh[26 + bs * 2]
    h4 = @bwh[26 + bs * 2 + 1]
    @row = row
    @col = col
    @row7 = row & 7
    @col7 = col & 7
    @bs = bs
    @min_mvx = 0 - (128 + col * 64)
    @min_mvy = 0 - (128 + row * 64)
    @max_mvx = 128 + (@cols - col - w4) * 64
    @max_mvy = 128 + (@rows - row - h4) * 64
    decode_mode(w4, h4)
    @uvtx = @tx
    @uvtx = @tx - 1 if w4 * 2 == (1 << @tx) || h4 * 2 == (1 << @tx)
    if @skip == 0
      has = decode_coeffs(w4, h4)
      if has == 0 && bs <= 9 && @intra == 0
        @skip = 1
        vp9_setn(@above_skip, col, w4, 1)
        vp9_setn(@left_skip, @row7, h4, 1)
    else
      vp9_setn(@above_ynnz, col * 2, w4 * 2, 0)
      vp9_setn(@above_uvnnz, col, w4, 0)
      vp9_setn(@above_uvnnz, @uvo + col, w4, 0)
      vp9_setn(@left_ynnz, @row7 * 2, h4 * 2, 0)
      vp9_setn(@left_uvnnz, @row7, h4, 0)
      vp9_setn(@left_uvnnz, 16 + @row7, h4, 0)
    if @intra == 1
      intra_recon(w4, h4)
    else
      inter_recon(w4, h4)
    if @lf_level > 0
      lvl = @lflvl[@seg_id * 8 + (@intra == 1 ? 0 : (@bref[0] + 1) * 2) + (@bmode[3] != 12 ? 1 : 0)]
      if lvl > 0
        xe = @cols - col
        xe = w4 if xe > w4
        ye = @rows - row
        ye = h4 if ye > h4
        skip_inter = (@intra == 0 && @skip == 1) ? 1 : 0
        sb = (row >> 3) * @sb_cols + (col >> 3)
        lv = @lf_lvl
        y = 0
        while y < h4
          x = 0
          while x < w4
            lv[sb * 64 + (@row7 + y) * 8 + @col7 + x] = lvl
            x += 1
          y += 1
        mask_edges(sb * 128, 0, 0, @row7, @col7, xe, ye, 0, 0, @tx, skip_inter)
        ce = 0
        ce = @cols & 7 if (@cols & 1) == 1 && col + w4 >= @cols
        re = 0
        re = @rows & 7 if (@rows & 1) == 1 && row + h4 >= @rows
        mask_edges(sb * 128 + 64, 1, 1, @row7, @col7, xe, ye, ce, re, @uvtx, skip_inter)
    0

  # Mode info (ffmpeg decode_mode equivalent): seg id, skip, intra, tx size,
  # modes, references, interpolation filter and motion vectors; then the
  # above/left contexts and the frame's mv/ref map.
  -> decode_mode(w4f, h4f)
    bs = @bs
    row = @row
    col = @col
    r7 = @row7
    max_tx = VP9_MAX_TX[bs]
    bw4 = w4f
    w4 = @cols - col
    w4 = bw4 if w4 > bw4
    bh4 = h4f
    h4 = @rows - row
    h4 = bh4 if h4 > bh4
    have_a = row > 0
    have_l = col > @tile_col_start
    kf = @keyframe == 1 || @intraonly == 1
    # segment id
    seg = 0
    if @seg_enabled == 0
      seg = 0
    elsif kf
      seg = @seg_update == 0 ? 0 : bd_tree(@segtree, @segprob, 0)
    elsif @seg_update == 0 || (@seg_temporal == 1 && bd(@segpred[@above_segpred[col] + @left_segpred[r7]]) == 1)
      if @errorres == 0 && @have_ref_seg == 1
        pred = 8
        rs = @ref_seg
        y = 0
        while y < h4
          b = (y + row) * 8 * @sb_cols + col
          x = 0
          while x < w4
            v = rs[b + x]
            pred = v if v < pred
            x += 1
          y += 1
        seg = pred
      else
        seg = 0
      vp9_setn(@above_segpred, col, w4, 1)
      vp9_setn(@left_segpred, r7, h4, 1)
    else
      seg = bd_tree(@segtree, @segprob, 0)
      vp9_setn(@above_segpred, col, w4, 0)
      vp9_setn(@left_segpred, r7, h4, 0)
    @seg_id = seg
    if @seg_enabled == 1 && (@seg_update == 1 || kf)
      cs = @cur_seg
      y = 0
      while y < bh4
        b = (row + y) * 8 * @sb_cols + col
        x = 0
        while x < bw4
          cs[b + x] = seg if row + y < @sb_rows * 8 && col + x < @sb_cols * 8
          x += 1
        y += 1
    fb = seg * 8
    skip = (@seg_enabled == 1 && @feat[fb + 6] == 1) ? 1 : 0
    if skip == 0
      c = @left_skip[r7] + @above_skip[col]
      skip = bd(@p[VP9P_SKIP + c])
      @counts[VC_SKIP + c * 2 + skip] += 1
    @skip = skip
    intra = 0
    if kf
      intra = 1
    elsif @seg_enabled == 1 && @feat[fb + 4] == 1
      intra = @feat[fb + 5] == 0 ? 1 : 0
    else
      c = 0
      if have_a && have_l
        c = @above_intra[col] + @left_intra[r7]
        c += 1 if c == 2
      elsif have_a
        c = 2 * @above_intra[col]
      elsif have_l
        c = 2 * @left_intra[r7]
      bit = bd(@p[VP9P_INTRA + c])
      @counts[VC_INTRA + c * 2 + bit] += 1
      intra = 1 - bit
    @intra = intra
    tx = 0
    if (intra == 1 || skip == 0) && @txmode == 4
      c = 0
      if have_a
        if have_l
          av = @above_skip[col] == 1 ? max_tx : @above_txfm[col]
          lv = @left_skip[r7] == 1 ? max_tx : @left_txfm[r7]
          c = (av + lv > max_tx) ? 1 : 0
        else
          c = @above_skip[col] == 1 ? 1 : ((@above_txfm[col] * 2 > max_tx) ? 1 : 0)
      elsif have_l
        c = @left_skip[r7] == 1 ? 1 : ((@left_txfm[r7] * 2 > max_tx) ? 1 : 0)
      else
        c = 1
      if max_tx == 3
        tx = bd(@p[VP9P_TX32 + c * 3])
        if tx == 1
          tx += bd(@p[VP9P_TX32 + c * 3 + 1])
          tx += bd(@p[VP9P_TX32 + c * 3 + 2]) if tx == 2
        @counts[VC_TX32 + c * 4 + tx] += 1
      elsif max_tx == 2
        tx = bd(@p[VP9P_TX16 + c * 2])
        tx += bd(@p[VP9P_TX16 + c * 2 + 1]) if tx == 1
        @counts[VC_TX16 + c * 3 + tx] += 1
      elsif max_tx == 1
        tx = bd(@p[VP9P_TX8 + c])
        @counts[VC_TX8 + c * 2 + tx] += 1
    else
      tx = max_tx < @txmode ? max_tx : @txmode
    @tx = tx
    m = @bmode
    filter_id = 0
    vref = 0
    @comp = 0
    if kf
      ao = col * 2
      lo = r7 * 2
      am = @above_mode
      lm = @left_mode
      if bs > 9
        m[0] = bd_tree(@itree, @kfy, (am[ao] * 10 + lm[lo]) * 9)
        am[ao] = m[0]
        if bs != 10
          m[1] = bd_tree(@itree, @kfy, (am[ao + 1] * 10 + m[0]) * 9)
          lm[lo] = m[1]
          am[ao + 1] = m[1]
        else
          m[1] = m[0]
          lm[lo] = m[1]
          am[ao + 1] = m[1]
        if bs != 11
          m[2] = bd_tree(@itree, @kfy, (am[ao] * 10 + lm[lo + 1]) * 9)
          am[ao] = m[2]
          if bs != 10
            m[3] = bd_tree(@itree, @kfy, (am[ao + 1] * 10 + m[2]) * 9)
            lm[lo + 1] = m[3]
            am[ao + 1] = m[3]
          else
            m[3] = m[2]
            lm[lo + 1] = m[3]
            am[ao + 1] = m[3]
        else
          m[2] = m[0]
          m[3] = m[1]
          lm[lo + 1] = m[3]
          am[ao + 1] = m[3]
      else
        m[0] = bd_tree(@itree, @kfy, (am[ao] * 10 + lm[lo]) * 9)
        m[1] = m[0]
        m[2] = m[0]
        m[3] = m[0]
        vp9_setn(am, ao, @bwh[bs * 2], m[0])
        vp9_setn(lm, lo, @bwh[bs * 2 + 1], m[0])
      @uvmode = bd_tree(@itree, @kfuv, m[3] * 9)
    elsif intra == 1
      if bs > 9
        m[0] = bd_tree(@itree, @p, VP9P_YMODE)
        @counts[VC_YMODE + m[0]] += 1
        if bs != 10
          m[1] = bd_tree(@itree, @p, VP9P_YMODE)
          @counts[VC_YMODE + m[1]] += 1
        else
          m[1] = m[0]
        if bs != 11
          m[2] = bd_tree(@itree, @p, VP9P_YMODE)
          @counts[VC_YMODE + m[2]] += 1
          if bs != 10
            m[3] = bd_tree(@itree, @p, VP9P_YMODE)
            @counts[VC_YMODE + m[3]] += 1
          else
            m[3] = m[2]
        else
          m[2] = m[0]
          m[3] = m[1]
      else
        sz = VP9_SIZE_GROUP[bs]
        m[0] = bd_tree(@itree, @p, VP9P_YMODE + sz * 9)
        m[1] = m[0]
        m[2] = m[0]
        m[3] = m[0]
        @counts[VC_YMODE + sz * 10 + m[3]] += 1
      @uvmode = bd_tree(@itree, @p, VP9P_UVMODE + m[3] * 9)
      @counts[VC_UVMODE + m[3] * 10 + @uvmode] += 1
    else
      read_refs(fb, have_a, have_l, r7, col)
      if bs <= 9
        if @seg_enabled == 1 && @feat[fb + 6] == 1
          m[0] = 12
        else
          c = @imctx[@above_mode[col + VP9_MODE_OFF[bs]] * 14 + @left_mode[r7 + VP9_MODE_OFF[bs]]]
          m[0] = bd_tree(@imtree, @p, VP9P_MVMODE + c * 3)
          @counts[VC_MVMODE + c * 4 + m[0] - 10] += 1
        m[1] = m[0]
        m[2] = m[0]
        m[3] = m[0]
      if @filtermode == 4
        c = 3
        if have_a && @above_mode[col] >= 10
          if have_l && @left_mode[r7] >= 10
            c = @above_filter[col] == @left_filter[r7] ? @left_filter[r7] : 3
          else
            c = @above_filter[col]
        elsif have_l && @left_mode[r7] >= 10
          c = @left_filter[r7]
        filter_id = bd_tree(@ftree, @p, VP9P_FILTER + c * 2)
        @counts[VC_FILTER + c * 3 + filter_id] += 1
        @filter = @flut[filter_id]
      else
        @filter = @filtermode
      if bs > 9
        c = @imctx[@above_mode[col] * 14 + @left_mode[r7]]
        m[0] = bd_tree(@imtree, @p, VP9P_MVMODE + c * 3)
        @counts[VC_MVMODE + c * 4 + m[0] - 10] += 1
        fill_mv(0, m[0], 0)
        if bs != 10
          m[1] = bd_tree(@imtree, @p, VP9P_MVMODE + c * 3)
          @counts[VC_MVMODE + c * 4 + m[1] - 10] += 1
          fill_mv(1, m[1], 1)
        else
          m[1] = m[0]
          vp9_copy(@bmv, 4, @bmv, 0, 4)
        if bs != 11
          m[2] = bd_tree(@imtree, @p, VP9P_MVMODE + c * 3)
          @counts[VC_MVMODE + c * 4 + m[2] - 10] += 1
          fill_mv(2, m[2], 2)
          if bs != 10
            m[3] = bd_tree(@imtree, @p, VP9P_MVMODE + c * 3)
            @counts[VC_MVMODE + c * 4 + m[3] - 10] += 1
            fill_mv(3, m[3], 3)
          else
            m[3] = m[2]
            vp9_copy(@bmv, 12, @bmv, 8, 4)
        else
          m[2] = m[0]
          vp9_copy(@bmv, 8, @bmv, 0, 4)
          m[3] = m[1]
          vp9_copy(@bmv, 12, @bmv, 4, 4)
      else
        fill_mv(0, m[0], -1)
        vp9_copy(@bmv, 4, @bmv, 0, 4)
        vp9_copy(@bmv, 8, @bmv, 0, 4)
        vp9_copy(@bmv, 12, @bmv, 0, 4)
      vref = @bref[@comp == 1 ? @signbias[@varcomp[0]] : 0]
    # contexts
    bwa = @bwh[26 + bs * 2]
    bha = @bwh[26 + bs * 2 + 1]
    vp9_setn(@above_skip, col, bwa, skip)
    vp9_setn(@above_txfm, col, bwa, tx)
    vp9_setn(@above_part, col, bwa, VP9_ABOVE_PCTX[bs])
    vp9_setn(@left_skip, r7, bha, skip)
    vp9_setn(@left_txfm, r7, bha, tx)
    vp9_setn(@left_part, r7, bha, VP9_LEFT_PCTX[bs])
    if !kf
      vp9_setn(@above_intra, col, bwa, intra)
      vp9_setn(@above_comp, col, bwa, @comp)
      vp9_setn(@above_mode, col, bwa, m[3])
      vp9_setn(@left_intra, r7, bha, intra)
      vp9_setn(@left_comp, r7, bha, @comp)
      vp9_setn(@left_mode, r7, bha, m[3])
      if intra == 0
        vp9_setn(@above_ref, col, bwa, vref)
        vp9_setn(@left_ref, r7, bha, vref)
        if @filtermode == 4
          vp9_setn(@above_filter, col, bwa, filter_id)
          vp9_setn(@left_filter, r7, bha, filter_id)
      # mv contexts: entries of 4 (mv0x, mv0y, mv1x, mv1y) per 4x4 column/row
      amv = @above_mv
      lmv = @left_mv
      if bs > 9
        vp9_copy(lmv, (r7 * 2) * 4, @bmv, 4, 4)
        vp9_copy(lmv, (r7 * 2 + 1) * 4, @bmv, 12, 4)
        vp9_copy(amv, (col * 2) * 4, @bmv, 8, 4)
        vp9_copy(amv, (col * 2 + 1) * 4, @bmv, 12, 4)
      else
        n = 0
        while n < w4 * 2
          vp9_copy(amv, (col * 2 + n) * 4, @bmv, 12, 4)
          n += 1
        n = 0
        while n < h4 * 2
          vp9_copy(lmv, (r7 * 2 + n) * 4, @bmv, 12, 4)
          n += 1
    # frame mv/ref map
    fm = @cur_mv
    y = 0
    while y < h4
      o = ((row + y) * @sb_cols * 8 + col) * 6
      x = 0
      while x < w4
        q = o + x * 6
        if intra == 1
          fm[q] = -1
          fm[q + 1] = -1
        elsif @comp == 1
          fm[q] = @bref[0]
          fm[q + 1] = @bref[1]
          fm[q + 2] = @bmv[12]
          fm[q + 3] = @bmv[13]
          fm[q + 4] = @bmv[14]
          fm[q + 5] = @bmv[15]
        else
          fm[q] = @bref[0]
          fm[q + 1] = -1
          fm[q + 2] = @bmv[12]
          fm[q + 3] = @bmv[13]
        x += 1
      y += 1
    0

  -> read_refs(fb, have_a, have_l, r7, col)
    if @seg_enabled == 1 && @feat[fb + 4] == 1
      @comp = 0
      @bref[0] = @feat[fb + 5] - 1
      return 0
    if @comppred != 2
      @comp = @comppred == 1 ? 1 : 0
    else
      c = 0
      ac = @above_comp[col]
      lc = @left_comp[r7]
      ai = @above_intra[col]
      li = @left_intra[r7]
      ar = @above_ref[col]
      lr = @left_ref[r7]
      fc = @fixcomp
      if have_a
        if have_l
          if ac == 1 && lc == 1
            c = 4
          elsif ac == 1
            c = 2 + ((li == 1 || lr == fc) ? 1 : 0)
          elsif lc == 1
            c = 2 + ((ai == 1 || ar == fc) ? 1 : 0)
          else
            c = ((ai == 0 && ar == fc) ? 1 : 0) ^ ((li == 0 && lr == fc) ? 1 : 0)
        else
          c = ac == 1 ? 3 : ((ai == 0 && ar == fc) ? 1 : 0)
      elsif have_l
        c = lc == 1 ? 3 : ((li == 0 && lr == fc) ? 1 : 0)
      else
        c = 1
      @comp = bd(@p[VP9P_COMP + c])
      @counts[VC_COMP + c * 2 + @comp] += 1
    ac = @above_comp[col]
    lc = @left_comp[r7]
    ai = @above_intra[col]
    li = @left_intra[r7]
    ar = @above_ref[col]
    lr = @left_ref[r7]
    fc = @fixcomp
    if @comp == 1
      fix_idx = @signbias[fc]
      var_idx = 1 - fix_idx
      @bref[fix_idx] = fc
      v1 = @varcomp[1]
      v0 = @varcomp[0]
      c = 0
      if have_a
        if have_l
          if ai == 1
            if li == 1
              c = 2
            else
              c = 1 + 2 * (lr != v1 ? 1 : 0)
          elsif li == 1
            c = 1 + 2 * (ar != v1 ? 1 : 0)
          else
            if lr == ar && ar == v1
              c = 0
            elsif lc == 0 && ac == 0
              if (ar == fc && lr == v0) || (lr == fc && ar == v0)
                c = 4
              else
                c = ar == lr ? 3 : 1
            elsif lc == 0
              if ar == v1 && lr != v1
                c = 1
              else
                c = (lr == v1 && ar != v1) ? 2 : 4
            elsif ac == 0
              if lr == v1 && ar != v1
                c = 1
              else
                c = (ar == v1 && lr != v1) ? 2 : 4
            else
              c = lr == ar ? 4 : 2
        else
          if ai == 1
            c = 2
          elsif ac == 1
            c = 4 * (ar != v1 ? 1 : 0)
          else
            c = 3 * (ar != v1 ? 1 : 0)
      elsif have_l
        if li == 1
          c = 2
        elsif lc == 1
          c = 4 * (lr != v1 ? 1 : 0)
        else
          c = 3 * (lr != v1 ? 1 : 0)
      else
        c = 2
      bit = bd(@p[VP9P_CREF + c])
      @bref[var_idx] = @varcomp[bit]
      @counts[VC_CREF + c * 2 + bit] += 1
    else
      c = 0
      if have_a && ai == 0
        if have_l && li == 0
          if lc == 1
            if ac == 1
              c = 1 + ((fc == 0 || lr == 0 || ar == 0) ? 1 : 0)
            else
              c = 3 * (ar == 0 ? 1 : 0) + ((fc == 0 || lr == 0) ? 1 : 0)
          elsif ac == 1
            c = 3 * (lr == 0 ? 1 : 0) + ((fc == 0 || ar == 0) ? 1 : 0)
          else
            c = 2 * (lr == 0 ? 1 : 0) + 2 * (ar == 0 ? 1 : 0)
        elsif ai == 1
          c = 2
        elsif ac == 1
          c = 1 + ((fc == 0 || ar == 0) ? 1 : 0)
        else
          c = 4 * (ar == 0 ? 1 : 0)
      elsif have_l && li == 0
        if lc == 1
          c = 1 + ((fc == 0 || lr == 0) ? 1 : 0)
        else
          c = 4 * (lr == 0 ? 1 : 0)
      else
        c = 2
      bit = bd(@p[VP9P_SREF + c * 2])
      @counts[VC_SREF + c * 4 + bit] += 1
      if bit == 0
        @bref[0] = 0
      else
        if have_a
          if have_l
            if li == 1
              if ai == 1
                c = 2
              elsif ac == 1
                c = 1 + 2 * ((fc == 1 || ar == 1) ? 1 : 0)
              elsif ar == 0
                c = 3
              else
                c = 4 * (ar == 1 ? 1 : 0)
            elsif ai == 1
              if li == 1
                c = 2
              elsif lc == 1
                c = 1 + 2 * ((fc == 1 || lr == 1) ? 1 : 0)
              elsif lr == 0
                c = 3
              else
                c = 4 * (lr == 1 ? 1 : 0)
            elsif ac == 1
              if lc == 1
                if lr == ar
                  c = 3 * ((fc == 1 || lr == 1) ? 1 : 0)
                else
                  c = 2
              elsif lr == 0
                c = 1 + 2 * ((fc == 1 || ar == 1) ? 1 : 0)
              else
                c = 3 * (lr == 1 ? 1 : 0) + ((fc == 1 || ar == 1) ? 1 : 0)
            elsif lc == 1
              if ar == 0
                c = 1 + 2 * ((fc == 1 || lr == 1) ? 1 : 0)
              else
                c = 3 * (ar == 1 ? 1 : 0) + ((fc == 1 || lr == 1) ? 1 : 0)
            elsif ar == 0
              if lr == 0
                c = 3
              else
                c = 4 * (lr == 1 ? 1 : 0)
            elsif lr == 0
              c = 4 * (ar == 1 ? 1 : 0)
            else
              c = 2 * (lr == 1 ? 1 : 0) + 2 * (ar == 1 ? 1 : 0)
          else
            if ai == 1 || (ac == 0 && ar == 0)
              c = 2
            elsif ac == 1
              c = 3 * ((fc == 1 || ar == 1) ? 1 : 0)
            else
              c = 4 * (ar == 1 ? 1 : 0)
        elsif have_l
          if li == 1 || (lc == 0 && lr == 0)
            c = 2
          elsif lc == 1
            c = 3 * ((fc == 1 || lr == 1) ? 1 : 0)
          else
            c = 4 * (lr == 1 ? 1 : 0)
        else
          c = 2
        bit = bd(@p[VP9P_SREF + c * 2 + 1])
        @counts[VC_SREF + c * 4 + 2 + bit] += 1
        @bref[0] = 1 + bit
    0

  # ------------------------------------------------------------------ mvs

  -> clamp_mv(x, y) (i64 i64) i64
    x = @min_mvx if x < @min_mvx
    x = @max_mvx if x > @max_mvx
    y = @min_mvy if y < @min_mvy
    y = @max_mvy if y > @max_mvy
    @pmv[0] = x
    @pmv[1] = y
    0

  # One RETURN_MV step; returns 1 when the search is done (result in @pmv).
  -> ret_mv(x, y) (i64 i64) i64
    if @fr_sb > 0
      if @fr_memsub_set == 0
        clamp_mv(x, y)
        if @pmv[0] != @fr_memx || @pmv[1] != @fr_memy
          return 1
        @fr_memsub_set = 1
        @fr_memsubx = x
        @fr_memsuby = y
        return 0
      elsif @fr_memsubx != x || @fr_memsuby != y
        clamp_mv(x, y)
        if @pmv[0] == @fr_memx && @pmv[1] == @fr_memy
          @pmv[0] = 0
          @pmv[1] = 0
        return 1
      return 0
    if @fr_idx == 0
      clamp_mv(x, y)
      return 1
    if @fr_mem_set == 0
      @fr_mem_set = 1
      @fr_memx = x
      @fr_memy = y
      return 0
    if x != @fr_memx || y != @fr_memy
      clamp_mv(x, y)
      return 1
    0

  -> ret_direct(x, y) (i64 i64) i64
    if @fr_idx == 0
      @pmv[0] = x
      @pmv[1] = y
      return 1
    if @fr_mem_set == 0
      @fr_mem_set = 1
      @fr_memx = x
      @fr_memy = y
      return 0
    if x != @fr_memx || y != @fr_memy
      @pmv[0] = x
      @pmv[1] = y
      return 1
    0

  -> find_ref_mvs(rf, z, idx, sb) (i64 i64 i64 i64) i64
    @fr_idx = idx
    @fr_sb = sb
    @fr_mem_set = 0
    @fr_memsub_set = 0
    row = @row
    col = @col
    fm = @cur_mv
    stride = @sb_cols * 8
    i = 0
    if sb >= 0
      if sb == 2 || sb == 1
        return 0 if ret_direct(@bmv[z * 2], @bmv[z * 2 + 1]) == 1
      elsif sb == 3
        return 0 if ret_direct(@bmv[8 + z * 2], @bmv[8 + z * 2 + 1]) == 1
        return 0 if ret_direct(@bmv[4 + z * 2], @bmv[4 + z * 2 + 1]) == 1
        return 0 if ret_direct(@bmv[z * 2], @bmv[z * 2 + 1]) == 1
      if row > 0
        q = ((row - 1) * stride + col) * 6
        e = (2 * col + (sb & 1)) * 4
        if fm[q] == rf
          return 0 if ret_mv(@above_mv[e], @above_mv[e + 1]) == 1
        elsif fm[q + 1] == rf
          return 0 if ret_mv(@above_mv[e + 2], @above_mv[e + 3]) == 1
      if col > @tile_col_start
        q = (row * stride + col - 1) * 6
        e = (2 * @row7 + (sb >> 1)) * 4
        if fm[q] == rf
          return 0 if ret_mv(@left_mv[e], @left_mv[e + 1]) == 1
        elsif fm[q + 1] == rf
          return 0 if ret_mv(@left_mv[e + 2], @left_mv[e + 3]) == 1
      i = 2
    ob = @bs * 16
    while i < 8
      cc = @mvref_off[ob + i * 2] + col
      rr = @mvref_off[ob + i * 2 + 1] + row
      if cc >= @tile_col_start && cc < @cols && rr >= 0 && rr < @rows
        q = (rr * stride + cc) * 6
        if fm[q] == rf
          return 0 if ret_mv(fm[q + 2], fm[q + 3]) == 1
        elsif fm[q + 1] == rf
          return 0 if ret_mv(fm[q + 4], fm[q + 5]) == 1
      i += 1
    pm = @prev_mv
    if @use_last_mvs == 1
      q = (row * stride + col) * 6
      if pm[q] == rf
        return 0 if ret_mv(pm[q + 2], pm[q + 3]) == 1
      elsif pm[q + 1] == rf
        return 0 if ret_mv(pm[q + 4], pm[q + 5]) == 1
    i = 0
    while i < 8
      cc = @mvref_off[ob + i * 2] + col
      rr = @mvref_off[ob + i * 2 + 1] + row
      if cc >= @tile_col_start && cc < @cols && rr >= 0 && rr < @rows
        q = (rr * stride + cc) * 6
        r0 = fm[q]
        r1 = fm[q + 1]
        if r0 != rf && r0 >= 0
          if @signbias[r0] != @signbias[rf]
            return 0 if ret_mv(0 - fm[q + 2], 0 - fm[q + 3]) == 1
          else
            return 0 if ret_mv(fm[q + 2], fm[q + 3]) == 1
        if r1 != rf && r1 >= 0 && (fm[q + 2] != fm[q + 4] || fm[q + 3] != fm[q + 5])
          if @signbias[r1] != @signbias[rf]
            return 0 if ret_mv(0 - fm[q + 4], 0 - fm[q + 5]) == 1
          else
            return 0 if ret_mv(fm[q + 4], fm[q + 5]) == 1
      i += 1
    if @use_last_mvs == 1
      q = (row * stride + col) * 6
      r0 = pm[q]
      r1 = pm[q + 1]
      if r0 != rf && r0 >= 0
        if @signbias[r0] != @signbias[rf]
          return 0 if ret_mv(0 - pm[q + 2], 0 - pm[q + 3]) == 1
        else
          return 0 if ret_mv(pm[q + 2], pm[q + 3]) == 1
      if r1 != rf && r1 >= 0 && (pm[q + 2] != pm[q + 4] || pm[q + 3] != pm[q + 5])
        if @signbias[r1] != @signbias[rf]
          return 0 if ret_mv(0 - pm[q + 4], 0 - pm[q + 5]) == 1
        else
          return 0 if ret_mv(pm[q + 4], pm[q + 5]) == 1
    clamp_mv(0, 0)
    0

  -> read_mv_component(idx, hp) (i64 i64) i64
    b = VP9P_MVC + idx * 33
    cb = VC_MVC + idx * 51
    sign = bd(@p[b])
    @counts[cb + sign] += 1
    c = bd_tree(@mvctree, @p, b + 1)
    @counts[cb + 2 + c] += 1
    n = 0 ## i64
    if c > 0
      m = 0 ## i64
      while m < c
        bit = bd(@p[b + 12 + m])
        n = n | (bit << m)
        @counts[cb + 15 + m * 2 + bit] += 1
        m += 1
      n = n << 3
      bit = bd_tree(@fptree, @p, b + 28)
      n = n | (bit << 1)
      @counts[cb + 43 + bit] += 1
      if hp == 1
        bit = bd(@p[b + 32])
        @counts[cb + 49 + bit] += 1
        n = n | bit
      else
        n = n | 1
        @counts[cb + 49 + 1] += 1
      n += 8 << c
    else
      n = bd(@p[b + 11])
      @counts[cb + 13 + n] += 1
      bit = bd_tree(@fptree, @p, b + 22 + n * 3)
      @counts[cb + 35 + n * 4 + bit] += 1
      n = (n << 3) | (bit << 1)
      if hp == 1
        bit = bd(@p[b + 31])
        @counts[cb + 47 + bit] += 1
        n = n | bit
      else
        n = n | 1
        @counts[cb + 47 + 1] += 1
    sign == 1 ? 0 - (n + 1) : n + 1

  # mv for sub-block sb (or -1 for the whole block) with inter mode
  # mode; writes @bmv[blk*4 ...].
  -> fill_mv(blk, mode, sb) (i64 i64 i64) i64
    o = blk * 4
    if mode == 12
      @bmv[o] = 0
      @bmv[o + 1] = 0
      @bmv[o + 2] = 0
      @bmv[o + 3] = 0
      return 0
    z = 0 ## i64
    while z < 1 + @comp
      find_ref_mvs(@bref[z], z, mode == 11 ? 1 : 0, mode == 13 ? -1 : sb)
      mx = @pmv[0]
      my = @pmv[1]
      hp = 0 ## i64
      if mode == 13 || sb == -1
        hp = (@hp == 1 && vp9_abs(mx) < 64 && vp9_abs(my) < 64) ? 1 : 0
        if hp == 0
          if (my & 1) == 1
            my = my < 0 ? my + 1 : my - 1
          if (mx & 1) == 1
            mx = mx < 0 ? mx + 1 : mx - 1
      if mode == 13
        j = bd_tree(@mvjtree, @p, VP9P_MVJ)
        @counts[VC_MVJ + j] += 1
        my += read_mv_component(0, hp) if j >= 2
        mx += read_mv_component(1, hp) if (j & 1) == 1
      @bmv[o + z * 2] = mx
      @bmv[o + z * 2 + 1] = my
      z += 1
    0

  # --------------------------------------------------------- coefficients

  # Tokens of one transform block into blk[bo ...] (dequantised, raster).
  # pb: coefficient prob base for (tx, plane, ref); cb: count base.
  -> decode_coeffs_b(blk, bo, nmax, is32, pb, nnz, so, bco, qdc, qac, cbc, cbe) (i16[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
    cp = @cp
    sc = @scans
    nb = @nbs
    cache = @cache
    par = @pareto
    cc = @ccoef
    ce = @ceob
    i = 0 ## i64
    band = 0 ## i64
    band_left = @bandc[bco]
    tp = pb + nnz * 3
    while true
      val = bd(cp[tp])
      ce[cbe + (band * 6 + nnz) * 2 + val] += 1
      break if val == 0
      skip_eob = true
      while skip_eob
        if bd(cp[tp + 1]) == 0
          cc[cbc + (band * 6 + nnz) * 3] += 1
          band_left -= 1
          if band_left == 0
            band += 1
            band_left = @bandc[bco + band]
          rc0 = sc[so + i]
          cache[rc0] = 0
          nnz = (1 + cache[nb[(so + i) * 2]] + cache[nb[(so + i) * 2 + 1]]) >> 1
          tp = pb + (band * 6 + nnz) * 3
          i += 1
          if i == nmax
            return i
        else
          skip_eob = false
      rc = sc[so + i]
      v = 0 ## i64
      if bd(cp[tp + 2]) == 0
        cc[cbc + (band * 6 + nnz) * 3 + 1] += 1
        v = 1
        cache[rc] = 1
      else
        cc[cbc + (band * 6 + nnz) * 3 + 2] += 1
        pp = cp[tp + 2] * 8
        # model probabilities p[3..10] = pareto8[p[2]]
        if bd(par[pp]) == 0
          if bd(par[pp + 1]) == 0
            v = 2
            cache[rc] = 2
          else
            v = 3 + bd(par[pp + 2])
            cache[rc] = 3
        elsif bd(par[pp + 3]) == 0
          cache[rc] = 4
          if bd(par[pp + 4]) == 0
            v = bd(159) + 5
          else
            v = (bd(165) << 1) + 7
            v += bd(145)
        else
          cache[rc] = 5
          if bd(par[pp + 5]) == 0
            if bd(par[pp + 6]) == 0
              v = 11 + (bd(173) << 2)
              v += bd(148) << 1
              v += bd(140)
            else
              v = 19 + (bd(176) << 3)
              v += bd(155) << 2
              v += bd(140) << 1
              v += bd(135)
          elsif bd(par[pp + 7]) == 0
            v = (bd(180) << 4) + 35
            v += bd(157) << 3
            v += bd(141) << 2
            v += bd(134) << 1
            v += bd(130)
          else
            v = 67
            v += bd(254) << 13
            v += bd(254) << 12
            v += bd(254) << 11
            v += bd(252) << 10
            v += bd(249) << 9
            v += bd(243) << 8
            v += bd(230) << 7
            v += bd(196) << 6
            v += bd(177) << 5
            v += bd(153) << 4
            v += bd(140) << 3
            v += bd(133) << 2
            v += bd(130) << 1
            v += bd(129)
      band_left -= 1
      if band_left == 0
        band += 1
        band_left = @bandc[bco + band]
      q = i == 0 ? qdc : qac
      sv = bd(128) == 1 ? 0 - v : v
      if is32 == 1
        blk[bo + rc] = (sv * q) / 2
      else
        blk[bo + rc] = sv * q
      nnz = (1 + cache[nb[(so + i) * 2]] + cache[nb[(so + i) * 2 + 1]]) >> 1
      tp = pb + (band * 6 + nnz) * 3
      i += 1
      break if i >= nmax
    i

  -> decode_coeffs(w4f, h4f) (i64 i64) i64
    row = @row
    col = @col
    tx = @tx
    ref = @intra == 1 ? 0 : 1
    w4 = w4f * 2
    h4 = h4f * 2
    end_x = 2 * (@cols - col)
    end_x = w4 if end_x > w4
    end_y = 2 * (@rows - row)
    end_y = h4 if end_y > h4
    qb = @seg_id * 4
    txi = @lossless == 1 ? 4 : tx
    total = 0 ## i64
    step = 1 << tx
    a = @above_ynnz
    l = @left_ynnz
    ao = col * 2
    lo = @row7 * 2
    pb = (tx * 2 * 2 + ref) * 108
    cbc = pb
    cbe = (tx * 2 * 2 + ref) * 72
    nmax = 16 * step * step
    is32 = tx == 3 ? 1 : 0
    bco = tx * 8
    # merge contexts for tx > 4x4
    if step > 1
      merge_ctx(l, lo, end_y, step)
      merge_ctx(a, ao, end_x, step)
    n = 0 ## i64
    y = 0 ## i64
    while y < end_y
      x = 0 ## i64
      while x < end_x
        mi = 0 ## i64
        mi = n if tx == 0 && @bs > 9
        txtp = @txtype[@bmode[mi]]
        so = 0 ## i64
        if txi == 4
          so = @scan_off[0]
        elsif tx == 3
          so = @scan_off[12]
        else
          so = @scan_off[tx * 4 + @scan_by_type[txtp]]
        ret = decode_coeffs_b(@blk, 16 * n, nmax, is32, pb, a[ao + x] + l[lo + y], so, bco, @qmul[qb], @qmul[qb + 1], cbc, cbe)
        nz = ret > 0 ? 1 : 0
        a[ao + x] = nz
        l[lo + y] = nz
        total = total | nz
        @eob[n] = ret
        x += step
        n += step * step
      y += step
    if step > 1
      splat_ctx(a, ao, end_x, step, end_x == w4)
      splat_ctx(l, lo, end_y, step, end_y == h4)
    # chroma
    uvtx = @uvtx
    ustep = 1 << uvtx
    pb = (uvtx * 2 * 2 + 2 + ref) * 108
    cbc = pb
    cbe = (uvtx * 2 * 2 + 2 + ref) * 72
    nmax = 16 * ustep * ustep
    is32 = uvtx == 3 ? 1 : 0
    bco = uvtx * 8
    w4 = w4 >> 1
    h4 = h4 >> 1
    end_x = end_x >> 1
    end_y = end_y >> 1
    so = @scan_off[uvtx == 3 ? 12 : uvtx * 4]
    so = @scan_off[0] if @lossless == 1
    pl = 0 ## i64
    while pl < 2
      a = @above_uvnnz
      ao = pl * @uvo + col
      l = @left_uvnnz
      lo = pl * 16 + @row7
      if ustep > 1
        merge_ctx(l, lo, end_y, ustep)
        merge_ctx(a, ao, end_x, ustep)
      n = 0
      y = 0
      while y < end_y
        x = 0
        while x < end_x
          ret = decode_coeffs_b(@uvblk, pl * 1024 + 16 * n, nmax, is32, pb, a[ao + x] + l[lo + y], so, bco, @qmul[qb + 2], @qmul[qb + 3], cbc, cbe)
          nz = ret > 0 ? 1 : 0
          a[ao + x] = nz
          l[lo + y] = nz
          total = total | nz
          @uveob[pl * 64 + n] = ret
          x += ustep
          n += ustep * ustep
        y += ustep
      if ustep > 1
        splat_ctx(a, ao, end_x, ustep, end_x == w4)
        splat_ctx(l, lo, end_y, ustep, end_y == h4)
      pl += 1
    total

  # la[n] = any(la[n...n+step]) for n < end step step.
  -> merge_ctx(la, o, e, step) (i64[] i64 i64 i64) i64
    n = 0 ## i64
    while n < e
      v = 0 ## i64
      k = 0 ## i64
      while k < step
        v = 1 if la[o + n + k] != 0
        k += 1
      la[o + n] = v
      n += step
    0

  -> splat_ctx(la, o, e, step, full) (i64[] i64 i64 i64 bool) i64
    n = 0 ## i64
    while n < e
      v = la[o + n]
      k = 1 ## i64
      lim = step - 1
      lim = e - n - 1 if !full && e - n - 1 < lim
      while k <= lim
        la[o + n + k] = v
        k += 1
      n += step
    0

  # ------------------------------------------------------- intra recon

  # Edge preparation (libvpx/ffmpeg check_intra_mode): returns the
  # predictor to use and fills @ia (top, [0] = top-left) and @il (left).
  -> intra_edges(mode, dst, stride, px, py, col, x, w, row, y, tx, ss) (i64 u8[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
    have_top = (row > 0 || y > 0) ? 1 : 0
    have_left = (col > @tile_col_start || x > 0) ? 1 : 0
    have_right = x < w - 1 ? 1 : 0
    m = mode
    if mode == 0
      m = have_top == 1 ? 0 : 13
    elsif mode == 1
      m = have_left == 1 ? 1 : 14
    elsif mode == 2
      if have_left == 1
        m = have_top == 1 ? 2 : 10
      else
        m = have_top == 1 ? 11 : 12
    elsif mode == 3
      m = have_top == 1 ? 3 : 13
    elsif mode == 7
      m = have_top == 1 ? 7 : 13
    elsif mode == 8
      m = have_left == 1 ? 8 : 14
    elsif mode == 9
      if have_left == 1
        m = have_top == 1 ? 9 : 1
      else
        m = have_top == 1 ? 0 : 14
    nl = 0 ## i64
    nt = 0 ## i64
    ntl = 0 ## i64
    ntr = 0 ## i64
    inv = 0 ## i64
    if m == 0 || m == 11
      nt = 1
    elsif m == 1 || m == 10
      nl = 1
    elsif m == 2
      nt = 1
      nl = 1
    elsif m == 3 || m == 7
      nt = 1
      ntr = 1
    elsif m == 4 || m == 5 || m == 6 || m == 9
      nl = 1
      nt = 1
      ntl = 1
    elsif m == 8
      nl = 1
      inv = 1
    a = @ia
    l = @il
    n = 4 << tx
    if nt == 1
      nhave = (((@cols - col) << (1 - ss)) - x) * 4
      ntrn = (tx == 0 && ntr == 1 && have_right == 1) ? 4 : 0
      t = (py - 1) * stride + px
      if have_top == 1 && (ntl == 0 || have_left == 1) && (tx != 0 || ntr == 0 || have_right == 1) && n + ntrn <= nhave
        k = 0 ## i64
        while k < n + ntrn
          a[1 + k] = dst[t + k]
          k += 1
        a[0] = dst[t - 1] if have_left == 1
      else
        if have_top == 1
          if n <= nhave
            k = 0
            while k < n
              a[1 + k] = dst[t + k]
              k += 1
          else
            k = 0
            while k < nhave
              a[1 + k] = dst[t + k]
              k += 1
            while k < n
              a[1 + k] = a[nhave]
              k += 1
        else
          k = 0
          while k < n
            a[1 + k] = 127
            k += 1
        if ntl == 1
          if have_left == 1 && have_top == 1
            a[0] = dst[t - 1]
          else
            a[0] = have_top == 1 ? 129 : 127
        if tx == 0 && ntr == 1
          if have_top == 1 && have_right == 1 && n + ntrn <= nhave
            k = 4
            while k < 8
              a[1 + k] = dst[t + k]
              k += 1
          else
            k = 4
            while k < 8
              a[1 + k] = a[4]
              k += 1
    if nl == 1
      if have_left == 1
        nhave = (((@rows - row) << (1 - ss)) - y) * 4
        lp = py * stride + px - 1
        if inv == 1
          k = 0
          lim = n < nhave ? n : nhave
          while k < lim
            l[k] = dst[lp + k * stride]
            k += 1
          while k < n
            l[k] = l[nhave - 1]
            k += 1
        else
          if n <= nhave
            k = 0
            while k < n
              l[n - 1 - k] = dst[lp + k * stride]
              k += 1
          else
            k = 0
            while k < nhave
              l[n - 1 - k] = dst[lp + k * stride]
              k += 1
            k = 0
            while k < n - nhave
              l[k] = l[n - nhave]
              k += 1
      else
        k = 0
        while k < n
          l[k] = 129
          k += 1
    m

  -> tx_kinds(txtp) (i64) i64
    ka = (txtp == 1 || txtp == 3) ? 1 : 0
    kb = (txtp == 2 || txtp == 3) ? 1 : 0
    ka | (kb << 1)

  -> itx(dst, d, stride, blk, bo, tx, txtp, eob) (u8[] i64 i64 i16[] i64 i64 i64 i64) i64
    if @lossless == 1
      vp9_itxfm_add(dst, d, stride, blk, bo, 4, 2, 2, 0, eob, @tx_tmp, @tx_out)
      return 0
    n = 4 << tx
    bits = tx == 0 ? 4 : (tx == 1 ? 5 : 6)
    kk = tx == 3 ? 0 : tx_kinds(txtp)
    vp9_itxfm_add(dst, d, stride, blk, bo, n, kk & 1, kk >> 1, bits, eob, @tx_tmp, @tx_out)
    0

  -> intra_recon(w4f, h4f)
    row = @row
    col = @col
    tx = @tx
    w4 = w4f * 2
    h4 = h4f * 2
    step = 1 << tx
    end_x = 2 * (@cols - col)
    end_x = w4 if end_x > w4
    end_y = 2 * (@rows - row)
    end_y = h4 if end_y > h4
    ys = @ys
    dst = @cur_y
    n = 0
    y = 0
    while y < end_y
      x = 0
      while x < end_x
        mi = 0
        mi = y * 2 + x if @bs > 9 && tx == 0
        mode = @bmode[mi]
        txtp = @txtype[mode]
        eob = @skip == 1 ? 0 : @eob[n]
        px = col * 8 + x * 4
        py = row * 8 + y * 4
        pm = intra_edges(mode, dst, ys, px, py, col, x, w4, row, y, tx, 0)
        vp9_ipred(dst, py * ys + px, ys, 4 << tx, pm, @il, @ia, @iv)
        itx(dst, py * ys + px, ys, @blk, 16 * n, tx, txtp, eob) if eob > 0
        x += step
        n += step * step
      y += step
    # chroma
    uvtx = @uvtx
    us = 1 << uvtx
    w4 = w4 >> 1
    end_x = end_x >> 1
    end_y = end_y >> 1
    uvs = @uvs
    pl = 0
    while pl < 2
      dst = pl == 0 ? @cur_u : @cur_v
      n = 0
      y = 0
      while y < end_y
        x = 0
        while x < end_x
          eob = @skip == 1 ? 0 : @uveob[pl * 64 + n]
          px = col * 4 + x * 4
          py = row * 4 + y * 4
          pm = intra_edges(@uvmode, dst, uvs, px, py, col, x, w4, row, y, uvtx, 1)
          vp9_ipred(dst, py * uvs + px, uvs, 4 << uvtx, pm, @il, @ia, @iv)
          itx(dst, py * uvs + px, uvs, @uvblk, pl * 1024 + 16 * n, uvtx, 0, eob) if eob > 0
          x += us
          n += us * us
        y += us
      pl += 1
    0

  # ------------------------------------------------------- inter recon

  -> mc_luma(rf, py, px, mx, my, bw, bh, avg) (VP9Frame i64 i64 i64 i64 i64 i64 i64) i64
    y = py + (my >> 3)
    x = px + (mx >> 3)
    fx = (mx & 7) << 1
    fy = (my & 7) << 1
    w = rf.w
    h = rf.h
    src = rf.y ## u8[]
    ss = rf.ys
    so = y * ss + x
    if x < 3 || y < 3 || x + bw + 4 > w || y + bh + 5 > h
      vp9_emu_edge(src, ss, w, h, x, y, bw, bh, @emu)
      src = @emu
      ss = 80
      so = 3 * 80 + 3
    flt = @filter
    vp9_mc(@cur_y, (py * @ys) + px, @ys, src, so, ss, bw, bh, fx, fy, @filters, (flt == 3 ? 0 : flt) * 128, flt == 3 ? 1 : 0, avg, @mc_tmp)
    0

  -> mc_chroma(rf, py, px, mx, my, bw, bh, avg) (VP9Frame i64 i64 i64 i64 i64 i64 i64) i64
    y = py + (my >> 4)
    x = px + (mx >> 4)
    fx = mx & 15
    fy = my & 15
    w = (rf.w + 1) >> 1
    h = (rf.h + 1) >> 1
    ss = rf.uvs
    flt = @filter
    pl = 0 ## i64
    while pl < 2
      src = (pl == 0 ? rf.u : rf.v) ## u8[]
      sst = ss
      so = y * ss + x
      if x < 3 || y < 3 || x + bw + 4 > w || y + bh + 5 > h
        vp9_emu_edge(src, ss, w, h, x, y, bw, bh, @emu)
        src = @emu
        sst = 80
        so = 3 * 80 + 3
      dst = (pl == 0 ? @cur_u : @cur_v) ## u8[]
      vp9_mc(dst, py * @uvs + px, @uvs, src, so, sst, bw, bh, fx, fy, @filters, (flt == 3 ? 0 : flt) * 128, flt == 3 ? 1 : 0, avg, @mc_tmp)
      pl += 1
    0

  -> mc_luma_s(rf, ri, py, px, mx0, my0, ppx, ppy, pw, ph, bw, bh, avg) (VP9Frame i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
    if rf.w == @w && rf.h == @h
      mc_luma(rf, py, px, mx0, my0, bw, bh, avg)
      return 0
    sx = @mvscale[ri * 2]
    sy = @mvscale[ri * 2 + 1]
    lo = 0 - (px + pw - ppx + 4) * 8
    hi = (@cols * 8 - px + ppx + 3) * 8
    mvx = mx0 < lo ? lo : (mx0 > hi ? hi : mx0)
    lo = 0 - (py + ph - ppy + 4) * 8
    hi = (@rows * 8 - py + ppy + 3) * 8
    mvy = my0 < lo ? lo : (my0 > hi ? hi : my0)
    mx = ((mvx * 2 * sx) >> 14) + ((px * 16 * sx) >> 14)
    my = ((mvy * 2 * sy) >> 14) + ((py * 16 * sy) >> 14)
    y = my >> 4
    x = mx >> 4
    mx = mx & 15
    my = my & 15
    stx = @mvstep[ri * 2]
    sty = @mvstep[ri * 2 + 1]
    rbw = ((bw - 1) * stx + mx) >> 4
    rbh = ((bh - 1) * sty + my) >> 4
    w = rf.w
    h = rf.h
    src = rf.y ## u8[]
    ss = rf.ys
    so = y * ss + x
    if x < 3 || y < 3 || x + 4 >= w - rbw || y + 5 >= h - rbh
      vp9_emu_edge288(src, ss, w, h, x, y, rbw + 1, rbh + 1, @emu288)
      src = @emu288
      ss = 288
      so = 3 * 288 + 3
    flt = @filter
    vp9_mc_scaled(@cur_y, py * @ys + px, @ys, src, so, ss, bw, bh, mx, my, stx, sty, @filters, (flt == 3 ? 0 : flt) * 128, flt == 3 ? 1 : 0, avg, @mc_tmp2)
    0

  -> mc_chroma_s(rf, ri, py, px, mx0, my0, ppx, ppy, pw, ph, bw, bh, avg) (VP9Frame i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
    if rf.w == @w && rf.h == @h
      mc_chroma(rf, py, px, mx0, my0, bw, bh, avg)
      return 0
    sx = @mvscale[ri * 2]
    sy = @mvscale[ri * 2 + 1]
    lo = 0 - (px + pw - ppx + 4) * 16
    hi = (@cols * 4 - px + ppx + 3) * 16
    mvx = mx0 < lo ? lo : (mx0 > hi ? hi : mx0)
    lo = 0 - (py + ph - ppy + 4) * 16
    hi = (@rows * 4 - py + ppy + 3) * 16
    mvy = my0 < lo ? lo : (my0 > hi ? hi : my0)
    mx = ((mvx * sx) >> 14) + (((px * 16 * sx) >> 14) & (0 - 16)) + (((px * 32 * sx) >> 14) & 15)
    my = ((mvy * sy) >> 14) + (((py * 16 * sy) >> 14) & (0 - 16)) + (((py * 32 * sy) >> 14) & 15)
    y = my >> 4
    x = mx >> 4
    mx = mx & 15
    my = my & 15
    stx = @mvstep[ri * 2]
    sty = @mvstep[ri * 2 + 1]
    rbw = ((bw - 1) * stx + mx) >> 4
    rbh = ((bh - 1) * sty + my) >> 4
    w = (rf.w + 1) >> 1
    h = (rf.h + 1) >> 1
    flt = @filter
    pl = 0 ## i64
    while pl < 2
      src = (pl == 0 ? rf.u : rf.v) ## u8[]
      ss = rf.uvs
      so = y * ss + x
      if x < 3 || y < 3 || x + 4 >= w - rbw || y + 5 >= h - rbh
        vp9_emu_edge288(src, ss, w, h, x, y, rbw + 1, rbh + 1, @emu288)
        src = @emu288
        ss = 288
        so = 3 * 288 + 3
      dst = (pl == 0 ? @cur_u : @cur_v) ## u8[]
      vp9_mc_scaled(dst, py * @uvs + px, @uvs, src, so, ss, bw, bh, mx, my, stx, sty, @filters, (flt == 3 ? 0 : flt) * 128, flt == 3 ? 1 : 0, avg, @mc_tmp2)
      pl += 1
    0

  -> inter_recon(w4f, h4f)
    row = @row
    col = @col
    bs = @bs
    scaled = false
    z = 0
    while z < 1 + @comp
      raise VP9Error.new("vp9: reference frame has invalid dimensions") if @mvscale[@bref[z] * 2] == -1
      scaled = true if @mvscale[@bref[z] * 2] != 0
      z += 1
    z = 0
    while z < 1 + @comp && scaled
      ri = @bref[z]
      rf = @refs[@refidx[ri]]
      avg = z
      o = z * 2
      if bs > 9
        mc_luma_s(rf, ri, row * 8, col * 8, @bmv[o], @bmv[o + 1], 0, 0, 8, 8, 4, 4, avg)
        mc_luma_s(rf, ri, row * 8, col * 8 + 4, @bmv[4 + o], @bmv[4 + o + 1], 4, 0, 8, 8, 4, 4, avg)
        mc_luma_s(rf, ri, row * 8 + 4, col * 8, @bmv[8 + o], @bmv[8 + o + 1], 0, 4, 8, 8, 4, 4, avg)
        mc_luma_s(rf, ri, row * 8 + 4, col * 8 + 4, @bmv[12 + o], @bmv[12 + o + 1], 4, 4, 8, 8, 4, 4, avg)
        ux = vp9_rdiv(@bmv[o] + @bmv[4 + o] + @bmv[8 + o] + @bmv[12 + o], 4)
        uy = vp9_rdiv(@bmv[o + 1] + @bmv[4 + o + 1] + @bmv[8 + o + 1] + @bmv[12 + o + 1], 4)
        mc_chroma_s(rf, ri, row * 4, col * 4, ux, uy, 0, 0, 4, 4, 4, 4, avg)
      else
        bw = @bwh[bs * 2] * 4
        bh = @bwh[bs * 2 + 1] * 4
        ubw = @bwh[26 + bs * 2] * 4
        ubh = @bwh[26 + bs * 2 + 1] * 4
        mc_luma_s(rf, ri, row * 8, col * 8, @bmv[o], @bmv[o + 1], 0, 0, bw, bh, bw, bh, avg)
        mc_chroma_s(rf, ri, row * 4, col * 4, @bmv[o], @bmv[o + 1], 0, 0, ubw, ubh, ubw, ubh, avg)
      z += 1
    z = 0
    while z < 1 + @comp && !scaled
      rf = @refs[@refidx[@bref[z]]]
      avg = z
      o = z * 2
      if bs > 9
        if bs == 10
          mc_luma(rf, row * 8, col * 8, @bmv[o], @bmv[o + 1], 8, 4, avg)
          mc_luma(rf, row * 8 + 4, col * 8, @bmv[8 + o], @bmv[8 + o + 1], 8, 4, avg)
          ux = vp9_rdiv(@bmv[o] + @bmv[8 + o], 2)
          uy = vp9_rdiv(@bmv[o + 1] + @bmv[8 + o + 1], 2)
          mc_chroma(rf, row * 4, col * 4, ux, uy, 4, 4, avg)
        elsif bs == 11
          mc_luma(rf, row * 8, col * 8, @bmv[o], @bmv[o + 1], 4, 8, avg)
          mc_luma(rf, row * 8, col * 8 + 4, @bmv[4 + o], @bmv[4 + o + 1], 4, 8, avg)
          ux = vp9_rdiv(@bmv[o] + @bmv[4 + o], 2)
          uy = vp9_rdiv(@bmv[o + 1] + @bmv[4 + o + 1], 2)
          mc_chroma(rf, row * 4, col * 4, ux, uy, 4, 4, avg)
        else
          mc_luma(rf, row * 8, col * 8, @bmv[o], @bmv[o + 1], 4, 4, avg)
          mc_luma(rf, row * 8, col * 8 + 4, @bmv[4 + o], @bmv[4 + o + 1], 4, 4, avg)
          mc_luma(rf, row * 8 + 4, col * 8, @bmv[8 + o], @bmv[8 + o + 1], 4, 4, avg)
          mc_luma(rf, row * 8 + 4, col * 8 + 4, @bmv[12 + o], @bmv[12 + o + 1], 4, 4, avg)
          ux = vp9_rdiv(@bmv[o] + @bmv[4 + o] + @bmv[8 + o] + @bmv[12 + o], 4)
          uy = vp9_rdiv(@bmv[o + 1] + @bmv[4 + o + 1] + @bmv[8 + o + 1] + @bmv[12 + o + 1], 4)
          mc_chroma(rf, row * 4, col * 4, ux, uy, 4, 4, avg)
      else
        bw = @bwh[bs * 2] * 4
        bh = @bwh[bs * 2 + 1] * 4
        ubw = @bwh[26 + bs * 2] * 4
        ubh = @bwh[26 + bs * 2 + 1] * 4
        mc_luma(rf, row * 8, col * 8, @bmv[o], @bmv[o + 1], bw, bh, avg)
        mc_chroma(rf, row * 4, col * 4, @bmv[o], @bmv[o + 1], ubw, ubh, avg)
      z += 1
    return 0 if @skip == 1
    tx = @tx
    w4 = w4f * 2
    h4 = h4f * 2
    step = 1 << tx
    end_x = 2 * (@cols - col)
    end_x = w4 if end_x > w4
    end_y = 2 * (@rows - row)
    end_y = h4 if end_y > h4
    ys = @ys
    n = 0
    y = 0
    while y < end_y
      x = 0
      while x < end_x
        e = @eob[n]
        itx(@cur_y, (row * 8 + y * 4) * ys + col * 8 + x * 4, ys, @blk, 16 * n, tx, 0, e) if e > 0
        x += step
        n += step * step
      y += step
    uvtx = @uvtx
    us = 1 << uvtx
    end_x = end_x >> 1
    end_y = end_y >> 1
    uvs = @uvs
    pl = 0
    while pl < 2
      dst = pl == 0 ? @cur_u : @cur_v
      n = 0
      y = 0
      while y < end_y
        x = 0
        while x < end_x
          e = @uveob[pl * 64 + n]
          itx(dst, (row * 4 + y * 4) * uvs + col * 4 + x * 4, uvs, @uvblk, pl * 1024 + 16 * n, uvtx, 0, e) if e > 0
          x += us
          n += us * us
        y += us
      pl += 1
    0

  # ---------------------------------------------------------- loop filter

  # Edge masks for one block (libvpx/ffmpeg mask_edges). mb: mask base for
  # this SB and plane type; [dir][y][k] at mb + (dir*8 + y)*4 + k.
  -> mask_edges(mb, ss_h, ss_v, r7, c7, w, h, col_end, row_end, tx, skip_inter) (i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64) i64
    m = @lf_mask
    wfc = ss_h == 1 ? 0x01 : 0x11
    wfr = ss_v == 1 ? 0x07 : 0x03
    if tx == 0 && (ss_v == 1 || ss_h == 1)
      if h == ss_v
        return 0 if (r7 & 1) == 1
        h += 1 if row_end == 0
      if w == ss_h
        return 0 if (c7 & 1) == 1
        w += 1 if col_end == 0
    if tx == 0 && skip_inter == 0
      t = 1 << c7
      m_col = (t << w) - t
      m_row_8 = m_col & wfc
      m_row_4 = m_col - m_row_8
      y = r7
      while y < h + r7
        cmi = 2 - ((y & wfr) == 0 ? 1 : 0)
        m[mb + y * 4 + 1] = m[mb + y * 4 + 1] | m_row_8
        m[mb + y * 4 + 2] = m[mb + y * 4 + 2] | m_row_4
        if (ss_h & ss_v) == 1 && (col_end & 1) == 1 && (y & 1) == 1
          m[mb + 32 + y * 4 + cmi] = m[mb + 32 + y * 4 + cmi] | ((t << (w - 1)) - t)
        else
          m[mb + 32 + y * 4 + cmi] = m[mb + 32 + y * 4 + cmi] | m_col
        if ss_h == 0
          m[mb + y * 4 + 3] = m[mb + y * 4 + 3] | m_col
        if ss_v == 0
          if ss_h == 1 && (col_end & 1) == 1
            m[mb + 32 + y * 4 + 3] = m[mb + 32 + y * 4 + 3] | ((t << (w - 1)) - t)
          else
            m[mb + 32 + y * 4 + 3] = m[mb + 32 + y * 4 + 3] | m_col
        y += 1
    else
      t = 1 << c7
      m_col = (t << w) - t
      if skip_inter == 0
        mask_id = tx == 1 ? 1 : 0
        l2 = tx + ss_h - 1
        mk = l2 == 0 ? 0xff : (l2 == 1 ? 0x55 : (l2 == 2 ? 0x11 : 0x01))
        m_row = m_col & mk
        if ss_h == 1 && tx > 1 && (w ^ (w - 1)) == 1
          m_row_16 = ((t << (w - 1)) - t) & mk
          m_row_8 = m_row - m_row_16
          y = r7
          while y < h + r7
            m[mb + y * 4] = m[mb + y * 4] | m_row_16
            m[mb + y * 4 + 1] = m[mb + y * 4 + 1] | m_row_8
            y += 1
        else
          y = r7
          while y < h + r7
            m[mb + y * 4 + mask_id] = m[mb + y * 4 + mask_id] | m_row
            y += 1
        l2 = tx + ss_v - 1
        step1d = 1 << l2
        if ss_v == 1 && tx > 1 && (h ^ (h - 1)) == 1
          y = r7
          while y < h + r7 - 1
            m[mb + 32 + y * 4] = m[mb + 32 + y * 4] | m_col
            y += step1d
          if y - r7 == h - 1
            m[mb + 32 + y * 4 + 1] = m[mb + 32 + y * 4 + 1] | m_col
        else
          y = r7
          while y < h + r7
            m[mb + 32 + y * 4 + mask_id] = m[mb + 32 + y * 4 + mask_id] | m_col
            y += step1d
      elsif tx != 0
        mask_id = (tx == 1 || h == ss_v) ? 1 : 0
        m[mb + 32 + r7 * 4 + mask_id] = m[mb + 32 + r7 * 4 + mask_id] | m_col
        mask_id = (tx == 1 || w == ss_h) ? 1 : 0
        y = r7
        while y < h + r7
          m[mb + y * 4 + mask_id] = m[mb + y * 4 + mask_id] | t
          y += 1
      else
        t8 = t & wfc
        t4 = t - t8
        y = r7
        while y < h + r7
          m[mb + y * 4 + 2] = m[mb + y * 4 + 2] | t4
          m[mb + y * 4 + 1] = m[mb + y * 4 + 1] | t8
          y += 1
        k = 2 - ((r7 & wfr) == 0 ? 1 : 0)
        m[mb + 32 + r7 * 4 + k] = m[mb + 32 + r7 * 4 + k] | m_col
    0

  -> lf8(dst, p, sa, sb, lvl, wd) (u8[] i64 i64 i64 i64 i64) i64
    vp9_lf(dst, p, sa, sb, @mblim_lut[lvl], @lim_lut[lvl], lvl >> 4, wd)
    0

  # filter_plane_cols: vertical edges. lb: level base, mb: mask base (dir 0)
  -> lf_cols(col, ss_h, ss_v, lb, mb, dst, d0, ls) (i64 i64 i64 i64 i64 u8[] i64 i64) i64
    m = @lf_mask
    lv = @lf_lvl
    y = 0 ## i64
    d = d0
    lo = lb
    while y < 8
      h1 = mb + y * 4
      h2 = mb + (y + 1 + ss_v) * 4
      hm1 = m[h1] | m[h1 + 1] | m[h1 + 2]
      hm13 = m[h1 + 3]
      hm2 = m[h2 + 1] | m[h2 + 2]
      hm23 = m[h2 + 3]
      hm = hm1 | hm2 | hm13 | hm23
      x = 1 ## i64
      ptr = d
      l = lo
      while (hm & (0 - x)) != 0
        if col != 0 || x > 1
          if (hm1 & x) != 0
            lvl = lv[l]
            if (m[h1] & x) != 0
              if (m[h2] & x) != 0
                lf8(dst, ptr, ls, 1, lvl, 16)
                lf8(dst, ptr + 8 * ls, ls, 1, lvl, 16)
              else
                lf8(dst, ptr, ls, 1, lvl, 16)
            elsif (hm2 & x) != 0
              l2 = lv[l + (8 << ss_v)]
              lf8(dst, ptr, ls, 1, lvl, (m[h1 + 1] & x) != 0 ? 8 : 4)
              lf8(dst, ptr + 8 * ls, ls, 1, l2, (m[h2 + 1] & x) != 0 ? 8 : 4)
            else
              lf8(dst, ptr, ls, 1, lvl, (m[h1 + 1] & x) != 0 ? 8 : 4)
          elsif (hm2 & x) != 0
            l2 = lv[l + (8 << ss_v)]
            lf8(dst, ptr + 8 * ls, ls, 1, l2, (m[h2 + 1] & x) != 0 ? 8 : 4)
        if ss_h == 1
          l += 2 if (x & 0xAA) != 0
        else
          if (hm13 & x) != 0
            lvl = lv[l]
            lf8(dst, ptr + 4, ls, 1, lvl, 4)
            if (hm23 & x) != 0
              lf8(dst, ptr + 8 * ls + 4, ls, 1, lv[l + (8 << ss_v)], 4)
          elsif (hm23 & x) != 0
            lf8(dst, ptr + 8 * ls + 4, ls, 1, lv[l + (8 << ss_v)], 4)
          l += 1
        x = x << 1
        ptr += 8 >> ss_h
      y += 2 << ss_v
      d += 16 * ls
      lo += 16 << ss_v
    0

  -> lf_rows(row, ss_h, ss_v, lb, mb, dst, d0, ls) (i64 i64 i64 i64 i64 u8[] i64 i64) i64
    m = @lf_mask
    lv = @lf_lvl
    y = 0 ## i64
    d = d0
    lo = lb
    while y < 8
      vb = mb + y * 4
      vm = m[vb] | m[vb + 1] | m[vb + 2]
      vm3 = m[vb + 3]
      x = 1 ## i64
      ptr = d
      l = lo
      sh = 1 + ss_h
      while (vm & (0 - x)) != 0
        if row != 0 || y != 0
          if (vm & x) != 0
            lvl = lv[l]
            if (m[vb] & x) != 0
              if (m[vb] & (x << sh)) != 0
                lf8(dst, ptr, 1, ls, lvl, 16)
                lf8(dst, ptr + 8, 1, ls, lvl, 16)
              else
                lf8(dst, ptr, 1, ls, lvl, 16)
            elsif (vm & (x << sh)) != 0
              l2 = lv[l + sh]
              lf8(dst, ptr, 1, ls, lvl, (m[vb + 1] & x) != 0 ? 8 : 4)
              lf8(dst, ptr + 8, 1, ls, l2, (m[vb + 1] & (x << sh)) != 0 ? 8 : 4)
            else
              lf8(dst, ptr, 1, ls, lvl, (m[vb + 1] & x) != 0 ? 8 : 4)
          elsif (vm & (x << sh)) != 0
            l2 = lv[l + sh]
            lf8(dst, ptr + 8, 1, ls, l2, (m[vb + 1] & (x << sh)) != 0 ? 8 : 4)
        if ss_v == 0
          if (vm3 & x) != 0
            lf8(dst, ptr + ls * 4, 1, ls, lv[l], 4)
            if (vm3 & (x << sh)) != 0
              lf8(dst, ptr + ls * 4 + 8, 1, ls, lv[l + sh], 4)
          elsif (vm3 & (x << sh)) != 0
            lf8(dst, ptr + ls * 4 + 8, 1, ls, lv[l + sh], 4)
        x = x << (2 << ss_h)
        ptr += 16
        l += 2 << ss_h
      if ss_v == 1
        lo += 16 if (y & 1) == 1
      else
        lo += 8
      y += 1
      d += (8 * ls) >> ss_v
    0

  -> lf_worker
    sr = 0
    while sr < @sb_rows
      need = sr + 2
      need = @sb_rows if need > @sb_rows
      while @lf_prog.load < need
        0
      lf_sb_row(sr)
      sr += 1
    0

  -> lf_sb_row(sr)
    sc = 0
    while sc < @sb_cols
      sb = sr * @sb_cols + sc
      row = sr * 8
      col = sc * 8
      yo = (row * 8) * @ys + col * 8
      uo = (row * 4) * @uvs + col * 4
      lf_cols(col, 0, 0, sb * 64, sb * 128, @cur_y, yo, @ys)
      lf_rows(row, 0, 0, sb * 64, sb * 128 + 32, @cur_y, yo, @ys)
      lf_cols(col, 1, 1, sb * 64, sb * 128 + 64, @cur_u, uo, @uvs)
      lf_rows(row, 1, 1, sb * 64, sb * 128 + 96, @cur_u, uo, @uvs)
      lf_cols(col, 1, 1, sb * 64, sb * 128 + 64, @cur_v, uo, @uvs)
      lf_rows(row, 1, 1, sb * 64, sb * 128 + 96, @cur_v, uo, @uvs)
      sc += 1
    0

  -> loop_filter_frame
    sr = 0
    while sr < @sb_rows
      sc = 0
      while sc < @sb_cols
        sb = sr * @sb_cols + sc
        row = sr * 8
        col = sc * 8
        yo = (row * 8) * @ys + col * 8
        uo = (row * 4) * @uvs + col * 4
        lf_cols(col, 0, 0, sb * 64, sb * 128, @cur_y, yo, @ys)
        lf_rows(row, 0, 0, sb * 64, sb * 128 + 32, @cur_y, yo, @ys)
        lf_cols(col, 1, 1, sb * 64, sb * 128 + 64, @cur_u, uo, @uvs)
        lf_rows(row, 1, 1, sb * 64, sb * 128 + 96, @cur_u, uo, @uvs)
        lf_cols(col, 1, 1, sb * 64, sb * 128 + 64, @cur_v, uo, @uvs)
        lf_rows(row, 1, 1, sb * 64, sb * 128 + 96, @cur_v, uo, @uvs)
        sc += 1
      sr += 1
    0

  # ---------------------------------------------------------- adaptation

  -> adapt(pa, i, ct0, ct1, max_count, uf) (i64[] i64 i64 i64 i64 i64) i64
    ct = ct0 + ct1
    return 0 if ct == 0
    f = (uf * (ct < max_count ? ct : max_count)) / max_count
    p1 = pa[i]
    p2 = ((ct0 << 8) + (ct >> 1)) / ct
    p2 = 1 if p2 < 1
    p2 = 255 if p2 > 255
    pa[i] = p1 + (((p2 - p1) * f + 128) >> 8)
    0

  -> adapt_probs
    cb = @ctxid * 1728
    pb = @ctxid * VP9P_SIZE
    cp = @ctx_cp
    uf = (@keyframe == 1 || @intraonly == 1 || @last_keyframe == 0) ? 112 : 128
    q = 0
    while q < 4 * 2 * 2 * 6 * 6
      band = (q / 6) % 6
      ctx = q % 6
      if !(band == 0 && ctx >= 3)
        e0 = @ceob[q * 2]
        e1 = @ceob[q * 2 + 1]
        c0 = @ccoef[q * 3]
        c1 = @ccoef[q * 3 + 1]
        c2 = @ccoef[q * 3 + 2]
        adapt(cp, cb + q * 3, e0, e1, 24, uf)
        adapt(cp, cb + q * 3 + 1, c0, c1 + c2, 24, uf)
        adapt(cp, cb + q * 3 + 2, c1, c2, 24, uf)
      q += 1
    p = @ctx_p
    c = @counts
    if @keyframe == 1 || @intraonly == 1
      vp9_copy(p, pb + VP9P_SKIP, @p, VP9P_SKIP, 3)
      vp9_copy(p, pb + VP9P_TX32, @p, VP9P_TX32, 12)
      return 0
    k = 0
    while k < 3
      adapt(p, pb + VP9P_SKIP + k, c[VC_SKIP + k * 2], c[VC_SKIP + k * 2 + 1], 20, 128)
      k += 1
    k = 0
    while k < 4
      adapt(p, pb + VP9P_INTRA + k, c[VC_INTRA + k * 2], c[VC_INTRA + k * 2 + 1], 20, 128)
      k += 1
    if @comppred == 2
      k = 0
      while k < 5
        adapt(p, pb + VP9P_COMP + k, c[VC_COMP + k * 2], c[VC_COMP + k * 2 + 1], 20, 128)
        k += 1
    if @comppred != 0
      k = 0
      while k < 5
        adapt(p, pb + VP9P_CREF + k, c[VC_CREF + k * 2], c[VC_CREF + k * 2 + 1], 20, 128)
        k += 1
    if @comppred != 1
      k = 0
      while k < 5
        adapt(p, pb + VP9P_SREF + k * 2, c[VC_SREF + k * 4], c[VC_SREF + k * 4 + 1], 20, 128)
        adapt(p, pb + VP9P_SREF + k * 2 + 1, c[VC_SREF + k * 4 + 2], c[VC_SREF + k * 4 + 3], 20, 128)
        k += 1
    k = 0
    while k < 16
      b = VC_PART + k * 4
      o = pb + VP9P_PART + k * 3
      adapt(p, o, c[b], c[b + 1] + c[b + 2] + c[b + 3], 20, 128)
      adapt(p, o + 1, c[b + 1], c[b + 2] + c[b + 3], 20, 128)
      adapt(p, o + 2, c[b + 2], c[b + 3], 20, 128)
      k += 1
    if @txmode == 4
      k = 0
      while k < 2
        adapt(p, pb + VP9P_TX8 + k, c[VC_TX8 + k * 2], c[VC_TX8 + k * 2 + 1], 20, 128)
        b16 = VC_TX16 + k * 3
        adapt(p, pb + VP9P_TX16 + k * 2, c[b16], c[b16 + 1] + c[b16 + 2], 20, 128)
        adapt(p, pb + VP9P_TX16 + k * 2 + 1, c[b16 + 1], c[b16 + 2], 20, 128)
        b32 = VC_TX32 + k * 4
        adapt(p, pb + VP9P_TX32 + k * 3, c[b32], c[b32 + 1] + c[b32 + 2] + c[b32 + 3], 20, 128)
        adapt(p, pb + VP9P_TX32 + k * 3 + 1, c[b32 + 1], c[b32 + 2] + c[b32 + 3], 20, 128)
        adapt(p, pb + VP9P_TX32 + k * 3 + 2, c[b32 + 2], c[b32 + 3], 20, 128)
        k += 1
    if @filtermode == 4
      k = 0
      while k < 4
        b = VC_FILTER + k * 3
        adapt(p, pb + VP9P_FILTER + k * 2, c[b], c[b + 1] + c[b + 2], 20, 128)
        adapt(p, pb + VP9P_FILTER + k * 2 + 1, c[b + 1], c[b + 2], 20, 128)
        k += 1
    k = 0
    while k < 7
      b = VC_MVMODE + k * 4
      o = pb + VP9P_MVMODE + k * 3
      adapt(p, o, c[b + 2], c[b + 1] + c[b] + c[b + 3], 20, 128)
      adapt(p, o + 1, c[b], c[b + 1] + c[b + 3], 20, 128)
      adapt(p, o + 2, c[b + 1], c[b + 3], 20, 128)
      k += 1
    b = VC_MVJ
    o = pb + VP9P_MVJ
    adapt(p, o, c[b], c[b + 1] + c[b + 2] + c[b + 3], 20, 128)
    adapt(p, o + 1, c[b + 1], c[b + 2] + c[b + 3], 20, 128)
    adapt(p, o + 2, c[b + 2], c[b + 3], 20, 128)
    i = 0
    while i < 2
      b = VC_MVC + i * 51
      o = pb + VP9P_MVC + i * 33
      adapt(p, o, c[b], c[b + 1], 20, 128)
      cl = b + 2
      sum = 0
      k = 1
      while k <= 10
        sum += c[cl + k]
        k += 1
      adapt(p, o + 1, c[cl], sum, 20, 128)
      sum -= c[cl + 1]
      adapt(p, o + 2, c[cl + 1], sum, 20, 128)
      sum -= c[cl + 2] + c[cl + 3]
      adapt(p, o + 3, c[cl + 2] + c[cl + 3], sum, 20, 128)
      adapt(p, o + 4, c[cl + 2], c[cl + 3], 20, 128)
      sum -= c[cl + 4] + c[cl + 5]
      adapt(p, o + 5, c[cl + 4] + c[cl + 5], sum, 20, 128)
      adapt(p, o + 6, c[cl + 4], c[cl + 5], 20, 128)
      sum -= c[cl + 6]
      adapt(p, o + 7, c[cl + 6], sum, 20, 128)
      adapt(p, o + 8, c[cl + 7] + c[cl + 8], c[cl + 9] + c[cl + 10], 20, 128)
      adapt(p, o + 9, c[cl + 7], c[cl + 8], 20, 128)
      adapt(p, o + 10, c[cl + 9], c[cl + 10], 20, 128)
      adapt(p, o + 11, c[b + 13], c[b + 14], 20, 128)
      k = 0
      while k < 10
        adapt(p, o + 12 + k, c[b + 15 + k * 2], c[b + 15 + k * 2 + 1], 20, 128)
        k += 1
      j = 0
      while j < 2
        cf = b + 35 + j * 4
        adapt(p, o + 22 + j * 3, c[cf], c[cf + 1] + c[cf + 2] + c[cf + 3], 20, 128)
        adapt(p, o + 22 + j * 3 + 1, c[cf + 1], c[cf + 2] + c[cf + 3], 20, 128)
        adapt(p, o + 22 + j * 3 + 2, c[cf + 2], c[cf + 3], 20, 128)
        j += 1
      cf = b + 43
      adapt(p, o + 28, c[cf], c[cf + 1] + c[cf + 2] + c[cf + 3], 20, 128)
      adapt(p, o + 29, c[cf + 1], c[cf + 2] + c[cf + 3], 20, 128)
      adapt(p, o + 30, c[cf + 2], c[cf + 3], 20, 128)
      if @hp == 1
        adapt(p, o + 31, c[b + 47], c[b + 48], 20, 128)
        adapt(p, o + 32, c[b + 49], c[b + 50], 20, 128)
      i += 1
    # intra modes: y_mode [4] and uv_mode [10]
    k = 0
    while k < 14
      cm = k < 4 ? VC_YMODE + k * 10 : VC_UVMODE + (k - 4) * 10
      o = k < 4 ? pb + VP9P_YMODE + k * 9 : pb + VP9P_UVMODE + (k - 4) * 9
      adapt_imode(p, o, c, cm)
      k += 1
    0

  # DC=2 TM=9 V=0 H=1 D135=4 D117=5 D45=3 D63=7 D153=6 D207=8
  -> adapt_imode(p, o, c, cm) (i64[] i64 i64[] i64) i64
    sum = c[cm] + c[cm + 1] + c[cm + 3] + c[cm + 4] + c[cm + 5] + c[cm + 6] + c[cm + 7] + c[cm + 8] + c[cm + 9]
    adapt(p, o, c[cm + 2], sum, 20, 128)
    sum -= c[cm + 9]
    adapt(p, o + 1, c[cm + 9], sum, 20, 128)
    sum -= c[cm]
    adapt(p, o + 2, c[cm], sum, 20, 128)
    s2 = c[cm + 1] + c[cm + 4] + c[cm + 5]
    sum -= s2
    adapt(p, o + 3, s2, sum, 20, 128)
    s2 -= c[cm + 1]
    adapt(p, o + 4, c[cm + 1], s2, 20, 128)
    adapt(p, o + 5, c[cm + 4], c[cm + 5], 20, 128)
    sum -= c[cm + 3]
    adapt(p, o + 6, c[cm + 3], sum, 20, 128)
    sum -= c[cm + 7]
    adapt(p, o + 7, c[cm + 7], sum, 20, 128)
    adapt(p, o + 8, c[cm + 6], c[cm + 8], 20, 128)
    0

-> vp9_tile_off(idx, log2n, n)
  s = (idx * n) >> log2n
  s = n if s > n
  s << 3

-> vp9_recenter(v, m)
  return v if v > 2 * m
  if (v & 1) == 1
    m - ((v + 1) >> 1)
  else
    m + (v >> 1)

-> vp9_clipu8(v)
  v < 0 ? 0 : (v > 255 ? 255 : v)

-> vp9_clip6(v)
  v < 0 ? 0 : (v > 63 ? 63 : v)

-> vp9_rdiv(a, b) (i64 i64) i64
  if a >= 0
    (a + (b >> 1)) / b
  else
    (a - (b >> 1)) / b

-> vp9_copy(dst, d, src, s, n) (i64[] i64 i64[] i64 i64) i64
  k = 0 ## i64
  while k < n
    dst[d + k] = src[s + k]
    k += 1
  0

-> vp9_zero(a) (i64[]) i64
  k = 0 ## i64
  n = a.size
  while k < n
    a[k] = 0
    k += 1
  0

-> vp9_zero32(a) (i32[]) i64
  k = 0 ## i64
  n = a.size
  while k < n
    a[k] = 0
    k += 1
  0

-> vp9_set(a, v) (i64[] i64) i64
  k = 0 ## i64
  n = a.size
  while k < n
    a[k] = v
    k += 1
  0

-> vp9_setn(a, o, n, v) (i64[] i64 i64 i64) i64
  k = 0 ## i64
  while k < n
    a[o + k] = v
    k += 1
  0

vcodec_register("vp09", ->(cfg) VP9Dec.new(cfg))

-> vp9_copy8(dst, src, n) (u8[] u8[] i64) i64
  i = 0
  while i < n
    dst[i] = src[i]
    i += 1
  n
