# Qwen3.8/27B-MLX real-weight fusion experiment.
#
# Compares independent projection dispatches with a single combined grid, both
# serially and on Tungsten's concurrent Metal command buffer. Also checks the
# fused down-projection + residual path against qmv followed by residual_add.

use core/metal
use tungsten-llama/sharded_safetensors

MODEL_INDEX = "/Users/erik/.cache/tungsten/qwen3.8-27b-mlx/model.safetensors.index.json"
NVFP4_DIR = "bits/tungsten-llama/lib/kernels/nvfp4/"
SHARED_DIR = "bits/tungsten-llama/lib/kernels/shared/"
HIDDEN = 5120
FFN = 17408
WARMUP_ITERS = 12
MEASURE_ITERS = 12

device = metal_device()
queue = metal_queue(device)
st = Tungsten:Llama:ShardedSafetensors.new(MODEL_INDEX)

r2_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_r_2.metal"))
dual_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_gu.metal"))
res_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_residual.metal"))
add_lib = metal_compile_source(device, read_file(SHARED_DIR + "residual_add.metal"))
r2_pipe = metal_pipeline(r2_lib, "nvfp4_matvec_mlx_scaled_r_2")
dual_pipe = metal_pipeline(dual_lib, "nvfp4_matvec_mlx_scaled_gu")
res_pipe = metal_pipeline(res_lib, "nvfp4_matvec_mlx_scaled_residual")
add_pipe = metal_pipeline(add_lib, "residual_add")

x_hidden = metal_buffer(device, HIDDEN * 4)
x_ffn = metal_buffer(device, FFN * 4)
i = 0
while i < FFN
  v = Math.sin(i * ~0.013) * ~0.25
  metal_buffer_write_f32(x_ffn, i, v)
  if i < HIDDEN then metal_buffer_write_f32(x_hidden, i, v)
  i = i + 1

-> tensor_buffer(name)
  d = st.tensor(name)
  metal_buffer_for_mmap(device, st.mmap_for(name), d[:byte_offset], d[:byte_length])

-> weight(name)
  [tensor_buffer(name), tensor_buffer(name + ".scale"), tensor_buffer(name + ".global_scale")]

-> dispatch(spec)
  metal_dispatch_groups(queue, spec[0], spec[1], spec[2], spec[3])

-> one_sample(specs, concurrent)
  if concurrent then metal_batch_begin_concurrent(queue) else metal_batch_begin(queue)
  i = 0
  while i < WARMUP_ITERS
    j = 0
    while j < specs.size()
      dispatch(specs[j])
      j = j + 1
    if concurrent then metal_batch_barrier(queue)
    i = i + 1
  metal_batch_commit(queue)
  if concurrent then metal_batch_begin_concurrent(queue) else metal_batch_begin(queue)
  i = 0
  while i < MEASURE_ITERS
    j = 0
    while j < specs.size()
      dispatch(specs[j])
      j = j + 1
    if concurrent then metal_batch_barrier(queue)
    i = i + 1
  ms = metal_batch_commit_ms(queue, 0)
  (ms / MEASURE_ITERS) * ~1000.0

-> median3(a, b, c)
  lo = a
  if b < lo then lo = b
  if c < lo then lo = c
  hi = a
  if b > hi then hi = b
  if c > hi then hi = c
  a + b + c - lo - hi

-> time_specs(specs, concurrent)
  median3(one_sample(specs, concurrent), one_sample(specs, concurrent), one_sample(specs, concurrent))

-> max_diff(out_a, out_b, n)
  m = ~0.0
  i = 0
  while i < 16
    d = metal_buffer_read_f32(out_a, i) - metal_buffer_read_f32(out_b, i)
    if d < ~0.0 then d = ~0.0 - d
    if d > m then m = d
    i = i + 1
  m

