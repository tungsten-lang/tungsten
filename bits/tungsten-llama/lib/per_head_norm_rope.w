# Fused per-head RMSNorm + NEOX-style RoPE for Q or K projections.
# Replaces the (per_head_norm → rope_neox) pair, saving 2 dispatches
# per layer × 48 = 96/token for Q+K.
#
# Decomposition: one threadgroup per head, 32 lanes. Each lane owns
# 4 elements striped (lane, lane+32, lane+64, lane+96). Since
# head_dim=128 and head_dim_half=64, each lane's 4 elements form 2
# disjoint RoPE pairs: (lane, lane+64) and (lane+32, lane+96).
# No cross-lane sync needed for the rope phase.
#
# Phases:
#   1. each lane sums squares of its 4 elements; simd_sum → row total;
#      rrms = 1/sqrt(total*inv_d + eps)
#   2. each lane reads its 2 pairs, applies (norm * w) then rope,
#      writes back to x in place.

## f32[]: x
## f32[]: w
## f32[]: cos_tab
## f32[]: sin_tab
## i32: head_dim
## i32: head_dim_half
## f32: inv_d
## f32: eps
@gpu fn per_head_norm_rope(x, w, cos_tab, sin_tab, head_dim, head_dim_half, inv_d, eps)
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

  # Each lane processes pairs at (lane, lane+head_dim_half) and
  # (lane+32, lane+32+head_dim_half). The second pair only exists when
  # lane+32 < head_dim_half (i.e. head_dim_half > 32). For head_dim=128
  # head_dim_half=64 this is always true.
  p = lane ## i32
  while p < head_dim_half
    lo_off = base + p ## i32
    hi_off = lo_off + head_dim_half ## i32
    a = x[lo_off] * rrms * w[p] ## f32
    b = x[hi_off] * rrms * w[p + head_dim_half] ## f32
    c = cos_tab[p] ## f32
    s = sin_tab[p] ## f32
    x[lo_off] = a * c - b * s
    x[hi_off] = a * s + b * c
    p = p + 32
