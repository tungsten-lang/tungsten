# RMSNorm — single-threadgroup reduction kernel.
#
# Formula: y[i] = x[i] * w[i] / sqrt(mean(x²) + eps)
#
# Used in qwen3 at three sites with three different vector lengths:
#   - hidden norm  (attn_norm, ffn_norm, output_norm) over 2048 floats
#   - per-head Q norm (attn_q_norm) over 128 floats
#   - per-head K norm (attn_k_norm) over 128 floats
#
# Schedule:
#   - One threadgroup of TG_SIZE threads (e.g. 256 = 8 simdgroups).
#   - Each thread scans n/TG_SIZE elements striped, accumulates sum-of-squares.
#   - `tg_sum` reduces across all simdgroups via threadgroup memory; every
#     thread then sees the full `total` and writes its slice of outputs.
#   - Stride is `gpu.threads_per_threadgroup`, so the kernel is correct
#     for any dispatched TG size from 32 to 1024 (Apple Silicon max).
#
# CPU passes inv_n = 1.0/n and eps directly so the kernel never has to
# cast i32 → f32 or do an internal division.
#
# Dispatched with `metal_dispatch_groups(queue, pipeline, bufs, 1, TG_SIZE)`
# where TG_SIZE should be a power of 2 in [32, 1024]; 256 is a sweet spot
# for HIDDEN=2048 (8 elements per thread).

## f32[]: x
## f32[]: w
## f32[]: y
## i32: n
## f32: inv_n
## f32: eps
@gpu fn rms_norm(x, w, y, n, inv_n, eps)
  tg_size = gpu.threads_per_threadgroup ## i32
  tid = gpu.thread_position_in_threadgroup.x ## i32
  sum_sq = 0.0 ## f32
  i = tid ## i32
  while i < n
    v = x[i] ## f32
    sum_sq = sum_sq + v * v
    i = i + tg_size
  total = tg_sum(sum_sq) ## f32
  rrms = ~1.0 / sqrt(total * inv_n + eps) ## f32
  i = tid
  while i < n
    y[i] = x[i] * rrms * w[i]
    i = i + tg_size
