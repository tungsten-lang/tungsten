# Residual add: a[i] += b[i]. Used for the two residual connections
# per transformer block (after attn_proj and after ffn).

## f32[]: a
## f32[]: b
## i32: n
@gpu fn residual_add(a, b, n)
  i = gpu.thread_position_in_grid.x ## i32
  if i < n
    a[i] = a[i] + b[i]
