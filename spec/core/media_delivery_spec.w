# spec: compiled -- media delivery uses VideoToolbox / AVFoundation
# spec: interpreter-rejects -- media is compiled-only
# Real-frame target probes and timing-preserving delivery checks.
passed = Atomic.new(0)
-> check(name, ok)
  raise "FAIL [name]" if !ok
  passed.increment()
  << "PASS [name]"

if !VideoEncoder.available?
  << "SKIP media_delivery_spec: needs macOS"
  exit(0)

TMP = "/tmp/tungsten_media_delivery_[OS.capture("echo $PPID").strip()]"
Dir.mkdir_p(TMP)
t = MediaVerify.sync_test(TMP + "/src.mp4", width: 320, height: 180, seconds: 2, codec: :hevc10, chapters: [["Intro", 0]])
r = Transcode.check(TMP + "/src.mp4", codec: :hevc10, frames: 48, chapters: [["Intro", 0]])
<< MediaVerify.format(r) if !r[:ok]
check("Main10 master passes its profile and bit-depth contract", r[:ok])
check("Main10 is rejected when Main8 was requested", !Transcode.check(TMP + "/src.mp4", codec: :hevc)[:ok])
check("VT level pinning capability is explicit", Transcode.level_pinnable?(:h264) && Transcode.level_pinnable?(:hevc10))
check("only dropped-frame failures are retryable", Transcode.retryable?("the segment failed to encode: VideoToolbox dropped a frame") && !Transcode.retryable?("no such input"))

["hevc10", "prores422", "prores422hq", "prores422lt", "prores422proxy"].each ->(codec)
  out = TMP + "/[codec].mov"
  tr = Transcode.run(TMP + "/src.mp4", out, codec: codec, frames: 24, width: 640, height: 360, audio: :pcm, edit_lists: false)
  vr = Transcode.check(out, codec: codec, frames: 24, edit_lists: false, chapters: [["Intro", 0]], sync: true, flashes: [12])
  << MediaVerify.format(vr) if !vr[:ok]
  check("[codec] CPU plane target: no edits, exact frames, PCM sync, chapters and colour", vr[:ok] && tr[:attempts] == 1 && tr[:duplicated] == 0 && tr[:dropped] == 0)

# Explicit HEVC levels must reach the bitstream, rather than being silently ignored.
["hevc", "hevc10"].each ->(codec)
  Transcode.run(TMP + "/src.mp4", TMP + "/pinned.mp4", codec: codec, level: "4.1", frames: 12, audio: false, tc: false, chapters: false)
  facts = MediaVerify.facts(TMP + "/pinned.mp4", false, false)
  check("[codec] explicit level 4.1 reaches hvcC/SPS", facts[:level] == 123)
  check("[codec] verification rejects a different pinned level", !Transcode.check(TMP + "/pinned.mp4", codec: codec, level: "4.0", audio: false, tc_start: nil)[:ok])

# Remove video edits while retaining sample-exact AAC priming.
tr = Transcode.run(TMP + "/src.mp4", TMP + "/video.mp4", codec: :hevc10, edit_lists: :audio)
vr = MediaVerify.check(TMP + "/video.mp4", frames: 48, sync: true, flashes: [12])
check("signed composition offsets preserve B-frame/AAC sync", vr[:ok] && vr[:facts][:video_edit_offset] == 0)

# Failed encodes preserve an already published destination and remove their temp file.
File.write(TMP + "/keep.mp4", "existing delivery")
msg = nil
begin
  Transcode.run(TMP + "/src.mp4", TMP + "/keep.mp4", codec: :no_such_codec)
rescue e
  msg = e.to_s
check("non-transient failures preserve the destination", msg != nil && File.read(TMP + "/keep.mp4") == "existing delivery")

msg = nil
begin
  Transcode.run(TMP + "/src.mp4", TMP + "/keep.mp4", codec: :hevc10, edit_lists: false)
rescue e
  msg = e.to_s
check("strict no-edit AAC is rejected without publishing a desynchronised file", msg != nil && msg.include?("priming") && File.read(TMP + "/keep.mp4") == "existing delivery")

attempts = Atomic.new(0)
encode = ->(src, dst, opts)
  File.write(dst, "partial")
  if attempts.increment() < 3
    raise "the segment failed to encode: VideoToolbox dropped a frame"
  File.write(dst, "complete")
  {frames: 1}
result = Transcode.deliver(TMP + "/src.mp4", TMP + "/keep.mp4", {retries: 2, retry_delay: 0}, encode)
check("dropped-frame retries restart twice and publish only the complete result", attempts.load() == 3 && result[:attempts] == 3 && File.read(TMP + "/keep.mp4") == "complete")

# Opening then closing before EOF exercises asynchronous callback teardown.
i = 0
while i < 5
  d = VideoDecoder.new(TMP + "/src.mp4")
  d.read
  d.close
  i += 1
check("asynchronous decoders close safely before EOF", true)

# Four actual 8K pictures, rather than a preset metadata-only test.
tr = Transcode.run(TMP + "/src.mp4", TMP + "/8k.mp4", preset: "8k", frames: 4, audio: false, tc: false, chapters: false)
vr = Transcode.check(TMP + "/8k.mp4", preset: "8k", frames: 4, audio: false, tc_start: nil)
<< MediaVerify.format(vr) if !vr[:ok]
check("8K preset encodes real 7680x4320 frames within its HEVC level cap", vr[:ok] && tr[:frames] == 4)
check("no encoder/segment/mux handle leaks", VideoEncoder.stats[:encoders] == 0 && VideoEncoder.stats[:segments] == 0 && VideoEncoder.stats[:muxes] == 0)
OS.system("rm -rf " + TMP)
<< "ALL PASS media_delivery_spec ([passed.load()] checks)"
