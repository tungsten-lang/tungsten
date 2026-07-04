# Optimized Q8_0 matvec — packed-quant reads.
#
# Differs from the baseline `q8_matvec` (bits/tungsten-llama/lib/q8_matvec.w)
# only in the w_q buffer layout: i32 packed (4 i8 quants per word) instead
# of plain i8. Each load-word feeds 4 multiplies; bytes are unpacked with
# arithmetic-right-shift sign extend.
#
# Layout:
#   w_q: i32[] of length N * K / 4   (4 quants per i32, little-endian)
#   w_s: f16[] of length N * K/32    (unchanged, one scale per Q8_0 block)
#   x:   f32[] of length K           (unchanged)
#   y:   f32[] of length N
#   k_dim: i32 (= K)
#
# Performance vs the i8[] baseline + llama.cpp's
# `kernel_mul_mv_q8_0_f32_nsg=4` on M3 Max (qwen3 lm_head, 2048×151936):
#   baseline                162 GB/s   (0.52× llama.cpp)
#   this kernel             273 GB/s   (0.88× llama.cpp)
# See bits/tungsten-llama/docs/q8-matvec-bakeoff.md for the full table.

## i32[]: w_q
## f16[]: w_s
## f32[]: x
## f32[]: y
## i32: k_dim
@gpu fn q8_matvec_packed(w_q, w_s, x, y, k_dim)
  m = gpu.thread_position_in_grid.x ## i32
  nb = k_dim / 32 ## i32
  ints_per_row = k_dim / 4 ## i32
  acc = 0.0 ## f32
  b = 0 ## i32
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
