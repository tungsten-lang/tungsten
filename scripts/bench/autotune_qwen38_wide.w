# Width-4/5 NVFP4 verification kernel bakeoff on real weights.
#
# Incumbent: nvfp4_matvec_mlx_scaled_{quad,quint} (one output row per SIMD
# group, BATCH*4 float4 activation loads per 2 u32 of weight).
# Candidate:  nvfp4_wide_b{3,4,5}_r{1,2,4} (ROWS output rows per SIMD group,
# activations loaded once and shared across them).
#
# Every candidate is validated against the production 8-row qmv on all BATCH
# rows before it is timed. The ROWS ladder is swept, not chosen.

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
pipe8 = metal_pipeline(base_lib, "nvfp4_matvec_mlx_scaled")
batch_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_batch.metal"))
quad_pipe = metal_pipeline(batch_lib, "nvfp4_matvec_mlx_scaled_quad")
quint_pipe = metal_pipeline(batch_lib, "nvfp4_matvec_mlx_scaled_quint")
trip_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_triplet.metal"))
trip_hoist_pipe = metal_pipeline(trip_lib, "nvfp4_matvec_mlx_scaled_triplet_hoist")
wide_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_wide.metal"))
mma_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_mma.metal"))
mma2_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_mma2.metal"))

# [name, pipeline, batch, rows]
cands = [
  ["b3_r2", metal_pipeline(wide_lib, "nvfp4_wide_b3_r2"), 3, 2],
  ["b3_r4", metal_pipeline(wide_lib, "nvfp4_wide_b3_r4"), 3, 4],
  ["b4_r1", metal_pipeline(wide_lib, "nvfp4_wide_b4_r1"), 4, 1],
  ["b4_r2", metal_pipeline(wide_lib, "nvfp4_wide_b4_r2"), 4, 2],
  ["b4_r3", metal_pipeline(wide_lib, "nvfp4_wide_b4_r3"), 4, 3],
  ["b4_HALF_r2", metal_pipeline(wide_lib, "nvfp4_wideh_b4_r2"), 4, 2],
  ["b4_HALF_r4", metal_pipeline(wide_lib, "nvfp4_wideh_b4_r4"), 4, 4],
  ["b5_HALF_r2", metal_pipeline(wide_lib, "nvfp4_wideh_b5_r2"), 5, 2],
  ["b3_HALF_r2", metal_pipeline(wide_lib, "nvfp4_wideh_b3_r2"), 3, 2],
  ["b4_r4", metal_pipeline(wide_lib, "nvfp4_wide_b4_r4"), 4, 4],
  ["b5_r1", metal_pipeline(wide_lib, "nvfp4_wide_b5_r1"), 5, 1],
  ["b5_r2", metal_pipeline(wide_lib, "nvfp4_wide_b5_r2"), 5, 2],
  ["b5_r3", metal_pipeline(wide_lib, "nvfp4_wide_b5_r3"), 5, 3],
  ["b5_r4", metal_pipeline(wide_lib, "nvfp4_wide_b5_r4"), 5, 4]
]

xs = []
b = 0
while b < 5
  xs.push(metal_buffer(device, MAX_K * 4))
  b = b + 1
x_wide = metal_buffer(device, 5 * MAX_K * 4)
i = 0
while i < MAX_K
  v0 = Math.sin(i * ~0.013)
  v1 = Math.cos(i * ~0.017) * ~0.75
  v2 = Math.sin(i * ~0.007 + ~0.3) * ~0.5
  v3 = Math.cos(i * ~0.011 + ~0.1) * ~0.625
  v4 = Math.sin(i * ~0.019 + ~0.6) * ~0.375
  metal_buffer_write_f32(xs[0], i, v0)
  metal_buffer_write_f32(xs[1], i, v1)
  metal_buffer_write_f32(xs[2], i, v2)
  metal_buffer_write_f32(xs[3], i, v3)
  metal_buffer_write_f32(xs[4], i, v4)
  i = i + 1

-> tensor_buffer(name)
  d = st.tensor(name)
  metal_buffer_for_mmap(device, st.mmap_for(name), d[:byte_offset], d[:byte_length])

-> weight(name)
  [tensor_buffer(name), tensor_buffer(name + ".scale"), tensor_buffer(name + ".global_scale")]

-> dispatch(spec)
  metal_dispatch_groups(queue, spec[0], spec[1], spec[2], spec[3])

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

-> capture_rows_first16(spec, out, row_stride, batch)
  metal_batch_begin(queue)
  dispatch(spec)
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

-> max_diff16(a, b)
  m = ~0.0
  i = 0
  while i < a.size()
    d = a[i] - b[i]
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

