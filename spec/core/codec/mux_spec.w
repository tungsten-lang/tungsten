# Muxers and remux (core/codec/container/mux_mp4, mux_webm, remux): fixture
# streams are copied into MP4 and WebM files and demuxed again; every track
# must come back with the same codec, sample count and sample bytes (FNV-1a),
# and the timestamps within a millisecond. Covers H.264 + AAC in MP4 (with
# faststart: moov before mdat), VP9 + Opus in WebM and in MP4 (vpcC
# synthesised), and the MPEG-TS → MP4 path.
#
# spec: compiled -- the codec files call functions at load time before defining them (hoisting is compiled-only)
#
#   bin/tungsten spec/core/codec/mux_spec.w

use core/codec/container/all
use support

TMP = "/tmp/tungsten-mux-spec-" + clock_ms().to_s

-> fixture_path(name)
  __DIR__ + "/../../fixtures/codec/" + name

# [[kind codec, count, fnv, first pts ms], …] of a file's tracks.
-> summary(bytes)
  d = demux_for(bytes)
  return [] if d == nil
  d.append(bytes)
  d.parse
  d.finish
  per = {}
  d.take.each ->(ts)
    per[ts[0]] = [0, FNV0, nil] if per[ts[0]] == nil
    p = per[ts[0]]
    p[0] += 1
    p[1] = fnv8(ts[1].data, ts[1].data.size, p[1])
    p[2] = ts[1].pts if p[2] == nil || ts[1].pts < p[2]
  out = []
  d.tracks.each ->(t)
    p = per[t.id]
    p = [0, FNV0, ~0.0] if p == nil
    # (presentation start, ms, for video: audio pre-roll before 0 is clamped by WebM)
    t0 = t.kind == :video ? " t0=" + (p[2] * ~1000.0).round.to_s : ""
    out.push(t.kind.to_s + " " + t.cfg.codec.strip + " n=" + p[0].to_s + " fnv=" + p[1].to_s + t0)
  out.sort

-> roundtrip(name, ins, out)
  want = []
  ins.each ->(i) summary(File.read_bytes(fixture_path(i))).each ->(x) want.push(x)
  media_remux(ins.map(->(i) fixture_path(i)), out)
  got = summary(File.read_bytes(out))
  check(name, got.join(" ; "), want.sort.join(" ; "))
  got

roundtrip("H.264 + AAC → MP4", ["h264.mp4", "aac.m4a"], TMP + "_a.mp4")
b = File.read_bytes(TMP + "_a.mp4")
check("faststart: moov before mdat", dm_fourcc(b, 4) + " " + dm_fourcc(b, 36 + 4), "ftyp moov")
roundtrip("VP9 + Opus → WebM", ["vp9.webm", "opus.ogg"], TMP + "_b.webm")
roundtrip("VP9 + Opus → MP4", ["vp9.webm", "opus.ogg"], TMP + "_c.mp4")
# MPEG-TS H.264 is Annex B: the MP4 gets avcC and length-prefixed NALs (other bytes), the AAC is unchanged
media_remux([fixture_path("av.ts")], TMP + "_d.mp4")
check("MPEG-TS → MP4", summary(File.read_bytes(TMP + "_d.mp4")).join(" ; "), "audio mp4a n=6 fnv=4150852399 ; video avc1 n=3 fnv=868431262 t0=21")
dd = demux_for(File.read_bytes(TMP + "_d.mp4"))
dd.append(File.read_bytes(TMP + "_d.mp4"))
dd.parse
vc = nil
dd.tracks.each ->(t) vc = t.cfg if t.kind == :video
check("MPEG-TS → MP4: avcC from the SPS/PPS", vc != nil && vc.extra != nil && vc.extra.size > 10 && vc.extra[0] == 1, true)
check("format choice", [media_remux_format([CodecConfig.new("vp09"), CodecConfig.new("vorb")]), media_remux_format([CodecConfig.new("avc1"), CodecConfig.new("mp4a")])].to_s, "\[webm, mp4]")
["_a.mp4", "_b.webm", "_c.mp4", "_d.mp4"].each ->(x) File.delete(TMP + x)
codec_done
