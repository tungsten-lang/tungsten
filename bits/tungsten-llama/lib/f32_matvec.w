# F32 matvec: y[N] = W[N, K] @ x[K]. Used for the MoE router (qwen3
# stores ffn_gate_inp.weight as F32) and any other small F32 weight.
#
# Cooperative shape: one threadgroup per output row, 32 lanes splitting
# the K-dim. Same pattern as q8_matvec_coop, but reading float weights
# directly — no dequant.

## f32[]: w
## f32[]: x
## f32[]: y
## i32: k_dim
@gpu fn f32_matvec(w, x, y, k_dim)
  m = gpu.threadgroup_position_in_grid.x ## i32
  lane = gpu.thread_index_in_simdgroup ## i32
  partial = 0.0 ## f32
  i = lane ## i32
  while i < k_dim
    partial = partial + w[m * k_dim + i] * x[i]
    i = i + 32
  total = simd_sum(partial) ## f32
  if lane == 0
    y[m] = total
