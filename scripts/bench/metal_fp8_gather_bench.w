# Matched host-throughput benchmark for FlashNext's 16 x 160 FP8 PLE gather.
# Compares the former scalar Mmap#byte_at + Metal write bridge loop with the
# bulk checked runtime call. Both write the same shared f32 buffer shape.

use core/metal

path = "/tmp/tungsten-metal-fp8-gather-bench.bin"
File.write(path, "é" * 1280) # 2560 UTF-8 bytes = 16 rows x 160
m = File.mmap(path)
d = metal_device()
scalar_out = metal_buffer(d, 2560 * 4)
bulk_out = metal_buffer(d, 2560 * 4)
mmaps = []
offsets = []
h = 0
while h < 16
  mmaps.push(m)
  offsets.push(h * 160)
  h = h + 1

lut = []
i = 0
while i < 256
  sign = (i & 128) != 0 ? ~0.0 - 1.0 : ~1.0
  ex = (i >> 3) & 15
  man = i & 7
  if ex == 0
    v = sign * ((~0.0 + man) / 8.0) * Math.pow(2.0, ~0.0 - 6.0)
  else
    v = sign * (~1.0 + (~0.0 + man) / 8.0) * Math.pow(2.0, ~0.0 + ex - 7.0)
  lut.push(v * ~0.25)
  i = i + 1

-> scalar_gather(m, dst, lut)
  i = 0
  while i < 2560
    metal_buffer_write_f32(dst, i, lut[m.byte_at(i)])
    i = i + 1

scalar_gather(m, scalar_out, lut)
metal_fp8_e4m3_gather_rows(bulk_out, mmaps, offsets, 160, ~0.25)
i = 0
while i < 2560
  if metal_buffer_read_f32(scalar_out, i) != metal_buffer_read_f32(bulk_out, i)
    raise "bulk gather mismatch at " + i.to_s
  i = i + 1

rounds = 10000
t0 = ccall("__w_clock_ms")
r = 0
while r < rounds
  scalar_gather(m, scalar_out, lut)
  r = r + 1
scalar_ms = ccall("__w_clock_ms") - t0

t0 = ccall("__w_clock_ms")
r = 0
while r < rounds
  metal_fp8_e4m3_gather_rows(bulk_out, mmaps, offsets, 160, ~0.25)
  r = r + 1
bulk_ms = ccall("__w_clock_ms") - t0

<< "scalar " + scalar_ms.to_s + " ms; bulk " + bulk_ms.to_s + " ms; speedup " + (scalar_ms / bulk_ms).to_s + "x"
