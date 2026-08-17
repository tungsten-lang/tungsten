# Qwen3.8/27B-MLX real-weight tensor-layout experiment.
#
# The model checkpoint stores NVFP4 weights output-row-major. This benchmark
# repacks selected matrices to group-major (K-group first), validates the
# result, then compares batches 1..5 against the production row-major kernels.

use core/metal
use tungsten-llama/sharded_safetensors

MODEL_INDEX = "/Users/erik/.cache/tungsten/qwen3.8-27b-mlx/model.safetensors.index.json"
NVFP4_DIR = "bits/tungsten-llama/lib/kernels/nvfp4/"
MAX_K = 17408
WARMUP_ITERS = 2
MEASURE_ITERS = 5

device = metal_device()
queue = metal_queue(device)
st = Tungsten:Llama:ShardedSafetensors.new(MODEL_INDEX)

base_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled.metal"))
r2_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_r_2.metal"))
pair_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_pair.metal"))
triplet_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_triplet.metal"))
batch_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_batch.metal"))
col_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_colmajor.metal"))

pipe8 = metal_pipeline(base_lib, "nvfp4_matvec_mlx_scaled")
pipe_r2 = metal_pipeline(r2_lib, "nvfp4_matvec_mlx_scaled_r_2")
pair_pipe = metal_pipeline(pair_lib, "nvfp4_matvec_mlx_scaled_pair")
pair_r1_pipe = metal_pipeline(pair_lib, "nvfp4_matvec_mlx_scaled_pair_r1")
triplet_pipe = metal_pipeline(triplet_lib, "nvfp4_matvec_mlx_scaled_triplet")
triplet_r1_pipe = metal_pipeline(triplet_lib, "nvfp4_matvec_mlx_scaled_triplet_r1")
quad_pipe = metal_pipeline(batch_lib, "nvfp4_matvec_mlx_scaled_quad")
quint_pipe = metal_pipeline(batch_lib, "nvfp4_matvec_mlx_scaled_quint")
repack_w_pipe = metal_pipeline(col_lib, "nvfp4_repack_group_major_weights")
repack_s_pipe = metal_pipeline(col_lib, "nvfp4_repack_group_major_scales")
col_pipe = metal_pipeline(col_lib, "nvfp4_matvec_mlx_scaled_colmajor")

x = metal_buffer(device, 5 * MAX_K * 4)
i = 0
while i < MAX_K
  metal_buffer_write_f32(x, i, Math.sin(i * ~0.013))
  metal_buffer_write_f32(x, MAX_K + i, Math.cos(i * ~0.017) * ~0.75)
  metal_buffer_write_f32(x, 2 * MAX_K + i, Math.sin(i * ~0.007 + ~0.3) * ~0.5)
  metal_buffer_write_f32(x, 3 * MAX_K + i, Math.cos(i * ~0.011 + ~0.1) * ~0.625)
  metal_buffer_write_f32(x, 4 * MAX_K + i, Math.sin(i * ~0.019 + ~0.6) * ~0.375)
  i = i + 1

-> tensor_buffer(name)
  d = st.tensor(name)
  metal_buffer_for_mmap(device, st.mmap_for(name), d[:byte_offset], d[:byte_length])

-> weight(name)
  [tensor_buffer(name), tensor_buffer(name + ".scale"), tensor_buffer(name + ".global_scale")]

-> dispatch(spec)
  metal_dispatch_groups(queue, spec[0], spec[1], spec[2], spec[3])

-> sample(spec)
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
  median3(sample(spec), sample(spec), sample(spec))

-> repeated_sample(specs)
  metal_batch_begin(queue)
  i = 0
  while i < WARMUP_ITERS
    j = 0
    while j < specs.size()
      dispatch(specs[j])
      j = j + 1
    i = i + 1
  metal_batch_commit(queue)
  metal_batch_begin(queue)
  i = 0
  while i < MEASURE_ITERS
    j = 0
    while j < specs.size()
      dispatch(specs[j])
      j = j + 1
    i = i + 1
  ms = metal_batch_commit_ms(queue, 0)
  (ms / MEASURE_ITERS) * ~1000.0

-> time_specs(specs)
  median3(repeated_sample(specs), repeated_sample(specs), repeated_sample(specs))

-> capture(spec, out, n, batch)
  metal_batch_begin(queue)
  dispatch(spec)
  metal_batch_commit(queue)
  vals = []
  b = 0
  while b < batch
    i = 0
    while i < 16
      vals.push(metal_buffer_read_f32(out, b * n + i))
      i = i + 1
    b = b + 1
  vals

-> max_diff(a, b)
  m = ~0.0
  i = 0
  while i < a.size()
    d = a[i] - b[i]
    if d < ~0.0 then d = ~0.0 - d
    if d > m then m = d
    i = i + 1
  m

