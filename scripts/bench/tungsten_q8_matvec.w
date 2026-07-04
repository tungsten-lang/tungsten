# Phase 2 bakeoff: time the Tungsten Q8_0 matvec @gpu kernel.
# Pairs with bits/tungsten-llama/bench/llama_q8_matvec.c (same shape,
# same bytes touched, same all-1s pattern).
#
# Usage:
#   tungsten compile scripts/bench/tungsten_q8_matvec.w \
#     -o /tmp/tungsten_q8_bench --ll
#   codesign --force -s - /tmp/tungsten_q8_bench
#   /tmp/tungsten_q8_bench
#
# Edit n_rows / k_cols below to match the llama.cpp side. Defaults are
# the qwen3 lm_head shape (compute-bound, dispatch overhead negligible).

use core/metal

## i8[]: w_q
## f16[]: w_s
## f32[]: x
## f32[]: y
## i32: k_dim
@gpu fn q8_matvec(w_q, w_s, x, y, k_dim)
  m = gpu.thread_position_in_grid.x ## i32
  nb = k_dim / 32 ## i32
  acc = 0.0 ## f32
  b = 0 ## i32
  while b < nb
    s = w_s[m * nb + b] ## f16
    block_acc = 0.0 ## f32
    j = 0 ## i32
    while j < 32
      block_acc = block_acc + w_q[m * k_dim + b * 32 + j] * x[b * 32 + j]
      j = j + 1
    acc = acc + s * block_acc
    b = b + 1
  y[m] = acc

msl = read_file("scripts/bench/tungsten_q8_matvec.metal")

device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "q8_matvec")

n_rows = 151936
k_cols = 2048
nb = k_cols / 32

w_q_buf = metal_buffer(device, n_rows * k_cols)
w_s_buf = metal_buffer(device, n_rows * nb * 2)
x_buf   = metal_buffer(device, k_cols * 4)
y_buf   = metal_buffer(device, n_rows * 4)
k_buf   = metal_buffer(device, 4)

# Fill: every quant = 1 (0x01010101 i32), every scale = 1.0 (f16 0x3C00,
# packed two per i32 = 0x3C003C00). Then dequantized W = 1 everywhere,
# x = 1.0, so y[m] == k_cols for all m — easy correctness check.
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

# Warmup (compiles + caches the pipeline, settles thermals).
i = 0
while i < 5
  metal_dispatch_n(queue, pipeline, bufs, n_rows)
  i = i + 1

# Correctness sanity-check: y[m] should equal k_cols (all 1s × all 1s
# × 1.0 scale × k_cols), within float tolerance.
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
  << "FAIL correctness"
  exit 1

# Bytes per dispatch matches llama.cpp accounting (Q8_0):
#   weights = N * (K/32) * 34   (i8 quants + f16 scale per block)
#   x f32   = K * 4
#   y f32   = N * 4
weight_bytes = n_rows * nb * 34
input_bytes  = k_cols * 4
output_bytes = n_rows * 4
bytes_per_call = weight_bytes + input_bytes + output_bytes

iters = 50
t0 = clock
i = 0
while i < iters
  metal_dispatch_n(queue, pipeline, bufs, n_rows)
  i = i + 1
elapsed = clock - t0

per_call_ms = elapsed * ~1000.0 / iters.to_f
total_bytes = bytes_per_call.to_f * iters.to_f
gb_per_s = total_bytes / elapsed / ~1.0e9

<< "tungsten K=" + k_cols.to_s + " N=" + n_rows.to_s + " per_call_ms=" + per_call_ms.to_s + " gb_per_s=" + gb_per_s.to_s