-> run_dual(shape)
  label = shape[0]
  name0 = shape[1]
  n0 = shape[2]
  name1 = shape[3]
  n1 = shape[4]
  k = shape[5]
  input = shape[6]
  w0 = weight(name0)
  w1 = weight(name1)
  out0 = metal_buffer(device, n0 * 4)
  out1 = metal_buffer(device, n1 * 4)
  fused0 = metal_buffer(device, n0 * 4)
  fused1 = metal_buffer(device, n1 * 4)
  s0 = [r2_pipe, [w0[0], w0[1], input, out0, k, w0[2]], n0 / 8, 64]
  s1 = [r2_pipe, [w1[0], w1[1], input, out1, k, w1[2]], n1 / 8, 64]
  fused = [dual_pipe,
    [w0[0], w0[1], w1[0], w1[1], input, fused0, fused1,
     k, n0 / 8, w0[2], w1[2]], (n0 + n1) / 8, 64]

  # Validate before timing. Both paths use the same decode/reduction order.
  metal_batch_begin(queue)
  dispatch(s0)
  dispatch(s1)
  metal_batch_commit(queue)
  metal_batch_begin(queue)
  dispatch(fused)
  metal_batch_commit(queue)
  err0 = max_diff(out0, fused0, n0)
  err1 = max_diff(out1, fused1, n1)
  if err0 > ~0.005 || err1 > ~0.005
    raise label + " validation failed: " + err0.to_s + ", " + err1.to_s

  # Alternate the order of complete timing samples to reduce DVFS/cache bias.
  fused_us = time_specs([fused], false)
  serial_us = time_specs([s0, s1], false)
  concurrent_us = time_specs([s0, s1], true)
  << label + ": serial=" + serial_us.to_s + " us, concurrent=" + concurrent_us.to_s + " us, fused-grid=" + fused_us.to_s + " us, fused/serial=" + (fused_us / serial_us).to_s + "x, fused/concurrent=" + (fused_us / concurrent_us).to_s + "x, err=" + err0.to_s

layer0 = "model.language_model.layers.0."
layer3 = "model.language_model.layers.3."
run_dual(["linear QKV+Z", layer0 + "linear_attn.in_proj_qkv.weight", 10240,
  layer0 + "linear_attn.in_proj_z.weight", 6144, HIDDEN, x_hidden])
run_dual(["attention K+V", layer3 + "self_attn.k_proj.weight", 1024,
  layer3 + "self_attn.v_proj.weight", 1024, HIDDEN, x_hidden])
run_dual(["MLP gate+up", layer0 + "mlp.gate_proj.weight", FFN,
  layer0 + "mlp.up_proj.weight", FFN, HIDDEN, x_hidden])

# Down projection: test folding the dependent residual add into the qmv store.
down = weight(layer0 + "mlp.down_proj.weight")
plain_out = metal_buffer(device, HIDDEN * 4)
plain_res = metal_buffer(device, HIDDEN * 4)
fused_res = metal_buffer(device, HIDDEN * 4)
i = 0
while i < HIDDEN
  v = Math.cos(i * ~0.009) * ~0.125
  metal_buffer_write_f32(plain_res, i, v)
  metal_buffer_write_f32(fused_res, i, v)
  i = i + 1
plain = [r2_pipe, [down[0], down[1], x_ffn, plain_out, FFN, down[2]], HIDDEN / 8, 64]
add = [add_pipe, [plain_res, plain_out, HIDDEN], (HIDDEN + 255) / 256, 256]
fused_down = [res_pipe, [down[0], down[1], x_ffn, fused_res, FFN, down[2]], HIDDEN / 8, 64]
metal_batch_begin(queue)
dispatch(plain)
dispatch(add)
metal_batch_commit(queue)
metal_batch_begin(queue)
dispatch(fused_down)
metal_batch_commit(queue)
down_err = max_diff(plain_res, fused_res, HIDDEN)
if down_err > ~0.005 then raise "down+residual validation failed: " + down_err.to_s
plain_us = time_specs([plain, add], false)
fused_us = time_specs([fused_down], false)
<< "MLP down+residual: separate=" + plain_us.to_s + " us, fused=" + fused_us.to_s + " us, ratio=" + (fused_us / plain_us).to_s + "x, err=" + down_err.to_s

st.close
<< "fusion autotune done"
