# spec: compiled -- media encodes through runtime/media (VideoToolbox/AVFoundation), linked only into compiled programs
# spec: interpreter-rejects -- media is compiled-only
# Media core (core/media/*.w, runtime/media): VideoToolbox encoding into
# closed-GOP segments, segment files, passthrough muxing with exact timing,
# audio, tmcd, and verification.
#
# Checks: the RGB -> Y'CbCr converter is bit-for-bit YuvFrame (BT.709,
# limited range, each siting, 8 and 10 bits, 4:2:0 and 4:2:2, RGBA/BGRA/RGB24
# input, every 8-bit RGB triple); a segment starts with an IDR and B-frames
# stay inside it; two encoders with
# equal settings emit byte-identical parameter sets, so their segments share
# one sample description; segment files round-trip; masters at 24, 24000/1001
# and 30000/1001 (drop-frame tmcd) in MP4/AAC and MOV/PCM pass every
# MediaVerify check, including the flash/click sync test (+-1 sample, 0
# frames) and the colour bars (BT.709, not BT.601); a segment from other
# settings is refused; 59.94 drop-frame, 10-bit HEVC and ProRes masters
# verify; no native leak.
#
# Run:
#   bin/tungsten spec/core/media_spec.w

passed = Atomic.new(0)

-> check(name, condition)
  raise "FAIL " + name if !condition
  passed.increment()
  << "PASS " + name

if !VideoEncoder.available?
  msg = nil
  begin
    VideoEncoder.new(64, 64)
  rescue e
    msg = e.to_s
  check("stub raises a clear error", msg != nil && msg.index("needs macOS") != nil)
  << "ALL PASS media_spec ([passed.load()] checks, stub build)"
  exit(0)

TMP = "/tmp/tungsten_media_spec_" + OS.capture("echo $PPID").strip()
Dir.mkdir_p(TMP)

# ---- codecs ----
codecs = VideoEncoder.codecs
check("VideoToolbox opens H.264, HEVC, HEVC Main10, ProRes 422 and 422 HQ",
      codecs.include?("h264") && codecs.include?("hevc") && codecs.include?("hevc10") && codecs.include?("prores422") && codecs.include?("prores422hq"))

# ---- converter == YuvFrame, bit for bit ----
-> test_image(w, h, bpp, ro, gof, bo) (i64 i64 i64 i64 i64 i64) u8[]
  px = u8[w * h * bpp]
  s = 12345
  y = 0
  while y < h
    x = 0
    while x < w
      s = (s * 1103515245 + 12345) & 2147483647
      o = (y * w + x) * bpp
      r = (s >> 8) & 255
      g = (x * 255) / (w - 1)
      b = (y * 255) / (h - 1)
      if (x + y) % 7 == 0
        r = 255
        g = 0
        b = 0
      if (x * y) % 11 == 3
        r = 0
        g = 0
        b = 255
      px[o + ro] = r
      px[o + gof] = g
      px[o + bo] = b
      if bpp == 4
        px[o + 6 - ro - gof - bo] = 255
      x += 1
    y += 1
  px

W = 66
H = 38
rgba = test_image(W, H, 4, 0, 1, 2)
bgra = test_image(W, H, 4, 2, 1, 0)
rgb24 = test_image(W, H, 3, 0, 1, 2)

-> same_bytes?(a, b)
  if a.size != b.size
    << "  sizes differ: [a.size] vs [b.size]"
    return false
  i = 0
  while i < a.size
    if a[i] != b[i]
      << "  first difference at byte [i]: [a[i]] vs [b[i]]"
      return false
    i += 1
  true

[["nv12", :yuv420, 8, "left"], ["nv12", :yuv420, 8, "center"], ["nv12", :yuv420, 8, "topleft"],
 ["p010", :yuv420, 10, "left"], ["nv16", :yuv422, 8, "left"], ["p210", :yuv422, 10, "left"]].each ->(t)
  ref = YuvFrame.from_rgba(rgba, W, H, {chroma: t[1], bits: t[2], siting: t[3].to_sym}).to_bytes(t[0])
  got = ccall("w_media_convert", rgba, W, H, W * 4, "rgba", t[0], t[3])
  check("converter == YuvFrame: [t[0]] siting [t[3]]", same_bytes?(got, ref))
