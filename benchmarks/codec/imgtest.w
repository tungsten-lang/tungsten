# imgtest — decode images with Blade's own decoders and compare against ImageIO.
#
#   tungsten benchmarks/codec/imgtest.w -- [options] FILE...
#     --raw        decoders skip colour management (IMG_COLOUR) and the
#                  comparison uses ImageIO's own-space bytes: checks pure decoding
#     --own        compare in the image's own colour space (ImageIO's raw bytes)
#                  instead of colour-managed into sRGB (the default)
#     --tol N      max abs error allowed per channel for "ok" (default 0)
#     --mean M     mean abs error allowed (default 0.0)
#     --runs N     decode N times and report the fastest (performance)
#     --dump DIR   write each decoded image (frame 0) to DIR/<name>.png
#     --rawframes DIR  write every frame as DIR/<name>.<i>.rgba (raw RGBA8) for
#                  external frame-by-frame comparison, and DIR/<name>.meta
#                  ("w h nframes loop_count delay,delay,…")
#     --frames     print frame count / delays / loop count of animations
#     --noref      don't compare (no ImageIO), just decode and time
#
# One line per file: STATUS name WxH [frames] ms max mean alpha_max. STATUS is
# ok, DIFF (decoded but over tolerance), ERR (our decoder raised; the message
# follows), REFERR (ImageIO failed: only the decode is reported).
# Colour error is measured on premultiplied values; alpha separately.
#
# ImageIO is used here as the reference oracle only, never in Blade's decode path.
# Every bitmap decoder in blade/images is loaded (SVG needs the DOM and painter:
# it is exercised through Blade itself).

use core/codec/image
use core/codec/image/icc
use core/codec/cicp
use core/codec/image/png
use core/codec/image/jpeg
use core/codec/image/gif
use core/codec/image/webp
use core/codec/image/bmp
use core/codec/image/qoi
use core/codec/image/pnm
use core/codec/image/rgbe
use core/codec/image/tga
use core/codec/image/tiff
use core/codec/image/exr
use core/codec/image/icns
use core/codec/image/gputex

# Colour is compared premultiplied (ImageIO hands back pixels that went through
# a premultiplied bitmap, so straight colour under partial alpha is rounded).
-> diff_px(a, b, n) (u8[] u8[] i64) i64[]
  r = i64[4]
  i = 0 ## i64
  mx = 0 ## i64
  am = 0 ## i64
  sum = 0 ## i64
  cnt = 0 ## i64
  while i < n
    aa = a[i + 3]
    ba = b[i + 3]
    da = aa - ba
    da = 0 - da if da < 0
    am = da if da > am
    c = 0 ## i64
    while c < 3
      pa = (a[i + c] * aa + 127) / 255
      pb = (b[i + c] * ba + 127) / 255
      d = pa - pb
      d = 0 - d if d < 0
      mx = d if d > mx
      sum += d
      c += 1
    cnt += 3
    i += 4
  r[0] = mx
  r[1] = sum
  r[2] = cnt
  r[3] = am
  r

-> reference(path, w, h, own)
  img = Canvas.load_image(path)
  return nil if img.width != w || img.height != h
  return img.bytes if own
  c = Canvas.new(w, h, manage: true)
  c.image(img, 0, 0, w, h, fit: :fill, quality: :none)
  b = c.bytes
  c.close
  img.release
  b

-> basename(p)
  k = p.size - 1
  while k >= 0 && p.byte_at(k) != 47
    k -= 1
  p.slice(k + 1, p.size - k - 1)

args = argv()
files = []
own = false
tol = 0
mtol = ~0.0
runs = 1
dump = nil
rawdir = nil
show_frames = false
noref = false
i = 0
while i < args.size
  a = args[i]
  if a == "--own"
    own = true
  elsif a == "--raw"
    own = true
    IMG_COLOUR[0] = false
  elsif a == "--tol"
    i += 1
    tol = args[i].to_i
  elsif a == "--mean"
    i += 1
    mtol = args[i].to_f
  elsif a == "--runs"
    i += 1
    runs = args[i].to_i
  elsif a == "--dump"
    i += 1
    dump = args[i]
  elsif a == "--frames"
    show_frames = true
  elsif a == "--rawframes"
    i += 1
    rawdir = args[i]
  elsif a == "--noref"
    noref = true
  else
    files.push(a)
  i += 1

nok = 0
ndiff = 0
nerr = 0
total_ms = ~0.0
files.each ->(path)
  name = basename(path)
  data = File.read_bytes(path)
  bm = nil
  msg = nil
  best = ~1.0e9
  r = 0
  while r < runs
    t = clock()
    begin
      bm = img_decode(data)
    rescue e
      msg = e.to_s
    el = (clock() - t) * ~1000.0
    best = el if el < best
    r += 1
  if msg != nil
    nerr += 1
    << "ERR    " + name + "  " + msg
  else
    total_ms = total_ms + best
    fr = bm.frames == nil ? "" : " frames=" + bm.frames.size.to_s
    line = name + " " + bm.width.to_s + "x" + bm.height.to_s + fr + " " + ((best * ~100.0).round / ~100.0).to_s + "ms"
    if dump != nil
      Canvas.write_pixels(bm.rgba, bm.width, bm.height, dump + "/" + name + ".png")
    if noref
      << "dec    " + line
    else
      ref = nil
      begin
        ref = reference(path, bm.width, bm.height, own)
      rescue e
        ref = nil
      if ref == nil
        << "REFERR " + line
      else
        d = diff_px(bm.rgba, ref, bm.width * bm.height * 4)
        mean = d[2] == 0 ? ~0.0 : d[1] / (d[2] + ~0.0)
        good = d[0] <= tol && d[3] <= tol && mean <= mtol
        if good
          nok += 1
        else
          ndiff += 1
        << (good ? "ok     " : "DIFF   ") + line + " max=" + d[0].to_s + " mean=" + ((mean * ~1000.0).round / ~1000.0).to_s + " amax=" + d[3].to_s
    if rawdir != nil
      fl = bm.frames == nil ? [[bm, 0]] : bm.frames
      k = 0
      while k < fl.size
        File.write(rawdir + "/" + name + "." + k.to_s + ".rgba", fl[k][0].rgba)
        k += 1
      File.write(rawdir + "/" + name + ".meta", bm.width.to_s + " " + bm.height.to_s + " " + fl.size.to_s + " " + bm.loop_count.to_s + " " + fl.map(->(f) f[1].to_s).join(",") + "\n")
    if show_frames && bm.frames != nil
      ds = bm.frames.map(->(f) f[1].to_s).join(",")
      << "       frames " + bm.frames.size.to_s + " loop=" + bm.loop_count.to_s + " delays=" + ds
<< "--- " + files.size.to_s + " files: " + nok.to_s + " ok, " + ndiff.to_s + " diff, " + nerr.to_s + " decode errors; decode total " + ((total_ms * ~10.0).round / ~10.0).to_s + " ms"
