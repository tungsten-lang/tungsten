# spec: compiled -- media scales, decodes and transcodes through runtime/media (VideoToolbox/AVFoundation/Metal), linked only into compiled programs
# spec: interpreter-rejects -- media is compiled-only
# Chapters, scaling, decoding and transcoding in the media core
# (core/media/{mux,scaler,transcode}.w, runtime/media).
#
# Checks: chapter tracks in MP4 and MOV (UTF-8 titles, exact frame starts, a
# first chapter after frame 0, Nero chpl in MP4), MediaVerify catching a
# wrong chapter, Mux.chapterize on an existing file; the scaler's weights,
# identity, constant and phase behaviour, downscale low-pass, premultiplied
# and straight alpha, crops and fits, a hand-computed Lanczos-3 pixel, and
# Metal / vImage / CPU agreement; VideoEncoder source: scaling; the
# decoder's frame order and count for movies and segments; transcodes on the
# Y'CbCr and RGB paths with audio passthrough and re-encode, a range,
# segments + WAV, presets with codec/level checks, all passing every
# MediaVerify check including the flash/click sync test.
#
# Run:
#   bin/tungsten spec/core/media_transcode_spec.w

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

if !VideoEncoder.available?
  msg = nil
  begin
    Scaler.new(64, 64, 32, 32)
  rescue e
    msg = e.to_s
  check("stub raises a clear error", msg != nil && msg.index("needs macOS") != nil)
  << "ALL PASS media_transcode_spec ([passed.load()] checks, stub build)"
  exit(0)

TMP = "/tmp/tungsten_media_transcode_spec_" + OS.capture("echo $PPID").strip()
Dir.mkdir_p(TMP)

-> passes(r)
  if !r[:ok]
    << MediaVerify.format(r)
  r[:ok]

# ---- chapters ----
chaps = [["Opening", 0], ["Second — π and Wolfenbüttel", 30], ["Third \"quoted\"", 151], ["Last", 200]]
t = MediaVerify.sync_test(TMP + "/ch.mp4", seconds: 10, chapters: chaps, tc_start: "01:00:00:00", codec: "hevc")
r = MediaVerify.check(TMP + "/ch.mp4", chapters: chaps, tc_start: "01:00:00:00", sync: true, flashes: t[:flashes])
check("MP4 chapter track: 4 UTF-8 titles at exact frames, chpl agrees, every other check passes", passes(r))
f = r[:facts]
check("one disabled text track, chapters referenced through 'chap'", f[:text_tracks] == 1 && f[:chapters].size == 4)
check("chpl starts in 100 ns units", f[:chpl] != nil && f[:chpl][1][1] == 12500000 && f[:chpl][2][1] == 62916667)
bad = MediaVerify.check(TMP + "/ch.mp4", chapters: [["Opening", 0], ["Second — π and Wolfenbüttel", 31], ["Third \"quoted\"", 151], ["Last", 200]],
                        tc_start: "01:00:00:00")
chk = nil
bad[:checks].each ->(c)
  chk = c if c[:name] == "chapters"
check("a chapter one frame off fails the chapters check", !bad[:ok] && chk != nil && !chk[:ok])
bad2 = MediaVerify.check(TMP + "/ch.mp4", chapters: [["Opening", 0], ["Second", 30], ["Third \"quoted\"", 151], ["Last", 200]], tc_start: "01:00:00:00")
check("a wrong title fails the chapters check", !bad2[:ok])

late = [["Late start", 12], ["Two", 100]]
MediaVerify.sync_test(TMP + "/ch.mov", seconds: 8, chapters: late, tc_start: nil)
r = MediaVerify.check(TMP + "/ch.mov", chapters: late, tc_start: nil)
check("MOV (PCM, no timecode): chapter track with a first chapter after frame 0 (empty edit)", passes(r))

msg = nil
begin
  m = Mux.new(TMP + "/x.mp4", rate: [24, 1])
  m.chapter("b", 10)
  m.chapter("a", 5)
rescue e
  msg = e.to_s
