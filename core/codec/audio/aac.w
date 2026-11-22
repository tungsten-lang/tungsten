# core/codec/audio/aac — an AAC decoder (ISO/IEC 14496-3): AAC-LC, HE-AAC v1 (SBR) and
# HE-AAC v2 (Parametric Stereo), in pure Tungsten.
#
#   acodec_register("mp4a", ->(cfg) AacDec.new(cfg))
#   dec.decode(sample) -> AudioBlock (1024 frames, or 2048 with SBR)
#   aac_es_parse(bytes) -> {cfg:, samples:, duration:} for ADTS files
#
# cfg.extra is the AudioSpecificConfig (object type incl. escape 31, explicit
# or indexed sampling rate, channel configuration 0-7/11/12 or a
# program_config_element, GASpecificConfig, explicit hierarchical SBR/PS
# signalling and the backward-compatible 0x2b7 / 0x548 sync extensions).
# Implicit SBR (no extension in the config but SBR data in the stream, as in
# every ADTS HE-AAC file) is detected on the first frame: from then on the
# output runs at twice the core rate; a mono stream whose first frame carries
# PS data is output as stereo. AudioBlock.sample_rate tells the pipeline.
#
# Each MediaSample holds one raw_data_block (MP4 / Matroska framing); an ADTS
# frame with several raw blocks becomes one sample that decodes to n*1024
# frames. A corrupt frame decodes to silence (counted in `errors`) rather
# than raising, so playback carries on.
#
# Output channel order is WAVE: L R C LFE Ls Rs (Lc Rc for config 7).
#
# Structure: the bitstream reader keeps its bit position in st[0] (st[1] =
# end in bits, st[2] = overread flag) over a zero-padded u8[]. Huffman
# codebooks are two-level lookup tables (9-bit root) in one shared i32[].
# All DSP (dequantisation, M/S, intensity, PNS, TNS, IMDCT via an N/4-point
# complex FFT, windowing / overlap-add) runs in typed functions over f64[].
# PNS uses FFmpeg's LCG so the noise matches the FFmpeg reference decoder.

use core/codec/media
use aac_tables
use aac_sbr
use aac_ps

AAC_PI = ~3.141592653589793
AAC_RATES = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]

-> aac_rate_index(rate)
  return 0 if rate >= 92017
  return 1 if rate >= 75132
  return 2 if rate >= 55426
  return 3 if rate >= 46009
  return 4 if rate >= 37566
  return 5 if rate >= 27713
  return 6 if rate >= 23004
  return 7 if rate >= 18783
  return 8 if rate >= 13856
  return 9 if rate >= 11502
  return 10 if rate >= 9391
  11

-> aac_fail(msg)
  raise MediaError.new(msg)

-> aac_as_u8(x)
  if x.is_a?(String)
    return ccall("w_string_bytes_view", x) ## u8[]
  x

-> aac_i64s(list)
  a = i64[list.size]
  i = 0
  while i < list.size
    a[i] = list[i]
    i += 1
  a

-> aac_f64s(list)
  a = f64[list.size]
  i = 0
  while i < list.size
    a[i] = list[i]
    i += 1
  a

# ---- Huffman tables ----
# Entry >= 0: (symbol << 5) | length; length 0 = invalid code.
# Entry < 0: -((subtable offset << 5) | subtable bits); sub entries hold
# (symbol << 5) | (length - 9).

-> aac_hb(tab, codes, lens, syms, first, n)
  root = tab.size
  i = 0
  while i < 512
    tab.push(0)
    i += 1
  maxl = []
  i = 0
  while i < 512
    maxl.push(0)
    i += 1
  i = 0
  while i < n
    l = lens[first + i]
    c = codes[first + i]
    s = i
    s = syms[first + i] if syms != nil
    if l <= 9
      base = c << (9 - l)
      j = 0
      while j < (1 << (9 - l))
        tab[root + base + j] = (s << 5) | l
        j += 1
    else
      p = c >> (l - 9)
      maxl[p] = l if l > maxl[p]
    i += 1
  subs = []
  i = 0
  while i < 512
    subs.push(0)
    if maxl[i] > 0
      sb = maxl[i] - 9
      subs[i] = tab.size
      tab[root + i] = 0 - ((tab.size << 5) | sb)
      j = 0
      while j < (1 << sb)
        tab.push(0)
        j += 1
    i += 1
  i = 0
  while i < n
    l = lens[first + i]
    if l > 9
      c = codes[first + i]
      s = i
      s = syms[first + i] if syms != nil
      p = c >> (l - 9)
      sb = maxl[p] - 9
      e = l - 9
      base = subs[p] + ((c & ((1 << e) - 1)) << (sb - e))
      j = 0
      while j < (1 << (sb - e))
        tab[base + j] = (s << 5) | e
        j += 1
    i += 1
  root

# roots: 0 = scalefactor, 1..11 spectral, 12..21 SBR, 22..31 PS
-> aac_build_huff
  tab = []
  roots = []
  roots.push(aac_hb(tab, AAC_SF_CODE, AAC_SF_BITS, nil, 0, 121))
  b = 1
  while b <= 11
    o = AAC_SPEC_OFFS[b - 1]
    roots.push(aac_hb(tab, AAC_SPEC_CODES, AAC_SPEC_BITS, nil, o, AAC_SPEC_OFFS[b] - o))
    b += 1
  b = 0
  while b < 10
    o = SBR_HUFF_OFFS[b]
    roots.push(aac_hb(tab, SBR_HUFF_CODE, SBR_HUFF_LEN, SBR_HUFF_SYM, o, SBR_HUFF_OFFS[b + 1] - o))
    b += 1
  b = 0
  while b < 10
    o = PS_HUFF_OFFS[b]
    roots.push(aac_hb(tab, PS_HUFF_CODE, PS_HUFF_LEN, PS_HUFF_SYM, o, PS_HUFF_OFFS[b + 1] - o))
    b += 1
  ht = i32[tab.size]
  i = 0
  while i < tab.size
    ht[i] = tab[i]
    i += 1
  [ht, aac_i64s(roots)]

AAC_HUFF = aac_build_huff()
AAC_HT = AAC_HUFF[0]
AAC_HROOT = AAC_HUFF[1]

# |x|^(4/3) for x < 8192
-> aac_build_pow43
  a = f64[8192]
  i = 0
  while i < 8192
    x = i ## f64
    a[i] = Math.cbrt(x) * x
    i += 1
  a

AAC_POW43 = aac_build_pow43()

