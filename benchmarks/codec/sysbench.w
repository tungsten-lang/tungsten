# sysbench — core/codec's decoders against the operating system's (macOS:
# VideoToolbox, AudioToolbox, ImageIO) on the same files.
#
#   bin/tungsten -o /tmp/sysbench --release benchmarks/codec/sysbench.w
#   /tmp/sysbench video FILE ours|sys|sysdrop    one decoder: speed, CPU, memory
#   /tmp/sysbench audio FILE ours|sys
#   /tmp/sysbench image FILE ours|sys [N]        N decodes (default 5)
#   /tmp/sysbench cmpvideo FILE                  both decoders: PSNR per plane
#   /tmp/sysbench cmpaudio FILE                  both decoders: max |diff|, SNR
#   /tmp/sysbench cmpimage FILE                  both decoders: RGBA PSNR
#
# A speed run prints one line of key=value pairs:
#   frames / secs (media duration), wall (decode seconds, demux excluded),
#   fps or rtf (real-time factor), cpu (user + system seconds of this
#   process: VideoToolbox's hardware decoder runs out of process, so its CPU
#   time is mostly not counted), rss0 / rss (peak resident set before and
#   after decoding, MB), first (ms from creating the decoder to the first
#   frame / block).
# Run each speed measurement in its own process so the peak RSS is that
# decoder's. "sys" copies every frame out of the CVPixelBuffer into Y/Cb/Cr
# planes (the VideoFrame contract); "sysdrop" only decodes.
#
# Video and audio files are demuxed with core/codec's demuxers, and both
# decoders get the same samples. Nothing is played.

use core/codec
use core/codec/system
use core/canvas

-> sb_now
  ccall("w_media_sys_rusage")[3]

-> sb_ru
  ccall("w_media_sys_rusage")

-> sb_mb(b)
  sb_r(b / 1048576.0, 1)

-> sb_r(x, d)
  sb_f(x, d)

-> sb_db(x, d)
  return "inf" if x >= 999.0
  sb_f(x, d)

-> sb_f(x, d)
  m = 10 ** d
  v = (x * m).round
  sg = ""
  if v < 0
    sg = "-"
    v = 0 - v
  return sg + v.to_s if d == 0
  f = (v % m).to_s
  while f.size < d
    f = "0" + f
  sg + (v / m).to_s + "." + f

-> sb_demux(path)
  a = File.read_bytes(path)
  d = demux_for(a)
  raise "no demuxer for " + path if d == nil
  samples = {}
  d.append(a)
  d.parse
  guard = 0
  while d.want_offset != nil && guard < 16
    wo = d.want_offset
    d.restart(wo)
    d.append(dm_slice(a, wo, a.size - wo))
    d.parse
    guard += 1
  d.finish
  d.take.each ->(ts)
    samples[ts[0]] = [] if samples[ts[0]] == nil
    samples[ts[0]].push(ts[1])
  [d, samples]

-> sb_track(path, kind)
  r = sb_demux(path)
  d = r[0]
  t = nil
  d.tracks.each ->(tr)
    t = tr if t == nil && tr.kind == kind
  raise "no " + kind.to_s + " track in " + path if t == nil
  [t, r[1][t.id]]

# frames whose planes were allocated for them alone belong to the consumer
-> sb_release(f)
  if f.owned
    f.planes.each ->(p) ccall("w_value_free_w", p)
  0

-> sb_vdec(cfg, which)
  return SysVideoDec.new(cfg) if which == "sys" || which == "sysdrop"
  Codec.prefer_system([])
  Codec.video(cfg)

-> sb_adec(cfg, which)
  return SysAudioDec.new(cfg) if which == "sys"
  Codec.prefer_system([])
  Codec.audio(cfg)

# ---- speed ----

