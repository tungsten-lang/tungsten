# Demuxers (core/codec/container/*): every fixture container is split into
# tracks and samples; each track's codec, sample count and an FNV-1a hash of
# its sample bytes are pinned. No decoding (video_spec / audio_spec do that).
#
# spec: compiled -- the codec files call functions at load time before defining them (hoisting is compiled-only)
#
#   bin/tungsten spec/core/codec/container_spec.w

use core/codec/container/all
use support

-> demux_summary(a)
  d = demux_for(a)
  return "unrecognised" if d == nil
  d.append(a)
  d.parse
  d.finish
  per = {}
  d.take.each ->(ts)
    per[ts[0]] = [0, FNV0] if per[ts[0]] == nil
    p = per[ts[0]]
    p[0] += 1
    p[1] = fnv8(ts[1].data, ts[1].data.size, p[1])
  out = d.kind.to_s
  d.tracks.each ->(t)
    p = per[t.id]
    p = [0, FNV0] if p == nil
    out = out + " | " + t.kind.to_s + " " + t.cfg.codec + " n=" + p[0].to_s + " fnv=" + p[1].to_s
  out = out + " ERROR " + d.error if d.error != nil
  out

CASES = [
  ["h264.mp4", "mp4 | video avc1 n=3 fnv=3676974463"],
  ["aac.m4a", "mp4 | audio mp4a n=6 fnv=3262107052"],
  ["vp9.webm", "webm | video vp09 n=3 fnv=1697103336"],
  ["opus.ogg", "ogg | audio opus n=6 fnv=2800070550"],
  ["theora.ogv", "ogg | video theo n=2 fnv=528143865"],
  ["av.ts", "ts | video h264 n=3 fnv=2880969153 | audio mp4a n=6 fnv=4150852399"],
  ["tone.wav", "wav | audio pcm  n=2 fnv=3031112357"],
  ["tone.aiff", "aiff | audio pcm  n=2 fnv=558428629"]
]

CASES.each ->(c)
  check(c[0], demux_summary(codec_fixture(c[0])), c[1])
codec_done
