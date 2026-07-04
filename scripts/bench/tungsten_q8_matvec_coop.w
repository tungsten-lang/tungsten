# V_coop: Q8_0 matvec with simdgroup-cooperative reduction.
# 32 threads per output row (one SIMD group), each lane handles
# nb/32 blocks, then simd_sum reduces partials.
#
# Dispatched as `n_groups = n_rows`, `threads_per_group = 32`.
# Each threadgroup is one simdgroup on Apple Silicon.
#
# Build on top of V2 (packed quants i32[]) since that's the per-thread
# inner-loop winner.

use core/metal

## i32[]: w_q
## f16[]: w_s
## f32[]: x
## f32[]: y
## i32: k_dim
@gpu fn q8_matvec_coop(w_q, w_s, x, y, k_dim)
  m = gpu.threadgroup_position_in_grid.x ## i32
  lane = gpu.thread_index_in_simdgroup ## i32
  nb = k_dim / 32 ## i32
  ints_per_row = k_dim / 4 ## i32

  partial = 0.0 ## f32
  b = lane ## i32
  while b < nb
    s = w_s[m * nb + b] ## f16
    block_acc = 0.0 ## f32
    row_off = m * ints_per_row + b * 8 ## i32
    x_off = b * 32 ## i32
    i = 0 ## i32
    while i < 8
      packed = w_q[row_off + i] ## i32
      block_acc = block_acc + ((packed << 24) >> 24) * x[x_off + i * 4] + ((packed << 16) >> 24) * x[x_off + i * 4 + 1] + ((packed << 8) >> 24) * x[x_off + i * 4 + 2] + (packed >> 24) * x[x_off + i * 4 + 3]
      i = i + 1
    partial = partial + s * block_acc
    b = b + 32

  # SIMD-group reduction: sum the 32 lane partials.
  total = simd_sum(partial) ## f32

  # Lane 0 writes the output.
  if lane == 0
    y[m] = total

msl = read_file("scripts/bench/tungsten_q8_matvec_coop.metal")
device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "q8_matvec_coop")

n_rows = 151936
k_cols = 2048
nb = k_cols / 32

w_q_buf = metal_buffer(device, n_rows * k_cols)
w_s_buf = metal_buffer(device, n_rows * nb * 2)
x_buf   = metal_buffer(device, k_cols * 4)
y_buf   = metal_buffer(device, n_rows * 4)
k_buf   = metal_buffer(device, 4)

total_q_words = (n_rows * k_cols) / 4
i = 0
while i < total_q_words
  metal_buffer_write_i32(w_q_buf, i, 0x01010101)
  i = i + 1
total_s_words = (n_rows * nb) / 2
i = 0
while i < total_s_words
  metal_buffer_write_i32(w_s_buf, i, 0x3C003C00)
  i = i + 1
i = 0
while i < k_cols
  metal_buffer_write_f32(x_buf, i, ~1.0)
  i = i + 1
metal_buffer_write_i32(k_buf, 0, k_cols)

queue = metal_queue(device)
bufs = [w_q_buf, w_s_buf, x_buf, y_buf, k_buf]

# 32 threads per output row, n_rows threadgroups.
i = 0
while i < 5
  metal_dispatch_groups(queue, pipeline, bufs, n_rows, 32)
  i = i + 1

expected_f = k_cols.to_f
ok = true
i = 0
while i < n_rows
  v = metal_buffer_read_f32(y_buf, i)
  diff = v - expected_f
  if diff > ~0.001
    ok = false
  if diff < ~-0.001
    ok = false
  i = i + 1
if !ok
  << "FAIL coop y\[0]=" + metal_buffer_read_f32(y_buf, 0).to_s + " expected=" + expected_f.to_s
  exit 1

weight_bytes = n_rows * nb * 34
bytes_per_call = weight_bytes + k_cols * 4 + n_rows * 4
iters = 50
t0 = clock
i = 0
while i < iters
  metal_dispatch_groups(queue, pipeline, bufs, n_rows, 32)
  i = i + 1
elapsed = clock - t0
per_call_ms = elapsed * ~1000.0 / iters.to_f
gb_per_s = bytes_per_call.to_f * iters.to_f / elapsed / ~1.0e9
<< "coop K=" + k_cols.to_s + " N=" + n_rows.to_s + " per_call_ms=" + per_call_ms.to_s + " gb_per_s=" + gb_per_s.to_s