ref = YuvFrame.from_rgba(rgba, W, H).to_nv12
check("converter == YuvFrame: BGRA input", same_bytes?(ccall("w_media_convert", bgra, W, H, W * 4, "bgra", "nv12", "left"), ref))
check("converter == YuvFrame: RGB24 input", same_bytes?(ccall("w_media_convert", rgb24, W, H, W * 3, "rgb24", "nv12", "left"), ref))
# A padded stride reads only the pixels.
padded = u8[(W * 4 + 40) * H]
y = 0
while y < H
  x = 0
  while x < W * 4
    padded[y * (W * 4 + 40) + x] = rgba[y * W * 4 + x]
    x += 1
  y += 1
check("converter honours the stride", same_bytes?(ccall("w_media_convert", padded, W, H, W * 4 + 40, "rgba", "nv12", "left"), ref))
# Every 8-bit RGB triple once (a 4096 x 4096 frame, shuffled by an odd
# multiplier so chroma neighbourhoods vary): the converter computes codes in
# fixed point and redoes the few within a guard band of a rounding tie with
# YuvFrame's double arithmetic; this exercises that path across the whole
# luma domain and 4.2M chroma samples, 8 and 10 bit.
-> all_rgb(n) (i64) u8[]
  px = u8[n * n * 4]
  i = 0
  while i < n * n
    v = (i * 2654435761) & 16777215
    o = i * 4
    px[o] = (v >> 16) & 255
    px[o + 1] = (v >> 8) & 255
    px[o + 2] = v & 255
    px[o + 3] = 255
    i += 1
  px

# (ccall takes integer literals as raw machine words, so sizes go through a
# method, as the media classes' own calls do.)
-> convert(px, w, h, stride, input, output, siting)
  ccall("w_media_convert", px, w, h, stride, input, output, siting)

N = 4096
big = all_rgb(N)
check("every RGB triple: converter == YuvFrame, 8-bit 4:2:0",
      same_bytes?(convert(big, N, N, N * 4, "rgba", "nv12", "left"), YuvFrame.from_rgba(big, N, N).to_nv12))
check("every RGB triple: converter == YuvFrame, 10-bit 4:2:2",
      same_bytes?(convert(big, N, N, N * 4, "rgba", "p210", "left"), YuvFrame.from_rgba(big, N, N, {chroma: :yuv422, bits: 10}).to_bytes("p210")))
check("every RGB triple: converter == YuvFrame, 8-bit 4:2:0 topleft",
      same_bytes?(convert(big, N, N, N * 4, "rgba", "nv12", "topleft"), YuvFrame.from_rgba(big, N, N, {siting: :topleft}).to_nv12))
big = nil

q = YCbCr.bt709
red = q.encode_rgb8(255, 0, 0)
check("BT.709 red is Y'CbCr 63/102/240 (BT.601 would be 81/90/240)", red == [63, 102, 240])

# ---- segments ----
-> frame_bytes(w, h, f) (i64 i64 i64) u8[]
  px = u8[w * h * 4]
  y = 0
  while y < h
    x = 0
    while x < w
      o = (y * w + x) * 4
      px[o] = (x + f * 3) & 255
      px[o + 1] = (y * 2 + f) & 255
      px[o + 2] = ((x + y) / 2 + f * 5) & 255
      px[o + 3] = 255
      x += 1
    y += 1
  px

SW = 640
SH = 360
frames = []
k = 0
while k < 8
  frames << frame_bytes(SW, SH, k * 3)
  k += 1

-> encode_segments(codec, lengths, frames, opts)
  enc = VideoEncoder.new(640, 360, codec: codec, rate: opts[:rate], quality: opts[:quality], gop: 48, reorder: opts[:reorder])
  segs = []
  f = 0
  lengths.each ->(n)
    i = 0
    while i < n
      enc.encode(frames[(f + i) % frames.size])
      i += 1
    f += n
    segs << enc.segment
  enc.close
  segs

