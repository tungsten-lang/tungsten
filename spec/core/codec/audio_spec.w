# Audio codecs (core/codec/audio/*): 0.1 s of a stereo 440/660 Hz tone per
# codec, decoded through the registry (Codec.audio) and pinned by an FNV-1a
# hash of the f32 output. The lossless ones (ALAC, PCM in WAV and AIFF)
# share one hash. MP3 and FLAC elementary streams go through the codec's own
# *_es_parse.
#
# spec: compiled -- the codec files call functions at load time before defining them (hoisting is compiled-only)
#
#   bin/tungsten spec/core/codec/audio_spec.w

use core/codec/container/all
use core/codec/audio/all
use core/codec/video/yuv
use media_support

CASES = [
  ["aac.m4a", "mp4a", "frames=6144 fnv=1633548298"],
  ["alac.m4a", "alac", "frames=4800 fnv=1507733285"],
  ["opus.ogg", "opus", "frames=5760 fnv=319441141"],
  ["vorbis.ogg", "vorb", "frames=5120 fnv=1467046782"],
  ["tone.ac3", "ac-3", "frames=6144 fnv=340808131"],
  ["tone.wav", "pcm ", "frames=4800 fnv=1507733285"],
  ["tone.aiff", "pcm ", "frames=4800 fnv=1507733285"]
]

CASES.each ->(c)
  r = demux_all(codec_fixture(c[0]))
  d = r[0]
  got = nil
  begin
    t = d.tracks[0]
    check(c[0] + " codec", t.cfg.codec, c[1])
    check(c[0] + " registered", Codec.audio?(t.cfg.codec), true)
    got = decode_audio(t.cfg, r[1][t.id])
  rescue e
    got = "error: " + e.to_s
  check(c[0], got, c[2])

ES_CASES = [
  ["tone.mp3", "frames=6912 fnv=4257085852"],
  ["tone.flac", "frames=4800 fnv=1507733285"]
]
ES_CASES.each ->(c)
  got = nil
  begin
    b = codec_fixture(c[0])
    es = c[0] == "tone.mp3" ? mp3_es_parse(b) : flac_es_parse(b)
    got = decode_audio(es[:cfg], es[:samples])
  rescue e
    got = "error: " + e.to_s
  check(c[0], got, c[1])
codec_done
