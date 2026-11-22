# vorbis_test — checks Blade's Vorbis decoder against ffmpeg.
#
#   bin/tungsten benchmarks/codec/vorbis_test.w -- [-n reps] [-fuzz k] [-t tol] file.ogg …
#
# A tiny Ogg reader (first logical stream only) splits the file into packets:
# the first three are the headers (cfg.extra), the rest are decoded one per
# MediaSample. The reference is <file>.f32 (`ffmpeg -i f.ogg -f f32le -c:a
# pcm_f32le f.ogg.f32`). The alignment is searched (ffmpeg starts with the
# first packet that returns audio and trims the end to the last granule
# position); max abs error and SNR are computed over the overlap. -ref .lv.f32
# compares with another reference decode instead (e.g. libvorbisfile's).

use core/codec/media
use core/codec/audio/vorbis

-> vt_u8(s)
  ccall("w_string_bytes_view", s) ## u8[]

-> vt_copy(src, so, dst, d0, n) (u8[] i64 u8[] i64 i64) i64
  i = 0 ## i64
  while i < n
    dst[d0 + i] = src[so + i]
    i += 1
  n

# Ogg pages -> packets of the first stream: [packets, granules (last granule per page end)]
-> vt_ogg_packets(b)
  n = b.size
  p = 0
  serial = nil
  packets = []
  cur = []
  curlen = 0
  last_gran = 0
  while p + 27 <= n
    if b[p] != 79 || b[p + 1] != 103 || b[p + 2] != 103 || b[p + 3] != 83
      p += 1
    else
      ns = b[p + 26]
      sr = b[p + 14] | (b[p + 15] << 8) | (b[p + 16] << 16) | (b[p + 17] << 24)
      g = 0
      k = 7
      while k >= 0
        g = (g << 8) | b[p + 6 + k]
        k -= 1
      serial = sr if serial == nil
      body = p + 27 + ns
      q = body
      if sr == serial
        last_gran = g
        i = 0
        while i < ns
          l = b[p + 27 + i]
          cur.push([q, l])
          curlen += l
          q += l
          if l < 255
            pk = u8[curlen]
            o = 0
            cur.each ->(seg)
              vt_copy(b, seg[0], pk, o, seg[1])
              o += seg[1]
            packets.push(pk)
            cur = []
            curlen = 0
          i += 1
      else
        i = 0
        while i < ns
          q += b[p + 27 + i]
          i += 1
      p = q
  [packets, last_gran]

-> vt_pow2_table
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

VT_P2 = vt_pow2_table()

-> vt_f32_decode(b, n, out, p2) (u8[] i64 f64[] f64[]) i64
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

-> vt_put(dst, d0, src, n) (f32[] i64 f32[] i64) i64
  i = 0 ## i64
  while i < n
    dst[d0 + i] = src[i]
    i += 1
  n

-> vt_maxdiff(a, an, mo, r, rn, n) (f32[] i64 i64 f64[] i64 i64) f64
  mx = ~0.0
  i = 0 ## i64
  while i < n
    if mo + i >= 0 && mo + i < an && i < rn
      d = (a[mo + i] ## f64) - r[i]
      d = ~0.0 - d if d < ~0.0
      mx = d if d > mx
    i += 1
  mx

-> vt_stats(a, an, mo, r, rn, out) (f32[] i64 i64 f64[] i64 f64[]) i64
  mx = ~0.0
  se = ~0.0
  ee = ~0.0
  c = 0 ## i64
  i = 0 ## i64
  while mo + i < an && i < rn
    if mo + i >= 0
      rv = r[i]
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

-> vt_fuzz(cfg, audio, seed)
  rng = seed
  dec = acodec_new(cfg)
  nok = 0
  nerr = 0
  audio.each ->(d)
    n = d.size
    if n > 0
      m = u8[n]
      vt_copy(d, 0, m, 0, n)
      flips = 1 + rng % 6
      j = 0
      while j < flips
        rng = (rng * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
        pos = (rng >> 16) % n
        rng = (rng * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
        m[pos] = (rng >> 24) & 255
        j += 1
      begin
        dec.decode(MediaSample.new(m, ~0.0, ~0.0, ~0.0, true))
        nok += 1
      rescue e
        nerr += 1
        << "  non-MediaError: [e]" if !e.is_a?(MediaError)
  [nok, nerr]

reps = 1
suffix = ".f32"
fuzz = 0
tol = ~0.0001
files = []
args = ARGV
i = 0
while i < args.size
  if args[i] == "-n"
    reps = args[i + 1].to_i
    i += 2
  elsif args[i] == "-ref"
    suffix = args[i + 1]
    i += 2
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
    og = vt_ogg_packets(vt_u8(File.read(f)))
    pk = og[0]
    cfg = CodecConfig.new("vorb", [pk[0], pk[1], pk[2]])
    audio = pk.slice(3, pk.size - 3)
    dec = acodec_new(cfg)
    nch = dec.channels
    rate = dec.rate
    blocks = []
    t0 = clock_ms()
    audio.each ->(d)
      bl = dec.decode(MediaSample.new(d, ~0.0, ~0.0, ~0.0, true))
      blocks.push(bl) if bl != nil
    k = 1
    while k < reps
      d2 = acodec_new(cfg)
      audio.each ->(d)
        d2.decode(MediaSample.new(d, ~0.0, ~0.0, ~0.0, true))
      k += 1
    ms_all = clock_ms() - t0
    total = 0
    blocks.each ->(bl)
      total += bl.frames * bl.channels
    mine = f32[total + 1]
    o = 0
    blocks.each ->(bl)
      vt_put(mine, o, bl.samples, bl.frames * bl.channels)
      o += bl.frames * bl.channels
    frames_out = total / nch
    dur = frames_out / (rate * ~1.0)
    rtf = (ms_all / ~1000.0) / reps / dur
    refp = f + suffix
    if !File.exist?(refp)
      << "NREF [name] [rate]Hz ch=[nch] packets=[audio.size] out=[frames_out] granule=[og[1]] rtf=[rtf]"
    else
      rb = vt_u8(File.read(refp))
      rn = rb.size / 4
      ref = f64[rn + 1]
      vt_f32_decode(rb, rn, ref, VT_P2)
      best = 0
      bestd = ~1.0e9
      off = -4096
      while off <= 4096
        dd = vt_maxdiff(mine, total, off * nch, ref, rn, 8192 * nch)
        if dd < bestd
          bestd = dd
          best = off
        off += 1
      stv = f64[4]
      vt_stats(mine, total, best * nch, ref, rn, stv)
      snr = ~999.0
      snr = ~10.0 * Math.log10(stv[1] / stv[2]) if stv[2] > ~0.0 && stv[1] > ~0.0
      tag = "ok  "
      if stv[0] > tol
        tag = "FAIL"
        nfail += 1
      << "[tag] [name] [rate]Hz ch=[nch] packets=[audio.size] out=[frames_out] ref=[rn / nch] granule=[og[1]] align=[best] cmp=[(stv[3] / nch).to_i] maxerr=[stv[0]] snr=[snr] rtf=[rtf]"
    if fuzz > 0
      fz = 0
      while fz < fuzz
        rr = vt_fuzz(cfg, audio, 4242 + fz * 7777)
        << "  fuzz [fz]: decoded [rr[0]] raised [rr[1]]"
        fz += 1
  rescue e
    << "FAIL [name] error: [e]"
    nfail += 1
<< "failures: [nfail] / [files.size]"
