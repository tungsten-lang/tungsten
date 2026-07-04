# Smoke test for the mmap → BigArray → Metal buffer zero-copy path.
# Opens Lightning safetensors, slices out q_proj layer 0, runs nvfp4_matvec,
# compares to the metal_buffer_write_from_mmap result.

use core/metal
use tungsten-llama/safetensors

LIGHTNING_PATH = "/Users/erik/.cache/huggingface/hub/models--bradyclarke--Lightning-1.7B-mlx-nvfp4/snapshots/93b9599f5380f67efa1faa0dc6591251f040882a/model.safetensors"
NVFP4_DIR = "bits/tungsten-llama/lib/kernels/nvfp4/"

K_DIM = 2048
N_ROWS = 2048

device = metal_device()
queue = metal_queue(device)
mv_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec.metal")), "nvfp4_matvec")

st = Safetensors.new(LIGHTNING_PATH)

# OLD path: copy bytes via metal_buffer_write_from_mmap.
w_desc = st.tensor("model.layers.0.self_attn.q_proj.weight")
s_desc = st.tensor("model.layers.0.self_attn.q_proj.scales")
w_buf_old = metal_buffer(device, w_desc[:byte_length])
s_buf_old = metal_buffer(device, s_desc[:byte_length])
st.upload_bytes("model.layers.0.self_attn.q_proj.weight", w_buf_old)
st.upload_bytes("model.layers.0.self_attn.q_proj.scales", s_buf_old)

# NEW path: view the mmap region as a BigArray, hand to metal_buffer_for.
all_bytes = st.mmap.as_u8
<< "all_bytes size=" + all_bytes.size.to_s
<< "w_desc byte_offset=" + w_desc[:byte_offset].to_s + " byte_length=" + w_desc[:byte_length].to_s
<< "all_bytes[0]=" + all_bytes[0].to_s + " all_bytes[100]=" + all_bytes[100].to_s
<< "all_bytes[w_off]=" + all_bytes[w_desc[:byte_offset]].to_s
small_view = all_bytes[0..7]
<< "small_view (first 8 bytes) size=" + small_view.size.to_s
w_view = all_bytes[w_desc[:byte_offset]..(w_desc[:byte_offset] + w_desc[:byte_length] - 1)]
s_view = all_bytes[s_desc[:byte_offset]..(s_desc[:byte_offset] + s_desc[:byte_length] - 1)]
<< "w_view size=" + w_view.size.to_s + " (expect " + w_desc[:byte_length].to_s + ")"
w_buf_new = metal_buffer_for(device, w_view)
s_buf_new = metal_buffer_for(device, s_view)
<< "w_buf_new bytes=" + metal_buffer_length(w_buf_new).to_s

# Set up activation + output, run matvec via OLD path.
x_buf = metal_buffer(device, K_DIM * 4)
i = 0
while i < K_DIM
  metal_buffer_write_f32(x_buf, i, ~0.0001 * ((i * 137) % 5000 - 2500))
  i = i + 1
y_old = metal_buffer(device, N_ROWS * 4)
y_new = metal_buffer(device, N_ROWS * 4)
kdim_buf = metal_buffer(device, 4) ; metal_buffer_write_i32(kdim_buf, 0, K_DIM)

metal_batch_begin(queue)
metal_dispatch_groups(queue, mv_pipe, [w_buf_old, s_buf_old, x_buf, y_old, kdim_buf], N_ROWS, 32)
metal_batch_commit(queue)

metal_batch_begin(queue)
metal_dispatch_groups(queue, mv_pipe, [w_buf_new, s_buf_new, x_buf, y_new, kdim_buf], N_ROWS, 32)
metal_batch_commit(queue)

# Compare every output element.
max_diff = ~0.0
i = 0
while i < N_ROWS
  d = metal_buffer_read_f32(y_old, i) - metal_buffer_read_f32(y_new, i)
  if d < ~0.0
    d = ~0.0 - d
  if d > max_diff
    max_diff = d
  i = i + 1

<< ""
<< "max diff (mmap-view vs copy): " + max_diff.to_s
if max_diff == ~0.0
  << "OK: bit-exact"
else
  << "DIFFERS — mmap view path produces different output"

st.close
