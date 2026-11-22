# core/codec/image/jxr_mb — JPEG XR headers, tiles and macroblock layer (T.832 clause 8).
#
# Everything a decoded plane needs lives in JxrPlane; image-wide geometry in
# JxrImage. Macroblocks are addressed by their global index g (row-major over
# the extended image); mx/my are tile-local, as every adaptive context and
# predictor in JPEG XR restarts at tile edges.

use core/codec/image
use jxr_parse

+ JxrPlane
  rw :nch, :clr, :scaled, :bands, :shift_bits, :len_mant, :exp_bias
  rw :dc_uni, :lp_uni, :hp_uni, :nlpq, :nhpq, :lp_use_dc, :hp_use_lp, :ccx, :ccy
  rw :dcq, :lpq, :hpq, :tdcq, :tlpq, :st, :co, :lpqi, :hpqv, :cbp, :mbhp, :hpmb, :pred
  rw :nmb, :mbw, :lpin, :rl, :diff, :hpin, :tmp, :hpfl, :hp_frame_lp, :tnlpq

  -> new
    @nch = 1
    @clr = 0
    @scaled = 0
    @bands = 0
    @shift_bits = 0
    @len_mant = 0
    @exp_bias = 0
    @dc_uni = 1
    @lp_uni = 1
    @hp_uni = 1
    @nlpq = 1
    @nhpq = 1
    @lp_use_dc = 0
    @hp_use_lp = 0
    @hp_frame_lp = 0
    @ccx = 0
    @ccy = 0
    @dcq = i64[16]
    @lpq = i64[256]
    @hpq = i64[256]
    @st = i64[220]
    @lpin = i64[128]
    @rl = i64[34]
    @diff = i64[16]
    @hpin = i64[16]
    @tmp = i64[16]

  -> alloc(nmb, mbw, ntiles)
    @nmb = nmb
    @mbw = mbw
    @co = i32[@nch * nmb * 256]
    @lpqi = i64[nmb]
    @hpqv = i64[@nch * nmb]
    @hpfl = i64[nmb]
    @cbp = i64[@nch * nmb]
    @mbhp = i64[nmb]
    @hpmb = i64[nmb * 2]
    @pred = i64[@nch * nmb * 8]
    @tdcq = i64[ntiles * 16]
    @tlpq = i64[ntiles * 256]
    @tnlpq = i64[ntiles]

+ JxrImage
  rw :w, :h, :ew, :eh, :mbw, :mbh, :nmb, :tcols, :trows, :tcw, :tcp, :trh, :trp
  rw :f1, :f2, :fmt, :no_tile_ovl, :sub, :wtop, :wleft, :pl, :alpha, :itab, :bd, :ocf

  -> new
    @alpha = nil
    @itab = nil

  -> tiling?
    (@f1 & 0x80) != 0
  -> freq?
    (@f1 & 0x40) != 0
  -> xform
    (@f1 >> 3) & 7
  -> index_table?
    (@f1 & 0x04) != 0
  -> overlap
    @f1 & 3
  -> short_header?
    (@f2 & 0x80) != 0
  -> windowing?
    (@f2 & 0x20) != 0
  -> trim_flex?
    (@f2 & 0x10) != 0
  -> has_alpha?
    (@f2 & 0x01) != 0

-> jxr_fail(msg)
  << "jxr: " + msg if env("JXR_DEBUG") != nil
  raise ImageError, "jxr: " + msg

# ---------------------------------------------------------------- headers

-> jxr_image_header(src, br)
  sig = "WMPHOTO"
  i = 0
  while i < 7
    jxr_fail("bad WMPHOTO signature") if jxr_get(src, br, 8) != sig.byte_at(i)
    i += 1
  jxr_fail("bad WMPHOTO signature") if jxr_get(src, br, 8) != 0
  im = JxrImage.new
  jxr_get(src, br, 4)
  im.no_tile_ovl = jxr_get(src, br, 1)
  im.sub = jxr_get(src, br, 3)
  im.f1 = jxr_get(src, br, 8)
  im.f2 = jxr_get(src, br, 8)
  im.fmt = jxr_get(src, br, 8)
  im.ocf = (im.fmt >> 4) & 15
  im.bd = im.fmt & 15
  w1 = 0
  h1 = 0
  if im.short_header?
    w1 = jxr_get(src, br, 16)
    h1 = jxr_get(src, br, 16)
  else
    w1 = jxr_get(src, br, 32)
    h1 = jxr_get(src, br, 32)
  im.w = w1 + 1
  im.h = h1 + 1
  tc = 1
  tr = 1
  if im.tiling?
    tc = jxr_get(src, br, 12) + 1
    tr = jxr_get(src, br, 12) + 1
  im.tcols = tc
  im.trows = tr
  tcw = i64[tc]
  tcp = i64[tc]
  trh = i64[tr]
  trp = i64[tr]
  nb = 16
  nb = 8 if im.short_header?
  ws = 0
  i = 0
  while i < tc - 1
    tcw[i] = jxr_get(src, br, nb)
    tcp[i] = ws
    ws += tcw[i]
    i += 1
  hs = 0
  i = 0
  while i < tr - 1
    trh[i] = jxr_get(src, br, nb)
    trp[i] = hs
    hs += trh[i]
    i += 1
  wt = 0
  wl = 0
  wb = 0
  wr = 0
  if im.windowing?
    wt = jxr_get(src, br, 6)
    wl = jxr_get(src, br, 6)
    wb = jxr_get(src, br, 6)
    wr = jxr_get(src, br, 6)
  else
    wb = 16 - (im.h % 16) if im.h % 16 != 0
    wr = 16 - (im.w % 16) if im.w % 16 != 0
  im.wtop = wt
  im.wleft = wl
  im.ew = im.w + wl + wr
  im.eh = im.h + wt + wb
  jxr_fail("extended size not a multiple of 16") if im.ew % 16 != 0 || im.eh % 16 != 0
  im.mbw = im.ew / 16
  im.mbh = im.eh / 16
  jxr_fail("image too large") if im.mbw * im.mbh > 4000000
  im.nmb = im.mbw * im.mbh
  tcw[tc - 1] = im.mbw - ws
  tcp[tc - 1] = ws
  trh[tr - 1] = im.mbh - hs
  trp[tr - 1] = hs
  jxr_fail("bad tile layout") if tcw[tc - 1] <= 0 || trh[tr - 1] <= 0
  im.tcw = tcw
  im.tcp = tcp
  im.trh = trh
  im.trp = trp
  im

