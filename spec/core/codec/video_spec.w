# Video codecs (core/codec/video/*): three frames of ffmpeg's testsrc per
# codec (Theora: the first frame of a Xiph clip), demuxed, decoded through
# the registry (Codec.video) and pinned by FNV-1a hashes of every Y'CbCr
# plane and of the first frame converted to RGBA (core/codec/video/yuv).
# H.264 in MP4 and in MPEG-TS (container_spec) decode to the same frames.
#
# spec: compiled -- the codec files call functions at load time before defining them (hoisting is compiled-only)
#
#   bin/tungsten spec/core/codec/video_spec.w

use core/codec/container/all
use core/codec/video/all
use media_support

CASES = [
  ["h264.mp4", "avc1", "32x24 420/8 frames=3 fnv=2273622277 rgba0=539060208"],
  ["hevc.mp4", "hvc1", "32x24 420/8 frames=3 fnv=2642263043 rgba0=1902044065"],
  ["av1.mp4", "av01", "64x64 420/8 frames=3 fnv=3566350211 rgba0=3109273462"],
  ["vp9.webm", "vp09", "32x24 420/8 frames=3 fnv=289111787 rgba0=3612507374"],
  ["vp8.webm", "vp08", "32x24 420/8 frames=3 fnv=1798599612 rgba0=450780826"],
  ["theora.ogv", "theo", "688x470 420/8 frames=2 fnv=4025398224 rgba0=1517533805"],
  ["av.ts", "h264", "32x24 420/8 frames=3 fnv=2273622277 rgba0=539060208"]
]

CASES.each ->(c)
  r = demux_all(codec_fixture(c[0]))
  d = r[0]
  got = nil
  begin
    t = d.tracks[0]
    check(c[0] + " codec", t.cfg.codec, c[1])
    check(c[0] + " registered", Codec.video?(t.cfg.codec), true)
    got = frames_summary(decode_video(t.cfg, r[1][t.id]))
  rescue e
    got = "error: " + e.to_s
  check(c[0], got, c[2])

check("unknown codec", Codec.video?("xxxx"), false)
err = nil
begin
  Codec.video(CodecConfig.new("xxxx"))
rescue e
  err = e.class.to_s + ": " + e.to_s
check("unknown codec raises MediaError", err, "MediaError: unsupported video codec xxxx")
codec_done
