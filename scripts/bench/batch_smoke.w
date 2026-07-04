# Smoke: batched dispatch produces same result as per-dispatch commit.
# Two chained passes of residual_add (a += b) — once eager, once batched.
# Both should produce a[i] = original_a[i] + 2 * b[i].

use core/metal

N = 64

device = metal_device()
queue = metal_queue(device)
add_pipe = metal_pipeline(metal_compile_source(device, read_file("bits/tungsten-llama/lib/residual_add.metal")), "residual_add")

a_buf = metal_buffer(device, N * 4)
b_buf = metal_buffer(device, N * 4)
n_buf = metal_buffer(device, 4)
metal_buffer_write_i32(n_buf, 0, N)
i = 0
while i < N
  metal_buffer_write_f32(a_buf, i, ~10.0)
  metal_buffer_write_f32(b_buf, i, ~3.0)
  i = i + 1

# Eager: two dispatches with implicit commit/wait each.
metal_dispatch_n(queue, add_pipe, [a_buf, b_buf, n_buf], N)
metal_dispatch_n(queue, add_pipe, [a_buf, b_buf, n_buf], N)

# Verify a = 10 + 3 + 3 = 16
all_ok = true
i = 0
while i < N
  v = metal_buffer_read_f32(a_buf, i)
  if v != ~16.0
    all_ok = false
  i = i + 1
<< "eager 2x add: " + (all_ok ? "OK" : "FAIL")

# Reset
i = 0
while i < N
  metal_buffer_write_f32(a_buf, i, ~10.0)
  i = i + 1

# Batched: two dispatches in one command buffer, one commit/wait.
metal_batch_begin(queue)
metal_dispatch_n(queue, add_pipe, [a_buf, b_buf, n_buf], N)
metal_dispatch_n(queue, add_pipe, [a_buf, b_buf, n_buf], N)
metal_batch_commit(queue)

all_ok = true
i = 0
while i < N
  v = metal_buffer_read_f32(a_buf, i)
  if v != ~16.0
    all_ok = false
  i = i + 1
<< "batched 2x add: " + (all_ok ? "OK" : "FAIL")
