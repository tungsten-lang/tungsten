# One 1920x1080 frame through the CPU Rec.709 paths (core/ycbcr.w): Raster ->
# Y'CbCr 4:2:0 -> packed bytes, and back. Benchmark a --release build:
#
#   bin/tungsten -o /tmp/rec709_frame --release benchmarks/media/rec709_frame.w
#   /tmp/rec709_frame [width height reps]
#
# Prints the mean milliseconds per frame for each step.

args = argv()
w = 1920
h = 1080
reps = 10
if args.size >= 2
  w = args[0].to_i
  h = args[1].to_i
if args.size >= 3
  reps = args[2].to_i

r = Raster.new(w, h, 0)
y = 0
while y < h
  x = 0
  while x < w
    r.pixels[y * w + x] = ((x * 255) / w) * 65536 + ((y * 255) / h) * 256 + ((x + y) % 256)
    x += 1
  y += 1

-> report(label, t0, reps)
  ms = (clock_ms - t0).to_f / reps.to_f
  << "[label]: [Motion.fixed(ms, 2)] ms/frame"

frame = nil
t0 = clock_ms
k = 0
while k < reps
  frame = YuvFrame.from_raster(r)
  k += 1
report("Raster -> 4:2:0 8-bit (passthrough)", t0, reps)

bytes = nil
t0 = clock_ms
k = 0
while k < reps
  bytes = frame.to_i420
  k += 1
report("pack I420", t0, reps)

t0 = clock_ms
k = 0
while k < reps
  bytes = frame.to_nv12
  k += 1
report("pack NV12", t0, reps)

t0 = clock_ms
k = 0
while k < reps
  bytes = YuvFrame.from_raster(r).to_i420
  k += 1
report("Raster -> I420 bytes (total)", t0, reps)

t0 = clock_ms
k = 0
while k < reps
  bytes = YuvFrame.from_raster(r, {bits: 10}).to_p010
  k += 1
report("Raster -> P010 bytes (10-bit)", t0, reps)

t0 = clock_ms
k = 0
while k < reps
  bytes = YuvFrame.from_raster(r, {transfer: :bt1886}).to_i420
  k += 1
report("Raster -> I420 bytes (sRGB -> BT.1886)", t0, reps)

t0 = clock_ms
k = 0
while k < reps
  bytes = YuvFrame.from_raster(r, {source: "display_p3"}).to_i420
  k += 1
report("Raster (Display P3) -> I420 bytes", t0, reps)

back = nil
bt = YuvFrame.from_raster(r, {transfer: :bt1886})
t0 = clock_ms
k = 0
while k < reps
  back = bt.to_raster
  k += 1
report("4:2:0 BT.1886 -> sRGB Raster", t0, reps)

t0 = clock_ms
k = 0
while k < reps
  back = frame.to_raster
  k += 1
report("4:2:0 -> Raster", t0, reps)

t0 = clock_ms
k = 0
while k < reps
  back = YuvFrame.from_bytes(bytes, "yuv420p", w, h).to_raster
  k += 1
report("I420 bytes -> Raster (total)", t0, reps)
