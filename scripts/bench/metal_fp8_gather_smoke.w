# Exactness smoke for the bulk host-resident FP8 E4M3 row gather.
# Two rows exercise positive and sign-bit-set values.

use core/metal

path = "/tmp/tungsten-metal-fp8-gather-smoke.bin"
File.write(path, ("A" * 64) + ("é" * 32))

m = File.mmap(path)
d = metal_device()
out = metal_buffer(d, 128 * 4)
metal_fp8_e4m3_gather_rows(out, [m, m], [0, 64], 64, ~0.25)

i = 0
while i < 128
  b = m.byte_at(i)
  sign = (b & 128) != 0 ? ~0.0 - 1.0 : ~1.0
  ex = (b >> 3) & 15
  man = b & 7
  if ex == 0
    want = sign * ((~0.0 + man) / 8.0) * Math.pow(2.0, ~0.0 - 6.0)
  else
    want = sign * (~1.0 + (~0.0 + man) / 8.0) * Math.pow(2.0, ~0.0 + ex - 7.0)
  want = want * ~0.25
  got = metal_buffer_read_f32(out, i)
  if got != want
    raise "fp8 gather mismatch at " + i.to_s + ": " + got.to_s + " != " + want.to_s
  i = i + 1
<< "metal fp8 gather smoke: PASS"