-> jxr_ch_mode(src, br, pl)
  return 0 if pl.nch == 1
  jxr_get(src, br, 2)

-> jxr_read_dc_qp(src, br, pl)
  m = jxr_ch_mode(src, br, pl)
  q = pl.dcq ## i64[]
  n = pl.nch
  if m == 0
    q[0] = jxr_get(src, br, 8)
    i = 1
    while i < n
      q[i] = q[0]
      i += 1
  elsif m == 1
    q[0] = jxr_get(src, br, 8)
    q[1] = jxr_get(src, br, 8)
    i = 2
    while i < n
      q[i] = q[1]
      i += 1
  elsif m == 2
    i = 0
    while i < n
      q[i] = jxr_get(src, br, 8)
      i += 1

# LP and HP quantisers: q[ch * 16 + index]
-> jxr_read_qps(src, br, pl, q, count)
  n = pl.nch
  k = 0
  while k < count
    m = jxr_ch_mode(src, br, pl)
    if m == 0
      q[k] = jxr_get(src, br, 8)
      i = 1
      while i < n
        q[i * 16 + k] = q[k]
        i += 1
    elsif m == 1
      q[k] = jxr_get(src, br, 8)
      q[16 + k] = jxr_get(src, br, 8)
      i = 2
      while i < n
        q[i * 16 + k] = q[16 + k]
        i += 1
    elsif m == 2
      i = 0
      while i < n
        q[i * 16 + k] = jxr_get(src, br, 8)
        i += 1
    k += 1

-> jxr_plane_header(src, br, im, is_alpha)
  pl = JxrPlane.new
  pl.clr = jxr_get(src, br, 3)
  pl.scaled = jxr_get(src, br, 1)
  pl.bands = jxr_get(src, br, 4)
  jxr_fail("alpha plane must be Y-only") if is_alpha && pl.clr != 0
  c = pl.clr
  if c == 0
    pl.nch = 1
  elsif c == 1
    jxr_get(src, br, 1)
    pl.ccx = jxr_get(src, br, 3)
    jxr_get(src, br, 1)
    pl.ccy = jxr_get(src, br, 3)
    pl.nch = 3
  elsif c == 2
    jxr_get(src, br, 1)
    pl.ccx = jxr_get(src, br, 3)
    jxr_get(src, br, 4)
    pl.nch = 3
  elsif c == 3
    jxr_get(src, br, 8)
    pl.nch = 3
  elsif c == 4
    pl.nch = 4
  elsif c == 6
    n = jxr_get(src, br, 4)
    if n == 15
      pl.nch = 16 + jxr_get(src, br, 12)
    else
      pl.nch = 1 + n
      jxr_get(src, br, 4)
  else
    jxr_fail("reserved internal colour format")
  jxr_fail("too many channels") if pl.nch > 16
  bd = im.bd
  if bd == 2 || bd == 3 || bd == 6
    pl.shift_bits = jxr_get(src, br, 8)
  elsif bd == 7
    pl.len_mant = jxr_get(src, br, 8)
    pl.exp_bias = jxr_get(src, br, 8)
  pl.dc_uni = jxr_get(src, br, 1)
  jxr_read_dc_qp(src, br, pl) if pl.dc_uni == 1
  pl.lp_uni = 1
  pl.hp_uni = 1
  # T.832 calls the bits before LP_/HP_IMAGE_PLANE_UNIFORM_FLAG reserved
  # (always 0); jxrlib reads them as "LP uses the DC quantisers" / "HP uses
  # the LP quantisers" and its encoder may set them, so honour them.
  if pl.bands != 3
    if jxr_get(src, br, 1) == 1
      pl.lp_uni = pl.dc_uni
      if pl.dc_uni == 1
        pl.nlpq = 1
        d = pl.dcq ## i64[]
        l = pl.lpq ## i64[]
        ch = 0
        while ch < pl.nch
          l[ch * 16] = d[ch]
          ch += 1
    else
      pl.lp_uni = jxr_get(src, br, 1)
      if pl.lp_uni == 1
        pl.nlpq = 1
        jxr_read_qps(src, br, pl, pl.lpq, 1)
    if pl.bands != 2
      if jxr_get(src, br, 1) == 1
        pl.hp_frame_lp = 1
        pl.hp_uni = pl.lp_uni
        if pl.lp_uni == 1
          pl.nhpq = 1
          l = pl.lpq ## i64[]
          h = pl.hpq ## i64[]
          i = 0
          while i < 256
            h[i] = l[i]
            i += 1
      else
        pl.hp_uni = jxr_get(src, br, 1)
        if pl.hp_uni == 1
          pl.nhpq = 1
          jxr_read_qps(src, br, pl, pl.hpq, 1)
  jxr_sync(br)
  pl

-> jxr_index_table(src, br, im)
  return nil if !im.index_table?
  jxr_fail("bad index table start code") if jxr_get(src, br, 8) != 0 || jxr_get(src, br, 8) != 1
  n = im.tcols * im.trows
  if im.freq?
    b = im.pl.bands
    if b == 4
      n = n * 4
    else
      n = n * (4 - b)
  t = i64[n]
  i = 0
  while i < n
    t[i] = jxr_vlw(src, br)
    i += 1
  t

# ---------------------------------------------------------------- tile headers

-> jxr_tile_hdr_dc(src, br, pl, ti)
  if pl.dc_uni == 0
    jxr_read_dc_qp(src, br, pl)
    q = pl.dcq ## i64[]
    t = pl.tdcq ## i64[]
    i = 0
    while i < 16
      t[ti * 16 + i] = q[i]
      i += 1

-> jxr_tile_hdr_lp(src, br, pl, ti)
  if pl.lp_uni == 0
    pl.lp_use_dc = jxr_get(src, br, 1)
    q = pl.lpq ## i64[]
    t = pl.tlpq ## i64[]
    if pl.lp_use_dc == 0
      pl.nlpq = jxr_get(src, br, 4) + 1
      jxr_read_qps(src, br, pl, q, pl.nlpq)
    else
      # this tile's DC quantisers (in frequency mode every DC tile header
      # was read before any LP one, so pl.dcq holds the last tile's)
      pl.nlpq = 1
      d = pl.dcq ## i64[]
      td = pl.tdcq ## i64[]
      ch = 0
      while ch < pl.nch
        if pl.dc_uni == 1
          q[ch * 16] = d[ch]
        else
          q[ch * 16] = td[ti * 16 + ch]
        ch += 1
    i = 0
    while i < 256
      t[ti * 256 + i] = q[i]
      i += 1
    tn = pl.tnlpq ## i64[]
    tn[ti] = pl.nlpq

