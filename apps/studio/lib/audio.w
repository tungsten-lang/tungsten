# studio/audio — `studio mix`: the soundtrack as a pure function of the resolved audio tracks (TIMELINE.md §3.4).
#
# Port of the episode's tools/mix.py without ffmpeg: MP3s are decoded once by macOS afconvert into
# build/audio/<sha256>.wav (48 kHz float), then every filter of the legacy chains runs here — RBJ biquads (the
# ffmpeg highpass/lowpass/equalizer/treble designs), ffmpeg's deesser and acompressor algorithms, the split-band
# de-esser (a linear-phase FIR by block convolution), noise-IR reverb by FFT convolution, looping with crossfades,
# sample-exact placement, block ducking — then EBU R128 normalisation (BS.1770-4 integrated loudness, linear gain to
# the cut's target) with a 4x-oversampled true-peak limiter, written as 48 kHz / 24-bit PCM exactly as long as the
# picture.
#
# Caches (build/audio/): every narration take's whole chain (EQ, de-ess, compression, gain, split-band de-ess,
# reverb, pan) is stored once as take_<key>.wav under H(take SHA-256, chain parameters, seed, DSP_VERSION), and
# every cue source's filter chain as cue_<key>.wav, both as 32-bit fixed point (Q3.28: 2^-29 resolution, ±8 range).
# A nudge or ripple re-places cached takes and re-runs only the bus stages. The cold path computes a take, stores
# it and places it from the stored file, so cold and cached mixes are bit-identical.

use base

SR48 = 48000
# Bump when the bytes of a processed take or cue chain change (it is part of their cache keys).
DSP_VERSION = "studio-dsp/2"
# The split-band de-esser's FIR: 2 * DEESS_HALF + 1 taps (+-0.68 s), applied by overlap-add with DEESS_FFT-point
# transforms (blocks of DEESS_FFT - 2 * DEESS_HALF samples). Against the legacy whole-take FFT on a 137 s take the
# de-essed signal differs by at most 3.5e-8 (0.3 LSB at 24 bits); half 8192 gives 2.7 LSB, 16384 0.9 LSB.
DEESS_HALF = 32768
DEESS_FFT = 131072
# Reverb overlap-add transform size (blocks of REVERB_FFT - irn + 1 samples); the same plan as the de-esser's.
REVERB_FFT = 131072
# Q3.28 fixed point for cached audio.
Q28 = ~268435456.0

-> db_lin(x)
  Math.exp(x * ~0.11512925464970229)

-> ms_of(seconds)
  (seconds * ~1000.0).round.to_i

# ---------------------------------------------------------------------------------------------- WAV

# [data byte offset, data bytes, channels, rate, bits, is_float] of a RIFF/WAVE file.
-> wav_info(path)
  m = File.mmap(path)
  v = m.as_u8
  n = v.size
  die("not a WAV: " + path) if n < 12 || v[0] != 82 || v[8] != 87
  pos = 12
  ch = 0
  rate = 0
  bits = 0
  fmt = 0
  doff = 0
  dlen = 0
  while pos + 8 <= n
    id = v[pos].chr + v[pos + 1].chr + v[pos + 2].chr + v[pos + 3].chr
    sz = v[pos + 4] + v[pos + 5] * 256 + v[pos + 6] * 65536 + v[pos + 7] * 16777216
    if id == "fmt "
      fmt = v[pos + 8] + v[pos + 9] * 256
      ch = v[pos + 10] + v[pos + 11] * 256
      rate = v[pos + 12] + v[pos + 13] * 256 + v[pos + 14] * 65536 + v[pos + 15] * 16777216
      bits = v[pos + 22] + v[pos + 23] * 256
      if fmt == 65534
        fmt = v[pos + 32] + v[pos + 33] * 256
    elsif id == "data"
      doff = pos + 8
      dlen = sz
      dlen = n - doff if dlen > n - doff || dlen == 0
      pos = n
    pos += 8 + sz + (sz % 2)
  m.close
  [doff, dlen, ch, rate, bits, fmt == 3]

# Decode a float WAV into planar f64 channels (mono files fill both). Returns frames.
-> load_wav_planar(path, left, right)
  info = wav_info(path)
  die("expected 32-bit float WAV: " + path) if !info[5] || info[4] != 32
  ch = info[2]
  frames = info[1] / (4 * ch)
  die("buffer too small for " + path) if frames > left.size
  m = File.mmap(path)
  fv = m.view_at(info[0], -32, frames * ch)
  wav_deinterleave(fv, frames, ch, left, right)
  m.close
  frames

-> wav_deinterleave(fv, frames, ch, left, right) (f32[] i64 i64 f64[] f64[]) i64
  i = 0
  while i < frames
    if ch == 1
      v = fv[i] ## f64
      left[i] = v
      right[i] = v
    else
      left[i] = fv[i * ch] ## f64
      right[i] = fv[i * ch + 1] ## f64
    i += 1
  frames

# Interleaved stereo f32 view of a float WAV (for the sync check): [view, frames, mmap].
-> read_wav_f32(path)
  info = wav_info(path)
  m = File.mmap(path)
  frames = info[1] / (info[4] / 8 * info[2])
  if info[5] && info[4] == 32
    return [m.view_at(info[0], -32, frames * info[2]), frames, m]
  # 24-bit PCM: convert
  out = f32[frames * 2]
  wav_s24_to_f32(m.as_u8, info[0], frames, info[2], out)
  m.close
  [out, frames, nil]

