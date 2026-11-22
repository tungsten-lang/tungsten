# flac_test — checks Blade's FLAC decoder against ffmpeg.
#
#   bin/tungsten benchmarks/codec/flac_test.w -- [-n reps] file.flac …
#
# Each file is split with flac_es_parse and decoded frame by frame. The
# reference is <file>.s32 next to it (made with
# `ffmpeg -i f.flac -f s32le -c:a pcm_s32le f.flac.s32`): int32 interleaved,
# the sample shifted up to 32 bits. The decoder's integer samples must match
# exactly; the f32 output is also compared with ref / 2^31. Prints frames,
# mismatches, max float error and the decode real-time factor (decode time /
# audio duration; -n repeats the decode for timing).

use core/codec/media
use core/codec/audio/flac

-> ft_u8(s)
  ccall("w_string_bytes_view", s) ## u8[]

-> ft_s32(b, i) (u8[] i64) i64
  v = b[i] | (b[i + 1] << 8) | (b[i + 2] << 16) | (b[i + 3] << 24)
  v = v - 4294967296 if v >= 2147483648
  v

# compare frames of decoded ints (channel c at c*stride) with ref at sample
# offset off (interleaved). r: 0 mismatches, 1 max int diff, 2 compared count
-> ft_cmp(s, stride, ch, bs, shift, ref, nref, off, r) (i64[] i64 i64 i64 i64 u8[] i64 i64 i64[]) i64
  i = 0 ## i64
  while i < bs
    c = 0 ## i64
    while c < ch
      k = (off + i) * ch + c
      if k * 4 + 4 <= nref
        want = ft_s32(ref, k * 4)
        got = s[c * stride + i] << shift
        d = got - want
        d = 0 - d if d < 0
        if d != 0
          r[0] = r[0] + 1
          r[1] = d if d > r[1]
        r[2] = r[2] + 1
      c += 1
    i += 1
  0

-> ft_fcmp(f, n, ref, nref, off, ch) (f32[] i64 u8[] i64 i64 i64) f64
  mx = ~0.0
  i = 0 ## i64
  while i < n
    k = off * ch + i
    if k * 4 + 4 <= nref
      want = ft_s32(ref, k * 4) / ~2147483648.0
      d = (f[i] ## f64) - want
      d = ~0.0 - d if d < ~0.0
      mx = d if d > mx
    i += 1
  mx

# corrupt copies of every sample: flipped bytes and truncation; decoding
# must raise MediaError or return a block, never crash or hang
-> ft_fuzz(cfg, samples, seed)
  rng = seed
  dec = acodec_new(cfg)
  nerr = 0
  nok = 0
  samples.each ->(smp)
    d = smp.data
    n = d.size
    m = u8[n]
    k = 0
    while k < n
      m[k] = d[k]
      k += 1
    flips = 1 + rng % 4
    j = 0
    while j < flips
      rng = (rng * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
      pos = (rng >> 16) % n
      rng = (rng * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
      m[pos] = (rng >> 24) & 255
      j += 1
    rng = (rng * 6364136223846793005 + 1442695040888963407) & 9223372036854775807
    if rng % 5 == 0
      cut = (rng >> 20) % n
      m2 = u8[cut]
      k = 0
      while k < cut
        m2[k] = m[k]
        k += 1
      m = m2
    begin
      dec.decode(MediaSample.new(m, smp.pts, smp.dts, smp.duration, true))
      nok += 1
    rescue e
      nerr += 1
      << "  non-MediaError: [e]" if !e.is_a?(MediaError)
  [nok, nerr]

fuzz = 0
reps = 1
files = []
args = ARGV
i = 0
while i < args.size
  if args[i] == "-fuzz"
    fuzz = args[i + 1].to_i
    i += 2
  elsif args[i] == "-n"
    reps = args[i + 1].to_i
    i += 2
  else
    files.push(args[i])
    i += 1

nfail = 0
files.each ->(f)
  name = f.split("/").last
  ok = true
  begin
    es = flac_es_parse(File.read(f))
    cfg = es[:cfg]
    refp = f + ".s32"
    ref = nil
    ref = ft_u8(File.read(refp)) if File.exist?(refp)
    nref = 0
    nref = ref.size if ref != nil
    dec = acodec_new(cfg)
    r = i64[3]
    fmax = ~0.0
    off = 0
    bad = 0
    t0 = clock_ms()
    es[:samples].each ->(smp)
      blk = dec.decode(smp)
      if dec.last_frames == 0
        bad += 1
      if ref != nil
        shift = 32 - dec.bps
        ft_cmp(dec.last_ints, dec.last_stride, blk.channels, blk.frames, shift, ref, nref, off, r)
        e = ft_fcmp(blk.samples, blk.frames * blk.channels, ref, nref, off, blk.channels)
        fmax = e if e > fmax
      off += blk.frames
    ms = clock_ms() - t0
    k = 1
    while k < reps
      dec2 = acodec_new(cfg)
      es[:samples].each ->(smp)
        dec2.decode(smp)
      k += 1
    ms_all = clock_ms() - t0
    dur = off / (cfg.sample_rate * ~1.0)
    rtf = (ms_all / ~1000.0) / reps / dur
    refn = 0
    refn = nref / 4 / cfg.channels if ref != nil
    tag = "ok  "
    if ref == nil
      tag = "NREF"
    elsif r[0] != 0 || refn != off || bad != 0
      tag = "FAIL"
      nfail += 1
    if fuzz > 0
      fz = 0
      while fz < fuzz
        rr = ft_fuzz(cfg, es[:samples], 12345 + fz * 7919)
        << "  fuzz [fz]: decoded [rr[0]] raised [rr[1]]"
        fz += 1
    << "[tag] [name] [cfg.sample_rate]Hz ch=[cfg.channels] bps=[dec.bps] frames=[es[:samples].size] samples=[off] ref=[refn] mism=[r[0]] maxd=[r[1]] badframes=[bad] fmax=[fmax] rtf=[rtf]"
  rescue e
    << "FAIL [name] error: [e]"
    nfail += 1
<< "failures: [nfail] / [files.size]"