-> jxr_tile_hdr_hp(src, br, pl, ti)
  if pl.hp_uni == 0
    pl.hp_use_lp = jxr_get(src, br, 1)
    q = pl.hpq ## i64[]
    if pl.hp_use_lp == 0
      pl.nhpq = jxr_get(src, br, 4) + 1
      jxr_read_qps(src, br, pl, q, pl.nhpq)
    else
      if pl.lp_uni == 1
        pl.nhpq = pl.nlpq
        l = pl.lpq ## i64[]
        i = 0
        while i < 256
          q[i] = l[i]
          i += 1
      else
        tn = pl.tnlpq ## i64[]
        tl = pl.tlpq ## i64[]
        pl.nhpq = tn[ti]
        i = 0
        while i < 256
          q[i] = tl[ti * 256 + i]
          i += 1

# ---------------------------------------------------------------- macroblock layer

-> jxr_mb_dc(pl, src, br, g, mx, my, tw)
  st = pl.st ## i64[]
  co = pl.co ## i32[]
  nch = pl.nch
  nmb = pl.nmb
  clr = pl.clr
  if mx == 0 && my == 0
    jxr_init_vlc(st, 0)
    jxr_init_vlc(st, 1)
    jxr_init_model(st, 100, 0)
  lap0 = 0
  lap1 = 0
  if clr == 0 || clr == 4 || clr == 6
    idx = 0
    while idx < nch
      m = 0
      m = 1 if idx > 0
      mbits = st[100 + m]
      isdc = jxr_bit(src, br)
      if isdc == 1
        if m == 0
          lap0 += 1
        else
          lap1 += 1
      co[(idx * nmb + g) * 256] = jxr_dec_dc(src, br, st, mbits, 0, isdc)
      idx += 1
  else
    isyuv = jxr_is_dc_yuv(src, br)
    my_ = st[100]
    muv = st[101]
    lap0 += 1 if (isyuv & 4) != 0
    co[g * 256] = jxr_dec_dc(src, br, st, my_, 0, isyuv & 4)
    lap1 += 1 if (isyuv & 2) != 0
    co[(nmb + g) * 256] = jxr_dec_dc(src, br, st, muv, 1, isyuv & 2)
    lap1 += 1 if (isyuv & 1) != 0
    co[(2 * nmb + g) * 256] = jxr_dec_dc(src, br, st, muv, 1, isyuv & 1)
  jxr_update_model(st, 100, lap0, lap1, 0, clr, nch)
  if mx % 16 == 0 || mx == tw - 1
    jxr_adapt_vlc(st, 0)
    jxr_adapt_vlc(st, 1)

-> jxr_mb_lp(pl, src, br, g, mx, my, tw)
  st = pl.st ## i64[]
  co = pl.co ## i32[]
  lpin = pl.lpin ## i64[]
  rl = pl.rl ## i64[]
  tmp = pl.tmp ## i64[]
  nch = pl.nch
  nmb = pl.nmb
  clr = pl.clr
  if mx == 0 && my == 0
    st[118] = 1
    st[119] = 1
    jxr_init_vlc2(st, 2)
    jxr_init_vlc2(st, 7)
    jxr_init_vlc2(st, 8)
    jxr_init_vlc2(st, 9)
    jxr_init_vlc2(st, 10)
    jxr_init_vlc2(st, 11)
    jxr_init_vlc(st, 3)
    jxr_init_vlc(st, 4)
    jxr_init_scan_lp(st)
    jxr_init_model(st, 104, 1)
  jxr_reset_totals(st, 135) if mx % 16 == 0
  i = 0
  while i < 128
    lpin[i] = 0
    i += 1
  lap0 = 0
  lap1 = 0
  full = nch
  full = 2 if clr == 1 || clr == 2
  cbplp = 0
  if clr == 1 || clr == 2 || clr == 3
    mx_ = full * 4 - 5
    if st[118] <= 0 || st[119] < 0
      v = 0
      if clr == 3
        v = jxr_inte(src, br, 4, JXR_CBPLP_B, JXR_CBPLP_V)
      elsif jxr_bit(src, br) == 0
        v = 0
      elsif jxr_bit(src, br) == 0
        v = 1
      elsif jxr_bit(src, br) == 0
        v = 2
      else
        v = 3
      if st[119] < st[118]
        cbplp = mx_ - v
      else
        cbplp = v
    else
      cbplp = jxr_get(src, br, full)
    st[118] = st[118] + 1
    st[118] = st[118] - 4 if cbplp == 0
    st[118] = 7 if st[118] > 7
    st[118] = -8 if st[118] < -8
    st[119] = st[119] + 1
    st[119] = st[119] - 4 if cbplp == mx_
    st[119] = 7 if st[119] > 7
    st[119] = -8 if st[119] < -8
  else
    idx = 0
    while idx < nch
      cbplp = cbplp | (jxr_bit(src, br) << idx)
      idx += 1
  t444 = JXR_TRANSPOSE444 ## i64[]
  t420 = JXR_TRANSPOSE420 ## i64[]
  t422 = JXR_TRANSPOSE422 ## i64[]
  ndx = 0
  while ndx < full
    chroma = 0
    chroma = 1 if ndx > 0
    nnz = 0
    if ((cbplp >> ndx) & 1) != 0
      location = 1
      location = 10 if clr == 1 && chroma == 1
      location = 2 if clr == 2 && chroma == 1
      nnz = jxr_decode_block(src, br, st, chroma, 1, location, rl)
      if (clr == 1 || clr == 2) && chroma == 1
        k = 0
        while k < 14
          tmp[k] = 0 if k < 16
          k += 1
        temp = i64[16]
        ii = 0
        k = 0
        while k < nnz
          ii += rl[k * 2]
          if ii < 14
            temp[ii] = rl[k * 2 + 1]
          ii += 1
          k += 1
        roff = 0
        roff = 1 if clr == 1
        cnt = 14
        cnt = 6 if clr == 1
        rm = JXR_LPCHR_REMAP ## i64[]
        k = 0
        while k < cnt
          r = rm[(k >> 1) + roff]
          plane = (k & 1) + 1
          if clr == 1
            r = t420[r]
          else
            r = t422[r]
          lpin[plane * 16 + r] = temp[k]
          k += 1
      else
        ii = 1
        k = 0
        while k < nnz
          ii += rl[k * 2]
          if ii <= 15
            jxr_scan_put(st, 120, lpin, ndx * 16, ii, rl[k * 2 + 1])
          else
            br[2] = 1
          ii += 1
          k += 1
    mbits = st[104 + chroma]
    if chroma == 0
      lap0 += nnz
    else
      lap1 += nnz
    if mbits > 0
      if chroma == 0
        k = 1
        while k < 16
          kp = ndx * 16 + t444[k]
          lpin[kp] = jxr_refine_lp(src, br, lpin[kp], mbits)
          k += 1
      elsif clr == 1
        k = 1
        while k < 4
          kp = t420[k]
          lpin[16 + kp] = jxr_refine_lp(src, br, lpin[16 + kp], mbits)
          lpin[32 + kp] = jxr_refine_lp(src, br, lpin[32 + kp], mbits)
          k += 1
      elsif clr == 2
        k = 1
        while k < 8
          kp = t422[k]
          lpin[16 + kp] = jxr_refine_lp(src, br, lpin[16 + kp], mbits)
          lpin[32 + kp] = jxr_refine_lp(src, br, lpin[32 + kp], mbits)
          k += 1
      else
        k = 1
        while k < 16
          kp = ndx * 16 + t444[k]
          lpin[kp] = jxr_refine_lp(src, br, lpin[kp], mbits)
          k += 1
    if chroma == 0 || (clr != 1 && clr != 2)
      b = (ndx * nmb + g) * 256
      k = 1
      while k < 16
        co[b + k] = lpin[ndx * 16 + k]
        k += 1
    else
      cnt = 8
      cnt = 4 if clr == 1
      b1 = (nmb + g) * 256
      b2 = (2 * nmb + g) * 256
      k = 1
      while k < cnt
        co[b1 + k] = lpin[16 + k]
        co[b2 + k] = lpin[32 + k]
        k += 1
    ndx += 1
  jxr_update_model(st, 104, lap0, lap1, 1, clr, nch)
  jxr_adapt_lp(st) if mx % 16 == 0 || mx == tw - 1

