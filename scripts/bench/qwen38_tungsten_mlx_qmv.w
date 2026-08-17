# Compare Tungsten's production Qwen3.8 NVFP4 Metal kernels with the actual
# MLX C API on the same tensors and activations.
#
# Build through build_qwen38_tungsten_mlx_qmv.sh. The MLX lane calls
# mlx_quantized_matmul and evaluates its result before returning to Tungsten;
# this is the synchronization contract required by a hybrid Metal/MLX graph.

use core/metal
use tungsten-llama/sharded_safetensors

MODEL_INDEX = "/Users/erik/.cache/tungsten/qwen3.8-27b-mlx/model.safetensors.index.json"
NVFP4_DIR = "bits/tungsten-llama/lib/kernels/nvfp4/"
MAX_K = 17408
MAX_N = 248320
WARMUPS = 3

device = metal_device()
queue = metal_queue(device)
st = Tungsten:Llama:ShardedSafetensors.new(MODEL_INDEX)

r2_pipe = metal_pipeline(
  metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_r_2.metal")),
  "nvfp4_matvec_mlx_scaled_r_2")
pair_pipe = metal_pipeline(
  metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_pair.metal")),
  "nvfp4_matvec_mlx_scaled_pair")

# Keep ordinary typed arrays at the C bridge boundary: mlx_bridge.c unwraps a
# WArray, whereas metal_array is an opaque Metal-backed object. Mirror the
# exact same activation values into the custom-kernel buffer.
x = f32[2 * MAX_K]
y_mlx = f32[2 * MAX_N]
x_buf = metal_buffer(device, 2 * MAX_K * 4)
y_tungsten = metal_buffer(device, 2 * MAX_N * 4)

i = 0
while i < MAX_K
  v = Math.sin(i * ~0.013)
  x[i] = v
  metal_buffer_write_f32(x_buf, i, v)
  i = i + 1

-> tensor_buffer(name)
  d = st.tensor(name)
  metal_buffer_for_mmap(device, st.mmap_for(name), d[:byte_offset], d[:byte_length])

-> weight(name)
  [tensor_buffer(name), tensor_buffer(name + ".scale"),
   tensor_buffer(name + ".global_scale")]

-> load_mlx_shard(name)
  shard = st.weight_map[name]
  path = st.index_dir + "/" + shard
  ok = ccall("w_mlxb_load_safetensors", path)
  if ok != 1 then raise "MLX failed to load " + path

-> median3(a, b, c)
  lo = a
  if b < lo then lo = b
  if c < lo then lo = c
  hi = a
  if b > hi then hi = b
  if c > hi then hi = c
  a + b + c - lo - hi

-> tungsten_single_sample(w, k, n, iterations)
  metal_batch_begin(queue)
  i = 0
  while i < WARMUPS
    metal_dispatch_groups(queue, r2_pipe,
      [w[0], w[1], x_buf, y_tungsten, k, w[2]], n / 8, 64)
    i = i + 1
  metal_batch_commit(queue)
  metal_batch_begin(queue)
  i = 0
  while i < iterations
    metal_dispatch_groups(queue, r2_pipe,
      [w[0], w[1], x_buf, y_tungsten, k, w[2]], n / 8, 64)
    i = i + 1
  ms = metal_batch_commit_ms(queue, 0)
  ms * ~1000.0 / iterations

-> tungsten_pair_sample(w, k, n, iterations)
  metal_batch_begin(queue)
  i = 0
  while i < WARMUPS
    metal_dispatch_groups(queue, pair_pipe,
      [w[0], w[1], x_buf, y_tungsten, k, n, w[2]], (n + 3) / 4, 64)
    i = i + 1
  metal_batch_commit(queue)
  metal_batch_begin(queue)
  i = 0
  while i < iterations
    metal_dispatch_groups(queue, pair_pipe,
      [w[0], w[1], x_buf, y_tungsten, k, n, w[2]], (n + 3) / 4, 64)
    i = i + 1
  ms = metal_batch_commit_ms(queue, 0)
  ms * ~1000.0 / iterations

-> mlx_sample(name, k, batch, iterations)
  ccall("w_mlxb_bench_quantized_matmul_nvfp4_scaled",
    name, name + ".scale", name + ".global_scale",
    x, k, batch, WARMUPS, iterations)

-> validate(name, w, k, n, batch)
  ok = ccall("w_mlxb_quantized_matmul_nvfp4_scaled",
    name, name + ".scale", name + ".global_scale",
    x, k, y_mlx, n, batch)
  if ok != 1 then raise "MLX correctness call failed for " + name

  metal_batch_begin(queue)
  if batch == 1
    metal_dispatch_groups(queue, r2_pipe,
      [w[0], w[1], x_buf, y_tungsten, k, w[2]], n / 8, 64)
  else
    metal_dispatch_groups(queue, pair_pipe,
      [w[0], w[1], x_buf, y_tungsten, k, n, w[2]], (n + 3) / 4, 64)
  metal_batch_commit(queue)

  err = ~0.0
  row = 0
  while row < batch
    j = 0
    while j < 16
      at = row * n + j
      d = y_mlx[at] - metal_buffer_read_f32(y_tungsten, at)
      if d < ~0.0 then d = ~0.0 - d
      if d > err then err = d
      j = j + 1
    row = row + 1
  err

