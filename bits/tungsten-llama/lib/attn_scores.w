# GQA attention scores: per-(head, position) Q·K dot product, scaled.
#
# Shapes (decode step — Q is for the current token only, K cache covers
# all prior tokens including the current one):
#   q:        f32[n_q_heads * head_dim]
#   k_cache:  f32[n_pos * n_kv_heads * head_dim]    (contiguous over pos)
#   scores:   f32[n_q_heads * n_pos]                (output)
#
# GQA: q-head h → kv-head h / group_size where group_size = n_q_heads / n_kv_heads.
# qwen3 has 32 q-heads, 4 kv-heads, so group_size=8.
#
# Dispatch: one TG per (h, t) cell — n_q_heads * n_pos TGs total, each
# cooperating via tg_sum to reduce the head_dim-element dot product.
# Pick TG_SIZE = 32 for head_dim=128 (4 elts/lane, single simdgroup);
# larger TG_SIZE makes sense if head_dim grows.

## f32[]: q
## f32[]: k_cache
## f32[]: scores
## i32: head_dim
## i32: n_kv_heads
## i32: group_size
## i32: n_pos
## f32: scale
@gpu fn attn_scores(q, k_cache, scores, head_dim, n_kv_heads, group_size, n_pos, scale)
  tg_size = gpu.threads_per_threadgroup ## i32
  tid = gpu.thread_position_in_threadgroup.x ## i32
  cell = gpu.threadgroup_position_in_grid.x ## i32
  h = cell / n_pos ## i32
  t = cell % n_pos ## i32
  kv_h = h / group_size ## i32
  q_off = h * head_dim ## i32
  k_off = (t * n_kv_heads + kv_h) * head_dim ## i32
  partial = 0.0 ## f32
  j = tid ## i32
  while j < head_dim
    partial = partial + q[q_off + j] * k_cache[k_off + j]
    j = j + tg_size
  total = tg_sum(partial) ## f32
  if tid == 0
    scores[h * n_pos + t] = total * scale
