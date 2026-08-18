# Drives the shipped tiled draft selector (mtp_draft_select_fast.metal),
# the live ARGV[6]!="slowsel" path in scripts/bench/qwen38_mlx.w.
# Also refuses to pass if the rejected q2draft experiment is still wired.

use core/metal

QWEN_DIR = "bits/tungsten-llama/lib/kernels/qwen3_6/"

PREFIX = 2048
CONTROL_COUNT = 8
CONTROL_START = 248044
TOTAL = PREFIX + CONTROL_COUNT
TILE = 1024
N_TILES = (TOTAL + TILE - 1) / TILE

device = metal_device()
queue = metal_queue(device)
lib = metal_compile_source(device, read_file(QWEN_DIR + "mtp_draft_select_fast.metal"))
stage1 = metal_pipeline(lib, "mtp_draft_select_stage1")
stage2 = metal_pipeline(lib, "mtp_draft_select_stage2")

prefix = metal_buffer(device, PREFIX * 4)
control = metal_buffer(device, CONTROL_COUNT * 4)
partial_vals = metal_buffer(device, N_TILES * 4)
partial_ids = metal_buffer(device, N_TILES * 4)
result = metal_buffer(device, 4)
prefix_n = metal_buffer(device, 4)
control_n = metal_buffer(device, 4)
control_s = metal_buffer(device, 4)
n_partials = metal_buffer(device, 4)
metal_buffer_write_i32(prefix_n, 0, PREFIX)
metal_buffer_write_i32(control_n, 0, CONTROL_COUNT)
metal_buffer_write_i32(control_s, 0, CONTROL_START)
metal_buffer_write_i32(n_partials, 0, N_TILES)

-> zero_logits
  i = 0
  while i < PREFIX
    metal_buffer_write_f32(prefix, i, ~0.0)
    i = i + 1
  i = 0
  while i < CONTROL_COUNT
    metal_buffer_write_f32(control, i, ~0.0)
    i = i + 1

-> run_select
  metal_batch_begin(queue)
  metal_dispatch_groups(queue, stage1,
    [prefix, control, partial_vals, partial_ids, prefix_n, control_n, control_s],
    N_TILES, 256)
  metal_batch_barrier(queue)
  metal_dispatch_groups(queue, stage2,
    [partial_vals, partial_ids, result, n_partials], 1, 256)
  metal_batch_commit(queue)
  metal_buffer_read_i32(result, 0)

# Planted unique maxima — the expected IDs are the positions we wrote, not
# a reimplemented reduction.
zero_logits()
metal_buffer_write_f32(prefix, 1500, ~9.0)
got = run_select()
if got != 1500
  raise "prefix winner: expected 1500 got " + got.to_s
<< "prefix winner PASS " + got.to_s

zero_logits()
metal_buffer_write_f32(control, 2, ~9.0)
got = run_select()
expect_control = CONTROL_START + 2
if got != expect_control
  raise "control winner: expected " + expect_control.to_s + " got " + got.to_s
<< "control winner PASS " + got.to_s

zero_logits()
metal_buffer_write_f32(prefix, 0, ~5.0)
metal_buffer_write_f32(control, 0, ~5.0)
got = run_select()
if got != 0
  raise "tie prefers lower id: expected 0 got " + got.to_s
<< "tie-break PASS " + got.to_s

<< "mtp_draft_select_fast shipped path PASS"
