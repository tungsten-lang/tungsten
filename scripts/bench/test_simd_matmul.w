# Validate nvfp4_matmul_simd_fc against nvfp4_matvec on a single Lightning q_proj.
# Replicate one activation × N times, run the simd matmul, compare every
# row against the reference single-token matvec.

use core/metal
use tungsten-llama/safetensors

LIGHTNING_PATH = "/Users/erik/.cache/huggingface/hub/models--bradyclarke--Lightning-1.7B-mlx-nvfp4/snapshots/93b9599f5380f67efa1faa0dc6591251f040882a/model.safetensors"
NVFP4_DIR  = "bits/tungsten-llama/lib/kernels/nvfp4/"

K_DIM = 2048
N_ROWS = 2048
BATCH = 32

device = metal_device()
queue = metal_queue(device)

st = Safetensors.new(LIGHTNING_PATH)

# Reference: single-token matvec
mv_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec.metal")), "nvfp4_matvec")
# Test: simd batched matmul
simd_lib  = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matmul_simd_fc.metal"))
simd_pipe = metal_pipeline_with_int_constants(simd_lib, "nvfp4_matmul_simd_fc", [K_DIM, N_ROWS, BATCH])
# f32→f16 converter
f32f16_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "f32_to_f16.metal")), "f32_to_f16")

w_desc = st.tensor("model.layers.0.self_attn.q_proj.weight")
s_desc = st.tensor("model.layers.0.self_attn.q_proj.scales")
w_buf = metal_buffer(device, w_desc[:byte_length])
s_buf = metal_buffer(device, s_desc[:byte_length])
st.upload_bytes("model.layers.0.self_attn.q_proj.weight", w_buf)
st.upload_bytes("model.layers.0.self_attn.q_proj.scales", s_buf)

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

x_batch_h = metal_buffer(device, BATCH * K_DIM * 2)
n_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(n_buf, 0, BATCH * K_DIM)
metal_batch_begin(queue)
metal_dispatch_n(queue, f32f16_pipe, [x_batch, x_batch_h, n_buf], BATCH * K_DIM)
metal_batch_commit(queue)

y_single = metal_buffer(device, N_ROWS * 4)
y_batch  = metal_buffer(device, BATCH * N_ROWS * 4)
kdim_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_buf, 0, K_DIM)

# Run reference single-token matvec
metal_batch_begin(queue)
metal_dispatch_groups(queue, mv_pipe, [w_buf, s_buf, x_single, y_single, kdim_buf], N_ROWS, 32)
metal_batch_commit(queue)

# Run simd batched matmul
n_m_tiles = BATCH / 8
n_n_tiles = N_ROWS / 8
n_tiles = n_m_tiles * n_n_tiles
metal_batch_begin(queue)
metal_set_threadgroup_memory(queue, 8 * 16 * 2, 0)  # tg_w: 128 half = 256 bytes
metal_set_threadgroup_memory(queue, 8 * 8 * 2, 1)   # tg_c: 64 half = 128 bytes
metal_dispatch_groups(queue, simd_pipe, [w_buf, s_buf, x_batch_h, y_batch], n_tiles, 32)
metal_batch_commit(queue)

# Compare. Allow some half-precision tolerance.
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

<< "max diff (simd matmul vs ref): " + max_diff.to_s
if max_diff > ~0.1
  << "FAIL: simd matmul drifted too far"
else
  << "OK: simd matmul matches ref within tolerance"

<< "ref y[0..4]:    " + [
  metal_buffer_read_f32(y_single, 0), metal_buffer_read_f32(y_single, 1),
  metal_buffer_read_f32(y_single, 2), metal_buffer_read_f32(y_single, 3),
  metal_buffer_read_f32(y_single, 4)
].to_s
<< "simd[0] y[0..4]: " + [
  metal_buffer_read_f32(y_batch, 0), metal_buffer_read_f32(y_batch, 1),
  metal_buffer_read_f32(y_batch, 2), metal_buffer_read_f32(y_batch, 3),
  metal_buffer_read_f32(y_batch, 4)
].to_s
<< "simd[7] y[0..4]: " + [
  metal_buffer_read_f32(y_batch, 7 * N_ROWS + 0), metal_buffer_read_f32(y_batch, 7 * N_ROWS + 1),
  metal_buffer_read_f32(y_batch, 7 * N_ROWS + 2), metal_buffer_read_f32(y_batch, 7 * N_ROWS + 3),
  metal_buffer_read_f32(y_batch, 7 * N_ROWS + 4)
].to_s

st.close
