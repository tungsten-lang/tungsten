# heiftest — corpus test for Blade's AVIF / HEIC decoders (core/codec/image/heif.w + av1 + hevc).
#
#   bin/tungsten benchmarks/codec/heiftest.w -- [-o outdir] [-t maxerr] file-or-dir …
#   bin/tungsten benchmarks/codec/heiftest.w -- --info file      item / property dump
#   bin/tungsten benchmarks/codec/heiftest.w -- --yuv file out    raw decoded planes
#       (primary item, before colour conversion; 8-bit as bytes, else u16 LE)
#
# Each file is decoded with img_decode and compared with ImageIO's decode
# (<file>.ref.png is used instead when present). Prints per-file max/mean
# absolute RGBA error and decode time; failures (max > threshold) get
# <outdir>/<name>.mine.png and .ref.png. ImageIO is only a test oracle.

use core/canvas
use core/codec/image
use core/codec/image/heif
use core/codec/video/av1
use core/codec/video/hevc

# Max / sum / count(>2) of absolute differences. Colour channels of
# translucent pixels are compared premultiplied (ImageIO's bitmaps are
# premultiplied, so their straight colour is imprecise at low alpha).
-> ht_cmp(a, b, n) (u8[] u8[] i64) i64[]
  r = i64[3]
  mx = 0 ## i64
  sum = 0 ## i64
  big = 0 ## i64
  i = 0 ## i64
  while i < n
    k = i & 3
    av = a[i - k + 3]
    bv = b[i - k + 3]
    x = a[i]
    y = b[i]
    if k != 3 && (av < 255 || bv < 255)
      x = (x * av + 127) / 255
      y = (y * bv + 127) / 255
    d = x - y
    d = 0 - d if d < 0
    mx = d if d > mx
    sum += d
    big += 1 if d > 2
    i += 1
  r[0] = mx
  r[1] = sum
  r[2] = big
  r

-> ht_allzero(a, n) (u8[] i64) i64
  i = 0 ## i64
  while i < n
    return 0 if a[i] != 0
    i += 1
  1

-> ht_info(path)
  b = File.read_bytes(path)
  f = heif_parse(b)
  << "brands [f.major] [f.brands.join(",")] primary [f.primary]"
  ids = f.items.keys.sort
  ids.each ->(id)
    it = f.items[id]
    ps = it.props.map(->(p) p.type + (p.essential ? "!" : "") + ht_pdesc(p))
    refs = []
    it.refs.each ->(k, v) refs.push(k + "->" + v.join(","))
    sz = 0
    it.extents.each ->(x) sz += x[1]
    << "  item [id] [it.type] m[it.method] [sz]B [ps.join(" ")] [refs.join(" ")]"
  if f.moov_track != nil
    << "  moov track [f.moov_track[0]] [f.moov_track[3]]x[f.moov_track[4]]"

-> ht_pdesc(p)
  case p.type
    when "ispe"
      "([p.f[:w]]x[p.f[:h]])"
    when "colr"
      p.f[:kind] == "nclx" ? "(nclx [p.f[:cp]]/[p.f[:tc]]/[p.f[:mc]] full=[p.f[:full]])" : "([p.f[:kind]] [p.f[:icc].size]B)"
    when "auxC"
      "([p.f[:urn]])"
    when "irot"
      "([p.f[:angle]])"
    when "imir"
      "([p.f[:axis]])"
    when "pixi"
      "([p.f[:bits].join(",")])"
    else
      ""

-> ht_yuv(path, out)
  b = File.read_bytes(path)
  f = heif_parse(b)
  it = f.primary == nil ? nil : f.item(f.primary)
  pic = nil
  if it == nil
    t = f.moov_track
    pic = HEIF_CODECS["track:" + t[0]].call(t[1], t[2])
  else
    pic = hf_decode_item(f, it, 0)
  << "[pic.width]x[pic.height] bd=[pic.bit_depth] ss=[pic.ssx],[pic.ssy] mono=[pic.mono] cicp=[pic.cicp]"
  wide = pic.bit_depth > 8
  total = 0
  k = 0
  while k < pic.planes.size
    total += pic.pw(k) * pic.ph(k)
    k += 1
  buf = ByteArray.new(wide ? total * 2 : total)
  o = 0
  k = 0
  while k < pic.planes.size
    o = ht_put(pic.planes[k], pic.pw(k) * pic.ph(k), buf, o, wide ? 1 : 0)
    k += 1
  File.write(out, buf)

