# Exhaustive exactness smoke for the bulk host-resident FP8 E4M3 row gather.
# All 256 byte encodings are checked, including the +/- NaN sentinels that the
# FlashNext/NVFP4 finite convention maps to zero.

use core/metal

path = "/tmp/tungsten-metal-fp8-gather-smoke.bin"
bytes = u8[256]
i = 0
while i < 256
  bytes[i] = i
  i = i + 1
File.write_bytes(path, bytes)

m = File.mmap(path)
d = metal_device()
out = metal_buffer(d, 256 * 4)
metal_fp8_e4m3_gather_rows(out, [m], [0], 256, ~0.25)

i = 0
while i < 256
  b = m.byte_at(i)
  sign = (b & 128) != 0 ? ~0.0 - 1.0 : ~1.0
  ex = (b >> 3) & 15
  man = b & 7
  if ex == 15 && man == 7
    want = ~0.0
  elsif ex == 0
    want = sign * ((~0.0 + man) / 8.0) * Math.pow(2.0, ~0.0 - 6.0)
  else
    want = sign * (~1.0 + (~0.0 + man) / 8.0) * Math.pow(2.0, ~0.0 + ex - 7.0)
  want = want * ~0.25
  got = metal_buffer_read_f32(out, i)
  if got != want
    raise "fp8 gather mismatch at " + i.to_s + ": " + got.to_s + " != " + want.to_s
  i = i + 1
if metal_buffer_read_f32(out, 0x7f) != ~0.0 || metal_buffer_read_f32(out, 0xff) != ~0.0
  raise "fp8 gather sentinel convention mismatch"
<< "metal fp8 gather smoke: PASS"
