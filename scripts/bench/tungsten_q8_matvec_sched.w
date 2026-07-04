# Bench the schedule-generated cooperative kernel.
# Same algorithm as bits/tungsten-llama/lib/q8_matvec.w; the @schedule
# block declaratively produces the cooperative MSL — should match the
# hand-tuned coop perf within noise.

use core/metal

## i32[]: w_q
## f16[]: w_s
## f32[]: x
## f32[]: y
## i32: k_dim
@gpu fn q8_matvec(w_q, w_s, x, y, k_dim)
  m = gpu.thread_position_in_grid.x ## axis :m
  nb = k_dim / 32 ## i32
  acc = 0.0 ## f32
  ints_per_row = k_dim / 4 ## i32
  b = 0 ## axis :b, i32
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
    acc = acc + s * block_acc
    b = b + 1
  y[m] = acc

@schedule q8_matvec.coop
  axis :m, parallelize: :threadgroup
  axis :b, parallelize: :simdgroup_lane, stride: 32
  axis :b, reduce: :simd_sum, into: :acc

msl = read_file("scripts/bench/tungsten_q8_matvec_sched.metal")
device = metal_device()
library = metal_compile_source(device, msl)
# Pick the schedule-generated coop variant (not the default).
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

# Cooperative kernel: 32 threads per output row.
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
  << "FAIL"
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
<< "sched-coop K=" + k_cols.to_s + " N=" + n_rows.to_s + " per_call_ms=" + per_call_ms.to_s + " gb_per_s=" + gb_per_s.to_s
