# Q8_0 matvec @gpu kernel — Phase 2 baseline.
#
# Layout:
#   y[N] = W[N, K] @ x[K]
# where W is stored as Q8_0 blocks of 32 weights:
#   - w_q: i8 quants, length N*K
#   - w_s: f16 scales, length N*(K/32) — one scale per block per row
#
# K must be a multiple of 32 (Q8_0 block size). Real qwen3 dims all
# satisfy this: K ∈ {768, 2048, 4096}.
#
# v0 strategy: one thread per output row m. Walks the row's K weights
# in 32-element blocks, dequantizing scale × quant on the fly and
# accumulating against x. No shared memory, no SIMD intrinsics, no
# threadgroup tiling — that's Phase 3 schedule-language territory.
# Correctness first; the bakeoff harness reports the GB/s gap and we
# iterate from there.

use core/metal

## i8[]: w_q
## f16[]: w_s
## f32[]: x
## f32[]: y
## i32: K
@gpu fn q8_matvec(w_q, w_s, x, y, K)
  m = gpu.thread_position_in_grid.x ## i32
  nb = K / 32 ## i32
  acc = 0.0 ## f32
  b = 0 ## i32
  while b < nb
    s = w_s[m * nb + b] ## f16
    block_acc = 0.0 ## f32
    j = 0 ## i32
    while j < 32
      block_acc = block_acc + w_q[m * K + b * 32 + j] * x[b * 32 + j]
      j = j + 1
    acc = acc + s * block_acc
    b = b + 1
  y[m] = acc