-> run_shape(shape)
  label = shape[0]
  name = shape[1]
  k = shape[2]
  n = shape[3]
  groups = k / 16
  w = weight(name)
  gm_w = metal_buffer(device, n * groups * 8)
  gm_s = metal_buffer(device, n * groups)
  total = n * groups
  repack_w = [repack_w_pipe, [w[0], gm_w, n, groups], (total + 255) / 256, 256]
  repack_s = [repack_s_pipe, [w[1], gm_s, n, groups], (total + 255) / 256, 256]

  # Repacking is a one-time load conversion; report its cost separately.
  metal_batch_begin(queue)
  dispatch(repack_w)
  dispatch(repack_s)
  repack_ms = metal_batch_commit_ms(queue, 0)

  # Compact the five activation rows for this K; the shared buffer was filled
  # at MAX_K strides so that all shapes could reuse it.
  packed_x = metal_buffer(device, 5 * k * 4)
  b = 0
  while b < 5
    i = 0
    while i < k
      metal_buffer_write_f32(packed_x, b * k + i, metal_buffer_read_f32(x, b * MAX_K + i))
      i = i + 1
    b = b + 1

  single_out = metal_buffer(device, n * 4)
  batch_out = metal_buffer(device, 5 * n * 4)
  single = [pipe_r2, [w[0], w[1], packed_x, single_out, k, w[2]], n / 8, 64]
  reference = []
  b = 0
  while b < 5
    # The column kernel is validated below against independent row-major
    # matvecs. Build each reference by copying one compact activation row.
    row_x = metal_buffer(device, k * 4)
    i = 0
    while i < k
      metal_buffer_write_f32(row_x, i, metal_buffer_read_f32(packed_x, b * k + i))
      i = i + 1
    ref_spec = [pipe8, [w[0], w[1], row_x, single_out, k, w[2]], n / 8, 64]
    reference = reference + capture(ref_spec, single_out, n, 1)
    b = b + 1

  # Row-major production candidates. Pair+pair and pair+triplet reflect the
  # lower-register composition that won the independent real-weight sweep.
  pair_args = [w[0], w[1], packed_x, batch_out, k, n, w[2]]
  pair = [pair_pipe, pair_args, (n + 3) / 4, 64]
  pair_r1 = [pair_r1_pipe, pair_args, (n + 1) / 2, 64]
  triplet = [triplet_pipe, pair_args, (n + 3) / 4, 64]
  triplet_r1 = [triplet_r1_pipe, pair_args, (n + 1) / 2, 64]
  quad = [quad_pipe, pair_args, (n + 1) / 2, 64]
  quint = [quint_pipe, pair_args, (n + 1) / 2, 64]
  row_times = [time_spec(single)]
  p2 = time_spec(pair)
  p2r1 = time_spec(pair_r1)
  if p2r1 < p2 then p2 = p2r1
  p3 = time_spec(triplet)
  p3r1 = time_spec(triplet_r1)
  if p3r1 < p3 then p3 = p3r1
  row_times.push(p2)
  row_times.push(p3)
  row_times.push(time_specs([pair, pair]))
  row_times.push(time_specs([pair, triplet]))

  << label + " K=" + k.to_s + " N=" + n.to_s + ": repack=" + repack_ms.to_s + " ms"
  b = 1
  while b <= 5
    best_col = ~1000000000.0
    best_tg = 0
    err = ~0.0
    tg_sizes = [64, 128, 256]
    t = 0
    while t < tg_sizes.size()
      tg = tg_sizes[t]
      col = [col_pipe, [gm_w, gm_s, packed_x, batch_out, k, n, b, w[2]], (n + tg - 1) / tg, tg]
      got = capture(col, batch_out, n, b)
      candidate_err = max_diff(got, reference.slice(0, b * 16))
      if candidate_err > err then err = candidate_err
      us = time_spec(col)
      if us < best_col
        best_col = us
        best_tg = tg
      t = t + 1
    << "  batch=" + b.to_s + ": row=" + row_times[b - 1].to_s + " us, group-major=" + best_col.to_s + " us (tg=" + best_tg.to_s + "), ratio=" + (best_col / row_times[b - 1]).to_s + "x, err=" + err.to_s
    if err > ~0.005 then raise label + " group-major validation failed"
    b = b + 1

shapes = [
  ["linear qkv", "model.language_model.layers.0.linear_attn.in_proj_qkv.weight", 5120, 10240],
  ["mlp down", "model.language_model.layers.0.mlp.down_proj.weight", 17408, 5120],
  ["lm head", "lm_head.weight", 5120, 248320]
]

<< "Qwen3.8/27B-MLX NVFP4 row-major vs group-major (real weights)"
i = 0
while i < shapes.size()
  run_shape(shapes[i])
  i = i + 1

st.close
<< "layout autotune done"
