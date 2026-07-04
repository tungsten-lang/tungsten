# P2.2 smoke: variable-buffer Metal dispatch via metal_dispatch_n.
# Five buffers (a, b, c, out, n) bound at slots 0..4 in array order.
# Compile with `--ll` so the .metal sidecar lands next to the .w.

use core/metal

## f32[]: a
## f32[]: b
## f32[]: c
## f32[]: out
## i32: n
@gpu fn add4(a, b, c, out, n)
  i = gpu.thread_position_in_grid.x ## i32
  if i < n
    out[i] = a[i] + b[i] + c[i]

msl = read_file("spec/core/metal_dispatch_n_spec.metal")

device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "add4")

a_buf = metal_buffer(device, 12)
b_buf = metal_buffer(device, 12)
c_buf = metal_buffer(device, 12)
out_buf = metal_buffer(device, 12)
n_buf = metal_buffer(device, 4)
metal_buffer_write_f32(a_buf, 0, ~1.0)
metal_buffer_write_f32(a_buf, 1, ~2.0)
metal_buffer_write_f32(a_buf, 2, ~3.0)
metal_buffer_write_f32(b_buf, 0, ~10.0)
metal_buffer_write_f32(b_buf, 1, ~20.0)
metal_buffer_write_f32(b_buf, 2, ~30.0)
metal_buffer_write_f32(c_buf, 0, ~100.0)
metal_buffer_write_f32(c_buf, 1, ~200.0)
metal_buffer_write_f32(c_buf, 2, ~300.0)
metal_buffer_write_i32(n_buf, 0, 3)

queue = metal_queue(device)
metal_dispatch_n(queue, pipeline, [a_buf, b_buf, c_buf, out_buf, n_buf], 3)

r0 = metal_buffer_read_f32(out_buf, 0)
r1 = metal_buffer_read_f32(out_buf, 1)
r2 = metal_buffer_read_f32(out_buf, 2)

if r0 == ~111.0 && r1 == ~222.0 && r2 == ~333.0
  << "dispatch_n smoke ok"
else
  << "FAIL dispatch_n: " + r0.to_s + " " + r1.to_s + " " + r2.to_s
  exit 1
