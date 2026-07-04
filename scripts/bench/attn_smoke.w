# GQA attention end-to-end smoke. Chains attn_scores → attn_softmax →
# attn_weighted_sum and compares the result against a CPU reference.
#
# Shapes: qwen3-style (32 q-heads, 4 kv-heads, head_dim=128) but with
# a tiny n_pos so the CPU side runs quickly.

use core/metal

HEAD_DIM = 128
N_Q_HEADS = 32
N_KV_HEADS = 4
GROUP_SIZE = 8       # 32 / 4
N_POS = 64           # short context for the test

device = metal_device()
queue = metal_queue(device)

scores_lib = metal_compile_source(device, read_file("bits/tungsten-llama/lib/attn_scores.metal"))
softmax_lib = metal_compile_source(device, read_file("bits/tungsten-llama/lib/attn_softmax.metal"))
weighted_lib = metal_compile_source(device, read_file("bits/tungsten-llama/lib/attn_weighted_sum.metal"))

scores_pipe = metal_pipeline(scores_lib, "attn_scores")
softmax_pipe = metal_pipeline(softmax_lib, "attn_softmax")
weighted_pipe = metal_pipeline(weighted_lib, "attn_weighted_sum")

# Buffers
q_buf       = metal_buffer(device, N_Q_HEADS * HEAD_DIM * 4)
k_buf       = metal_buffer(device, N_POS * N_KV_HEADS * HEAD_DIM * 4)
v_buf       = metal_buffer(device, N_POS * N_KV_HEADS * HEAD_DIM * 4)
scores_buf  = metal_buffer(device, N_Q_HEADS * N_POS * 4)
out_buf     = metal_buffer(device, N_Q_HEADS * HEAD_DIM * 4)

hd_buf = metal_buffer(device, 4)
nkv_buf = metal_buffer(device, 4)
gs_buf = metal_buffer(device, 4)
np_buf = metal_buffer(device, 4)
scale_buf = metal_buffer(device, 4)
n_scores_buf = metal_buffer(device, 4)

metal_buffer_write_i32(hd_buf, 0, HEAD_DIM)
metal_buffer_write_i32(nkv_buf, 0, N_KV_HEADS)
metal_buffer_write_i32(gs_buf, 0, GROUP_SIZE)
metal_buffer_write_i32(np_buf, 0, N_POS)
scale = ~1.0 / Math.sqrt(~0.0 + HEAD_DIM)
metal_buffer_write_f32(scale_buf, 0, scale)
metal_buffer_write_i32(n_scores_buf, 0, N_POS)

# Deterministic input data.
i = 0
while i < N_Q_HEADS * HEAD_DIM
  metal_buffer_write_f32(q_buf, i, Math.sin(i * ~0.013))
  i = i + 1
i = 0
while i < N_POS * N_KV_HEADS * HEAD_DIM
  metal_buffer_write_f32(k_buf, i, Math.sin(i * ~0.027))
  metal_buffer_write_f32(v_buf, i, Math.cos(i * ~0.019))
  i = i + 1

# 1. scores
scores_bufs = [q_buf, k_buf, scores_buf, hd_buf, nkv_buf, gs_buf, np_buf, scale_buf]
metal_dispatch_n(queue, scores_pipe, scores_bufs, N_Q_HEADS * N_POS)

# 2. softmax (one threadgroup per row of length N_POS)
softmax_bufs = [scores_buf, n_scores_buf]
metal_dispatch_groups(queue, softmax_pipe, softmax_bufs, N_Q_HEADS, 32)

# 3. weighted sum
weighted_bufs = [scores_buf, v_buf, out_buf, hd_buf, nkv_buf, gs_buf, np_buf]
metal_dispatch_n(queue, weighted_pipe, weighted_bufs, N_Q_HEADS * HEAD_DIM)

# CPU reference for ONE q-head (head 17, kv-head 17/8 = 2). Verifying
# every head is overkill for the smoke; one head proves the indexing.
TEST_HEAD = 17
test_kv_head = TEST_HEAD / GROUP_SIZE  # = 2

# scores[t] = (q[h] . k[t, kv_h]) * scale, for t in 0..n_pos
cpu_scores = []
t = 0
max_score = ~-1000000000.0
while t < N_POS
  dot = ~0.0
  j = 0
  while j < HEAD_DIM
    qv = Math.sin((TEST_HEAD * HEAD_DIM + j) * ~0.013)
    k_idx = (t * N_KV_HEADS + test_kv_head) * HEAD_DIM + j
    kv = Math.sin(k_idx * ~0.027)
    dot = dot + qv * kv
    j = j + 1
  s = dot * scale
  cpu_scores.push(s)
  if s > max_score
    max_score = s
  t = t + 1

# Softmax
sum_exp = ~0.0
t = 0
while t < N_POS
  cpu_scores[t] = Math.exp(cpu_scores[t] - max_score)
  sum_exp = sum_exp + cpu_scores[t]
  t = t + 1
t = 0
while t < N_POS
  cpu_scores[t] = cpu_scores[t] / sum_exp
  t = t + 1

# Weighted sum: out[h, j] = sum_t scores[t] * v[t, kv_h, j]
max_abs_err = ~0.0
j = 0
while j < HEAD_DIM
  expected = ~0.0
  t = 0
  while t < N_POS
    v_idx = (t * N_KV_HEADS + test_kv_head) * HEAD_DIM + j
    vv = Math.cos(v_idx * ~0.019)
    expected = expected + cpu_scores[t] * vv
    t = t + 1
  got = metal_buffer_read_f32(out_buf, TEST_HEAD * HEAD_DIM + j)
  err = expected - got
  if err < ~0.0
    err = ~0.0 - err
  if err > max_abs_err
    max_abs_err = err
  j = j + 1

<< "gqa attention smoke (q_heads=" + N_Q_HEADS.to_s + ", kv_heads=" + N_KV_HEADS.to_s + ", head_dim=" + HEAD_DIM.to_s + ", n_pos=" + N_POS.to_s + "):"
<< "  test head = " + TEST_HEAD.to_s + " (kv head " + test_kv_head.to_s + ")"
<< "  scale = 1/sqrt(head_dim) = " + scale.to_s
<< "  max abs error vs CPU = " + max_abs_err.to_s
if max_abs_err > ~0.0001
  << "FAIL"
  exit 1
<< "OK"
