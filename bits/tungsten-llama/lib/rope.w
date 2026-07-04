# Rotary position embedding (NEOX-style split-half) — applied to Q and
# K projections before attention. qwen3 uses this layout: pair element i
# with element i + head_dim/2 across the head dimension, rotate by
# theta_i * position.
#
# Layout:
#   x: f32[n_heads * head_dim] — flat concatenation of all heads' vectors
#      (i.e. the output of q_proj or k_proj for one token).
#   cos, sin: f32[head_dim/2] — precomputed for the current position.
#     CPU side: cos[i] = cos(pos * base^(-2i/head_dim)),
#               sin[i] = sin(pos * base^(-2i/head_dim)).
#   head_dim, head_dim_half, n_heads: constant ints.
#
# In-place: each thread reads (x[lo], x[hi]) and writes the rotated
# values to the same slots. No intra-threadgroup synchronization needed
# because every thread owns a disjoint pair.
#
# Dispatch: `metal_dispatch_n(queue, pipeline, bufs, n_heads * head_dim_half)`.
# One thread per (head, pair). Apple GPUs round threadgroup width up to
# 32; n_heads * head_dim_half is a multiple of 32 for any sane shape
# (qwen3 q: 32 * 64 = 2048; qwen3 k: 4 * 64 = 256), so dispatch_n's
# default group sizing is fine.

## f32[]: x
## f32[]: cos_tab
## f32[]: sin_tab
## i32: head_dim
## i32: head_dim_half
## i32: n_heads
@gpu fn rope_neox(x, cos_tab, sin_tab, head_dim, head_dim_half, n_heads)
  tid = gpu.thread_position_in_grid.x ## i32
  head = tid / head_dim_half ## i32
  pair = tid % head_dim_half ## i32
  base_off = head * head_dim ## i32
  i_lo = base_off + pair ## i32
  i_hi = i_lo + head_dim_half ## i32
  a = x[i_lo] ## f32
  b = x[i_hi] ## f32
  c = cos_tab[pair] ## f32
  s = sin_tab[pair] ## f32
  x[i_lo] = a * c - b * s
  x[i_hi] = a * s + b * c