-> jxr_iabs(v) (i64) i64
  return 0 - v if v < 0
  v

-> jxr_iabs32(v) (i32) i64
  return 0 - v if v < 0
  v

# DC and LP prediction (T.832 8.7.1-8.7.2); runs once DC (and LP) of the
# macroblock are parsed.
-> jxr_complete_dclp(pl, g, mx, my)
  co = pl.co ## i32[]
  pred = pl.pred ## i64[]
  lpqi = pl.lpqi ## i64[]
  nch = pl.nch
  nmb = pl.nmb
  clr = pl.clr
  mbw = pl.mbw
  mode = 2
  if mx == 0 && my == 0
    mode = 3
  elsif mx == 0
    mode = 1
  elsif my == 0
    mode = 0
  else
    left = co[(g - 1) * 256]
    top = co[(g - mbw) * 256]
    tl = co[(g - mbw - 1) * 256]
    sh = 0
    sv = 0
    if clr == 0 || clr == 6
      sh = jxr_iabs(tl - left)
      sv = jxr_iabs(tl - top)
    else
      bu = nmb * 256
      bv = 2 * nmb * 256
      scale = 2
      scale = 4 if clr == 2
      scale = 8 if clr == 1
      sh = jxr_iabs(tl - left) * scale + jxr_iabs(co[bu + (g - mbw - 1) * 256] - co[bu + (g - 1) * 256]) + jxr_iabs(co[bv + (g - mbw - 1) * 256] - co[bv + (g - 1) * 256])
      sv = jxr_iabs(tl - top) * scale + jxr_iabs(co[bu + (g - mbw - 1) * 256] - co[bu + (g - mbw) * 256]) + jxr_iabs(co[bv + (g - mbw - 1) * 256] - co[bv + (g - mbw) * 256])
    if sh * 4 < sv
      mode = 1
    elsif sv * 4 < sh
      mode = 0
  ch = 0
  while ch < nch
    b = (ch * nmb + g) * 256
    if mode == 0
      co[b] = co[b] + co[b - 256]
    elsif mode == 1
      co[b] = co[b] + co[b - mbw * 256]
    elsif mode == 2
      s = co[b - 256] + co[b - mbw * 256]
      if ch > 0 && (clr == 1 || clr == 2)
        co[b] = co[b] + ((s + 1) >> 1)
      else
        co[b] = co[b] + (s >> 1)
    ch += 1
  lpm = 2
  if mode == 0 && lpqi[g] == lpqi[g - 1]
    lpm = 0
  elsif mode == 1 && lpqi[g] == lpqi[g - mbw]
    lpm = 1
  ch = 0
  while ch < nch
    b = (ch * nmb + g) * 256
    p = (ch * nmb + g) * 8
    pl_ = p - 8
    pu = p - mbw * 8
    if ch == 0 || (clr != 1 && clr != 2)
      if lpm == 0
        co[b + 4] = co[b + 4] + pred[pl_ + 4]
        co[b + 8] = co[b + 8] + pred[pl_ + 5]
        co[b + 12] = co[b + 12] + pred[pl_ + 6]
      elsif lpm == 1
        co[b + 1] = co[b + 1] + pred[pu + 1]
        co[b + 2] = co[b + 2] + pred[pu + 2]
        co[b + 3] = co[b + 3] + pred[pu + 3]
      pred[p + 1] = co[b + 1]
      pred[p + 2] = co[b + 2]
      pred[p + 3] = co[b + 3]
      pred[p + 4] = co[b + 4]
      pred[p + 5] = co[b + 8]
      pred[p + 6] = co[b + 12]
    elsif clr == 2
      if lpm == 0
        co[b + 4] = co[b + 4] + pred[pl_ + 4]
        co[b + 2] = co[b + 2] + pred[pl_ + 2]
        co[b + 6] = co[b + 6] + pred[pl_ + 6]
      elsif lpm == 1
        co[b + 4] = co[b + 4] + pred[pu + 4]
        co[b + 1] = co[b + 1] + pred[pu + 5]
        co[b + 5] = co[b + 5] + co[b + 1]
      elsif mode == 1
        co[b + 5] = co[b + 5] + co[b + 1]
      pred[p + 1] = co[b + 1]
      pred[p + 2] = co[b + 2]
      pred[p + 4] = co[b + 4]
      pred[p + 5] = co[b + 5]
      pred[p + 6] = co[b + 6]
    else
      if lpm == 0
        co[b + 2] = co[b + 2] + pred[pl_ + 2]
      elsif lpm == 1
        co[b + 1] = co[b + 1] + pred[pu + 1]
      pred[p + 1] = co[b + 1]
      pred[p + 2] = co[b + 2]
    ch += 1