-> wav_s24_to_f32(u, off, frames, ch, out) (u8[] i64 i64 i64 f32[]) i64
  i = 0
  while i < frames
    c = 0
    while c < 2
      cc = c
      cc = 0 if ch == 1
      p = off + (i * ch + cc) * 3
      v = u[p] + u[p + 1] * 256 + u[p + 2] * 65536
      v = v - 16777216 if v >= 8388608
      out[i * 2 + c] = ((v ## f64) / ~8388608.0) ## f32
      c += 1
    i += 1
  0

-> le32(n)
  [n % 256, (n / 256) % 256, (n / 65536) % 256, (n / 16777216) % 256]

# 48 kHz / 24-bit stereo PCM WAV from an interleaved f32 bus (clipped, rounded), written in 1 MiB blocks.
-> write_wav_s24(path, bus, frames, rate)
  data = frames * 6
  hdr = u8[44]
  bytes = [82, 73, 70, 70] + le32(36 + data) + [87, 65, 86, 69, 102, 109, 116, 32] + le32(16) + [1, 0, 2, 0] + le32(rate) + le32(rate * 6) + [6, 0, 24, 0, 100, 97, 116, 97] + le32(data)
  i = 0
  while i < 44
    hdr[i] = bytes[i]
    i += 1
  tmp = path + ".part"
  fh = FileHandle.new(tmp, "wb")
  fh.write(hdr)
  blk = 174762
  buf = u8[blk * 6]
  f = 0
  while f < frames
    n = [blk, frames - f].min
    if n < blk
      buf = u8[n * 6]
    pack_s24(bus, f, n, buf)
    fh.write(buf)
    f += n
  fh.close
  File.rename(tmp, path)
  path

-> pack_s24(bus, f0, n, buf) (f32[] i64 i64 u8[]) i64
  i = 0
  while i < n * 2
    v = (bus[f0 * 2 + i] ## f64) * ~8388607.0
    v = ~8388607.0 if v > ~8388607.0
    v = (~0.0 - ~8388608.0) if v < (~0.0 - ~8388608.0)
    q = Math.floor(v + ~0.5) ## i64
    q = q + 16777216 if q < 0
    buf[i * 3] = q & 255
    buf[i * 3 + 1] = (q >> 8) & 255
    buf[i * 3 + 2] = (q >> 16) & 255
    i += 1
  0

# Encoder delay and padding from an MP3's Xing/Info frame and LAME tag: [delay, padding] samples, or nil.
-> mp3_gapless(path)
  m = File.mmap(path)
  v = m.as_u8
  n = v.size
  start = 0
  if n > 10 && v[0] == 73 && v[1] == 68 && v[2] == 51
    start = 10 + ((v[6] & 127) * 2097152 + (v[7] & 127) * 16384 + (v[8] & 127) * 128 + (v[9] & 127))
  res = nil
  i = start
  lim = [start + 4096, n - 160].min
  while i < lim && res == nil
    if (v[i] == 73 && v[i + 1] == 110 && v[i + 2] == 102 && v[i + 3] == 111) || (v[i] == 88 && v[i + 1] == 105 && v[i + 2] == 110 && v[i + 3] == 103)
      flags = v[i + 7]
      o = i + 8
      o += 4 if flags & 1 != 0
      o += 4 if flags & 2 != 0
      o += 100 if flags & 4 != 0
      o += 4 if flags & 8 != 0
      d = v[o + 21] * 16 + v[o + 22] / 16
      pd = (v[o + 22] & 15) * 256 + v[o + 23]
      res = [d, pd]
    i += 1
  m.close
  res

# Cut `head` frames off the start and `tail` off the end of a float WAV (byte copy of the data, native rate).
-> wav_trim(src, dst, head, tail)
  info = wav_info(src)
  ch = info[2]
  fb = 4 * ch
  frames = info[1] / fb
  keep = frames - head - tail
  die("cannot trim " + src) if keep <= 0
  data = keep * fb
  hdr = u8[44]
  bytes = [82, 73, 70, 70] + le32(36 + data) + [87, 65, 86, 69, 102, 109, 116, 32] + le32(16) + [3, 0, ch, 0] + le32(info[3]) + le32(info[3] * fb) + [fb, 0, 32, 0, 100, 97, 116, 97] + le32(data)
  i = 0
  while i < 44
    hdr[i] = bytes[i]
    i += 1
  m = File.mmap(src)
  u = m.as_u8
  fh = FileHandle.new(dst, "wb")
  fh.write(hdr)
  off = info[0] + head * fb
  rest = data
  blk = 1048576
  buf = u8[blk]
  while rest > 0
    nb = [blk, rest].min
    buf = u8[nb] if nb < blk
    copy_bytes(u, off, buf, nb)
    fh.write(buf)
    off += nb
    rest -= nb
  fh.close
  m.close
  keep

-> copy_bytes(src, off, dst, n) (u8[] i64 u8[] i64) i64
  i = 0
  while i < n
    dst[i] = src[off + i]
    i += 1
  n

# ---------------------------------------------------------------------------------------------- filters

# RBJ cookbook biquads, as ffmpeg's af_biquads designs them (t=q widths). Returns [b0, b1, b2, a1, a2] / a0.
-> biquad_design(kind, f, q, gain, sr)
  w0 = ~6.283185307179586 * f / sr
  cw = Math.cos(w0)
  sw = Math.sin(w0)
  alpha = sw / (~2.0 * q)
  a = Math.exp(gain * ~0.05756462732485115)    # 10^(g/40)
  b0 = ~1.0
  b1 = ~0.0
  b2 = ~0.0
  a0 = ~1.0
  a1 = ~0.0
  a2 = ~0.0
  if kind == "lowpass"
    b0 = (~1.0 - cw) / ~2.0
    b1 = ~1.0 - cw
    b2 = (~1.0 - cw) / ~2.0
    a0 = ~1.0 + alpha
    a1 = (~0.0 - ~2.0) * cw
    a2 = ~1.0 - alpha
  elsif kind == "highpass"
    b0 = (~1.0 + cw) / ~2.0
    b1 = ~0.0 - (~1.0 + cw)
    b2 = (~1.0 + cw) / ~2.0
    a0 = ~1.0 + alpha
    a1 = (~0.0 - ~2.0) * cw
    a2 = ~1.0 - alpha
  elsif kind == "peak"
    b0 = ~1.0 + alpha * a
    b1 = (~0.0 - ~2.0) * cw
    b2 = ~1.0 - alpha * a
    a0 = ~1.0 + alpha / a
    a1 = (~0.0 - ~2.0) * cw
    a2 = ~1.0 - alpha / a
  elsif kind == "highshelf"
    sq = ~2.0 * Math.sqrt(a) * alpha
    b0 = a * ((a + ~1.0) + (a - ~1.0) * cw + sq)
    b1 = (~0.0 - ~2.0) * a * ((a - ~1.0) + (a + ~1.0) * cw)
    b2 = a * ((a + ~1.0) + (a - ~1.0) * cw - sq)
    a0 = (a + ~1.0) - (a - ~1.0) * cw + sq
    a1 = ~2.0 * ((a - ~1.0) - (a + ~1.0) * cw)
    a2 = (a + ~1.0) - (a - ~1.0) * cw - sq
  else
    die("unknown filter " + kind.to_s)
  [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]

-> biquad_run(x, n, b0, b1, b2, a1, a2) (f64[] i64 f64 f64 f64 f64 f64) i64
  x1 = ~0.0
  x2 = ~0.0
  y1 = ~0.0
  y2 = ~0.0
  i = 0
  while i < n
    v = x[i]
    y = b0 * v + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
    x2 = x1
    x1 = v
    y2 = y1
    y1 = y
    x[i] = y
    i += 1
  0

# Four biquads in cascade, sample by sample (cs: b0 b1 b2 a1 a2 per stage): the same arithmetic as four
# biquad_run passes, but the stages' recursions overlap. An unused stage is the identity (1 0 0 0 0), exact.
-> biquad4_run(x, n, cs) (f64[] i64 f64[]) i64
  p0 = cs[0]
  p1 = cs[1]
  p2 = cs[2]
  p3 = cs[3]
  p4 = cs[4]
  q0 = cs[5]
  q1 = cs[6]
  q2 = cs[7]
  q3 = cs[8]
  q4 = cs[9]
  r0 = cs[10]
  r1 = cs[11]
  r2 = cs[12]
  r3 = cs[13]
  r4 = cs[14]
  s0 = cs[15]
  s1 = cs[16]
  s2 = cs[17]
  s3 = cs[18]
  s4 = cs[19]
  ax1 = ~0.0
  ax2 = ~0.0
  ay1 = ~0.0
  ay2 = ~0.0
  bx1 = ~0.0
  bx2 = ~0.0
  by1 = ~0.0
  by2 = ~0.0
  cx1 = ~0.0
  cx2 = ~0.0
  cy1 = ~0.0
  cy2 = ~0.0
  dx1 = ~0.0
  dx2 = ~0.0
  dy1 = ~0.0
  dy2 = ~0.0
  i = 0
  while i < n
    v = x[i]
    y = p0 * v + p1 * ax1 + p2 * ax2 - p3 * ay1 - p4 * ay2
    ax2 = ax1
    ax1 = v
    ay2 = ay1
    ay1 = y
    v = y
    y = q0 * v + q1 * bx1 + q2 * bx2 - q3 * by1 - q4 * by2
    bx2 = bx1
    bx1 = v
    by2 = by1
    by1 = y
    v = y
    y = r0 * v + r1 * cx1 + r2 * cx2 - r3 * cy1 - r4 * cy2
    cx2 = cx1
    cx1 = v
    cy2 = cy1
    cy1 = y
    v = y
    y = s0 * v + s1 * dx1 + s2 * dx2 - s3 * dy1 - s4 * dy2
    dx2 = dx1
    dx1 = v
    dy2 = dy1
    dy1 = y
    x[i] = y
    i += 1
  0

# ffmpeg af_deesser.c (Airwindows DeEss), output mode.
-> deesser_run(x, n, inten, maxi, freq, sr) (f64[] i64 f64 f64 f64 i64) i64
  srf = sr ## f64
  overall = srf / ~44100.0
  overall = ~44100.0 / srf if sr < 44100
  intensity = Math.exp(~5.0 * Math.log(inten)) * (~8192.0 / overall)
  maxdess = ~1.0 / Math.exp((maxi - ~1.0) * ~48.0 / ~20.0 * ~2.302585092994046)
  iir = freq * freq / overall
  s1 = ~0.0
  s2 = ~0.0
  s3 = ~0.0
  ra = ~1.0
  rb = ~1.0
  ia = ~0.0
  ib = ~0.0
  flip = 0
  i = 0
  while i < n
    sample = x[i]
    s3 = s2
    s2 = s1
    s1 = sample
    m1 = (s1 - s2) * ((s1 - s2) / ~1.3)
    m2 = (s2 - s3) * ((s1 - s2) / ~1.3)
    sense = (m1 - m2) * ((m1 - m2) / ~1.3)
    attack = ~7.0 + sense * ~1024.0
    sense = ~1.0 + intensity * intensity * sense
    sense = intensity if sense > intensity
    recovery = ~1.0 + (~0.01 / sense)
    # |sample| spelled out: `.abs` in a typed function is a boxed method call (~55 ns)
    sa = sample
    sa = ~0.0 - sample if sample < ~0.0
    offset = ~1.0 - sa
    if flip != 0
      ia = ia * (~1.0 - offset * iir) + sample * (offset * iir)
      if ra < sense
        ra = (ra * attack + sense) / (attack + ~1.0)
      else
        ra = ~1.0 + (ra - ~1.0) / recovery
      ra = maxdess if ra > maxdess
      sample = ia + (sample - ia) / ra
    else
      ib = ib * (~1.0 - offset * iir) + sample * (offset * iir)
      if rb < sense
        rb = (rb * attack + sense) / (attack + ~1.0)
      else
        rb = ~1.0 + (rb - ~1.0) / recovery
      rb = maxdess if rb > maxdess
      sample = ib + (sample - ib) / rb
    flip = 1 - flip
    x[i] = sample
    i += 1
  0

# ffmpeg af_sidechaincompress.c acompressor: downward, RMS detection, mono link, hermite soft knee.
-> compressor_run(x, n, thr_lin, ratio, attack_ms, release_ms, makeup, knee, sr) (f64[] i64 f64 f64 f64 f64 f64 f64 i64) i64
  srf = sr ## f64
  thres = Math.log(thr_lin)
  lks = thr_lin / Math.sqrt(knee)
  lke = thr_lin * Math.sqrt(knee)
  adj_start = lks * lks
  kstart = Math.log(lks)
  kstop = Math.log(lke)
  ckstop = (kstop - thres) / ratio + thres
  ac = ~1.0 / (attack_ms * srf / ~4000.0)
  ac = ~1.0 if ac > ~1.0
  rc = ~1.0 / (release_ms * srf / ~4000.0)
  rc = ~1.0 if rc > ~1.0
  delta = ~1.0 / ratio
  slope_lin = ~0.0
  i = 0
  while i < n
    a = x[i]
    a = a * a
    if a > slope_lin
      slope_lin = slope_lin + (a - slope_lin) * ac
    else
      slope_lin = slope_lin + (a - slope_lin) * rc
    gain = ~1.0
    if slope_lin > ~0.0 && slope_lin > adj_start
      slope = Math.log(slope_lin) * ~0.5
      g = (slope - thres) / ratio + thres
      if knee > ~1.0 && slope < kstop
        width = kstop - kstart
        t = (slope - kstart) / width
        m0 = width
        m1 = delta * width
        c2 = (~0.0 - ~3.0) * kstart - ~2.0 * m0 + ~3.0 * ckstop - m1
        c3 = ~2.0 * kstart + m0 - ~2.0 * ckstop + m1
        g = c3 * t * t * t + c2 * t * t + m0 * t + kstart
      gain = Math.exp(g - slope)
    x[i] = x[i] * gain * makeup
    i += 1
  0

-> scale_run(x, n, g) (f64[] i64 f64) i64
  i = 0
  while i < n
    x[i] = x[i] * g
    i += 1
  0

-> sumsq(x, n) (f64[] i64) f64
  s = ~0.0
  i = 0
  while i < n
    s = s + x[i] * x[i]
    i += 1
  s

-> peak_abs(x, n) (f64[] i64) f64
  p = ~0.0
  i = 0
  while i < n
    v = x[i]
    v = ~0.0 - v if v < ~0.0
    p = v if v > p
    i += 1
  p

# tools/mix.py fade: squared linear ramps over k samples at each end.
-> fade_run(x, n, kin, kout) (f64[] i64 i64 i64) i64
  if kin > 0
    k = [kin, n].min
    i = 0
    while i < k
      r = (i ## f64) / ((k - 1) ## f64)
      r = ~1.0 if k == 1
      x[i] = x[i] * r * r
      i += 1
  if kout > 0
    k = [kout, n].min
    i = 0
    while i < k
      r = ~1.0 - (i ## f64) / ((k - 1) ## f64)
      r = ~0.0 if k == 1
      x[n - k + i] = x[n - k + i] * r * r
      i += 1
  0

# tools/mix.py loop_to: repeat src (sn samples) to need samples, each seam a k-sample linear crossfade.
-> loop_run(src, sn, dst, need, k) (f64[] i64 f64[] i64 i64) i64
  i = 0
  while i < sn && i < need
    dst[i] = src[i]
    i += 1
  len = sn
  while len < need
    p = len - k
    j = 0
    while j < k && p + j < need
      r = (j ## f64) / ((k - 1) ## f64)
      dst[p + j] = dst[p + j] * (~1.0 - r) + src[j] * r
      j += 1
    j = k
    while j < sn && p + j < need
      dst[p + j] = src[j]
      j += 1
    len = p + sn
  need

# ---------------------------------------------------------------------------------------------- FFT
# Complex FFT of n = 2^k points on split re/im f64 arrays, for fast convolution only. The forward transform is
# decimation in frequency (natural order in, digit-reversed order out) and the inverse its mirror, decimation in
# time (that order in, natural order out, unscaled): spectra are only ever multiplied point by point, so no
# bit-reversal pass is needed. Radix-4 stages from the full span down, one radix-2 stage last when k is odd; the
# twiddles of every stage are precomputed contiguously (6 doubles per butterfly: cos/sin of j, 2j and 3j turns of
# 2 pi / span), so each stage reads them in order. Real signals go two per transform (see fir_ola_pairs).

# Size of the twiddle table of an n-point plan.
-> fft4_table_size(n)
  s = 0
  span = n
  while span >= 8
    s += (span / 4) * 6
    span = span / 4
  s + 6

-> fft4_twiddles(n, tw) (i64 f64[]) i64
  o = 0
  span = n
  while span >= 8
    q = span / 4
    j = 0
    while j < q
      a = ~6.283185307179586 * (j ## f64) / (span ## f64)
      tw[o] = Math.cos(a)
      tw[o + 1] = Math.sin(a)
      tw[o + 2] = Math.cos(a * ~2.0)
      tw[o + 3] = Math.sin(a * ~2.0)
      tw[o + 4] = Math.cos(a * ~3.0)
      tw[o + 5] = Math.sin(a * ~3.0)
      o += 6
      j += 1
    span = span / 4
  o

# One radix-4 DIF stage of span >= 8 over the whole array, twiddles from tw[to]: for each group, the four
# quarter sequences a, b, c, d become z_m = sum_p x_p (-i)^(p m), times w^(m j), in place.
-> fft4_dif(re, im, n, span, tw, to) (f64[] f64[] i64 i64 f64[] i64) i64
  q = span / 4
  s = 0
  while s < n
    j = 0
    t = to
    i0 = s
    while j < q
      i1 = i0 + q
      i2 = i1 + q
      i3 = i2 + q
      ar = re[i0]
      ai = im[i0]
      br = re[i1]
      bi = im[i1]
      cr = re[i2]
      ci = im[i2]
      dr = re[i3]
      di = im[i3]
      t0r = ar + cr
      t0i = ai + ci
      t1r = ar - cr
      t1i = ai - ci
      t2r = br + dr
      t2i = bi + di
      t3r = br - dr
      t3i = bi - di
      re[i0] = t0r + t2r
      im[i0] = t0i + t2i
      z1r = t1r + t3i
      z1i = t1i - t3r
      z2r = t0r - t2r
      z2i = t0i - t2i
      z3r = t1r - t3i
      z3i = t1i + t3r
      w1r = tw[t]
      w1i = tw[t + 1]
      w2r = tw[t + 2]
      w2i = tw[t + 3]
      w3r = tw[t + 4]
      w3i = tw[t + 5]
      re[i1] = z1r * w1r + z1i * w1i
      im[i1] = z1i * w1r - z1r * w1i
      re[i2] = z2r * w2r + z2i * w2i
      im[i2] = z2i * w2r - z2r * w2i
      re[i3] = z3r * w3r + z3i * w3i
      im[i3] = z3i * w3r - z3r * w3i
      t += 6
      i0 += 1
      j += 1
    s += span
  0

# The mirror DIT stage (inverse direction, unscaled).
-> fft4_dit(re, im, n, span, tw, to) (f64[] f64[] i64 i64 f64[] i64) i64
  q = span / 4
  s = 0
  while s < n
    j = 0
    t = to
    i0 = s
    while j < q
      i1 = i0 + q
      i2 = i1 + q
      i3 = i2 + q
      w1r = tw[t]
      w1i = tw[t + 1]
      w2r = tw[t + 2]
      w2i = tw[t + 3]
      w3r = tw[t + 4]
      w3i = tw[t + 5]
      z1r = re[i1]
      z1i = im[i1]
      z2r = re[i2]
      z2i = im[i2]
      z3r = re[i3]
      z3i = im[i3]
      u1r = z1r * w1r - z1i * w1i
      u1i = z1i * w1r + z1r * w1i
      u2r = z2r * w2r - z2i * w2i
      u2i = z2i * w2r + z2r * w2i
      u3r = z3r * w3r - z3i * w3i
      u3i = z3i * w3r + z3r * w3i
      ar = re[i0]
      ai = im[i0]
      p0r = ar + u2r
      p0i = ai + u2i
      p1r = ar - u2r
      p1i = ai - u2i
      p2r = u1r + u3r
      p2i = u1i + u3i
      p3r = u1r - u3r
      p3i = u1i - u3i
      re[i0] = p0r + p2r
      im[i0] = p0i + p2i
      re[i2] = p0r - p2r
      im[i2] = p0i - p2i
      re[i1] = p1r - p3i
      im[i1] = p1i + p3r
      re[i3] = p1r + p3i
      im[i3] = p1i - p3r
      t += 6
      i0 += 1
      j += 1
    s += span
  0

# The last radix-4 stage (span 4, no twiddles); dir 0 forward, 1 inverse.
-> fft4_last4(re, im, n, dir) (f64[] f64[] i64 i64) i64
  s = 0
  while s < n
    ar = re[s]
    ai = im[s]
    br = re[s + 1]
    bi = im[s + 1]
    cr = re[s + 2]
    ci = im[s + 2]
    dr = re[s + 3]
    di = im[s + 3]
    p0r = ar + cr
    p0i = ai + ci
    p1r = ar - cr
    p1i = ai - ci
    p2r = br + dr
    p2i = bi + di
    p3r = br - dr
    p3i = bi - di
    re[s] = p0r + p2r
    im[s] = p0i + p2i
    re[s + 2] = p0r - p2r
    im[s + 2] = p0i - p2i
    if dir == 0
      re[s + 1] = p1r + p3i
      im[s + 1] = p1i - p3r
      re[s + 3] = p1r - p3i
      im[s + 3] = p1i + p3r
    else
      re[s + 1] = p1r - p3i
      im[s + 1] = p1i + p3r
      re[s + 3] = p1r + p3i
      im[s + 3] = p1i - p3r
    s += 4
  0

# Radix-2 butterflies on adjacent pairs (the extra stage when log2 n is odd; its own inverse up to a factor 2).
-> fft4_last2(re, im, n) (f64[] f64[] i64) i64
  s = 0
  while s < n
    ar = re[s]
    ai = im[s]
    br = re[s + 1]
    bi = im[s + 1]
    re[s] = ar + br
    im[s] = ai + bi
    re[s + 1] = ar - br
    im[s + 1] = ai - bi
    s += 2
  0

-> fft4_forward(re, im, n, tw) (f64[] f64[] i64 f64[]) i64
  span = n
  to = 0
  while span >= 8
    fft4_dif(re, im, n, span, tw, to)
    to += (span / 4) * 6
    span = span / 4
  if span == 4
    fft4_last4(re, im, n, 0)
  elsif span == 2
    fft4_last2(re, im, n)
  0

# Inverse of fft4_forward times n.
-> fft4_inverse(re, im, n, tw) (f64[] f64[] i64 f64[]) i64
  span = n
  to = 0
  while span >= 8
    to += (span / 4) * 6
    span = span / 4
  if span == 4
    fft4_last4(re, im, n, 1)
  elsif span == 2
    fft4_last2(re, im, n)
  span = span * 4
  while span <= n
    to -= (span / 4) * 6
    fft4_dit(re, im, n, span, tw, to)
    span = span * 4
  0

-> zero_run(x, a, b) (f64[] i64 i64) i64
  i = a
  while i < b
    x[i] = ~0.0
    i += 1
  0

-> copy_run(src, dst, n) (f64[] f64[] i64) i64
  i = 0
  while i < n
    dst[i] = src[i]
    i += 1
  0

# Two real blocks into one complex transform input: zr = x[sa, sa + la), zi = x[sb, sb + lb), zero-padded to nfft.
-> pack_pair(x, sa, la, sb, lb, zr, zi, nfft) (f64[] i64 i64 i64 i64 f64[] f64[] i64) i64
  i = 0
  while i < la
    zr[i] = x[sa + i]
    i += 1
  while i < nfft
    zr[i] = ~0.0
    i += 1
  i = 0
  while i < lb
    zi[i] = x[sb + i]
    i += 1
  while i < nfft
    zi[i] = ~0.0
    i += 1
  0

# out[p0 + j] += y[j] for j in [0, m), clipped to [0, n).
-> add_run(out, n, y, p0, m) (f64[] i64 f64[] i64 i64) i64
  j = 0
  j = 0 - p0 if p0 < 0
  e = m
  e = n - p0 if p0 + m > n
  while j < e
    out[p0 + j] = out[p0 + j] + y[j]
    j += 1
  0

# The split-band de-esser's high band filter: tools/mix.py weighted the whole take's spectrum by
# w(f) = clip((f - (cross - 400)) / 800, 0, 1), a zero-phase high-pass with a linear ramp from cross - 400 to
# cross + 400 Hz. Its impulse response is delta - h_lp with the trapezoid low-pass
#   h_lp(t) = sin(pi (f1 + f2) t) / (pi t) * sin(pi (f2 - f1) t) / (pi (f2 - f1) t),   h_lp(0) = f1 + f2
# (f in cycles per sample; band-limited, so the sampled sequence has exactly that spectrum). Truncated to
# |t| <= half, delayed by half (causal), zero-padded to nfft, transformed and scaled by 1 / nfft into hr/hi.
-> deess_fir_spectrum(cross, sr, half, nfft, tw, hr, hi) (f64 i64 i64 i64 f64[] f64[] f64[]) i64
  f1 = (cross - ~400.0) / (sr ## f64)
  f2 = (cross + ~400.0) / (sr ## f64)
  pi = ~3.141592653589793
  zero_run(hr, 0, nfft)
  zero_run(hi, 0, nfft)
  t = 0 - half
  while t <= half
    v = f1 + f2
    if t != 0
      tf = t ## f64
      v = Math.sin(pi * (f1 + f2) * tf) / (pi * tf) * (Math.sin(pi * (f2 - f1) * tf) / (pi * (f2 - f1) * tf))
    h = ~0.0 - v
    h = ~1.0 - v if t == 0
    hr[t + half] = h
    t += 1
  fft4_forward(hr, hi, nfft, tw)
  s = ~1.0 / (nfft ## f64)
  i = 0
  while i < nfft
    hr[i] = hr[i] * s
    hi[i] = hi[i] * s
    i += 1
  0

# out = x (*) h for a real FIR h of 2 half + 1 taps centred on tap half (spectrum hr/hi from deess_fir_spectrum),
# by overlap-add: blocks of nfft - 2 half samples, two per transform (x_a + i x_b: h is real, so the real part of
# the product's inverse is x_a (*) h and the imaginary part x_b (*) h), one forward and one inverse per pair.
-> fir_ola_pairs(x, n, hr, hi, nfft, half, tw, zr, zi, out) (f64[] i64 f64[] f64[] i64 i64 f64[] f64[] f64[] f64[]) i64
  blk = nfft - 2 * half
  zero_run(out, 0, n)
  st = 0
  while st < n
    la = blk
    la = n - st if st + la > n
    sb = st + blk
    lb = 0
    if sb < n
      lb = blk
      lb = n - sb if sb + lb > n
    pack_pair(x, st, la, sb, lb, zr, zi, nfft)
    fft4_forward(zr, zi, nfft, tw)
    cmul_run(zr, zi, hr, hi, nfft)
    fft4_inverse(zr, zi, nfft, tw)
    add_run(out, n, zr, st - half, la + 2 * half)
    add_run(out, n, zi, sb - half, lb + 2 * half) if lb > 0
    st += 2 * blk
  0

# tools/mix.py deess_dynamic: the high band (above) and the body, block RMS (32 samples) with attack/release, and
# the high band clamped against the body.
-> deess_apply(x, hi, n, sr, max_ratio, abs_lim, env_a, env_b) (f64[] f64[] i64 i64 f64 f64 f64[] f64[]) i64
  step = 32
  m = n / step
  srb = (sr ## f64) / (step ## f64)
  hau = Math.exp((~0.0 - ~1.0) / [~1.0, ~0.0015 * srb].max)
  had = Math.exp((~0.0 - ~1.0) / [~1.0, ~0.035 * srb].max)
  lau = Math.exp((~0.0 - ~1.0) / [~1.0, ~0.005 * srb].max)
  lad = Math.exp((~0.0 - ~1.0) / [~1.0, ~0.060 * srb].max)
  ha = ~0.0
  la = ~0.0
  floor44 = Math.exp((~0.0 - ~44.0) * ~0.11512925464970229)
  floor18 = Math.exp((~0.0 - ~18.0) * ~0.11512925464970229)
  b = 0
  while b < m
    hs = ~0.0
    ls = ~0.0
    i = b * step
    while i < (b + 1) * step
      h = hi[i]
      l = x[i] - h
      hs = hs + h * h
      ls = ls + l * l
      i += 1
    hv = Math.sqrt(hs / (step ## f64) + ~1.0e-12)
    lv = Math.sqrt(ls / (step ## f64) + ~1.0e-12)
    if hv > ha
      ha = hau * ha + (~1.0 - hau) * hv
    else
      ha = had * ha + (~1.0 - had) * hv
    if lv > la
      la = lau * la + (~1.0 - lau) * lv
    else
      la = lad * la + (~1.0 - lad) * lv
    allowed = [abs_lim, [la * max_ratio, floor44].max].min
    g = ~1.0
    g = allowed / (ha + ~1.0e-12) if ha > allowed
    g = floor18 if g < floor18
    g = ~1.0 if g > ~1.0
    env_a[b] = g
    b += 1
  last = ~1.0
  last = env_a[m - 1] if m > 0
  i = 0
  while i < n
    bi = i / step
    g = last
    g = env_a[bi] if bi < m
    l = x[i] - hi[i]
    x[i] = l + hi[i] * g
    i += 1
  0

# Noise IR (tools/mix.py ir()): exponential decay over `seconds`, one-pole lowpass at damp twice, unit energy.
-> make_ir(key, n, seconds, damp, sr, out) (i64 i64 f64 f64 i64 f64[]) i64
  srf = sr ## f64
  a = Math.exp((~0.0 - ~6.283185307179586) * damp / srf)
  i = 0
  while i < n
    t = (i ## f64) / srf
    out[i] = rng_n(key, i) * Math.exp((~0.0 - ~6.9) * t / seconds)
    i += 1
  p = 0
  while p < 2
    acc = ~0.0
    i = 0
    while i < n
      acc = (~1.0 - a) * out[i] + a * acc
      out[i] = acc
      i += 1
    p += 1
  e = Math.sqrt(sumsq(out, n))
  scale_run(out, n, ~1.0 / e)
  0

# complex multiply re/im by the spectrum hr/hi
-> cmul_run(re, im, hr, hi, n) (f64[] f64[] f64[] f64[] i64) i64
  i = 0
  while i < n
    r = re[i] * hr[i] - im[i] * hi[i]
    q = re[i] * hi[i] + im[i] * hr[i]
    re[i] = r
    im[i] = q
    i += 1
  0

# (ar, ai) = (re, im) * (h1r, h1i); (re, im) *= (h0r, h0i): one spectrum times two kernels.
-> cmul2_run(re, im, h0r, h0i, h1r, h1i, ar, ai, n) (f64[] f64[] f64[] f64[] f64[] f64[] f64[] f64[] i64) i64
  i = 0
  while i < n
    xr = re[i]
    xi = im[i]
    ar[i] = xr * h1r[i] - xi * h1i[i]
    ai[i] = xr * h1i[i] + xi * h1r[i]
    re[i] = xr * h0r[i] - xi * h0i[i]
    im[i] = xr * h0i[i] + xi * h0r[i]
    i += 1
  0

# Reverb by overlap-add (tools/mix.py: dry * (1 - wet / 2) + wet * x (*) ir_c, times pan_c): blocks of
# nfft - irn + 1 samples, two blocks per forward transform (the IRs are real, so the real and imaginary parts of
# each inverse are the two blocks' outputs) and one inverse per channel. h0/h1 are the channels' IR spectra,
# scaled by 1 / nfft. outl/outr get total = n + irn - 1 samples.
-> reverb_ola_pairs(x, n, h0r, h0i, h1r, h1i, irn, nfft, tw, zr, zi, ar, ai, outl, outr, total, wet, pl, pr) (f64[] i64 f64[] f64[] f64[] f64[] i64 i64 f64[] f64[] f64[] f64[] f64[] f64[] f64[] i64 f64 f64 f64) i64
  zero_run(outl, 0, total)
  zero_run(outr, 0, total)
  blk = nfft - irn + 1
  st = 0
  while st < n
    la = blk
    la = n - st if st + la > n
    sb = st + blk
    lb = 0
    if sb < n
      lb = blk
      lb = n - sb if sb + lb > n
    pack_pair(x, st, la, sb, lb, zr, zi, nfft)
    fft4_forward(zr, zi, nfft, tw)
    cmul2_run(zr, zi, h0r, h0i, h1r, h1i, ar, ai, nfft)
    fft4_inverse(zr, zi, nfft, tw)
    fft4_inverse(ar, ai, nfft, tw)
    add_run(outl, total, zr, st, la + irn - 1)
    add_run(outr, total, ar, st, la + irn - 1)
    if lb > 0
      add_run(outl, total, zi, sb, lb + irn - 1)
      add_run(outr, total, ai, sb, lb + irn - 1)
    st += 2 * blk
  dry = ~1.0 - wet * ~0.5
  i = 0
  while i < total
    d = ~0.0
    d = x[i] if i < n
    outl[i] = (d * dry + outl[i] * wet) * pl
    outr[i] = (d * dry + outr[i] * wet) * pr
    i += 1
  0

# ---------------------------------------------------------------------------------------------- bus

# Add (left, right) * gain into the interleaved bus at sample s0 (clipped to the bus), with an optional duck:
# the gain is multiplied by db(depth * duck[sample / 64]) when depth != 0 (computed once per 64-sample block).
-> place_run(bus, nbus, left, right, n, s0, gain, duck, nduck, depth) (f32[] i64 f64[] f64[] i64 i64 f64 f64[] i64 f64) i64
  i = 0
  if s0 < 0
    i = 0 - s0
  cb = -1
  g = gain
  while i < n && s0 + i < nbus
    p = s0 + i
    if depth != ~0.0
      b = p / 64
      if b != cb
        cb = b
        d = ~0.0
        d = duck[b] if b < nduck
        g = gain * Math.exp(depth * d * ~0.11512925464970229)
    bus[p * 2] = ((bus[p * 2] ## f64) + left[i] * g) ## f32
    bus[p * 2 + 1] = ((bus[p * 2 + 1] ## f64) + right[i] * g) ## f32
    i += 1
  0

# Add n stereo frames of Q3.28 audio (interleaved i32, a cached take) into the bus at sample s0.
-> place_q28(bus, nbus, src, n, s0) (f32[] i64 i32[] i64 i64) i64
  sc = ~1.0 / ~268435456.0
  i = 0
  if s0 < 0
    i = 0 - s0
  while i < n && s0 + i < nbus
    p = s0 + i
    a = src[i * 2]
    b = src[i * 2 + 1]
    bus[p * 2] = ((bus[p * 2] ## f64) + (a ## f64) * sc) ## f32
    bus[p * 2 + 1] = ((bus[p * 2 + 1] ## f64) + (b ## f64) * sc) ## f32
    i += 1
  0

# Q3.28 interleaved stereo -> planar f64 (exact).
-> q28_planar(src, n, left, right) (i32[] i64 f64[] f64[]) i64
  sc = ~1.0 / ~268435456.0
  i = 0
  while i < n
    a = src[i * 2]
    b = src[i * 2 + 1]
    left[i] = (a ## f64) * sc
    right[i] = (b ## f64) * sc
    i += 1
  0

# Planar f64 frames [f0, f0 + n) -> interleaved little-endian Q3.28 bytes (rounded, saturated); returns the
# number of saturated samples.
-> pack_q28(left, right, f0, n, buf) (f64[] f64[] i64 i64 u8[]) i64
  sat = 0
  i = 0
  while i < n * 2
    v = left[f0 + i / 2]
    v = right[f0 + i / 2] if i % 2 == 1
    v = v * ~268435456.0
    if v > ~2147483647.0
      v = ~2147483647.0
      sat += 1
    if v < (~0.0 - ~2147483648.0)
      v = ~0.0 - ~2147483648.0
      sat += 1
    q = Math.floor(v + ~0.5) ## i64
    q = 2147483647 if q > 2147483647
    q = q + 4294967296 if q < 0
    buf[i * 4] = q & 255
    buf[i * 4 + 1] = (q >> 8) & 255
    buf[i * 4 + 2] = (q >> 16) & 255
    buf[i * 4 + 3] = (q >> 24) & 255
    i += 1
  sat

# A stereo 32-bit PCM WAV of Q3.28 samples from planar f64 (the take and cue caches), written atomically.
-> write_wav_q28(path, left, right, frames, rate)
  data = frames * 8
  hdr = u8[44]
  bytes = [82, 73, 70, 70] + le32(36 + data) + [87, 65, 86, 69, 102, 109, 116, 32] + le32(16) + [1, 0, 2, 0] + le32(rate) + le32(rate * 8) + [8, 0, 32, 0, 100, 97, 116, 97] + le32(data)
  i = 0
  while i < 44
    hdr[i] = bytes[i]
    i += 1
  tmp = path + ".part"
  fh = FileHandle.new(tmp, "wb")
  fh.write(hdr)
  blk = 131072
  buf = u8[blk * 8]
  sat = 0
  f = 0
  while f < frames
    n = [blk, frames - f].min
    if n < blk
      buf = u8[n * 8]
    sat += pack_q28(left, right, f, n, buf)
    fh.write(buf)
    f += n
  fh.close
  File.rename(tmp, path)
  << "mix: warning: " + sat.to_s + " samples saturated in " + path if sat > 0
  path

# [i32 view of the interleaved samples, frames, mmap] of a Q3.28 WAV (keep the mmap open while using the view).
-> read_wav_q28(path)
  info = wav_info(path)
  die("expected a 32-bit stereo PCM cache: " + path) if info[5] || info[4] != 32 || info[2] != 2
  m = File.mmap(path)
  frames = info[1] / 8
  [m.view_at(info[0], 33, frames * 2), frames, m]

# tools/mix.py ducking: block max of mean |vo| over 64 samples, attack/release follower, duck = clip(env / full).
-> duck_env(bus, nbus, out, nb, attack, release, full, sr) (f32[] i64 f64[] i64 f64 f64 f64 i64) i64
  au = Math.exp((~0.0 - ~1.0) / (attack * (sr ## f64) / ~64.0))
  ad = Math.exp((~0.0 - ~1.0) / (release * (sr ## f64) / ~64.0))
  acc = ~0.0
  b = 0
  while b < nb
    mx = ~0.0
    i = b * 64
    e = i + 64
    e = nbus if e > nbus
    while i < e
      a = bus[i * 2] ## f64
      a = ~0.0 - a if a < ~0.0
      c = bus[i * 2 + 1] ## f64
      c = ~0.0 - c if c < ~0.0
      v = (a + c) * ~0.5
      mx = v if v > mx
      i += 1
    if mx > acc
      acc = au * acc + (~1.0 - au) * mx
    else
      acc = ad * acc + (~1.0 - ad) * mx
    d = acc / full
    d = ~1.0 if d > ~1.0
    out[b] = d
    b += 1
  0

-> bus_peak(bus, n) (f32[] i64) f64
  p = ~0.0
  i = 0
  while i < n
    v = bus[i] ## f64
    v = ~0.0 - v if v < ~0.0
    p = v if v > p
    i += 1
  p

-> bus_scale(bus, n, g) (f32[] i64 f64) i64
  i = 0
  while i < n
    bus[i] = ((bus[i] ## f64) * g) ## f32
    i += 1
  0

# ---------------------------------------------------------------------------------------------- loudness

# BS.1770-4 K-weighted mean square per 100 ms sub-block (both channels summed), into zs. The two channels' filter
# recursions run interleaved (independent dependency chains), each summed per sub-block, then added.
-> k_weight_blocks(bus, n, zs, sub) (f32[] i64 f64[] i64) i64
  # 48 kHz coefficients from the recommendation (stage 1 shelf, stage 2 high-pass)
  sb0 = ~1.53512485958697
  sb1 = (~0.0 - ~2.69169618940638)
  sb2 = ~1.19839281085285
  sa1 = (~0.0 - ~1.69065929318241)
  sa2 = ~0.73248077421585
  hb0 = ~1.0
  hb1 = (~0.0 - ~2.0)
  hb2 = ~1.0
  ha1 = (~0.0 - ~1.99004745483398)
  ha2 = ~0.99007225036621
  nb = n / sub
  ax1 = ~0.0
  ax2 = ~0.0
  ay1 = ~0.0
  ay2 = ~0.0
  au1 = ~0.0
  au2 = ~0.0
  av1 = ~0.0
  av2 = ~0.0
  bx1 = ~0.0
  bx2 = ~0.0
  by1 = ~0.0
  by2 = ~0.0
  bu1 = ~0.0
  bu2 = ~0.0
  bv1 = ~0.0
  bv2 = ~0.0
  b = 0
  while b < nb
    s0 = ~0.0
    s1 = ~0.0
    i = b * sub
    e = i + sub
    while i < e
      xa = bus[i * 2] ## f64
      xb = bus[i * 2 + 1] ## f64
      ya = sb0 * xa + sb1 * ax1 + sb2 * ax2 - sa1 * ay1 - sa2 * ay2
      yb = sb0 * xb + sb1 * bx1 + sb2 * bx2 - sa1 * by1 - sa2 * by2
      ax2 = ax1
      ax1 = xa
      ay2 = ay1
      ay1 = ya
      bx2 = bx1
      bx1 = xb
      by2 = by1
      by1 = yb
      va = hb0 * ya + hb1 * au1 + hb2 * au2 - ha1 * av1 - ha2 * av2
      vb = hb0 * yb + hb1 * bu1 + hb2 * bu2 - ha1 * bv1 - ha2 * bv2
      au2 = au1
      au1 = ya
      av2 = av1
      av1 = va
      bu2 = bu1
      bu1 = yb
      bv2 = bv1
      bv1 = vb
      s0 = s0 + va * va
      s1 = s1 + vb * vb
      i += 1
    zs[b] = (s0 + s1) / (sub ## f64)
    b += 1
  nb

# Integrated loudness (LUFS) from 100 ms sub-blocks: 400 ms blocks, 75% overlap, gates -70 LUFS and -10 LU.
-> integrated_lufs(zs, nb) (f64[] i64) f64
  sum = ~0.0
  cnt = 0
  b = 0
  while b + 3 < nb
    z = (zs[b] + zs[b + 1] + zs[b + 2] + zs[b + 3]) * ~0.25
    l = (~0.0 - ~0.691) + ~10.0 * Math.log(z + ~1.0e-20) * ~0.4342944819032518
    if l > (~0.0 - ~70.0)
      sum = sum + z
      cnt += 1
    b += 1
  return (~0.0 - ~200.0) if cnt == 0
  rel = (~0.0 - ~0.691) + ~10.0 * Math.log(sum / (cnt ## f64)) * ~0.4342944819032518 - ~10.0
  sum = ~0.0
  cnt = 0
  b = 0
  while b + 3 < nb
    z = (zs[b] + zs[b + 1] + zs[b + 2] + zs[b + 3]) * ~0.25
    l = (~0.0 - ~0.691) + ~10.0 * Math.log(z + ~1.0e-20) * ~0.4342944819032518
    if l > (~0.0 - ~70.0) && l > rel
      sum = sum + z
      cnt += 1
    b += 1
  (~0.0 - ~0.691) + ~10.0 * Math.log(sum / (cnt ## f64)) * ~0.4342944819032518

# 4x polyphase windowed-sinc interpolator taps (12 per phase) for true peak (BS.1770-4 Annex 2 method).
-> tp_taps(h) (f64[]) i64
  p = 0
  while p < 4
    s = ~0.0
    k = 0
    while k < 12
      x = ((k - 5) ## f64) - (p ## f64) / ~4.0
      v = ~1.0
      if x != ~0.0
        v = Math.sin(~3.141592653589793 * x) / (~3.141592653589793 * x)
      wv = ~0.5 + ~0.5 * Math.cos(~3.141592653589793 * x / ~7.0)
      h[p * 12 + k] = v * wv
      s = s + v * wv
      k += 1
    k = 0
    while k < 12
      h[p * 12 + k] = h[p * 12 + k] / s
      k += 1
    p += 1
  0

# The bound on a 4x-interpolated value from the largest |sample| in its 12-tap window: the largest sum of |taps|
# over the phases, inflated past any rounding of the 12-term sums.
-> tp_bound(h) (f64[]) f64
  best = ~0.0
  p = 0
  while p < 4
    s = ~0.0
    k = 0
    while k < 12
      v = h[p * 12 + k]
      v = ~0.0 - v if v < ~0.0
      s = s + v
      k += 1
    best = s if s > best
    p += 1
  best * (~1.0 + ~1.0e-9)

# Max |sample| of channel c over each of nsub 16-sample sub-blocks starting at base (clipped to [0, n)), into
# sm[off ...].
-> sub_max(bus, n, c, base, nsub, sm, off) (f32[] i64 i64 i64 i64 f64[] i64) i64
  j = 0
  while j < nsub
    a = base + j * 16
    e = a + 16
    a = 0 if a < 0
    e = n if e > n
    m = ~0.0
    i = a
    while i < e
      v = bus[i * 2 + c] ## f64
      v = ~0.0 - v if v < ~0.0
      m = v if v > m
      i += 1
    sm[off + j] = m
    j += 1
  0

# One channel's 4x-oversampled peak at sample i (6 <= i < n - 6): the sample and the four interpolation phases.
-> tp_at(bus, i, c, h) (f32[] i64 i64 f64[]) f64
  tp = bus[i * 2 + c] ## f64
  tp = ~0.0 - tp if tp < ~0.0
  p = 0
  while p < 4
    acc = ~0.0
    k = 0
    while k < 12
      acc = acc + (bus[(i + k - 5) * 2 + c] ## f64) * h[p * 12 + k]
      k += 1
    acc = ~0.0 - acc if acc < ~0.0
    tp = acc if acc > tp
    p += 1
  tp

# Per sample, the gain that keeps the 4x-oversampled peak of both channels at or under ceil (1 where it already
# is), into g (n entries); returns the largest peak seen. Only 256-sample blocks whose sample peak nearby could
# exceed ceil after interpolation are evaluated, and inside them only samples whose 12-tap window can reach
# min(ceil, the running maximum) (tp_bound): a skipped sample would have gain 1 and could not raise the maximum,
# so the gains and the maximum equal those of evaluating every sample of those blocks.
-> tp_gain(bus, n, h, ceil, g) (f32[] i64 f64[] f64 f32[]) f64
  bound = tp_bound(h)
  maxtp = ~0.0
  safe = ceil / ~1.7
  nb = n / 256 + 1
  bm = f64[nb]
  sm = f64[36]
  i = 0
  while i < n
    v = bus[i * 2] ## f64
    v = ~0.0 - v if v < ~0.0
    w = bus[i * 2 + 1] ## f64
    w = ~0.0 - w if w < ~0.0
    v = w if w > v
    b = i / 256
    bm[b] = v if v > bm[b]
    i += 1
  b = 0
  while b < nb
    lo = b * 256
    hi = lo + 256
    hi = n if hi > n
    near = bm[b]
    near = bm[b - 1] if b > 0 && bm[b - 1] > near
    near = bm[b + 1] if b + 1 < nb && bm[b + 1] > near
    if near <= safe
      i = lo
      while i < hi
        g[i] = ~1.0 ## f32
        i += 1
    else
      base = lo - 16
      sub_max(bus, n, 0, base, 18, sm, 0)
      sub_max(bus, n, 1, base, 18, sm, 18)
      i = lo
      while i < hi
        gi = ~1.0
        c = 0
        while c < 2
          tp = bus[i * 2 + c] ## f64
          tp = ~0.0 - tp if tp < ~0.0
          if i >= 6 && i + 6 < n
            wm = sm[c * 18 + (i - 5 - base) / 16]
            w2 = sm[c * 18 + (i + 6 - base) / 16]
            wm = w2 if w2 > wm
            lim = ceil
            lim = maxtp if maxtp < lim
            tp = tp_at(bus, i, c, h) if wm * bound > lim
          maxtp = tp if tp > maxtp
          q = ~1.0
          q = ceil / tp if tp > ceil
          gi = q if q < gi
          c += 1
        g[i] = gi ## f32
        i += 1
    b += 1
  maxtp

# Look-ahead limiter: gain = running min over the next 2w samples, averaged over w (so it is down by the peak),
# with an exponential release; applied in place.
-> limit_apply(bus, n, g, w, release_coef) (f32[] i64 f32[] i64 f64) i64
  # forward min over [i, i + 2w] (in place, from the end, with a monotone deque emulated by a block scan)
  m = f32[n]
  i = n - 1
  while i >= 0
    lo = g[i] ## f64
    e = i + 2 * w
    e = n - 1 if e > n - 1
    if lo < ~1.0 || (i + 1 < n && (m[i + 1] ## f64) < ~1.0)
      k = i
      while k <= e
        v = g[k] ## f64
        lo = v if v < lo
        k += 1
    m[i] = lo ## f32
    i -= 1
  acc = ~0.0
  i = 0
  while i < w && i < n
    acc = acc + (m[i] ## f64)
    i += 1
  gcur = ~1.0
  i = 0
  while i < n
    avg = ~1.0
    if i >= w
      acc = acc + (m[i] ## f64) - (m[i - w] ## f64)
      avg = acc / (w ## f64)
    else
      avg = (m[i] ## f64)
    gcur = gcur + (~1.0 - gcur) * release_coef
    gcur = avg if avg < gcur
    bus[i * 2] = ((bus[i * 2] ## f64) * gcur) ## f32
    bus[i * 2 + 1] = ((bus[i * 2 + 1] ## f64) * gcur) ## f32
    i += 1
  0

# ---------------------------------------------------------------------------------------------- the mix

+ Mixer
  -> new(@proj, @r)
    @sr = @r["sr"]
    @mixcfg = @proj.ep["mix"]
    @n = @r["samples"]
    @seed = @r["seed"]
    @dir = @proj.build + "/audio"
    mkdir_p(@dir)
    @cap = 0
    @report = {}
    @tm = f64[8]
    @takes_cached = 0
    @takes_made = 0
    @cues_made = 0
    @tw_d = nil

  # Decode an asset once into build/audio/<sha>.wav (48 kHz float). MP3s are gapless-trimmed first: afconvert
  # ignores the LAME/Info header, so the native-rate decode keeps the encoder delay (576 samples on these files,
  # 13 ms) and the padding; they are cut here from the header's values, then afconvert resamples (bats SRC).
  -> decoded(key)
    sha = @proj.asset_sha[key]
    sha = @proj.ep["assets"][key]["sha256"] if sha == nil
    out = @dir + "/" + sha + ".wav"
    if !File.exist?(out)
      src = @proj.asset_path(key)
      gap = nil
      gap = mp3_gapless(src) if src.downcase.ends_with?(".mp3")
      if gap != nil
        raw = out + ".raw.wav"
        trim = out + ".trim.wav"
        die("afconvert failed on " + src) if !OS.system("afconvert -f WAVE -d LEF32 " + shq(src) + " " + shq(raw))
        wav_trim(raw, trim, gap[0], gap[1])
        die("afconvert failed on " + trim) if !OS.system("afconvert -f WAVE -d LEF32@" + @sr.to_s + " -r 127 --src-complexity bats " + shq(trim) + " " + shq(out + ".part"))
        File.delete(raw)
        File.delete(trim)
      else
        die("afconvert failed on " + src) if !OS.system("afconvert -f WAVE -d LEF32@" + @sr.to_s + " -r 127 --src-complexity bats " + shq(src) + " " + shq(out + ".part"))
      File.rename(out + ".part", out)
    out

  -> asset_sha(key)
    sha = @proj.asset_sha[key]
    sha = @proj.ep["assets"][key]["sha256"] if sha == nil
    sha

  # A narration take's whole chain is cached under this key: the take's content and every parameter its
  # processing reads (the reverb IR is drawn from the seed).
  -> take_key(it)
    v = @mixcfg["voices"][it["spk"]]
    vo = @mixcfg["vo"]
    hash_of({"dsp" => DSP_VERSION, "kind" => "take", "sr" => @sr, "seed" => @seed, "take" => asset_sha(it["src"]),
             "chain" => v["chain"], "gain_db" => v["gain_db"], "pan" => v["pan"], "reverb" => v["reverb"],
             "rms_db" => vo["rms_db"], "max_gain_db" => vo["max_gain_db"], "deess" => vo["deess"],
             "fir" => [DEESS_HALF, DEESS_FFT, REVERB_FFT]})

  -> take_path(it)
    @dir + "/take_" + take_key(it) + ".wav"

  # Every scratch buffer is allocated once, at the largest size any uncached take or any cue needs (an array that
  # is reassigned is not freed until exit, so growing on demand would keep every old size alive).
  -> prepare
    cap = @sr * 4
    @r["tracks"][2]["items"].each ->(it)
      if !File.exist?(take_path(it))
        fr = frames_of(it["src"])
        cap = [cap, fr + @sr * 2].max
    @r["tracks"][3]["items"].each ->(c)
      fr = frames_of(c["src"])
      need = fr + @sr * 2
      if c["kind"] == "music"
        need = [need, c["s1"] - c["s0"] + (to_f(get(c, "fade_out_ms", 2000)) * @sr / ~1000.0).to_i + @sr + 16].max
      elsif c["kind"] == "amb"
        need = [need, c["s1"] - c["s0"] + (to_f(@mixcfg["amb"]["post_ms"]) * @sr / ~1000.0).to_i + 16].max
      cap = [cap, need].max
    @cap = cap
    @l = f64[cap]
    @rr = f64[cap]
    @tl = f64[cap]
    @tr = f64[cap]
    @env = f64[cap / 32 + 2]
    @ir = f64[@sr * 2]
    @irspec = {}
    @dkspec = {}
    nil

  # The FFT plan and work arrays, made on the first take that is not cached.
  -> ensure_fft
    if @tw_d == nil
      die("DEESS_FFT and REVERB_FFT share one plan") if DEESS_FFT != REVERB_FFT
      @tw_d = f64[fft4_table_size(DEESS_FFT)]
      fft4_twiddles(DEESS_FFT, @tw_d)
      @tw_r = @tw_d
      @zr = f64[REVERB_FFT]
      @zi = f64[REVERB_FFT]
      @ar = f64[REVERB_FFT]
      @ai = f64[REVERB_FFT]
    nil

  -> load(key, cap)
    p = decoded(key)
    info = wav_info(p)
    frames = info[1] / (4 * info[2])
    die("scratch too small for " + key) if frames + @sr > @cap || cap > @cap
    load_wav_planar(p, @l, @rr)

  -> frames_of(key)
    info = wav_info(decoded(key))
    info[1] / (4 * info[2])

  # Run a filter chain in place; consecutive biquads go four at a time through biquad4_run.
  -> chain(spec, x, n)
    cs = f64[20]
    nq = 0
    spec.each ->(f)
      k = f[0]
      if k == "deesser" || k == "compressor"
        flush_biquads(cs, nq, x, n)
        nq = 0
        if k == "deesser"
          deesser_run(x, n, to_f(f[1]), to_f(f[2]), to_f(f[3]), @sr)
        else
          compressor_run(x, n, db_lin(to_f(f[1])), to_f(f[2]), to_f(f[3]), to_f(f[4]), to_f(f[5]), ~2.82843, @sr)
      else
        gain = ~0.0
        gain = to_f(f[3]) if f.size > 3
        c = biquad_design(k, to_f(f[1]), to_f(f[2]), gain, @sr + ~0.0)
        j = 0
        while j < 5
          cs[nq * 5 + j] = c[j]
          j += 1
        nq += 1
        if nq == 4
          flush_biquads(cs, nq, x, n)
          nq = 0
    flush_biquads(cs, nq, x, n)
    nil

  -> flush_biquads(cs, nq, x, n)
    return nil if nq == 0
    q = nq
    while q < 4
      cs[q * 5] = ~1.0
      cs[q * 5 + 1] = ~0.0
      cs[q * 5 + 2] = ~0.0
      cs[q * 5 + 3] = ~0.0
      cs[q * 5 + 4] = ~0.0
      q += 1
    biquad4_run(x, n, cs)
    nil

  -> rms_gain(n, target_db, max_db)
    r = Math.sqrt((sumsq(@l, n) + sumsq(@rr, n)) / (~2.0 * n) + ~1.0e-12)
    [db_lin(target_db) / r, db_lin(max_db)].min

  -> peak_gain(n, target_db, max_db)
    pk = [peak_abs(@l, n), peak_abs(@rr, n)].max + ~1.0e-9
    [db_lin(target_db) / pk, db_lin(max_db)].min

  # The spectrum (at the overlap-add transform size, scaled by 1 / size) of a voice's noise IR for one channel,
  # made once.
  -> ir_spectrum(rev, c)
    key = rev[0].to_s + ":" + rev[2].to_s + ":" + c.to_s
    sp = @irspec[key]
    if sp == nil
      irn = (to_f(rev[0]) * @sr / ~1000.0).to_i
      make_ir(rng_key(@seed, id60("ir:" + rev[0].to_s + ":" + rev[2].to_s), c, P_IR), irn, to_f(rev[0]) / ~1000.0, to_f(rev[2]), @sr, @ir)
      hr = f64[REVERB_FFT]
      hi = f64[REVERB_FFT]
      copy_run(@ir, hr, irn)
      fft4_forward(hr, hi, REVERB_FFT, @tw_r)
      scale_run(hr, REVERB_FFT, ~1.0 / (REVERB_FFT + ~0.0))
      scale_run(hi, REVERB_FFT, ~1.0 / (REVERB_FFT + ~0.0))
      sp = [hr, hi, irn]
      @irspec[key] = sp
    sp

  # The de-esser's high-band FIR spectrum for a crossover, made once.
  -> deess_spectrum(cross)
    key = cross.to_s
    sp = @dkspec[key]
    if sp == nil
      hr = f64[DEESS_FFT]
      hi = f64[DEESS_FFT]
      deess_fir_spectrum(cross, @sr, DEESS_HALF, DEESS_FFT, @tw_d, hr, hi)
      sp = [hr, hi]
      @dkspec[key] = sp
    sp

  # One narration take through its whole chain: EQ/de-ess/compressor chain (mono, as the legacy chain ran on the
  # mono file) -> rms gain -> split-band de-ess (linear-phase FIR) -> reverb and pan (overlap-add), stored as
  # build/audio/take_<key>.wav (Q3.28 stereo) unless it is there already. Returns the path.
  -> take_file(it)
    path = take_path(it)
    if File.exist?(path)
      @takes_cached += 1
      return path
    v = @mixcfg["voices"][it["spk"]]
    vo = @mixcfg["vo"]
    ensure_fft()
    c0 = clock()
    n = load(it["src"], 0)
    chain(v["chain"], @l, n)
    g = rms_gain_mono(n, to_f(vo["rms_db"]), to_f(vo["max_gain_db"])) * db_lin(to_f(v["gain_db"]))
    scale_run(@l, n, g)
    c1 = clock()
    de = vo["deess"]
    dk = deess_spectrum(to_f(de["cross_hz"]))
    fir_ola_pairs(@l, n, dk[0], dk[1], DEESS_FFT, DEESS_HALF, @tw_d, @zr, @zi, @tl)
    deess_apply(@l, @tl, n, @sr, to_f(de["max_ratio"]), db_lin(to_f(de["abs_db"])), @env, @env)
    c2 = clock()
    rev = v["reverb"]
    s0 = ir_spectrum(rev, 0)
    s1 = ir_spectrum(rev, 1)
    irn = s0[2]
    total = n + irn - 1
    reverb_ola_pairs(@l, n, s0[0], s0[1], s1[0], s1[1], irn, REVERB_FFT, @tw_r, @zr, @zi, @ar, @ai, @tl, @tr, total, to_f(rev[1]), to_f(v["pan"][0]), to_f(v["pan"][1]))
    c3 = clock()
    write_wav_q28(path, @tl, @tr, total, @sr)
    c4 = clock()
    @tm[0] = @tm[0] + (c1 - c0)
    @tm[1] = @tm[1] + (c2 - c1)
    @tm[2] = @tm[2] + (c3 - c2)
    @tm[3] = @tm[3] + (c4 - c3)
    @takes_made += 1
    path

  # One narration line: its processed take (cached or made now), placed from the stored file either way.
  -> place_line(it, bus)
    path = take_file(it)
    c0 = clock()
    q = read_wav_q28(path)
    place_q28(bus, @n, q[0], q[1], it["s0"])
    q[2].close
    @tm[4] = @tm[4] + (clock() - c0)
    nil

  # A cue source after its filter chain (both channels), from build/audio/cue_<key>.wav or made and stored now;
  # loaded into @l/@rr. Returns its frames.
  -> load_chained(key, spec, cap)
    k = hash_of({"dsp" => DSP_VERSION, "kind" => "cue", "sr" => @sr, "src" => asset_sha(key), "chain" => spec})
    path = @dir + "/cue_" + k + ".wav"
    if !File.exist?(path)
      n = load(key, cap)
      chain(spec, @l, n)
      chain(spec, @rr, n)
      write_wav_q28(path, @l, @rr, n, @sr)
      @cues_made += 1
    q = read_wav_q28(path)
    die("scratch too small for " + key) if q[1] + @sr > @cap || cap > @cap
    q28_planar(q[0], q[1], @l, @rr)
    q[2].close
    q[1]

  -> rms_gain_mono(n, target_db, max_db)
    r = Math.sqrt(sumsq(@l, n) / (n + ~0.0) + ~1.0e-12)
    [db_lin(target_db) / r, db_lin(max_db)].min

  -> place_cues(bus, duck, nduck, kinds)
    @r["tracks"][3]["items"].each ->(c)
      if kinds.include?(c["kind"])
        place_cue(c, bus, duck, nduck)
    nil

  -> place_cue(c, bus, duck, nduck)
    k = c["kind"]
    sr = @sr
    cap = 0
    if k == "music"
      cap = c["s1"] - c["s0"] + (to_f(get(c, "fade_out_ms", 2000)) * sr / ~1000.0).to_i + sr + 16
    elsif k == "amb"
      cap = c["s1"] - c["s0"] + (to_f(@mixcfg["amb"]["post_ms"]) * sr / ~1000.0).to_i + 16
    n = 0
    if k == "music"
      mc = @mixcfg["music"]
      n = load_chained(c["src"], mc["chain"], cap)
      fo = (to_f(get(c, "fade_out_ms", 2000)) * sr / ~1000.0).to_i
      seg = c["s1"] - c["s0"] + fo
      need = seg + sr
      xf = (to_f(mc["loop_xf_ms"]) * sr / ~1000.0).to_i
      loop_run(@l, n, @tl, need, xf)
      loop_run(@rr, n, @tr, need, xf)
      copy_run(@tl, @l, need)
      copy_run(@tr, @rr, need)
      g = rms_gain(need, to_f(mc["rms_db"]), ~14.0)
      fi = (to_f(get(c, "fade_in_ms", 1200)) * sr / ~1000.0).to_i
      fade_run(@l, seg, fi, fo)
      fade_run(@rr, seg, fi, fo)
      gain = g * db_lin(to_f(c["gain_db"]) + to_f(mc["offset_db"]))
      place_run(bus, @n, @l, @rr, seg, c["s0"], gain, duck, nduck, to_f(@mixcfg["duck"]["music_db"]))
    elsif k == "amb"
      ac = @mixcfg["amb"]
      n = load_chained(c["src"], ac["chain"], cap)
      g = rms_gain(n, to_f(ac["rms_db"]), to_f(ac["max_gain_db"]))
      need = c["s1"] - c["s0"] + (to_f(ac["post_ms"]) * sr / ~1000.0).to_i
      xf = (~1.5 * sr).to_i
      loop_run(@l, n, @tl, need, xf)
      loop_run(@rr, n, @tr, need, xf)
      fk = (to_f(ac["fade_ms"]) * sr / ~1000.0).to_i
      fade_run(@tl, need, fk, fk)
      fade_run(@tr, need, fk, fk)
      gain = g * db_lin(to_f(c["gain_db"]) + to_f(ac["offset_db"]))
      pre = (to_f(ac["pre_ms"]) * sr / ~1000.0).to_i
      place_run(bus, @n, @tl, @tr, need, c["s0"] - pre, gain, duck, nduck, to_f(@mixcfg["duck"]["amb_db"]))
    elsif k == "sfx"
      if c["filter"] == "tone"
        tc = @mixcfg["tone"]
        n = load_chained(c["src"], tc["chain"], cap)
        g = rms_gain(n, to_f(tc["rms_db"]), to_f(tc["max_gain_db"]))
      else
        sc = @mixcfg["sfx"]
        n = load_chained(c["src"], sc["chain"], cap)
        g = peak_gain(n, to_f(sc["peak_db"]), to_f(sc["max_gain_db"]))
      sc2 = @mixcfg["sfx"]
      fade_run(@l, n, (to_f(sc2["fade_in_ms"]) * sr / ~1000.0).to_i, (to_f(sc2["fade_out_ms"]) * sr / ~1000.0).to_i)
      fade_run(@rr, n, (to_f(sc2["fade_in_ms"]) * sr / ~1000.0).to_i, (to_f(sc2["fade_out_ms"]) * sr / ~1000.0).to_i)
      place_run(bus, @n, @l, @rr, n, c["s0"], g * db_lin(to_f(c["gain_db"])), duck, 0, ~0.0)
    elsif k == "audio"
      n = load(c["src"], cap)
      g = rms_gain(n, to_f(get(c["norm"], "rms_db", (~0.0 - ~19.0))), ~14.0)
      fi = (to_f(get(c, "fade_in_ms", 50)) * sr / ~1000.0).to_i
      fo = (to_f(get(c, "fade_out_ms", 250)) * sr / ~1000.0).to_i
      fade_run(@l, n, fi, fo)
      fade_run(@rr, n, fi, fo)
      place_run(bus, @n, @l, @rr, n, c["s0"], g * db_lin(to_f(get(c, "gain_db", 0))), duck, 0, ~0.0)
    nil

  # The whole soundtrack: returns the report hash; writes out (24-bit WAV, exactly the picture's length).
  -> mix(out)
    t0 = clock_ms()
    prepare()
    n = @n
    bus = f32[n * 2]
    lines = @r["tracks"][2]["items"]
    lines.each ->(it)
      place_line(it, bus)
    t1 = clock_ms()
    dk = @mixcfg["duck"]
    nduck = n / 64 + 1
    duck = f64[nduck]
    duck_env(bus, n, duck, nduck, to_f(dk["attack_ms"]) / ~1000.0, to_f(dk["release_ms"]) / ~1000.0, to_f(dk["full"]), @sr)
    place_cues(bus, duck, nduck, ["music", "amb"])
    place_cues(bus, duck, nduck, ["sfx", "audio"])
    t2 = clock_ms()
    pk = bus_peak(bus, n * 2)
    lim = db_lin(to_f(@mixcfg["peak_db"]))
    bus_scale(bus, n * 2, lim / pk) if pk > lim
    # loudness: measure, apply the linear gain to the target, limit true peaks
    loud = @proj.ep["cuts"][@r["cut"]]["loudness"]
    target = to_f(loud["lufs"])
    ceil = db_lin(to_f(loud["tp"]))
    sub = @sr / 10
    zs = f64[n / sub + 1]
    q0 = clock()
    nb = k_weight_blocks(bus, n, zs, sub)
    before = integrated_lufs(zs, nb)
    gain_db = target - before
    bus_scale(bus, n * 2, db_lin(gain_db))
    h = f64[48]
    tp_taps(h)
    g = f32[n]
    q1 = clock()
    tp_pre = tp_gain(bus, n, h, ceil, g)
    q2 = clock()
    w = @sr / 1000 * 2
    limit_apply(bus, n, g, w, ~1.0 - Math.exp((~0.0 - ~1.0) / (~0.1 * @sr)))
    q3 = clock()
    nb = k_weight_blocks(bus, n, zs, sub)
    after = integrated_lufs(zs, nb)
    q4 = clock()
    tp_post = true_peak(bus, n, h, ceil * ~0.5)
    q5 = clock()
    t3 = clock_ms()
    write_wav_s24(out, bus, n, @sr)
    t4 = clock_ms()
    {"samples" => n, "lines" => lines.size, "cues" => @r["tracks"][3]["items"].size, "lufs_premaster" => before,
     "gain_db" => gain_db, "lufs" => after, "true_peak_dbtp" => ~20.0 * Math.log(tp_post) * ~0.4342944819032518,
     "true_peak_before_limit_dbtp" => ~20.0 * Math.log(tp_pre) * ~0.4342944819032518,
     "takes" => {"cached" => @takes_cached, "made" => @takes_made}, "cue_chains_made" => @cues_made,
     "ms" => {"narration" => t1 - t0, "cues" => t2 - t1, "loudness" => t3 - t2, "write" => t4 - t3},
     "detail_ms" => {"take_chain" => ms_of(@tm[0]), "take_deess" => ms_of(@tm[1]), "take_reverb" => ms_of(@tm[2]),
                     "take_store" => ms_of(@tm[3]), "take_place" => ms_of(@tm[4]), "kweight_gain" => ms_of(q1 - q0),
                     "tp_gain" => ms_of(q2 - q1), "limiter" => ms_of(q3 - q2), "kweight_after" => ms_of(q4 - q3),
                     "true_peak" => ms_of(q5 - q4)}}

# True peak (4x oversampled, both channels) over the whole bus, evaluating interpolation wherever the sample is
# above `floor` and its 12-tap window can exceed the running maximum (the same maximum as evaluating them all).
-> true_peak(bus, n, h, floor) (f32[] i64 f64[] f64) f64
  bound = tp_bound(h)
  maxtp = ~0.0
  sm = f64[36]
  lo = 0
  while lo < n
    hi = lo + 256
    hi = n if hi > n
    base = lo - 16
    have = 0
    i = lo
    i = 6 if i < 6
    while i < hi && i + 6 < n
      c = 0
      while c < 2
        x0 = bus[i * 2 + c] ## f64
        x0 = ~0.0 - x0 if x0 < ~0.0
        maxtp = x0 if x0 > maxtp
        if x0 > floor
          if have == 0
            sub_max(bus, n, 0, base, 18, sm, 0)
            sub_max(bus, n, 1, base, 18, sm, 18)
            have = 1
          wm = sm[c * 18 + (i - 5 - base) / 16]
          w2 = sm[c * 18 + (i + 6 - base) / 16]
          wm = w2 if w2 > wm
          if wm * bound > maxtp
            tp = tp_at(bus, i, c, h)
            maxtp = tp if tp > maxtp
        c += 1
      i += 1
    lo = hi
  maxtp

# The mix is a pure function of the resolved audio tracks, the mix settings, the loudness target and the audio
# assets, so it is cached under that hash (build/audio/mix_<key>.wav): an edit that leaves the sound alone
# (a camera move) reuses it.
-> mix_key(p, r)
  shas = {}
  p.ep["assets"].keys.each ->(k)
    shas[k] = p.asset_sha[k] if get(p.ep["assets"][k], "kind", "") == "audio"
  hash_of({"v" => 4, "dsp" => DSP_VERSION, "sr" => r["sr"], "samples" => r["samples"], "a1" => r["tracks"][2]["items"], "a3" => r["tracks"][3]["items"],
           "mix" => p.ep["mix"], "loudness" => p.ep["cuts"][r["cut"]]["loudness"], "assets" => shas, "seed" => r["seed"]})

-> cmd_mix(args)
  p = Project.new(args[1], (args.size > 3 && args[2] == "--cut") ? args[3] : "full")
  p.verify_assets(true)
  r = p.resolve
  out = p.out_path("mix.wav")
  key = mix_key(p, r)
  cached = p.build + "/audio/mix_" + key + ".wav"
  if File.exist?(cached) && File.exist?(cached + ".json")
    OS.system("rm -f " + shq(out) + " && ln " + shq(cached) + " " + shq(out))
    write_text(p.out_path("mix_report.json"), File.read(cached + ".json"))
    << "mix: unchanged audio (" + key.slice(0, 12) + "), reused " + cached
    return 0
  m = Mixer.new(p, r)
  rep = m.mix(cached)
  write_text(cached + ".json", JSON.encode(rep))
  OS.system("rm -f " + shq(out) + " && ln " + shq(cached) + " " + shq(out))
  write_text(p.out_path("mix_report.json"), JSON.encode(rep))
  << "mix: " + rep["samples"].to_s + " samples (" + timecode(r["frames"], r["rate"][0], r["rate"][1]) + "), " + rep["lines"].to_s + " lines, " + rep["cues"].to_s + " cues; " + fixed6(rep["lufs_premaster"]) + " LUFS + " + fixed6(rep["gain_db"]) + " dB -> " + fixed6(rep["lufs"]) + " LUFS, true peak " + fixed6(rep["true_peak_dbtp"]) + " dBTP -> " + out
  << "mix timing ms: " + JSON.encode(rep["ms"]) + "; takes " + rep["takes"]["cached"].to_s + " cached, " + rep["takes"]["made"].to_s + " made; " + JSON.encode(rep["detail_ms"])
  0
