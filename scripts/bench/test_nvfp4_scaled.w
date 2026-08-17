# Focused correctness check for Ollama's newer scaled-NVFP4 tensor layout.
# References were computed with MLX dequantize(mode="nvfp4") followed by the
# tensor's f32 global_scale. Inputs are deterministic real Qwen3.8 weights.

use core/metal
use tungsten-llama/sharded_safetensors

MODEL_INDEX = "/Users/erik/.cache/tungsten/qwen3.8-27b-mlx/model.safetensors.index.json"
NVFP4_DIR = "bits/tungsten-llama/lib/kernels/nvfp4/"
HIDDEN = 5120
QKV_DIM = 10240
INTERMEDIATE = 17408

device = metal_device()
queue = metal_queue(device)
st = Tungsten:Llama:ShardedSafetensors.new(MODEL_INDEX)

matvec_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled.metal")), "nvfp4_matvec_mlx_scaled")
r2_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_r_2.metal")), "nvfp4_matvec_mlx_scaled_r_2")
residual_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_residual.metal")), "nvfp4_matvec_mlx_scaled_residual")
gu_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_gu.metal")), "nvfp4_matvec_mlx_scaled_gu")

-> tensor_buffer(name)
  d = st.tensor(name)
  v = st.mmap_for(name).view_at(d[:byte_offset], :u8, d[:byte_length])
  metal_buffer_for(device, v)

-> scaled_weight(name)
  [tensor_buffer(name), tensor_buffer(name + ".scale"), tensor_buffer(name + ".global_scale")]

-> abs_value(x)
  if x < ~0.0 then ~0.0 - x else x

-> check_first_eight(label, buf, refs)
  max_diff = ~0.0
  i = 0
  while i < 8
    got = metal_buffer_read_f32(buf, i)
    diff = abs_value(got - refs[i])
    if diff > max_diff then max_diff = diff
    i = i + 1
  << label + ": max_diff=" + max_diff.to_s
  if max_diff >= ~0.005
    raise label + " failed"

x = metal_buffer(device, HIDDEN * 4)
i = 0
while i < HIDDEN
  metal_buffer_write_f32(x, i, Math.sin(i * ~0.013))
  i = i + 1

qkv_name = "model.language_model.layers.0.linear_attn.in_proj_qkv.weight"
qkv = scaled_weight(qkv_name)
qkv_w = qkv[0]
qkv_s = qkv[1]
qkv_g = qkv[2]
qkv_out = metal_buffer(device, QKV_DIM * 4)
qkv_ref = [~-1.259841323, ~-0.569419265, ~0.842016816, ~0.689877212,
           ~0.750479877, ~-0.081818283, ~0.417766452, ~-0.156180814]

metal_batch_begin(queue)
matvec_args = [qkv_w, qkv_s, x, qkv_out, HIDDEN, qkv_g]
metal_dispatch_groups(queue, matvec_pipe, matvec_args, QKV_DIM / 8, 64)
metal_batch_commit(queue)
check_first_eight("scaled matvec", qkv_out, qkv_ref)

metal_batch_begin(queue)
metal_dispatch_groups(queue, r2_pipe, matvec_args, QKV_DIM / 8, 64)
metal_batch_commit(queue)
check_first_eight("scaled r_2 packed-qdot matvec", qkv_out, qkv_ref)

i = 0
while i < QKV_DIM
  metal_buffer_write_f32(qkv_out, i, ~1.0)
  i = i + 1
residual_ref = []
i = 0
while i < 8
  residual_ref.push(qkv_ref[i] + ~1.0)
  i = i + 1
metal_batch_begin(queue)
metal_dispatch_groups(queue, residual_pipe, [qkv_w, qkv_s, x, qkv_out, HIDDEN, qkv_g], QKV_DIM / 8, 64)
metal_batch_commit(queue)
check_first_eight("scaled residual matvec", qkv_out, residual_ref)

gate = scaled_weight("model.language_model.layers.0.mlp.gate_proj.weight")
up = scaled_weight("model.language_model.layers.0.mlp.up_proj.weight")
gate_out = metal_buffer(device, INTERMEDIATE * 4)
up_out = metal_buffer(device, INTERMEDIATE * 4)
gate_ref = [~0.563643575, ~0.501019776, ~-0.381000668, ~0.953298986,
            ~-0.639197946, ~0.060377330, ~-0.278479278, ~0.608838737]
up_ref = [~0.119013213, ~0.591891587, ~0.169220284, ~-0.024570635,
          ~-0.184710920, ~0.127056703, ~-0.385853887, ~-0.053156402]
gate_tgs = INTERMEDIATE / 8
metal_batch_begin(queue)
metal_dispatch_groups(queue, gu_pipe,
  [gate[0], gate[1], up[0], up[1], x, gate_out, up_out, HIDDEN, gate_tgs, gate[2], up[2]],
  gate_tgs * 2, 64)
metal_batch_commit(queue)
check_first_eight("scaled gate projection", gate_out, gate_ref)
check_first_eight("scaled up projection", up_out, up_ref)

st.close
<< "scaled NVFP4 kernels PASS"
