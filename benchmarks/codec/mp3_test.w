# mp3_test — checks Blade's MPEG audio decoder against ffmpeg.
#
#   bin/tungsten benchmarks/codec/mp3_test.w -- [-n reps] [-fuzz k] [-t tol] file.mp3 …
#
# Each file is split with mp3_es_parse and decoded frame by frame. The
# reference is <file>.f32 next to it (`ffmpeg -i f -f f32le -c:a pcm_f32le
# f.f32`: float interleaved, with ffmpeg's gapless trimming). Our output is
# trimmed by the first sample's pts (as the pipeline would); the alignment
# with the reference is then searched in ±2400 samples. Prints max abs
# error, SNR, sample counts and the decode real-time factor.

use core/codec/media
use core/codec/audio/mp3

-> mt_u8(s)
  ccall("w_string_bytes_view", s) ## u8[]

-> mt_pow2_table
  t = f64[300]
  p = ~1.0
  i = 150
  while i < 300
    t[i] = p
    p = p * ~2.0
    i += 1
  p = ~0.5
  i = 149
  while i >= 0
    t[i] = p
    p = p * ~0.5
    i -= 1
  t

MT_P2 = mt_pow2_table()

# f32le bytes -> f64[]
-> mt_f32_decode(b, n, out, p2) (u8[] i64 f64[] f64[]) i64
  i = 0 ## i64
  while i < n
    bits = b[4 * i] | (b[4 * i + 1] << 8) | (b[4 * i + 2] << 16) | (b[4 * i + 3] << 24)
    e = (bits >> 23) & 255
    m = bits & 8388607
    v = ~0.0
    if e == 0
      v = (m * ~1.0) * p2[1]
    else
      v = ((m | 8388608) * ~1.0) * p2[e]
    v = ~0.0 - v if (bits >> 31) != 0
    out[i] = v
    i += 1
  n

# s16le bytes -> f64[] / 32768
-> mt_s16_decode(b, n, out) (u8[] i64 f64[]) i64
  i = 0 ## i64
  while i < n
    v = b[2 * i] | (b[2 * i + 1] << 8)
    v = v - 65536 if v >= 32768
    out[i] = v / ~32768.0
    i += 1
  n