check("chapters must ascend", msg != nil && msg.index("not after") != nil)

MediaVerify.sync_test(TMP + "/plain.mp4", seconds: 4)
n = Mux.chapterize(TMP + "/plain.mp4", TMP + "/plain_ch.mp4", [["Intro", 0], ["Middle", 48]])
r = MediaVerify.check(TMP + "/plain_ch.mp4", chapters: [["Intro", 0], ["Middle", 48]])
check("Mux.chapterize adds a chapter track to an existing MP4 without re-encoding", n == 2 && passes(r) &&
      r[:facts][:video_bytes] == MediaVerify.facts(TMP + "/plain.mp4", true, false)[:video_bytes])
msg = nil
begin
  Mux.chapterize(TMP + "/plain_ch.mp4", TMP + "/again.mp4", [["X", 0]])
rescue e
  msg = e.to_s
check("Mux.chapterize refuses a file that already has chapters", msg != nil && msg.index("already has") != nil)

# ---- scaler ----
-> ramp(w, h) (i64 i64) u8[]
  px = u8[w * h * 4]
  y = 0
  while y < h
    x = 0
    while x < w
      o = (y * w + x) * 4
      px[o] = (x * 255) / (w - 1)
      px[o + 1] = (y * 255) / (h - 1)
      px[o + 2] = ((x * 7 + y * 13) % 251)
      px[o + 3] = 255
      x += 1
    y += 1
  px

-> fill(w, h, r, g, b, a) (i64 i64 i64 i64 i64 i64) u8[]
  px = u8[w * h * 4]
  i = 0
  while i < w * h
    px[i * 4] = r
    px[i * 4 + 1] = g
    px[i * 4 + 2] = b
    px[i * 4 + 3] = a
    i += 1
  px

-> maxdiff(a, b, n) (u8[] u8[] i64) i64
  m = 0
  i = 0
  while i < n
    d = a[i] - b[i]
    d = 0 - d if d < 0
    m = d if d > m
    i += 1
  m

