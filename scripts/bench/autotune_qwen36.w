# TG_SIZE × kernel-variant autotune for qwen3.6/35b-a3b-nvfp4 hot path.
#
# Same hot kernels (rms_norm, argmax, attn_softmax, attn_scores) as
# Lightning, but at qwen3.6's larger shapes — and with long-context
# attn_softmax (n_pos=4096) since the model supports max_position=262K.
#
# Architecture (from config.json — see config.w in this dir):
#   hidden_size=2048 (same as Lightning), head_dim=256 (2× Lightning),
#   vocab_size=248320 (1.6× Lightning), num_hidden_layers=40
#   layer_types: 30 linear_attention (Mamba/SSM) + 10 full_attention.
#   This autotune covers the 10 full_attention layers' kernels; the
#   linear_attention/Mamba selective_scan kernel doesn't exist yet
#   (separate port effort).
#
# Synthetic inputs; no model load. Runs in seconds.
#
# Usage:
#   bin/tungsten compile bits/tungsten-llama/lib/models/qwen3_6_35b_a3b_nvfp4/autotune.w
#   codesign --force -s - bits/tungsten-llama/lib/models/qwen3_6_35b_a3b_nvfp4/autotune.wc
#   bits/tungsten-llama/lib/models/qwen3_6_35b_a3b_nvfp4/autotune.wc

use core/metal

KERNEL_DIR = "bits/tungsten-llama/lib/kernels/shared/"
HIDDEN  = 2048
EPS     = ~0.000001

# qwen3.6-specific dimensions
Q36_VOCAB      = 248320
Q36_HEAD_DIM   = 256
Q36_LONG_NPOS  = 4096   # representative long-context softmax
Q36_N_KV_HEADS = 2      # extreme GQA: 16 Q heads / 2 KV heads = group_size 8
Q36_N_HEADS    = 16
Q36_GROUP_SIZE = 8

TG_SIZES = [32, 64, 128, 256, 512, 1024]
WARMUP_ITERS  = 5
MEASURE_ITERS = 30

device = metal_device()
queue  = metal_queue(device)

rms_pipe     = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "rms_norm.metal")), "rms_norm")
argmax_pipe  = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "argmax.metal")), "argmax")
softmax_pipe = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "attn_softmax.metal")), "attn_softmax")
scores_pipe  = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "attn_scores.metal")), "attn_scores")

# ---- Synthetic buffers ----
x_buf = metal_buffer(device, HIDDEN * 4)
w_buf = metal_buffer(device, HIDDEN * 4)
y_buf = metal_buffer(device, HIDDEN * 4)
i = 0
while i < HIDDEN
  metal_buffer_write_f32(x_buf, i, ~1.0 + (i % 7) * ~0.03)
  metal_buffer_write_f32(w_buf, i, ~1.0)
  i = i + 1

logits_buf = metal_buffer(device, Q36_VOCAB * 4)
arg_buf    = metal_buffer(device, 4)
i = 0
while i < Q36_VOCAB
  v = ~0.5
  if i == 200000
    v = ~99.0
  metal_buffer_write_f32(logits_buf, i, v)
  i = i + 1

long_softmax_buf = metal_buffer(device, Q36_N_HEADS * Q36_LONG_NPOS * 4)
i = 0
while i < Q36_N_HEADS * Q36_LONG_NPOS
  metal_buffer_write_f32(long_softmax_buf, i, (i % 13) * ~0.1)
  i = i + 1

# attn_scores buffers — shaped for qwen3.6 full_attention layer
scores_n_pos_active = 64
q_buf  = metal_buffer(device, Q36_N_HEADS * Q36_HEAD_DIM * 4)
k_buf  = metal_buffer(device, scores_n_pos_active * Q36_N_KV_HEADS * Q36_HEAD_DIM * 4)
scores_buf = metal_buffer(device, Q36_N_HEADS * scores_n_pos_active * 4)
i = 0
while i < Q36_N_HEADS * Q36_HEAD_DIM
  metal_buffer_write_f32(q_buf, i, (i % 17) * ~0.05)
  i = i + 1
i = 0
while i < scores_n_pos_active * Q36_N_KV_HEADS * Q36_HEAD_DIM
  metal_buffer_write_f32(k_buf, i, (i % 11) * ~0.07)
  i = i + 1

# ---- Median-of-N timing helpers ----

-> sweep_tg_size_groups(label, pipe, args, n_groups)
  << "=== " + label + " ==="
  best_us = ~999999.0
  best_tg = 0
  ti = 0
  while ti < TG_SIZES.size()
    tg = TG_SIZES[ti]
    metal_batch_begin(queue)
    wi = 0
    while wi < WARMUP_ITERS
      metal_dispatch_groups(queue, pipe, args, n_groups, tg)
      wi = wi + 1
    metal_batch_commit(queue)
    metal_batch_begin(queue)
    mi = 0
    while mi < MEASURE_ITERS
      metal_dispatch_groups(queue, pipe, args, n_groups, tg)
      mi = mi + 1
    ms = metal_batch_commit_ms(queue, 0)
    us = (ms / MEASURE_ITERS) * ~1000.0
    marker = ""
    if us < best_us
      best_us = us
      best_tg = tg
      marker = " *"
    << "  TG=" + tg.to_s + ": " + us.to_s + " µs/call" + marker
    ti = ti + 1
  << "  → best TG=" + best_tg.to_s + " at " + best_us.to_s + " µs"
  << ""

