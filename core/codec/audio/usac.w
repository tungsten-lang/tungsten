# core/codec/audio/usac — an MPEG-D USAC / xHE-AAC decoder (ISO/IEC 23003-3),
# in pure Tungsten.
#
#   dec = UsacDec.new(cfg)              # cfg.extra: AudioSpecificConfig, AOT 42
#   dec.decode(sample) -> AudioBlock    # one UsacFrame() per MediaSample
#
# Registered under "mp4a": core/codec/audio/aac hands AudioSpecificConfigs
# with audioObjectType 42 to this decoder (MP4 `mp4a` + esds, Matroska
# A_AAC, LATM/LOAS via core/codec/audio/latm).
#
# Implemented: UsacConfig (all element types, config extensions incl.
# loudness info), UsacFrame with SCE / CPE / LFE / EXT elements; the FD core
# coder: arithmetic-coded spectra with context mapping, scalefactors, noise
# filling, TNS, M/S and complex-prediction stereo (MDST estimate), every
# window sequence and shape for 1024- and 768-sample frames; extension
# elements (fill, audio pre-roll, uniDrc gain payloads are kept for
# core/codec/audio/usac_drc). See usac_lpd / usac_sbr / usac_mps for the
# other tools; a frame using a tool that is not implemented decodes to
# silence for that element (counted in `errors`) rather than raising.
#
# Samples are computed in 16-bit PCM units (AAC's scale) and output as f32
# in -1..1. Channel order is WAVE (L R C LFE Ls Rs) for the standard channel
# configurations.

use core/codec/media
use usac_tables
use usac_dsp
use aac_tables
# (aac_huff / AAC_HT / AAC_HROOT come from core/codec/audio/aac, which loads this file)

USAC_RATES = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350, -1, -1, 57600,
              51200, 40000, 38400, 34150, 28800, 25600, 20000, 19200, 17075, 14400, 12800, 9600, -1, -1, -1, -1]
USAC_RATE_BOUNDS = [92017, 75132, 55426, 46009, 37566, 27713, 23004, 18783, 13856, 11502, 9391, 0]

# element types
USAC_SCE = 0
USAC_CPE = 1
USAC_LFE = 2
USAC_EXT = 3

# extension element types
USAC_EXT_FILL = 0
USAC_EXT_MPEGS = 1
USAC_EXT_SAOC = 2
USAC_EXT_PREROLL = 3
USAC_EXT_UNI_DRC = 4

# window sequences (after usacMapWindowSequences)
USAC_ONLY_LONG = 0
USAC_LONG_START = 1
USAC_EIGHT_SHORT = 2
USAC_LONG_STOP = 3
USAC_STOP_START = 4

USAC_DEBUG = [env("USAC_DEBUG") == "1"]

-> usac_fail(msg)
  raise MediaError.new("usac: " + msg)

# ---- bit reader: bs is the payload padded with zero bytes; st = [pos, end, overread] ----

-> usac_bits(bs, st, n) (u8[] i64[] i64) i64
  pos = st[0]
  st[0] = pos + n
  if pos + n > st[1]
    st[2] = 1
    if pos >= st[1]
      return 0
  by = pos >> 3
  w = (bs[by] << 32) | (bs[by + 1] << 24) | (bs[by + 2] << 16) | (bs[by + 3] << 8) | bs[by + 4]
  (w >> (40 - (pos & 7) - n)) & ((1 << n) - 1)

-> usac_rate_index(rate)
  i = 0
  while i < 11 && USAC_RATE_BOUNDS[i] > rate
    i += 1
  i

# ---- arithmetic decoder (7.4 spectral noiseless coding) ----

-> usac_get_pk(s, hash, lookup) (i64 i64[] i64[]) i64
  lo = -1
  hi = 741
  while hi - lo > 1
    i = lo + ((hi - lo) >> 1)
    j = hash[i]
    js = j >> 8
    if s < js
      hi = i
    elsif s > js
      lo = i
    else
      return j & 255
  lookup[hi]

# Decode lg spectral lines of one window (n lines long) into q[qo ..]: the
# context `last` (c values of the previous window, last[513] unused) is
# updated. st[0] is left after the sign bits. Returns 0, or 1 on a corrupt
# escape sequence.
-> usac_ac_window(bs, st, q, qo, lg, n, last, cf, cf4, hash, lookup) (u8[] i64[] i32[] i64 i64 i64 i64[] i64[] i64[] i64[] i64[]) i64
  i = 0
  while i < n
    q[qo + i] = 0
    i += 1
  if lg == 0
    i = 0
    while i < (n >> 1)
      last[i] = 1
      i += 1
    while i < 513
      last[i] = 0
      i += 1
    return 0
  p = st[0]
  e = st[1]
  # ari_start_decoding: 16 bits
  val = 0
  k = 0
  while k < 16
    b = 0
    b = (bs[p >> 3] >> (7 - (p & 7))) & 1 if p < e
    val = (val << 1) | b
    p += 1
    k += 1
  low = 0
  high = 65535
  s = last[0] << 12
  c1 = 0
  c2 = 0
  c3 = 0
  np = lg >> 1
  err = 0
  i = 0
  stop = false
  while i < np && !stop
    s = (s >> 4) + (last[i + 1] << 12)
    s = (s & 65520) + c1
    ctx = s
    ctx = s + 65536 if i > 3 && c1 + c2 + c3 < 5
    lev = 0
    esc = 0
    m = 0
    more = true
    while more
      pki = usac_get_pk(ctx + (esc << 17), hash, lookup)
      cb = pki * 17
      rng = high - low + 1
      cc = ((val - low + 1) << 14) - 1
      sym = 0
      while cf[cb + sym] * rng > cc
        sym += 1
      high = low + ((rng * cf[cb + sym - 1]) >> 14) - 1 if sym > 0
      low += (rng * cf[cb + sym]) >> 14
      ren = true
      while ren
        if high < 32768
          ren = true
        elsif low >= 32768
          val -= 32768
          low -= 32768
          high -= 32768
        elsif low >= 16384 && high < 49152
          val -= 16384
          low -= 16384
          high -= 16384
        else
          ren = false
        if ren
          low = low + low
          high = high + high + 1
          b = 0
          b = (bs[p >> 3] >> (7 - (p & 7))) & 1 if p < e
          val = (val << 1) | b
          p += 1
      m = sym
      if m < 16
        more = false
      else
        lev += 1
        esc = lev
        esc = 7 if esc > 7
        if lev > 23
          err = 1
          more = false
          stop = true
    if !stop
      if m == 0 && esc > 0
        stop = true
      else
        b0 = m >> 2
        a0 = m & 3
        l = 0
        while l < lev
          idx = 2
          idx = 0 if b0 == 0
          idx = 1 if a0 == 0
          cb = idx * 4
          rng = high - low + 1
          cc = ((val - low + 1) << 14) - 1
          sym = 0
          while cf4[cb + sym] * rng > cc
            sym += 1
          high = low + ((rng * cf4[cb + sym - 1]) >> 14) - 1 if sym > 0
          low += (rng * cf4[cb + sym]) >> 14
          ren = true
          while ren
            if high < 32768
              ren = true
            elsif low >= 32768
              val -= 32768
              low -= 32768
              high -= 32768
            elsif low >= 16384 && high < 49152
              val -= 16384
              low -= 16384
              high -= 16384
            else
              ren = false
            if ren
              low = low + low
              high = high + high + 1
              b = 0
              b = (bs[p >> 3] >> (7 - (p & 7))) & 1 if p < e
              val = (val << 1) | b
              p += 1
          a0 = (a0 << 1) | (sym & 1)
          b0 = (b0 << 1) | ((sym >> 1) & 1)
          l += 1
        q[qo + 2 * i] = a0
        q[qo + 2 * i + 1] = b0
        c = a0 + b0 + 1
        c = 15 if c > 15
        c3 = c2
        c2 = c1
        c1 = c
        last[i] = c
        i += 1
  j = i
  while j < (n >> 1)
    last[j] = 1
    j += 1
  while j < 513
    last[j] = 0
    j += 1
  # the decoder read 14 bits past the end of the arithmetic code word
  p -= 14
  k = 0
  while k < lg
    if q[qo + k] != 0
      b = 0
      b = (bs[p >> 3] >> (7 - (p & 7))) & 1 if p < e
      p += 1
      q[qo + k] = 0 - q[qo + k] if b == 0
    k += 1
  st[0] = p
  st[2] = 1 if p > e
  err

