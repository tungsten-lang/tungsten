# Per-expert Q8_0 matvec — same algorithm as q8_matvec_coop, but the
# weight buffer holds n_experts contiguous Q8_0 matrices and an i32
# `expert_idx` selects which one to use for this dispatch.
#
# Layout: w_q is i32[n_experts * n_rows * k_dim/4], w_s is f16[n_experts
# * n_rows * k_dim/32]. Each expert occupies one stride exactly. Caller
# computes which expert via top-k routing on the CPU.
#
# Same dispatch shape as q8_matvec_coop: n_rows threadgroups × 32 lanes.

## i32[]: w_q
## f16[]: w_s
## f32[]: x
## f32[]: y
## i32: k_dim
## i32: n_rows
## i32: expert_idx
@gpu fn q8_matvec_expert(w_q, w_s, x, y, k_dim, n_rows, expert_idx)
  m = gpu.threadgroup_position_in_grid.x ## i32
  lane = gpu.thread_index_in_simdgroup ## i32
  nb = k_dim / 32 ## i32
  ints_per_row = k_dim / 4 ## i32

  scales_per_expert = n_rows * nb ## i32
  ints_per_expert = n_rows * ints_per_row ## i32
  s_base = expert_idx * scales_per_expert ## i32
  q_base = expert_idx * ints_per_expert ## i32

  partial = 0.0 ## f32
  b = lane ## i32
  while b < nb
    s = w_s[s_base + m * nb + b] ## f16
    block_acc = 0.0 ## f32
    row_off = q_base + m * ints_per_row + b * 8 ## i32
    x_off = b * 32 ## i32
    i = 0 ## i32
    while i < 8
      packed = w_q[row_off + i] ## i32
      block_acc = block_acc + ((packed << 24) >> 24) * x[x_off + i * 4] + ((packed << 16) >> 24) * x[x_off + i * 4 + 1] + ((packed << 8) >> 24) * x[x_off + i * 4 + 2] + (packed >> 24) * x[x_off + i * 4 + 3]
      i = i + 1
    partial = partial + s * block_acc
    b = b + 32

  total = simd_sum(partial) ## f32

  if lane == 0
    y[m] = total
