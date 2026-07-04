# Fused per-head RMSNorm + NEOX-style RoPE that writes the output
# directly into a row of the K cache at (pos * row_size). Replaces the
# (per_head_norm_rope → kv_write_k) pair for the K side.
#
# Reads from k_now (the k_proj output, in-place not allowed), normalizes
# per-head with w, applies rope, writes the rotated values into
# cache[pos * row_size + base + ...].
#
# row_size is n_kv_heads * head_dim. base = h * head_dim within the row.

## f32[]: k_now
## f32[]: w
## f32[]: cos_tab
## f32[]: sin_tab
## f32[]: cache
## i32: head_dim
## i32: head_dim_half
## i32: pos
## i32: row_size
## f32: inv_d
## f32: eps
@gpu fn per_head_norm_rope_to_cache(k_now, w, cos_tab, sin_tab, cache, head_dim, head_dim_half, pos, row_size, inv_d, eps)
  h = gpu.threadgroup_position_in_grid.x ## i32
  lane = gpu.thread_index_in_simdgroup ## i32
  base = h * head_dim ## i32
  cache_base = pos * row_size + base ## i32

  sum_sq = 0.0 ## f32
  i = lane ## i32
  while i < head_dim
    v = k_now[base + i] ## f32
    sum_sq = sum_sq + v * v
    i = i + 32
  total = simd_sum(sum_sq) ## f32
  rrms = ~1.0 / sqrt(total * inv_d + eps) ## f32

  p = lane ## i32
  while p < head_dim_half
    a = k_now[base + p] * rrms * w[p] ## f32
    b = k_now[base + p + head_dim_half] * rrms * w[p + head_dim_half] ## f32
    c = cos_tab[p] ## f32
    s = sin_tab[p] ## f32
    cache[cache_base + p] = a * c - b * s
    cache[cache_base + p + head_dim_half] = a * s + b * c
    p = p + 32
