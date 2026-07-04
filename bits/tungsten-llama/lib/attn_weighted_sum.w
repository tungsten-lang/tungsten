# GQA attention weighted sum: out[h, j] = Σ_t scores[h, t] * V_cache[t, kv_h, j].
# Run after attn_softmax has normalized the scores rowwise.
#
# Shapes:
#   scores:   f32[n_q_heads * n_pos]
#   v_cache:  f32[n_pos * n_kv_heads * head_dim]
#   out:      f32[n_q_heads * head_dim]
#
# Dispatch: one TG per (head, j) cell — n_q_heads * head_dim TGs total,
# each cooperating via tg_sum to reduce the n_pos-element weighted sum.
# Pick TG_SIZE based on expected n_pos: 32 for short (decode), 256+ for
# long context (n_pos > 1000) where the per-thread serial scan would
# dominate.

## f32[]: scores
## f32[]: v_cache
## f32[]: out
## i32: head_dim
## i32: n_kv_heads
## i32: group_size
## i32: n_pos
@gpu fn attn_weighted_sum(scores, v_cache, out, head_dim, n_kv_heads, group_size, n_pos)
  tg_size = gpu.threads_per_threadgroup ## i32
  tid = gpu.thread_position_in_threadgroup.x ## i32
  cell = gpu.threadgroup_position_in_grid.x ## i32
  h = cell / head_dim ## i32
  j = cell % head_dim ## i32
  kv_h = h / group_size ## i32
  scores_off = h * n_pos ## i32
  partial = 0.0 ## f32
  t = tid ## i32
  while t < n_pos
    v_off = (t * n_kv_heads + kv_h) * head_dim + j ## i32
    partial = partial + scores[scores_off + t] * v_cache[v_off]
    t = t + tg_size
  total = tg_sum(partial) ## f32
  if tid == 0
    out[h * head_dim + j] = total
