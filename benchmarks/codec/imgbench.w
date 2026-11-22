# imgbench — time Blade's image decoders against macOS ImageIO.
#
#   tungsten compile --release benchmarks/codec/imgbench.w -o /tmp/imgbench
#   /tmp/imgbench --mode blade|imageio|imageio_net|imageio_bytes|none [--runs N] FILE...
#
# Modes (each timed run produces a drawable CanvasImage, then releases it):
#   blade          img_decode(bytes) + Canvas.image_from_rgba   (Blade's path)
#   imageio        Canvas.load_image(path) of a file already on disk
#   imageio_net    write the bytes to a temp file, then Canvas.load_image: what
#                  Blade would pay for an image that arrived over the network
#   imageio_bytes  Canvas.load_image + CanvasImage#bytes (pixels back in Tungsten)
#   none           read the file only (baseline for peak-memory measurements)
#
# One line per file: mode name WxH first=ms (the first decode in this process:
# cold caches, time to first pixels) median=ms min=ms of the remaining runs.
# For animations Blade decodes and composites every frame; ImageIO's
# load_image decodes frame 0 only (frames=N says how many Blade produced).
# Run each file in its own process under /usr/bin/time -l for peak memory.
#
# ImageIO is measured here as a reference only; it is never in Blade's path.

use core/canvas
use core/codec/image
use core/codec/image/icc
use core/codec/cicp
use core/codec/image/png
use core/codec/image/jpeg
use core/codec/image/gif
use core/codec/image/webp
use core/codec/image/bmp
use core/codec/image/heif
use core/codec/video/av1
use core/codec/video/hevc
use core/codec/image/jxl
use core/codec/image/jp2
use core/codec/image/jxr
use core/codec/image/tiff
use core/codec/image/qoi
use core/codec/image/exr
use core/codec/image/rgbe
use core/codec/image/icns
use core/codec/image/gputex
use core/codec/image/pnm
use core/codec/image/tga

-> bench_basename(p)
  k = p.size - 1
  while k >= 0 && p.byte_at(k) != 47
    k -= 1
  p.slice(k + 1, p.size - k - 1)

-> bench_ms(t)
  v = (t * ~100000.0).round
  f = (v % 100).to_s
  f = "0" + f if f.size < 2
  (v / 100).to_s + "." + f

args = argv()
mode = "blade"
runs = 9
files = []
tmpdir = "/tmp"
i = 0
while i < args.size
  a = args[i]
  if a == "--mode"
    i += 1
    mode = args[i]
  elsif a == "--runs"
    i += 1
    runs = args[i].to_i
  elsif a == "--tmp"
    i += 1
    tmpdir = args[i]
  else
    files.push(a)
  i += 1

files.each ->(path)
  name = bench_basename(path)
  data = File.read_bytes(path)
  times = []
  w = 0
  h = 0
  nfr = 0
  err = nil
  r = 0
  while r < runs && err == nil
    t = clock()
    begin
      if mode == "blade"
        bm = img_decode(data)
        img = Canvas.image_from_rgba(bm.rgba, bm.width, bm.height)
        w = bm.width
        h = bm.height
        nfr = bm.frames == nil ? 1 : bm.frames.size
        img.release
      elsif mode == "imageio"
        img = Canvas.load_image(path)
        w = img.width
        h = img.height
        img.release
      elsif mode == "imageio_net"
        tp = tmpdir + "/imgbench." + r.to_s + "." + name
        File.write(tp, data)
        img = Canvas.load_image(tp)
        w = img.width
        h = img.height
        img.release
        File.delete(tp)
      elsif mode == "imageio_bytes"
        img = Canvas.load_image(path)
        px = img.bytes
        w = img.width
        h = img.height
        img.release
      else
        w = data.size
    rescue e
      err = e.to_s
    times.push(clock() - t)
    r += 1
  if err != nil
    << mode + " " + name + " ERR " + err
  else
    first = times[0]
    rest = times.size > 1 ? times.copy(1, times.size - 1) : times
    srt = rest.sort
    med = srt[srt.size / 2]
    fr = nfr > 1 ? " frames=" + nfr.to_s : ""
    << mode + " " + name + " " + w.to_s + "x" + h.to_s + fr + " first=" + bench_ms(first).to_s + " median=" + bench_ms(med).to_s + " min=" + bench_ms(srt[0]).to_s
