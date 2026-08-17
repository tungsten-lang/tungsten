# Qwen3.8/27B-MLX NVFP4 matvec row-grouping autotune on real weights.
#
# The sweep covers both single-token qmv row grouping and the MTP-1 two-token
# verification primitive. Every candidate is checked against the production
# 8-row qmv before timing on the model's real mmap-backed weights.

use core/metal
use tungsten-llama/sharded_safetensors

MODEL_INDEX = "/Users/erik/.cache/tungsten/qwen3.8-27b-mlx/model.safetensors.index.json"
NVFP4_DIR = "bits/tungsten-llama/lib/kernels/nvfp4/"
MAX_K = 17408
WARMUP_ITERS = 3
MEASURE_ITERS = 8

device = metal_device()
queue = metal_queue(device)
st = Tungsten:Llama:ShardedSafetensors.new(MODEL_INDEX)

base_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled.metal"))
rows_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_rows.metal"))
r2_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_r_2.metal"))
pipe4 = metal_pipeline(rows_lib, "nvfp4_matvec_mlx_scaled_4r")
pipe8 = metal_pipeline(base_lib, "nvfp4_matvec_mlx_scaled")
pipe16 = metal_pipeline(rows_lib, "nvfp4_matvec_mlx_scaled_16r")
pipe_r2 = metal_pipeline(r2_lib, "nvfp4_matvec_mlx_scaled_r_2")
pair_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_pair.metal"))
pair_pipe = metal_pipeline(pair_lib, "nvfp4_matvec_mlx_scaled_pair")
pair_r1_pipe = metal_pipeline(pair_lib, "nvfp4_matvec_mlx_scaled_pair_r1")
triplet_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_triplet.metal"))
triplet_pipe = metal_pipeline(triplet_lib, "nvfp4_matvec_mlx_scaled_triplet")
triplet_r1_pipe = metal_pipeline(triplet_lib, "nvfp4_matvec_mlx_scaled_triplet_r1")
batch_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_batch.metal"))
quad_pipe = metal_pipeline(batch_lib, "nvfp4_matvec_mlx_scaled_quad")
quint_pipe = metal_pipeline(batch_lib, "nvfp4_matvec_mlx_scaled_quint")

x0 = metal_buffer(device, MAX_K * 4)
x1 = metal_buffer(device, MAX_K * 4)
x2 = metal_buffer(device, MAX_K * 4)
x3 = metal_buffer(device, MAX_K * 4)
x4 = metal_buffer(device, MAX_K * 4)
x_pair = metal_buffer(device, 2 * MAX_K * 4)
x_triplet = metal_buffer(device, 3 * MAX_K * 4)
x_quad = metal_buffer(device, 4 * MAX_K * 4)
x_quint = metal_buffer(device, 5 * MAX_K * 4)
i = 0
while i < MAX_K
  v0 = Math.sin(i * ~0.013)
  v1 = Math.cos(i * ~0.017) * ~0.75
  metal_buffer_write_f32(x0, i, v0)
  metal_buffer_write_f32(x1, i, v1)
  metal_buffer_write_f32(x2, i, Math.sin(i * ~0.007 + ~0.3) * ~0.5)
  metal_buffer_write_f32(x3, i, Math.cos(i * ~0.011 + ~0.1) * ~0.625)
  metal_buffer_write_f32(x4, i, Math.sin(i * ~0.019 + ~0.6) * ~0.375)
  i = i + 1

-> tensor_buffer(name)
  d = st.tensor(name)
  metal_buffer_for_mmap(device, st.mmap_for(name), d[:byte_offset], d[:byte_length])

-> weight(name)
  [tensor_buffer(name), tensor_buffer(name + ".scale"), tensor_buffer(name + ".global_scale")]

-> dispatch(spec)
  pipe = spec[0]
  args = spec[1]
  groups = spec[2]
  threads = spec[3]
  metal_dispatch_groups(queue, pipe, args, groups, threads)

