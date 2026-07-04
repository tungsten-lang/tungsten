# F16 matvec — qwen3 stores attn_v.weight as F16 (slightly higher
# precision than Q8 for the value path). Same cooperative shape as
# f32_matvec; reads `half` weights and accumulates in float.

## f16[]: w
## f32[]: x
## f32[]: y
## i32: k_dim
@gpu fn f16_matvec(w, x, y, k_dim)
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