# 2^((i - 300) / 4)
-> aac_build_p2
  a = f64[601]
  i = 0
  while i < 601
    a[i] = Math.pow(~2.0, ((i - 300) ## f64) * ~0.25)
    i += 1
  a

AAC_P2 = aac_build_p2()

-> aac_bessel_i0(x)
  s = ~1.0
  t = ~1.0
  k = 1
  while k < 200
    h = x / ((k * 2) ## f64)
    t = t * h * h
    s += t
    break if t < s * ~1.0e-18
    k += 1
  s

-> aac_kbd(alpha, n)
  w = f64[n]
  tmp = f64[n / 2 + 1]
  alpha2 = ~4.0 * (alpha * AAC_PI / (n ## f64)) * (alpha * AAC_PI / (n ## f64))
  scale = ~0.0
  i = 0
  while i <= n / 2
    t = ((i * (n - i)) ## f64) * alpha2
    tmp[i] = aac_bessel_i0(Math.sqrt(t))
    if i > 0 && i < n / 2
      scale += tmp[i] * ~2.0
    else
      scale += tmp[i]
    i += 1
  scale = ~1.0 / (scale + ~1.0)
  sum = ~0.0
  i = 0
  while i <= n / 2
    sum += tmp[i]
    w[i] = Math.sqrt(sum * scale)
    i += 1
  while i < n
    sum += tmp[n - i]
    w[i] = Math.sqrt(sum * scale)
    i += 1
  w

-> aac_sine(n)
  w = f64[n]
  i = 0
  while i < n
    w[i] = Math.sin(((i ## f64) + ~0.5) * AAC_PI / ((2 * n) ## f64))
    i += 1
  w

AAC_SINE_L = aac_sine(1024)
AAC_SINE_S = aac_sine(128)
AAC_KBD_L = aac_kbd(~4.0, 1024)
AAC_KBD_S = aac_kbd(~6.0, 128)

# IMDCT tables. md layout per size (n = 2048 / 256, n4 = n / 4):
#   tcos[n4] tsin[n4] fft-cos[n4 / 2] fft-sin[n4 / 2]
# long at 0, short at 1536; revtab long at 0, short at 512.
AAC_MD_S = 1536

-> aac_md_fill(md, rev, mo, ro, n, scale)
  n4 = n / 4
  bits = 0
  while (1 << bits) < n4
    bits += 1
  s = Math.sqrt(scale)
  k = 0
  while k < n4
    a = ~2.0 * AAC_PI * ((k ## f64) + ~0.125) / (n ## f64)
    md[mo + k] = ~0.0 - Math.cos(a) * s
    md[mo + n4 + k] = ~0.0 - Math.sin(a) * s
    r = 0
    b = 0
    while b < bits
      r = r | (((k >> b) & 1) << (bits - 1 - b))
      b += 1
    rev[ro + k] = r
    k += 1
  k = 0
  while k < n4 / 2
    a = ~2.0 * AAC_PI * (k ## f64) / (n4 ## f64)
    md[mo + 2 * n4 + k] = Math.cos(a)
    md[mo + 2 * n4 + n4 / 2 + k] = Math.sin(a)
    k += 1

-> aac_build_md
  md = f64[1536 + 192]
  rev = i64[512 + 64]
  aac_md_fill(md, rev, 0, 0, 2048, ~1.0 / (~1024.0 * ~32768.0))
  aac_md_fill(md, rev, AAC_MD_S, 512, 256, ~1.0 / (~128.0 * ~32768.0))
  [md, rev]

AAC_MDT = aac_build_md()
AAC_MD = AAC_MDT[0]
AAC_REV = AAC_MDT[1]

AAC_SWB_L_ALL = aac_i64s(AAC_SWB_1024)
AAC_SWB_S_ALL = aac_i64s(AAC_SWB_128)

# ---- bit reader ----

-> aac_bits(bs, st, n) (u8[] i64[] i64) i64
  pos = st[0]
  by = pos >> 3
  st[0] = pos + n
  if by + 5 > bs.size
    st[2] = 1
    return 0
  w = (bs[by] << 32) | (bs[by + 1] << 24) | (bs[by + 2] << 16) | (bs[by + 3] << 8) | bs[by + 4]
  (w >> (40 - (pos & 7) - n)) & ((1 << n) - 1)

-> aac_huff(bs, st, ht, root) (u8[] i64[] i32[] i64) i64
  pos = st[0]
  by = pos >> 3
  if by + 5 > bs.size
    st[2] = 1
    return -1
  w = (bs[by] << 32) | (bs[by + 1] << 24) | (bs[by + 2] << 16) | (bs[by + 3] << 8) | bs[by + 4]
  sh = pos & 7
  e = ht[root + ((w >> (31 - sh)) & 511)]
  if e >= 0
    l = e & 31
    if l == 0
      st[2] = 1
      return -1
    st[0] = pos + l
    return e >> 5
  ne = 0 - e
  sb = ne & 31
  e2 = ht[(ne >> 5) + ((w >> (31 - sh - sb)) & ((1 << sb) - 1))]
  l2 = e2 & 31
  if l2 == 0
    st[2] = 1
    return -1
  st[0] = pos + 9 + l2
  e2 >> 5

# ---- spectral data ----

# Decode the quantised spectrum into q (window w at w * 128). 0 = ok.
-> aac_spec(bs, st, ht, roots, bt, swb, max_sfb, ngroups, glen, q) (u8[] i64[] i32[] i64[] i64[] i64[] i64 i64 i64[] i32[]) i64
  i = 0
  while i < 1024
    q[i] = 0
    i += 1
  ws = 0
  g = 0
  while g < ngroups
    gl = glen[g]
    sfb = 0
    while sfb < max_sfb
      cb = bt[g * max_sfb + sfb]
      if cb >= 1 && cb <= 11
        root = roots[cb]
        w = 0
        while w < gl
          k = (ws + w) * 128 + swb[sfb]
          kend = (ws + w) * 128 + swb[sfb + 1]
          while k < kend
            idx = aac_huff(bs, st, ht, root)
            if idx < 0
              return 1
            if cb <= 2
              q[k] = idx / 27 - 1
              q[k + 1] = (idx / 9) % 3 - 1
              q[k + 2] = (idx / 3) % 3 - 1
              q[k + 3] = idx % 3 - 1
              k += 4
            elsif cb <= 4
              v0 = idx / 27
              v1 = (idx / 9) % 3
              v2 = (idx / 3) % 3
              v3 = idx % 3
              if v0 != 0
                v0 = 0 - v0 if aac_bits(bs, st, 1) == 1
              if v1 != 0
                v1 = 0 - v1 if aac_bits(bs, st, 1) == 1
              if v2 != 0
                v2 = 0 - v2 if aac_bits(bs, st, 1) == 1
              if v3 != 0
                v3 = 0 - v3 if aac_bits(bs, st, 1) == 1
              q[k] = v0
              q[k + 1] = v1
              q[k + 2] = v2
              q[k + 3] = v3
              k += 4
            elsif cb <= 6
              q[k] = idx / 9 - 4
              q[k + 1] = idx % 9 - 4
              k += 2
            else
              m = 8
              m = 13 if cb >= 9
              m = 17 if cb == 11
              v0 = idx / m
              v1 = idx % m
              s0 = 0
              s1 = 0
              s0 = aac_bits(bs, st, 1) if v0 != 0
              s1 = aac_bits(bs, st, 1) if v1 != 0
              if cb == 11
                if v0 == 16
                  n = 0
                  while aac_bits(bs, st, 1) == 1
                    n += 1
                    if n > 8
                      return 2
                  v0 = (1 << (n + 4)) + aac_bits(bs, st, n + 4)
                if v1 == 16
                  n = 0
                  while aac_bits(bs, st, 1) == 1
                    n += 1
                    if n > 8
                      return 2
                  v1 = (1 << (n + 4)) + aac_bits(bs, st, n + 4)
              v0 = 0 - v0 if s0 == 1
              v1 = 0 - v1 if s1 == 1
              q[k] = v0
              q[k + 1] = v1
              k += 2
          if st[2] != 0
            return 3
          w += 1
      sfb += 1
    ws += gl
    g += 1
  0

# Scalefactors -> linear gains in sf (per group * max_sfb + sfb). 0 = ok.
-> aac_sf(bs, st, ht, root, bt, sf, ngroups, max_sfb, gg, p2) (u8[] i64[] i32[] i64 i64[] f64[] i64 i64 i64 f64[]) i64
  off0 = gg
  off1 = gg - 90
  off2 = 0
  nflag = 1
  n = ngroups * max_sfb
  idx = 0
  while idx < n
    cb = bt[idx]
    if cb == 0
      sf[idx] = ~0.0
    elsif cb == 14 || cb == 15
      d = aac_huff(bs, st, ht, root)
      if d < 0
        return 1
      off2 += d - 60
      c = off2
      c = -155 if c < -155
      c = 100 if c > 100
      sf[idx] = p2[300 - c]
    elsif cb == 13
      if nflag == 1
        off1 += aac_bits(bs, st, 9) - 256
        nflag = 0
      else
        d = aac_huff(bs, st, ht, root)
        if d < 0
          return 1
        off1 += d - 60
      c = off1
      c = -100 if c < -100
      c = 155 if c > 155
      sf[idx] = p2[300 + c]
    else
      d = aac_huff(bs, st, ht, root)
      if d < 0
        return 1
      off0 += d - 60
      if off0 < 0 || off0 > 255
        return 2
      sf[idx] = p2[200 + off0]
    idx += 1
  0

# Dequantise q into coef; PNS bands get FFmpeg-compatible LCG noise.
-> aac_dequant(q, coef, bt, sf, swb, max_sfb, ngroups, glen, pow43, rng) (i32[] f64[] i64[] f64[] i64[] i64 i64 i64[] f64[] i64[]) i64
  i = 0
  while i < 1024
    coef[i] = ~0.0
    i += 1
  ws = 0
  g = 0
  while g < ngroups
    gl = glen[g]
    sfb = 0
    while sfb < max_sfb
      idx = g * max_sfb + sfb
      cb = bt[idx]
      gain = sf[idx]
      if cb >= 1 && cb <= 11
        w = 0
        while w < gl
          k = (ws + w) * 128 + swb[sfb]
          kend = (ws + w) * 128 + swb[sfb + 1]
          while k < kend
            v = q[k]
            if v > 0
              coef[k] = pow43[v] * gain
            elsif v < 0
              coef[k] = ~0.0 - pow43[0 - v] * gain
            k += 1
          w += 1
      elsif cb == 13
        w = 0
        while w < gl
          k0 = (ws + w) * 128 + swb[sfb]
          kend = (ws + w) * 128 + swb[sfb + 1]
          r = rng[0]
          e = ~0.0
          k = k0
          while k < kend
            r = (r * 1664525 + 1013904223) & 4294967295
            s = r
            s = r - 4294967296 if r >= 2147483648
            x = ((s ## f64) ## f32) ## f64
            coef[k] = x
            e += x * x
            k += 1
          rng[0] = r
          scale = gain / Math.sqrt(e)
          k = k0
          while k < kend
            coef[k] = coef[k] * scale
            k += 1
          w += 1
      sfb += 1
    ws += gl
    g += 1
  0

-> aac_ms(c0, c1, bt0, bt1, msm, swb, max_sfb, ngroups, glen) (f64[] f64[] i64[] i64[] i64[] i64[] i64 i64 i64[]) i64
  ws = 0
  g = 0
  while g < ngroups
    gl = glen[g]
    w = 0
    while w < gl
      sfb = 0
      while sfb < max_sfb
        idx = g * max_sfb + sfb
        if msm[idx] != 0 && bt0[idx] < 13 && bt1[idx] < 13
          k = (ws + w) * 128 + swb[sfb]
          kend = (ws + w) * 128 + swb[sfb + 1]
          while k < kend
            a = c0[k]
            b = c1[k]
            c0[k] = a + b
            c1[k] = a - b
            k += 1
        sfb += 1
      w += 1
    ws += gl
    g += 1
  0

-> aac_is(c0, c1, bt1, sf1, msm, ms_present, swb, max_sfb, ngroups, glen) (f64[] f64[] i64[] f64[] i64[] i64 i64[] i64 i64 i64[]) i64
  ws = 0
  g = 0
  while g < ngroups
    gl = glen[g]
    sfb = 0
    while sfb < max_sfb
      idx = g * max_sfb + sfb
      b = bt1[idx]
      if b == 14 || b == 15
        c = ~1.0
        c = ~-1.0 if b == 14
        if ms_present != 0 && msm[idx] != 0
          c = ~0.0 - c
        scale = c * sf1[idx]
        w = 0
        while w < gl
          k = (ws + w) * 128 + swb[sfb]
          kend = (ws + w) * 128 + swb[sfb + 1]
          while k < kend
            c1[k] = c0[k] * scale
            k += 1
          w += 1
      sfb += 1
    ws += gl
    g += 1
  0

# TNS. tns: per window w at w * 16: [nfilt, (length, order, direction) * 4];
# tc: per window/filter 32 parcor values at (w * 4 + f) * 32.
-> aac_tns(coef, swb, nwin, num_swb, mmm, tns, tc) (f64[] i64[] i64 i64 i64 i64[] f64[]) i64
  if mmm <= 0
    return 0
  lpc = f64[32]
  w = 0
  while w < nwin
    bottom = num_swb
    nf = tns[w * 16]
    f = 0
    while f < nf
      top = bottom
      bottom = top - tns[w * 16 + 1 + f * 3]
      bottom = 0 if bottom < 0
      order = tns[w * 16 + 2 + f * 3]
      if order > 0
        cb = (w * 4 + f) * 32
        i = 0
        while i < order
          r = ~0.0 - tc[cb + i]
          lpc[i] = r
          j = 0
          while j < ((i + 1) >> 1)
            fv = lpc[j]
            bv = lpc[i - 1 - j]
            lpc[j] = fv + r * bv
            lpc[i - 1 - j] = bv + r * fv
            j += 1
          i += 1
        lo = bottom
        lo = mmm if lo > mmm
        hi = top
        hi = mmm if hi > mmm
        start = swb[lo]
        en = swb[hi]
        size = en - start
        if size > 0
          inc = 1
          if tns[w * 16 + 3 + f * 3] != 0
            inc = -1
            start = en - 1
          start += w * 128
          m = 0
          while m < size
            lim = m
            lim = order if lim > order
            acc = coef[start]
            i = 1
            while i <= lim
              acc -= coef[start - i * inc] * lpc[i - 1]
              i += 1
            coef[start] = acc
            start += inc
            m += 1
      f += 1
    w += 1
  0

# ---- filterbank ----

# Radix-2 DIT complex FFT, input in bit-reversed order. tw: cos at to, sin
# at to + n / 2 (exp(+i 2 pi k / n)).
-> aac_fft(re, im, n, tw, to) (f64[] f64[] i64 f64[] i64) i64
  # first two stages combined (radix-4 butterflies)
  i = 0
  while i < n
    ar = re[i]
    ai = im[i]
    br = re[i + 1]
    bi = im[i + 1]
    cr = re[i + 2]
    ci = im[i + 2]
    dr = re[i + 3]
    di = im[i + 3]
    t0r = ar + br
    t0i = ai + bi
    t1r = ar - br
    t1i = ai - bi
    t2r = cr + dr
    t2i = ci + di
    t3r = cr - dr
    t3i = ci - di
    re[i] = t0r + t2r
    im[i] = t0i + t2i
    re[i + 2] = t0r - t2r
    im[i + 2] = t0i - t2i
    # t3 * (+i)
    re[i + 1] = t1r - t3i
    im[i + 1] = t1i + t3r
    re[i + 3] = t1r + t3i
    im[i + 3] = t1i - t3r
    i += 4
  half_n = n >> 1
  size = 8
  while size <= n
    half = size >> 1
    step = n / size
    i = 0
    while i < n
      j = 0
      k = 0
      while j < half
        wr = tw[to + k]
        wi = tw[to + half_n + k]
        a = i + j
        b = a + half
        xr = re[b]
        xi = im[b]
        tr = xr * wr - xi * wi
        ti = xr * wi + xi * wr
        re[b] = re[a] - tr
        im[b] = im[a] - ti
        re[a] = re[a] + tr
        im[a] = im[a] + ti
        j += 1
        k += step
      i += size
    size = size << 1
  0

# Half IMDCT (FFmpeg's imdct_half): n2 = 2 * n4 coefficients at inp[io] ->
# n2 samples at out[oo] (the middle half of the full IMDCT output).
-> aac_imdct_half(inp, io, out, oo, n4, md, mo, rev, ro, re, im) (f64[] i64 f64[] i64 i64 f64[] i64 i64[] i64 f64[] f64[]) i64
  n2 = n4 * 2
  n8 = n4 >> 1
  k = 0
  while k < n4
    j = rev[ro + k]
    in1 = inp[io + 2 * k]
    in2 = inp[io + n2 - 1 - 2 * k]
    c = md[mo + k]
    s = md[mo + n4 + k]
    re[j] = in1 * s - in2 * c
    im[j] = ~0.0 - (in2 * s + in1 * c)
    k += 1
  aac_fft(re, im, n4, md, mo + 2 * n4)
  k = 0
  while k < n8
    a = n8 - k - 1
    b = n8 + k
    ca = md[mo + a]
    sa = md[mo + n4 + a]
    cb = md[mo + b]
    sb = md[mo + n4 + b]
    r0 = im[a] * sa - re[a] * ca
    i1 = im[a] * ca + re[a] * sa
    r1 = im[b] * sb - re[b] * cb
    i0 = im[b] * cb + re[b] * sb
    re[a] = r0
    im[a] = i0
    re[b] = r1
    im[b] = i1
    k += 1
  k = 0
  while k < n4
    out[oo + 2 * k] = re[k]
    out[oo + 2 * k + 1] = im[k]
    k += 1
  0

-> aac_vfw(dst, d, src0, s0, src1, s1, win, wo, len) (f64[] i64 f64[] i64 f64[] i64 f64[] i64 i64) i64
  t = 0
  l2 = 2 * len - 1
  while t < len
    a = src0[s0 + t]
    b = src1[s1 + len - 1 - t]
    wi = win[wo + t]
    wj = win[wo + l2 - t]
    dst[d + t] = a * wj - b * wi
    dst[d + l2 - t] = a * wi + b * wj
    t += 1
  0

-> aac_copy(dst, d, src, s, n) (f64[] i64 f64[] i64 i64) i64
  i = 0
  while i < n
    dst[d + i] = src[s + i]
    i += 1
  0

# IMDCT + windowing + overlap-add of one channel (FFmpeg's structure).
# seq/pseq: window sequence now / before; lwp: previous long window,
# sw / swp: current / previous short window. Writes 1024 samples to out.
-> aac_filterbank(coef, buf, saved, out, tmp, seq, pseq, lwp, sw, swp, md, rev, re, im) (f64[] f64[] f64[] f64[] f64[] i64 i64 f64[] f64[] f64[] f64[] i64[] f64[] f64[]) i64
  if seq == 2
    i = 0
    while i < 8
      aac_imdct_half(coef, i * 128, buf, i * 128, 64, md, 1536, rev, 512, re, im)
      i += 1
  else
    aac_imdct_half(coef, 0, buf, 0, 512, md, 0, rev, 0, re, im)
  if (pseq == 0 || pseq == 3) && (seq == 0 || seq == 1)
    aac_vfw(out, 0, saved, 0, buf, 0, lwp, 0, 512)
  else
    aac_copy(out, 0, saved, 0, 448)
    if seq == 2
      aac_vfw(out, 448, saved, 448, buf, 0, swp, 0, 64)
      aac_vfw(out, 576, buf, 64, buf, 128, sw, 0, 64)
      aac_vfw(out, 704, buf, 192, buf, 256, sw, 0, 64)
      aac_vfw(out, 832, buf, 320, buf, 384, sw, 0, 64)
      aac_vfw(tmp, 0, buf, 448, buf, 512, sw, 0, 64)
      aac_copy(out, 960, tmp, 0, 64)
    else
      aac_vfw(out, 448, saved, 448, buf, 0, swp, 0, 64)
      aac_copy(out, 576, buf, 64, 448)
  if seq == 2
    aac_copy(saved, 0, tmp, 64, 64)
    aac_vfw(saved, 64, buf, 576, buf, 640, sw, 0, 64)
    aac_vfw(saved, 192, buf, 704, buf, 768, sw, 0, 64)
    aac_vfw(saved, 320, buf, 832, buf, 896, sw, 0, 64)
    aac_copy(saved, 448, buf, 960, 64)
  elsif seq == 1
    aac_copy(saved, 0, buf, 512, 448)
    aac_copy(saved, 448, buf, 960, 64)
  else
    aac_copy(saved, 0, buf, 512, 512)
  0

# Interleave one channel into the f32 output, clamped to -1..1.
-> aac_interleave(dst, src, so, n, nch, c) (f32[] f64[] i64 i64 i64 i64) i64
  i = 0
  while i < n
    x = src[so + i]
    x = ~1.0 if x > ~1.0
    x = ~-1.0 if x < ~-1.0
    dst[i * nch + c] = x ## f32
    i += 1
  0

-> aac_zero_ch(dst, n, nch, c) (f32[] i64 i64 i64) i64
  i = 0
  while i < n
    dst[i * nch + c] = (~0.0) ## f32
    i += 1
  0

-> aac_zero(a, n) (f64[] i64) i64
  i = 0
  while i < n
    a[i] = ~0.0
    i += 1
  0

# ---- per-channel state ----

# info: 0 window_sequence, 1 previous window_sequence, 2 window_shape,
# 3 previous shape, 4 max_sfb, 5 window groups, 6 windows, 7 num_swb,
# 8..15 group lengths, 16 tns_max_bands, 17 tns present, 18 pulse present
+ AacChan
  ro :info, :glen, :coef, :q, :bt, :sf, :saved, :buf, :pcm, :tmp, :tns, :tc, :pulse, :sbr

  -> new
    @info = i64[32]
    @glen = i64[8]
    @coef = f64[1024]
    @q = i32[1024]
    @bt = i64[128]
    @sf = f64[128]
    @saved = f64[1024]
    @buf = f64[1024]
    @pcm = f64[2048]
    @tmp = f64[128]
    @tns = i64[8 * 16]
    @tc = f64[8 * 4 * 32]
    @pulse = i64[10]
    @sbr = nil

  -> sbr=(s)
    @sbr = s

  -> reset
    aac_zero(@saved, 1024)
    @info[0] = 0
    @info[1] = 0
    @info[2] = 0
    @info[3] = 0
    @sbr.reset if @sbr != nil

# ---- AudioSpecificConfig ----

+ AacConfig
  rw :aot, :rate, :sfi, :chcfg, :ext_aot, :ext_rate, :sbr, :ps, :frame_len, :pce

  -> new
    @aot = 2
    @rate = 44100
    @sfi = 4
    @chcfg = 2
    @ext_aot = 0
    @ext_rate = 0
    @sbr = -1
    @ps = -1
    @frame_len = 1024
    @pce = nil

# Program config element: {front:, side:, back:, lfe:} lists of [is_cpe, tag].
-> aac_read_pce(r)
  r.bits(4)
  r.bits(2)
  r.bits(4)
  nf = r.bits(4)
  ns = r.bits(4)
  nb = r.bits(4)
  nl = r.bits(2)
  na = r.bits(3)
  nc = r.bits(4)
  r.bits(4) if r.bits(1) == 1
  r.bits(4) if r.bits(1) == 1
  r.bits(3) if r.bits(1) == 1
  front = []
  side = []
  back = []
  lfe = []
  nf.times -> front.push([r.bits(1), r.bits(4)])
  ns.times -> side.push([r.bits(1), r.bits(4)])
  nb.times -> back.push([r.bits(1), r.bits(4)])
  nl.times -> lfe.push([0, r.bits(4)])
  na.times -> r.bits(4)
  nc.times -> r.bits(5)
  r.align
  cl = r.bits(8)
  r.skip(cl * 8)
  {front: front, side: side, back: back, lfe: lfe}

# A plain MSB-first reader for headers (config, ADTS).
+ AacBitReader
  ro :pos

  -> new(@data, @pos = 0)
    @nbits = @data.size * 8

  -> bits(n)
    v = 0
    i = 0
    while i < n
      b = 0
      if @pos < @nbits
        b = (@data[@pos >> 3] >> (7 - (@pos & 7))) & 1
      v = (v << 1) | b
      @pos += 1
      i += 1
    v

  -> skip(n)
    @pos += n

  -> align
    @pos = (@pos + 7) & -8

  -> left
    @nbits - @pos

-> aac_get_aot(r)
  t = r.bits(5)
  t = 32 + r.bits(6) if t == 31
  t

-> aac_get_rate(r)
  i = r.bits(4)
  return r.bits(24) if i == 15
  return 0 if i >= 13
  AAC_RATES[i]

-> aac_parse_asc(bytes)
  c = AacConfig.new
  r = AacBitReader.new(bytes)
  c.aot = aac_get_aot(r)
  c.rate = aac_get_rate(r)
  c.chcfg = r.bits(4)
  if c.aot == 5 || c.aot == 29
    c.ext_aot = 5
    c.sbr = 1
    c.ps = 1 if c.aot == 29
    c.ext_rate = aac_get_rate(r)
    c.aot = aac_get_aot(r)
    r.bits(4) if c.aot == 22
  if [1, 2, 3, 4, 6, 7, 17, 19, 20, 21, 22, 23].include?(c.aot)
    c.frame_len = 960 if r.bits(1) == 1
    r.bits(14) if r.bits(1) == 1
    ext = r.bits(1)
    if c.chcfg == 0 && r.left >= 34
      pce = aac_read_pce(r)
      # an ADTS-derived config carries no PCE: keep nil (in-band PCE / dynamic)
      n = pce[:front].size + pce[:side].size + pce[:back].size + pce[:lfe].size
      c.pce = pce if n > 0
    r.bits(3) if c.aot == 6 || c.aot == 20
    if ext == 1
      if c.aot == 22
        r.bits(5)
        r.bits(11)
      r.bits(3) if c.aot == 17 || c.aot == 19 || c.aot == 20 || c.aot == 23
      r.bits(1)
  else
    aac_fail("aac: unsupported audio object type [c.aot]")
  if c.ext_aot != 5 && r.left >= 16
    if r.bits(11) == 0x2b7
      e = aac_get_aot(r)
      if e == 5
        if r.bits(1) == 1
          c.ext_aot = 5
          c.sbr = 1
          c.ext_rate = aac_get_rate(r)
          if r.left >= 12 && r.bits(11) == 0x548
            c.ps = r.bits(1)
        else
          c.sbr = 0
  if c.ext_aot == 5 && c.ps == -1 && r.left >= 12
    if r.bits(11) == 0x548
      c.ps = r.bits(1)
  aac_fail("aac: bad sampling rate") if c.rate <= 0
  c.sfi = aac_rate_index(c.rate)
  c.ext_rate = c.rate * 2 if c.sbr == 1 && c.ext_rate <= 0
  c

# Build the AudioSpecificConfig bytes for (object type, rate, channel config).
-> aac_make_asc(aot, rate, chcfg)
  idx = AAC_RATES.index(rate)
  if idx == nil
    b = u8[5]
    v = (aot << 35) | (15 << 31) | (rate << 7) | (chcfg << 3)
    i = 0
    while i < 5
      b[i] = (v >> (32 - i * 8)) & 255
      i += 1
    return b
  b = u8[2]
  v = (aot << 11) | (idx << 7) | (chcfg << 3)
  b[0] = v >> 8
  b[1] = v & 255
  b

# ---- decoder ----

AAC_SCE = 0
AAC_CPE = 1
AAC_CCE = 2
AAC_LFE = 3
AAC_DSE = 4
AAC_PCE = 5
AAC_FIL = 6
AAC_END = 7

+ AacDec
  ro :channels, :sample_rate, :errors, :cfg_info, :sbr_on, :ps_on, :stats, :last_error

  -> new(cfg)
    ex = cfg.extra
    ex = aac_as_u8(ex)
    if ex == nil || ex.size < 2
      sr = cfg.sample_rate
      sr = 44100 if sr == nil || sr <= 0
      ch = cfg.channels
      ch = 2 if ch == nil || ch <= 0
      ex = aac_make_asc(2, sr, ch)
    @cfg_info = aac_parse_asc(ex)
    c = @cfg_info
    aac_fail("aac: 960-sample frames are not supported") if c.frame_len != 1024
    aac_fail("aac: unsupported object type [c.aot]") if c.aot != 2 && c.aot != 1 && c.aot != 4
    @sfi = c.sfi
    @core_rate = c.rate
    @swb_l = aac_i64s(AAC_SWB_1024.slice(AAC_SWB_1024_IDX[@sfi], AAC_NUM_SWB_1024[@sfi] + 1))
    @swb_s = aac_i64s(AAC_SWB_128.slice(AAC_SWB_128_IDX[@sfi], AAC_NUM_SWB_128[@sfi] + 1))
    @bs = u8[4096]
    @st = i64[4]
    @rng = i64[1]
    @rng[0] = 0x1f2e3d4c
    @re = f64[512]
    @im = f64[512]
    @msm = i64[128]
    @errors = 0
    @last_error = nil
    @stats = i64[24]
    @sbr_on = c.sbr == 1
    @ps_on = c.ps == 1
    @decided = c.sbr != -1
    @setup_done = false
    setup_channels
    @scratch = [AacChan.new, AacChan.new]

  # Slot maps: per element type a list of output slot arrays.
  -> setup_channels
    c = @cfg_info
    @sce_map = []
    @cpe_map = []
    @lfe_map = []
    @dyn = false
    case c.chcfg
    when 0
      if c.pce != nil
        setup_pce(c.pce)
      else
        @dyn = true
        @nch = 0
    when 1
      @sce_map = [[0]]
      @nch = 1
    when 2
      @cpe_map = [[0, 1]]
      @nch = 2
    when 3
      @sce_map = [[2]]
      @cpe_map = [[0, 1]]
      @nch = 3
    when 4
      @sce_map = [[2], [3]]
      @cpe_map = [[0, 1]]
      @nch = 4
    when 5
      @sce_map = [[2]]
      @cpe_map = [[0, 1], [3, 4]]
      @nch = 5
    when 6
      @sce_map = [[2]]
      @cpe_map = [[0, 1], [4, 5]]
      @lfe_map = [[3]]
      @nch = 6
    when 7
      @sce_map = [[2]]
      @cpe_map = [[6, 7], [0, 1], [4, 5]]
      @lfe_map = [[3]]
      @nch = 8
    when 11
      @sce_map = [[2], [6]]
      @cpe_map = [[0, 1], [4, 5]]
      @lfe_map = [[3]]
      @nch = 7
    when 12
      @sce_map = [[2]]
      @cpe_map = [[0, 1], [6, 7], [4, 5]]
      @lfe_map = [[3]]
      @nch = 8
    else
      aac_fail("aac: unsupported channel configuration [c.chcfg]")
    alloc_channels

  -> setup_pce(p)
    slots = 0
    fr = p[:front]
    # a leading centre SCE followed by a CPE becomes L R C
    if fr.size >= 2 && fr[0][0] == 0 && fr[1][0] == 1
      @cpe_map.push([0, 1])
      @sce_map.push([2])
      slots = 3
      if p[:lfe].size > 0
        @lfe_map.push([3])
        slots = 4
      rest = fr.slice(2, fr.size - 2) + p[:back] + p[:side]
      lfes = []
      lfes = p[:lfe].slice(1, p[:lfe].size - 1) if p[:lfe].size > 1
    else
      rest = fr + p[:back] + p[:side]
      lfes = p[:lfe]
    rest.each ->(e)
      if e[0] == 1
        @cpe_map.push([slots, slots + 1])
        slots += 2
      else
        @sce_map.push([slots])
        slots += 1
    if lfes != nil
      lfes.each ->(e)
        @lfe_map.push([slots])
        slots += 1
    @nch = slots

  -> alloc_channels
    @chans = []
    i = 0
    n = @nch
    n = 2 if n < 2
    while i < n
      @chans.push(AacChan.new)
      i += 1

  -> channels
    return 2 if @nch == 1 && @ps_on
    @nch

  -> sample_rate
    return @core_rate * 2 if @sbr_on
    @core_rate

  -> reset
    @chans.each ->(ch) ch.reset
    @scratch.each ->(ch) ch.reset
    @ps.reset if @ps != nil

  -> flush
    nil

  -> gb(n)
    aac_bits(@bs, @st, n)

  -> fail(msg)
    @last_error = msg
    aac_fail("aac: " + msg)

  -> check
    fail("bitstream overread") if @st[2] != 0 || @st[0] > @st[1]

  -> decode(sample)
    d = sample.data
    d = aac_as_u8(d)
    n = d.size
    if @bs.size < n + 16
      @bs = u8[n + 1024]
    aac_load_bytes(@bs, d, n)
    @st[0] = 0
    @st[1] = n * 8
    @st[2] = 0
    blocks = []
    ok = true
    begin
      decode_block(blocks)
      # further raw blocks (multi-block ADTS frames)
      while blocks.size < 4 && @st[1] - ((@st[0] + 7) & -8) >= 24
        @st[0] = (@st[0] + 7) & -8
        decode_block(blocks)
    rescue e
      ok = false if blocks.size == 0
      @errors += 1
    if !ok
      return silence(sample)
    make_block(blocks, sample)

  # Like decode but raises MediaError on a corrupt frame (tests / tools).
  -> decode_raise(sample)
    d = aac_as_u8(sample.data)
    n = d.size
    if @bs.size < n + 16
      @bs = u8[n + 1024]
    aac_load_bytes(@bs, d, n)
    @st[0] = 0
    @st[1] = n * 8
    @st[2] = 0
    blocks = []
    decode_block(blocks)
    make_block(blocks, sample)

  -> silence(sample)
    nch = channels
    fl = 1024
    fl = 2048 if @sbr_on
    nch = 1 if nch < 1
    AudioBlock.new(f32[fl * nch], fl, nch, sample_rate, sample.pts)

  -> make_block(blocks, sample)
    nch = channels
    fl = 1024
    fl = 2048 if @sbr_on
    total = fl * blocks.size
    out = f32[total * nch]
    bi = 0
    blocks.each ->(b)
      aac_copy_f32(out, bi * fl * nch, b, fl * nch)
      bi += 1
    AudioBlock.new(out, total, nch, sample_rate, sample.pts)

  # One raw_data_block -> interleaved f32 frame appended to blocks.
  -> decode_block(blocks)
    @n_sce = 0
    @n_cpe = 0
    @n_lfe = 0
    @els = []
    @last_el = nil
    count = 0
    while true
      id = gb(3)
      check
      break if id == AAC_END
      count += 1
      fail("too many elements") if count > 64
      tag = gb(4)
      case id
      when AAC_SCE
        decode_sce(tag, false)
      when AAC_LFE
        decode_sce(tag, true)
      when AAC_CPE
        decode_cpe(tag)
      when AAC_CCE
        decode_cce
        @last_el = nil
      when AAC_DSE
        decode_dse
      when AAC_PCE
        decode_pce_el
      when AAC_FIL
        decode_fil(tag)
      check
    finish_frame(blocks)

  -> decode_dse
    align = gb(1)
    cnt = gb(8)
    cnt += gb(8) if cnt == 255
    @st[0] = (@st[0] + 7) & -8 if align == 1
    @st[0] = @st[0] + cnt * 8

  -> decode_pce_el
    # tag already consumed: rebuild a reader at the element start
    st = @st[0] - 4
    r = AacBitReader.new(@bs, st)
    pce = aac_read_pce(r)
    @st[0] = r.pos
    # channel configuration 0 without a PCE in the config: the first
    # in-band PCE defines the layout
    if @cfg_info.chcfg == 0 && @cfg_info.pce == nil && !@setup_done && @els.size == 0
      @sce_map = []
      @cpe_map = []
      @lfe_map = []
      @dyn = false
      setup_pce(pce)
      alloc_channels

  -> decode_fil(cnt)
    cnt += gb(8) - 1 if cnt == 15
    return nil if cnt <= 0
    endpos = @st[0] + cnt * 8
    fail("fill overrun") if endpos > @st[1]
    typ = gb(4)
    if (typ == 13 || typ == 14) && @last_el != nil
      sbr_payload(typ == 14, cnt, endpos)
    @st[0] = endpos

  -> slot_chan(map, k)
    return nil if k >= map.size
    m = map[k]
    @chans[m[0]]

  -> dyn_slot(n)
    # channel configuration 0 without a PCE: assign slots on first sight
    if !@setup_done
      if n == 1
        @sce_map.push([@nch])
        @nch += 1
      else
        @cpe_map.push([@nch, @nch + 1])
        @nch += 2
      while @chans.size < @nch
        @chans.push(AacChan.new)

  -> decode_sce(tag, lfe)
    if lfe
      k = @n_lfe
      @n_lfe += 1
      map = @lfe_map
    else
      k = @n_sce
      @n_sce += 1
      dyn_slot(1) if @dyn && k >= @sce_map.size
      map = @sce_map
    ch = nil
    slot = -1
    if k < map.size
      slot = map[k][0]
      ch = @chans[slot]
    else
      ch = @scratch[0]
    decode_ics(ch, false)
    spectral_post(ch)
    filterbank(ch)
    @last_el = [0, ch, nil, slot, -1]
    @els.push(@last_el)

  -> decode_cpe(tag)
    k = @n_cpe
    @n_cpe += 1
    dyn_slot(2) if @dyn && k >= @cpe_map.size
    if k < @cpe_map.size
      s0 = @cpe_map[k][0]
      s1 = @cpe_map[k][1]
      c0 = @chans[s0]
      c1 = @chans[s1]
    else
      s0 = -1
      s1 = -1
      c0 = @scratch[0]
      c1 = @scratch[1]
    common = gb(1)
    ms = 0
    if common == 1
      read_ics_info(c0)
      copy_info(c0, c1)
      ms = gb(2)
      fail("reserved ms_mask_present") if ms == 3
      i0 = c0.info
      n = i0[5] * i0[4]
      i = 0
      while i < n
        @msm[i] = 1
        @msm[i] = gb(1) if ms == 1
        i += 1
    decode_ics(c0, common == 1)
    decode_ics(c1, common == 1)
    i1 = c1.info
    swb = @swb_l
    swb = @swb_s if i1[0] == 2
    if common == 1 && ms != 0
      aac_ms(c0.coef, c1.coef, c0.bt, c1.bt, @msm, swb, i1[4], i1[5], c1.glen)
    aac_is(c0.coef, c1.coef, c1.bt, c1.sf, @msm, ms, swb, i1[4], i1[5], c1.glen)
    spectral_post(c0)
    spectral_post(c1)
    filterbank(c0)
    filterbank(c1)
    @last_el = [1, c0, c1, s0, s1]
    @els.push(@last_el)

  -> copy_info(a, b)
    i = 0
    while i < 32
      b.info[i] = a.info[i]
      i += 1
    i = 0
    while i < 8
      b.glen[i] = a.glen[i]
      i += 1

  -> read_ics_info(ch)
    info = ch.info
    gb(1)
    info[1] = info[0]
    info[3] = info[2]
    seq = gb(2)
    info[0] = seq
    info[2] = gb(1)
    glen = ch.glen
    if seq == 2
      info[4] = gb(4)
      grp = gb(7)
      ng = 1
      glen[0] = 1
      i = 0
      while i < 7
        if ((grp >> (6 - i)) & 1) == 1
          glen[ng - 1] = glen[ng - 1] + 1
        else
          glen[ng] = 1
          ng += 1
        i += 1
      info[5] = ng
      info[6] = 8
      info[7] = AAC_NUM_SWB_128[@sfi]
      info[16] = AAC_TNS_MAX_BANDS_128[@sfi]
    else
      info[4] = gb(6)
      info[5] = 1
      info[6] = 1
      glen[0] = 1
      info[7] = AAC_NUM_SWB_1024[@sfi]
      info[16] = AAC_TNS_MAX_BANDS_1024[@sfi]
      fail("prediction not supported") if gb(1) == 1
    fail("max_sfb too large") if info[4] > info[7]

  -> decode_ics(ch, common)
    gg = gb(8)
    read_ics_info(ch) if !common
    info = ch.info
    max_sfb = info[4]
    ng = info[5]
    short = info[0] == 2
    swb = @swb_l
    swb = @swb_s if short
    # section data
    bt = ch.bt
    sbits = 5
    sbits = 3 if short
    esc = (1 << sbits) - 1
    g = 0
    while g < ng
      k = 0
      while k < max_sfb
        cb = gb(4)
        fail("reserved codebook") if cb == 12
        len = 0
        while true
          inc = gb(sbits)
          len += inc
          check
          break if inc != esc
        fail("section overrun") if k + len > max_sfb
        j = 0
        while j < len
          bt[g * max_sfb + k + j] = cb
          j += 1
        k += len
      g += 1
    j = 0
    while j < ng * max_sfb
      @stats[bt[j]] = @stats[bt[j]] + 1
      j += 1
    @stats[16 + info[0]] = @stats[16 + info[0]] + 1
    r = aac_sf(@bs, @st, AAC_HT, AAC_HROOT[0], bt, ch.sf, ng, max_sfb, gg, AAC_P2)
    fail("scalefactors") if r != 0
    # pulse
    pulse = ch.pulse
    pulse[0] = 0
    if gb(1) == 1
      fail("pulse data in short window") if short
      np = gb(2) + 1
      psfb = gb(6)
      fail("pulse sfb") if psfb >= info[7]
      pos = swb[psfb] + gb(5)
      pulse[0] = np
      pulse[1] = pos
      pulse[2] = gb(4)
      i = 1
      while i < np
        pos += gb(5)
        pulse[1 + i * 2] = pos
        pulse[2 + i * 2] = gb(4)
        i += 1
      fail("pulse pos") if pos >= 1024
    # tns
    info[17] = gb(1)
    read_tns(ch) if info[17] == 1
    @stats[20] = @stats[20] + info[17]
    @stats[21] = @stats[21] + info[2]
    @stats[22] = @stats[22] + 1 if pulse[0] > 0
    fail("gain control not supported") if gb(1) == 1
    check
    r = aac_spec(@bs, @st, AAC_HT, AAC_HROOT, bt, swb, max_sfb, ng, ch.glen, ch.q)
    fail("spectral data") if r != 0
    check
    if pulse[0] > 0
      q = ch.q
      i = 0
      while i < pulse[0]
        p = pulse[1 + i * 2]
        a = pulse[2 + i * 2]
        if q[p] > 0
          q[p] = q[p] + a
        else
          q[p] = q[p] - a
        i += 1
    aac_dequant(ch.q, ch.coef, bt, ch.sf, swb, max_sfb, ng, ch.glen, AAC_POW43, @rng)

  -> read_tns(ch)
    info = ch.info
    short = info[0] == 2
    tns = ch.tns
    tc = ch.tc
    w = 0
    while w < info[6]
      nf = 0
      if short
        nf = gb(1)
      else
        nf = gb(2)
      tns[w * 16] = nf
      if nf > 0
        res = gb(1)
        f = 0
        while f < nf
          ln = 0
          order = 0
          if short
            ln = gb(4)
            order = gb(3)
          else
            ln = gb(6)
            order = gb(5)
            fail("tns order") if order > 12
          tns[w * 16 + 1 + f * 3] = ln
          tns[w * 16 + 2 + f * 3] = order
          tns[w * 16 + 3 + f * 3] = 0
          if order > 0
            tns[w * 16 + 3 + f * 3] = gb(1)
            comp = gb(1)
            clen = res + 3 - comp
            ti = 2 * comp + res
            i = 0
            while i < order
              tc[(w * 4 + f) * 32 + i] = AAC_TNS_MAP[ti * 16 + gb(clen)]
              i += 1
          f += 1
      w += 1

  # TNS (after M/S and intensity).
  -> spectral_post(ch)
    info = ch.info
    if info[17] == 1
      swb = @swb_l
      swb = @swb_s if info[0] == 2
      mmm = info[16]
      mmm = info[4] if info[4] < mmm
      aac_tns(ch.coef, swb, info[6], info[7], mmm, ch.tns, ch.tc)

  -> filterbank(ch)
    info = ch.info
    lwp = AAC_SINE_L
    lwp = AAC_KBD_L if info[3] == 1
    swp = AAC_SINE_S
    swp = AAC_KBD_S if info[3] == 1
    sw = AAC_SINE_S
    sw = AAC_KBD_S if info[2] == 1
    aac_filterbank(ch.coef, ch.buf, ch.saved, ch.pcm, ch.tmp, info[0], info[1], lwp, sw, swp, AAC_MD, AAC_REV, @re, @im)

  -> decode_cce
    # Coupling channel elements are parsed and discarded.
    ch = @scratch[0]
    ind = gb(1)
    ncc = gb(3)
    nce = 0
    i = 0
    while i <= ncc
      nce += 1
      if gb(1) == 1
        gb(4)
        if gb(1) == 1
          gb(2)
          nce += 1
      else
        gb(4)
      i += 1
    gb(1)
    gb(1)
    gb(2)
    decode_ics(ch, false)
    info = ch.info
    i = 1
    while i < nce
      cgp = 1
      cgp = gb(1) if ind == 0
      if cgp == 1
        aac_huff(@bs, @st, AAC_HT, AAC_HROOT[0]) if i > 0
      else
        g = 0
        while g < info[5]
          sfb = 0
          while sfb < info[4]
            aac_huff(@bs, @st, AAC_HT, AAC_HROOT[0]) if ch.bt[g * info[4] + sfb] != 0
            sfb += 1
          g += 1
      i += 1

  -> sbr_payload(crc, cnt, endpos)
    el = @last_el
    if !@decided
      @decided = true
      @sbr_on = true
      @ps_on = true if @nch == 1 && @cfg_info.ps != 0
    return nil if !@sbr_on
    stereo = el[0] == 1
    c0 = el[1]
    s = c0.sbr
    if s == nil
      s = AacSbr.new(@core_rate * 2)
      c0.sbr = s
    @st[0] = @st[0] + 10 if crc
    s.read_data(@bs, @st, endpos, stereo, self)

  # PS data found inside the SBR extension of a mono element.
  -> ps_found
    return nil if !@ps_on
    @ps = AacPs.new if @ps == nil
    @ps

  -> finish_frame(blocks)
    fail("no audio elements") if @nch == 0
    if !@decided
      @decided = true
      @ps_on = true if @sbr_on && @nch == 1 && @cfg_info.ps != 0
    @setup_done = true
    nch = channels
    fl = 1024
    fl = 2048 if @sbr_on
    out = f32[fl * nch]
    @els.each ->(el)
      c0 = el[1]
      c1 = el[2]
      s0 = el[3]
      s1 = el[4]
      if s0 >= 0
        if @sbr_on
          s = c0.sbr
          if s == nil
            s = AacSbr.new(@core_rate * 2)
            c0.sbr = s
          if el[0] == 1
            s.process(c0.pcm, c1.pcm, 2, nil)
            aac_interleave(out, c0.pcm, 0, fl, nch, s0)
            aac_interleave(out, c1.pcm, 0, fl, nch, s1)
          elsif @ps_on && @nch == 1
            @ps = AacPs.new if @ps == nil
            r = @chans[1].pcm
            s.process(c0.pcm, r, 1, @ps)
            aac_interleave(out, c0.pcm, 0, fl, nch, 0)
            aac_interleave(out, r, 0, fl, nch, 1)
          else
            s.process(c0.pcm, nil, 1, nil)
            aac_interleave(out, c0.pcm, 0, fl, nch, s0)
        else
          aac_interleave(out, c0.pcm, 0, fl, nch, s0)
          if el[0] == 1
            aac_interleave(out, c1.pcm, 0, fl, nch, s1)
          elsif @ps_on && @nch == 1
            aac_interleave(out, c0.pcm, 0, fl, nch, 1)
    blocks.push(out)

-> aac_load_bytes(dst, src, n) (u8[] u8[] i64) i64
  i = 0
  while i < n
    dst[i] = src[i]
    i += 1
  e = n + 16
  e = dst.size if e > dst.size
  while i < e
    dst[i] = 0
    i += 1
  0

-> aac_copy_f32(dst, d, src, n) (f32[] i64 f32[] i64) i64
  i = 0
  while i < n
    dst[d + i] = src[i]
    i += 1
  0

acodec_register("mp4a", ->(cfg) AacDec.new(cfg))

# ---- ADTS elementary streams ----

-> aac_es_parse(bytes)
  b = bytes
  b = aac_as_u8(b)
  n = b.size
  p = 0
  # ID3v2 tags
  while p + 10 <= n && b[p] == 0x49 && b[p + 1] == 0x44 && b[p + 2] == 0x33
    sz = ((b[p + 6] & 127) << 21) | ((b[p + 7] & 127) << 14) | ((b[p + 8] & 127) << 7) | (b[p + 9] & 127)
    sz += 10 if (b[p + 5] & 0x10) != 0
    p += 10 + sz
  samples = []
  cfg = nil
  rate = 0
  nframes = 0
  while p + 7 <= n
    if b[p] != 0xff || (b[p + 1] & 0xf6) != 0xf0
      # resync (also skips trailing ID3v1 / APE tags and garbage)
      p += 1
      next
    prot_absent = b[p + 1] & 1
    prof = (b[p + 2] >> 6) & 3
    sfi = (b[p + 2] >> 2) & 15
    chc = ((b[p + 2] & 1) << 2) | ((b[p + 3] >> 6) & 3)
    flen = ((b[p + 3] & 3) << 11) | (b[p + 4] << 3) | ((b[p + 5] >> 5) & 7)
    nblk = (b[p + 6] & 3) + 1
    if sfi >= 13 || flen < 7 + (1 - prot_absent) * 2 || p + flen > n
      p += 1
      next
    if cfg == nil
      rate = AAC_RATES[sfi]
      cfg = CodecConfig.new("mp4a", aac_make_asc(prof + 1, rate, chc))
      cfg.sample_rate = rate
      cfg.channels = chc
      cfg.channels = 8 if chc == 7
      cfg.timescale = rate
    hl = 7
    if prot_absent == 0 && nblk > 1
      # raw_data_block_position[1..n-1] then the header CRC
      starts = [0]
      i = 1
      while i < nblk
        starts.push((b[p + 7 + (i - 1) * 2] << 8) | b[p + 8 + (i - 1) * 2])
        i += 1
      hl = 7 + (nblk - 1) * 2 + 2
      base = p + hl
      fend = p + flen
      i = 0
      while i < nblk
        s = base + starts[i]
        e = fend - 2
        e = base + starts[i + 1] - 2 if i + 1 < nblk
        if s < e && e <= fend
          pts = (nframes * 1024 ## f64) / (rate ## f64)
          samples.push(MediaSample.new(b.slice(s, e - s), pts, pts, ~1024.0 / (rate ## f64), true))
        nframes += 1
        i += 1
    else
      hl += 2 if prot_absent == 0
      s = p + hl
      e = p + flen
      pts = (nframes * 1024 ## f64) / (rate ## f64)
      dur = ((nblk * 1024) ## f64) / (rate ## f64)
      samples.push(MediaSample.new(b.slice(s, e - s), pts, pts, dur, true))
      nframes += nblk
    p += flen
  aac_fail("aac: no ADTS frames") if cfg == nil
  {cfg: cfg, samples: samples, duration: (nframes * 1024 ## f64) / (rate ## f64)}
