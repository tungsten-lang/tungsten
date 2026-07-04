# Smoke test for int8_affine_matvec.metal against real qwen3.6 router weights.
#
# Loads layer 3's mlp.gate (router) — N=256 experts × K=2048 hidden,
# 8-bit unsigned affine quant with group_size=64 — runs the kernel
# on a deterministic activation (sin(k*0.01)), and compares against
# the MLX reference written to /tmp/qwen36_router_ref.f32 by
# the Python pre-step:
#
#   python3 -c "..." > /tmp/qwen36_router_ref.f32
#
# (See git log of this file for the Python script that produces it.)
#
# Pass criterion: max |y - y_ref| < 5e-3 (the kernel runs in f32 internally
# but reads bf16 scales+biases — bf16 rounding alone can be ~1e-3 per element).

use core/metal
use tungsten-llama/sharded_safetensors

QWEN36_PATH = "/Users/erik/.cache/huggingface/hub/models--mlx-community--Qwen3.6-35B-A3B-nvfp4/snapshots/9c1a3a223ddd8a3425212cc421056614f149cf0f/model.safetensors.index.json"
KERNEL_PATH = "bits/tungsten-llama/lib/kernels/int8_affine/int8_affine_matvec.metal"
REF_PATH    = "/tmp/qwen36_router_ref.f32"

N_ROWS = 256       # num_experts
K_DIM  = 2048      # hidden_size
TG_SIZE = 64       # 2 simdgroups × 32 lanes (8 rows per TG)

device = metal_device()
queue  = metal_queue(device)

<< "loading qwen3.6 sharded safetensors..."
st = ShardedSafetensors.new(QWEN36_PATH)

w_desc = st.tensor("language_model.model.layers.3.mlp.gate.weight")
s_desc = st.tensor("language_model.model.layers.3.mlp.gate.scales")
b_desc = st.tensor("language_model.model.layers.3.mlp.gate.biases")
<< "  weight: " + w_desc[:byte_length].to_s + " bytes (expected 524288 = 256×512×4)"
<< "  scales: " + s_desc[:byte_length].to_s + " bytes (expected 16384  = 256×32×2)"
<< "  biases: " + b_desc[:byte_length].to_s + " bytes (expected 16384  = 256×32×2)"

<< "uploading weight + scales + biases (zero-copy mmap → MTLBuffer)..."
w_view = st.mmap_for("language_model.model.layers.3.mlp.gate.weight").view_at(w_desc[:byte_offset], :u8, w_desc[:byte_length])
s_view = st.mmap_for("language_model.model.layers.3.mlp.gate.scales").view_at(s_desc[:byte_offset], :u8, s_desc[:byte_length])
b_view = st.mmap_for("language_model.model.layers.3.mlp.gate.biases").view_at(b_desc[:byte_offset], :u8, b_desc[:byte_length])
w_buf = metal_buffer_for(device, w_view)
s_buf = metal_buffer_for(device, s_view)
b_buf = metal_buffer_for(device, b_view)

# Deterministic activation: x[k] = sin(k * 0.01)
x_buf = metal_buffer(device, K_DIM * 4)
i = 0
while i < K_DIM
  metal_buffer_write_f32(x_buf, i, Math.sin(i * ~0.01))
  i = i + 1

# Output buffer
y_buf = metal_buffer(device, N_ROWS * 4)

# Compile + dispatch
matvec_pipe = metal_pipeline(metal_compile_source(device, read_file(KERNEL_PATH)), "int8_affine_matvec")
n_tgs = (N_ROWS + 7) / 8

<< "running int8_affine_matvec (N=" + N_ROWS.to_s + ", K=" + K_DIM.to_s + ", " + n_tgs.to_s + " TGs × " + TG_SIZE.to_s + " threads)..."
metal_batch_begin(queue)
metal_dispatch_groups(queue, matvec_pipe, [w_buf, s_buf, b_buf, x_buf, y_buf, K_DIM, N_ROWS], n_tgs, TG_SIZE)
ms = metal_batch_commit_ms(queue, 0)
<< "  GPU time: " + (ms * ~1000.0).to_s + " µs"

# MLX-computed reference for the first 8 outputs (Python pre-step:
# x[k]=sin(k*0.01), MLX dequantize affine + matmul, see git log).
REF = [
  ~-0.773979,
  ~-0.058976,
  ~-1.239301,
  ~-1.095240,
  ~+0.010491,
  ~+0.772490,
  ~-0.678091,
  ~-1.305231
]

<< ""
<< "first 8 outputs (kernel vs MLX reference):"
max_abs_diff = ~0.0
worst_idx = -1
i = 0
while i < 8
  got = metal_buffer_read_f32(y_buf, i)
  ref = REF[i]
  d = got - ref
  if d < ~0.0
    d = ~0.0 - d
  if d > max_abs_diff
    max_abs_diff = d
    worst_idx = i
  << "  y[" + i.to_s + "]: kernel=" + got.to_s + "  ref=" + ref.to_s + "  diff=" + (got - ref).to_s
  i = i + 1

<< ""
<< "max |y - y_ref| over first 8 rows: " + max_abs_diff.to_s + " (worst at row " + worst_idx.to_s + ")"
if max_abs_diff < ~0.005
  << "PASS — within 5e-3 tolerance (bf16 scale/bias rounding accounts for ~1e-3)"
else
  << "FAIL — max diff exceeds 5e-3 tolerance"

st.close