-> capture_first16(spec, out)
  metal_batch_begin(queue)
  dispatch(spec)
  metal_batch_commit(queue)
  vals = []
  i = 0
  while i < 16
    vals.push(metal_buffer_read_f32(out, i))
    i = i + 1
  vals

-> max_diff_first16(spec, out, baseline)
  got = capture_first16(spec, out)
  m = ~0.0
  i = 0
  while i < 16
    d = got[i] - baseline[i]
    if d < ~0.0 then d = ~0.0 - d
    if d > m then m = d
    i = i + 1
  m

-> one_sample(spec)
  metal_batch_begin(queue)
  i = 0
  while i < WARMUP_ITERS
    dispatch(spec)
    i = i + 1
  metal_batch_commit(queue)
  metal_batch_begin(queue)
  i = 0
  while i < MEASURE_ITERS
    dispatch(spec)
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

-> time_spec(spec)
  median3(one_sample(spec), one_sample(spec), one_sample(spec))

-> capture_pair_first16(spec, out, row_stride)
  metal_batch_begin(queue)
  dispatch(spec)
  metal_batch_commit(queue)
  vals = []
  row = 0
  while row < 2
    i = 0
    while i < 16
      vals.push(metal_buffer_read_f32(out, row * row_stride + i))
      i = i + 1
    row = row + 1
  vals

-> max_diff16(a, b)
  m = ~0.0
  i = 0
  while i < a.size()
    d = a[i] - b[i]
    if d < ~0.0 then d = ~0.0 - d
    if d > m then m = d
    i = i + 1
  m

-> one_pair_sample(spec)
  metal_batch_begin(queue)
  i = 0
  while i < WARMUP_ITERS
    dispatch(spec)
    i = i + 1
  metal_batch_commit(queue)
  metal_batch_begin(queue)
  i = 0
  while i < MEASURE_ITERS
    dispatch(spec)
    i = i + 1
  ms = metal_batch_commit_ms(queue, 0)
  (ms / MEASURE_ITERS) * ~1000.0

-> one_two_single_sample(spec)
  metal_batch_begin(queue)
  i = 0
  while i < WARMUP_ITERS
    dispatch(spec)
    dispatch(spec)
    i = i + 1
  metal_batch_commit(queue)
  metal_batch_begin(queue)
  i = 0
  while i < MEASURE_ITERS
    dispatch(spec)
    dispatch(spec)
    i = i + 1
  ms = metal_batch_commit_ms(queue, 0)
  (ms / MEASURE_ITERS) * ~1000.0

-> time_pair(spec)
  median3(one_pair_sample(spec), one_pair_sample(spec), one_pair_sample(spec))

-> capture_triplet_first16(spec, out, row_stride)
  metal_batch_begin(queue)
  dispatch(spec)
  metal_batch_commit(queue)
  vals = []
  row = 0
  while row < 3
    i = 0
    while i < 16
      vals.push(metal_buffer_read_f32(out, row * row_stride + i))
      i = i + 1
    row = row + 1
  vals

-> one_triplet_sample(spec)
  metal_batch_begin(queue)
  i = 0
  while i < WARMUP_ITERS
    dispatch(spec)
    i = i + 1
  metal_batch_commit(queue)
  metal_batch_begin(queue)
  i = 0
  while i < MEASURE_ITERS
    dispatch(spec)
    i = i + 1
  ms = metal_batch_commit_ms(queue, 0)
  (ms / MEASURE_ITERS) * ~1000.0

-> time_triplet(spec)
  median3(one_triplet_sample(spec), one_triplet_sample(spec), one_triplet_sample(spec))

-> one_three_single_sample(spec)
  metal_batch_begin(queue)
  i = 0
  while i < WARMUP_ITERS
    dispatch(spec)
    dispatch(spec)
    dispatch(spec)
    i = i + 1
  metal_batch_commit(queue)
  metal_batch_begin(queue)
  i = 0
  while i < MEASURE_ITERS
    dispatch(spec)
    dispatch(spec)
    dispatch(spec)
    i = i + 1
  ms = metal_batch_commit_ms(queue, 0)
  (ms / MEASURE_ITERS) * ~1000.0

