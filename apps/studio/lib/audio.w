# studio/audio — `studio mix`: the soundtrack as a pure function of the resolved audio tracks (TIMELINE.md §3.4).
#
# Port of the episode's tools/mix.py without ffmpeg: MP3s are decoded once by macOS afconvert into
# build/audio/<sha256>.wav (48 kHz float), then every filter of the legacy chains runs here — RBJ biquads (the
# ffmpeg highpass/lowpass/equalizer/treble designs), ffmpeg's deesser and acompressor algorithms, the FFT
# split-band de-esser, noise-IR reverb by FFT convolution, looping with crossfades, sample-exact placement,
# block ducking — then EBU R128 normalisation (BS.1770-4 integrated loudness, linear gain to the cut's target)
# with a 4x-oversampled true-peak limiter, written as 48 kHz / 24-bit PCM exactly as long as the picture.

use base

SR48 = 48000

-> db_lin(x)
  Math.exp(x * ~0.11512925464970229)

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
    offset = ~1.0 - sample.abs
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
    a = x[i].abs
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
    v = x[i].abs
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

-> fft_tables(n, cs, sn) (i64 f64[] f64[]) i64
  i = 0
  while i < n / 2
    a = ~6.283185307179586 * (i ## f64) / (n ## f64)
    cs[i] = Math.cos(a)
    sn[i] = Math.sin(a)
    i += 1
  0

# In-place iterative radix-2 FFT of length n (power of 2); inv != 0 for the inverse (unscaled). cs/sn hold the
# twiddles of a larger power of two; ts = that size / n.
-> fft_run(re, im, n, inv, cs, sn, ts) (f64[] f64[] i64 i64 f64[] f64[] i64) i64
  j = 0
  i = 0
  while i < n
    if i < j
      t = re[i]
      re[i] = re[j]
      re[j] = t
      t = im[i]
      im[i] = im[j]
      im[j] = t
    m = n / 2
    while m >= 1 && j >= m
      j = j - m
      m = m / 2
    j = j + m
    i += 1
  len = 2
  while len <= n
    half = len / 2
    step = n / len
    s = 0
    while s < n
      k = 0
      while k < half
        wr = cs[k * step * ts]
        wi = sn[k * step * ts]
        if inv == 0
          wi = ~0.0 - wi
        a = s + k
        b = a + half
        tr = re[b] * wr - im[b] * wi
        ti = re[b] * wi + im[b] * wr
        re[b] = re[a] - tr
        im[b] = im[a] - ti
        re[a] = re[a] + tr
        im[a] = im[a] + ti
        k += 1
      s += len
    len = len * 2
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

# tools/mix.py deess_dynamic: split at ~3.4 kHz with a linear-phase frequency weighting (FFT), follow the high
# and low band block RMS (32 samples) with attack/release, and clamp the high band against the body.
-> deess_hi_split(re, im, nfft, sr, cross) (f64[] f64[] i64 i64 f64) i64
  k = 0
  while k <= nfft / 2
    fr = (k ## f64) * (sr ## f64) / (nfft ## f64)
    w = (fr - (cross - ~400.0)) / ~800.0
    w = ~0.0 if w < ~0.0
    w = ~1.0 if w > ~1.0
    re[k] = re[k] * w
    im[k] = im[k] * w
    if k > 0 && k < nfft / 2
      re[nfft - k] = re[nfft - k] * w
      im[nfft - k] = im[nfft - k] * w
    k += 1
  0

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

# ---------------------------------------------------------------------------------------------- bus

# Add (left, right) * gain into the interleaved bus at sample s0 (clipped to the bus), with an optional duck:
# the gain is multiplied by db(depth * duck[sample / 64]) when depth != 0.
-> place_run(bus, nbus, left, right, n, s0, gain, duck, nduck, depth) (f32[] i64 f64[] f64[] i64 i64 f64 f64[] i64 f64) i64
  i = 0
  if s0 < 0
    i = 0 - s0
  while i < n && s0 + i < nbus
    p = s0 + i
    g = gain
    if depth != ~0.0
      b = p / 64
      d = ~0.0
      d = duck[b] if b < nduck
      g = g * Math.exp(depth * d * ~0.11512925464970229)
    bus[p * 2] = ((bus[p * 2] ## f64) + left[i] * g) ## f32
    bus[p * 2 + 1] = ((bus[p * 2 + 1] ## f64) + right[i] * g) ## f32
    i += 1
  0

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
      v = ((bus[i * 2] ## f64).abs + (bus[i * 2 + 1] ## f64).abs) * ~0.5
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
    v = (bus[i] ## f64).abs
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

# BS.1770-4 K-weighted mean square per 100 ms sub-block (both channels summed), into zs.
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
  b = 0
  while b < nb
    zs[b] = ~0.0
    b += 1
  c = 0
  while c < 2
    x1 = ~0.0
    x2 = ~0.0
    y1 = ~0.0
    y2 = ~0.0
    u1 = ~0.0
    u2 = ~0.0
    v1 = ~0.0
    v2 = ~0.0
    i = 0
    while i < nb * sub
      x = bus[i * 2 + c] ## f64
      y = sb0 * x + sb1 * x1 + sb2 * x2 - sa1 * y1 - sa2 * y2
      x2 = x1
      x1 = x
      y2 = y1
      y1 = y
      v = hb0 * y + hb1 * u1 + hb2 * u2 - ha1 * v1 - ha2 * v2
      u2 = u1
      u1 = y
      v2 = v1
      v1 = v
      b = i / sub
      zs[b] = zs[b] + v * v
      i += 1
    c += 1
  b = 0
  while b < nb
    zs[b] = zs[b] / (sub ## f64)
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

# Per sample, the gain that keeps the 4x-oversampled peak of both channels at or under ceil (1 where it already
# is), into g (n entries). Only windows whose sample peak could exceed ceil after interpolation are evaluated.
-> tp_gain(bus, n, h, ceil, g) (f32[] i64 f64[] f64 f32[]) f64
  maxtp = ~0.0
  safe = ceil / ~1.7
  nb = n / 256 + 1
  bm = f64[nb]
  i = 0
  while i < n
    v = (bus[i * 2] ## f64).abs
    w = (bus[i * 2 + 1] ## f64).abs
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
      i = lo
      while i < hi
        gi = ~1.0
        c = 0
        while c < 2
          tp = (bus[i * 2 + c] ## f64).abs
          if i >= 6 && i + 6 < n
            p = 0
            while p < 4
              acc = ~0.0
              k = 0
              while k < 12
                acc = acc + (bus[(i + k - 5) * 2 + c] ## f64) * h[p * 12 + k]
                k += 1
              acc = acc.abs
              tp = acc if acc > tp
              p += 1
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

  # Every scratch buffer is allocated once, at the largest size any take or cue needs (an array that is
  # reassigned is not freed until exit, so growing on demand would keep every old size alive).
  -> prepare
    cap = 0
    mfft = 1
    @r["tracks"][2]["items"].each ->(it)
      fr = frames_of(it["src"])
      cap = [cap, fr + @sr * 2].max
      mfft = [mfft, fft_size(fr)].max
    @r["tracks"][3]["items"].each ->(c)
      fr = frames_of(c["src"])
      need = fr + @sr * 2
      if c["kind"] == "music"
        need = [need, c["s1"] - c["s0"] + (to_f(get(c, "fade_out_ms", 2000)) * @sr / ~1000.0).to_i + @sr + 16].max
      elsif c["kind"] == "amb"
        need = [need, c["s1"] - c["s0"] + (to_f(@mixcfg["amb"]["post_ms"]) * @sr / ~1000.0).to_i + 16].max
      cap = [cap, need].max
    mfft = [mfft, 131072].max
    @cap = cap
    @l = f64[cap]
    @rr = f64[cap]
    @tl = f64[cap]
    @tr = f64[cap]
    @env = f64[cap / 32 + 2]
    @mfft = mfft
    @re = f64[mfft]
    @im = f64[mfft]
    @cs = f64[mfft / 2]
    @sn = f64[mfft / 2]
    fft_tables(mfft, @cs, @sn)
    @blk = 131072
    @bre = f64[@blk]
    @bim = f64[@blk]
    @bre2 = f64[@blk]
    @bim2 = f64[@blk]
    @ir = f64[@sr * 2]
    @irspec = {}
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

  -> chain(spec, x, n)
    spec.each ->(f)
      k = f[0]
      if k == "deesser"
        deesser_run(x, n, to_f(f[1]), to_f(f[2]), to_f(f[3]), @sr)
      elsif k == "compressor"
        compressor_run(x, n, db_lin(to_f(f[1])), to_f(f[2]), to_f(f[3]), to_f(f[4]), to_f(f[5]), ~2.82843, @sr)
      else
        gain = ~0.0
        gain = to_f(f[3]) if f.size > 3
        c = biquad_design(k, to_f(f[1]), to_f(f[2]), gain, @sr + ~0.0)
        biquad_run(x, n, c[0], c[1], c[2], c[3], c[4])
    nil

  -> rms_gain(n, target_db, max_db)
    r = Math.sqrt((sumsq(@l, n) + sumsq(@rr, n)) / (~2.0 * n) + ~1.0e-12)
    [db_lin(target_db) / r, db_lin(max_db)].min

  -> peak_gain(n, target_db, max_db)
    pk = [peak_abs(@l, n), peak_abs(@rr, n)].max + ~1.0e-9
    [db_lin(target_db) / pk, db_lin(max_db)].min

  -> fft_size(n)
    m = 1
    m = m * 2 while m < n
    m

  # The spectrum (at the overlap-add block size) of a voice's noise IR for one channel, made once.
  -> ir_spectrum(rev, c)
    key = rev[0].to_s + ":" + rev[2].to_s + ":" + c.to_s
    sp = @irspec[key]
    if sp == nil
      irn = (to_f(rev[0]) * @sr / ~1000.0).to_i
      make_ir(rng_key(@seed, id60("ir:" + rev[0].to_s + ":" + rev[2].to_s), c, P_IR), irn, to_f(rev[0]) / ~1000.0, to_f(rev[2]), @sr, @ir)
      hr = f64[@blk]
      hi = f64[@blk]
      copy_run(@ir, hr, irn)
      fft_run(hr, hi, @blk, 0, @cs, @sn, @mfft / @blk)
      sp = [hr, hi, irn]
      @irspec[key] = sp
    sp

  # One narration line: chain -> rms -> split-band de-ess (FFT) -> pan -> reverb (overlap-add) -> place.
  -> place_line(it, bus)
    v = @mixcfg["voices"][it["spk"]]
    vo = @mixcfg["vo"]
    n = load(it["src"], 0)
    # mono processing: the legacy chain ran on the mono file before upmixing
    chain(v["chain"], @l, n)
    g = rms_gain_mono(n, to_f(vo["rms_db"]), to_f(vo["max_gain_db"])) * db_lin(to_f(v["gain_db"]))
    scale_run(@l, n, g)
    de = vo["deess"]
    m = fft_size(n)
    copy_run(@l, @re, n)
    zero_run(@re, n, m)
    zero_run(@im, 0, m)
    fft_run(@re, @im, m, 0, @cs, @sn, @mfft / m)
    deess_hi_split(@re, @im, m, @sr, to_f(de["cross_hz"]))
    fft_run(@re, @im, m, 1, @cs, @sn, @mfft / m)
    scale_run(@re, m, ~1.0 / m)
    deess_apply(@l, @re, n, @sr, to_f(de["max_ratio"]), db_lin(to_f(de["abs_db"])), @env, @env)
    rev = v["reverb"]
    s0 = ir_spectrum(rev, 0)
    s1 = ir_spectrum(rev, 1)
    irn = s0[2]
    total = n + irn - 1
    ola_reverb(@l, n, s0[0], s0[1], s1[0], s1[1], irn, @blk, @cs, @sn, @mfft / @blk, @bre, @bim, @bre2, @bim2, @tl, @tr, total, to_f(rev[1]), to_f(v["pan"][0]), to_f(v["pan"][1]))
    place_run(bus, @n, @tl, @tr, total, it["s0"], ~1.0, @l, 0, ~0.0)
    nil

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
    n = load(c["src"], cap)
    if k == "music"
      mc = @mixcfg["music"]
      chain(mc["chain"], @l, n)
      chain(mc["chain"], @rr, n)
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
      chain(ac["chain"], @l, n)
      chain(ac["chain"], @rr, n)
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
        chain(tc["chain"], @l, n)
        chain(tc["chain"], @rr, n)
        g = rms_gain(n, to_f(tc["rms_db"]), to_f(tc["max_gain_db"]))
      else
        sc = @mixcfg["sfx"]
        chain(sc["chain"], @l, n)
        chain(sc["chain"], @rr, n)
        g = peak_gain(n, to_f(sc["peak_db"]), to_f(sc["max_gain_db"]))
      sc2 = @mixcfg["sfx"]
      fade_run(@l, n, (to_f(sc2["fade_in_ms"]) * sr / ~1000.0).to_i, (to_f(sc2["fade_out_ms"]) * sr / ~1000.0).to_i)
      fade_run(@rr, n, (to_f(sc2["fade_in_ms"]) * sr / ~1000.0).to_i, (to_f(sc2["fade_out_ms"]) * sr / ~1000.0).to_i)
      place_run(bus, @n, @l, @rr, n, c["s0"], g * db_lin(to_f(c["gain_db"])), duck, 0, ~0.0)
    elsif k == "audio"
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
    nb = k_weight_blocks(bus, n, zs, sub)
    before = integrated_lufs(zs, nb)
    gain_db = target - before
    bus_scale(bus, n * 2, db_lin(gain_db))
    h = f64[48]
    tp_taps(h)
    g = f32[n]
    tp_pre = tp_gain(bus, n, h, ceil, g)
    w = @sr / 1000 * 2
    limit_apply(bus, n, g, w, ~1.0 - Math.exp((~0.0 - ~1.0) / (~0.1 * @sr)))
    nb = k_weight_blocks(bus, n, zs, sub)
    after = integrated_lufs(zs, nb)
    tp_post = true_peak(bus, n, h, ceil * ~0.5)
    t3 = clock_ms()
    write_wav_s24(out, bus, n, @sr)
    t4 = clock_ms()
    {"samples" => n, "lines" => lines.size, "cues" => @r["tracks"][3]["items"].size, "lufs_premaster" => before,
     "gain_db" => gain_db, "lufs" => after, "true_peak_dbtp" => ~20.0 * Math.log(tp_post) * ~0.4342944819032518,
     "true_peak_before_limit_dbtp" => ~20.0 * Math.log(tp_pre) * ~0.4342944819032518,
     "ms" => {"narration" => t1 - t0, "cues" => t2 - t1, "loudness" => t3 - t2, "write" => t4 - t3}}

# Reverb by overlap-add: blocks of blk - irn + 1 samples, FFT once, multiply by each channel's IR spectrum,
# inverse, accumulate. outl/outr = (dry * (1 - wet / 2) + wet * x (*) ir_c) * pan_c, total = n + irn - 1 samples.
-> ola_reverb(x, n, h0r, h0i, h1r, h1i, irn, blk, cs, sn, ts, bre, bim, bre2, bim2, outl, outr, total, wet, pl, pr) (f64[] i64 f64[] f64[] f64[] f64[] i64 i64 f64[] f64[] i64 f64[] f64[] f64[] f64[] f64[] f64[] i64 f64 f64 f64) i64
  zero_run(outl, 0, total)
  zero_run(outr, 0, total)
  lb = blk - irn + 1
  inv = ~1.0 / (blk ## f64)
  st = 0
  while st < n
    len = lb
    len = n - st if st + len > n
    i = 0
    while i < blk
      v = ~0.0
      v = x[st + i] if i < len
      bre[i] = v
      bim[i] = ~0.0
      i += 1
    fft_run(bre, bim, blk, 0, cs, sn, ts)
    i = 0
    while i < blk
      bre2[i] = bre[i] * h1r[i] - bim[i] * h1i[i]
      bim2[i] = bre[i] * h1i[i] + bim[i] * h1r[i]
      r = bre[i] * h0r[i] - bim[i] * h0i[i]
      q = bre[i] * h0i[i] + bim[i] * h0r[i]
      bre[i] = r
      bim[i] = q
      i += 1
    fft_run(bre, bim, blk, 1, cs, sn, ts)
    fft_run(bre2, bim2, blk, 1, cs, sn, ts)
    i = 0
    while i < len + irn - 1 && st + i < total
      outl[st + i] = outl[st + i] + bre[i] * inv
      outr[st + i] = outr[st + i] + bre2[i] * inv
      i += 1
    st += lb
  dry = ~1.0 - wet * ~0.5
  i = 0
  while i < total
    d = ~0.0
    d = x[i] if i < n
    outl[i] = (d * dry + outl[i] * wet) * pl
    outr[i] = (d * dry + outr[i] * wet) * pr
    i += 1
  0

# True peak (4x oversampled, both channels) over the whole bus, evaluating interpolation wherever the sample
# peak nearby is above `floor`.
-> true_peak(bus, n, h, floor) (f32[] i64 f64[] f64) f64
  maxtp = ~0.0
  i = 6
  while i + 6 < n
    c = 0
    while c < 2
      x0 = (bus[i * 2 + c] ## f64).abs
      maxtp = x0 if x0 > maxtp
      if x0 > floor
        p = 0
        while p < 4
          acc = ~0.0
          k = 0
          while k < 12
            acc = acc + (bus[(i + k - 5) * 2 + c] ## f64) * h[p * 12 + k]
            k += 1
          acc = acc.abs
          maxtp = acc if acc > maxtp
          p += 1
      c += 1
    i += 1
  maxtp

-> cmd_mix(args)
  p = Project.new(args[1], (args.size > 3 && args[2] == "--cut") ? args[3] : "full")
  p.verify_assets(true)
  r = p.resolve
  out = p.build + "/" + p.cut + "/mix.wav"
  m = Mixer.new(p, r)
  rep = m.mix(out)
  write_text(p.build + "/" + p.cut + "/mix_report.json", JSON.encode(rep))
  << "mix: " + rep["samples"].to_s + " samples (" + timecode(r["frames"], r["rate"][0], r["rate"][1]) + "), " + rep["lines"].to_s + " lines, " + rep["cues"].to_s + " cues; " + fixed6(rep["lufs_premaster"]) + " LUFS + " + fixed6(rep["gain_db"]) + " dB -> " + fixed6(rep["lufs"]) + " LUFS, true peak " + fixed6(rep["true_peak_dbtp"]) + " dBTP -> " + out
  << "mix timing ms: " + JSON.encode(rep["ms"])
  0
