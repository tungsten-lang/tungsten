# Real Tungsten bridge smoke for the upstream kernel ports. No model weights.
# Run from the repository root with BIT_HOME=$PWD/bits bin/tungsten run <file>.
# The exhaustive fast-math and shape gate is test_upstream_kernels.sh.
use core/metal

KERNELS = "bits/tungsten-llama/lib/kernels/qwen4_fn/"
device = metal_device()
queue = metal_queue(device)
multi = metal_compile_source(device, read_file(KERNELS + "fn_multi.metal"))
router = metal_compile_source(device, read_file(KERNELS + "router_softmax_topk10_warp.metal"))
norm = metal_compile_source(device, read_file(KERNELS + "grouped_rms_norm_warp.metal"))
router_ref = metal_pipeline(multi, "router_softmax_topk10_multi")
router_multi = metal_pipeline(router, "router_softmax_topk10_multi_warp")
router_single = metal_pipeline(router, "router_softmax_topk10_warp")
norm_ref = metal_pipeline(multi, "grouped_rms_norm_multi")
norm_pipes = [metal_pipeline(norm, "grouped_rms_norm_multi_warp"), metal_pipeline(norm, "grouped_rms_norm_multi_t64"), metal_pipeline(norm, "grouped_rms_norm_multi_t128")]

-> same_bits(a, b, count, label)
  i = 0
  while i < count
    if metal_buffer_read_i32(a, i) != metal_buffer_read_i32(b, i)
      raise label + " differs at " + i.to_s()
    i = i + 1

-> launch(pipe, args, groups, threads, recorded)
  metal_batch_begin(queue)
  if recorded == 1
    ccall("w_metal_program_run", queue, [[0, pipe, args, groups, threads]], recorded)
  else
    metal_dispatch_groups(queue, pipe, args, groups, threads)
  metal_batch_commit(queue)

widths = [1, 7, 64]
wi = 0
while wi < widths.size()
  rows = widths[wi]
  x = metal_buffer(device, rows * 512 * 4)
  ri = metal_buffer(device, rows * 10 * 4)
  rw = metal_buffer(device, rows * 10 * 4)
  i = 0
  while i < rows * 512
    metal_buffer_write_f32(x, i, ~0.125 * ((i * 37) % 67 - 33))
    i = i + 1
  launch(router_ref, [x, ri, rw], rows, 512, 0)
  mode = 0
  while mode < 2
    ci = metal_buffer(device, rows * 10 * 4)
    cw = metal_buffer(device, rows * 10 * 4)
    launch(router_multi, [x, ci, cw], rows, 32, mode)
    same_bits(ri, ci, rows * 10, "router IDs")
    same_bits(rw, cw, rows * 10, "router weights")
    if rows == 1
      si = metal_buffer(device, 40)
      sw = metal_buffer(device, 40)
      launch(router_single, [x, si, sw], 1, 32, mode)
      same_bits(ri, si, 10, "serial router IDs")
      same_bits(rw, sw, 10, "serial router weights")
    mode = mode + 1
  wi = wi + 1

# Exercise scalar boxing and dispatch dimensions for every norm variant.
rows = 128
d = 127
streams = 4
count = rows * streams * d
x = metal_buffer(device, count * 4)
w = metal_buffer(device, streams * d * 4)
ref = metal_buffer(device, count * 4)
i = 0
while i < count
  metal_buffer_write_f32(x, i, ~0.125 * (i % 59 - 29))
  i = i + 1
i = 0
while i < streams * d
  metal_buffer_write_f32(w, i, ~1.0 + ~0.001 * (i % 13))
  i = i + 1
launch(norm_ref, [x, w, ref, d, streams, ~0.000001], rows * streams, 256, 0)
ni = 0
threads = 32
while ni < 3
  mode = 0
  while mode < 2
    out = metal_buffer(device, count * 4)
    launch(norm_pipes[ni], [x, w, out, d, streams, ~0.000001], rows * streams, threads, mode)
    same_bits(ref, out, count, "grouped norm")
    mode = mode + 1
  threads = threads * 2
  ni = ni + 1

# Twelve mixed buffer/scalar arguments through both dispatch mechanisms.
qsa_ref = metal_pipeline(metal_compile_source(device, read_file(KERNELS + "qsa.metal")), "qsa_sdpa_selected_par")
qsa_group = metal_pipeline(metal_compile_source(device, read_file(KERNELS + "qsa_selected_group2.metal")), "qsa_sdpa_selected_group2")
rows = 64
q = metal_buffer(device, rows * 24 * 256 * 4)
k = metal_buffer(device, 64 * 512 * 4)
v = metal_buffer(device, 64 * 512 * 4)
sel = metal_buffer(device, rows * 2051 * 4)
ns = metal_buffer(device, rows * 4)
ref = metal_buffer(device, rows * 24 * 256 * 4)
i = 0
while i < rows * 24 * 256
  metal_buffer_write_f32(q, i, ~0.015625 * (i % 29 - 14))
  i = i + 1
i = 0
while i < 64 * 512
  metal_buffer_write_f32(k, i, ~0.015625 * (i % 31 - 15))
  metal_buffer_write_f32(v, i, ~0.015625 * (i % 37 - 18))
  i = i + 1
t = 0
while t < rows
  metal_buffer_write_i32(ns, t, t % 17)
  p = 0
  while p < 17
    metal_buffer_write_i32(sel, t * 2051 + p, (p * 7 + t) % 64)
    p = p + 1
  t = t + 1
launch(qsa_ref, [q, k, v, ref, sel, ns, 12, 24, 512, ~0.0625, 2051, rows], rows * 24, 256, 0)
mode = 0
while mode < 2
  out = metal_buffer(device, rows * 24 * 256 * 4)
  launch(qsa_group, [q, k, v, out, sel, ns, 12, 24, 512, ~0.0625, 2051, rows], rows * 12, 256, mode)
  same_bits(ref, out, rows * 24 * 256, "grouped QSA")
  mode = mode + 1
<< "PASS: router, normalization, and QSA match through direct and recorded Tungsten dispatch"
