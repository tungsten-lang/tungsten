# jpegx_test — corpus test for Blade's JPEG XL / JPEG 2000 / JPEG XR decoders.
#
#   bin/tungsten benchmarks/codec/jpegx_test.w -- [-o outdir] [-t maxerr] file-or-dir …
#
# Each file is decoded with img_decode and compared with a reference:
#   <file>.ref.png if it exists (formats ImageIO can't read, e.g. JPEG XR, or a
#   djxl/opj_decompress rendering), otherwise ImageIO's decode of the file itself.
# Prints per-file max/mean absolute error over RGBA and the decode time; files
# over the threshold get <outdir>/<name>.mine.png and .ref.png for viewing.
# ImageIO is used here only as a test oracle, never by the decoders.

use core/codec/image
use core/codec/image/jxl
use core/codec/image/jp2
use core/codec/image/jxr

-> jt_u8(s)
  ccall("w_string_bytes_view", s) ## u8[]

-> jt_cmp(a, b, n) (u8[] u8[] i64) i64[]
  r = i64[2]
  mx = 0 ## i64
  tot = 0 ## i64
  i = 0 ## i64
  while i < n
    d = a[i] - b[i]
    if (i & 3) != 3
      # colour is compared premultiplied: ImageIO hands back premultiplied-
      # then-unpremultiplied pixels, so straight colour under low alpha is noise
      aa = a[i | 3]
      ab = b[i | 3]
      d = (a[i] * aa - b[i] * ab) / 255
    d = 0 - d if d < 0
    mx = d if d > mx
    tot += d
    i += 1
  r[0] = mx
  r[1] = tot
  r

-> jt_ext_ok?(p)
  l = p.downcase
  l.ends_with?(".jxl") || l.ends_with?(".jp2") || l.ends_with?(".j2k") || l.ends_with?(".j2c") || l.ends_with?(".jpx") || l.ends_with?(".jpf") || l.ends_with?(".jph") || l.ends_with?(".jxr") || l.ends_with?(".wdp") || l.ends_with?(".hdp") || l.ends_with?(".jpc") || l.ends_with?(".codestream")

outdir = nil
thresh = 8
files = []
args = ARGV
i = 0
while i < args.size
  a = args[i]
  if a == "-o"
    outdir = args[i + 1]
    i += 2
  elsif a == "-t"
    thresh = args[i + 1].to_i
    i += 2
  else
    if Dir.directory?(a)
      Dir.children(a).sort.each ->(c)
        p = a + "/" + c
        files.push(p) if jt_ext_ok?(p) && !Dir.directory?(p)
    else
      files.push(a)
    i += 1
Dir.mkdir_p(outdir) if outdir != nil

npass = 0
nfail = 0
total_ms = 0
files.each ->(f)
  name = f.split("/").last
  s = File.read(f)
  u = jt_u8(s)
  fmt = img_sniff(u)
  t0 = clock_ms()
  bm = nil
  err = nil
  begin
    bm = img_decode(u)
  rescue e
    err = e.to_s
  ms = clock_ms() - t0
  total_ms += ms
  if bm == nil
    << "FAIL [name] fmt=[fmt] error: [err] ([ms] ms)"
    nfail += 1
  else
    refp = f + ".ref.png"
    refp = f if !File.exist?(refp)
    ref = nil
    rw = 0
    rh = 0
    begin
      im = Canvas.load_image(refp)
      rw = im.width
      rh = im.height
      ref = im.bytes
    rescue e2
      ref = nil
    if ref == nil
      << "NOREF [name] fmt=[fmt] [bm.width]x[bm.height] ([ms] ms)"
      npass += 1
      if outdir != nil
        Canvas.write_pixels(bm.rgba, bm.width, bm.height, outdir + "/" + name + ".mine.png")
    elsif rw != bm.width || rh != bm.height
      << "FAIL [name] fmt=[fmt] size [bm.width]x[bm.height] vs ref [rw]x[rh] ([ms] ms)"
      nfail += 1
      if outdir != nil
        Canvas.write_pixels(bm.rgba, bm.width, bm.height, outdir + "/" + name + ".mine.png")
    else
      n = rw * rh * 4
      r = jt_cmp(bm.rgba, ref, n)
      mean = (r[1] * 1000 / n) / ~1000.0
      anim = ""
      anim = " frames=[bm.frames.size] loop=[bm.loop_count]" if bm.frames != nil
      ok = r[0] <= thresh
      tag = "ok  "
      tag = "FAIL" if !ok
      << "[tag] [name] fmt=[fmt] [rw]x[rh] max=[r[0]] mean=[mean] [ms] ms[anim]"
      if ok
        npass += 1
      else
        nfail += 1
        if outdir != nil
          Canvas.write_pixels(bm.rgba, bm.width, bm.height, outdir + "/" + name + ".mine.png")
          Canvas.write_pixels(ref, rw, rh, outdir + "/" + name + ".ref.png")
<< "passed [npass] failed [nfail] total decode [total_ms] ms"