-> sb_video(path, which)
  ts = sb_track(path, :video)
  t = ts[0]
  samples = ts[1]
  r0 = sb_ru()
  t0 = r0[3]
  dec = sb_vdec(t.cfg, which)
  topen = sb_now() - t0
  drop = which == "sysdrop"
  first = -1.0
  n = 0
  samples.each ->(s)
    fs = drop ? (dec.decode_drop(s)) : dec.decode(s)
    if fs.size > 0 && first < 0.0
      first = sb_now() - t0
    n += fs.size
    if !drop
      fs.each ->(f) sb_release(f)
  fs = drop ? dec.flush_drop : dec.flush
  first = sb_now() - t0 if fs.size > 0 && first < 0.0
  n += fs.size
  if !drop
    fs.each ->(f) sb_release(f)
  r1 = sb_ru()
  wall = r1[3] - t0
  cpu = (r1[0] + r1[1]) - (r0[0] + r0[1])
  hw = ""
  hw = " hw=" + dec.hw?.to_s if which != "ours"
  << "video " + which + " " + File.basename(path) + " " + t.cfg.width.to_s + "x" + t.cfg.height.to_s + " frames=" + n.to_s + " wall=" + sb_r(wall, 3).to_s + " fps=" + sb_r(n / wall, 1).to_s + " cpu=" + sb_r(cpu, 2).to_s + " rss0=" + sb_mb(r0[2]).to_s + " rss=" + sb_mb(r1[2]).to_s + " first=" + sb_r(first * 1000.0, 1) + " open=" + sb_r(topen * 1000.0, 1) + hw

-> sb_audio(path, which)
  ts = sb_track(path, :audio)
  t = ts[0]
  samples = ts[1]
  r0 = sb_ru()
  t0 = r0[3]
  dec = sb_adec(t.cfg, which)
  topen = sb_now() - t0
  first = -1.0
  frames = 0
  rate = 0
  ch = 0
  samples.each ->(s)
    b = dec.decode(s)
    if b != nil
      first = sb_now() - t0 if first < 0.0
      frames += b.frames
      rate = b.sample_rate
      ch = b.channels
  b = dec.flush
  if b != nil
    frames += b.frames
  r1 = sb_ru()
  wall = r1[3] - t0
  cpu = (r1[0] + r1[1]) - (r0[0] + r0[1])
  secs = rate > 0 ? frames / (rate * 1.0) : 0.0
  << "audio " + which + " " + File.basename(path) + " " + t.cfg.codec + " " + rate.to_s + "Hz/" + ch.to_s + "ch frames=" + frames.to_s + " secs=" + sb_r(secs, 2).to_s + " wall=" + sb_r(wall, 4).to_s + " rtf=" + sb_r(secs / wall, 1).to_s + " cpu=" + sb_r(cpu, 3).to_s + " rss0=" + sb_mb(r0[2]).to_s + " rss=" + sb_mb(r1[2]).to_s + " first=" + sb_r(first * 1000.0, 2) + " open=" + sb_r(topen * 1000.0, 2).to_s

-> sb_image(path, which, reps)
  bytes = File.read_bytes(path)
  r0 = sb_ru()
  t0 = r0[3]
  first = -1.0
  w = 0
  h = 0
  i = 0
  while i < reps
    if which == "sys"
      img = Canvas.load_image_data(bytes)
      px = img.bytes
      w = img.width
      h = img.height
      img.release
    else
      bm = Image.decode(bytes)
      w = bm.width
      h = bm.height
    first = sb_now() - t0 if first < 0.0
    i += 1
  r1 = sb_ru()
  wall = r1[3] - t0
  cpu = (r1[0] + r1[1]) - (r0[0] + r0[1])
  mp = w * h / 1000000.0
  gpu = env("TUNGSTEN_CODEC_GPU") == "0" ? " gpu=off" : ""
  << "image " + which + " " + File.basename(path) + " " + w.to_s + "x" + h.to_s + " reps=" + reps.to_s + " ms=" + sb_r(wall * 1000.0 / reps, 1).to_s + " mpps=" + sb_r(mp * reps / wall, 1).to_s + " cpu_ms=" + sb_r(cpu * 1000.0 / reps, 1).to_s + " rss0=" + sb_mb(r0[2]).to_s + " rss=" + sb_mb(r1[2]).to_s + " first=" + sb_r(first * 1000.0, 1).to_s + gpu

# ---- correctness ----

