# usac_test — the USAC (xHE-AAC) decoder against the ISO/IEC 23003-3
# conformance references.
#
#   bin/tungsten benchmarks/codec/usac_test.w -- REFDIR file.mp4 …
#
# For each bitstream, REFDIR/<name>.wav is the reference decoder's output
# (it may be cut short: only the reference's length is compared). The
# decoded signal is aligned to the reference (best lag within ±3072
# samples, found on the first second) and compared: max |diff| in 16-bit
# LSBs, SNR in dB, and the decoder's error count. Also --sys to decode with
# AudioToolbox (core/codec/system) instead, -n N to time N decodes.

use core/codec
use core/codec/system

-> ut_track(path)
  a = File.read_bytes(path)
  d = demux_for(a)
  raise "no demuxer" if d == nil
  d.append(a)
  d.parse
  g = 0
  while d.want_offset != nil && g < 16
    wo = d.want_offset
    d.restart(wo)
    d.append(dm_slice(a, wo, a.size - wo))
    d.parse
    g += 1
  d.finish
  t = nil
  trs = d.tracks
  i = 0
  while i < trs.size
    t = trs[i] if t == nil && trs[i].kind == :audio
    i += 1
  raise "no audio track" if t == nil
  ss = []
  tk = d.take
  i = 0
  while i < tk.size
    ss.push(tk[i][1]) if tk[i][0] == t.id
    i += 1
  [t, ss]

-> ut_put(dst, o, src, n) (f64[] i64 f32[] i64) i64
  i = 0
  while i < n
    dst[o + i] = src[i]
    i += 1
  n

-> ut_decode(dec, ss)
  blocks = []
  total = 0
  rate = 0
  ch = 0
  i = 0
  while i < ss.size
    b = dec.decode(ss[i])
    if b != nil
      blocks.push(b)
      total += b.frames * b.channels
      rate = b.sample_rate
      ch = b.channels
    i += 1
  out = f64[total]
  o = 0
  j = 0
  while j < blocks.size
    b = blocks[j]
    n = b.frames * b.channels
    ut_put(out, o, b.samples, n)
    o += n
    j += 1
  [out, rate, ch]

# [max |a - b|, sum d^2, sum b^2, n] of ref a[i] vs b[i + lag], i in [0, lim)
-> ut_diff(a, b, ch, lag, lim) (f64[] f64[] i64 i64 i64) f64[]
  r = f64[4]
  na = a.size / ch
  nb = b.size / ch
  na = lim if lim < na
  mx = 0.0
  e = 0.0
  p = 0.0
  c = 0.0
  i = 0
  while i < na
    if i + lag >= 0 && i + lag < nb
      k = 0
      while k < ch
        x = a[i * ch + k]
        y = b[(i + lag) * ch + k]
        d = (x - y).abs
        mx = d if d > mx
        e += (x - y) * (x - y)
        p += x * x
        c += 1.0
        k += 1
    i += 1
  r[0] = mx
  r[1] = e
  r[2] = p
  r[3] = c
  r

-> ut_diff_range(a, b, ch, lag, start, n) (f64[] f64[] i64 i64 i64 i64) f64[]
  r = f64[4]
  na = a.size / ch
  nb = b.size / ch
  mx = 0.0
  e = 0.0
  p = 0.0
  i = start
  while i < start + n && i < na
    if i + lag >= 0 && i + lag < nb
      k = 0
      while k < ch
        x = a[i * ch + k]
        y = b[(i + lag) * ch + k]
        d = (x - y).abs
        mx = d if d > mx
        e += (x - y) * (x - y)
        p += x * x
        k += 1
    i += 1
  r[0] = mx
  r[1] = e
  r[2] = p
  r

-> ut_f(x, d)
  m = 10 ** d
  v = (x * m).round
  s = v < 0 ? "-" : ""
  v = v.abs
  f = (v % m).to_s
  while f.size < d
    f = "0" + f
  s + (v / m).to_s + "." + f

refdir = ARGV[0]
sys = false
reps = 1
files = []
i = 1
while i < ARGV.size
  if ARGV[i] == "--sys"
    sys = true
  elsif ARGV[i] == "-n"
    i += 1
    reps = ARGV[i].to_i
  else
    files.push(ARGV[i])
  i += 1
pass = 0
fail = 0
fi0 = 0
while fi0 < files.size
  f = files[fi0]
  fi0 += 1
  name = File.basename(f).sub(".mp4", "")
  line = name
  begin
    ts = ut_track(f)
    t = ts[0]
    dec = nil
    t0 = Time.now
    r = nil
    k = 0
    while k < reps
      dec = sys ? SysAudioDec.new(t.cfg) : Codec.audio(t.cfg)
      r = ut_decode(dec, ts[1])
      k += 1
    ms = (Time.now - t0).to_s.to_i / 1000000 / reps
    errs = sys ? 0 : dec.errors
    rp = refdir + "/" + name + ".wav"
    if !File.exist?(rp)
      line += " decoded " + r[1].to_s + "Hz/" + r[2].to_s + "ch errors=" + errs.to_s + " (no reference)"
    else
      rt = ut_track(rp)
      ref = ut_decode(Codec.audio(rt[0].cfg), rt[1])
      ch = r[2]
      if ch != ref[2] || r[1] != ref[1]
        line += " FORMAT ours " + r[1].to_s + "/" + ch.to_s + " ref " + ref[1].to_s + "/" + ref[2].to_s + " errors=" + errs.to_s
        fail += 1
      else
        best = nil
        bl = 0
        lmax = env("UT_LAG") == nil ? 3072 : env("UT_LAG").to_i
        lag = 0 - lmax
        while lag <= lmax
          d = ut_diff(ref[0], r[0], ch, lag, 48000)
          if d[3] > 0.0 && (best == nil || d[1] / d[3] < best[1] / best[3])
            best = d
            bl = lag
          lag += 1
        d = ut_diff(ref[0], r[0], ch, bl, ref[0].size)
        if env("UT_FRAMES") != nil
          # per-frame SNR (1024-sample frames of the reference), first 12 bad ones
          fl = 1024
          nf = ref[0].size / ch / fl
          bad = 0
          fi = 0
          while fi < nf && bad < 12
            dd = ut_diff_range(ref[0], r[0], ch, bl, fi * fl, fl)
            fs = dd[1] == 0.0 ? 999.0 : 10.0 * Math.log10((dd[2] + 1.0e-30) / dd[1])
            if fs < 70.0
              << "  frame " + fi.to_s + " snr=" + ut_f(fs, 1) + " maxdiff_lsb=" + ut_f(dd[0] * 32768.0, 1)
              bad += 1
            fi += 1
        snr = d[1] == 0.0 ? 999.0 : 10.0 * Math.log10((d[2] + 1.0e-30) / d[1])
        lsb = d[0] * 32768.0
        ok = errs == 0 && (lsb <= 4.0 || snr >= 70.0)
        if ok
          pass += 1
        else
          fail += 1
        line = (ok ? "PASS " : "FAIL ") + line + " " + r[1].to_s + "Hz/" + ch.to_s + "ch lag=" + bl.to_s + " maxdiff_lsb=" + ut_f(lsb, 2) + " snr=" + ut_f(snr, 1) + " errors=" + errs.to_s + " ms=" + ms.to_s
  rescue e
    line = "FAIL " + line + " error: " + e.to_s
    fail += 1
  << line
<< pass.to_s + " passed, " + fail.to_s + " failed"
