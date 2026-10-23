# benchmarks/media/scale_bench.w — Scaler backends (Metal, vImage, CPU) on
# real frames, and raw RGBA dumps for comparing against ffmpeg's swscale.
#
#   bin/tungsten -o /tmp/scale_bench --release benchmarks/media/scale_bench.w
#   /tmp/scale_bench MASTER.mp4 START_FRAME COUNT [DUMP_DIR]
#
# Decodes COUNT frames (RGBA) from START_FRAME, then for each job (share
# 1280x720, 4K 3840x2160, 480p, vertical cover 1080x1920 and contain) and
# filter (lanczos3, bicubic) times every backend over the frames (median of
# three passes, ms per frame) and reports each backend's largest and RMS
# difference from the CPU backend. With DUMP_DIR it also writes
# DUMP_DIR/src_<k>.rgba (the decoded 1920x1080 frames) and
# DUMP_DIR/<job>_<filter>_<k>.rgba (the CPU backend's output), for
# benchmarks/media/scale_vs_ffmpeg.sh to score against ffmpeg's scale filter
# on the same RGBA input.

args = argv()
if args.size < 3
  << "usage: scale_bench MASTER START COUNT [DUMP_DIR]"
  exit(2)
src = args[0]
start = args[1].to_i
count = args[2].to_i
dump = args.size > 3 ? args[3] : nil

dec = VideoDecoder.new(src, start: start)
W = dec.width
H = dec.height
frames = []
while frames.size < count
  b = u8[W * H * 4]
  if dec.read(b) == nil
    break
  frames << b
dec.close
<< "decoded [frames.size] frames [W]x[H] from frame [start]"
if dump != nil
  Dir.mkdir_p(dump)
  k = 0
  while k < frames.size
    File.write_bytes(dump + "/src_[k].rgba", frames[k])
    k += 1

-> diffstat(a, b, n) (u8[] u8[] i64) f64
  m = 0
  s = ~0.0
  i = 0
  while i < n
    d = a[i] - b[i]
    d = 0 - d if d < 0
    m = d if d > m
    x = d ## f64
    s = s + x * x
    i += 1
  (m ## f64) * ~1000000.0 + Math.sqrt(s / (n ## f64))

jobs = [["share", 1280, 720, "stretch"], ["4k", 3840, 2160, "stretch"], ["480p", 854, 480, "stretch"],
        ["vertical", 1080, 1920, "cover"], ["vertical_pad", 1080, 1920, "contain"]]
backends = Scaler.backends
<< "backends: [backends], default [ccall("w_media_scaler_info", nil, "default")]"
<< "job\tfilter\tbackend\tms_per_frame\tmax_diff_vs_cpu\trms_vs_cpu"
jobs.each ->(j)
  name = j[0]
  dw = j[1]
  dh = j[2]
  ref = []
  outs = []
  frames.each ->(f)
    ref << u8[dw * dh * 4]
    outs << u8[dw * dh * 4]
  ["lanczos3", "bicubic"].each ->(filter)
    ["cpu", "metal", "vimage"].each ->(b)
      ok = backends.include?(b)
      sc = nil
      if ok
        begin
          sc = Scaler.new(W, H, dw, dh, filter: filter, fit: j[3], backend: b)
        rescue e
          ok = false
      if ok
        dst = b == "cpu" ? ref : outs
        times = []
        pass = 0
        while pass < 3
          t0 = clock()
          k = 0
          while k < frames.size
            sc.scale(frames[k], dst[k])
            k += 1
          times << (clock() - t0) * ~1000.0 / frames.size.to_f
          pass += 1
        times = times.sort
        ms = (times[1] * ~1000.0).round.to_f / ~1000.0
        if b == "cpu"
          << "[name]\t[filter]\t[b]\t[ms]\t0\t0"
          if dump != nil
            k = 0
            while k < ref.size
              File.write_bytes(dump + "/[name]_[filter]_[k].rgba", ref[k])
              k += 1
        else
          mx = 0
          rs = ~0.0
          k = 0
          while k < outs.size
            d = diffstat(outs[k], ref[k], dw * dh * 4)
            m = (d / ~1000000.0).floor.to_i
            r = d - m.to_f * ~1000000.0
            mx = m if m > mx
            rs = r if r > rs
            k += 1
          << "[name]\t[filter]\t[b]\t[ms]\t[mx]\t[(rs * ~1000.0).round.to_f / ~1000.0]"
        sc.free
      else
        << "[name]\t[filter]\t[b]\tn/a\t-\t-"
