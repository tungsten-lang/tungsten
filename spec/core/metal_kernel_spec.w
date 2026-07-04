# Phase 0 kernel provenance smoke — `@gpu fn` end-to-end.
#
# Compiles add_one to MSL, runtime-compiles the .metal, builds a
# pipeline, fills `[1.0, 2.0, 3.0]` into an input buffer, dispatches
# threads=3, asserts the output buffer reads back as `[2, 3, 4]`.
#
# Pinned by the rspec equivalent in
# implementations/ruby/spec/compiler_regression_spec.rb so CI catches the
# regression even when this .w file isn't run directly. Run manually
# on any darwin machine:
#
#   tungsten compile spec/core/metal_kernel_spec.w --out /tmp/smoke && /tmp/smoke

use core/metal

## f32[]: x
## f32[]: y
## i32: n
@gpu fn add_one(x, y, n)
  i = gpu.thread_position_in_grid.x ## i32
  if i < n
    y[i] = x[i] + 1.0

# The compiler emits a sibling .metal next to the .ll. When invoked
# as `tungsten compile spec/core/metal_kernel_spec.w --ll`, the
# sidecar lands at spec/core/metal_kernel_spec.metal.
msl = read_file("spec/core/metal_kernel_spec.metal")

device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "add_one")

input = metal_buffer(device, 12)
output = metal_buffer(device, 12)
n_buf = metal_buffer(device, 4)
metal_buffer_write_f32(input, 0, ~1.0)
metal_buffer_write_f32(input, 1, ~2.0)
metal_buffer_write_f32(input, 2, ~3.0)
metal_buffer_write_i32(n_buf, 0, 3)

queue = metal_queue(device)
metal_dispatch1(queue, pipeline, input, output, n_buf, 3)

a = metal_buffer_read_f32(output, 0)
b = metal_buffer_read_f32(output, 1)
c = metal_buffer_read_f32(output, 2)

if a == ~2.0 && b == ~3.0 && c == ~4.0
  << "metal smoke ok"
else
  << "metal smoke FAILED"
  << "got "
  << a.to_s
  << b.to_s
  << c.to_s
  exit 1