-> jxr_update_cbp_model(st, c, norig) (i64[] i64 i64) i64
  a = st[114 + c] + norig - 3
  a = 15 if a > 15
  a = -16 if a < -16
  st[114 + c] = a
  b = st[116 + c] + 16 - norig - 3
  b = 15 if b > 15
  b = -16 if b < -16
  st[116 + c] = b
  if a < 0
    if a < b
      st[112 + c] = 1
    else
      st[112 + c] = 2
  elsif b < 0
    st[112 + c] = 2
  else
    st[112 + c] = 0
  0

-> jxr_pred_cbp(st, cbpa, kind, ch, diffv, g, nmb, mbw, mx, my) (i64[] i64[] i64 i64 i64 i64 i64 i64 i64 i64) i64
  chroma = 0 ## i64
  chroma = 1 if ch > 0
  cbp = diffv
  state = st[112 + chroma]
  base = ch * nmb
  if kind == 444
    if state == 0
      if mx == 0
        if my == 0
          cbp = cbp ^ 1
        else
          cbp = cbp ^ ((cbpa[base + g - mbw] >> 10) & 1)
      else
        cbp = cbp ^ ((cbpa[base + g - 1] >> 5) & 1)
      cbp = cbp ^ (0x02 & (cbp << 1))
      cbp = cbp ^ (0x10 & (cbp << 3))
      cbp = cbp ^ (0x20 & (cbp << 1))
      cbp = cbp ^ ((cbp & 0x33) << 2)
      cbp = cbp ^ ((cbp & 0xcc) << 6)
      cbp = cbp ^ ((cbp & 0x3300) << 2)
    elsif state == 2
      cbp = cbp ^ 0xffff
    jxr_update_cbp_model(st, chroma, jxr_popcount(cbp))
  elsif kind == 422
    if state == 0
      if mx == 0
        if my == 0
          cbp = cbp ^ 1
        else
          cbp = cbp ^ ((cbpa[base + g - mbw] >> 6) & 1)
      else
        cbp = cbp ^ ((cbpa[base + g - 1] >> 1) & 1)
      cbp = cbp ^ (0x02 & (cbp << 1))
      cbp = cbp ^ (0x0c & (cbp << 2))
      cbp = cbp ^ (0x30 & (cbp << 2))
      cbp = cbp ^ (0xc0 & (cbp << 2))
    elsif state == 2
      cbp = cbp ^ 0xff
    jxr_update_cbp_model(st, 1, jxr_popcount(cbp) * 2)
  else
    if state == 0
      if mx == 0
        if my == 0
          cbp = cbp ^ 1
        else
          cbp = cbp ^ ((cbpa[base + g - mbw] >> 2) & 1)
      else
        cbp = cbp ^ ((cbpa[base + g - 1] >> 1) & 1)
      cbp = cbp ^ (0x02 & (cbp << 1))
      cbp = cbp ^ (0x0c & (cbp << 2))
    elsif state == 2
      cbp = cbp ^ 0xf
    jxr_update_cbp_model(st, 1, jxr_popcount(cbp) * 4)
  cbpa[base + g] = cbp
  cbp

-> jxr_mb_cbp(pl, src, br, g, mx, my)
  st = pl.st ## i64[]
  cbpa = pl.cbp ## i64[]
  diff = pl.diff ## i64[]
  nch = pl.nch
  clr = pl.clr
  if mx == 0 && my == 0
    jxr_init_vlc(st, 12)
    jxr_init_vlc(st, 13)
  i = 0
  while i < 16
    diff[i] = 0
    i += 1
  channels = 1
  channels = nch if clr == 4 || clr == 6
  d5 = JXR_BLKCBP_D5 ## i64[]
  d9 = JXR_BLKCBP_D9 ## i64[]
  flc = JXR_CBP_FLC ## i64[]
  off = JXR_CBP_OFF ## i64[]
  outt = JXR_CBP_OUT ## i64[]
  chan = 0
  while chan < channels
    ncbp = jxr_num_cbp(src, br, st[60])
    st[63] = st[63] + d5[ncbp]
    cbp = jxr_refine_cbp(src, br, ncbp)
    blk = 0
    while blk < 4
      if ((cbp >> blk) & 1) != 0
        t = st[65]
        nb = 0
        if clr == 0 || clr == 4 || clr == 6
          nb = jxr_num_cbp(src, br, t)
          st[68] = st[68] + d5[nb]
        else
          if t == 0
            nb = jxr_inte(src, br, 5, JXR_BLK0B, JXR_BLK0V)
          else
            nb = jxr_inte(src, br, 6, JXR_BLK1B, JXR_BLK1V)
            nb += jxr_bit(src, br) if nb == 7
          st[68] = st[68] + d9[nb]
        val = nb + 1
        blkcbp = 0
        if val >= 6
          chr = jxr_value012(src, br)
          blkcbp = 0x10 * (chr + 1)
          val += jxr_value012(src, br) if val >= 9
          val -= 6
        if val >= 6
          br[2] = 1
          val = 0
        code = off[val] + jxr_get(src, br, flc[val])
        blkcbp += outt[code & 15]
        if clr == 3
          diff[0] = diff[0] | ((blkcbp & 15) << (blk * 4))
          if (blkcbp & 0x10) != 0
            n = jxr_num_ch_blk(src, br)
            diff[1] = diff[1] | (jxr_refine_cbp(src, br, n + 1) << (blk * 4))
          if (blkcbp & 0x20) != 0
            n = jxr_num_ch_blk(src, br)
            diff[2] = diff[2] | (jxr_refine_cbp(src, br, n + 1) << (blk * 4))
        elsif clr == 2
          diff[0] = diff[0] | ((blkcbp & 15) << (blk * 4))
          sft = 0
          sft = 1 if blk == 1
          sft = 4 if blk == 2
          sft = 5 if blk == 3
          if (blkcbp & 0x10) != 0
            c = jxr_value012(src, br)
            v = 1
            v = 4 if c == 1
            v = 5 if c == 2
            diff[1] = diff[1] | (v << sft)
          if (blkcbp & 0x20) != 0
            c = jxr_value012(src, br)
            v = 1
            v = 4 if c == 1
            v = 5 if c == 2
            diff[2] = diff[2] | (v << sft)
        elsif clr == 1
          diff[0] = diff[0] | ((blkcbp & 15) << (blk * 4))
          diff[1] = diff[1] | (((blkcbp >> 4) & 1) << blk)
          diff[2] = diff[2] + (((blkcbp >> 5) & 1) << blk)
        else
          diff[chan] = diff[chan] | (blkcbp << (blk * 4))
      blk += 1
    chan += 1
  if mx == 0 && my == 0
    st[112] = 0
    st[113] = 0
    st[114] = -4
    st[115] = -4
    st[116] = 4
    st[117] = 4
  nmb = pl.nmb
  mbw = pl.mbw
  if clr == 1 || clr == 2
    jxr_pred_cbp(st, cbpa, 444, 0, diff[0], g, nmb, mbw, mx, my)
    k = 420
    k = 422 if clr == 2
    jxr_pred_cbp(st, cbpa, k, 1, diff[1], g, nmb, mbw, mx, my)
    jxr_pred_cbp(st, cbpa, k, 2, diff[2], g, nmb, mbw, mx, my)
  else
    ch = 0
    while ch < nch
      jxr_pred_cbp(st, cbpa, 444, ch, diff[ch], g, nmb, mbw, mx, my)
      ch += 1

