# Fused Q8_0 gate + up matvec for one MoE expert.
#
# Computes y_gate[] = W_gate[expert] @ x and y_up[] = W_up[expert] @ x
# in a single kernel pass. Both projections read the same `x` vector,
# so doing them together lets the GPU reuse x in registers across both
# accumulators — halves the L1 traffic on x, and doubles the arithmetic
# intensity per byte of x read.
#
# Same cooperative shape as q8_matvec_expert: one threadgroup per output
# row `m`, 32 lanes covering the K-dim stride. Apple's M-series GPU
# typically runs one threadgroup per SIMD cluster, so fusing two matvecs
# into one dispatch also halves the threadgroup-launch overhead.
#
# Dispatch: n_rows threadgroups × 32 lanes (same as q8_matvec_expert).
# Caller provides both weight tensors' quants/scales and the single shared
# x buffer; kernel writes to y_gate and y_up at the same row index.

## i32[]: w_q_gate
## f16[]: w_s_gate
## i32[]: w_q_up
## f16[]: w_s_up
## f32[]: x
## f32[]: y_gate
## f32[]: y_up
## i32: k_dim
## i32: n_rows
## i32: expert_idx
@gpu fn q8_matvec_gate_up_expert(w_q_gate, w_s_gate, w_q_up, w_s_up, x, y_gate, y_up, k_dim, n_rows, expert_idx)
  m = gpu.threadgroup_position_in_grid.x ## i32
  lane = gpu.thread_index_in_simdgroup ## i32
  nb = k_dim / 32 ## i32
  ints_per_row = k_dim / 4 ## i32

  scales_per_expert = n_rows * nb ## i32
  ints_per_expert = n_rows * ints_per_row ## i32
  s_base = expert_idx * scales_per_expert ## i32
  q_base = expert_idx * ints_per_expert ## i32

  partial_g = 0.0 ## f32
  partial_u = 0.0 ## f32
  b = lane ## i32
  while b < nb
    s_g = w_s_gate[s_base + m * nb + b] ## f16
    s_u = w_s_up[s_base + m * nb + b] ## f16
    block_g = 0.0 ## f32
    block_u = 0.0 ## f32
    row_off = q_base + m * ints_per_row + b * 8 ## i32
    x_off = b * 32 ## i32
    i = 0 ## i32
    while i < 8
      pg = w_q_gate[row_off + i] ## i32
      pu = w_q_up[row_off + i] ## i32
      x0 = x[x_off + i * 4] ## f32
      x1 = x[x_off + i * 4 + 1] ## f32
      x2 = x[x_off + i * 4 + 2] ## f32
      x3 = x[x_off + i * 4 + 3] ## f32
      block_g = block_g + ((pg << 24) >> 24) * x0 + ((pg << 16) >> 24) * x1 + ((pg << 8) >> 24) * x2 + (pg >> 24) * x3
      block_u = block_u + ((pu << 24) >> 24) * x0 + ((pu << 16) >> 24) * x1 + ((pu << 8) >> 24) * x2 + (pu >> 24) * x3
      i = i + 1
    partial_g = partial_g + s_g * block_g
    partial_u = partial_u + s_u * block_u
    b = b + 32

  total_g = simd_sum(partial_g) ## f32
  total_u = simd_sum(partial_u) ## f32

  if lane == 0
    y_gate[m] = total_g
    y_up[m] = total_u