-> time_three_single(spec)
  median3(one_three_single_sample(spec), one_three_single_sample(spec), one_three_single_sample(spec))

-> time_two_single(spec)
  median3(one_two_single_sample(spec), one_two_single_sample(spec), one_two_single_sample(spec))

-> capture_batch_first16(spec)
  dispatch_spec = spec[0]
  out = spec[1]
  row_stride = spec[2]
  batch = spec[3]
  metal_batch_begin(queue)
  dispatch(dispatch_spec)
  metal_batch_commit(queue)
  vals = []
  row = 0
  while row < batch
    i = 0
    while i < 16
      vals.push(metal_buffer_read_f32(out, row * row_stride + i))
      i = i + 1
    row = row + 1
  vals

-> one_repeated_single_sample(spec)
  dispatch_spec = spec[0]
  repeats = spec[1]
  metal_batch_begin(queue)
  i = 0
  while i < WARMUP_ITERS
    j = 0
    while j < repeats
      dispatch(dispatch_spec)
      j = j + 1
    i = i + 1
  metal_batch_commit(queue)
  metal_batch_begin(queue)
  i = 0
  while i < MEASURE_ITERS
    j = 0
    while j < repeats
      dispatch(dispatch_spec)
      j = j + 1
    i = i + 1
  ms = metal_batch_commit_ms(queue, 0)
  (ms / MEASURE_ITERS) * ~1000.0

-> time_repeated_single(spec)
  median3(one_repeated_single_sample(spec), one_repeated_single_sample(spec), one_repeated_single_sample(spec))

