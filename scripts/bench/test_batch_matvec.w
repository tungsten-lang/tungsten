# Validate nvfp4_matvec_batch_fc against nvfp4_matvec by running both
# on the same q_proj weights with N_BATCH copies of an activation, and
# checking they produce identical outputs.

use core/metal
use tungsten-llama/safetensors

LIGHTNING_PATH = "/Users/erik/.cache/huggingface/hub/models--bradyclarke--Lightning-1.7B-mlx-nvfp4/snapshots/93b9599f5380f67efa1faa0dc6591251f040882a/model.safetensors"
NVFP4_DIR  = "bits/tungsten-llama/lib/kernels/nvfp4/"

K_DIM = 2048
N_ROWS = 2048
BATCH = 5

device = metal_device()
queue = metal_queue(device)

st = Safetensors.new(LIGHTNING_PATH)

# Decode kernel (single-token)
mv_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec.metal")), "nvfp4_matvec")
# Batched kernel
mv_batch_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_batch_fc.metal"))
mv_batch_pipe = metal_pipeline_with_int_constants(mv_batch_lib, "nvfp4_matvec_batch_fc", [K_DIM, N_ROWS, BATCH])

# Load q_proj layer 0 weights
w_desc = st.tensor("model.layers.0.self_attn.q_proj.weight")
s_desc = st.tensor("model.layers.0.self_attn.q_proj.scales")
w_buf = metal_buffer(device, w_desc[:byte_length])
s_buf = metal_buffer(device, s_desc[:byte_length])
st.upload_bytes("model.layers.0.self_attn.q_proj.weight", w_buf)
st.upload_bytes("model.layers.0.self_attn.q_proj.scales", s_buf)

# Activation: a fixed pseudo-random vector replicated BATCH times
x_single = metal_buffer(device, K_DIM * 4)
x_batch  = metal_buffer(device, BATCH * K_DIM * 4)
i = 0
while i < K_DIM
  v = ~0.0001 * ((i * 137) % 5000 - 2500)
  metal_buffer_write_f32(x_single, i, v)
  bi = 0
  while bi < BATCH
    metal_buffer_write_f32(x_batch, bi * K_DIM + i, v)
    bi = bi + 1
  i = i + 1

y_single = metal_buffer(device, N_ROWS * 4)
y_batch  = metal_buffer(device, BATCH * N_ROWS * 4)
kdim_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_buf, 0, K_DIM)

# Run single-token matvec
metal_batch_begin(queue)
metal_dispatch_groups(queue, mv_pipe, [w_buf, s_buf, x_single, y_single, kdim_buf], N_ROWS, 32)
metal_batch_commit(queue)

# Run batched matvec
metal_batch_begin(queue)
metal_dispatch_groups(queue, mv_batch_pipe, [w_buf, s_buf, x_batch, y_batch], BATCH * N_ROWS, 32)
metal_batch_commit(queue)

# Compare each batch row to single-token output
max_diff = ~0.0
i = 0
while i < N_ROWS
  ref = metal_buffer_read_f32(y_single, i)
  bi = 0
  while bi < BATCH
    got = metal_buffer_read_f32(y_batch, bi * N_ROWS + i)
    d = ref - got
    if d < ~0.0
      d = ~0.0 - d
    if d > max_diff
      max_diff = d
    bi = bi + 1
  i = i + 1

<< "max diff between single-token and batched matvec: " + max_diff.to_s
if max_diff > ~0.001
  << "FAIL: batched matvec diverges from single-token"
else
  << "OK: batched matvec matches single-token"

# Show first 5 outputs of each
<< "single y[0..4]: " + [
  metal_buffer_read_f32(y_single, 0),
  metal_buffer_read_f32(y_single, 1),
  metal_buffer_read_f32(y_single, 2),
  metal_buffer_read_f32(y_single, 3),
  metal_buffer_read_f32(y_single, 4)
].to_s
<< "batch[0] y[0..4]: " + [
  metal_buffer_read_f32(y_batch, 0),
  metal_buffer_read_f32(y_batch, 1),
  metal_buffer_read_f32(y_batch, 2),
  metal_buffer_read_f32(y_batch, 3),
  metal_buffer_read_f32(y_batch, 4)
].to_s
<< "batch[2] y[0..4]: " + [
  metal_buffer_read_f32(y_batch, 2 * N_ROWS + 0),
  metal_buffer_read_f32(y_batch, 2 * N_ROWS + 1),
  metal_buffer_read_f32(y_batch, 2 * N_ROWS + 2),
  metal_buffer_read_f32(y_batch, 2 * N_ROWS + 3),
  metal_buffer_read_f32(y_batch, 2 * N_ROWS + 4)
].to_s

st.close
