# Image codecs (core/codec/image/*): one tiny fixture per decoder, decoded
# through the registry (Image.sniff / Image.decode) and pinned by an FNV-1a
# hash of the RGBA output. The lossless encodings of spec/fixtures/codec/
# rgba.png (PNG, QOI, TGA, TIFF, lossless WebP, modular JPEG XL) share one
# hash, as do the alpha-less ones (BMP, PPM, JPEG 2000).
#
#   bin/tungsten spec/core/codec/image_spec.w
#   bin/tungsten run --interpret spec/core/codec/image_spec.w

use core/codec/image/all
use support

CASES = [
  ["rgba.png", "png 23x17 fnv=2525377564"],
  ["tiny.jpg", "jpeg 23x17 fnv=510157020"],
  ["tiny.gif", "gif 23x17 fnv=3898129800"],
  ["tiny.bmp", "bmp 23x17 fnv=1847664028"],
  ["tiny.ico", "ico 16x16 fnv=1526197701"],
  ["lossy.webp", "webp 23x17 fnv=850341367"],
  ["lossless.webp", "webp 23x17 fnv=2525377564"],
  ["tiny.tif", "tiff 23x17 fnv=2525377564"],
  ["tiny.qoi", "qoi 23x17 fnv=2525377564"],
  ["tiny.exr", "exr 23x17 fnv=691746247"],
  ["tiny.hdr", "hdr 23x17 fnv=1398826225"],
  ["tiny.icns", "icns 16x16 fnv=1518695142"],
  ["bc1.dds", "dds 8x8 fnv=2188081205"],
  ["bc1.ktx2", "ktx2 250x166 fnv=2124352750"],
  ["tiny.ppm", "pnm 23x17 fnv=1847664028"],
  ["tiny.tga", "tga 23x17 fnv=2525377564"],
  ["tiny.avif", "avif 23x17 fnv=3273496805"],
  ["tiny.heic", "heic 23x17 fnv=135863438"],
  ["vardct.jxl", "jxl 23x17 fnv=531632044"],
  ["modular.jxl", "jxl 23x17 fnv=2525377564"],
  ["tiny.jp2", "jp2 23x17 fnv=1847664028"],
  ["tiny.jxr", "jxr 70x45 fnv=1778120273"]
]

CASES.each ->(c)
  a = codec_fixture(c[0])
  got = nil
  begin
    bm = Image.decode(a)
    got = Image.sniff(a) + " " + bm.width.to_s + "x" + bm.height.to_s + " fnv=" + fnv8(bm.rgba, bm.rgba.size, FNV0).to_s
  rescue e
    got = "error: " + e.to_s
  check(c[0], got, c[1])

# The registry: every format registered, in sniff order; String input; errors.
check("formats", Image.formats.join(" "), "jxl jp2 jxr avif heic png jpeg gif webp bmp ico tiff qoi exr hdr icns dds ktx2 pnm tga")
png_text = File.read(__DIR__ + "/../../fixtures/codec/rgba.png")
check("sniff String", Image.sniff(png_text), "png")
check("decode String", Image.decode(png_text).width, 23)
check("sniff unknown", Image.sniff("hello world"), nil)
err = nil
begin
  Image.decode("definitely not an image")
rescue e
  err = e.class.to_s + ": " + e.to_s
check("decode unknown raises ImageError", err, "ImageError: unrecognised image format")
codec_done