-> ht_put(p, n, buf, o, wide) (u16[] i64 u8[] i64 i64) i64
  i = 0 ## i64
  while i < n
    if wide != 0
      buf[o] = p[i] & 255
      buf[o + 1] = p[i] >> 8
      o += 2
    else
      buf[o] = p[i]
      o += 1
    i += 1
  o

-> ht_base(p)
  s = p.split("/").last
  s

-> ht_one(path, outdir, thr, stats)
  b = File.read_bytes(path)
  name = ht_base(path)
  t0 = Time.now
  bm = nil
  begin
    bm = img_decode(b)
  rescue e
    << "FAIL  [name]: [e]"
    stats[1] += 1
    return nil
  ms = (Time.now - t0).to_s.to_i / 1000000
  refp = path + ".ref.png"
  refp = path if !File.exist?(refp)
  ref = nil
  begin
    ref = Canvas.load_image(refp)
  rescue e
    << "ok?   [name] [bm.width]x[bm.height] [ms]ms (no reference: [e])"
    return nil
  rb = ref.bytes
  if ref.width != bm.width || ref.height != bm.height || rb.size != bm.width * bm.height * 4
    << "SIZE  [name] mine [bm.width]x[bm.height] ref [ref.width]x[ref.height] refbytes [rb.size] [ms] ms"
    stats[1] += 1
    Canvas.write_pixels(bm.rgba, bm.width, bm.height, outdir + "/" + name + ".mine.png")
    return nil
  n = bm.width * bm.height * 4
  if ht_allzero(rb, n) == 1
    << "noref [name] [bm.width]x[bm.height] [ms] ms (ImageIO returned an empty bitmap)"
    stats[2] += 1
    return nil
  r = ht_cmp(bm.rgba, rb, n)
  mean = (r[1] * 1000 / n).to_f / ~1000.0
  tag = r[0] <= thr ? "pass " : "DIFF "
  if r[0] <= thr
    stats[0] += 1
  else
    stats[1] += 1
    Canvas.write_pixels(bm.rgba, bm.width, bm.height, outdir + "/" + name + ".mine.png")
    Canvas.write_pixels(rb, bm.width, bm.height, outdir + "/" + name + ".ref.png")
  << "[tag] [name] [bm.width]x[bm.height] max [r[0]] mean [mean] >2: [r[2]] [ms] ms"

args = ARGV
if args.size > 0 && args[0] == "--info"
  ht_info(args[1])
elsif args.size > 0 && args[0] == "--yuv"
  ht_yuv(args[1], args[2])
else
  outdir = "."
  thr = 2
  files = []
  i = 0
  while i < args.size
    a = args[i]
    if a == "-o"
      outdir = args[i + 1]
      i += 1
    elsif a == "--up"
      HEIF_UPSAMPLE[0] = args[i + 1].to_i
      i += 1
    elsif a == "--raw"
      HEIF_COLOR_MANAGE[0] = false
    elsif a == "-t"
      thr = args[i + 1].to_i
      i += 1
    elsif Dir.exist?(a)
      Dir.entries(a).sort.each ->(e)
        if e.ends_with?(".avif") || e.ends_with?(".heic") || e.ends_with?(".heif") || e.ends_with?(".HEIC")
          files.push(a + "/" + e)
    else
      files.push(a)
    i += 1
  stats = [0, 0, 0]
  files.each ->(p) ht_one(p, outdir, thr, stats)
  << "[stats[0]] passed, [stats[1]] failed, [stats[2]] without reference"