-> run_shape(shape)
  label = shape[0]
  name = shape[1]
  k = shape[2]
  n = shape[3]
  w = weight(name)
  out = metal_buffer(device, n * 4)
  args = [w[0], w[1], x0, out, k, w[2]]
  s4 = [pipe4, args, n / 4, 32]
  s8 = [pipe8, args, n / 8, 64]
  s16 = [pipe16, args, n / 16, 128]
  sr2 = [pipe_r2, args, n / 8, 64]

  baseline = capture_first16(s8, out)
  err4 = max_diff_first16(s4, out, baseline)
  err16 = max_diff_first16(s16, out, baseline)
  err_r2 = max_diff_first16(sr2, out, baseline)
  if err4 > ~0.005 || err16 > ~0.005 || err_r2 > ~0.005
    raise label + " validation failed: err4=" + err4.to_s + ", err16=" + err16.to_s + ", err_r2=" + err_r2.to_s

  us4 = time_spec(s4)
  us8 = time_spec(s8)
  us16 = time_spec(s16)
  us_r2 = time_spec(sr2)
  winner = "4r"
  best = us4
  if us8 < best
    winner = "8r"
    best = us8
  if us16 < best
    winner = "16r"
    best = us16
  if us_r2 < best
    winner = "r_2-qdot"
    best = us_r2
  msg = label + " K=" + k.to_s + " N=" + n.to_s
  msg = msg + ": 4r=" + us4.to_s + " us, 8r=" + us8.to_s
  msg = msg + " us, 16r=" + us16.to_s + " us, r_2-qdot=" + us_r2.to_s
  msg = msg + " us -> " + winner + " (r_2 err=" + err_r2.to_s + ")"
  << msg

  # Pair correctness uses distinct activation rows. Build the two single-qmv
  # references separately, then compare both rows of the shared-weight pass.
  ref0 = capture_first16(s8, out)
  args1 = [w[0], w[1], x1, out, k, w[2]]
  ref1 = capture_first16([pipe8, args1, n / 8, 64], out)
  reference = ref0 + ref1
  pair_out = metal_buffer(device, 2 * n * 4)
  i = 0
  while i < k
    metal_buffer_write_f32(x_pair, i, Math.sin(i * ~0.013))
    metal_buffer_write_f32(x_pair, k + i, Math.cos(i * ~0.017) * ~0.75)
    i = i + 1
  pair_args = [w[0], w[1], x_pair, pair_out, k, n, w[2]]
  pair_spec = [pair_pipe, pair_args, (n + 3) / 4, 64]
  pair_r1_spec = [pair_r1_pipe, pair_args, (n + 1) / 2, 64]
  pair_vals = capture_pair_first16(pair_spec, pair_out, n)
  pair_err = max_diff16(pair_vals, reference)
  pair_r1_vals = capture_pair_first16(pair_r1_spec, pair_out, n)
  pair_r1_err = max_diff16(pair_r1_vals, reference)
  if pair_err > ~0.005 || pair_r1_err > ~0.005
    raise label + " pair validation failed: r2=" + pair_err.to_s + ", r1=" + pair_r1_err.to_s
  pair_us = time_pair(pair_spec)
  pair_r1_us = time_pair(pair_r1_spec)
  two_us = time_two_single(s8)
  pair_best = pair_us
  pair_winner = "r2"
  if pair_r1_us < pair_best
    pair_best = pair_r1_us
    pair_winner = "r1"
  speedup = two_us / pair_best
  pair_msg = "  pair: two-qmv=" + two_us.to_s + " us, r2=" + pair_us.to_s
  pair_msg = pair_msg + " us, r1=" + pair_r1_us.to_s + " us -> " + pair_winner
  pair_msg = pair_msg + ", speedup=" + speedup.to_s + "x, err=" + pair_err.to_s
  << pair_msg

  args2 = [w[0], w[1], x2, out, k, w[2]]
  ref2 = capture_first16([pipe8, args2, n / 8, 64], out)
  triplet_reference = reference + ref2
  triplet_out = metal_buffer(device, 3 * n * 4)
  i = 0
  while i < k
    metal_buffer_write_f32(x_triplet, i, Math.sin(i * ~0.013))
    metal_buffer_write_f32(x_triplet, k + i, Math.cos(i * ~0.017) * ~0.75)
    metal_buffer_write_f32(x_triplet, 2 * k + i, Math.sin(i * ~0.007 + ~0.3) * ~0.5)
    i = i + 1
  triplet_args = [w[0], w[1], x_triplet, triplet_out, k, n, w[2]]
  triplet_spec = [triplet_pipe, triplet_args, (n + 3) / 4, 64]
  triplet_r1_spec = [triplet_r1_pipe, triplet_args, (n + 1) / 2, 64]
  triplet_vals = capture_triplet_first16(triplet_spec, triplet_out, n)
  triplet_err = max_diff16(triplet_vals, triplet_reference)
  triplet_r1_vals = capture_triplet_first16(triplet_r1_spec, triplet_out, n)
  triplet_r1_err = max_diff16(triplet_r1_vals, triplet_reference)
  if triplet_err > ~0.005 || triplet_r1_err > ~0.005
    raise label + " triplet validation failed: r2=" + triplet_err.to_s + ", r1=" + triplet_r1_err.to_s
  triplet_us = time_triplet(triplet_spec)
  triplet_r1_us = time_triplet(triplet_r1_spec)
  three_us = time_three_single(s8)
  triplet_best = triplet_us
  if triplet_r1_us < triplet_best then triplet_best = triplet_r1_us
  triplet_speedup = three_us / triplet_best
  triplet_msg = "  triplet: three-qmv=" + three_us.to_s + " us, r2=" + triplet_us.to_s
  triplet_msg = triplet_msg + " us, r1=" + triplet_r1_us.to_s
  triplet_msg = triplet_msg + " us, speedup=" + triplet_speedup.to_s + "x, err=" + triplet_err.to_s
  << triplet_msg

  args3 = [w[0], w[1], x3, out, k, w[2]]
  args4 = [w[0], w[1], x4, out, k, w[2]]
  ref3 = capture_first16([pipe8, args3, n / 8, 64], out)
  ref4 = capture_first16([pipe8, args4, n / 8, 64], out)
  quad_reference = triplet_reference + ref3
  quint_reference = quad_reference + ref4
  quad_out = metal_buffer(device, 4 * n * 4)
  quint_out = metal_buffer(device, 5 * n * 4)
  i = 0
  while i < k
    v0 = Math.sin(i * ~0.013)
    v1 = Math.cos(i * ~0.017) * ~0.75
    v2 = Math.sin(i * ~0.007 + ~0.3) * ~0.5
    v3 = Math.cos(i * ~0.011 + ~0.1) * ~0.625
    v4 = Math.sin(i * ~0.019 + ~0.6) * ~0.375
    metal_buffer_write_f32(x_quad, i, v0)
    metal_buffer_write_f32(x_quad, k + i, v1)
    metal_buffer_write_f32(x_quad, 2 * k + i, v2)
    metal_buffer_write_f32(x_quad, 3 * k + i, v3)
    metal_buffer_write_f32(x_quint, i, v0)
    metal_buffer_write_f32(x_quint, k + i, v1)
    metal_buffer_write_f32(x_quint, 2 * k + i, v2)
    metal_buffer_write_f32(x_quint, 3 * k + i, v3)
    metal_buffer_write_f32(x_quint, 4 * k + i, v4)
    i = i + 1
  quad_args = [w[0], w[1], x_quad, quad_out, k, n, w[2]]
  quint_args = [w[0], w[1], x_quint, quint_out, k, n, w[2]]
  quad_spec = [quad_pipe, quad_args, (n + 1) / 2, 64]
  quint_spec = [quint_pipe, quint_args, (n + 1) / 2, 64]
  quad_vals = capture_batch_first16([quad_spec, quad_out, n, 4])
  quint_vals = capture_batch_first16([quint_spec, quint_out, n, 5])
  quad_err = max_diff16(quad_vals, quad_reference)
  quint_err = max_diff16(quint_vals, quint_reference)
  if quad_err > ~0.005 || quint_err > ~0.005
    raise label + " deep batch validation failed: quad=" + quad_err.to_s + ", quint=" + quint_err.to_s
  quad_us = time_triplet(quad_spec)
  quint_us = time_triplet(quint_spec)
  four_us = time_repeated_single([s8, 4])
  five_us = time_repeated_single([s8, 5])
  deep_msg = "  deep: four-qmv=" + four_us.to_s + " us, quad=" + quad_us.to_s
  deep_msg = deep_msg + " us (" + (four_us / quad_us).to_s + "x), five-qmv=" + five_us.to_s
  deep_msg = deep_msg + " us, quint=" + quint_us.to_s + " us (" + (five_us / quint_us).to_s
  deep_msg = deep_msg + "x), err=" + quint_err.to_s
  << deep_msg

