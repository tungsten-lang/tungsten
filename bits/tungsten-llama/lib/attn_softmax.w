# Cooperative row-wise softmax. One threadgroup per row, TG_SIZE threads
# (TG-wide reduction via `tg_max`/`tg_sum` so the kernel scales with row
# length instead of being capped at one simdgroup of 32 lanes).
#
# Two-pass numerically-stable softmax:
#   1. find max across the row (tg_max reduces partials across all
#      simdgroups in the TG)
#   2. compute exp(x - max), sum across all threads (tg_sum)
#   3. each thread writes its own slice of x = exp(x - max) / sum
#
# Dispatch: n_q_heads threadgroups × TG_SIZE threads. Pick TG_SIZE based
# on expected row length n_pos: 32 for short (decode), 256+ for long
# context prefill (n_pos > 1000).

## f32[]: x
## i32: n
@gpu fn attn_softmax(x, n)
  tg_size = gpu.threads_per_threadgroup ## i32
  row = gpu.threadgroup_position_in_grid.x ## i32
  tid = gpu.thread_position_in_threadgroup.x ## i32
  base = row * n ## i32

  m_local = ~-1000000000.0 ## f32
  i = tid ## i32
  while i < n
    v = x[base + i] ## f32
    if v > m_local
      m_local = v
    i = i + tg_size
  m = tg_max(m_local) ## f32

  s_local = 0.0 ## f32
  i = tid
  while i < n
    s_local = s_local + exp(x[base + i] - m)
    i = i + tg_size
  s = tg_sum(s_local) ## f32

  inv_s = ~1.0 / s ## f32
  i = tid
  while i < n
    x[base + i] = exp(x[base + i] - m) * inv_s
    i = i + tg_size