# sum of squared differences over n samples of two planes (8- or 16-bit)
-> sb_sse8(a, b, n) (u8[] u8[] i64) i64
  s = 0 ## i64
  i = 0 ## i64
  while i < n
    d = (a[i] ## i64) - (b[i] ## i64)
    s += d * d
    i += 1
  s

-> sb_sse16(a, b, n) (u16[] u16[] i64) i64
  s = 0 ## i64
  i = 0 ## i64
  while i < n
    d = (a[i] ## i64) - (b[i] ## i64)
    s += d * d
    i += 1
  s

# copy a plane out of a (possibly strided) decoder-owned picture
-> sb_pack8(src, stride, w, h) (u8[] i64 i64 i64) u8[]
  o = u8[w * h]
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      o[y * w + x] = src[y * stride + x]
      x += 1
    y += 1
  o

-> sb_pack16(src, stride, w, h) (u16[] i64 i64 i64) u16[]
  o = u16[w * h]
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      o[y * w + x] = src[y * stride + x]
      x += 1
    y += 1
  o

-> sb_pack(f)
  cw = (f.width + 1) / 2
  ch = (f.height + 1) / 2
  dims = [[f.width, f.height], [cw, ch], [cw, ch]]
  out = []
  i = 0
  while i < 3
    if f.bit_depth > 8
      out.push(sb_pack16(f.planes[i], f.strides[i], dims[i][0], dims[i][1]))
    else
      out.push(sb_pack8(f.planes[i], f.strides[i], dims[i][0], dims[i][1]))
    i += 1
  [f.pts, out, f.bit_depth]

-> sb_psnr(sse, n, peak)
  return 999.0 if sse == 0
  mse = sse / (n * 1.0)
  10.0 * Math.log10(peak * peak / mse)

-> sb_cmpvideo(path)
  ts = sb_track(path, :video)
  t = ts[0]
  samples = ts[1]
  ours = sb_vdec(t.cfg, "ours")
  sys = SysVideoDec.new(t.cfg)
  qa = []
  qb = []
  sse = [0, 0, 0]
  cnt = [0, 0, 0]
  worst = 999.0
  frames = 0
  exact = 0
  pts_bad = 0
  cmp = ->()
    while qa.size > 0 && qb.size > 0
      a = qa.shift
      b = qb.shift
      pts_bad += 1 if (a[0] - b[0]).abs > 0.0015
      fsse = 0
      fn = 0
      peak = a[2] > 8 ? ((1 << a[2]) - 1) * 1.0 : 255.0
      i = 0
      while i < 3
        n = a[1][i].size
        n = b[1][i].size if b[1][i].size < n
        e = a[2] > 8 ? sb_sse16(a[1][i], b[1][i], n) : sb_sse8(a[1][i], b[1][i], n)
        sse[i] += e
        cnt[i] += n
        fsse += e
        fn += n
        i += 1
      a[1].each ->(pl) ccall("w_value_free_w", pl)
      b[1].each ->(pl) ccall("w_value_free_w", pl)
      p = sb_psnr(fsse, fn, peak)
      worst = p if p < worst
      exact += 1 if fsse == 0
      frames += 1
    0
  samples.each ->(s)
    ours.decode(s).each ->(f)
      qa.push(sb_pack(f))
      sb_release(f)
    sys.decode(s).each ->(f)
      qb.push([f.pts, f.planes, f.bit_depth])
    cmp.call
  ours.flush.each ->(f)
    qa.push(sb_pack(f))
    sb_release(f)
  sys.flush.each ->(f)
    qb.push([f.pts, f.planes, f.bit_depth])
  cmp.call
  peak = 255.0
  << "cmpvideo " + File.basename(path) + " frames=" + frames.to_s + " left_ours=" + qa.size.to_s + " left_sys=" + qb.size.to_s + " exact=" + exact.to_s + " psnr_y=" + sb_db(sb_psnr(sse[0], cnt[0], peak), 2) + " psnr_cb=" + sb_db(sb_psnr(sse[1], cnt[1], peak), 2) + " psnr_cr=" + sb_db(sb_psnr(sse[2], cnt[2], peak), 2) + " worst_frame=" + sb_db(worst, 2) + " pts_mismatch=" + pts_bad.to_s

# whole decoded stream as one f64[] (interleaved) + [rate, channels]
-> sb_decode_all(cfg, samples, which)
  dec = sb_adec(cfg, which)
  blocks = []
  total = 0
  rate = 0
  ch = 0
  samples.each ->(s)
    b = dec.decode(s)
    if b != nil
      blocks.push(b)
      total += b.frames * b.channels
      rate = b.sample_rate
      ch = b.channels
  b = dec.flush
  if b != nil
    blocks.push(b)
    total += b.frames * b.channels
  out = f64[total]
  o = 0
  j = 0
  while j < blocks.size
    b = blocks[j]
    n = b.frames * b.channels
    sb_put(out, o, b.samples, n)
    o += n
    j += 1
  [out, rate, ch]

-> sb_put(dst, o, src, n) (f64[] i64 f32[] i64) i64
  i = 0 ## i64
  while i < n
    dst[o + i] = src[i]
    i += 1
  n

# [max |a - b|, sum (a-b)^2, sum b^2, count] with b shifted by lag frames
-> sb_adiff(a, b, ch, lag, skip) (f64[] f64[] i64 i64 i64) f64[]
  sb_adiff_n(a, b, ch, lag, skip, a.size / ch)

-> sb_adiff_n(a, b, ch, lag, skip, lim) (f64[] f64[] i64 i64 i64 i64) f64[]
  r = f64[4]
  na = a.size / ch
  na = lim if lim < na
  nb = b.size / ch
  mx = 0.0
  e = 0.0
  p = 0.0
  c = 0.0
  i = skip
  while i < na && i + lag < nb && i + lag >= 0
    k = 0 ## i64
    while k < ch
      x = a[i * ch + k]
      y = b[(i + lag) * ch + k]
      d = (x - y).abs
      mx = d if d > mx
      e += (x - y) * (x - y)
      p += y * y
      c += 1.0
      k += 1
    i += 1
  r[0] = mx
  r[1] = e
  r[2] = p
  r[3] = c
  r

-> sb_cmpaudio(path)
  ts = sb_track(path, :audio)
  t = ts[0]
  samples = ts[1]
  a = sb_decode_all(t.cfg, samples, "ours")
  STDERR.puts("dbg ours done") if env("SB_DEBUG") == "1"
  b = sb_decode_all(t.cfg, samples, "sys")
  STDERR.puts("dbg sys done") if env("SB_DEBUG") == "1"
  if a[1] != b[1] || a[2] != b[2]
    << "cmpaudio " + File.basename(path) + " FORMAT ours=" + a[1].to_s + "/" + a[2].to_s + " sys=" + b[1].to_s + "/" + b[2].to_s
    return nil
  ch = a[2]
  best = nil
  bl = 0
  lag = -4096
  while lag <= 4096
    r = sb_adiff_n(a[0], b[0], ch, lag, 4096, 4096 + 96000)
    if r[3] > 0.0 && (best == nil || r[1] / r[3] < best[1] / best[3])
      best = r
      bl = lag
    lag += lag.abs < 64 ? 1 : 16
  # refine around the best coarse lag
  l2 = bl - 16
  while l2 <= bl + 16
    r = sb_adiff(a[0], b[0], ch, l2, 4096)
    if r[3] > 0.0 && r[1] / r[3] < best[1] / best[3]
      best = r
      bl = l2
    l2 += 1
  snr = best[1] == 0.0 ? 999.0 : 10.0 * Math.log10(best[2] / best[1])
  << "cmpaudio " + File.basename(path) + " " + a[1].to_s + "Hz/" + ch.to_s + "ch frames_ours=" + (a[0].size / ch).to_s + " frames_sys=" + (b[0].size / ch).to_s + " lag=" + bl.to_s + " maxdiff=" + best[0].to_s + " maxdiff_lsb16=" + sb_r(best[0] * 32768.0, 1).to_s + " snr_db=" + sb_db(snr, 1)

# a decoder's output against a reference file (WAV / anything core/codec
# demuxes, e.g. the conformance references), best lag within ±4096 frames;
# which: ours / sys. Compares the reference's length (references may be cut).
-> sb_cmpref(path, ref, which)
  ts = sb_track(path, :audio)
  a = sb_decode_all(ts[0].cfg, ts[1], which)
  rt = sb_track(ref, :audio)
  b = sb_decode_all(rt[0].cfg, rt[1], "ours")
  if a[2] != b[2]
    << "cmpref " + File.basename(path) + " " + which + " CHANNELS ours=" + a[2].to_s + " ref=" + b[2].to_s + " rate " + a[1].to_s + "/" + b[1].to_s
    return nil
  ch = a[2]
  best = nil
  bl = 0
  lag = -4096
  while lag <= 4096
    r = sb_adiff_n(b[0], a[0], ch, lag, 0, 48000)
    if r[3] > 0.0 && (best == nil || r[1] / r[3] < best[1] / best[3])
      best = r
      bl = lag
    lag += 1
  best = sb_adiff(b[0], a[0], ch, bl, 0)
  snr = best[1] == 0.0 ? 999.0 : 10.0 * Math.log10(best[2] / best[1])
  << "cmpref " + File.basename(path) + " " + which + " " + a[1].to_s + "Hz/" + ch.to_s + "ch ref_rate=" + b[1].to_s + " frames=" + (a[0].size / ch).to_s + " ref_frames=" + (b[0].size / ch).to_s + " lag=" + bl.to_s + " maxdiff=" + best[0].to_s + " maxdiff_lsb16=" + sb_r(best[0] * 32768.0, 1) + " snr_db=" + sb_db(snr, 1)

-> sb_cmpimage(path)
  bytes = File.read_bytes(path)
  bm = Image.decode(bytes)
  img = Canvas.load_image_data(bytes)
  px = img.bytes
  a = bm.rgba
  n = a.size
  n = px.size if px.size < n
  # RGB only (alpha is 255 in both)
  sse = sb_sse_rgb(a, px, n)
  cnt = n / 4 * 3
  mx = sb_maxd_rgb(a, px, n)
  << "cmpimage " + File.basename(path) + " ours=" + bm.width.to_s + "x" + bm.height.to_s + " sys=" + img.width.to_s + "x" + img.height.to_s + " space=" + img.space.to_s + " psnr_rgb=" + sb_db(sb_psnr(sse, cnt, 255.0), 2) + " maxdiff=" + mx.to_s

-> sb_sse_rgb(a, b, n) (u8[] u8[] i64) i64
  s = 0 ## i64
  i = 0 ## i64
  while i < n
    if (i & 3) != 3
      d = (a[i] ## i64) - (b[i] ## i64)
      s += d * d
    i += 1
  s

-> sb_maxd_rgb(a, b, n) (u8[] u8[] i64) i64
  m = 0 ## i64
  i = 0 ## i64
  while i < n
    if (i & 3) != 3
      d = ((a[i] ## i64) - (b[i] ## i64)).abs
      m = d if d > m
    i += 1
  m

# Every measurement of a directory of test media, each speed run in its own
# process (peak RSS per decoder); prints the lines as they come.
-> sb_suite(dir, reps)
  me = ARGV0[0]
  run = ->(args)
    << OS.capture(me + " " + args).strip
    0
  vids = ["h264_1080.mp4", "h264_4k.mp4", "hevc_1080.mp4", "hevc_4k.mp4"]
  vids.each ->(v)
    p = dir + "/" + v
    if File.exist?(p)
      ["ours", "sys", "sysdrop"].each ->(w)
        k = 0
        while k < reps
          run.call("video " + p + " " + w)
          k += 1
      run.call("cmpvideo " + p)
  ["still_1080.heic", "still_4k.heic"].each ->(v)
    p = dir + "/" + v
    if File.exist?(p)
      run.call("image " + p + " ours 5")
      run.call("image " + p + " sys 5")
      run.call("cmpimage " + p)
  ["aac_lc.m4a", "he1.m4a", "he2.m4a", "eac3_st.mp4", "eac3_51.mp4", "xhe.m4a"].each ->(v)
    p = dir + "/" + v
    if File.exist?(p)
      ["ours", "sys"].each ->(w)
        k = 0
        while k < reps
          run.call("audio " + p + " " + w)
          k += 1
      run.call("cmpaudio " + p)
  0

ARGV0 = [nil]
mode = ARGV[0]
path = ARGV[1]
if mode == "suite"
  ARGV0[0] = ARGV.size > 3 ? ARGV[3] : "sysbench"
  sb_suite(path, ARGV.size > 2 ? ARGV[2].to_i : 1)
elsif mode == "video"
  sb_video(path, ARGV[2])
elsif mode == "audio"
  sb_audio(path, ARGV[2])
elsif mode == "image"
  sb_image(path, ARGV[2], ARGV.size > 3 ? ARGV[3].to_i : 5)
elsif mode == "cmpvideo"
  sb_cmpvideo(path)
elsif mode == "cmpaudio"
  sb_cmpaudio(path)
elsif mode == "cmpref"
  sb_cmpref(path, ARGV[2], ARGV.size > 3 ? ARGV[3] : "ours")
elsif mode == "cmpimage"
  sb_cmpimage(path)
else
  << "usage: sysbench video|audio|image|cmpvideo|cmpaudio|cmpimage FILE [ours|sys|sysdrop]"