-> ref_prefix(reference, batch)
  r = []
  b = 0
  while b < batch
    i = 0
    while i < 16
      r.push(reference[b * 16 + i])
      i = i + 1
    b = b + 1
  r

-> run_shape(shape)
  label = shape[0]
  name = shape[1]
  k = shape[2]
  n = shape[3]
  w = weight(name)
  single_out = metal_buffer(device, n * 4)

  # Per-row references from the production single-row qmv.
  reference = []
  b = 0
  while b < 5
    args = [w[0], w[1], xs[b], single_out, k, w[2]]
    reference = reference + capture_first16([pipe8, args, n / 8, 64], single_out)
    b = b + 1

  i = 0
  while i < k
    metal_buffer_write_f32(x_wide, i, metal_buffer_read_f32(xs[0], i))
    metal_buffer_write_f32(x_wide, k + i, metal_buffer_read_f32(xs[1], i))
    metal_buffer_write_f32(x_wide, 2 * k + i, metal_buffer_read_f32(xs[2], i))
    metal_buffer_write_f32(x_wide, 3 * k + i, metal_buffer_read_f32(xs[3], i))
    metal_buffer_write_f32(x_wide, 4 * k + i, metal_buffer_read_f32(xs[4], i))
    i = i + 1

  out5 = metal_buffer(device, 5 * n * 4)
  args = [w[0], w[1], x_wide, out5, k, n, w[2]]

  # Incumbents.
  trip_spec = [trip_hoist_pipe, args, (n + 3) / 4, 64]
  quad_spec = [quad_pipe, args, (n + 1) / 2, 64]
  quint_spec = [quint_pipe, args, (n + 1) / 2, 64]
  trip_err = max_diff16(capture_rows_first16(trip_spec, out5, n, 3), ref_prefix(reference, 3))
  quad_err = max_diff16(capture_rows_first16(quad_spec, out5, n, 4), ref_prefix(reference, 4))
  quint_err = max_diff16(capture_rows_first16(quint_spec, out5, n, 5), ref_prefix(reference, 5))
  if trip_err > ~0.005 || quad_err > ~0.005 || quint_err > ~0.005
    raise label + " incumbent validation failed"
  trip_us = time_spec(trip_spec)
  quad_us = time_spec(quad_spec)
  quint_us = time_spec(quint_spec)

  msg = label + " K=" + k.to_s + " N=" + n.to_s
  << msg
  << "  incumbent: triplet_hoist=" + trip_us.to_s + " quad=" + quad_us.to_s + " quint=" + quint_us.to_s

  ci = 0
  while ci < cands.size()
    c = cands[ci]
    batch = c[2]
    rows = c[3]
    if rows == 0 - 1
      groups = (n + 127) / 128
      spec = [c[1], args, groups, 128]
    elsif rows == 0
      groups = (n + 7) / 8
      spec = [c[1], args, groups, 32]
    else
      per_tg = 2 * rows
      groups = (n + per_tg - 1) / per_tg
      spec = [c[1], args, groups, 64]
    err = max_diff16(capture_rows_first16(spec, out5, n, batch), ref_prefix(reference, batch))
    if err > ~0.005
      raise label + " " + c[0] + " validation failed: err=" + err.to_s
    us = time_spec(spec)
    base = quint_us
    if batch == 3 then base = trip_us
    if batch == 4 then base = quad_us
    << "  " + c[0] + " = " + us.to_s + " us  (" + (base / us).to_s + "x vs incumbent, err=" + err.to_s + ")"
    ci = ci + 1

shapes = [
  ["linear qkv", "model.language_model.layers.0.linear_attn.in_proj_qkv.weight", 5120, 10240],
  ["linear z", "model.language_model.layers.0.linear_attn.in_proj_z.weight", 5120, 6144],
  ["linear/full out", "model.language_model.layers.0.linear_attn.out_proj.weight", 6144, 5120],
  ["attention q", "model.language_model.layers.3.self_attn.q_proj.weight", 5120, 12288],
  ["attention k", "model.language_model.layers.3.self_attn.k_proj.weight", 5120, 1024],
  ["mlp gate", "model.language_model.layers.0.mlp.gate_proj.weight", 5120, 17408],
  ["mlp down", "model.language_model.layers.0.mlp.down_proj.weight", 17408, 5120],
  ["lm head", "lm_head.weight", 5120, 248320],
  ["mtp fuse", "mtp.fc.weight", 10240, 5120],
  ["mtp q", "mtp.layers.0.self_attn.q_proj.weight", 5120, 12288]
]

<< "Qwen3.8/27B-MLX wide-verify bakeoff (real weights, median of 3x" + MEASURE_ITERS.to_s + ")"
i = 0
while i < shapes.size()
  run_shape(shapes[i])
  i = i + 1

st.close
<< "wide bakeoff done"