-> rms(a, b, n) (u8[] u8[] i64) f64
  s = ~0.0
  i = 0
  while i < n
    d = (a[i] - b[i]) ## f64
    s = s + d * d
    i += 1
  Math.sqrt(s / (n ## f64))

backends = Scaler.backends
check("Scaler backends: cpu always, metal and vimage on this Mac", backends.include?("cpu") && backends.include?("metal") && backends.include?("vimage"))

["lanczos3", "bicubic", "bilinear"].each ->(fl)
  sc = Scaler.new(96, 54, 37, 20, filter: fl, backend: :cpu)
  ok = true
  sc.weights(:x).each ->(row)
    s = ~0.0
    k = 1
    while k < row.size
      s = s + row[k]
      k += 1
    ok = false if (s - ~1.0).abs > ~0.000001
  sc.free
  check("[fl] weights sum to 1 on every output column", ok)

src = ramp(64, 36)
same = Scaler.new(64, 36, 64, 36, backend: :cpu).scale(src)
check("same size, Lanczos-3: an exact copy", maxdiff(same, src, 64 * 36 * 4) == 0)
same = Scaler.new(64, 36, 64, 36, filter: :bicubic, backend: :metal).scale(src)
check("same size, bicubic on Metal: an exact copy", maxdiff(same, src, 64 * 36 * 4) == 0)
flat = fill(40, 30, 200, 100, 50, 255)
up = Scaler.new(40, 30, 160, 90, backend: :cpu).scale(flat)
check("a flat picture stays flat when upscaled (no ringing at the edges)", maxdiff(up, fill(160, 90, 200, 100, 50, 255), 160 * 90 * 4) == 0)

# 2x upscale is phase-correct: pixel 2i and 2i+1 straddle source pixel i, so a horizontal ramp stays symmetric
ramp1 = u8[64 * 1 * 4]
i = 0
while i < 64
  ramp1[i * 4] = i * 4
  ramp1[i * 4 + 1] = i * 4
  ramp1[i * 4 + 2] = i * 4
  ramp1[i * 4 + 3] = 255
  i += 1
up2 = Scaler.new(64, 1, 128, 1, filter: :bilinear, backend: :cpu).scale(ramp1)
check("2x bilinear upscale samples at x/2 - 0.25 (pixel 21 of 128 = 0.75 x 40 + 0.25 x 44 = 41)", up2[21 * 4] == 41 && up2[20 * 4] == 39)

# downscaling widens the kernel: a 1-pixel checkerboard averages to grey instead of aliasing
cb = u8[90 * 90 * 4]
y = 0
while y < 90
  x = 0
  while x < 90
    v = (x + y) % 2 == 0 ? 255 : 0
    o = (y * 90 + x) * 4
    cb[o] = v
    cb[o + 1] = v
    cb[o + 2] = v
    cb[o + 3] = 255
    x += 1
  y += 1
small = Scaler.new(90, 90, 30, 30, backend: :cpu).scale(cb)
lo = 255
hi = 0
y = 3
while y < 27
  x = 3
  while x < 27
    v = small[(y * 30 + x) * 4]
    lo = v if v < lo
    hi = v if v > hi
    x += 1
  y += 1
check("3x downscale of a 1-pixel checkerboard is flat grey (low-pass, no aliasing): [lo]..[hi]", lo >= 120 && hi <= 135)

# a hand-computed Lanczos-3 pixel: 64 -> 40 columns, column 17
-> lanczos(t) (f64) f64
  a = t < ~0.0 ? ~0.0 - t : t
  if a < ~0.000000001
    return ~1.0
  if a >= ~3.0
    return ~0.0
  pt = ~3.141592653589793 * a
  ~3.0 * Math.sin(pt) * Math.sin(pt / ~3.0) / (pt * pt)
row = u8[64 * 4]
i = 0
while i < 64
  v = (i * 37 + 11) % 256
  row[i * 4] = v
  row[i * 4 + 1] = v
  row[i * 4 + 2] = v
  row[i * 4 + 3] = 255
  i += 1
out = Scaler.new(64, 1, 40, 1, backend: :cpu).scale(row)
sc = ~64.0 / ~40.0
xc = (~17.0 + ~0.5) * sc - ~0.5
s = ~0.0
wsum = ~0.0
k = (xc - ~3.0 * sc).floor.to_i
while k <= (xc + ~3.0 * sc).ceil.to_i
  wt = lanczos((k.to_f - xc) / sc)
  kk = k < 0 ? 0 : (k > 63 ? 63 : k)
  s = s + wt * row[kk * 4].to_f
  wsum = wsum + wt
  k += 1
want = (s / wsum).round.to_i
want = 0 if want < 0
want = 255 if want > 255
check("a Lanczos-3 pixel matches a hand computation (64 -> 40, column 17: [want])", out[17 * 4] == want)

# premultiplied alpha: colours never exceed alpha after ringing; straight alpha does not bleed
edge = u8[32 * 8 * 4]
y = 0
while y < 8
  x = 0
  while x < 32
    o = (y * 32 + x) * 4
    if x < 16
      edge[o] = 255
      edge[o + 3] = 255
    else
      edge[o + 1] = 200
      edge[o + 3] = 0
    x += 1
  y += 1
pm = Scaler.new(32, 8, 75, 19, backend: :cpu).scale(edge)
okpm = true
i = 0
while i < 75 * 19
  okpm = false if pm[i * 4] > pm[i * 4 + 3] || pm[i * 4 + 1] > pm[i * 4 + 3]
  i += 1
check("premultiplied: every colour <= its alpha after a Lanczos upscale", okpm)
st = Scaler.new(32, 8, 75, 19, alpha: :straight, backend: :cpu).scale(edge)
okst = true
x = 30
while x < 45
  o = (9 * 75 + x) * 4
  okst = false if st[o + 3] > 0 && st[o + 1] > 2
  x += 1
check("straight alpha: the transparent green does not bleed into the red edge", okst)

# crops and fits
f1 = Scaler.fit(1920, 1080, 1080, 1920, :contain)
check("fit contain 1920x1080 -> 1080x1920: [f1[:rect]]", f1[:rect] == [0, 656, 1080, 608])
f2 = Scaler.fit(1920, 1080, 1080, 1920, :cover)
check("fit cover 1920x1080 -> 1080x1920: centre 607.5 x 1080 crop", f2[:crop][2] == ~607.5 && f2[:crop][0] == ~656.25 && f2[:rect] == [0, 0, 1080, 1920])
big = ramp(64, 36)
half = Scaler.new(64, 36, 32, 36, crop: [32, 0, 32, 36], backend: :cpu).scale(big)
okc = true
y = 0
while y < 36
  x = 0
  while x < 32
    okc = false if half[(y * 32 + x) * 4] != big[(y * 64 + x + 32) * 4]
    x += 1
  y += 1
check("a whole-pixel crop at the same scale copies the region exactly", okc)
pad = Scaler.new(64, 36, 64, 64, fit: :contain, fill: [10, 20, 30, 255], backend: :metal).scale(big)
check("contain pads with the fill colour", pad[0] == 10 && pad[1] == 20 && pad[2] == 30 && pad[(63 * 64) * 4] == 10 && pad[(32 * 64 + 5) * 4] != 10)

# backends agree
img = ramp(1920, 1080)
[[1280, 720], [3840, 2160], [854, 480]].each ->(sz)
  dw = sz[0]
  dh = sz[1]
  nb = dw * dh * 4
  c = Scaler.new(1920, 1080, dw, dh, backend: :cpu).scale(img)
  m = Scaler.new(1920, 1080, dw, dh, backend: :metal).scale(img)
  v = Scaler.new(1920, 1080, dw, dh, backend: :vimage).scale(img)
  check("1920x1080 -> [dw]x[dh]: Metal = CPU within 1 code ([maxdiff(m, c, nb)])", maxdiff(m, c, nb) <= 1)
  check("1920x1080 -> [dw]x[dh]: vImage's own Lanczos close to ours (RMS [(rms(v, c, nb) * ~100.0).round.to_f / ~100.0])", rms(v, c, nb) < ~2.5)
msg = nil
begin
  Scaler.new(1920, 1080, 1080, 1920, fit: :cover, backend: :vimage)
rescue e
  msg = e.to_s
check("vImage refuses a fractional crop", msg != nil && msg.index("whole-pixel") != nil)

# ---- VideoEncoder source: (scaling inside the encoder) ----
enc = VideoEncoder.new(640, 360, codec: :h264, source: [1280, 720])
src720 = ramp(1280, 720)
k = 0
while k < 24
  enc.encode(src720)
  k += 1
seg = enc.segment
check("VideoEncoder source: [1280, 720] encodes 640x360 frames ([enc.stats[:scale_backend]])", seg.frames == 24 && seg.width == 640 && seg.height == 360)
seg.release
enc.close

# ---- decoder ----
dec = VideoDecoder.new(TMP + "/ch.mp4", format: :nv12)
lum = []
b = dec.read
while b != nil
  lum << b[1280 * 100 + 640]
  b = dec.read
dec.close
fl = []
i = 0
while i < lum.size
  fl << i if lum[i] > 128
  i += 1
check("VideoDecoder: all 240 frames of a B-frame HEVC master, in presentation order (flashes [fl])", lum.size == 240 && fl == t[:flashes])

# segments decode too
enc = VideoEncoder.new(1280, 720, codec: :hevc, rate: [24, 1])
dec = VideoDecoder.new(TMP + "/ch.mp4")
segs = []
k = 0
b = dec.read
while b != nil
  enc.encode(b)
  b = dec.read
  k += 1
  if k % 48 == 0
    s = enc.segment
    p = TMP + "/seg[segs.size].hevc"
    s.save(p)
    s.release
    segs << p
dec.close
enc.close
dec = VideoDecoder.new(segs, format: :nv12)
lum = []
b = dec.read
while b != nil
  lum << b[1280 * 100 + 640]
  b = dec.read
dec.close
fl = []
i = 0
while i < lum.size
  fl << i if lum[i] > 128
  i += 1
check("VideoDecoder over 5 segment files: 240 frames, flashes [fl]", lum.size == 240 && fl == t[:flashes])

# ---- transcodes ----
r = Transcode.run(TMP + "/ch.mp4", TMP + "/a480.mp4", width: 854, height: 480, quality: ~0.7)
v = MediaVerify.check(TMP + "/a480.mp4", sync: true, flashes: t[:flashes], chapters: chaps, tc_start: "01:00:00:00", frames: 240)
check("transcode Y'CbCr path 720p HEVC -> 480p H.264, AAC passthrough: chapters, tmcd, sync, colour all pass ([r[:duplicated]] repeated, [r[:dropped]] dropped)",
      passes(v) && r[:duplicated] == 0 && r[:dropped] == 0 && r[:via] == "yuv")
r = Transcode.run(TMP + "/ch.mp4", TMP + "/b480.mp4", width: 854, height: 480, via: :rgb, audio: :aac, audio_kbps: 128)
v = MediaVerify.check(TMP + "/b480.mp4", sync: true, flashes: t[:flashes], chapters: chaps, tc_start: "01:00:00:00", frames: 240)
check("transcode RGB path with AAC re-encode passes every check", passes(v) && r[:via] == "rgb")
r = Transcode.run(TMP + "/ch.mp4", TMP + "/range.mp4", start: 30, frames: 120, width: 640, height: 360)
v = MediaVerify.check(TMP + "/range.mp4", sync: true, flashes: [30, 78], chapters: [["Second — π and Wolfenbüttel", 0]], tc_start: "01:00:01:06", frames: 120)
check("a range (frames 30-149) shifts the flashes, clicks, chapters and timecode", passes(v))
r = Transcode.run(segs, TMP + "/vert.mp4", rate: [24, 1], audio_src: t[:wav], preset: :vertical_pad, chapters: chaps)
v = Transcode.check(TMP + "/vert.mp4", preset: :vertical_pad, sync: true, flashes: t[:flashes], chapters: chaps, tc_start: "00:00:00:00", frames: 240)
check("segments + WAV -> vertical_pad (1080x1920 H.264, bars): every check and the preset's codec/level", passes(v))
r = Transcode.run(TMP + "/ch.mp4", TMP + "/share.mp4", preset: :share)
v = Transcode.check(TMP + "/share.mp4", preset: :share, sync: true, flashes: t[:flashes], chapters: chaps, tc_start: "01:00:00:00", frames: 240)
check("share preset (1280x720 H.264 2.5 Mb/s, AAC 128k): every check, level within 4.0", passes(v))

# ---- levels ----
check("H.264 minimum levels: 720p30 3.1, 1080p30 4.0, 1080p60 4.2, 2160p30 5.1, 2160p60 5.2",
      Transcode.min_level("h264", 1280, 720, [30, 1])[0] == "3.1" && Transcode.min_level("h264", 1920, 1080, [30, 1])[0] == "4.0" &&
      Transcode.min_level("h264", 1920, 1080, [60, 1])[0] == "4.2" && Transcode.min_level("h264", 3840, 2160, [30, 1])[0] == "5.1" &&
      Transcode.min_level("h264", 3840, 2160, [60, 1])[0] == "5.2")
check("H.264 cannot hold 8K; HEVC 4320p30 needs level 6",
      Transcode.min_level("h264", 7680, 4320, [30, 1]) == nil && Transcode.min_level("hevc", 7680, 4320, [30, 1])[0] == "6")
check("presets: the ladder 480p..4320p, verticals and share", Transcode.presets.keys.size == 10 && Transcode.preset("4k")[:width] == 3840 && Transcode.preset("8k")[:codec] == "hevc")

st = VideoEncoder.stats
check("no native leak (encoders, segments, muxes)", st[:encoders] == 0 && st[:segments] == 0 && st[:muxes] == 0)
OS.system("rm -rf " + TMP)
<< "ALL PASS media_transcode_spec ([passed.load()] checks)"
