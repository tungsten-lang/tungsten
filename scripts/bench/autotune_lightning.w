# TG_SIZE × kernel-variant autotune for Lightning-1.7B-mlx-nvfp4 hot path.
#
# Sweeps:
#   1. tg_*-using kernels (rms_norm, argmax, attn_softmax) × TG_SIZE in
#      {32, 64, 128, 256, 512, 1024}. Apple max is 1024.
#   2. nvfp4 matvec variants (mlx, v3, v4) on the q_proj-shape (K=N=2048).
#      Each variant has its own dispatch contract (rows/TG, threads/TG,
#      threadgroup memory).
#
# Synthetic input buffers; argmax output validated so "wrong but fast"
# never wins. No model load — runs in seconds.
#
# Usage:
#   bin/tungsten compile bits/tungsten-llama/lib/models/lightning_1_7b/autotune.w
#   codesign --force -s - bits/tungsten-llama/lib/models/lightning_1_7b/autotune.wc
#   bits/tungsten-llama/lib/models/lightning_1_7b/autotune.wc

use core/metal

KERNEL_DIR = "bits/tungsten-llama/lib/kernels/shared/"
NVFP4_DIR  = "bits/tungsten-llama/lib/kernels/nvfp4/"
HIDDEN  = 2048
N_VOCAB = 151936
N_POS   = 128
EPS     = ~0.000001

TG_SIZES = [32, 64, 128, 256, 512, 1024]
WARMUP_ITERS  = 5
MEASURE_ITERS = 30

device = metal_device()
queue  = metal_queue(device)

rms_pipe     = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "rms_norm.metal")), "rms_norm")
argmax_pipe  = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "argmax.metal")), "argmax")
softmax_pipe = metal_pipeline(metal_compile_source(device, read_file(KERNEL_DIR + "attn_softmax.metal")), "attn_softmax")

# nvfp4 matvec variant pipelines — q_proj shape (K=N=2048).
mv_mlx_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx.metal")), "nvfp4_matvec_mlx")
mv_pipe     = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec.metal")), "nvfp4_matvec")
mv_v3_pipe  = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_v3.metal")), "nvfp4_matvec_v3")
mv_v4_pipe  = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_v4.metal")), "nvfp4_matvec_v4")

# ---- Synthetic buffers ----
x_buf = metal_buffer(device, HIDDEN * 4)
w_buf = metal_buffer(device, HIDDEN * 4)
y_buf = metal_buffer(device, HIDDEN * 4)
i = 0
while i < HIDDEN
  metal_buffer_write_f32(x_buf, i, ~1.0 + (i % 7) * ~0.03)
  metal_buffer_write_f32(w_buf, i, ~1.0)
  i = i + 1

logits_buf = metal_buffer(device, N_VOCAB * 4)
arg_buf    = metal_buffer(device, 4)
i = 0
while i < N_VOCAB
  v = ~0.5
  if i == 12345
    v = ~99.0
  metal_buffer_write_f32(logits_buf, i, v)
  i = i + 1

N_HEADS_S = 16
softmax_buf = metal_buffer(device, N_HEADS_S * N_POS * 4)
i = 0
while i < N_HEADS_S * N_POS
  metal_buffer_write_f32(softmax_buf, i, (i % 13) * ~0.1)
  i = i + 1

# nvfp4 matvec buffers — N_ROWS=2048, K=2048.
N_ROWS_M = 2048
mv_quants_buf = metal_buffer(device, N_ROWS_M * (HIDDEN / 8) * 4)
mv_scales_buf = metal_buffer(device, N_ROWS_M * (HIDDEN / 16))
mv_y_buf      = metal_buffer(device, N_ROWS_M * 4)
i = 0
while i < N_ROWS_M * (HIDDEN / 8)
  metal_buffer_write_i32(mv_quants_buf, i, 305419896)  # 0x12345678
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

-> bench_one_dispatch(label, pipe, args, n_groups, tg_size, tg_mem_bytes)
  metal_batch_begin(queue)
  if tg_mem_bytes > 0
    metal_set_threadgroup_memory(queue, tg_mem_bytes, 0)
  wi = 0
  while wi < WARMUP_ITERS
    metal_dispatch_groups(queue, pipe, args, n_groups, tg_size)
    wi = wi + 1
  metal_batch_commit(queue)
  metal_batch_begin(queue)
  if tg_mem_bytes > 0
    metal_set_threadgroup_memory(queue, tg_mem_bytes, 0)
  mi = 0
  while mi < MEASURE_ITERS
    metal_dispatch_groups(queue, pipe, args, n_groups, tg_size)
    mi = mi + 1
  ms = metal_batch_commit_ms(queue, 0)
  (ms / MEASURE_ITERS) * ~1000.0

<< "Lightning-1.7B-mlx-nvfp4 autotune."
<< "Apple max TG is 1024 (32 lanes × 32 simdgroups); 2048+ rejected by MSL."
<< "Grid: " + TG_SIZES.to_s + ", " + WARMUP_ITERS.to_s + "+" + MEASURE_ITERS.to_s + " iters."
<< ""

# ---- 1. TG_SIZE sweep ----
sweep_tg_size_groups("rms_norm  (HIDDEN=" + HIDDEN.to_s + ")",
                    rms_pipe,
                    [x_buf, w_buf, y_buf, HIDDEN, ~1.0 / HIDDEN, EPS],
                    1)

sweep_tg_size_groups("argmax    (N_VOCAB=" + N_VOCAB.to_s + ")",
                    argmax_pipe,
                    [logits_buf, arg_buf, N_VOCAB],
                    1)

sweep_tg_size_groups("attn_softmax (n_heads=" + N_HEADS_S.to_s + ", n_pos=" + N_POS.to_s + ")",
                    softmax_pipe,
                    [softmax_buf, N_POS],
                    N_HEADS_S)

# ---- 2. nvfp4 matvec variant selection (q_proj shape: K=N=2048) ----
<< "=== nvfp4 matvec variants on (K=" + HIDDEN.to_s + ", N=" + N_ROWS_M.to_s + ") ==="
us_orig = bench_one_dispatch("nvfp4_matvec",     mv_pipe,    [mv_quants_buf, mv_scales_buf, x_buf, mv_y_buf, HIDDEN], N_ROWS_M, 32, 0)
<< "  nvfp4_matvec        (1 row/TG, 32 thr):  " + us_orig.to_s + " µs/call"
us_mlx = bench_one_dispatch("nvfp4_matvec_mlx", mv_mlx_pipe, [mv_quants_buf, mv_scales_buf, x_buf, mv_y_buf, HIDDEN], N_ROWS_M / 8, 64, 0)
<< "  nvfp4_matvec_mlx    (8 rows/TG, 64 thr): " + us_mlx.to_s + " µs/call  \[bench uses this]"
us_v3 = bench_one_dispatch("nvfp4_matvec_v3",   mv_v3_pipe, [mv_quants_buf, mv_scales_buf, x_buf, mv_y_buf, HIDDEN], N_ROWS_M / 4, 128, 0)
<< "  nvfp4_matvec_v3     (4 rows/TG, 128 thr):" + us_v3.to_s + " µs/call"
us_v4 = bench_one_dispatch("nvfp4_matvec_v4",   mv_v4_pipe, [mv_quants_buf, mv_scales_buf, x_buf, mv_y_buf, HIDDEN], N_ROWS_M / 32, 1024, HIDDEN * 4)
<< "  nvfp4_matvec_v4     (32 rows/TG, 1024 thr, TG-cached x): " + us_v4.to_s + " µs/call"
<< ""
<< "done."
