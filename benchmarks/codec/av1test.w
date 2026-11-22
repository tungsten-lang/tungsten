# av1test — decode an AV1 IVF file with Blade's AV1 decoder (test tool).
#
#   bin/tungsten benchmarks/codec/av1test.w -- in.ivf [out.yuv]
#
# Writes every output frame's planes (8-bit as bytes, else u16 LE) to out.yuv
# for comparison with dav1d/aomdec output, and prints frames / fps.

use core/codec/image
use core/codec/image/heif
use core/codec/video/av1

-> at_le32(b, o)
  b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)

-> at_put(p, stride, w, h, buf, o, wide) (u16[] i64 i64 i64 u8[] i64 i64) i64
  y = 0 ## i64
  while y < h
    x = 0 ## i64
    while x < w
      v = p[y * stride + x]
      if wide != 0
        buf[o] = v & 255
        buf[o + 1] = v >> 8
        o += 2
      else
        buf[o] = v
        o += 1
      x += 1
    y += 1
  o

b = File.read_bytes(ARGV[0])
out = ARGV.size > 1 ? ARGV[1] : nil
hl = b[6] | (b[7] << 8)
pos = hl
dec = Av1Decoder.new
chunks = []
nfr = 0
t0 = Time.now
while pos + 12 <= b.size
  sz = at_le32(b, pos)
  pos += 12
  data = hf_slice(b, pos, sz)
  pos += sz
  dec.decode(data).each ->(fr)
    nfr += 1
    if out != nil
      wide = fr.bit_depth > 8 ? 1 : 0
      np = fr.planes.size
      cw = (fr.width + fr.ssx) >> fr.ssx
      chh = (fr.height + fr.ssy) >> fr.ssy
      total = fr.width * fr.height + (np - 1) * cw * chh
      buf = ByteArray.new(total * (wide + 1))
      o = at_put(fr.planes[0], fr.strides[0], fr.width, fr.height, buf, 0, wide)
      k = 1
      while k < np
        o = at_put(fr.planes[k], fr.strides[k], cw, chh, buf, o, wide)
        k += 1
      chunks.push(buf)
ms = (Time.now - t0).to_s.to_i / 1000000
<< "[nfr] frames in [ms] ms"
if out != nil
  total = 0
  chunks.each ->(c) total += c.size
  all = ByteArray.new(total)
  o = 0
  chunks.each ->(c)
    hf_copy(c, 0, all, o, c.size)
    o += c.size
  File.write(out, all)
