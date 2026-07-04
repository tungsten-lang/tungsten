# Phase 4 — autotuner smoke. Loads the four hand-written variants of
# the q8_matvec kernel from q8_matvec_three_schedules.w (default,
# tgmapped, coop, coop_packed) and lets the Autotuner pick the winner.

use core/metal
use tungsten-llama/autotune

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

@schedule q8_matvec.tgmapped
  axis :m, parallelize: :threadgroup

@schedule q8_matvec.coop
  axis :m, parallelize: :threadgroup
  axis :b, parallelize: :simdgroup_lane, stride: 32
  axis :b, reduce: :simd_sum, into: :acc

@schedule q8_matvec.coop_packed
  use_layout :packed_q8
  axis :m, parallelize: :threadgroup
  axis :b, parallelize: :simdgroup_lane, stride: 32
  axis :b, reduce: :simd_sum, into: :acc

n_rows = 151936
k_cols = 2048
nb = k_cols / 32

device = metal_device()
queue = metal_queue(device)

msl = read_file("scripts/bench/autotune_smoke.metal")
library = metal_compile_source(device, msl)

default_pipe = metal_pipeline(library, "q8_matvec")
tg_pipe      = metal_pipeline(library, "q8_matvec_tgmapped")
coop_pipe    = metal_pipeline(library, "q8_matvec_coop")
packed_pipe  = metal_pipeline(library, "q8_matvec_coop_packed")

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

bufs = [w_q_buf, w_s_buf, x_buf, y_buf, k_buf]

# Build candidate list. dispatch_n + tg_size = 0 → metal_dispatch_n.
# tg_size > 0 → metal_dispatch_groups with that threadgroup size.
candidates = []
candidates.push(AutotuneCandidate.new("default",     default_pipe, n_rows, 0,  bufs))
candidates.push(AutotuneCandidate.new("tgmapped",    tg_pipe,      n_rows, 1,  bufs))
candidates.push(AutotuneCandidate.new("coop",        coop_pipe,    n_rows, 32, bufs))
candidates.push(AutotuneCandidate.new("coop_packed", packed_pipe,  n_rows, 32, bufs))

# Use the default variant as the baseline. All four should produce
# identical output (they implement the same algorithm), so any
# divergence is a bug in the schedule transformation, not numerical
# noise — keep abs_tol tight.
tuner = Autotuner.new(queue, candidates, y_buf, n_rows)
tuner.abs_tol = ~0.001
tuner.warmup_iters = 5
tuner.measure_iters = 50
winner_idx = tuner.run
if winner_idx >= 0
  shape_key = n_rows.to_s + "x" + k_cols.to_s
  system("mkdir -p /tmp/tungsten/autotune-cache")
  tuner.write_cache("/tmp/tungsten/autotune-cache", "q8_matvec", shape_key, winner_idx, ~1.1)