-> run_shape(shape)
  label = shape[0]
  name = shape[1]
  k = shape[2]
  n = shape[3]
  iterations = shape[5]

  # The pair kernel and MLX batch=2 both use tightly packed activation rows.
  i = 0
  while i < k
    v = Math.cos(i * ~0.017) * ~0.75
    x[k + i] = v
    metal_buffer_write_f32(x_buf, k + i, v)
    i = i + 1

  load_mlx_shard(name)
  w = weight(name)
  err1 = validate(name, w, k, n, 1)
  err2 = validate(name, w, k, n, 2)
  if err1 > ~0.01 || err2 > ~0.01
    raise label + " parity failed: single=" + err1.to_s + ", pair=" + err2.to_s

  t1 = median3(
    tungsten_single_sample(w, k, n, iterations),
    tungsten_single_sample(w, k, n, iterations),
    tungsten_single_sample(w, k, n, iterations))
  m1 = median3(
    mlx_sample(name, k, 1, iterations),
    mlx_sample(name, k, 1, iterations),
    mlx_sample(name, k, 1, iterations))
  t2 = median3(
    tungsten_pair_sample(w, k, n, iterations),
    tungsten_pair_sample(w, k, n, iterations),
    tungsten_pair_sample(w, k, n, iterations))
  m2 = median3(
    mlx_sample(name, k, 2, iterations),
    mlx_sample(name, k, 2, iterations),
    mlx_sample(name, k, 2, iterations))

  msg = label + " K=" + k.to_s + " N=" + n.to_s
  msg = msg + ": tungsten=" + t1.to_s + " us, mlx=" + m1.to_s
  msg = msg + " us, mlx/tungsten=" + (m1 / t1).to_s + "x, err=" + err1.to_s
  << msg
  pair_msg = "  pair: tungsten=" + t2.to_s + " us, mlx=" + m2.to_s
  pair_msg = pair_msg + " us, mlx/tungsten=" + (m2 / t2).to_s + "x, err=" + err2.to_s
  << pair_msg
  [t1, m1, t2, m2]

# count is the number of projections of this shape in one target-model pass.
# The shared 6144x5120 shape covers both linear-attention and full-attention
# output projections; the 1024x5120 shape covers full-attention K and V.
shapes = [
  ["linear qkv", "model.language_model.layers.0.linear_attn.in_proj_qkv.weight", 5120, 10240, 48, 12],
  ["linear z", "model.language_model.layers.0.linear_attn.in_proj_z.weight", 5120, 6144, 48, 12],
  ["attention/linear out", "model.language_model.layers.0.linear_attn.out_proj.weight", 6144, 5120, 64, 12],
  ["attention q", "model.language_model.layers.3.self_attn.q_proj.weight", 5120, 12288, 16, 12],
  ["attention k/v", "model.language_model.layers.3.self_attn.k_proj.weight", 5120, 1024, 32, 20],
  ["mlp gate/up", "model.language_model.layers.0.mlp.gate_proj.weight", 5120, 17408, 128, 8],
  ["mlp down", "model.language_model.layers.0.mlp.down_proj.weight", 17408, 5120, 64, 8],
  ["lm head", "lm_head.weight", 5120, 248320, 1, 3]
]

<< "Qwen3.8 actual MLX C API vs Tungsten Metal QMV"
<< "MLX lane: mlx_quantized_matmul(nvfp4) * checkpoint global_scale, eval per call"
weighted_t1 = ~0.0
weighted_m1 = ~0.0
weighted_t2 = ~0.0
weighted_m2 = ~0.0
i = 0
while i < shapes.size()
  result = run_shape(shapes[i])
  count = shapes[i][4]
  weighted_t1 = weighted_t1 + result[0] * count
  weighted_m1 = weighted_m1 + result[1] * count
  weighted_t2 = weighted_t2 + result[2] * count
  weighted_m2 = weighted_m2 + result[3] * count
  i = i + 1

summary1 = "weighted projection time, serial target pass: tungsten="
summary1 = summary1 + (weighted_t1 / ~1000.0).to_s + " ms, mlx-bridge="
summary1 = summary1 + (weighted_m1 / ~1000.0).to_s + " ms"
<< summary1
summary2 = "weighted projection time, two-row target pass: tungsten="
summary2 = summary2 + (weighted_t2 / ~1000.0).to_s + " ms, mlx-bridge="
summary2 = summary2 + (weighted_m2 / ~1000.0).to_s + " ms"
<< summary2

st.close
