# P2.3 smoke: half/f16 input buffer in @gpu kernel. Reads f16, writes
# f32 (free promotion in MSL). Compile with `--ll` so the .metal
# sidecar lands next to the .w.

use core/metal

## f16[]: src
## f32[]: dst
## i32: n
@gpu fn f16_to_f32(src, dst, n)
  i = gpu.thread_position_in_grid.x ## i32
  if i < n
    dst[i] = src[i]

msl = read_file("spec/core/metal_f16_buffer_spec.metal")

device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "f16_to_f32")

src_buf = metal_buffer(device, 8)
dst_buf = metal_buffer(device, 16)
n_buf = metal_buffer(device, 4)

# Pack two f16s per i32 slot (LE byte order):
# slot 0 low half bytes 0-1 = 0x3C00 (1.0h), high half bytes 2-3 = 0x4000 (2.0h)
# slot 1 low half bytes 0-1 = 0xC200 (-3.0h), high half bytes 2-3 = 0x3800 (0.5h)
metal_buffer_write_i32(src_buf, 0, 0x40003C00)
metal_buffer_write_i32(src_buf, 1, 0x3800C200)
metal_buffer_write_i32(n_buf, 0, 4)

queue = metal_queue(device)
metal_dispatch_n(queue, pipeline, [src_buf, dst_buf, n_buf], 4)

r0 = metal_buffer_read_f32(dst_buf, 0)
r1 = metal_buffer_read_f32(dst_buf, 1)
r2 = metal_buffer_read_f32(dst_buf, 2)
r3 = metal_buffer_read_f32(dst_buf, 3)

if r0 == ~1.0 && r1 == ~2.0 && r2 == ~-3.0 && r3 == ~0.5
  << "f16 smoke ok"
else
  << "FAIL f16: " + r0.to_s + " " + r1.to_s + " " + r2.to_s + " " + r3.to_s
  exit 1
