# Cooperative Q8_0 matvec — 32-thread simdgroup reduction.
#
# Algorithm: y[N] = W[N, K] @ x[K], W stored as Q8_0 (i8 quants + f16
# scale per 32-element block). Same math as q8_matvec.w; difference
# is the parallelization.
#
# Schedule:
#   - One threadgroup per output row (m = threadgroup_position_in_grid.x).
#   - 32 threads per threadgroup — exactly one SIMD group on Apple GPUs.
#   - Each lane handles blocks {lane, lane+32, lane+64, ...} — strided so
#     it works for any nb (not just multiples of 32).
#   - simd_sum reduces the 32 lane partials in registers.
#   - Lane 0 writes y[m].
#
# Layout matches q8_matvec_packed.w:
#   w_q: i32[] of length N * K / 4   (4 quants per i32, little-endian)
#   w_s: f16[] of length N * K/32
#   x:   f32[] of length K
#   y:   f32[] of length N
#   k_dim: i32 (= K)
#
# Dispatched with `metal_dispatch_groups(queue, pipeline, bufs, N, 32)`.
#
# Performance vs llama.cpp's `kernel_mul_mv_q8_0_f32_nsg=4` on M3 Max
# (qwen3 lm_head, 2048×151936): coop hits 323 GB/s vs llama.cpp's 320
# (1.01×). Beats llama.cpp at every measured qwen3 hot-path shape; see
# bits/tungsten-llama/docs/q8-matvec-bakeoff.md for the table.

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

  total = simd_sum(partial) ## f32

  if lane == 0
    y[m] = total