-> first_vcl_nal(sample, hevc)
  off = 0
  while off + 5 <= sample.size
    len = (sample[off] << 24) | (sample[off + 1] << 16) | (sample[off + 2] << 8) | sample[off + 3]
    t = hevc ? (sample[off + 4] >> 1) & 63 : sample[off + 4] & 31
    vcl = hevc ? t < 32 : (t >= 1 && t <= 5)
    return t if vcl
    off += 4 + len
  0 - 1

segs = encode_segments("h264", [48, 1, 20], frames, {rate: [24, 1], quality: ~0.6, reorder: false})
check("three segments of 48, 1 and 20 frames", segs[0].frames == 48 && segs[1].frames == 1 && segs[2].frames == 20)
check("each segment has exactly one sync sample, first", segs.all? ->(s) s.keyframes == 1 && s.sync[0] == 1)
check("H.264 segments start with an IDR slice (NAL 5)", segs.all? ->(s) first_vcl_nal(s.sample(0), false) == 5)
check("no reordering: decode order is presentation order", segs[0].pts == (0...48).to_a)
check("parameter sets are identical across segments", segs[0].param_sets == segs[1].param_sets && segs[1].param_sets == segs[2].param_sets)
other = encode_segments("h264", [5], frames, {rate: [24, 1], quality: ~0.6, reorder: false})
check("a second encoder with the same settings emits byte-identical SPS/PPS", other[0].param_sets == segs[0].param_sets && other[0].format == segs[0].format)
sps = ccall("w_media_parse_sps", segs[0].param_sets, false)
facts = {}
sps.each ->(p)
  facts[p[0]] = p[1]
check("SPS: High profile, 640x360, VUI BT.709 1/1/1, limited range", facts["profile"] == 100 && facts["width"] == 640 && facts["height"] == 360 &&
      facts["primaries"] == 1 && facts["transfer"] == 1 && facts["matrix"] == 1 && facts["full_range"] == 0)
<< "  H.264 VUI chroma_sample_loc_type: [facts["chroma_loc"]] (-1 = not signalled, which means 0 = left)"

path = TMP + "/seg.h264"
n = segs[2].save(path)
back = VideoSegment.load(path)
check("segment file round trip: frames, bytes, sync, parameter sets", back.frames == 20 && back.bytes == segs[2].bytes && back.sync == segs[2].sync && back.param_sets == segs[2].param_sets)
check("segment file round trip: format description and samples", back.format == segs[2].format && back.sample(7) == segs[2].sample(7) && n == File.size(path))

hsegs = encode_segments("hevc", [24, 3], frames, {rate: [24000, 1001], quality: ~0.6})
check("HEVC segments start with an IDR (IDR_W_RADL/IDR_N_LP)", hsegs.all? ->(s) first_vcl_nal(s.sample(0), true) == 19 || first_vcl_nal(s.sample(0), true) == 20)
hother = encode_segments("hevc", [2], frames, {rate: [24000, 1001], quality: ~0.6})
check("HEVC: a second encoder emits byte-identical VPS/SPS/PPS", hother[0].param_sets == hsegs[0].param_sets)
hq = encode_segments("hevc", [2], frames, {rate: [24000, 1001], quality: ~0.9})
check("HEVC parameter sets depend on quality (so the mux must refuse mixing)", hq[0].param_sets != hsegs[0].param_sets)

# B-frames inside segments: still one IDR per segment, all frames 0..n-1.
rsegs = encode_segments("hevc", [48, 1, 30], frames, {rate: [24, 1], quality: ~0.7, reorder: true})
check("reordering: one sync sample per segment, first", rsegs.all? ->(s) s.keyframes == 1 && s.sync[0] == 1)
check("reordering: decode order differs from presentation order", rsegs[0].pts != (0...48).to_a && rsegs[0].pts.sort == (0...48).to_a)
rmp4 = TMP + "/reorder.mp4"
mux = Mux.new(rmp4, rate: [24, 1])
mux.append(rsegs[1])
mux.append(rsegs[0])
mux.append(rsegs[2])
mux.close
rv = MediaVerify.check(rmp4, rate: [24, 1], frames: 79, audio: false)
<< MediaVerify.format(rv)
check("a reordered master starting with a 1-frame segment verifies (DTS delay reserved, edit list applied)", rv[:ok])
rsegs.each ->(s)
  s.release

