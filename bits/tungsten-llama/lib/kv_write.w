# Write the current step's K and V into the KV cache at position pos.
# K cache layout: [max_pos, n_kv_heads * head_dim] f32 row-major.
# Same for V cache. Each row is contiguous (n_kv_heads * head_dim
# floats); pos selects the row.

## f32[]: k_now
## f32[]: cache
## i32: pos
## i32: row_size
@gpu fn kv_write(k_now, cache, pos, row_size)
  i = gpu.thread_position_in_grid.x ## i32
  if i < row_size
    cache[pos * row_size + i] = k_now[i]
