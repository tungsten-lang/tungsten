# aac_test — test / benchmark tool for Blade's AAC decoder (core/codec/audio/aac).
#
#   bin/tungsten benchmarks/codec/aac_test.w -- [options] file.aac …
#
# Each ADTS file is split with aac_es_parse, decoded with AacDec and compared
# with FFmpeg's float decode (<file>.ref.f32, made with
#   ffmpeg -i file.aac -f f32le -c:a pcm_f32le file.ref.f32
# when missing; FFmpeg is only a test oracle). Prints channels / rate, max
# absolute error, SNR in dB and the real-time factor of the decode.
#
# Options:
#   -n N        decode N times (benchmark; use a --release build)
#   --asc HEX   override the AudioSpecificConfig (e.g. explicit SBR signalling)
#   --rewrap M  re-wrap the ADTS stream before parsing: "crc" (CRC-protected
#               headers), "multi" (two raw blocks per frame), "multicrc"
#   --corrupt   also run a robustness pass over randomly damaged packets
#   -o FILE     write the decoded output as f32le

use core/codec/audio/aac

-> at_u8(s)
  ccall("w_string_bytes_view", s) ## u8[]

# f32le bytes -> f64 values
-> at_f32le(b, out, n) (u8[] f64[] i64) i64
  i = 0
  while i < n
    v = b[i * 4] | (b[i * 4 + 1] << 8) | (b[i * 4 + 2] << 16) | (b[i * 4 + 3] << 24)
    e = (v >> 23) & 255
    m = v & 8388607
    x = ~0.0
    if e == 0
      x = (m ## f64) * Math.pow(~2.0, ~-149.0)
    elsif e < 255
      x = ((m | 8388608) ## f64) * Math.pow(~2.0, ((e - 150) ## f64))
    x = ~0.0 - x if (v >> 31) == 1
    out[i] = x
    i += 1
  0

# compare a (n values) with b shifted by off frames; returns [maxerr, sig, noise, count]
-> at_cmp(a, na, b, nb, off, nch, res) (f64[] i64 f64[] i64 i64 i64 f64[]) i64
  mx = ~0.0
  sig = ~0.0
  noi = ~0.0
  cnt = 0
  i = 0
  while i < na
    j = i + off * nch
    if j >= 0 && j < nb
      d = a[i] - b[j]
      d = ~0.0 - d if d < ~0.0
      mx = d if d > mx
      sig += b[j] * b[j]
      noi += d * d
      cnt += 1
    i += 1
  res[0] = mx
  res[1] = sig
  res[2] = noi
  res[3] = cnt ## f64
  0

-> at_append(dst, d, src, n) (f64[] i64 f32[] i64) i64
  i = 0
  while i < n
    dst[d + i] = src[i]
    i += 1
  0

-> at_to_f32le(src, n, out) (f64[] i64 u8[]) i64
  f = f32[1]
  i = 0
  while i < n
    x = src[i]
    v = 0
    if x != ~0.0
      s = 0
      if x < ~0.0
        s = 1
        x = ~0.0 - x
      e = 0
      while x >= ~2.0
        x = x * ~0.5
        e += 1
      while x < ~1.0
        x = x * ~2.0
        e -= 1
      m = ((x - ~1.0) * ~8388608.0 + ~0.5) ## i64
      if m >= 8388608
        m = 0
        e += 1
      if e + 127 <= 0
        v = s << 31
      else
        v = (s << 31) | ((e + 127) << 23) | m
    out[i * 4] = v & 255
    out[i * 4 + 1] = (v >> 8) & 255
    out[i * 4 + 2] = (v >> 16) & 255
    out[i * 4 + 3] = (v >> 24) & 255
    i += 1
  0

# max |x| of a block, or -1 if it holds NaN / Inf
-> at_scan(a, n) (f32[] i64) f64
  m = ~0.0
  i = 0
  while i < n
    x = a[i] ## f64
    if x != x || x > ~1.0e30 || x < ~-1.0e30
      return ~-1.0
    x = ~0.0 - x if x < ~0.0
    m = x if x > m
    i += 1
  m

-> at_hex(s)
  b = u8[s.size / 2]
  i = 0
  while i < b.size
    b[i] = s.slice(i * 2, 2).to_i(16)
    i += 1
  b

# Re-wrap an ADTS stream: mode "crc" = protection on, "multi" = 2 raw blocks
# per frame (no CRC), "multicrc" = 2 raw blocks with positions and CRCs.
-> at_rewrap(b, mode)
  frames = []
  p = 0
  n = b.size
  while p + 7 <= n
    if b[p] != 0xff || (b[p + 1] & 0xf6) != 0xf0
      p += 1
      next
    pa = b[p + 1] & 1
    flen = ((b[p + 3] & 3) << 11) | (b[p + 4] << 3) | ((b[p + 5] >> 5) & 7)
    hl = 7
    hl = 9 if pa == 0
    frames.push([b.slice(p, 7), b.slice(p + hl, flen - hl)])
    p += flen
  out = []
  i = 0
  while i < frames.size
    hdr = frames[i][0]
    if mode == "crc"
      pay = frames[i][1]
      tot = 9 + pay.size
      h = at_hdr(hdr, tot, 0, 0)
      out.push(h)
      out.push([0x12, 0x34])
      out.push(pay)
      i += 1
    else
      if i + 1 >= frames.size
        break
      p0 = frames[i][1]
      p1 = frames[i + 1][1]
      if mode == "multi"
        tot = 7 + p0.size + p1.size
        out.push(at_hdr(hdr, tot, 1, 1))
        out.push(p0)
        out.push(p1)
      else
        # positions (1 entry) + header crc, each block followed by a crc
        tot = 7 + 2 + 2 + p0.size + 2 + p1.size + 2
        out.push(at_hdr(hdr, tot, 1, 0))
        pos1 = p0.size + 2
        out.push([pos1 >> 8, pos1 & 255])
        out.push([0, 0])
        out.push(p0)
        out.push([0, 0])
        out.push(p1)
        out.push([0, 0])
      i += 2
  total = 0
  out.each ->(x) total += x.size
  r = u8[total]
  k = 0
  out.each ->(x)
    j = 0
    while j < x.size
      r[k] = x[j]
      k += 1
      j += 1
  r

-> at_hdr(h, flen, nblk_minus1, prot_absent)
  r = [h[0], (h[1] & 0xfe) | prot_absent, h[2], h[3], h[4], h[5], h[6]]
  r[3] = (h[3] & 0xfc) | ((flen >> 11) & 3)
  r[4] = (flen >> 3) & 255
  r[5] = ((flen & 7) << 5) | (h[5] & 31)
  r[6] = (h[6] & 0xfc) | nblk_minus1
  r

reps = 1
asc = nil
rewrap = nil
corrupt = false
outfile = nil
files = []
args = ARGV
i = 0
while i < args.size
  a = args[i]
  if a == "-n"
    reps = args[i + 1].to_i
    i += 2
  elsif a == "--asc"
    asc = at_hex(args[i + 1])
    i += 2
  elsif a == "--rewrap"
    rewrap = args[i + 1]
    i += 2
  elsif a == "-o"
    outfile = args[i + 1]
    i += 2
  elsif a == "--corrupt"
    corrupt = true
    i += 1
  else
    files.push(a)
    i += 1

files.each ->(f)
  name = f.split("/").last
  raw = at_u8(File.read(f))
  data = raw
  data = at_rewrap(raw, rewrap) if rewrap != nil
  es = aac_es_parse(data)
  cfg = es[:cfg]
  cfg.extra = asc if asc != nil
  samples = es[:samples]
  outs = []
  dec = nil
  t0 = clock_ms()
  r = 0
  while r < reps
    dec = AacDec.new(cfg)
    outs = []
    samples.each ->(s)
      blk = dec.decode(s)
      outs.push(blk) if blk != nil
    r += 1
  ms = (clock_ms() - t0) ## f64
  total = 0
  outs.each ->(b) total += b.frames * b.channels
  nch = 1
  rate = 1
  if outs.size > 0
    nch = outs[0].channels
    rate = outs[0].sample_rate
  mine = f64[total + 1]
  k = 0
  outs.each ->(b)
    at_append(mine, k, b.samples, b.frames * b.channels)
    k += b.frames * b.channels
  dur = ((total / nch) ## f64) / (rate ## f64)
  rtf = dur * (reps ## f64) * ~1000.0 / ms
  ref = f + ".ref.f32"
  if !File.exist?(ref)
    OS.capture("/opt/homebrew/bin/ffmpeg -nostdin -loglevel error -y -i '[f]' -f f32le -c:a pcm_f32le '[ref]'")
  rb = at_u8(File.read(ref))
  nr = rb.size / 4
  refv = f64[nr + 1]
  at_f32le(rb, refv, nr)
  res = f64[4]
  best = 0
  bsnr = ~-1000.0
  # alignment search (FFmpeg trims nothing for ADTS, so 0 is expected)
  cands = [0, -1024, 1024, -2048, 2048, -2112, 2112]
  cands.each ->(off)
    at_cmp(mine, total, refv, nr, off, nch, res)
    if res[2] > ~0.0 && res[1] > ~0.0
      snr = ~10.0 * Math.log10(res[1] / res[2])
    else
      snr = ~999.0
    if snr > bsnr
      bsnr = snr
      best = off
  at_cmp(mine, total, refv, nr, best, nch, res)
  snr = ~999.0
  snr = ~10.0 * Math.log10(res[1] / res[2]) if res[2] > ~0.0
  sr = (snr * ~100.0).round / ~100.0
  mx = res[0]
  << "[name]: [nch]ch [rate]Hz frames=[total / nch] ref=[nr / nch] off=[best] maxerr=[mx] SNR=[sr] dB  decode [ms.round] ms ([reps]x)  RTF=[(rtf * ~10.0).round / ~10.0]x  errors=[dec.errors] sbr=[dec.sbr_on] ps=[dec.ps_on]"
  st = dec.stats
  << "  band types: zero=[st[0]] spectral=[st[1] + st[2] + st[3] + st[4] + st[5] + st[6] + st[7] + st[8] + st[9] + st[10] + st[11]] esc=[st[11]] pns=[st[13]] is=[st[14] + st[15]]  windows: long=[st[16]] start=[st[17]] short=[st[18]] stop=[st[19]] tns=[st[20]] kbd=[st[21]] pulse=[st[22]]"
  if outfile != nil
    ob = u8[total * 4]
    at_to_f32le(mine, total, ob)
    File.write(outfile, ob)
  if corrupt
    rng = 12345
    t1 = clock_ms()
    nraise = 0
    nerr = 0
    nbad = 0
    peak = ~0.0
    pass = 0
    while pass < 5
      d2 = AacDec.new(cfg)
      samples.each ->(s)
        b = s.data
        c = u8[b.size]
        j = 0
        while j < b.size
          c[j] = b[j]
          j += 1
        if pass < 3
          nflip = 1 + pass * 4
          q = 0
          while q < nflip && c.size > 0
            rng = (rng * 1103515245 + 12345) & 2147483647
            c[rng % c.size] = (rng >> 8) & 255
            q += 1
        elsif pass == 3
          c = c.slice(0, c.size / 2) if c.size > 4
        else
          j = 0
          while j < c.size
            rng = (rng * 1103515245 + 12345) & 2147483647
            c[j] = (rng >> 16) & 255
            j += 1
        begin
          blk = d2.decode(MediaSample.new(c, s.pts, s.dts, s.duration, true))
          if blk != nil
            r2 = at_scan(blk.samples, blk.frames * blk.channels)
            nbad += 1 if r2 < ~0.0
            peak = r2 if r2 > peak
        rescue e
          nraise += 1
      nerr += d2.errors
      pass += 1
    d3 = AacDec.new(cfg)
    d3.decode(MediaSample.new(u8[0], ~0.0, ~0.0, ~0.0, true))
    nerr += d3.errors
    << "  corrupt: 5 passes x [samples.size] packets in [clock_ms() - t1] ms: raised=[nraise] frames-concealed=[nerr] non-finite-blocks=[nbad] peak=[peak]"
