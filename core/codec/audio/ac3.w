# core/codec/audio/ac3 — Dolby Digital (AC-3, ATSC A/52) and Dolby Digital Plus (E-AC-3,
# A/52 Annex E) decoder in Tungsten.
#
#   acodec_register("ac-3", …) and ("ec-3", …): cfg.extra is unused (the
#   frames are self-describing; MP4 dac3/dec3 boxes are not needed).
#   ac3_es_parse(bytes) splits a raw .ac3/.eac3 elementary stream into samples.
#
# AC-3: all channel modes incl. dual mono, LFE, block switching (256/512-point
# IMDCT, KBD window), coupling with phase flags, rematrixing, delta bit
# allocation, dither, dynamic range (line mode, as browsers and ffmpeg apply
# by default). E-AC-3: independent substream 0 (dependent substreams that
# add 7.1 channels are skipped, so a 7.1 stream plays as its 5.1 core), 1-6
# blocks per frame, frame-level exponent strategies, spectral extension.
# Not supported (the frame decodes as silence): adaptive hybrid transform
# (AHT) and enhanced coupling, both rare in practice.
#
# Output channels: L R C LFE Ls Rs order (mono is one channel; dual mono two).
# Tables are the spec's (A/52 Tables 7.x / E.x).

use core/codec/media
use core/codec/container/demux
use core/codec/container/demux_ts
use core/codec/container/demux_ogg

AC3_TAB = [nil]

-> ac3_tables
  return AC3_TAB[0] if AC3_TAB[0] != nil
  t = {}
  t[:band_start] = ac3_i64(AC3_BAND_START)
  t[:bin_band] = ac3_i64(AC3_BIN_BAND)
  t[:logadd] = ac3_i64(AC3_LOGADD)
  t[:hth] = ac3_i64(AC3_HTH)
  t[:bap] = ac3_i64(AC3_BAP)
  # IMDCT tables
  n = 512
  c1 = f64[128]
  s1 = f64[128]
  k = 0
  while k < 128
    a = ~2.0 * ~3.141592653589793 * (8 * k + 1).to_f / (8 * n).to_f
    c1[k] = ~0.0 - Math.cos(a)
    s1[k] = ~0.0 - Math.sin(a)
    k += 1
  c2 = f64[64]
  s2 = f64[64]
  k = 0
  while k < 64
    a = ~2.0 * ~3.141592653589793 * (8 * k + 1).to_f / (4 * n).to_f
    c2[k] = ~0.0 - Math.cos(a)
    s2[k] = ~0.0 - Math.sin(a)
    k += 1
  # FFT twiddles for 128 points: w[k] = exp(+j 2 pi k / 128)
  tw = f64[256]
  k = 0
  while k < 128
    a = ~2.0 * ~3.141592653589793 * k.to_f / ~128.0
    tw[k * 2] = Math.cos(a)
    tw[k * 2 + 1] = Math.sin(a)
    k += 1
  t[:c1] = c1
  t[:s1] = s1
  t[:c2] = c2
  t[:s2] = s2
  t[:tw] = tw
  t[:win] = ac3_kbd_window()
  # dynamic range gains
  dr = f64[256]
  i = 0
  while i < 256
    v = (i >> 5) - ((i >> 7) << 3) - 5
    dr[i] = (~2.0 ** v) * ((i & 31) | 32).to_f
    i += 1
  t[:drc] = dr
  AC3_TAB[0] = t
  t

-> ac3_i64(a)
  r = i64[a.size]
  i = 0
  while i < a.size
    r[i] = a[i]
    i += 1
  r

# Kaiser-Bessel-derived window, alpha 5, 256 samples (A/52 7.9.4).
-> ac3_kbd_window
  n = 256
  alpha2 = ~4.0 * (~5.0 * ~3.141592653589793 / n.to_f) * (~5.0 * ~3.141592653589793 / n.to_f)
  local = f64[n]
  sum = ~0.0
  i = 0
  while i < n
    tmp = (i * (n - i)).to_f * alpha2
    bessel = ~1.0
    j = 50
    while j > 0
      bessel = bessel * (tmp * ~0.25) / (j * j).to_f + ~1.0
      j -= 1
    sum = sum + bessel
    local[i] = sum
    i += 1
  sum = sum + ~1.0
  w = f64[n]
  i = 0
  while i < n
    w[i] = (local[i] / sum) ** ~0.5
    i += 1
  w

-> ac3_bits(d, st, n) (u8[] i64[] i64) i64
  return 0 if n == 0
  p = st[0]
  st[0] = p + n
  o = p >> 3
  v = 0 ## i64
  k = 0 ## i64
  while k < 5
    b = 0 ## i64
    b = d[o + k] if o + k < st[1]
    v = (v << 8) | b
    k += 1
  (v >> (40 - (p & 7) - n)) & ((1 << n) - 1)

-> ac3_sbits(d, st, n) (u8[] i64[] i64) i64
  v = 0 ## i64
  v = ac3_bits(d, st, n)
  return v - (1 << n) if v >= (1 << (n - 1))
  v

# Split a raw AC-3 / E-AC-3 stream into samples (one independent frame plus
# its dependent frames each).
-> ac3_es_parse(bytes)
  b = dm_bytes(bytes)
  n = b.size
  p = 0
  samples = []
  cfg = nil
  t = ~0.0
  while p + 7 <= n
    fi = ts_ac3_frame(b, p, n)
    if fi == nil
      p += 1
      next
    flen = fi[0]
    break if p + flen > n
    while p + flen + 6 <= n && b[p + flen] == 0x0B && b[p + flen + 1] == 0x77 && (b[p + flen + 5] >> 3) > 10 && (b[p + flen + 2] >> 6) == 1
      dl = ((((b[p + flen + 2] & 7) << 8) | b[p + flen + 3]) + 1) * 2
      break if p + flen + dl > n
      flen += dl
    if cfg == nil
      cfg = CodecConfig.new((b[p + 5] >> 3) > 10 ? "ec-3" : "ac-3")
      cfg.sample_rate = fi[1]
      cfg.channels = fi[2]
      cfg.timescale = fi[1]
      cfg.codec_string = cfg.codec
    d = fi[3].to_f / fi[1].to_f
    samples.push(MediaSample.new(dm_slice(b, p, flen), t, t, d, true))
    t += d
    p += flen
  raise MediaError.new("no AC-3 frames") if cfg == nil
  {cfg: cfg, samples: samples, duration: t}