-> jxr_mbhp_mode(co, b0, b1, b2, clr) (i32[] i64 i64 i64 i64) i64
  h = jxr_iabs32(co[b0 + 1]) + jxr_iabs32(co[b0 + 2]) + jxr_iabs32(co[b0 + 3])
  v = jxr_iabs32(co[b0 + 4]) + jxr_iabs32(co[b0 + 8]) + jxr_iabs32(co[b0 + 12])
  if clr == 3 || clr == 4
    h += jxr_iabs32(co[b1 + 1]) + jxr_iabs32(co[b2 + 1])
    v += jxr_iabs32(co[b1 + 4]) + jxr_iabs32(co[b2 + 4])
  elsif clr == 2
    h += jxr_iabs32(co[b1 + 1]) + jxr_iabs32(co[b2 + 1]) + jxr_iabs32(co[b1 + 5]) + jxr_iabs32(co[b2 + 5])
    v += jxr_iabs32(co[b1 + 2]) + jxr_iabs32(co[b2 + 2]) + jxr_iabs32(co[b1 + 6]) + jxr_iabs32(co[b2 + 6])
  elsif clr == 1
    h += jxr_iabs32(co[b1 + 1]) + jxr_iabs32(co[b2 + 1])
    v += jxr_iabs32(co[b1 + 2]) + jxr_iabs32(co[b2 + 2])
  return 0 if h * 4 < v
  return 1 if v * 4 < h
  2

-> jxr_decode_flex(src, br, co, i, fl, trim) (u8[] i64[] i32[] i64 i64 i64) i64
  c = co[i]
  r = jxr_get(src, br, fl)
  if c > 0
    c += r << trim
  elsif c < 0
    c -= r << trim
  elsif r != 0 && jxr_bit(src, br) == 1
    c = (0 - r) << trim
  else
    c = r << trim
  co[i] = c
  0

-> jxr_block_flex(src, br, co, hb, mbits, trim) (u8[] i64[] i32[] i64 i64 i64) i64
  fl = mbits - trim
  return 0 if fl <= 0
  t = JXR_TRANSPOSE444 ## i64[]
  idx = 1 ## i64
  while idx < 16
    jxr_decode_flex(src, br, co, hb + t[idx] - 1, fl, trim)
    idx += 1
  0

# HP coefficients of one block (DECODE_BLOCK_ADAPTIVE).
-> jxr_hp_block(src, br, st, co, hb, chroma, mode, mbits, rl, hpin) (u8[] i64[] i64[] i32[] i64 i64 i64 i64 i64[] i64[]) i64
  k = 0 ## i64
  while k < 16
    hpin[k] = 0
    k += 1
  nnz = jxr_decode_block(src, br, st, chroma, 2, 1, rl)
  so = 150 ## i64
  so = 180 if mode == 1
  k = 1
  idx = 0 ## i64
  while idx < nnz
    k += rl[idx * 2]
    if k >= 16
      br[2] = 1
      return nnz
    jxr_scan_put(st, so, hpin, 0, k, rl[idx * 2 + 1])
    k += 1
    idx += 1
  idx = 1
  while idx < 16
    co[hb + idx - 1] = hpin[idx] << mbits
    idx += 1
  nnz

-> jxr_propagate_hp(co, b, mode) (i32[] i64 i64) i64
  if mode == 0
    idx = 1 ## i64
    while idx < 16
      if idx % 4 != 0
        h = b + 16 + 15 * idx
        p = h - 15
        co[h + 3] = co[h + 3] + co[p + 3]
        co[h + 7] = co[h + 7] + co[p + 7]
        co[h + 11] = co[h + 11] + co[p + 11]
      idx += 1
  elsif mode == 1
    idx = 4
    while idx < 16
      h = b + 16 + 15 * idx
      p = h - 60
      co[h] = co[h] + co[p]
      co[h + 1] = co[h + 1] + co[p + 1]
      co[h + 2] = co[h + 2] + co[p + 2]
      idx += 1
  0

