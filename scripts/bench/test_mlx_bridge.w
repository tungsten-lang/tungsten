# Smoke test for the mlx-c bridge: load Lightning safetensors via MLX,
# call mlx_quantized_matmul on q_proj layer 0, print first few outputs.

LIGHTNING_PATH = "/Users/erik/.cache/huggingface/hub/models--bradyclarke--Lightning-1.7B-mlx-nvfp4/snapshots/93b9599f5380f67efa1faa0dc6591251f040882a/model.safetensors"

K_DIM = 2048
N_ROWS = 2048
BATCH = 1

<< "calling load..."
ok = ccall("w_mlxb_load_safetensors", LIGHTNING_PATH)
<< "load: " + ok.to_s
<< "tensor count: " + ccall("w_mlxb_tensor_count").to_s

<< "allocating x..."
x = f32[K_DIM]
<< "filling x..."
i = 0
while i < K_DIM
  x[i] = ~0.0001 * ((i * 137) % 5000 - 2500)
  i = i + 1

<< "allocating y..."
y = f32[N_ROWS]
<< "calling matmul..."
ok = ccall("w_mlxb_quantized_matmul_nvfp4",
  "model.layers.0.self_attn.q_proj.weight",
  "model.layers.0.self_attn.q_proj.scales",
  x, K_DIM, y, N_ROWS, BATCH)
<< "matmul: " + ok.to_s
<< "y[0] = " + y[0].to_s + " (expect -0.0376)"

# Time N matmul calls.
N_ITERS = 1000
<< ""
<< "timing " + N_ITERS.to_s + " calls..."
t0 = ccall("__w_clock")
i = 0
while i < N_ITERS
  ccall("w_mlxb_quantized_matmul_nvfp4",
    "model.layers.0.self_attn.q_proj.weight",
    "model.layers.0.self_attn.q_proj.scales",
    x, K_DIM, y, N_ROWS, BATCH)
  i = i + 1
t1 = ccall("__w_clock")
elapsed_ms = (t1 - t0) * ~1000.0
us_per_call = (elapsed_ms * ~1000.0) / N_ITERS
<< "MLX nvfp4 matvec: " + us_per_call.to_s + " us/call (" + elapsed_ms.to_s + " ms total)"

# Compare to our Tungsten nvfp4_matvec at the same shape.
use core/metal
use tungsten-llama/safetensors

device = metal_device()
queue = metal_queue(device)
NVFP4_DIR = "bits/tungsten-llama/lib/kernels/nvfp4/"
mv_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec.metal")), "nvfp4_matvec")

st = Safetensors.new(LIGHTNING_PATH)
w_desc = st.tensor("model.layers.0.self_attn.q_proj.weight")
s_desc = st.tensor("model.layers.0.self_attn.q_proj.scales")
w_buf = metal_buffer(device, w_desc[:byte_length])
s_buf = metal_buffer(device, s_desc[:byte_length])
st.upload_bytes("model.layers.0.self_attn.q_proj.weight", w_buf)
st.upload_bytes("model.layers.0.self_attn.q_proj.scales", s_buf)

x_buf = metal_buffer(device, K_DIM * 4)
i = 0
while i < K_DIM
  metal_buffer_write_f32(x_buf, i, ~0.0001 * ((i * 137) % 5000 - 2500))
  i = i + 1
y_buf = metal_buffer(device, N_ROWS * 4)
kdim_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_buf, 0, K_DIM)

# Warm up
metal_batch_begin(queue)
metal_dispatch_groups(queue, mv_pipe, [w_buf, s_buf, x_buf, y_buf, kdim_buf], N_ROWS, 32)
metal_batch_commit(queue)

<< ""
<< "timing " + N_ITERS.to_s + " calls of Tungsten nvfp4_matvec..."
t0 = ccall("__w_clock")
i = 0
while i < N_ITERS
  metal_batch_begin(queue)
  metal_dispatch_groups(queue, mv_pipe, [w_buf, s_buf, x_buf, y_buf, kdim_buf], N_ROWS, 32)
  metal_batch_commit(queue)
  i = i + 1
t1 = ccall("__w_clock")
tg_ms = (t1 - t0) * ~1000.0
tg_us = (tg_ms * ~1000.0) / N_ITERS
<< "Tungsten nvfp4 matvec: " + tg_us.to_s + " us/call (" + tg_ms.to_s + " ms total)"
<< ""
<< "MLX y[0] = -0.0376321"
<< "Tungsten y_buf[0] = " + metal_buffer_read_f32(y_buf, 0).to_s

st.close
