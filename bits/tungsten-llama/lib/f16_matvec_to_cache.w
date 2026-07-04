# F16 matvec that writes directly into a row of a cache buffer at
# offset (pos * row_size). Fuses v_proj + kv_write_v: eliminates the
# v_buf round-trip, saving one dispatch per layer.

## f16[]: w
## f32[]: x
## f32[]: cache
## i32: k_dim
## i32: pos
## i32: row_size
@gpu fn f16_matvec_to_cache(w, x, cache, k_dim, pos, row_size)
  m = gpu.threadgroup_position_in_grid.x ## i32
  lane = gpu.thread_index_in_simdgroup ## i32
  partial = 0.0 ## f32
  i = lane ## i32
  while i < k_dim
    partial = partial + w[m * k_dim + i] * x[i]
    i = i + 32
  total = simd_sum(partial) ## f32
  if lane == 0
    cache[pos * row_size + m] = total
