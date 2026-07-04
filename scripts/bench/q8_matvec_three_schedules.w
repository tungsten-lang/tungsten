# Phase 3 plan-required verification harness:
# "one algorithm, three schedules, three measurably-different MSL
# outputs + three measurably-different GPU times."
#
# Algorithm: the v0 baseline Q8_0 matvec (one thread per output row,
# byte reads). Three named variants, each declared as a separate
# @schedule that applies different transformations.
#
# Run:
#   bin/tungsten compile scripts/bench/q8_matvec_three_schedules.w \
#     -o /tmp/q8_three --ll
#   codesign --force -s - /tmp/q8_three
#   /tmp/q8_three

use core/metal

## i8[]: w_q
## f16[]: w_s
## f32[]: x
## f32[]: y
## i32: k_dim
@gpu fn q8_matvec(w_q, w_s, x, y, k_dim)
  m = gpu.thread_position_in_grid.x ## axis :m
  nb = k_dim / 32 ## i32
  acc = 0.0 ## f32
  b = 0 ## axis :b, i32
  while b < nb
    s = w_s[m * nb + b] ## f16
    block_acc = 0.0 ## f32
    j = 0 ## i32
    while j < 32
      block_acc = block_acc + w_q[m * k_dim + b * 32 + j] * x[b * 32 + j]
      j = j + 1
    acc = acc + s * block_acc
    b = b + 1
  y[m] = acc

@layout q8_matvec.packed_q8
  buffer :w_q, from: "i8[]", to: "i32[]", unpack: :sign_extend_per_byte

# Variant A: m → threadgroup only (1 lane per row, no reduction).
# Mostly a sanity check that the @schedule plumbing produces a
# distinct kernel even with a minimal directive.
@schedule q8_matvec.tgmapped
  axis :m, parallelize: :threadgroup

# Variant B: full cooperative reduction (schedule-only).
@schedule q8_matvec.coop
  axis :m, parallelize: :threadgroup
  axis :b, parallelize: :simdgroup_lane, stride: 32
  axis :b, reduce: :simd_sum, into: :acc

# Variant C: cooperative + packed layout (composed).
@schedule q8_matvec.coop_packed
  use_layout :packed_q8
  axis :m, parallelize: :threadgroup
  axis :b, parallelize: :simdgroup_lane, stride: 32
  axis :b, reduce: :simd_sum, into: :acc

msl = read_file("scripts/bench/q8_matvec_three_schedules.metal")
device = metal_device()
library = metal_compile_source(device, msl)

# Pick the three named variants.
default_pipe = metal_pipeline(library, "q8_matvec")
tg_pipe      = metal_pipeline(library, "q8_matvec_tgmapped")
coop_pipe    = metal_pipeline(library, "q8_matvec_coop")
packed_pipe  = metal_pipeline(library, "q8_matvec_coop_packed")

# qwen3 lm_head shape — most stable signal in our bench.
n_rows = 151936
k_cols = 2048
nb = k_cols / 32

w_q_buf = metal_buffer(device, n_rows * k_cols)
w_s_buf = metal_buffer(device, n_rows * nb * 2)
x_buf   = metal_buffer(device, k_cols * 4)
y_buf   = metal_buffer(device, n_rows * 4)
k_buf   = metal_buffer(device, 4)

total_q_words = (n_rows * k_cols) / 4
i = 0
while i < total_q_words
  metal_buffer_write_i32(w_q_buf, i, 0x01010101)
  i = i + 1
total_s_words = (n_rows * nb) / 2
i = 0
while i < total_s_words
  metal_buffer_write_i32(w_s_buf, i, 0x3C003C00)
  i = i + 1
i = 0
while i < k_cols
  metal_buffer_write_f32(x_buf, i, ~1.0)
  i = i + 1
metal_buffer_write_i32(k_buf, 0, k_cols)

queue = metal_queue(device)
bufs = [w_q_buf, w_s_buf, x_buf, y_buf, k_buf]

weight_bytes = n_rows * nb * 34
bytes_per_call = weight_bytes + k_cols * 4 + n_rows * 4
iters = 50

# Warmup all four pipelines.
i = 0
while i < 5
  metal_dispatch_n(queue, default_pipe, bufs, n_rows)
  metal_dispatch_groups(queue, tg_pipe,      bufs, n_rows, 1)
  metal_dispatch_groups(queue, coop_pipe,    bufs, n_rows, 32)
  metal_dispatch_groups(queue, packed_pipe,  bufs, n_rows, 32)
  i = i + 1

# Bench helpers. Each runs one variant for `iters` dispatches and
# returns GB/s. Best-of-5 on each to suppress run-to-run noise.

-> bench_default(queue, pipe, bufs, n_rows, iters, bytes_per_call)
  t0 = clock
  i = 0
  while i < iters
    metal_dispatch_n(queue, pipe, bufs, n_rows)
    i = i + 1
  elapsed = clock - t0
  bytes_per_call.to_f * iters.to_f / elapsed / ~1.0e9

-> bench_groups(queue, pipe, bufs, n_rows, threads_per_group, iters, bytes_per_call)
  t0 = clock
  i = 0
  while i < iters
    metal_dispatch_groups(queue, pipe, bufs, n_rows, threads_per_group)
    i = i + 1
  elapsed = clock - t0
  bytes_per_call.to_f * iters.to_f / elapsed / ~1.0e9

# Best of 5 runs per variant.
default_gbs = ~0.0
i = 0
while i < 5
  v = bench_default(queue, default_pipe, bufs, n_rows, iters, bytes_per_call)
  if v > default_gbs
    default_gbs = v
  i = i + 1

tg_gbs = ~0.0
i = 0
while i < 5
  v = bench_groups(queue, tg_pipe, bufs, n_rows, 1, iters, bytes_per_call)
  if v > tg_gbs
    tg_gbs = v
  i = i + 1

coop_gbs = ~0.0
i = 0
while i < 5
  v = bench_groups(queue, coop_pipe, bufs, n_rows, 32, iters, bytes_per_call)
  if v > coop_gbs
    coop_gbs = v
  i = i + 1

packed_gbs = ~0.0
i = 0
while i < 5
  v = bench_groups(queue, packed_pipe, bufs, n_rows, 32, iters, bytes_per_call)
  if v > packed_gbs
    packed_gbs = v
  i = i + 1

# CSV output — easy to grep, easy to paste into a doc.
<< "variant,gb_per_s"
<< "default," + default_gbs.to_s
<< "tgmapped," + tg_gbs.to_s
<< "coop," + coop_gbs.to_s
<< "coop_packed," + packed_gbs.to_s