# Chroma HP prediction for YUV420 (nb = 4 blocks) and YUV422 (nb = 8).
-> jxr_propagate_hp42x(co, b, mode, nb) (i32[] i64 i64 i64) i64
  if mode == 0
    idx = 1 ## i64
    while idx < nb
      h = b + 16 + 15 * idx
      p = h - 15
      co[h + 3] = co[h + 3] + co[p + 3]
      co[h + 7] = co[h + 7] + co[p + 7]
      co[h + 11] = co[h + 11] + co[p + 11]
      idx += 2
  elsif mode == 1
    idx = 2
    while idx < nb
      h = b + 16 + 15 * idx
      p = h - 30
      co[h] = co[h] + co[p]
      co[h + 1] = co[h + 1] + co[p + 1]
      co[h + 2] = co[h + 2] + co[p + 2]
      idx += 1
  0

-> jxr_propagate_mb(pl, g, mode)
  co = pl.co ## i32[]
  nmb = pl.nmb
  clr = pl.clr
  if clr == 1 || clr == 2
    jxr_propagate_hp(co, g * 256, mode)
    nb = 4
    nb = 8 if clr == 2
    jxr_propagate_hp42x(co, (nmb + g) * 256, mode, nb)
    jxr_propagate_hp42x(co, (2 * nmb + g) * 256, mode, nb)
  else
    ch = 0
    while ch < pl.nch
      jxr_propagate_hp(co, (ch * nmb + g) * 256, mode)
      ch += 1

-> jxr_mb_hp(pl, src, br, g, mx, my, tw, freq, trim)
  st = pl.st ## i64[]
  co = pl.co ## i32[]
  rl = pl.rl ## i64[]
  hpin = pl.hpin ## i64[]
  cbpa = pl.cbp ## i64[]
  nch = pl.nch
  nmb = pl.nmb
  clr = pl.clr
  if mx == 0 && my == 0
    jxr_init_vlc2(st, 16)
    jxr_init_vlc2(st, 14)
    jxr_init_vlc2(st, 15)
    jxr_init_vlc2(st, 17)
    jxr_init_vlc2(st, 18)
    jxr_init_vlc2(st, 19)
    jxr_init_vlc(st, 5)
    jxr_init_vlc(st, 6)
    jxr_init_scan_hp(st)
    jxr_init_model(st, 108, 2)
  if mx % 16 == 0
    jxr_reset_totals(st, 165)
    jxr_reset_totals(st, 195)
  flex = 1
  flex = 0 if pl.bands == 1 || freq
  b1 = 0
  b2 = 0
  if nch >= 3
    b1 = (nmb + g) * 256
    b2 = (2 * nmb + g) * 256
  mode = jxr_mbhp_mode(co, g * 256, b1, b2, clr)
  smap = JXR_HP_SCAN_MAP ## i64[]
  lap0 = 0
  lap1 = 0
  idx = 0
  while idx < nch
    chroma = 0
    chroma = 1 if idx > 0
    nblocks = 4
    nblocks = 1 if chroma == 1 && clr == 1
    nblocks = 2 if chroma == 1 && clr == 2
    mbits = st[108 + chroma]
    cbp = cbpa[idx * nmb + g]
    b = (idx * nmb + g) * 256
    block = 0
    while block < nblocks * 4
      bpos = block
      bpos = smap[block] if nblocks == 4
      hb = b + 16 + 15 * bpos
      nnz = 0
      if (cbp & 1) != 0
        nnz = jxr_hp_block(src, br, st, co, hb, chroma, mode, mbits, rl, hpin)
      jxr_block_flex(src, br, co, hb, mbits, trim) if flex == 1
      if chroma == 0
        lap0 += nnz
      else
        lap1 += nnz
      cbp = cbp >> 1
      block += 1
    idx += 1
  jxr_propagate_mb(pl, g, mode) if !freq || pl.bands == 1
  mbhp = pl.mbhp ## i64[]
  hpmb = pl.hpmb ## i64[]
  mbhp[g] = mode
  hpmb[g * 2] = st[108]
  hpmb[g * 2 + 1] = st[109]
  jxr_update_model(st, 108, lap0, lap1, 2, clr, nch)
  jxr_adapt_hp(st) if mx % 16 == 0 || mx == tw - 1

-> jxr_mb_flex(pl, src, br, g, trim)
  co = pl.co ## i32[]
  hpmb = pl.hpmb ## i64[]
  smap = JXR_HP_SCAN_MAP ## i64[]
  nmb = pl.nmb
  clr = pl.clr
  idx = 0
  while idx < pl.nch
    chroma = 0
    chroma = 1 if idx > 0
    nblocks = 4
    nblocks = 1 if chroma == 1 && clr == 1
    nblocks = 2 if chroma == 1 && clr == 2
    mbits = hpmb[g * 2 + chroma]
    b = (idx * nmb + g) * 256
    block = 0
    while block < nblocks * 4
      bpos = block
      bpos = smap[block] if nblocks == 4
      jxr_block_flex(src, br, co, b + 16 + 15 * bpos, mbits, trim)
      block += 1
    idx += 1

# ---------------------------------------------------------------- tiles

-> jxr_start_code(src, br)
  a = jxr_get(src, br, 8)
  b = jxr_get(src, br, 8)
  c = jxr_get(src, br, 8)
  jxr_get(src, br, 8)
  jxr_fail("bad tile start code") if a != 0 || b != 0 || c != 1

-> jxr_seek(src, br, im, idx)
  t = im.itab
  jxr_fail("missing index table") if t == nil
  jxr_fail("bad index table entry") if idx >= t.size || t[idx] < 0
  br[0] = (br[1] + t[idx]) * 8

# jxrlib copies the LP quantiser objects (already scaled with the LP shift,
# 0 for chroma) when HP uses the LP QPs, instead of re-mapping the indices.
-> jxr_hp_from_lp(pl)
  return 1 if pl.hp_frame_lp == 1 && pl.hp_uni == 1
  return 1 if pl.hp_uni == 0 && pl.hp_use_lp == 1
  0

-> jxr_mb_qp(src, br, pl, g)
  qlp = 0
  qhp = 0
  if pl.bands != 3
    qlp = jxr_qp_index(src, br, pl.nlpq) if pl.nlpq > 1 && pl.lp_use_dc == 0
    if pl.bands != 2 && pl.nhpq > 1
      if pl.hp_use_lp == 0
        qhp = jxr_qp_index(src, br, pl.nhpq)
      else
        qhp = qlp
  lpqi = pl.lpqi ## i64[]
  hpqv = pl.hpqv ## i64[]
  hq = pl.hpq ## i64[]
  lpqi[g] = qlp
  hf = pl.hpfl ## i64[]
  hf[g] = jxr_hp_from_lp(pl)
  ch = 0
  while ch < pl.nch
    hpqv[ch * pl.nmb + g] = hq[ch * 16 + qhp]
    ch += 1