+ Ac3Dec
  -> new(cfg)
    @tab = ac3_tables()
    @rate = cfg.sample_rate
    @nout = 0
    # per channel (0 = coupling, 1..5 fbw, 6 = LFE slot when present)
    @exps = i64[7 * 256]
    @bap = i64[7 * 256]
    @psd = i64[7 * 256]
    @bpsd = i64[7 * 64]
    @mask = i64[7 * 64]
    @coef = f64[7 * 256]
    @delay = f64[7 * 256]
    @tmp = f64[1024]
    @st = i64[4]
    @ci = i64[64]        # per channel state, see ac3 fields below
    @cplco = f64[7 * 20]
    @phs = i64[20]
    @cplbs = i64[20]     # coupling band sizes
    @spxbs = i64[20]
    @spx_nb = f64[7 * 20]
    @spx_sb = f64[7 * 20]
    @dba = i64[7 * 32]   # per channel: 0 mode, 1 nseg, then (off, len, val) * 8
    @expstr = i64[6 * 7]
    @cpl_strat = i64[6]
    @cpl_inuse = i64[6]
    @seed = 12345
    @gm = i64[8]         # mantissa group state
    @remat = i64[4]
    @drc = f64[2]
    @lastmode = -1
    @incpl = i64[8]
    @blksw = i64[8]
    @inspx = i64[8]
    @outb = f64[7 * 256]
    @spx = 0
    @first_cpl_leak = 1
    @last_error = nil

  rw :last_error

  -> flush
    nil

  -> reset
    i = 0
    while i < @delay.size
      @delay[i] = ~0.0
      i += 1
    nil

  -> decode(s)
    d = s.data
    n = d.size
    p = 0
    outs = []
    while p + 7 <= n
      fi = ts_ac3_frame(d, p, n)
      break if fi == nil
      flen = fi[0]
      break if p + flen > n
      bsid = d[p + 5] >> 3
      if bsid <= 10 || ((d[p + 2] >> 6) != 1 && ((d[p + 2] >> 3) & 7) == 0)
        blk = nil
        begin
          blk = frame(d, p, flen)
        rescue e
          @last_error = e.to_s
          blk = nil
        outs.push(blk) if blk != nil
      p += flen
    return nil if outs.size == 0
    if outs.size == 1
      outs[0].pts = s.pts
      return outs[0]
    tot = 0
    outs.each ->(b) tot += b.frames
    ch = outs[0].channels
    res = f32[tot * ch]
    o = 0
    outs.each ->(b)
      if b.channels == ch
        ac3_copy_f32(res, o, b.samples, b.frames * ch)
        o += b.frames * ch
    AudioBlock.new(res, o / ch, ch, outs[0].sample_rate, s.pts)

  # Decode one syncframe at d[p, p + flen) → AudioBlock.
  -> frame(d, p, flen)
    sub = u8[flen + 8]
    ac3_copy_u8(sub, 0, d, p, flen)
    st = @st
    st[0] = 16
    st[1] = flen
    bsid = sub[5] >> 3
    @eac3 = bsid > 10
    nblk = 6
    fscod = 0
    if !@eac3
      ac3_bits(sub, st, 16)        # crc1
      fscod = ac3_bits(sub, st, 2)
      ac3_bits(sub, st, 6)
      ac3_bits(sub, st, 5)
      ac3_bits(sub, st, 3)
      @acmod = ac3_bits(sub, st, 3)
      if @acmod == 2
        ac3_bits(sub, st, 2)
      else
        ac3_bits(sub, st, 2) if (@acmod & 1) != 0 && @acmod != 1
        ac3_bits(sub, st, 2) if (@acmod & 4) != 0
      @lfeon = ac3_bits(sub, st, 1)
      k = 0
      while k < (@acmod == 0 ? 2 : 1)
        ac3_bits(sub, st, 5)
        ac3_bits(sub, st, 8) if ac3_bits(sub, st, 1) == 1
        ac3_bits(sub, st, 8) if ac3_bits(sub, st, 1) == 1
        ac3_bits(sub, st, 7) if ac3_bits(sub, st, 1) == 1
        k += 1
      ac3_bits(sub, st, 2)
      ac3_bits(sub, st, 14) if ac3_bits(sub, st, 1) == 1
      ac3_bits(sub, st, 14) if ac3_bits(sub, st, 1) == 1
      if ac3_bits(sub, st, 1) == 1
        l = ac3_bits(sub, st, 6)
        st[0] += (l + 1) * 8
      @ftype = 2
    else
      @ftype = ac3_bits(sub, st, 2)
      ac3_bits(sub, st, 3)
      ac3_bits(sub, st, 11)
      fscod = ac3_bits(sub, st, 2)
      if fscod == 3
        raise MediaError.new("e-ac-3 reduced sample rates are not supported")
      nblk = [1, 2, 3, 6][ac3_bits(sub, st, 2)]
      @acmod = ac3_bits(sub, st, 3)
      @lfeon = ac3_bits(sub, st, 1)
      eac3_bsi(sub, st, nblk)
    @fscod = fscod
    @nfch = [2, 1, 2, 3, 3, 4, 4, 5][@acmod]
    @nch = @nfch + @lfeon
    @lfech = @lfeon == 1 ? @nfch + 1 : -1
    if @lastmode != @acmod * 2 + @lfeon
      reset()
      @lastmode = @acmod * 2 + @lfeon
    @nblk = nblk
    eac3_audfrm(sub, st) if @eac3
    pcm = f32[nblk * 256 * @nch]
    b = 0
    ok = true
    while b < nblk && ok
      ok = block(sub, st, b)
      emit_block(pcm, b) if ok
      b += 1
    rate = [48000, 44100, 32000][fscod]
    AudioBlock.new(pcm, nblk * 256, @nch, rate, ~0.0)

  # E-AC-3 bit stream information after acmod/lfeon (A/52 E.1.2.2).
  -> eac3_bsi(d, st, nblk)
    ac3_bits(d, st, 5)            # bsid
    k = 0
    while k < (@acmod == 0 ? 2 : 1)
      ac3_bits(d, st, 5)
      ac3_bits(d, st, 8) if ac3_bits(d, st, 1) == 1
      k += 1
    if @ftype == 1
      ac3_bits(d, st, 16) if ac3_bits(d, st, 1) == 1
    if ac3_bits(d, st, 1) == 1       # mixmdate
      if @acmod > 2
        ac3_bits(d, st, 2)
        if (@acmod & 1) != 0
          ac3_bits(d, st, 6)
        if (@acmod & 4) != 0
          ac3_bits(d, st, 6)
      if @lfeon == 1
        ac3_bits(d, st, 5) if ac3_bits(d, st, 1) == 1
      if @ftype == 0
        k = 0
        while k < (@acmod == 0 ? 2 : 1)
          ac3_bits(d, st, 6) if ac3_bits(d, st, 1) == 1
          k += 1
        ac3_bits(d, st, 6) if ac3_bits(d, st, 1) == 1
        mp = ac3_bits(d, st, 2)
        if mp == 1
          ac3_bits(d, st, 5)
        elsif mp == 2
          ac3_bits(d, st, 12)
        elsif mp == 3
          sz = (ac3_bits(d, st, 5) + 2) * 8
          st[0] += sz
        if @acmod < 2
          k = 0
          while k < (@acmod == 0 ? 2 : 1)
            ac3_bits(d, st, 14) if ac3_bits(d, st, 1) == 1
            k += 1
        if ac3_bits(d, st, 1) == 1
          k = 0
          while k < nblk
            ac3_bits(d, st, 5) if nblk == 1 || ac3_bits(d, st, 1) == 1
            k += 1
    if ac3_bits(d, st, 1) == 1       # infomdate
      ac3_bits(d, st, 3)
      ac3_bits(d, st, 2)
      ac3_bits(d, st, 4) if @acmod == 2
      ac3_bits(d, st, 2) if @acmod >= 6
      k = 0
      while k < (@acmod == 0 ? 2 : 1)
        ac3_bits(d, st, 8) if ac3_bits(d, st, 1) == 1
        k += 1
      ac3_bits(d, st, 1)          # sourcefscod (fscod != 3 here)
    ac3_bits(d, st, 1) if @ftype == 0 && nblk != 6
    if @ftype == 2 && (nblk == 6 || ac3_bits(d, st, 1) == 1)
      ac3_bits(d, st, 6)
    if ac3_bits(d, st, 1) == 1
      l = ac3_bits(d, st, 6)
      st[0] += (l + 1) * 8
    nil

  # E-AC-3 audio frame element (strategies for the whole frame).
  -> eac3_audfrm(d, st)
    nblk = @nblk
    expstr_ac3 = 1
    aht = 0
    if nblk == 6
      expstr_ac3 = ac3_bits(d, st, 1)
      aht = ac3_bits(d, st, 1)
    @snrstr = ac3_bits(d, st, 2)
    tpn = ac3_bits(d, st, 1)
    @blkswe = ac3_bits(d, st, 1)
    @dithe = ac3_bits(d, st, 1)
    @baie_syn = ac3_bits(d, st, 1)
    if @baie_syn == 0
      @sdecay = AC3_SLOW_DECAY[2]
      @fdecay = AC3_FAST_DECAY[1]
      @sgain = AC3_SLOW_GAIN[1]
      @dbknee = AC3_DB_PER_BIT[2]
      @floor = AC3_FLOOR[7]
    @fgain_syn = ac3_bits(d, st, 1)
    @dba_syn = ac3_bits(d, st, 1)
    @skip_syn = ac3_bits(d, st, 1)
    spxatt = ac3_bits(d, st, 1)
    ncpl = 0
    b = 0
    while b < nblk
      if @acmod > 1
        @cpl_strat[b] = b == 0 ? 1 : ac3_bits(d, st, 1)
        @cpl_inuse[b] = @cpl_strat[b] == 1 ? ac3_bits(d, st, 1) : @cpl_inuse[b - 1]
      else
        @cpl_strat[b] = 0
        @cpl_inuse[b] = 0
      ncpl += @cpl_inuse[b]
      b += 1
    if expstr_ac3 == 1
      b = 0
      while b < nblk
        ch = @cpl_inuse[b] == 1 ? 0 : 1
        while ch <= @nfch
          @expstr[b * 7 + ch] = ac3_bits(d, st, 2)
          ch += 1
        b += 1
    else
      ch = (@acmod > 1 && ncpl > 0) ? 0 : 1
      while ch <= @nfch
        f = ac3_bits(d, st, 5)
        b = 0
        while b < 6
          @expstr[b * 7 + ch] = AC3_FRM_EXPSTR[f * 6 + b]
          b += 1
        ch += 1
    if @lfeon == 1
      b = 0
      while b < nblk
        @expstr[b * 7 + @lfech] = ac3_bits(d, st, 1)
        b += 1
    if @ftype == 0 && (nblk == 6 || ac3_bits(d, st, 1) == 1)
      st[0] += 5 * @nfch
    if aht == 1
      ch = ncpl != 6 ? 1 : 0
      while ch <= @nch
        use = true
        b = 1
        while b < 6
          use = false if @expstr[b * 7 + ch] != 0 || (ch == 0 && @cpl_strat[b] == 1)
          b += 1
        raise MediaError.new("e-ac-3 AHT is not supported") if use && ac3_bits(d, st, 1) == 1
        ch += 1
    if @snrstr == 0
      cs = (ac3_bits(d, st, 6) - 15) << 4
      sn = (cs + ac3_bits(d, st, 4)) << 2
      ch = 0
      while ch <= @nch
        @ci[ch * 8 + 0] = sn
        ch += 1
    if tpn == 1
      ch = 1
      while ch <= @nfch
        st[0] += 18 if ac3_bits(d, st, 1) == 1
        ch += 1
    ch = 1
    while ch <= @nfch
      @ci[ch * 8 + 5] = (spxatt == 1 && ac3_bits(d, st, 1) == 1) ? ac3_bits(d, st, 5) : -1
      ch += 1
    if nblk > 1 && ac3_bits(d, st, 1) == 1
      fw = (st[1] - 2)
      lg = 0
      while (1 << (lg + 1)) <= fw
        lg += 1
      st[0] += (nblk - 1) * (4 + lg)
    ch = 1
    while ch <= @nfch
      @ci[ch * 8 + 6] = 1     # first spx coords
      @ci[ch * 8 + 7] = 1     # first cpl coords
      ch += 1
    @first_cpl_leak = 1
    nil

  # ci fields per channel (8 each): 0 snr offset, 1 fast gain, 2 start, 3 end,
  # 4 dither, 5 spx atten code, 6 first spx, 7 first cpl.
  # Further per-channel flags live in these instance arrays:
  -> block(d, st, blk)
    t = @tab
    nf = @nfch
    if !@eac3 || @blkswe == 1
      ch = 1
      while ch <= nf
        @blksw[ch] = ac3_bits(d, st, 1)
        ch += 1
    elsif blk == 0
      ch = 1
      while ch <= nf
        @blksw[ch] = 0
        ch += 1
    if !@eac3 || @dithe == 1
      ch = 1
      while ch <= nf
        @ci[ch * 8 + 4] = ac3_bits(d, st, 1)
        ch += 1
    elsif blk == 0
      ch = 1
      while ch <= nf
        @ci[ch * 8 + 4] = 1
        ch += 1
    # dynamic range
    k = @acmod == 0 ? 1 : 0
    while k >= 0
      if ac3_bits(d, st, 1) == 1
        @drc[k] = t[:drc][ac3_bits(d, st, 8)]
      elsif blk == 0
        @drc[k] = ~1.0
      k -= 1
    # spectral extension
    if @eac3 && (blk == 0 || ac3_bits(d, st, 1) == 1)
      @spx = ac3_bits(d, st, 1)
      spx_strategy(d, st, blk) if @spx == 1
    if !@eac3 || @spx != 1
      @spx = 0
      ch = 1
      while ch <= nf
        @inspx[ch] = 0
        @ci[ch * 8 + 6] = 1
        ch += 1
    spx_coords(d, st) if @spx == 1
    # coupling strategy
    cs = @eac3 ? @cpl_strat[blk] == 1 : ac3_bits(d, st, 1) == 1
    if cs
      @cpl_inuse[blk] = ac3_bits(d, st, 1) if !@eac3
      if @cpl_inuse[blk] == 1
        cpl_strategy(d, st, blk)
      else
        ch = 1
        while ch <= nf
          @incpl[ch] = 0
          @ci[ch * 8 + 7] = 1
          ch += 1
        @first_cpl_leak = @eac3 ? 1 : 0
        @phsinuse = 0
    elsif !@eac3
      raise MediaError.new("ac-3: no coupling strategy in block 0") if blk == 0
      @cpl_inuse[blk] = @cpl_inuse[blk - 1]
    cpl = @cpl_inuse[blk] == 1
    # coupling coordinates
    cpl_coords(d, st, blk) if cpl
    # rematrixing
    if @acmod == 2
      if (@eac3 && blk == 0) || ac3_bits(d, st, 1) == 1
        @nremat = 4
        cst = @ci[0 * 8 + 2]
        if cpl && cst <= 61
          @nremat -= 1 + (cst == 37 ? 1 : 0)
        elsif @spx == 1 && @spx_src <= 61
          @nremat -= 1
        k = 0
        while k < @nremat
          @remat[k] = ac3_bits(d, st, 1)
          k += 1
      elsif blk == 0
        @nremat = 0
    # exponent strategies
    ch = cpl ? 0 : 1
    while ch <= @nch
      if !@eac3
        @expstr[blk * 7 + ch] = ac3_bits(d, st, ch == @lfech ? 1 : 2)
      ch += 1
    # bandwidth
    ch = 1
    while ch <= nf
      @ci[ch * 8 + 2] = 0
      if @expstr[blk * 7 + ch] != 0
        if @incpl[ch] == 1
          @ci[ch * 8 + 3] = @ci[2]
        elsif @inspx[ch] == 1
          @ci[ch * 8 + 3] = @spx_src
        else
          bw = ac3_bits(d, st, 6)
          raise MediaError.new("ac-3: bad bandwidth code") if bw > 60
          @ci[ch * 8 + 3] = bw * 3 + 73
      ch += 1
    if @lfeon == 1
      @ci[@lfech * 8 + 2] = 0
      @ci[@lfech * 8 + 3] = 7
    # exponents
    ch = cpl ? 0 : 1
    while ch <= @nch
      es = @expstr[blk * 7 + ch]
      if es != 0
        start = @ci[ch * 8 + 2]
        stop = @ci[ch * 8 + 3]
        gs = 3 << (es - 1)
        ng = ch == 0 ? (stop - start) / gs : (stop + gs - 4) / gs
        absexp = ac3_bits(d, st, 4)
        absexp = absexp << 1 if ch == 0
        r = ac3_exps(d, st, es, ng, absexp, @exps, ch * 256 + (ch == 0 ? start : 1))
        raise MediaError.new("ac-3: bad exponents") if r != 0
        @exps[ch * 256] = absexp if ch != 0
        ac3_bits(d, st, 2) if ch != 0 && ch != @lfech
      ch += 1
    # bit allocation parameters
    if !@eac3 || @baie_syn == 1
      if ac3_bits(d, st, 1) == 1
        @sdecay = AC3_SLOW_DECAY[ac3_bits(d, st, 2)]
        @fdecay = AC3_FAST_DECAY[ac3_bits(d, st, 2)]
        @sgain = AC3_SLOW_GAIN[ac3_bits(d, st, 2)]
        @dbknee = AC3_DB_PER_BIT[ac3_bits(d, st, 2)]
        @floor = AC3_FLOOR[ac3_bits(d, st, 3)]
      elsif blk == 0
        raise MediaError.new("ac-3: no bit allocation info in block 0")
    if !@eac3 || blk == 0
      if (!@eac3 || @snrstr != 0) && ac3_bits(d, st, 1) == 1
        csnr = (ac3_bits(d, st, 6) - 15) << 4
        snr = 0
        first = cpl ? 0 : 1
        ch = first
        while ch <= @nch
          snr = (csnr + ac3_bits(d, st, 4)) << 2 if ch == first || !@eac3 || @snrstr == 2
          @ci[ch * 8] = snr
          @ci[ch * 8 + 1] = AC3_FAST_GAIN[ac3_bits(d, st, 3)] if !@eac3
          ch += 1
      elsif !@eac3 && blk == 0
        raise MediaError.new("ac-3: no snr offsets in block 0")
    if @eac3 && @fgain_syn == 1 && ac3_bits(d, st, 1) == 1
      ch = cpl ? 0 : 1
      while ch <= @nch
        @ci[ch * 8 + 1] = AC3_FAST_GAIN[ac3_bits(d, st, 3)]
        ch += 1
    elsif @eac3 && blk == 0
      ch = 0
      while ch <= @nch
        @ci[ch * 8 + 1] = AC3_FAST_GAIN[4]
        ch += 1
    if @eac3 && @ftype == 0 && ac3_bits(d, st, 1) == 1
      ac3_bits(d, st, 10)
    if cpl
      if (@eac3 && @first_cpl_leak == 1) || ac3_bits(d, st, 1) == 1
        @cfleak = ac3_bits(d, st, 3)
        @csleak = ac3_bits(d, st, 3)
      elsif !@eac3 && blk == 0
        raise MediaError.new("ac-3: no coupling leak in block 0")
      @first_cpl_leak = 0
    # delta bit allocation
    if (!@eac3 || @dba_syn == 1) && ac3_bits(d, st, 1) == 1
      ch = cpl ? 0 : 1
      while ch <= nf
        @dba[ch * 32] = ac3_bits(d, st, 2)
        ch += 1
      ch = cpl ? 0 : 1
      while ch <= nf
        if @dba[ch * 32] == 1
          ns = ac3_bits(d, st, 3) + 1
          @dba[ch * 32 + 1] = ns
          k = 0
          while k < ns
            @dba[ch * 32 + 2 + k * 3] = ac3_bits(d, st, 5)
            @dba[ch * 32 + 3 + k * 3] = ac3_bits(d, st, 4)
            @dba[ch * 32 + 4 + k * 3] = ac3_bits(d, st, 3)
            k += 1
        ch += 1
    elsif blk == 0
      ch = 0
      while ch <= @nch
        @dba[ch * 32] = 2
        ch += 1
    # bit allocation (always recomputed; it is cheap)
    ch = cpl ? 0 : 1
    while ch <= @nch
      start = @ci[ch * 8 + 2]
      stop = @ci[ch * 8 + 3]
      if stop > start
        ac3_psd(@exps, ch * 256, start, stop, @psd, @bpsd, ch * 64, t[:bin_band], t[:band_start], t[:logadd])
        fl = ch == 0 ? (@cfleak << 8) + 768 : 0
        sl = ch == 0 ? (@csleak << 8) + 768 : 0
        ac3_mask(@bpsd, ch * 64, start, stop, @ci[ch * 8 + 1], ch == @lfech ? 1 : 0, @sgain, @sdecay, @fdecay, @dbknee, fl, sl, t[:bin_band], t[:hth], @fscod, @dba, ch * 32, @mask)
        ac3_bapcalc(@mask, ch * 64, @psd, ch * 256, start, stop, @ci[ch * 8], @floor, t[:bap], t[:bin_band], t[:band_start], @bap)
      ch += 1
    if (!@eac3 || @skip_syn == 1) && ac3_bits(d, st, 1) == 1
      st[0] += ac3_bits(d, st, 9) * 8
    # mantissas
    gm = @gm
    gm[0] = 0
    gm[1] = 0
    gm[2] = 0
    got_cpl = false
    ch = 1
    while ch <= @nch
      dith = ch == @lfech ? 0 : @ci[ch * 8 + 4]
      @seed = ac3_mant(d, st, @bap, @exps, @coef, ch * 256, @ci[ch * 8 + 2], @ci[ch * 8 + 3], dith, gm, @seed)
      e = @ci[ch * 8 + 3]
      if ch != @lfech && @incpl[ch] == 1
        if !got_cpl
          @seed = ac3_mant(d, st, @bap, @exps, @coef, 0, @ci[2], @ci[3], 1, gm, @seed)
          uncouple()
          got_cpl = true
        e = @ci[3]
      ac3_zero(@coef, ch * 256 + e, 256 - e)
      ch += 1
    # undo dither in the coupling range for channels without dither
    if cpl
      ch = 1
      while ch <= nf
        if @ci[ch * 8 + 4] == 0 && @incpl[ch] == 1
          ac3_undither(@coef, ch * 256, @bap, 0, @ci[2], @ci[3])
        ch += 1
    if @acmod == 2
      e = @ci[8 + 3] < @ci[16 + 3] ? @ci[8 + 3] : @ci[16 + 3]
      ac3_rematrix(@coef, @remat, @nremat, e)
    # gains
    ch = 1
    while ch <= @nch
      g = @drc[(@acmod == 0 && ch == 1) ? 1 : 0]
      ac3_scale(@coef, ch * 256, 256, g)
      ch += 1
    apply_spx() if @spx == 1
    # IMDCT
    ch = 1
    while ch <= @nch
      sw = ch == @lfech ? 0 : @blksw[ch]
      ac3_imdct(@coef, ch * 256, @delay, ch * 256, @outb, @tmp, sw, t[:c1], t[:s1], t[:c2], t[:s2], t[:tw], t[:win])
      ch += 1
    true

  -> uncouple
    nf = @nfch
    bin = @ci[2]
    b = 0
    while b < @ncplbnd
      sz = @cplbs[b]
      ch = 1
      while ch <= nf
        if @incpl[ch] == 1
          f = @cplco[ch * 20 + b]
          f = ~0.0 - f if ch == 2 && @phs[b] == 1 && @acmod == 2
          ac3_cplcopy(@coef, ch * 256, bin, sz, f)
        ch += 1
      bin += sz
      b += 1
    nil

  -> cpl_strategy(d, st, blk)
    nf = @nfch
    raise MediaError.new("ac-3: coupling in mono") if @acmod < 2
    raise MediaError.new("e-ac-3: enhanced coupling is not supported") if @eac3 && ac3_bits(d, st, 1) == 1
    if @eac3 && @acmod == 2
      @incpl[1] = 1
      @incpl[2] = 1
    else
      ch = 1
      while ch <= nf
        @incpl[ch] = ac3_bits(d, st, 1)
        ch += 1
    @phsinuse = @acmod == 2 ? ac3_bits(d, st, 1) : 0
    cbeg = ac3_bits(d, st, 4)
    cend = @spx == 1 ? (@spx_src - 37) / 12 : ac3_bits(d, st, 4) + 3
    raise MediaError.new("ac-3: bad coupling range") if cbeg >= cend
    @ci[2] = cbeg * 12 + 37
    @ci[3] = cend * 12 + 37
    @ncplbnd = band_structure(d, st, blk, cbeg, cend, AC3_CPL_BAND_STRUCT, @cplbs, 0)
    nil

  # Band structure (coupling: kind 0, spx: kind 1); fills sizes, returns count.
  -> band_structure(d, st, blk, sb0, sb1, defaults, sizes, kind)
    @bstruct = [nil, nil] if @bstruct == nil
    if blk == 0 || @bstruct[kind] == nil
      @bstruct[kind] = defaults.copy(0, defaults.size)
    bs = @bstruct[kind]
    nsb = sb1 - sb0
    if !@eac3 || ac3_bits(d, st, 1) == 1
      k = 0
      while k < nsb - 1
        bs[sb0 + 1 + k] = ac3_bits(d, st, 1)
        k += 1
    nb = 0
    sizes[0] = 12
    k = 1
    while k < nsb
      if bs[sb0 + k] == 1
        sizes[nb] += 12
      else
        nb += 1
        sizes[nb] = 12
      k += 1
    nb + 1

  -> cpl_coords(d, st, blk)
    nf = @nfch
    any = false
    ch = 1
    while ch <= nf
      if @incpl[ch] == 1
        if (@eac3 && @ci[ch * 8 + 7] == 1) || ac3_bits(d, st, 1) == 1
          @ci[ch * 8 + 7] = 0
          any = true
          mstr = 3 * ac3_bits(d, st, 2)
          b = 0
          while b < @ncplbnd
            ce = ac3_bits(d, st, 4)
            cm = ac3_bits(d, st, 4)
            m = ce == 15 ? cm.to_f / ~16.0 : (cm + 16).to_f / ~32.0
            @cplco[ch * 20 + b] = m * ~8.0 / (1 << (ce + mstr)).to_f
            b += 1
        elsif blk == 0
          raise MediaError.new("ac-3: no coupling coordinates in block 0")
      else
        @ci[ch * 8 + 7] = 1
      ch += 1
    if @acmod == 2 && any
      b = 0
      while b < @ncplbnd
        @phs[b] = @phsinuse == 1 ? ac3_bits(d, st, 1) : 0
        b += 1
    nil

  -> spx_strategy(d, st, blk)
    nf = @nfch
    if @acmod == 1
      @inspx[1] = 1
    else
      ch = 1
      while ch <= nf
        @inspx[ch] = ac3_bits(d, st, 1)
        ch += 1
    dst = ac3_bits(d, st, 2)
    sb0 = ac3_bits(d, st, 3) + 2
    sb0 += sb0 - 7 if sb0 > 7
    sb1 = ac3_bits(d, st, 3) + 5
    sb1 += sb1 - 7 if sb1 > 7
    raise MediaError.new("e-ac-3: bad spx range") if sb0 >= sb1
    @spx_dst = dst * 12 + 25
    @spx_src = sb0 * 12 + 25
    @spx_end = sb1 * 12 + 25
    raise MediaError.new("e-ac-3: bad spx copy start") if @spx_dst >= @spx_src
    @nspxbnd = band_structure(d, st, blk, sb0, sb1, AC3_SPX_BAND_STRUCT, @spxbs, 1)
    nil

  -> spx_coords(d, st)
    nf = @nfch
    ch = 1
    while ch <= nf
      if @inspx[ch] == 1
        if @ci[ch * 8 + 6] == 1 || ac3_bits(d, st, 1) == 1
          @ci[ch * 8 + 6] = 0
          blend = ac3_bits(d, st, 5).to_f / ~32.0
          mstr = ac3_bits(d, st, 2) * 3
          bin = @spx_src
          b = 0
          while b < @nspxbnd
            bsz = @spxbs[b]
            nr = (bin + (bsz >> 1)).to_f / @spx_end.to_f - blend
            nr = ~0.0 if nr < ~0.0
            nr = ~1.0 if nr > ~1.0
            nb = (~3.0 * nr) ** ~0.5
            sb = (~1.0 - nr) ** ~0.5
            bin += bsz
            ce = ac3_bits(d, st, 4)
            cm = ac3_bits(d, st, 2)
            cm = ce == 15 ? cm << 1 : cm + 4
            co = cm.to_f * (~2.0 ** (25 - ce - mstr - 23))
            @spx_nb[ch * 20 + b] = nb * co
            @spx_sb[ch * 20 + b] = sb * co
            b += 1
      else
        @ci[ch * 8 + 6] = 1
      ch += 1
    nil

  -> apply_spx
    nf = @nfch
    # copy sections (wrap back to the copy start when reaching the source start)
    sizes = []
    wrap = []
    bin = @spx_dst
    b = 0
    while b < @nspxbnd
      bsz = @spxbs[b]
      w = b == 0
      if bin + bsz > @spx_src
        sizes.push(bin - @spx_dst)
        bin = @spx_dst
        w = true
      wrap.push(w)
      i = 0
      while i < bsz
        if bin == @spx_src
          sizes.push(bin - @spx_dst)
          bin = @spx_dst
        cs = bsz - i
        cs = @spx_src - bin if @spx_src - bin < cs
        bin += cs
        i += cs
      b += 1
    sizes.push(bin - @spx_dst)
    ch = 1
    while ch <= nf
      if @inspx[ch] == 1
        base = ch * 256
        bin = @spx_src
        sizes.each ->(sz)
          ac3_fcopy(@coef, base + bin, @coef, base + @spx_dst, sz)
          bin += sz
        rms = []
        bin = @spx_src
        b = 0
        while b < @nspxbnd
          rms.push(ac3_rms(@coef, base + bin, @spxbs[b]))
          bin += @spxbs[b]
          b += 1
        at = @ci[ch * 8 + 5]
        if at >= 0
          bin = @spx_src - 2
          b = 0
          while b < @nspxbnd
            if wrap[b]
              k = 0
              while k < 5
                kk = k == 3 ? 1 : (k == 4 ? 0 : k)
                @coef[base + bin + k] = @coef[base + bin + k] * (~2.0 ** ((kk + 1) * (at + 1)).to_f / ~-15.0)
                k += 1
            bin += @spxbs[b]
            b += 1
        bin = @spx_src
        b = 0
        while b < @nspxbnd
          ns = @spx_nb[ch * 20 + b] * rms[b]
          ss = @spx_sb[ch * 20 + b]
          @seed = ac3_spx_band(@coef, base + bin, @spxbs[b], ns, ss, @seed)
          bin += @spxbs[b]
          b += 1
      ch += 1
    nil

  # Interleave block b's 256 samples into pcm in L R C LFE Ls Rs order.
  -> emit_block(pcm, b)
    nch = @nch
    ord = ac3_out_order(@acmod, @lfeon)
    o = 0
    while o < nch
      ac3_interleave(@outb, ord[o] * 256, pcm, b * 256 * nch + o, nch)
      o += 1
    nil

