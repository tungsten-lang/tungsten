# @schedule unroll smoke — the schedule language end-to-end.
#
# scale4 doubles 4 elements per thread inside a while loop whose
# induction variable carries the `## axis :i` tag; the @schedule block
# below unrolls that loop 4x into the scale4_unrolled variant. This
# spec dispatches the UNROLLED kernel on the device and checks the
# output, exercising the whole schedule chain: axis tag (parser sparse
# field) → schedule match → kernel deep-clone → i+k substitution →
# increment rewrite → MSL emission → runtime dispatch.
#
# Like metal_kernel_spec.w, the .metal sidecar lands next to this file
# when compiled as `tungsten compile spec/core/schedule_unroll_spec.w --ll`.

use core/metal

## f32[]: x
## f32[]: y
## i32: n
@gpu fn scale4(x, y, n)
  tid = gpu.thread_position_in_grid.x ## i32
  base = tid * 4
  i = 0 ## axis :i
  while i < 4
    y[base + i] = x[base + i] * 2.0
    i = i + 1

@schedule scale4.unrolled
  axis :i, vectorize: 4

msl = read_file("spec/core/schedule_unroll_spec.metal")

device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "scale4_unrolled")

# 8 floats = 2 threads x 4 elements each.
input = metal_buffer(device, 32)
output = metal_buffer(device, 32)
n_buf = metal_buffer(device, 4)
metal_buffer_write_f32(input, 0, ~1.0)
metal_buffer_write_f32(input, 1, ~2.0)
metal_buffer_write_f32(input, 2, ~3.0)
metal_buffer_write_f32(input, 3, ~4.0)
metal_buffer_write_f32(input, 4, ~5.0)
metal_buffer_write_f32(input, 5, ~6.0)
metal_buffer_write_f32(input, 6, ~7.0)
metal_buffer_write_f32(input, 7, ~8.0)
metal_buffer_write_i32(n_buf, 0, 8)

queue = metal_queue(device)
metal_dispatch1(queue, pipeline, input, output, n_buf, 2)

a = metal_buffer_read_f32(output, 0)
b = metal_buffer_read_f32(output, 3)
c = metal_buffer_read_f32(output, 4)
d = metal_buffer_read_f32(output, 7)

if a == ~2.0 && b == ~8.0 && c == ~10.0 && d == ~16.0
  << "schedule unroll ok"
else
  << "schedule unroll FAILED"
  << a.to_s
  << b.to_s
  << c.to_s
  << d.to_s
  exit 1