# Context mapping when the window length changes (7.4.3, map_context).
-> usac_ac_map(last, prev, n) (i64[] i64 i64) i64
  return 0 if prev == n
  tmp = i64[513]
  i = 0
  while i < 513
    tmp[i] = last[i]
    i += 1
  i = 0
  while i < (n >> 1)
    k = (i * prev) / n
    last[i] = tmp[k]
    i += 1
  while i < 513
    last[i] = 0
    i += 1
  0

# ---- inverse quantisation, noise filling, scalefactors ----

-> usac_build_pow43
  t = f64[8192]
  i = 0
  while i < 8192
    t[i] = Math.pow(i * 1.0, 4.0 / 3.0)
    i += 1
  t

USAC_POW43 = usac_build_pow43()

# p: [max_sfb, ngroups, winlen, nf_on, nf_level, nf_offset, nf_start, seed]
# glen: group lengths; swb: band offsets (one window); sf: scalefactors
# [g * max_sfb + sfb]. coef gets the scaled spectrum of all windows.
-> usac_scale(q, coef, sf, swb, glen, p, pow43) (i32[] f64[] i64[] i64[] i64[] i64[] f64[]) i64
  max_sfb = p[0]
  ngroups = p[1]
  winlen = p[2]
  nf_on = p[3]
  nlev = ~0.0
  nlev = Math.pow(~2.0, ((p[4] - 14) ## f64) / ~3.0) if nf_on != 0 && p[4] > 0
  noff = p[5] - 16
  nstart = p[6]
  seed = p[7]
  nwin = 0
  g = 0
  while g < ngroups
    nwin += glen[g]
    g += 1
  i = 0
  while i < nwin * winlen
    coef[i] = ~0.0
    i += 1
  wt = 0
  g = 0
  while g < ngroups
    sfb = 0
    while sfb < max_sfb
      fac = sf[g * max_sfb + sfb] - 100
      st0 = swb[sfb]
      en = swb[sfb + 1]
      if nf_on != 0
        noise = 1
        w = 0
        while w < glen[g] && noise == 1
          o = (wt + w) * winlen
          k = st0
          while k < en
            if q[o + k] != 0
              noise = 0
              k = en
            k += 1
          w += 1
        fac += noff if noise == 1
      gain = Math.pow(~2.0, ~0.25 * (fac ## f64))
      # the reference draws a random sign for every zero line of a noise-filled
      # band, even at noise level 0 (the value is then 0)
      use_nf = nf_on != 0 && st0 >= nstart
      w = 0
      while w < glen[g]
        o = (wt + w) * winlen
        k = st0
        while k < en
          v = q[o + k] ## i64
          x = ~0.0
          if v == 0
            if use_nf
              seed = (seed * 69069 + 5) & 4294967295
              x = (seed & 65536) != 0 ? ~0.0 - nlev : nlev
          elsif v > 0
            v = 8191 if v > 8191
            x = pow43[v]
          else
            v = 0 - v
            v = 8191 if v > 8191
            x = ~0.0 - pow43[v]
          coef[o + k] = x * gain
          k += 1
        w += 1
      sfb += 1
    wt += glen[g]
    g += 1
  p[7] = seed
  0

# ---- TNS (same tool as AAC; USAC band limits) ----

# tns: per window w at w * 16: [n_filt, (start, stop, order, dir) x 3];
# coefficients (LPC, a[1..order]) at tc[(w * 4 + f) * 32 + i].
-> usac_tns_apply(coef, swb, nwin, winlen, nbands, maxb, tns, tc) (f64[] i64[] i64 i64 i64 i64 i64[] f64[]) i64
  st = f64[32]
  w = 0
  while w < nwin
    nf = tns[w * 16]
    f = 0
    while f < nf
      b = w * 16 + 1 + f * 4
      order = tns[b + 2]
      if order > 0
        s0 = tns[b]
        s1 = tns[b + 1]
        s0 = maxb if s0 > maxb
        s0 = nbands if s0 > nbands
        s1 = maxb if s1 > maxb
        s1 = nbands if s1 > nbands
        start = swb[s0]
        stop = swb[s1]
        size = stop - start
        if size > 0
          inc = 1
          pos = w * winlen + start
          if tns[b + 3] != 0
            inc = -1
            pos = w * winlen + stop - 1
          i = 0
          while i < order
            st[i] = ~0.0
            i += 1
          cb = (w * 4 + f) * 32
          n = 0
          while n < size
            y = coef[pos]
            j = 0
            while j < order
              y -= tc[cb + 1 + j] * st[j]
              j += 1
            j = order - 1
            while j > 0
              st[j] = st[j - 1]
              j -= 1
            st[0] = y
            coef[pos] = y
            pos += inc
            n += 1
      f += 1
    w += 1
  0

# ---- stereo ----

# M/S over the masked bands: l = m + s, r = m - s
-> usac_ms(c0, c1, mask, swb, glen, ngroups, max_sfb, winlen) (f64[] f64[] i64[] i64[] i64[] i64 i64 i64) i64
  wt = 0
  g = 0
  while g < ngroups
    sfb = 0
    while sfb < max_sfb
      if mask[g * max_sfb + sfb] != 0
        w = 0
        while w < glen[g]
          o = (wt + w) * winlen
          k = swb[sfb]
          while k < swb[sfb + 1]
            m = c0[o + k]
            s = c1[o + k]
            c0[o + k] = m + s
            c1[o + k] = m - s
            k += 1
          w += 1
      sfb += 1
    wt += glen[g]
    g += 1
  0

# MDST estimate of one window (filterAndAdd): out += f (*) in, the even
# outputs scaled by fe and the odd ones by fo.
-> usac_mdst_add(inp, io, len, flt, fb, out, oo, fe, fo) (f64[] i64 i64 f64[] i64 f64[] i64 f64 f64) i64
  f0 = flt[fb]
  f1 = flt[fb + 1]
  f2 = flt[fb + 2]
  f3 = flt[fb + 3]
  f4 = flt[fb + 4]
  f5 = flt[fb + 5]
  f6 = flt[fb + 6]
  i = 0
  while i < len
    # in[] mirrored at both ends (in[-1] = in[0], in[len] = in[len - 1], ...)
    s = ~0.0
    k = -3
    while k <= 3
      j = i + k
      j = -j - 1 if j < 0
      j = 2 * len - 1 - j if j >= len
      fk = f3
      fk = f6 if k == -3
      fk = f5 if k == -2
      fk = f4 if k == -1
      fk = f2 if k == 1
      fk = f1 if k == 2
      fk = f0 if k == 3
      s += fk * inp[io + j]
      k += 1
    out[oo + i] += (i & 1) == 0 ? s * fe : s * fo
    i += 1
  0

-> usac_cplx_upmix(c0, c1, dmx_re, dmx_im, are, aim, used, n, dir) (f64[] f64[] f64[] f64[] f64[] f64[] i64[] i64 i64) i64
  i = 0
  while i < n
    if used[i] != 0
      x = c1[i] - are[i] * c0[i] - aim[i] * dmx_im[i]
      l = c0[i]
      if dir == 0
        c1[i] = l - x
        c0[i] = l + x
      else
        c1[i] = x - l
        c0[i] = x + l
    i += 1
  0

# ---- filterbank ----

-> usac_vmul(a, ao, w, wo, n) (f64[] i64 f64[] i64 i64) i64
  i = 0
  while i < n
    a[ao + i] = a[ao + i] * w[wo + i]
    i += 1
  0

# a[ao + i] *= w[wo + n - 1 - i] (the falling half)
-> usac_vmul_rev(a, ao, w, wo, n) (f64[] i64 f64[] i64 i64) i64
  i = 0
  while i < n
    a[ao + i] = a[ao + i] * w[wo + n - 1 - i]
    i += 1
  0

-> usac_vadd(a, ao, b, bo, n) (f64[] i64 f64[] i64 i64) i64
  i = 0
  while i < n
    a[ao + i] = a[ao + i] + b[bo + i]
    i += 1
  0

-> usac_vzero(a, ao, n) (f64[] i64 i64) i64
  i = 0
  while i < n
    a[ao + i] = ~0.0
    i += 1
  0

-> usac_out_f32(dst, src, n, nch, c, scale) (f32[] f64[] i64 i64 i64 f64) i64
  i = 0
  while i < n
    x = src[i] * scale
    x = ~1.0 if x > ~1.0
    x = ~-1.0 if x < ~-1.0
    dst[i * nch + c] = x ## f32
    i += 1
  0

# ---- per-channel state ----

+ UsacCh
  rw :seq, :seq_last, :shape, :shape_prev, :max_sfb, :grouping, :ngroups, :glen, :core_mode, :core_mode_last
  rw :q, :coef, :coef_save, :sf, :last, :last_len, :seed, :obuf, :tbuf, :out, :tns, :tc, :tns_present
  rw :nf_level, :nf_offset, :fac_present, :sp

  -> new(n)
    @seq = USAC_ONLY_LONG
    @seq_last = USAC_ONLY_LONG
    @shape = 0
    @shape_prev = 0
    @max_sfb = 0
    @grouping = 0
    @ngroups = 1
    @glen = i64[8]
    @glen[0] = 1
    @core_mode = 0
    @core_mode_last = 0
    @q = i32[1024]
    @coef = f64[1024]
    @coef_save = f64[1024]
    @sf = i64[128]
    @last = i64[513]
    @last_len = 0
    @seed = 12345
    @obuf = f64[2 * n]
    @tbuf = f64[2 * n]
    @out = f64[n]
    @tns = i64[8 * 16]
    @tc = f64[8 * 4 * 32]
    @tns_present = 0
    @nf_level = 0
    @nf_offset = 0
    @fac_present = 0
    @sp = i64[8]

+ UsacStereo
  rw :ms_mode, :mask, :max_sfb_ste, :used, :are, :aim, :are_prev, :aim_prev, :pred_dir, :complex, :use_prev
  rw :dmx_re, :dmx_im, :dmx_prev, :b_used, :b_are, :b_aim

  -> new
    @ms_mode = 0
    @mask = i64[8 * 64]
    @max_sfb_ste = 0
    @used = i64[8 * 64]
    @are = i64[8 * 64]
    @aim = i64[8 * 64]
    @are_prev = i64[64]
    @aim_prev = i64[64]
    @pred_dir = 0
    @complex = 0
    @use_prev = 0
    @dmx_re = f64[1024]
    @dmx_im = f64[1024]
    @dmx_prev = f64[1024]
    @b_used = i64[1024]
    @b_are = f64[1024]
    @b_aim = f64[1024]

# ---- the decoder ----

+ UsacDec
  ro :sample_rate, :channels, :frame, :out_frame, :errors, :config
  rw :drc_payloads

  -> new(cfg)
    asc = cfg.extra
    if asc.is_a?(String)
      asc = ccall("w_string_bytes_view", asc) ## u8[]
    usac_fail("missing AudioSpecificConfig") if asc == nil || asc.size < 2
    @errors = 0
    @drc_payloads = []
    parse_asc(asc)
    usac_dsp_prepare(@frame)
    setup

  # ---- configuration (7.2 UsacConfig) ----

  -> cfg_bits(n)
    usac_bits(@bs, @st, n)

  -> escaped(n1, n2, n3)
    v = cfg_bits(n1)
    if v == (1 << n1) - 1
      v2 = cfg_bits(n2)
      v += v2
      v += cfg_bits(n3) if n3 > 0 && v2 == (1 << n2) - 1
    v

  -> load(bytes)
    n = bytes.size
    @bs = u8[n + 16]
    i = 0
    while i < n
      @bs[i] = bytes[i]
      i += 1
    @st = i64[4]
    @st[1] = n * 8

  -> parse_asc(asc)
    load(asc)
    aot = cfg_bits(5)
    aot = 32 + cfg_bits(6) if aot == 31
    usac_fail("not a USAC config (audioObjectType " + aot.to_s + ")") if aot != 42
    fi = cfg_bits(4)
    cfg_bits(24) if fi == 15
    cfg_bits(4)
    parse_usac_config

  -> parse_usac_config
    fi = cfg_bits(5)
    rate = fi == 31 ? cfg_bits(24) : USAC_RATES[fi]
    usac_fail("bad sampling frequency") if rate <= 0
    @sample_rate = rate
    @csfli = cfg_bits(3)
    usac_fail("reserved coreSbrFrameLengthIndex") if @csfli > 4
    @frame = (@csfli == 0 || @csfli == 2) ? 768 : 1024
    @sbr_ratio = [0, 0, 1, 2, 3][@csfli]       # 1: 8:3, 2: 2:1, 3: 4:1
    @out_frame = [768, 1024, 2048, 2048, 4096][@csfli]
    cci = cfg_bits(5)
    @out_pos = []
    if cci == 0
      n = escaped(5, 8, 16)
      k = 0
      while k < n
        @out_pos.push(cfg_bits(5))
        k += 1
    else
      @out_pos = usac_default_layout(cci)
    @cci = cci
    nel = escaped(4, 8, 16) + 1
    @elems = []
    k = 0
    while k < nel
      t = cfg_bits(2)
      e = {type: t, tw_mdct: 0, noise_fill: 0, stereo: 0, sbr: nil, mps: nil}
      if t == USAC_SCE || t == USAC_CPE
        e[:tw_mdct] = cfg_bits(1)
        e[:noise_fill] = cfg_bits(1)
        if @sbr_ratio > 0
          e[:sbr] = read_sbr_config
          e[:stereo] = cfg_bits(2) if t == USAC_CPE
        e[:mps] = read_mps_config(e[:stereo]) if t == USAC_CPE && e[:stereo] > 0
      elsif t == USAC_EXT
        e[:ext_type] = escaped(4, 8, 16)
        clen = escaped(4, 8, 16)
        e[:ext_default] = 0
        e[:ext_default] = escaped(8, 16, 0) + 1 if cfg_bits(1) == 1
        e[:ext_frag] = cfg_bits(1)
        cb = u8[clen]
        j = 0
        while j < clen
          cb[j] = cfg_bits(8)
          j += 1
        e[:ext_config] = cb
        e[:ext_buf] = []
      @elems.push(e)
      k += 1
    @loudness = nil
    if cfg_bits(1) == 1
      n = escaped(2, 4, 8) + 1
      k = 0
      while k < n
        ty = escaped(4, 8, 16)
        len = escaped(4, 8, 16)
        cb = u8[len]
        j = 0
        while j < len
          cb[j] = cfg_bits(8)
          j += 1
        @loudness = cb if ty == 2          # ID_CONFIG_EXT_LOUDNESS_INFO
        k += 1
    usac_fail("truncated UsacConfig") if @st[2] != 0
    @config = {rate: @sample_rate, frame: @frame, out_frame: @out_frame, sbr_ratio: @sbr_ratio, cci: @cci, elements: @elems}

  -> read_sbr_config
    h = {}
    h[:harmonic] = cfg_bits(1)
    h[:inter_tes] = cfg_bits(1)
    h[:pvc] = cfg_bits(1)
    h[:start_freq] = cfg_bits(4)
    h[:stop_freq] = cfg_bits(4)
    x1 = cfg_bits(1)
    x2 = cfg_bits(1)
    h[:freq_scale] = 2
    h[:alter_scale] = 1
    h[:noise_bands] = 2
    if x1 == 1
      h[:freq_scale] = cfg_bits(2)
      h[:alter_scale] = cfg_bits(1)
      h[:noise_bands] = cfg_bits(2)
    h[:limiter_bands] = 2
    h[:limiter_gains] = 2
    h[:interpol_freq] = 1
    h[:smoothing_mode] = 1
    if x2 == 1
      h[:limiter_bands] = cfg_bits(2)
      h[:limiter_gains] = cfg_bits(2)
      h[:interpol_freq] = cfg_bits(1)
      h[:smoothing_mode] = cfg_bits(1)
    h

  -> read_mps_config(sci)
    m = {}
    m[:freq_res] = cfg_bits(3)
    m[:fixed_gain] = cfg_bits(3)
    m[:temp_shape] = cfg_bits(2)
    m[:decorr] = cfg_bits(2)
    m[:high_rate] = cfg_bits(1)
    m[:phase_coding] = cfg_bits(1)
    m[:otts_phase] = [0, 10, 10, 7, 5, 3, 2, 2][m[:freq_res]]
    m[:otts_phase] = cfg_bits(5) if cfg_bits(1) == 1
    m[:residual_bands] = 0
    m[:pseudo_lr] = 0
    if sci > 1
      m[:residual_bands] = cfg_bits(5)
      m[:otts_phase] = m[:residual_bands] if m[:residual_bands] > m[:otts_phase]
      m[:pseudo_lr] = cfg_bits(1)
    m[:env_quant] = 0
    m[:env_quant] = cfg_bits(1) if m[:temp_shape] == 2
    m

  # ---- decoder state ----

  -> setup
    # core sampling rate and the band tables (indexed as the reference
    # decoder does: 768-sample frames without SBR use the rate * 4 / 3 index)
    @core_rate = @sample_rate
    @core_rate = @sample_rate * 3 / 8 if @sbr_ratio == 1
    @core_rate = @sample_rate / 2 if @sbr_ratio == 2
    @core_rate = @sample_rate / 4 if @sbr_ratio == 3
    trate = @out_frame == 768 ? @core_rate * 4 / 3 : @core_rate
    @rate_idx = usac_rate_index(trate)
    ri = @rate_idx
    if @frame == 1024
      @swb_l = usac_slice(AAC_SWB_1024, AAC_SWB_1024_IDX[ri], AAC_SWB_1024_IDX[ri + 1] - AAC_SWB_1024_IDX[ri])
      @swb_s = usac_slice(AAC_SWB_128, AAC_SWB_128_IDX[ri], AAC_SWB_128_IDX[ri + 1] - AAC_SWB_128_IDX[ri])
    else
      @swb_l = usac_slice(USAC_SWB_768, USAC_SWB_768_IDX[ri], USAC_NUM_SWB_768[ri] + 1)
      @swb_s = usac_slice(USAC_SWB_96, USAC_SWB_96_IDX[ri], USAC_NUM_SWB_96[ri] + 1)
    @nswb_l = @swb_l.size - 1
    @nswb_s = @swb_s.size - 1
    @tns_max_l = USAC_TNS_MAX_L[ri]
    @tns_max_s = USAC_TNS_MAX_S[ri]
    @nf_start_l = @frame == 768 ? 120 : 160
    @nf_start_s = @frame == 768 ? 15 : 20
    # channels: one UsacCh per coded channel of each element
    @ech = []
    @est = []
    @channels = 0
    @elems.each ->(e)
      t = e[:type]
      if t == USAC_EXT
        @ech.push(nil)
        @est.push(nil)
      else
        n = t == USAC_CPE ? 2 : 1
        chs = []
        k = 0
        while k < n
          ch = UsacCh.new(@frame)
          # noise-filling seeds: 0x3039 for even, 0x10932 for odd channel numbers
          ch.seed = (@channels + k) % 2 == 0 ? 12345 : 67890
          chs.push(ch)
          k += 1
        @ech.push(chs)
        @est.push(t == USAC_CPE ? UsacStereo.new : nil)
        @channels += n
    @channels = @out_pos.size if @out_pos.size > 0 && @out_pos.size != @channels && @cci == 0
    @tmp = f64[2 * @frame]
    @sp = i64[8]
    @frames = 0

  -> reset
    setup

  -> flush
    nil

  # ---- frames ----

  -> bits(n)
    usac_bits(@bs, @st, n)

  -> decode(sample)
    d = sample.data
    if d.is_a?(String)
      d = ccall("w_string_bytes_view", d) ## u8[]
    load(d)
    outs = []
    begin
      outs = decode_frame
    rescue e
      @errors += 1
      outs = []
    @frames += 1
    emit(outs, sample.pts)

  # the decoded channels, in element order, as f64 arrays of out_frame samples
  -> decode_frame
    @indep = bits(1)
    outs = []
    i = 0
    while i < @elems.size
      e = @elems[i]
      t = e[:type]
      if t == USAC_EXT
        read_ext(e)
      else
        chs = @ech[i]
        nch = chs.size
        ok = true
        begin
          decode_core(e, chs, @est[i], t)
        rescue err
          @errors += 1
          ok = false
        chs.each ->(c)
          usac_vzero(c.out, 0, @frame) if !ok
          outs.push(c.out)
        # the bitstream position after a failed element is unknown: stop here
        if !ok
          j = i + 1
          while j < @elems.size
            if @ech[j] != nil
              @ech[j].each ->(c)
                usac_vzero(c.out, 0, @frame)
                outs.push(c.out)
            j += 1
          return outs
      i += 1
    outs

  -> emit(outs, pts)
    n = @frame
    nch = outs.size
    if nch == 0
      nch = @channels
      nch = 1 if nch == 0
      buf = f32[n * nch]
      return AudioBlock.new(buf, n, nch, @sample_rate, pts)
    order = usac_wave_order(@cci, nch)
    buf = f32[n * nch]
    c = 0
    while c < nch
      usac_out_f32(buf, outs[order[c]], n, nch, c, 1.0 / 32768.0)
      c += 1
    AudioBlock.new(buf, n, nch, @sample_rate, pts)

  # ---- extension elements (7.17) ----

  -> read_ext(e)
    return nil if bits(1) == 0                # usacExtElementPresent
    len = 0
    if bits(1) == 1                           # usacExtElementUseDefaultLength
      len = e[:ext_default]
    else
      len = bits(8)
      len += bits(16) - 2 if len == 255
    return nil if len == 0
    fs = 1
    fe = 1
    if e[:ext_frag] == 1
      fs = bits(1)
      fe = bits(1)
    data = u8[len]
    j = 0
    while j < len
      data[j] = bits(8)
      j += 1
    e[:ext_buf] = [] if fs == 1
    e[:ext_buf].push(data)
    if fe == 1
      if e[:ext_type] == USAC_EXT_UNI_DRC
        @drc_payloads.push(e[:ext_buf])
        @drc_payloads.shift if @drc_payloads.size > 4
      e[:ext_buf] = []
    nil

  # ---- channel elements (7.7 / 7.8) ----

  -> decode_core(e, chs, ste, t)
    nch = chs.size
    chs.each ->(c)
      c.core_mode_last = c.core_mode
      c.core_mode = 0
      c.tns_present = 0
      c.fac_present = 0
    if t != USAC_LFE
      chs.each ->(c)
        c.core_mode = bits(1)
    k = 0
    while k < nch
      usac_fail("LPD core not implemented") if chs[k].core_mode != 0
      k += 1
    usac_fail("time-warped MDCT not implemented") if e[:tw_mdct] == 1
    usac_fail("MPEG Surround 2-1-2 not implemented") if e[:stereo] > 0
    usac_fail("SBR not implemented") if e[:sbr] != nil
    common_window = 0
    tns_on_lr = 1
    if nch == 2
      tns_active = bits(1)
      common_window = bits(1)
      c0 = chs[0]
      c1 = chs[1]
      ste.ms_mode = 0
      if common_window == 1
        read_ics_info(c0)
        c1.seq_last = c1.seq
        c1.seq = c0.seq
        c1.shape_prev = c1.shape
        c1.shape = c0.shape
        c1.grouping = c0.grouping
        c1.ngroups = c0.ngroups
        k = 0
        while k < 8
          c1.glen[k] = c0.glen[k]
          k += 1
        c1.max_sfb = c0.max_sfb
        if bits(1) == 0                     # common_max_sfb
          c1.max_sfb = bits(c0.seq == USAC_EIGHT_SHORT ? 4 : 6)
          check_max_sfb(c1)
        ste.max_sfb_ste = c0.max_sfb > c1.max_sfb ? c0.max_sfb : c1.max_sfb
        ste.ms_mode = bits(2)
        ms = ste.ms_mode
        if ms == 1
          g = 0
          while g < c0.ngroups
            sfb = 0
            while sfb < ste.max_sfb_ste
              ste.mask[g * ste.max_sfb_ste + sfb] = bits(1)
              sfb += 1
            g += 1
        elsif ms == 2
          g = 0
          while g < c0.ngroups * ste.max_sfb_ste
            ste.mask[g] = 1
            g += 1
        elsif ms == 3
          read_cplx_pred(ste, c0.ngroups)
      if tns_active == 1
        common_tns = 0
        common_tns = bits(1) if common_window == 1
        tns_on_lr = bits(1)
        if common_tns == 1
          read_tns(c0)
          k = 0
          while k < 8 * 16
            c1.tns[k] = c0.tns[k]
            k += 1
          k = 0
          while k < 8 * 4 * 32
            c1.tc[k] = c0.tc[k]
            k += 1
          c0.tns_present = 1
          c1.tns_present = 1
          @common_tns = true
        else
          @common_tns = false
          if bits(1) == 1                   # tns_present_both
            c0.tns_present = 2
            c1.tns_present = 2
          else
            c1.tns_present = bits(1) == 1 ? 2 : 0
            c0.tns_present = c1.tns_present == 2 ? 0 : 2
    elsif t == USAC_SCE
      chs[0].tns_present = bits(1) == 1 ? 2 : 0
    k = 0
    while k < nch
      fd_channel_stream(e, chs[k], common_window == 1, k)
      k += 1
    if USAC_DEBUG[0] && nch == 2
      << "  cpe f" + @frames.to_s + " cw=" + common_window.to_s + " seq=" + chs[0].seq.to_s + "/" + chs[1].seq.to_s + " ms=" + ste.ms_mode.to_s + " cplx=" + ste.complex.to_s + " prev=" + ste.use_prev.to_s + " dir=" + ste.pred_dir.to_s + " tns=" + chs[0].tns_present.to_s + "/" + chs[1].tns_present.to_s + " lr=" + tns_on_lr.to_s + " msfb=" + chs[0].max_sfb.to_s + "/" + chs[1].max_sfb.to_s
    # spectral processing
    if nch == 2 && common_window == 1
      c0 = chs[0]
      c1 = chs[1]
      if ste.ms_mode == 3
        cplx_prev_dmx(ste, c0, c1)
      else
        k = 0
        while k < 64
          ste.are_prev[k] = 0
          ste.aim_prev[k] = 0
          k += 1
      p = 0
      while p < 2
        if p != tns_on_lr
          stereo(ste, c0, c1)
        else
          tns(c0)
          tns(c1)
        p += 1
      save_prev(c0)
      save_prev(c1)
    else
      if nch == 2
        # no complex prediction in this frame: its predictors restart at 0
        k = 0
        while k < 64
          ste.are_prev[k] = 0
          ste.aim_prev[k] = 0
          k += 1
      k = 0
      while k < nch
        tns(chs[k])
        save_prev(chs[k])
        k += 1
    chs.each ->(c)
      filterbank(c)
    nil

  -> check_max_sfb(c)
    lim = c.seq == USAC_EIGHT_SHORT ? @nswb_s : @nswb_l
    usac_fail("max_sfb " + c.max_sfb.to_s + " > " + lim.to_s) if c.max_sfb > lim

  # ics_info(): window sequence and shape, max_sfb, grouping
  -> read_ics_info(c)
    c.seq_last = c.seq
    ws = bits(2)
    c.shape_prev = c.shape
    c.shape = bits(1)
    if ws == USAC_LONG_START && (c.seq_last == USAC_LONG_START || c.seq_last == USAC_EIGHT_SHORT || c.seq_last == USAC_STOP_START)
      ws = USAC_STOP_START
    c.seq = ws
    if ws == USAC_EIGHT_SHORT
      c.max_sfb = bits(4)
      c.grouping = bits(7)
      ng = 0
      k = 0
      while k < 8
        c.glen[k] = 0
        k += 1
      c.glen[0] = 1
      k = 0
      while k < 7
        if (c.grouping >> (6 - k)) & 1 == 1
          c.glen[ng] = c.glen[ng] + 1
        else
          ng += 1
          c.glen[ng] = 1
        k += 1
      c.ngroups = ng + 1
    else
      c.max_sfb = bits(6)
      c.ngroups = 1
      c.glen[0] = 1
    check_max_sfb(c)

  -> read_cplx_pred(ste, ngroups)
    msfb = ste.max_sfb_ste
    all = bits(1)
    g = 0
    while g < ngroups
      sfb = 0
      while sfb < msfb
        if all == 1
          ste.used[g * msfb + sfb] = 1
          sfb += 1
        else
          v = bits(1)
          ste.used[g * msfb + sfb] = v
          ste.used[g * msfb + sfb + 1] = v if sfb + 1 < msfb
          sfb += 2
      g += 1
    ste.pred_dir = bits(1)
    ste.complex = bits(1)
    ste.use_prev = 0
    ste.use_prev = bits(1) if ste.complex == 1 && @indep == 0
    dct = 0
    dct = bits(1) if @indep == 0
    g = 0
    while g < ngroups
      sfb = 0
      while sfb < msfb
        lre = 0
        lim = 0
        if dct == 1
          lre = ste.are_prev[sfb]
          lim = ste.aim_prev[sfb]
        elsif sfb > 0
          lre = ste.are[g * msfb + sfb - 1]
          lim = ste.aim[g * msfb + sfb - 1]
        i = g * msfb + sfb
        if ste.used[i] == 1
          ste.are[i] = lre + 60 - huff_sf
          ste.aim[i] = ste.complex == 1 ? lim + 60 - huff_sf : 0
        else
          ste.are[i] = 0
          ste.aim[i] = 0
        if sfb + 1 < msfb
          ste.are[i + 1] = ste.are[i]
          ste.aim[i + 1] = ste.aim[i]
        ste.are_prev[sfb] = ste.are[i]
        ste.aim_prev[sfb] = ste.aim[i]
        sfb += 2
      sfb = msfb
      while sfb < 64
        ste.are_prev[sfb] = 0
        ste.aim_prev[sfb] = 0
        sfb += 1
      g += 1

  -> huff_sf
    v = aac_huff_sym(@bs, @st)
    usac_fail("bad Huffman code") if v < 0
    v

  # fd_channel_stream() (7.7.2)
  -> fd_channel_stream(e, c, common_window, k)
    gg = bits(8)
    c.nf_level = 0
    c.nf_offset = 0
    if e[:noise_fill] == 1
      c.nf_level = bits(3)
      c.nf_offset = bits(5)
    read_ics_info(c) if !common_window
    short = c.seq == USAC_EIGHT_SHORT
    # scalefactors: the first band of the first group is global_gain itself
    off = gg
    g = 0
    while g < c.ngroups
      sfb = 0
      while sfb < c.max_sfb
        off += huff_sf - 60 if g > 0 || sfb > 0
        usac_fail("scalefactor out of range") if off < 0 || off > 255
        c.sf[g * c.max_sfb + sfb] = off
        sfb += 1
      g += 1
    read_tns(c) if c.tns_present == 2
    c.tns_present = 1 if c.tns_present == 2
    # ac_spectral_data()
    reset = @indep == 1 ? 1 : bits(1)
    n = short ? @frame / 8 : @frame
    swb = short ? @swb_s : @swb_l
    lg = swb[c.max_sfb]
    if reset == 1
      k2 = 0
      while k2 < 513
        c.last[k2] = 0
        k2 += 1
    else
      usac_ac_map(c.last, c.last_len, n) if c.last_len > 0
    c.last_len = n
    nwin = short ? 8 : 1
    w = 0
    while w < nwin
      r = usac_ac_window(@bs, @st, c.q, w * n, lg, n, c.last, USAC_ARI_CF, USAC_ARI_CF4, USAC_ARI_HASH, USAC_ARI_LOOKUP)
      usac_fail("arithmetic decoder error") if r != 0
      w += 1
    c.fac_present = bits(1)
    usac_fail("FAC data (LPD transition) not implemented") if c.fac_present == 1
    usac_fail("bitstream overrun") if @st[2] != 0
    # inverse quantisation, noise filling and scalefactors
    sp = c.sp
    sp[0] = c.max_sfb
    sp[1] = c.ngroups
    sp[2] = n
    sp[3] = e[:noise_fill]
    sp[4] = c.nf_level
    sp[5] = c.nf_offset
    sp[6] = short ? @nf_start_s : @nf_start_l
    sp[7] = c.seed
    usac_scale(c.q, c.coef, c.sf, swb, c.glen, sp, USAC_POW43)
    if USAC_DEBUG[0]
      << "frame " + @frames.to_s + " seq=" + c.seq.to_s + " shape=" + c.shape.to_s + " max_sfb=" + c.max_sfb.to_s + " ng=" + c.ngroups.to_s + " nf=" + c.nf_level.to_s + "/" + c.nf_offset.to_s + " seed " + c.seed.to_s + "->" + sp[7].to_s + " indep=" + @indep.to_s
    c.seed = sp[7]

  -> read_tns(c)
    short = c.seq == USAC_EIGHT_SHORT
    nwin = short ? 8 : 1
    nb = short ? @nswb_s : @nswb_l
    w = 0
    while w < nwin
      base = w * 16
      nf = bits(short ? 1 : 2)
      c.tns[base] = nf
      if nf > 0
        res = bits(1) + 3
        top = nb
        f = 0
        while f < nf
          b = base + 1 + f * 4
          len = bits(short ? 4 : 6)
          order = bits(short ? 3 : 4)
          start = top - len
          start = 0 if start < 0
          c.tns[b] = start
          c.tns[b + 1] = top
          c.tns[b + 2] = order
          c.tns[b + 3] = 0
          top = start
          if order > 0
            c.tns[b + 3] = bits(1)
            compress = bits(1)
            r2 = res - compress
            iq = ((1 << (res - 1)) - 0.5) / (USAC_PI / 2.0)
            iqm = ((1 << (res - 1)) + 0.5) / (USAC_PI / 2.0)
            par = f64[order + 1]
            i = 0
            while i < order
              v = bits(r2)
              v -= (1 << r2) if v >= (1 << (r2 - 1))
              par[i + 1] = Math.sin(v / (v >= 0 ? iq : iqm))
              i += 1
            # parcor -> LPC (Markel and Gray)
            a = f64[order + 1]
            tb = f64[order + 1]
            a[0] = 1.0
            m = 1
            while m <= order
              tb[0] = a[0]
              i = 1
              while i < m
                tb[i] = a[i] + par[m] * a[m - i]
                i += 1
              tb[m] = par[m]
              i = 0
              while i <= m
                a[i] = tb[i]
                i += 1
              m += 1
            cb = (w * 4 + f) * 32
            i = 0
            while i <= order
              c.tc[cb + i] = a[i]
              i += 1
          f += 1
      w += 1

  -> tns(c)
    return nil if c.tns_present == 0
    short = c.seq == USAC_EIGHT_SHORT
    usac_tns_apply(c.coef, short ? @swb_s : @swb_l, short ? 8 : 1, short ? @frame / 8 : @frame, c.max_sfb, short ? @tns_max_s : @tns_max_l, c.tns, c.tc)

  -> stereo(ste, c0, c1)
    short = c0.seq == USAC_EIGHT_SHORT
    swb = short ? @swb_s : @swb_l
    n = short ? @frame / 8 : @frame
    if ste.ms_mode == 1 || ste.ms_mode == 2
      usac_ms(c0.coef, c1.coef, ste.mask, swb, c0.glen, c0.ngroups, ste.max_sfb_ste, n)
    elsif ste.ms_mode == 3
      cplx_pred(ste, c0, c1, short, swb, n)

  # downmix of the previous frame (last window) with this frame's direction
  -> cplx_prev_dmx(ste, c0, c1)
    short = c0.seq == USAC_EIGHT_SHORT
    n = short ? @frame / 8 : @frame
    offs = @frame - n
    sg = ste.pred_dir == 0 ? 0.5 : -0.5
    i = 0
    while i < n
      ste.dmx_prev[i] = 0.5 * c0.coef_save[offs + i] + sg * c1.coef_save[offs + i]
      i += 1

  -> cplx_pred(ste, c0, c1, short, swb, n)
    msfb = ste.max_sfb_ste
    nb = @frame
    # per-line prediction flags and coefficients
    wt = 0
    g = 0
    while g < c0.ngroups
      w = 0
      while w < c0.glen[g]
        o = (wt + w) * n
        k = 0
        while k < n
          ste.b_used[o + k] = 0
          ste.b_are[o + k] = 0.0
          ste.b_aim[o + k] = 0.0
          k += 1
        sfb = 0
        while sfb < msfb
          i = g * msfb + sfb
          k = swb[sfb]
          while k < swb[sfb + 1]
            ste.b_used[o + k] = ste.used[i]
            ste.b_are[o + k] = ste.are[i] * 0.1
            ste.b_aim[o + k] = ste.complex == 1 ? ste.aim[i] * 0.1 : 0.0
            k += 1
          sfb += 1
        w += 1
      wt += c0.glen[g]
      g += 1
    # real downmix of this frame
    sg = ste.pred_dir == 0 ? 0.5 : -0.5
    i = 0
    while i < nb
      if ste.b_used[i] == 1
        ste.dmx_re[i] = c0.coef[i]
      else
        ste.dmx_re[i] = 0.5 * c0.coef[i] + sg * c1.coef[i]
      ste.dmx_im[i] = 0.0
      i += 1
    if ste.complex == 1
      # MDST estimate, window by window
      wi = usac_mdst_kind(c0.seq)
      sh = c0.shape
      shp = c0.shape_prev
      nw = short ? 8 : 1
      w = 0
      while w < nw
        fc = ((wi * 2 + shp) * 2 + sh) * 7
        usac_mdst_add(ste.dmx_re, w * n, n, USAC_MDST_CUR, fc, ste.dmx_im, w * n, 1.0, 1.0)
        pk = (wi == 2 || wi == 3) ? 1 : 0
        fp = (pk * 2 + shp) * 7
        if w == 0
          usac_mdst_add(ste.dmx_prev, 0, n, USAC_MDST_PREV, fp, ste.dmx_im, 0, -1.0, 1.0) if ste.use_prev == 1
        else
          usac_mdst_add(ste.dmx_re, (w - 1) * n, n, USAC_MDST_PREV, fp, ste.dmx_im, w * n, -1.0, 1.0)
        shp = sh
        w += 1
    usac_cplx_upmix(c0.coef, c1.coef, ste.dmx_re, ste.dmx_im, ste.b_are, ste.b_aim, ste.b_used, nb, ste.pred_dir)

  -> save_prev(c)
    usac_copy(c.coef_save, 0, c.coef, 0, @frame)

  # IMDCT, windowing and overlap-add (fd2buffer, FD frames)
  -> filterbank(c)
    nl = @frame
    ns = nl / 8
    nflat = (nl - ns) / 2
    ntr = ns
    o = c.obuf
    t = c.tbuf
    seq = c.seq
    wlp = usac_window(nl, c.shape_prev == 1)
    ws = usac_window(ns, c.shape == 1)
    wsp = usac_window(ntr, c.shape_prev == 1)
    if seq == USAC_ONLY_LONG || seq == USAC_LONG_START
      usac_imdct(c.coef, 0, t, 0, nl)
      usac_vmul(t, 0, wlp, 0, nl)
      usac_vmul_rev(o, 0, wlp, 0, nl)
      usac_vadd(o, 0, t, 0, nl)
      usac_copy(o, nl, t, nl, nl)
    elsif seq == USAC_LONG_STOP || seq == USAC_STOP_START
      usac_imdct(c.coef, 0, t, 0, nl)
      usac_vmul(t, nflat, wsp, 0, ntr)
      usac_vzero(t, 0, nflat)
      usac_vmul_rev(o, nflat, wsp, 0, ntr)
      usac_vzero(o, nflat + ntr, nflat)
      usac_vadd(o, 0, t, 0, nl)
      usac_copy(o, nl, t, nl, nl)
    else
      usac_vzero(o, nl, nl)
      fp = nflat
      k = 0
      while k < 8
        usac_imdct(c.coef, k * ns, t, 0, ns)
        if k == 0
          usac_vmul(t, 0, wsp, 0, ns)
          usac_vzero(o, fp + ntr, nflat)
          usac_vmul_rev(o, fp, wsp, 0, ntr)
        else
          usac_vmul(t, 0, ws, 0, ns)
        usac_vadd(o, fp, t, 0, ns)
        usac_vmul_rev(t, ns, ws, 0, ns) if k < 7
        usac_vadd(o, fp + ns, t, ns, ns)
        fp += ns
        k += 1
      usac_vzero(o, 2 * nl - nflat, nflat)
    usac_copy(c.out, 0, o, 0, nl)
    usac_copy(o, 0, o, nl, nl)
    usac_vzero(o, nl, nl)
    nil

-> usac_mdst_kind(seq)
  return 1 if seq == USAC_LONG_START
  return 2 if seq == USAC_LONG_STOP
  return 3 if seq == USAC_STOP_START
  0

-> usac_slice(tab, start, n)
  a = i64[n]
  i = 0
  while i < n
    a[i] = tab[start + i]
    i += 1
  a

# scalefactor Huffman codebook (AAC's), symbol 0..120 or -1
-> aac_huff_sym(bs, st)
  aac_huff(bs, st, AAC_HT, AAC_HROOT[0])

# channelConfigurationIndex -> output channel positions (0 L, 1 R, 2 C, 3 LFE, 4 Ls, 5 Rs, ...)
-> usac_default_layout(cci)
  return [2] if cci == 1
  return [0, 1] if cci == 2
  return [2, 0, 1] if cci == 3
  return [2, 0, 1, 10] if cci == 4
  return [2, 0, 1, 4, 5] if cci == 5
  return [2, 0, 1, 4, 5, 3] if cci == 6
  return [2, 6, 7, 0, 1, 4, 5, 3] if cci == 7
  return [0, 1] if cci == 8
  return [0, 1, 10] if cci == 9
  return [0, 1, 4, 5] if cci == 10
  return [2, 0, 1, 4, 5, 10, 3] if cci == 11
  return [2, 0, 1, 4, 5, 8, 9, 3] if cci == 12
  []

# element-order channel index for each WAVE output slot
-> usac_wave_order(cci, nch)
  return [1, 2, 0] if cci == 3 && nch == 3
  return [1, 2, 0, 3] if cci == 4 && nch == 4
  return [1, 2, 0, 3, 4] if cci == 5 && nch == 5
  return [1, 2, 0, 5, 3, 4] if cci == 6 && nch == 6
  return [3, 4, 0, 7, 5, 6, 1, 2] if cci == 7 && nch == 8
  o = []
  i = 0
  while i < nch
    o.push(i)
    i += 1
  o