# Decoded channel index (1-based, LFE last) for each output position.
-> ac3_out_order(acmod, lfe)
  base = [[1, 2], [1], [1, 2], [1, 3, 2], [1, 2, 3], [1, 3, 2, 4], [1, 2, 3, 4], [1, 3, 2, 4, 5]][acmod]
  return base if lfe == 0
  nf = base.size
  l = nf + 1
  return [1, l] if acmod == 1
  return [1, 2, l] if acmod == 2 || acmod == 0
  return [1, 3, 2, l] if acmod == 3
  return [1, 2, l, 3] if acmod == 4
  return [1, 3, 2, l, 4] if acmod == 5
  return [1, 2, l, 3, 4] if acmod == 6
  [1, 3, 2, l, 4, 5]

-> ac3_get(a, i)
  a[i]

-> ac3_set(a, i, v)
  a[i] = v

-> ac3_copy_u8(dst, doff, src, soff, n) (u8[] i64 u8[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[doff + i] = src[soff + i]
    i += 1
  n

-> ac3_copy_f32(dst, doff, src, n) (f32[] i64 f32[] i64) i64
  i = 0 ## i64
  while i < n
    dst[doff + i] = src[i]
    i += 1
  n

-> ac3_fcopy(dst, doff, src, soff, n) (f64[] i64 f64[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[doff + i] = src[soff + i]
    i += 1
  n

-> ac3_zero(c, off, n) (f64[] i64 i64) i64
  i = 0 ## i64
  while i < n
    c[off + i] = ~0.0
    i += 1
  0

-> ac3_rms(c, off, n) (f64[] i64 i64) f64
  s = ~0.0
  i = 0 ## i64
  while i < n
    s = s + c[off + i] * c[off + i]
    i += 1
  (s / n.to_f) ** ~0.5

-> ac3_spx_band(c, off, n, ns, ss, seed) (f64[] i64 i64 f64 f64 i64) i64
  i = 0 ## i64
  while i < n
    seed = (seed * 1103515245 + 12345) & 0xFFFFFFFF
    r = (seed - 2147483648).to_f / ~2147483648.0
    c[off + i] = c[off + i] * ss + r * ns
    i += 1
  seed

-> ac3_interleave(src, soff, dst, doff, step) (f64[] i64 f32[] i64 i64) i64
  i = 0 ## i64
  while i < 256
    v = src[soff + i]
    v = ~1.0 if v > ~1.0
    v = ~-1.0 if v < ~-1.0
    dst[doff + i * step] = v ## f32
    i += 1
  0

# Unpack ngrps 7-bit exponent groups → absolute exponents (A/52 7.1.3).
-> ac3_exps(d, st, es, ngrps, absexp, out, off) (u8[] i64[] i64 i64 i64 i64[] i64) i64
  gs = es == 3 ? 4 : es
  prev = absexp
  j = off
  g = 0 ## i64
  while g < ngrps
    v = ac3_bits(d, st, 7)
    return 1 if v >= 125
    k = 0 ## i64
    while k < 3
      dx = 0 ## i64
      if k == 0
        dx = v / 25
      elsif k == 1
        dx = (v % 25) / 5
      else
        dx = v % 5
      prev += dx - 2
      return 1 if prev < 0 || prev > 24
      m = 0 ## i64
      while m < gs
        out[j] = prev
        j += 1
        m += 1
      k += 1
    g += 1
  0

-> ac3_psd(exps, eo, start, stop, psd, bpsd, bo, binband, bstart, logadd) (i64[] i64 i64 i64 i64[] i64[] i64 i64[] i64[] i64[]) i64
  bin = start
  while bin < stop
    psd[eo + bin] = 3072 - (exps[eo + bin] << 7)
    bin += 1
  bin = start
  while bin < stop && bin < 28
    bpsd[bo + bin] = psd[eo + bin]
    bin += 1
  return 0 if bin >= stop
  band = binband[bin]
  while true
    v = psd[eo + bin]
    bin += 1
    be = bstart[band + 1]
    be = stop if be > stop
    while bin < be
      p = psd[eo + bin]
      mx = v > p ? v : p
      adr = mx - ((v + p + 1) >> 1)
      adr = 255 if adr > 255
      v = mx + logadd[adr]
      bin += 1
    bpsd[bo + band] = v
    band += 1
    break if stop <= bstart[band]
  0

-> ac3_lowcomp1(a, b0, b1, c) (i64 i64 i64 i64) i64
  return c if b0 + 256 == b1
  if b0 > b1
    a -= 64
    a = 0 if a < 0
  a

-> ac3_lowcomp(a, b0, b1, band) (i64 i64 i64 i64) i64
  return ac3_lowcomp1(a, b0, b1, 384) if band < 7
  return ac3_lowcomp1(a, b0, b1, 320) if band < 20
  a -= 128
  a < 0 ? 0 : a

-> ac3_mask(bpsd, bo, start, stop, fgain, lfe, sgain, sdecay, fdecay, dbknee, cfl, csl, binband, hth, fscod, dba, dbo, mask) (i64[] i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64 i64[] i64[] i64 i64[] i64 i64[]) i64
  exc = i64[64]
  bs = binband[start]
  be = binband[stop - 1] + 1
  lowcomp = 0 ## i64
  fastleak = 0 ## i64
  slowleak = 0 ## i64
  bgn = 0 ## i64
  if bs == 0
    lowcomp = ac3_lowcomp1(lowcomp, bpsd[bo], bpsd[bo + 1], 384)
    exc[0] = bpsd[bo] - fgain - lowcomp
    lowcomp = ac3_lowcomp1(lowcomp, bpsd[bo + 1], bpsd[bo + 2], 384)
    exc[1] = bpsd[bo + 1] - fgain - lowcomp
    bgn = 7
    band = 2 ## i64
    while band < 7
      notlfe6 = !(lfe == 1 && band == 6)
      lowcomp = ac3_lowcomp1(lowcomp, bpsd[bo + band], bpsd[bo + band + 1], 384) if notlfe6
      fastleak = bpsd[bo + band] - fgain
      slowleak = bpsd[bo + band] - sgain
      exc[band] = fastleak - lowcomp
      if notlfe6 && bpsd[bo + band] <= bpsd[bo + band + 1]
        bgn = band + 1
        break
      band += 1
    e1 = be < 22 ? be : 22
    band = bgn
    while band < e1
      lowcomp = ac3_lowcomp(lowcomp, bpsd[bo + band], bpsd[bo + band + 1], band) if !(lfe == 1 && band == 6)
      fastleak -= fdecay
      x = bpsd[bo + band] - fgain
      fastleak = x if x > fastleak
      slowleak -= sdecay
      x = bpsd[bo + band] - sgain
      slowleak = x if x > slowleak
      x = fastleak - lowcomp
      exc[band] = x > slowleak ? x : slowleak
      band += 1
    bgn = 22
  else
    bgn = bs
    fastleak = cfl
    slowleak = csl
  band = bgn
  while band < be
    fastleak -= fdecay
    x = bpsd[bo + band] - fgain
    fastleak = x if x > fastleak
    slowleak -= sdecay
    x = bpsd[bo + band] - sgain
    slowleak = x if x > slowleak
    exc[band] = fastleak > slowleak ? fastleak : slowleak
    band += 1
  band = bs
  while band < be
    tmp = dbknee - bpsd[bo + band]
    exc[band] += tmp >> 2 if tmp > 0
    h = hth[band * 3 + fscod]
    mask[bo + band] = h > exc[band] ? h : exc[band]
    band += 1
  mode = dba[dbo]
  if mode == 0 || mode == 1
    band = bs
    ns = dba[dbo + 1]
    sg = 0 ## i64
    while sg < ns && sg < 8
      band += dba[dbo + 2 + sg * 3]
      ln = dba[dbo + 3 + sg * 3]
      v = dba[dbo + 4 + sg * 3]
      delta = v >= 4 ? (v - 3) * 128 : (v - 4) * 128
      k = 0 ## i64
      while k < ln && band < 50
        mask[bo + band] += delta
        band += 1
        k += 1
      sg += 1
  0

-> ac3_bapcalc(mask, mo, psd, po, start, stop, snr, floor, baptab, binband, bstart, bap) (i64[] i64 i64[] i64 i64 i64 i64 i64 i64[] i64[] i64[] i64[]) i64
  bin = start
  band = binband[start]
  while true
    m = mask[mo + band] - snr - floor
    m = 0 if m < 0
    m = (m & 0x1FE0) + floor
    be = bstart[band + 1]
    be = stop if be > stop
    while bin < be
      adr = (psd[po + bin] - m) >> 5
      adr = 0 if adr < 0
      adr = 63 if adr > 63
      bap[po + bin] = baptab[adr]
      bin += 1
    break if stop <= be
    band += 1
  0

# Mantissas of one channel (bins start..stop) → coefficients (A/52 7.3).
# gm: grouped mantissa state (0 b1 count, 1 b2 count, 2 b4 count, 3..7 values).
-> ac3_mant(d, st, bap, exps, coef, off, start, stop, dith, gm, seed) (u8[] i64[] i64[] i64[] f64[] i64 i64 i64 i64 i64[] i64) i64
  bin = start
  while bin < stop
    b = bap[off + bin]
    m = ~0.0
    q = 0 ## i64
    g = 0 ## i64
    nb = 0 ## i64
    if b == 0
      if dith == 1
        seed = (seed * 1103515245 + 12345) & 0xFFFFFFFF
        m = ((seed >> 8) & 0xFFFF).to_f / ~46341.0 - ~0.707
    elsif b == 1
      if gm[0] > 0
        gm[0] -= 1
        q = gm[3 + gm[0]]
      else
        g = ac3_bits(d, st, 5)
        q = g / 9
        gm[4] = (g % 9) / 3
        gm[3] = g % 3
        gm[0] = 2
      m = ((q - 1) * 2).to_f / ~3.0
    elsif b == 2
      if gm[1] > 0
        gm[1] -= 1
        q = gm[5 + gm[1]]
      else
        g = ac3_bits(d, st, 7)
        q = g / 25
        gm[6] = (g % 25) / 5
        gm[5] = g % 5
        gm[1] = 2
      m = ((q - 2) * 2).to_f / ~5.0
    elsif b == 3
      q = ac3_bits(d, st, 3)
      m = (q * 2 - 6).to_f / ~7.0
    elsif b == 4
      if gm[2] > 0
        gm[2] = 0
        q = gm[7]
      else
        g = ac3_bits(d, st, 7)
        q = g / 11
        gm[7] = g % 11
        gm[2] = 1
      m = (q * 2 - 10).to_f / ~11.0
    elsif b == 5
      q = ac3_bits(d, st, 4)
      m = (q * 2 - 14).to_f / ~15.0
    else
      nb = b - 1
      nb = 14 if b == 14
      nb = 16 if b >= 15
      q = ac3_bits(d, st, nb)
      q -= 1 << nb if q >= (1 << (nb - 1))
      m = q.to_f / (1 << (nb - 1)).to_f
    e = exps[off + bin]
    coef[off + bin] = m / (1 << e).to_f
    bin += 1
  seed

-> ac3_undither(coef, off, bap, cplo, start, stop) (f64[] i64 i64[] i64 i64 i64) i64
  i = start
  while i < stop
    coef[off + i] = ~0.0 if bap[cplo + i] == 0
    i += 1
  0

-> ac3_cplcopy(coef, off, bin, n, f) (f64[] i64 i64 i64 f64) i64
  i = 0 ## i64
  while i < n
    coef[off + bin + i] = coef[bin + i] * f
    i += 1
  0

-> ac3_rematrix(coef, flags, nb, stop) (f64[] i64[] i64 i64) i64
  bands = i64[5]
  bands[0] = 13
  bands[1] = 25
  bands[2] = 37
  bands[3] = 61
  bands[4] = 253
  b = 0 ## i64
  while b < nb
    if flags[b] == 1
      e = bands[b + 1] < stop ? bands[b + 1] : stop
      i = bands[b]
      while i < e
        l = coef[256 + i]
        r = coef[512 + i]
        coef[256 + i] = l + r
        coef[512 + i] = l - r
        i += 1
    b += 1
  0

-> ac3_scale(coef, off, n, g) (f64[] i64 i64 f64) i64
  i = 0 ## i64
  while i < n
    coef[off + i] = coef[off + i] * g
    i += 1
  0

# In-place radix-2 complex inverse FFT of n points (re/im interleaved),
# twiddles tw for 128 points (stride 128/n).
-> ac3_ifft(x, n, tw) (f64[] i64 f64[]) i64
  j = 0 ## i64
  i = 0 ## i64
  while i < n
    if i < j
      tr = x[i * 2]
      ti = x[i * 2 + 1]
      x[i * 2] = x[j * 2]
      x[i * 2 + 1] = x[j * 2 + 1]
      x[j * 2] = tr
      x[j * 2 + 1] = ti
    m = n >> 1
    while m >= 1 && (j & m) != 0
      j = j ^ m
      m = m >> 1
    j = j | m
    i += 1
  len = 2 ## i64
  while len <= n
    half = len >> 1
    step = 128 / len
    s = 0 ## i64
    while s < n
      k = 0 ## i64
      while k < half
        wr = tw[k * step * 2]
        wi = tw[k * step * 2 + 1]
        a = (s + k) * 2
        b = (s + k + half) * 2
        br = x[b] * wr - x[b + 1] * wi
        bi = x[b] * wi + x[b + 1] * wr
        x[b] = x[a] - br
        x[b + 1] = x[a + 1] - bi
        x[a] = x[a] + br
        x[a + 1] = x[a + 1] + bi
        k += 1
      s += len
    len = len << 1
  0

# A/52 7.9.4 IMDCT with KBD windowing and overlap-add. coef[co..co+255] →
# 256 output samples in delay[do_ + 1792 ...] (a staging area), keeping the
# second half in delay[do_ ...] for the next block.
-> ac3_imdct(coef, co, delay, dlo, outb, x, sw, c1, s1, c2, s2, tw, w) (f64[] i64 f64[] i64 f64[] f64[] i64 f64[] f64[] f64[] f64[] f64[] f64[]) i64
  # x: 0..255 complex work (re/im), 256..767 windowed output
  ob = 256
  if sw == 0
    k = 0 ## i64
    while k < 128
      xr = coef[co + 255 - 2 * k]
      xi = coef[co + 2 * k]
      x[k * 2] = xr * c1[k] - xi * s1[k]
      x[k * 2 + 1] = xr * s1[k] + xi * c1[k]
      k += 1
    ac3_ifft(x, 128, tw)
    n = 0 ## i64
    while n < 128
      yr = x[n * 2] * c1[n] - x[n * 2 + 1] * s1[n]
      yi = x[n * 2] * s1[n] + x[n * 2 + 1] * c1[n]
      x[n * 2] = yr
      x[n * 2 + 1] = yi
      n += 1
    n = 0
    while n < 64
      x[ob + 2 * n] = ~0.0 - x[(64 + n) * 2 + 1] * w[2 * n]
      x[ob + 2 * n + 1] = x[(63 - n) * 2] * w[2 * n + 1]
      x[ob + 128 + 2 * n] = ~0.0 - x[n * 2] * w[128 + 2 * n]
      x[ob + 128 + 2 * n + 1] = x[(127 - n) * 2 + 1] * w[128 + 2 * n + 1]
      x[ob + 256 + 2 * n] = ~0.0 - x[(64 + n) * 2] * w[255 - 2 * n]
      x[ob + 256 + 2 * n + 1] = x[(63 - n) * 2 + 1] * w[255 - 2 * n - 1]
      x[ob + 384 + 2 * n] = x[n * 2 + 1] * w[127 - 2 * n]
      x[ob + 384 + 2 * n + 1] = ~0.0 - x[(127 - n) * 2] * w[127 - 2 * n - 1]
      n += 1
  else
    # two 256-point transforms on even / odd coefficients; z1 in x[0..127], z2 in x[128..255]
    k = 0 ## i64
    while k < 64
      ar = coef[co + 2 * (127 - 2 * k)]
      ai = coef[co + 2 * (2 * k)]
      x[k * 2] = ar * c2[k] - ai * s2[k]
      x[k * 2 + 1] = ar * s2[k] + ai * c2[k]
      br = coef[co + 2 * (127 - 2 * k) + 1]
      bi = coef[co + 2 * (2 * k) + 1]
      x[128 + k * 2] = br * c2[k] - bi * s2[k]
      x[128 + k * 2 + 1] = br * s2[k] + bi * c2[k]
      k += 1
    ac3_ifft_at(x, 0, 64, tw)
    ac3_ifft_at(x, 128, 64, tw)
    n = 0 ## i64
    while n < 64
      r1 = x[n * 2] * c2[n] - x[n * 2 + 1] * s2[n]
      i1 = x[n * 2] * s2[n] + x[n * 2 + 1] * c2[n]
      x[n * 2] = r1
      x[n * 2 + 1] = i1
      r2 = x[128 + n * 2] * c2[n] - x[128 + n * 2 + 1] * s2[n]
      i2 = x[128 + n * 2] * s2[n] + x[128 + n * 2 + 1] * c2[n]
      x[128 + n * 2] = r2
      x[128 + n * 2 + 1] = i2
      n += 1
    n = 0
    while n < 64
      x[ob + 2 * n] = ~0.0 - x[n * 2 + 1] * w[2 * n]
      x[ob + 2 * n + 1] = x[(63 - n) * 2] * w[2 * n + 1]
      x[ob + 128 + 2 * n] = ~0.0 - x[n * 2] * w[128 + 2 * n]
      x[ob + 128 + 2 * n + 1] = x[(63 - n) * 2 + 1] * w[128 + 2 * n + 1]
      x[ob + 256 + 2 * n] = x[128 + n * 2] * w[255 - 2 * n]
      x[ob + 256 + 2 * n + 1] = ~0.0 - x[128 + (63 - n) * 2 + 1] * w[255 - 2 * n - 1]
      x[ob + 384 + 2 * n] = x[128 + n * 2 + 1] * w[127 - 2 * n]
      x[ob + 384 + 2 * n + 1] = ~0.0 - x[128 + (63 - n) * 2] * w[127 - 2 * n - 1]
      n += 1
  n = 0 ## i64
  while n < 256
    outb[dlo + n] = ~2.0 * (x[ob + n] + delay[dlo + n])
    delay[dlo + n] = x[ob + 256 + n]
    n += 1
  0

-> ac3_ifft_at(x, base, n, tw) (f64[] i64 i64 f64[]) i64
  tmp = f64[n * 2]
  i = 0 ## i64
  while i < n * 2
    tmp[i] = x[base + i]
    i += 1
  ac3_ifft(tmp, n, tw)
  i = 0
  while i < n * 2
    x[base + i] = tmp[i]
    i += 1
  0

acodec_register("ac-3", ->(cfg) Ac3Dec.new(cfg))
acodec_register("ec-3", ->(cfg) Ac3Dec.new(cfg))
es_parser_register(:ac3, ->(b) ac3_es_parse(b))

# ---- tables (A/52) ----

AC3_BAND_START = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 31, 34, 37, 40, 43, 46, 49, 55, 61, 67, 73, 79, 85, 97, 109, 121, 133, 157, 181, 205, 229, 253]
AC3_BIN_BAND = [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 28, 28, 29, 29, 29, 30, 30, 30, 31, 31, 31, 32, 32, 32, 33, 33, 33, 34, 34, 34, 35, 35, 35, 35, 35, 35, 36, 36, 36, 36, 36, 36, 37, 37, 37, 37, 37, 37, 38, 38, 38, 38, 38, 38, 39, 39, 39, 39, 39, 39, 40, 40, 40, 40, 40, 40, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 41, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 42, 43, 43, 43, 43, 43, 43, 43, 43, 43, 43, 43, 43, 44, 44, 44, 44, 44, 44, 44, 44, 44, 44, 44, 44, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 45, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 46, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 47, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 48, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49, 49]
AC3_LOGADD = [64, 63, 62, 61, 60, 59, 58, 57, 56, 55, 54, 53, 52, 52, 51, 50, 49, 48, 47, 47, 46, 45, 44, 44, 43, 42, 41, 41, 40, 39, 38, 38, 37, 36, 36, 35, 35, 34, 33, 33, 32, 32, 31, 30, 30, 29, 29, 28, 28, 27, 27, 26, 26, 25, 25, 24, 24, 23, 23, 22, 22, 21, 21, 21, 20, 20, 19, 19, 19, 18, 18, 18, 17, 17, 17, 16, 16, 16, 15, 15, 15, 14, 14, 14, 13, 13, 13, 13, 12, 12, 12, 12, 11, 11, 11, 11, 10, 10, 10, 10, 10, 9, 9, 9, 9, 9, 8, 8, 8, 8, 8, 8, 7, 7, 7, 7, 7, 7, 6, 6, 6, 6, 6, 6, 6, 6, 5, 5, 5, 5, 5, 5, 5, 5, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 4, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
AC3_HTH = [1232, 1264, 1408, 1232, 1264, 1408, 1088, 1120, 1200, 1024, 1040, 1104, 992, 992, 1056, 960, 976, 1008, 944, 960, 992, 944, 944, 976, 928, 944, 960, 928, 928, 944, 928, 928, 944, 928, 928, 944, 928, 928, 928, 912, 928, 928, 912, 912, 928, 912, 912, 928, 896, 912, 928, 896, 896, 928, 880, 896, 928, 880, 896, 928, 864, 880, 912, 864, 880, 912, 848, 864, 912, 848, 864, 912, 832, 848, 896, 832, 848, 896, 816, 832, 896, 800, 832, 880, 784, 800, 864, 768, 784, 848, 752, 768, 832, 752, 752, 816, 752, 752, 800, 752, 752, 784, 768, 752, 768, 784, 768, 752, 832, 800, 752, 912, 848, 752, 992, 912, 768, 1056, 992, 784, 1120, 1056, 816, 1168, 1104, 848, 1184, 1184, 960, 1120, 1168, 1040, 1088, 1120, 1136, 1088, 1088, 1184, 1312, 1152, 1120, 2048, 1584, 1088, 2112, 2112, 1104, 2112, 2112, 1248]
AC3_BAP = [0, 1, 1, 1, 1, 1, 2, 2, 3, 3, 3, 4, 4, 5, 5, 6, 6, 6, 6, 7, 7, 7, 7, 8, 8, 8, 8, 9, 9, 9, 9, 10, 10, 10, 10, 11, 11, 11, 11, 12, 12, 12, 12, 13, 13, 13, 13, 14, 14, 14, 14, 14, 14, 14, 14, 15, 15, 15, 15, 15, 15, 15, 15, 15]
AC3_FRAME_SIZE = [64, 69, 96, 64, 70, 96, 80, 87, 120, 80, 88, 120, 96, 104, 144, 96, 105, 144, 112, 121, 168, 112, 122, 168, 128, 139, 192, 128, 140, 192, 160, 174, 240, 160, 175, 240, 192, 208, 288, 192, 209, 288, 224, 243, 336, 224, 244, 336, 256, 278, 384, 256, 279, 384, 320, 348, 480, 320, 349, 480, 384, 417, 576, 384, 418, 576, 448, 487, 672, 448, 488, 672, 512, 557, 768, 512, 558, 768, 640, 696, 960, 640, 697, 960, 768, 835, 1152, 768, 836, 1152, 896, 975, 1344, 896, 976, 1344, 1024, 1114, 1536, 1024, 1115, 1536, 1152, 1253, 1728, 1152, 1254, 1728, 1280, 1393, 1920, 1280, 1394, 1920]
AC3_CPL_BAND_STRUCT = [0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 1, 0, 1, 1, 1, 1, 1]
AC3_SPX_BAND_STRUCT = [0, 0, 0, 0, 0, 0, 0, 0, 1, 0, 1, 0, 1, 0, 1, 0, 1]
AC3_FRM_EXPSTR = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 3, 1, 0, 0, 0, 2, 0, 1, 0, 0, 0, 3, 3, 2, 0, 0, 2, 0, 0, 2, 0, 0, 2, 0, 3, 2, 0, 0, 3, 2, 0, 2, 0, 0, 3, 3, 3, 2, 0, 1, 0, 0, 0, 2, 0, 2, 0, 0, 3, 2, 0, 2, 0, 2, 0, 2, 0, 2, 0, 3, 3, 2, 0, 3, 2, 0, 0, 2, 0, 3, 2, 0, 3, 2, 0, 3, 3, 2, 0, 2, 0, 3, 3, 3, 3, 3, 1, 0, 0, 0, 0, 3, 1, 0, 0, 0, 3, 3, 2, 0, 0, 2, 0, 3, 2, 0, 0, 3, 3, 3, 2, 0, 2, 0, 0, 3, 2, 0, 2, 0, 3, 3, 2, 0, 3, 2, 0, 3, 2, 0, 3, 3, 3, 3, 3, 1, 0, 0, 0, 3, 3, 2, 0, 0, 3, 3, 3, 2, 0, 2, 0, 3, 3, 2, 0, 3, 3, 3, 3, 3, 2, 0, 0, 3, 3, 3, 2, 0, 3, 3, 3, 3, 3, 2, 0, 3, 3, 3, 3, 3, 3]
AC3_SLOW_DECAY = [15, 17, 19, 21]
AC3_FAST_DECAY = [63, 83, 103, 123]
AC3_SLOW_GAIN = [1344, 1240, 1144, 1040]
AC3_DB_PER_BIT = [0, 1792, 2304, 2816]
AC3_FLOOR = [752, 688, 624, 560, 496, 368, 240, 0]
AC3_FLOOR[7] = 0 - 2048
AC3_FAST_GAIN = [128, 256, 384, 512, 640, 768, 896, 1024]
AC3_QUANT_BITS = [0, 3, 5, 7, 11, 15, 5, 6, 7, 8, 9, 10, 11, 12, 14, 16]