# f32[] -> s32le bytes (v * 2^30, clipped) for offline inspection
-> mt_s32_bytes(a, n, out) (f32[] i64 u8[]) i64
  i = 0 ## i64
  while i < n
    v = ((a[i] ## f64) * ~1073741824.0) ## i64
    v = 2147483647 if v > 2147483647
    v = -2147483648 if v < -2147483648
    out[4 * i] = v & 255
    out[4 * i + 1] = (v >> 8) & 255
    out[4 * i + 2] = (v >> 16) & 255
    out[4 * i + 3] = (v >> 24) & 255
    i += 1
  n

-> mt_put(dst, d0, src, n) (f32[] i64 f32[] i64) i64
  i = 0 ## i64
  while i < n
    dst[d0 + i] = src[i]
    i += 1
  n

# max abs diff over n values of mine[mo ..] vs ref[ro ..] (bounded by sizes)
-> mt_maxdiff(a, an, mo, r, rn, ro, n) (f32[] i64 i64 f64[] i64 i64 i64) f64
  mx = ~0.0
  i = 0 ## i64
  while i < n
    if mo + i >= 0 && mo + i < an && ro + i >= 0 && ro + i < rn
      d = (a[mo + i] ## f64) - r[ro + i]
      d = ~0.0 - d if d < ~0.0
      mx = d if d > mx
    i += 1
  mx

# out: 0 max err, 1 signal energy, 2 error energy, 3 count
-> mt_stats(a, an, mo, r, rn, ro, out) (f32[] i64 i64 f64[] i64 i64 f64[]) i64
  mx = ~0.0
  se = ~0.0
  ee = ~0.0
  c = 0 ## i64
  i = 0 ## i64
  while mo + i < an && ro + i < rn
    if mo + i >= 0 && ro + i >= 0
      rv = r[ro + i]
      d = (a[mo + i] ## f64) - rv
      se += rv * rv
      ee += d * d
      d = ~0.0 - d if d < ~0.0
      mx = d if d > mx
      c += 1
    i += 1
  out[0] = mx
  out[1] = se
  out[2] = ee
  out[3] = c * ~1.0
  c

-> mt_fuzz(samples, seed)
  rng = seed
  dec = acodec_new(CodecConfig.new("mp3 ", nil))
  nok = 0
  nerr = 0
  samples.each ->(smp)
    d = smp.data
    n = d.size
    m = u8[n]
    k = 0
    while k < n
      m[k] = d[k]
      k += 1
    flips = 1 + rng % 6
    j = 0
    while j < flips
      rng = (rng * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
      pos = (rng >> 16) % n
      rng = (rng * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
      m[pos] = (rng >> 24) & 255
      j += 1
    begin
      dec.decode(MediaSample.new(m, smp.pts, smp.dts, smp.duration, true))
      nok += 1
    rescue e
      nerr += 1
      << "  non-MediaError: [e]" if !e.is_a?(MediaError)
  [nok, nerr]

reps = 1
dump = nil
use_pcm = false
fuzz = 0
tol = ~0.0001
files = []
args = ARGV
i = 0
while i < args.size
  if args[i] == "-n"
    reps = args[i + 1].to_i
    i += 2
  elsif args[i] == "-dump"
    dump = args[i + 1]
    i += 2
  elsif args[i] == "-pcm"
    use_pcm = true
    i += 1
  elsif args[i] == "-fuzz"
    fuzz = args[i + 1].to_i
    i += 2
  elsif args[i] == "-t"
    tol = args[i + 1].to_f
    i += 2
  else
    files.push(args[i])
    i += 1

nfail = 0
files.each ->(f)
  name = f.split("/").last
  begin
    es = mp3_es_parse(File.read(f))
    cfg = es[:cfg]
    samples = es[:samples]
    dec = acodec_new(cfg)
    blocks = []
    t0 = clock_ms()
    samples.each ->(smp)
      blocks.push(dec.decode(smp))
    ms = clock_ms() - t0
    k = 1
    while k < reps
      d2 = acodec_new(cfg)
      samples.each ->(smp)
        d2.decode(smp)
      k += 1
    ms_all = clock_ms() - t0
    total = 0
    nch = cfg.channels
    blocks.each ->(bl)
      total += bl.frames * bl.channels
    mine = f32[total + 1]
    o = 0
    chg = false
    blocks.each ->(bl)
      mt_put(mine, o, bl.samples, bl.frames * bl.channels)
      o += bl.frames * bl.channels
      chg = true if bl.channels != nch
    if dump != nil
      db = u8[total * 4]
      mt_s32_bytes(mine, total, db)
      File.write_bytes(dump + "/" + name + ".mine.s32", db)
    rate = cfg.sample_rate
    frames_out = total / nch
    dur = frames_out / (rate * ~1.0)
    rtf = (ms_all / ~1000.0) / reps / dur
    skip = 0
    if samples.size > 0 && samples[0].pts < ~0.0
      skip = ((~0.0 - samples[0].pts) * rate + ~0.5).to_i
    refp = f + ".f32"
    refp = f.sub(".bit", ".pcm") if use_pcm
    if !File.exist?(refp)
      << "NREF [name] [rate]Hz ch=[nch] frames=[samples.size] out=[frames_out] skip=[skip] dur=[es[:duration]] rtf=[rtf]"
    else
      rb = mt_u8(File.read(refp))
      rn = rb.size / 4
      rn = rb.size / 2 if use_pcm
      ref = f64[rn + 1]
      if use_pcm
        mt_s16_decode(rb, rn, ref)
      else
        mt_f32_decode(rb, rn, ref, MT_P2)
      # alignment search around the pts trim
      best = skip * nch
      bestd = ~1.0e9
      off = -2400
      while off <= 2400
        mo = (skip + off) * nch
        dd = mt_maxdiff(mine, total, mo, ref, rn, 0, 4096 * nch)
        if dd < bestd
          bestd = dd
          best = mo
        off += 1
      stv = f64[4]
      mt_stats(mine, total, best, ref, rn, 0, stv)
      snr = ~999.0
      snr = ~10.0 * Math.log10(stv[1] / stv[2]) if stv[2] > ~0.0 && stv[1] > ~0.0
      shift = best / nch - skip
      tag = "ok  "
      want = (es[:duration] * rate + ~0.5).to_i
      if stv[0] > tol || shift != 0 || want * nch != rn
        tag = "DIFF"
        tag = "FAIL" if stv[0] > tol
        nfail += 1 if stv[0] > tol
      << "[tag] [name] [rate]Hz ch=[nch] frames=[samples.size] out=[frames_out] skip=[skip] trimmed=[(total / nch) - skip] dur=[want] ref=[rn / nch] align=[shift] maxerr=[stv[0]] snr=[snr] bad=[dec.bad_frames] rtf=[rtf]"
    if fuzz > 0
      fz = 0
      while fz < fuzz
        rr = mt_fuzz(samples, 777 + fz * 31337)
        << "  fuzz [fz]: decoded [rr[0]] raised [rr[1]]"
        fz += 1
  rescue e
    << "FAIL [name] error: [e]"
    nfail += 1
<< "failures: [nfail] / [files.size]"