shapes = [
  ["linear qkv", "model.language_model.layers.0.linear_attn.in_proj_qkv.weight", 5120, 10240],
  ["linear z", "model.language_model.layers.0.linear_attn.in_proj_z.weight", 5120, 6144],
  ["linear/full out", "model.language_model.layers.0.linear_attn.out_proj.weight", 6144, 5120],
  ["attention q", "model.language_model.layers.3.self_attn.q_proj.weight", 5120, 12288],
  ["attention k", "model.language_model.layers.3.self_attn.k_proj.weight", 5120, 1024],
  ["mlp gate", "model.language_model.layers.0.mlp.gate_proj.weight", 5120, 17408],
  ["mlp down", "model.language_model.layers.0.mlp.down_proj.weight", 17408, 5120],
  ["lm head", "lm_head.weight", 5120, 248320],
  ["lm draft prefix", "lm_head.weight", 5120, 98304],
  ["mtp fuse", "mtp.fc.weight", 10240, 5120],
  ["mtp q", "mtp.layers.0.self_attn.q_proj.weight", 5120, 12288]
]

<< "Qwen3.8/27B-MLX NVFP4 qmv/pair autotune (real weights, median of 3x" + MEASURE_ITERS.to_s + ")"
i = 0
while i < shapes.size()
  run_shape(shapes[i])
  i = i + 1

st.close
<< "autotune done"
