# spec: compiled -- native 10-bit planes use VideoToolbox and Metal
# spec: interpreter-rejects -- media is compiled-only
passed = Atomic.new(0)
-> check(name, ok)
  raise "FAIL [name]" if !ok
  passed.increment()
  << "PASS [name]"

if !VideoEncoder.available?
  << "SKIP media_precision_spec: needs macOS"
  exit(0)

# P010 is MSB-aligned: store fine values which an 8-bit detour would erase.
-> plane(w, h, channels, stride) (i64 i64 i64 i64) u8[]
  out = u8[stride * h]
  y = 0
  while y < h
    x = 0
    while x < w * channels
      v = (x * 13 + y * 7 + 257) % 1024
      p = y * stride + x * 2
      out[p] = (v * 64) % 256
      out[p + 1] = v / 4
      x += 1
    y += 1
  out

-> code(p, offset) (u8[] i64) i64
  (p[offset] + p[offset + 1] * 256) / 64

[1, 2].each ->(channels)
  stride = 64 * channels * 2 + 16
  src = plane(64, 36, channels, stride)
  cpu = Scaler.new(64, 36, 64, 36, channels: channels, source_bits: 10, bits: 10, backend: :cpu)
  dst = cpu.scale(src, nil, stride)
  exact = true
  fine = 0
  y = 0
  while y < 36
    x = 0
    while x < 64 * channels
      got = code(dst, (y * 64 * channels + x) * 2)
      exact = false if got != code(src, y * stride + x * 2)
      fine += 1 if got % 4 != 0
      x += 1
    y += 1
  check("[channels]-channel CPU identity preserves all ten bits with padded input stride", exact && fine > 100)
  cpu.free
  if Scaler.backends.include?("metal")
    ["lanczos3", "bicubic", "bilinear"].each ->(filter)
      cpu = Scaler.new(64, 36, 93, 54, channels: channels, source_bits: 10, bits: 10, backend: :cpu, filter: filter, crop: [~1.25, ~0.5, ~60.5, ~34.5])
      gpu = Scaler.new(64, 36, 93, 54, channels: channels, source_bits: 10, bits: 10, backend: :metal, filter: filter, crop: [~1.25, ~0.5, ~60.5, ~34.5])
      a = cpu.scale(src, nil, stride)
      b = gpu.scale(src, nil, stride)
      diff = 0
      i = 0
      while i < 93 * 54 * channels
        d = (code(a, i * 2) - code(b, i * 2)).abs
        diff = d if d > diff
        i += 1
      check("[channels]-channel [filter] Metal fractional crop agrees within one 10-bit code ([diff])", diff <= 1 && gpu.backend == "metal")
      cpu.free
      gpu.free
  else
    << "SKIP Metal agreement: no Metal device"

# Downscale, destination padding and depth conversion exercise the other paths.
source = plane(64, 36, 1, 128)
["cpu", "metal"].each ->(backend)
  if backend == "cpu" || Scaler.backends.include?(backend)
    sc = Scaler.new(64, 36, 32, 18, channels: 1, source_bits: 10, bits: 8, filter: :bilinear, backend: backend)
    out = sc.scale(source)
    check("[backend] 10-to-8 downscale produces a byte plane", out.size == 32 * 18 && out[0] > 60 && out[0] < 100)
    sc.free
    sc = Scaler.new(64, 36, 80, 48, channels: 1, source_bits: 10, bits: 10, rect: [8, 6, 64, 36], fill: [16, 0, 0, 255], backend: backend)
    out = sc.scale(source)
    check("[backend] 10-bit padding uses exact limited-range black", code(out, 0) == 64 && code(out, (6 * 80 + 8) * 2) == code(source, 0))
    msg = nil
    begin
      sc.scale(source, nil, 129)
    rescue e
      msg = e.to_s
    check("[backend] rejects unaligned 10-bit rows", msg != nil && msg.include?("alignment"))
    msg = nil
    begin
      sc.scale(source, nil, -128)
    rescue e
      msg = e.to_s
    check("[backend] rejects a negative stride without wrapping buffer arithmetic", msg != nil && msg.include?("stride"))
    sc.free

TMP = "/tmp/tungsten_media_precision_" + OS.capture("echo $PPID").strip()
Dir.mkdir_p(TMP)
MediaVerify.sync_test(TMP + "/src.mov", width: 128, height: 72, seconds: 2, codec: :hevc10)
dec = VideoDecoder.new(TMP + "/src.mov", format: :p010)
msg = nil
begin
  dec.read(nil, -1)
rescue e
  msg = e.to_s
check("decoder rejects a negative stride before consuming a frame", msg != nil && msg.include?("stride") && dec.frame == -1)
px = dec.read
check("P010 decoder exposes two-byte luma and interleaved chroma samples", px.size == 128 * 72 * 3 && dec.frame_bytes == px.size)
dec.cancel
msg = nil
begin
  dec.read
rescue e
  msg = e.to_s
dec.close
check("decoder cancellation wakes a blocked or queued read", msg != nil && msg.include?("cancelled"))
Env.set("TUNGSTEN_MEDIA_TEST_STALL_DECODER", "1")
dec = VideoDecoder.new(TMP + "/src.mov", timeout_ms: 50)
t0 = clock_ms()
msg = nil
begin
  dec.read
rescue e
  msg = e.to_s
dec.close
Env.delete("TUNGSTEN_MEDIA_TEST_STALL_DECODER")
check("decoder timeout and early close are bounded", msg != nil && msg.include?("timed out") && clock_ms() - t0 < 2000)
r = Transcode.run(TMP + "/src.mov", TMP + "/out.mov", codec: :prores422, width: 256, height: 144, audio: :pcm)
check("Main10 to ProRes reports 10-bit decode and 10-bit output", r[:decode_bits] == 10 && MediaVerify.facts(TMP + "/out.mov", false, false)[:bit_depth] == 10)
OS.system("rm -rf " + TMP)
<< "ALL PASS media_precision_spec ([passed.load()] checks)"
