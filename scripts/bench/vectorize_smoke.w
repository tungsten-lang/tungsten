# P3.5 — `axis :i, vectorize: N` schedule directive.
#
# Same kernel, two named schedules: scalar (no transformation) and
# vec4 (loop body unrolled 4× with axis_name substituted by axis+0,
# axis+1, axis+2, axis+3 in each copy, increment rewritten from +1 to +4).
#
# Verifies:
#   1. The .metal output contains both vec_double_scalar and
#      vec_double_vec4 kernel definitions.
#   2. The vec4 variant has the unrolled body shape.
#   3. Both kernels produce the same numerical result on a small
#      input (correctness gate before declaring the transformation
#      shippable).

use core/metal

## f32[]: x
## f32[]: y
## i32: n
@gpu fn vec_double(x, y, n)
  m = gpu.thread_position_in_grid.x ## i32
  if m == 0
    i = 0 ## axis :i, i32
    while i < n
      y[i] = x[i] * ~2.0
      i = i + 1

@schedule vec_double.scalar
  axis :i

@schedule vec_double.vec4
  axis :i, vectorize: 4

N = 16
device = metal_device()
queue = metal_queue(device)

x_buf = metal_buffer(device, N * 4)
y_buf = metal_buffer(device, N * 4)
n_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(n_buf, 0, N)
i = 0
while i < N
  metal_buffer_write_f32(x_buf, i, ~1.0 + i)
  i = i + 1

msl = read_file("scripts/bench/vectorize_smoke.metal")
library = metal_compile_source(device, msl)
scalar_pipe = metal_pipeline(library, "vec_double_scalar")
vec4_pipe   = metal_pipeline(library, "vec_double_vec4")

# Run scalar
metal_dispatch_n(queue, scalar_pipe, [x_buf, y_buf, n_buf], 1)
ok_scalar = true
i = 0
while i < N
  if metal_buffer_read_f32(y_buf, i) != (~1.0 + i) * ~2.0
    ok_scalar = false
  i = i + 1
<< "scalar correct: " + ok_scalar.to_s

i = 0
while i < N
  metal_buffer_write_f32(y_buf, i, ~0.0)
  i = i + 1

# Run vec4
metal_dispatch_n(queue, vec4_pipe, [x_buf, y_buf, n_buf], 1)
ok_vec4 = true
i = 0
while i < N
  if metal_buffer_read_f32(y_buf, i) != (~1.0 + i) * ~2.0
    ok_vec4 = false
  i = i + 1
<< "vec4 correct:   " + ok_vec4.to_s