# ---- a master from segments of two encoders ----
mp4 = TMP + "/concat.mp4"
mux = Mux.new(mp4, rate: [24, 1])
segs.each ->(s)
  mux.append(s)
other.each ->(s)
  mux.append(s)
r = mux.close
check("mux wrote 74 frames", r[:frames] == 74 && r[:file_bytes] > r[:video_bytes])
v = MediaVerify.check(mp4, rate: [24, 1], frames: 74, audio: false)
<< MediaVerify.format(v)
check("concatenated master verifies (CFR, exact PTS, tmcd, colour, faststart)", v[:ok])

# mixing settings is refused
bad = TMP + "/bad.mp4"
mux = Mux.new(bad, rate: [24000, 1001])
mux.append(hsegs[0])
msg = ""
begin
  mux.append(hq[0])
rescue e
  msg = e.to_s
check("a segment with other parameter sets is refused", msg.index("different settings") != nil)
r2 = mux.close
check("the mux stays usable after a refusal", r2[:frames] == 24)

# ---- sync + colour masters ----
-> sync_master(name, opts)
  t = MediaVerify.sync_test(TMP + "/" + name, opts)
  r = MediaVerify.check(t[:path], rate: opts[:rate], frames: t[:frames], tc_start: opts[:tc_start], sync: true, flashes: t[:flashes], bars: true)
  << MediaVerify.format(r)
  r[:ok]

check("24 fps MP4 + AAC: CFR, PTS, tmcd, audio length, colour, sync, bars",
      sync_master("sync24.mp4", {rate: [24, 1], seconds: 6, width: 640, height: 360, tc_start: "00:00:00:00"}))
check("24 fps MP4 + AAC without a frame-count promise (audio overshoot trimmed)",
      sync_master("sync24np.mp4", {rate: [24, 1], seconds: 5, width: 640, height: 360, promise: false}))
check("23.976 MP4 HEVC + AAC, tmcd from 01:00:00:00",
      sync_master("sync23976.mp4", {rate: [24000, 1001], seconds: 6, width: 640, height: 360, codec: :hevc, tc_start: "01:00:00:00"}))
check("29.97 MOV + 24-bit PCM, drop-frame tmcd from 00:59:59;00",
      sync_master("sync2997.mov", {rate: [30000, 1001], seconds: 6, width: 640, height: 360, tc_start: "00:59:59;00"}))
check("59.94 MP4 + AAC, drop-frame tmcd from 00:00:00;00",
      sync_master("sync5994.mp4", {rate: [60000, 1001], seconds: 3, width: 640, height: 360, tc_start: "00:00:00;00"}))
check("10-bit HEVC MOV verifies, bars at 10 bits",
      sync_master("sync10.mov", {rate: [25, 1], seconds: 4, width: 640, height: 360, codec: :hevc10}))
check("H.264 without B-frames (reorder: false), MP4 + AAC",
      sync_master("syncnb.mp4", {rate: [24, 1], seconds: 5, width: 640, height: 360, reorder: false}))
check("ProRes 422 HQ MOV verifies",
      sync_master("syncpr.mov", {rate: [24, 1], seconds: 3, width: 640, height: 360, codec: :prores422hq}))

# ---- no native leak ----
segs.each ->(s)
  s.release
[other, hsegs, hother, hq].each ->(list)
  list.each ->(s)
    s.release
back.release
st = VideoEncoder.stats
check("no native encoder, segment or mux left", st[:encoders] == 0 && st[:segments] == 0 && st[:segment_bytes] == 0)

OS.system("rm -rf " + TMP)
<< "ALL PASS media_spec ([passed.load()] checks)"
