# opus_test — test / benchmark tool for Blade's Opus decoder (core/codec/audio/opus).
#
#   bin/tungsten benchmarks/codec/opus_test.w -- tv DIR [-m] [-o OUTDIR]
#       RFC 8251 test vectors: decodes DIR/testvectorNN.bit (4-byte BE packet
#       length, 4-byte BE final range, packet), checks the final range of every
#       packet, compares with testvectorNN.dec (16-bit LE, 48 kHz stereo; -m:
#       mono and the NNm.dec references) and writes OUTDIR/NN.raw (s16le) for
#       opus_compare.
#   bin/tungsten benchmarks/codec/opus_test.w -- ogg FILE.opus [REF.f32] [-o OUT.f32]
#       Decodes an Ogg Opus file; with REF (ffmpeg -f f32le output, pre-skip
#       trimmed) prints max abs error and SNR after dropping pre-skip.
#   bin/tungsten benchmarks/codec/opus_test.w -- bench FILE.opus [REPEAT]
#       Decode speed: real-time factor (decode time / audio duration).

use core/codec/media
use core/codec/audio/opus

-> ot_be32(b, o)
  (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3]

# s16 LE reference -> f32 in [-1, 1)
-> ot_s16_to_f(b, n) (u8[] i64) f32[]
  r = f32[n]
  i = 0 ## i64
  while i < n
    v = b[2 * i] | (b[2 * i + 1] << 8)
    v -= 65536 if v >= 32768
    r[i] = ((v ## f32) * (~0.000030517578125 ## f32))
    i += 1
  r

-> ot_f32le(b, n) (u8[] i64) f32[]
  r = f32[n]
  i = 0 ## i64
  while i < n
    bits = b[4 * i] | (b[4 * i + 1] << 8) | (b[4 * i + 2] << 16) | (b[4 * i + 3] << 24)
    r[i] = ot_bits_f32(bits)
    i += 1
  r

-> ot_bits_f32(bits) (i64) f32
  sgn = (bits >> 31) & 1
  ex = (bits >> 23) & 255
  man = bits & 8388607
  v = ~0.0
  if ex == 0
    v = (man ## f64) * Math.exp(~-149.0 * ~0.6931471805599453)
  elsif ex == 255
    v = ~0.0
  else
    v = ((man + 8388608) ## f64) * Math.exp(((ex - 150) ## f64) * ~0.6931471805599453)
  v = ~0.0 - v if sgn == 1
  v ## f32

# error stats: out[0] max abs err, out[1] signal energy, out[2] noise energy
-> ot_cmp(a, ao, b, bo, n, out) (f32[] i64 f32[] i64 i64 f64[]) i64
  mx = ~0.0
  se = ~0.0
  ne = ~0.0
  i = 0 ## i64
  while i < n
    x = b[bo + i] ## f64
    d = (a[ao + i] ## f64) - x
    d2 = d
    d2 = ~0.0 - d if d < ~0.0
    mx = d2 if d2 > mx
    se = se + x * x
    ne = ne + d * d
    i += 1
  out[0] = mx
  out[1] = se
  out[2] = ne
  0

-> ot_to_s16(a, n) (f32[] i64) u8[]
  r = u8[2 * n]
  i = 0 ## i64
  while i < n
    v = a[i] * (~32768.0 ## f32)
    iv = 0 ## i64
    if v >= (~0.0 ## f32)
      iv = (v + (~0.5 ## f32)) ## i64
    else
      iv = (v - (~0.5 ## f32)) ## i64
    iv = 32767 if iv > 32767
    iv = -32768 if iv < -32768
    iv += 65536 if iv < 0
    r[2 * i] = iv & 255
    r[2 * i + 1] = iv >> 8
    i += 1
  r

-> ot_f32_bytes(a, n) (f32[] i64) u8[]
  r = u8[4 * n]
  i = 0 ## i64
  while i < n
    bits = ot_f32_bits(a[i])
    r[4 * i] = bits & 255
    r[4 * i + 1] = (bits >> 8) & 255
    r[4 * i + 2] = (bits >> 16) & 255
    r[4 * i + 3] = (bits >> 24) & 255
    i += 1
  r

-> ot_f32_bits(f) (f32) i64
  v = f ## f64
  return 0 if v == ~0.0
  sgn = 0 ## i64
  if v < ~0.0
    sgn = 1
    v = ~0.0 - v
  ex = 0 ## i64
  while v >= ~2.0
    v = v / ~2.0
    ex += 1
  while v < ~1.0
    v = v * ~2.0
    ex -= 1
  man = ((v - ~1.0) * ~8388608.0 + ~0.5) ## i64
  if man >= 8388608
    man = 0
    ex += 1
  (sgn << 31) | ((ex + 127) << 23) | man

-> ot_snr(se, ne)
  return ~999.0 if ne <= ~0.0
  return ~0.0 if se <= ~0.0
  ~10.0 * Math.log10(se / ne)

-> ot_join(blocks, cc)
  total = 0
  blocks.each ->(b)
    total += b.frames
  r = f32[total * cc]
  o = 0
  blocks.each ->(b)
    ot_copyf(r, o, b.samples, b.frames * cc)
    o += b.frames * cc
  [r, total]

-> ot_copyf(d, o, s, n) (f32[] i64 f32[] i64) i64
  i = 0 ## i64
  while i < n
    d[o + i] = s[i]
    i += 1
  0

# ---------------------------------------------------------------- test vectors

-> ot_testvector(dir, name, mono, outdir)
  bit = File.read_bytes(dir + "/" + name + ".bit")
  refp = dir + "/" + name + (mono ? "m" : "") + ".dec"
  cc = mono ? 1 : 2
  cfg = CodecConfig.new("opus", nil)
  cfg.channels = cc
  dec = OpusDec.new(cfg)
  dec.soft_clip_on = true
  blocks = []
  off = 0
  npk = 0
  bad_rng = 0
  first_bad = -1
  t0 = clock_ms()
  err = nil
  while off + 8 <= bit.size
    len = ot_be32(bit, off)
    rng = ot_be32(bit, off + 4)
    off += 8
    break if off + len > bit.size
    pk = u8[len < 1 ? 1 : len]
    i = 0
    while i < len
      pk[i] = bit[off + i]
      i += 1
    off += len
    s = MediaSample.new(len == 0 ? nil : pk, ~0.0, ~0.0, ~0.0, true)
    begin
      blk = dec.decode(s)
      blocks.push(blk)
    rescue e
      err = e.to_s if err == nil
    got = 0
    got = dec.last_ranges[0] if dec.last_ranges.size > 0
    if len > 0 && got != rng
      bad_rng += 1
      first_bad = npk if first_bad < 0
    npk += 1
  ms = clock_ms() - t0
  j = ot_join(blocks, cc)
  pcm = j[0]
  n = j[1]
  ref_b = File.read_bytes(refp)
  rn = ref_b.size / 2
  ref = ot_s16_to_f(ref_b, rn)
  m = [rn, n * cc].min
  st = f64[3]
  ot_cmp(pcm, 0, ref, 0, m, st)
  if outdir != nil
    File.write_bytes(outdir + "/" + name + (mono ? "m" : "") + ".raw", ot_to_s16(pcm, n * cc))
  e = (err == nil) ? "" : " ERROR: " + err
  << "[name][mono ? "m" : ""]: packets [npk] range_mismatch [bad_rng] (first [first_bad]) samples [n] ref [rn / cc] maxerr [(st[0] * ~32768.0).round(1)] lsb SNR [ot_snr(st[1], st[2]).round(2)] dB [ms] ms[e]"

# ---------------------------------------------------------------- Ogg

# Returns array of packets (u8[]) from an Ogg stream (first logical stream).
-> ot_ogg_packets(b)
  pkts = []
  cur = []
  off = 0
  serial = -1
  while off + 27 <= b.size
    raise "bad ogg capture" if b[off] != 79 || b[off + 1] != 103 || b[off + 2] != 103 || b[off + 3] != 83
    ser = b[off + 14] | (b[off + 15] << 8) | (b[off + 16] << 16) | (b[off + 17] << 24)
    nseg = b[off + 26]
    lacing = off + 27
    p = lacing + nseg
    serial = ser if serial < 0
    i = 0
    while i < nseg
      l = b[lacing + i]
      if ser == serial
        j = 0
        while j < l
          cur.push(b[p + j])
          j += 1
        if l < 255
          a = u8[cur.size]
          k = 0
          while k < cur.size
            a[k] = cur[k]
            k += 1
          pkts.push(a)
          cur = []
      p += l
      i += 1
    off = p
  pkts

-> ot_decode_ogg(path)
  b = File.read_bytes(path)
  pkts = ot_ogg_packets(b)
  head = pkts[0]
  cfg = CodecConfig.new("opus", head)
  dec = OpusDec.new(cfg)
  blocks = []
  i = 2
  t0 = clock_ms()
  while i < pkts.size
    s = MediaSample.new(pkts[i], ~0.0, ~0.0, ~0.0, true)
    blocks.push(dec.decode(s))
    i += 1
  ms = clock_ms() - t0
  j = ot_join(blocks, dec.channels)
  [j[0], j[1], dec, ms]

-> ot_ogg(args)
  path = args[1]
  ref = nil
  outp = nil
  i = 2
  while i < args.size
    if args[i] == "-o"
      outp = args[i + 1]
      i += 2
    else
      ref = args[i]
      i += 1
  r = ot_decode_ogg(path)
  pcm = r[0]
  n = r[1]
  dec = r[2]
  cc = dec.channels
  skip = dec.pre_skip
  name = path.split("/").last
  line = "[name]: ch [cc] streams [dec.streams.size] pre_skip [skip] frames [n] ([(((n - skip) ## f64) / ~48000.0).round(2)] s) decode [r[3]] ms"
  if outp != nil
    File.write_bytes(outp, ot_f32_bytes(pcm, n * cc))
  if ref != nil
    rb = File.read_bytes(ref)
    rn = rb.size / 4
    rf = ot_f32le(rb, rn)
    m = [rn, (n - skip) * cc].min
    st = f64[3]
    ot_cmp(pcm, skip * cc, rf, 0, m, st)
    line += " | vs ref ([rn / cc] frames): maxerr [st[0].round(6)] SNR [ot_snr(st[1], st[2]).round(2)] dB"
  << line

-> ot_bench(args)
  path = args[1]
  rep = 1
  rep = args[2].to_i if args.size > 2
  b = File.read_bytes(path)
  pkts = ot_ogg_packets(b)
  cfg = CodecConfig.new("opus", pkts[0])
  frames = 0
  t0 = clock_ms()
  k = 0
  while k < rep
    dec = OpusDec.new(cfg)
    i = 2
    while i < pkts.size
      blk = dec.decode(MediaSample.new(pkts[i], ~0.0, ~0.0, ~0.0, true))
      frames += blk.frames
      i += 1
    k += 1
  ms = clock_ms() - t0
  dur = (frames ## f64) / ~48000.0
  << "[path.split("/").last]: [dur.round(2)] s audio decoded in [ms] ms -> RTF [((ms ## f64) / ~1000.0 / dur).round(4)] ([(dur * ~1000.0 / (ms ## f64)).round(1)]x realtime)"

# Robustness: decodes every packet of an Ogg file / test vector with random
# corruption (bit flips, truncation, random bytes); must not crash or hang.
-> ot_fuzz(args)
  path = args[1]
  rounds = 3
  rounds = args[2].to_i if args.size > 2
  pkts = nil
  head = nil
  if path.ends_with?(".bit")
    b = File.read_bytes(path)
    pkts = []
    off = 0
    while off + 8 <= b.size
      len = ot_be32(b, off)
      off += 8
      break if off + len > b.size
      a = u8[len < 1 ? 1 : len]
      i = 0
      while i < len
        a[i] = b[off + i]
        i += 1
      pkts.push(a) if len > 0
      off += len
  else
    all = ot_ogg_packets(File.read_bytes(path))
    head = all[0]
    pkts = all.slice(2, all.size - 2)
  seed = 12345
  msgs = {}
  errors = 0
  ok = 0
  r = 0
  while r < rounds
    cfg = CodecConfig.new("opus", head)
    cfg.channels = 2
    dec = OpusDec.new(cfg)
    pkts.each ->(pk)
      n = pk.size
      seed = (seed * 1103515245 + 12345) % 2147483648
      mode = seed % 4
      q = nil
      if mode == 0
        q = u8[n]
        i = 0
        while i < n
          q[i] = pk[i]
          i += 1
        k = 0
        while k < 1 + (seed >> 8) % 8
          seed = (seed * 1103515245 + 12345) % 2147483648
          bi = seed % (n * 8)
          q[bi >> 3] = q[bi >> 3] ^ (1 << (bi & 7))
          k += 1
      elsif mode == 1
        m = (seed >> 4) % n + 1
        q = u8[m]
        i = 0
        while i < m
          q[i] = pk[i]
          i += 1
      elsif mode == 2
        m = (seed >> 4) % 1300 + 1
        q = u8[m]
        i = 0
        while i < m
          seed = (seed * 1103515245 + 12345) % 2147483648
          q[i] = (seed >> 16) & 255
          i += 1
        q[0] = pk[0] if (seed & 1) == 0
      else
        q = pk
      e0 = dec.errors
      begin
        dec.decode(MediaSample.new(q, ~0.0, ~0.0, ~0.02, true))
      rescue e
        msg = "RAISED: " + e.to_s
        msgs[msg] = (msgs.has_key?(msg) ? msgs[msg] : 0) + 1
      if dec.errors != e0
        errors += 1
        msg = dec.last_error
        msgs[msg] = (msgs.has_key?(msg) ? msgs[msg] : 0) + 1
      else
        ok += 1
    r += 1
  msgs.keys.each ->(k)
    << "  [msgs[k]] x [k]"
  << "[path.split("/").last]: fuzz rounds [rounds]: [ok] decoded, [errors] rejected and concealed, no crash"

args = ARGV
if args.size == 0
  << "usage: opus_test tv DIR \[-m] \[-o OUTDIR] | ogg FILE \[REF.f32] \[-o OUT.f32] | bench FILE \[REPEAT]"
elsif args[0] == "tv"
  dir = args[1]
  mono = false
  outdir = nil
  only = nil
  i = 2
  while i < args.size
    if args[i] == "-m"
      mono = true
      i += 1
    elsif args[i] == "-o"
      outdir = args[i + 1]
      i += 2
    else
      only = args[i]
      i += 1
  Dir.mkdir_p(outdir) if outdir != nil
  k = 1
  while k <= 12
    name = "testvector" + (k < 10 ? "0" : "") + k.to_s
    ot_testvector(dir, name, mono, outdir) if only == nil || only == name
    k += 1
elsif args[0] == "ogg"
  ot_ogg(args)
elsif args[0] == "bench"
  ot_bench(args)
elsif args[0] == "fuzz"
  ot_fuzz(args)
