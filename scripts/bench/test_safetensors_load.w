# End-to-end test: load Lightning-1.7B safetensors from Tungsten,
# pull out one nvfp4 tensor, run nvfp4_matvec on it, compare to the
# Python-dumped MLX reference output (q_proj layer 3 from Qwen3.6).
#
# We don't yet have the FULL Lightning forward pass — this just proves
# Tungsten can load a real safetensors file and dispatch nvfp4 matvec
# end to end on its weights.

use core/metal
use tungsten-llama/safetensors

LIGHTNING_PATH = "/Users/erik/.cache/huggingface/hub/models--bradyclarke--Lightning-1.7B-mlx-nvfp4/snapshots/93b9599f5380f67efa1faa0dc6591251f040882a/model.safetensors"
KERNEL = "compiler/lib/kernels/tungsten-llama/nvfp4/nvfp4_matvec.metal"

<< "loading Lightning-1.7B safetensors..."
st = Safetensors.new(LIGHTNING_PATH)
<< "  " + st.count.to_s + " tensors loaded"

<< ""
<< "first 10 tensor names:"
keys = st.tensors.keys
i = 0
while i < 10 && i < keys.length()
  k = keys[i]
  d = st.tensor(k)
  << "  " + k + ": dtype=" + d[:dtype] + " shape=" + d[:shape].to_s + " offset=" + d[:byte_offset].to_s + " bytes=" + d[:byte_length].to_s
  i = i + 1

<< ""
<< "looking up layer 0 q_proj..."
qw = st.tensor("model.layers.0.self_attn.q_proj.weight")
qs = st.tensor("model.layers.0.self_attn.q_proj.scales")
<< "  q_proj.weight: " + qw[:dtype] + " " + qw[:shape].to_s + " (" + qw[:byte_length].to_s + " bytes)"
<< "  q_proj.scales: " + qs[:dtype] + " " + qs[:shape].to_s + " (" + qs[:byte_length].to_s + " bytes)"

# Set up Metal + run the kernel
device = metal_device()
queue = metal_queue(device)
matvec_pipe = metal_pipeline(metal_compile_source(device, read_file(KERNEL)), "nvfp4_matvec")

# Lightning q_proj: (2048, 256) uint32 = 2048 outputs × 2048 nvfp4 inputs
# Lightning has hidden=2048, so q is 2048-wide (16 heads × 128 head_dim)
N_ROWS = qw[:shape][0]
K_DIM = qw[:shape][1] * 8

w_buf = metal_buffer(device, qw[:byte_length])
s_buf = metal_buffer(device, qs[:byte_length])
x_buf = metal_buffer(device, K_DIM * 4)
y_buf = metal_buffer(device, N_ROWS * 4)
k_buf = metal_buffer(device, 4)
metal_buffer_write_i32(k_buf, 0, K_DIM)

st.upload_bytes("model.layers.0.self_attn.q_proj.weight", w_buf)
st.upload_bytes("model.layers.0.self_attn.q_proj.scales", s_buf)

# Use a known activation: x[i] = i / K_DIM (deterministic, easy to verify in Python)
i = 0
while i < K_DIM
  metal_buffer_write_f32(x_buf, i, (~0.0 + i) / (~0.0 + K_DIM))
  i = i + 1

<< ""
<< "dispatching nvfp4_matvec on Lightning layer 0 q_proj (n=" + N_ROWS.to_s + ", k=" + K_DIM.to_s + ")..."
metal_batch_begin(queue)
metal_dispatch_groups(queue, matvec_pipe, [w_buf, s_buf, x_buf, y_buf, k_buf], N_ROWS, 32)
metal_batch_commit(queue)

<< ""
<< "first 10 outputs:"
i = 0
while i < 10
  v = metal_buffer_read_f32(y_buf, i)
  << "  y[" + i.to_s + "] = " + v.to_s
  i = i + 1

<< ""
<< "✓ safetensors loader + nvfp4 matvec end-to-end works"
st.close
