# RMSNorm applied independently to each [head_dim]-length chunk of a
# vector. qwen3 normalizes Q and K per-head with separate weight
# vectors (attn_q_norm, attn_k_norm both length head_dim=128).
#
# Layout: x is [n_heads * head_dim] flat, w is [head_dim] (broadcast
# across all heads). Dispatch one threadgroup per head, 32 lanes
# splitting the head_dim reduction.

## f32[]: x
## f32[]: w
## i32: head_dim
## f32: inv_d
## f32: eps
@gpu fn per_head_norm(x, w, head_dim, inv_d, eps)
  h = gpu.threadgroup_position_in_grid.x ## i32
  lane = gpu.thread_index_in_simdgroup ## i32
  base = h * head_dim ## i32
  sum_sq = 0.0 ## f32
  i = lane ## i32
  while i < head_dim
    v = x[base + i] ## f32
    sum_sq = sum_sq + v * v
    i = i + 32
  total = simd_sum(sum_sq) ## f32
  rrms = ~1.0 / sqrt(total * inv_d + eps) ## f32
  i = lane
  while i < head_dim
    x[base + i] = x[base + i] * rrms * w[i]
    i = i + 32