-> bench_one_dispatch(pipe, args, n_groups, tg_size)
  metal_batch_begin(queue)
  wi = 0
  while wi < WARMUP_ITERS
    metal_dispatch_groups(queue, pipe, args, n_groups, tg_size)
    wi = wi + 1
  metal_batch_commit(queue)
  metal_batch_begin(queue)
  mi = 0
  while mi < MEASURE_ITERS
    metal_dispatch_groups(queue, pipe, args, n_groups, tg_size)
    mi = mi + 1
  ms = metal_batch_commit_ms(queue, 0)
  (ms / MEASURE_ITERS) * ~1000.0

<< "qwen3.6/35b-a3b-nvfp4 autotune."
<< "Hidden=2048, head_dim=256, vocab=248320, max_pos=262144."
<< "Layer mix: 30 linear_attention (Mamba/SSM) + 10 full_attention."
<< "Apple max TG is 1024; grid: " + TG_SIZES.to_s + "."
<< ""

# ---- 1. rms_norm (HIDDEN=2048, same as Lightning — sanity) ----
sweep_tg_size_groups("rms_norm  (HIDDEN=" + HIDDEN.to_s + ")",
                    rms_pipe,
                    [x_buf, w_buf, y_buf, HIDDEN, ~1.0 / HIDDEN, EPS],
                    1)

# ---- 2. argmax at the larger vocab ----
# Each lane scans Q36_VOCAB / TG elements. At TG=1024: 242 elts/lane
# (vs 148 for Lightning's 152K vocab). Apple max-1024 is the ceiling
# for this 1-pass kernel; a 2-pass argmax (multi-TG partial reduce +
# final reduce) could break through it.
sweep_tg_size_groups("argmax    (N_VOCAB=" + Q36_VOCAB.to_s + ", 1.6× Lightning)",
                    argmax_pipe,
                    [logits_buf, arg_buf, Q36_VOCAB],
                    1)

# ---- 3. Long-context attn_softmax (n_pos=4096) ----
# At Lightning's n_pos=128 the autotune found TG=256/512 best. For
# qwen3.6's max_position=262K, longer rows likely shift the sweet spot
# upward. This sweep covers 4096 — extrapolate or re-sweep for actual
# expected n_pos in production.
sweep_tg_size_groups("attn_softmax (n_heads=" + Q36_N_HEADS.to_s + ", n_pos=" + Q36_LONG_NPOS.to_s + ", long context)",
                    softmax_pipe,
                    [long_softmax_buf, Q36_LONG_NPOS],
                    Q36_N_HEADS)

# ---- 4. attn_scores cooperative — head_dim=256, 1 TG per (h, t) cell ----
# Lightning's tuning at head_dim=128 said TG=32 (1 simdgroup) wins.
# Worth re-checking at head_dim=256 — 2× the per-cell reduction.
<< "=== attn_scores variants on qwen3.6 head_dim=256 ==="
<< "  (decode shape: 1 TG per (h,t); " + Q36_N_HEADS.to_s + " q-heads × " + scores_n_pos_active.to_s + " positions)"
n_cells = Q36_N_HEADS * scores_n_pos_active
scale_val = ~0.0625   # rough 1/sqrt(head_dim) for head_dim=256
us_s32 = bench_one_dispatch(scores_pipe,
  [q_buf, k_buf, scores_buf, Q36_HEAD_DIM, Q36_N_KV_HEADS, Q36_GROUP_SIZE, scores_n_pos_active, scale_val],
  n_cells, 32)
<< "  TG=32  (1 simdgroup, 8 elts/lane): " + us_s32.to_s + " µs/call"
us_s64 = bench_one_dispatch(scores_pipe,
  [q_buf, k_buf, scores_buf, Q36_HEAD_DIM, Q36_N_KV_HEADS, Q36_GROUP_SIZE, scores_n_pos_active, scale_val],
  n_cells, 64)
<< "  TG=64  (2 simdgroups, 4 elts/lane): " + us_s64.to_s + " µs/call"
us_s128 = bench_one_dispatch(scores_pipe,
  [q_buf, k_buf, scores_buf, Q36_HEAD_DIM, Q36_N_KV_HEADS, Q36_GROUP_SIZE, scores_n_pos_active, scale_val],
  n_cells, 128)
<< "  TG=128 (4 simdgroups, 2 elts/lane): " + us_s128.to_s + " µs/call"
<< ""
<< "done."