-> jxr_tile_spatial(src, br, im, tx, ty)
  jxr_start_code(src, br)
  trim = 0
  trim = jxr_get(src, br, 4) if im.trim_flex?
  ti = ty * im.tcols + tx
  pl = im.pl
  al = im.alpha
  bands = pl.bands
  jxr_tile_hdr_dc(src, br, pl, ti)
  if bands != 3
    jxr_tile_hdr_lp(src, br, pl, ti)
    jxr_tile_hdr_hp(src, br, pl, ti) if bands != 2
  if al != nil
    jxr_tile_hdr_dc(src, br, al, ti)
    if bands != 3
      jxr_tile_hdr_lp(src, br, al, ti)
      jxr_tile_hdr_hp(src, br, al, ti) if bands != 2
  tw = im.tcw[tx]
  th = im.trh[ty]
  x0 = im.tcp[tx]
  y0 = im.trp[ty]
  mbw = im.mbw
  nplanes = 1
  nplanes = 2 if al != nil
  my = 0
  while my < th
    mx = 0
    while mx < tw
      g = (y0 + my) * mbw + x0 + mx
      pi = 0
      while pi < nplanes
        p = pl
        p = al if pi == 1
        jxr_mb_qp(src, br, p, g)
        jxr_mb_dc(p, src, br, g, mx, my, tw)
        if p.bands != 3
          jxr_mb_lp(p, src, br, g, mx, my, tw)
          jxr_complete_dclp(p, g, mx, my)
          if p.bands != 2
            jxr_mb_cbp(p, src, br, g, mx, my)
            jxr_mb_hp(p, src, br, g, mx, my, tw, false, trim)
        else
          jxr_complete_dclp(p, g, mx, my)
        pi += 1
      mx += 1
    jxr_fail("truncated tile data") if br[2] != 0
    my += 1
  jxr_sync(br)

-> jxr_tiles_frequency(src, br, im)
  pl = im.pl
  al = im.alpha
  b = pl.bands
  nbands = 4
  nbands = 3 if b == 1
  nbands = 2 if b == 2
  nbands = 1 if b == 3
  jxr_fail("isolated bands not supported") if b == 4
  mbw = im.mbw
  band = 0
  while band < nbands
    ty = 0
    while ty < im.trows
      tx = 0
      while tx < im.tcols
        ti = ty * im.tcols + tx
        tw = im.tcw[tx]
        th = im.trh[ty]
        x0 = im.tcp[tx]
        y0 = im.trp[ty]
        it = im.itab
        if band == 3 && it != nil && ti * nbands + 3 < it.size && it[ti * nbands + 3] < 0
          # escaped FLEXBITS tile: just run the deferred HP prediction
          my = 0
          while my < th
            mx = 0
            while mx < tw
              g = (y0 + my) * mbw + x0 + mx
              jxr_propagate_mb(pl, g, pl.mbhp[g])
              jxr_propagate_mb(al, g, al.mbhp[g]) if al != nil
              mx += 1
            my += 1
        else
          jxr_seek(src, br, im, ti * nbands + band)
          jxr_start_code(src, br)
          trim = 0
          if band == 0
            jxr_tile_hdr_dc(src, br, pl, ti)
            jxr_tile_hdr_dc(src, br, al, ti) if al != nil
          elsif band == 1
            jxr_tile_hdr_lp(src, br, pl, ti)
            jxr_tile_hdr_lp(src, br, al, ti) if al != nil
          elsif band == 2
            jxr_tile_hdr_hp(src, br, pl, ti)
            jxr_tile_hdr_hp(src, br, al, ti) if al != nil
          else
            trim = jxr_get(src, br, 4) if im.trim_flex?
          my = 0
          while my < th
            mx = 0
            while mx < tw
              g = (y0 + my) * mbw + x0 + mx
              pi = 0
              while pi < 2
                p = pl
                p = al if pi == 1
                if p != nil
                  if band == 0
                    jxr_mb_dc(p, src, br, g, mx, my, tw)
                    jxr_complete_dclp(p, g, mx, my) if p.bands == 3
                  elsif band == 1
                    qlp = 0
                    qlp = jxr_qp_index(src, br, p.nlpq) if p.lp_use_dc == 0 && p.nlpq > 1
                    lq = p.lpqi ## i64[]
                    lq[g] = qlp
                    jxr_mb_lp(p, src, br, g, mx, my, tw)
                    jxr_complete_dclp(p, g, mx, my) if p.bands != 3
                  elsif band == 2
                    qhp = 0
                    if p.nhpq > 1
                      if p.hp_use_lp == 0
                        qhp = jxr_qp_index(src, br, p.nhpq)
                      else
                        qhp = p.lpqi[g]
                    hpqv = p.hpqv ## i64[]
                    hq = p.hpq ## i64[]
                    hf = p.hpfl ## i64[]
                    hf[g] = jxr_hp_from_lp(p)
                    ch = 0
                    while ch < p.nch
                      hpqv[ch * p.nmb + g] = hq[ch * 16 + qhp]
                      ch += 1
                    jxr_mb_cbp(p, src, br, g, mx, my)
                    jxr_mb_hp(p, src, br, g, mx, my, tw, true, 0)
                  else
                    jxr_mb_flex(p, src, br, g, trim)
                    jxr_propagate_mb(p, g, p.mbhp[g])
                pi += 1
              mx += 1
            jxr_fail("truncated tile data") if br[2] != 0
            my += 1
          jxr_sync(br)
        tx += 1
      ty += 1
    band += 1
  # without a FLEXBITS band the HP prediction already ran (bands == 1); with
  # DC/LP-only bands there is nothing to propagate.

-> jxr_decode_tiles(src, br, im)
  if im.freq?
    jxr_tiles_frequency(src, br, im)
  else
    ty = 0
    while ty < im.trows
      tx = 0
      while tx < im.tcols
        jxr_seek(src, br, im, ty * im.tcols + tx) if im.index_table?
        jxr_tile_spatial(src, br, im, tx, ty)
        tx += 1
      ty += 1
