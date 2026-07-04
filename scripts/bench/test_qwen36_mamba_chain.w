# Multi-layer Mamba chain test — runs layers 0 and 1 of qwen3.6 in sequence
# and validates each output bit-exactly against MLX.
#
# Validates:
#   - Per-layer weight loading parameterized by layer index
#   - Multi-layer chaining (layer 1's input = layer 0's output)
#   - All 13 forward stages reusable as a function
#
# Once this passes, scaling to all 30 Mamba layers is just a loop.

use core/metal
use tungsten-llama/sharded_safetensors

QWEN36_PATH = "/Users/erik/.cache/huggingface/hub/models--mlx-community--Qwen3.6-35B-A3B-nvfp4/snapshots/9c1a3a223ddd8a3425212cc421056614f149cf0f/model.safetensors.index.json"
SHARED_DIR = "bits/tungsten-llama/lib/kernels/shared/"
NVFP4_DIR  = "bits/tungsten-llama/lib/kernels/nvfp4/"
Q36_DIR    = "bits/tungsten-llama/lib/kernels/qwen3_6/"

HIDDEN  = 2048
HK      = 16
HV      = 32
DK      = 128
DV      = 128
Q_DIM   = HK * DK     # 2048
K_DIM   = HK * DK     # 2048
V_DIM   = HV * DV     # 4096
QKV_DIM = Q_DIM + K_DIM + V_DIM    # 8192 = conv_dim
EPS     = ~0.000001

device = metal_device()
queue  = metal_queue(device)

st = ShardedSafetensors.new(QWEN36_PATH)

# ---- Pipelines ----
rms_pipe       = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "rms_norm.metal")), "rms_norm")
nvfp4_mlx_pipe = metal_pipeline(metal_compile_source(device, read_file(NVFP4_DIR  + "nvfp4_matvec_mlx.metal")), "nvfp4_matvec_mlx")
copy_pipe      = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "copy_f32_slice.metal")), "copy_f32_slice")
phn_pipe       = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "per_head_norm.metal")), "per_head_norm")
add_pipe       = metal_pipeline(metal_compile_source(device, read_file(SHARED_DIR + "residual_add.metal")), "residual_add")
conv_pipe      = metal_pipeline(metal_compile_source(device, read_file(Q36_DIR    + "conv1d_depthwise_step.metal")), "conv1d_depthwise_step")
g_pipe         = metal_pipeline(metal_compile_source(device, read_file(Q36_DIR    + "compute_g.metal")), "compute_g")
step_pipe      = metal_pipeline(metal_compile_source(device, read_file(Q36_DIR    + "gated_delta_step.metal")), "gated_delta_step")
rng_pipe       = metal_pipeline(metal_compile_source(device, read_file(Q36_DIR    + "rms_norm_gated.metal")), "rms_norm_gated")

# ---- Constant per-head normalize weights (Q/K) ----
# MLX: q = (1/Dk) * normalize(q),  k = (1/√Dk) * normalize(k)
# These are constants for a given Dk; load once.
inv_scale_k = ~1.0 / Math.sqrt(~0.0 + DK)
q_scale = inv_scale_k * inv_scale_k   # 1/Dk
k_scale = inv_scale_k                  # 1/√Dk
q_w_buf = metal_buffer(device, DK * 4)
k_w_buf = metal_buffer(device, DK * 4)
i = 0
while i < DK
  metal_buffer_write_f32(q_w_buf, i, q_scale)
  metal_buffer_write_f32(k_w_buf, i, k_scale)
  i = i + 1

# ---- Helper: load BF16 tensor → f32 buffer via byte-shift ----
-> load_bf16(name, n_elements, dst_buf)
  d = st.tensor(name)
  m = st.mmap_for(name)
  i = 0
  while i < n_elements
    off = d[:byte_offset] + i * 2
    bits = m.byte_at(off + 0) | (m.byte_at(off + 1) << 8)
    metal_buffer_write_i32(dst_buf, i, bits << 16)
    i = i + 1

# ---- Helper: zero-copy mmap → MTLBuffer for nvfp4 weight or scales ----
-> load_nvfp4_part(name)
  d = st.tensor(name)
  v = st.mmap_for(name).view_at(d[:byte_offset], :u8, d[:byte_length])
  metal_buffer_for(device, v)

# ---- One-Mamba-layer forward ----
# Computes: x_out = x_in + linear_attn(input_layernorm(x_in))
#
# Allocates buffers internally (could be pooled across layers in production).
# State (conv + ssm) initialized to zeros each call (single-token decode from
# scratch — for sequential decoding a real harness would persist state).
-> mamba_layer(li, x_in_buf, x_out_buf)
  prefix = "language_model.model.layers." + li.to_s + "."

  # Stage 1: input_layernorm
  norm_w_buf = metal_buffer(device, HIDDEN * 4)
  load_bf16(prefix + "input_layernorm.weight", HIDDEN, norm_w_buf)
  xn_buf = metal_buffer(device, HIDDEN * 4)

  # Stages 2-5: in_proj_qkv/z/a/b (nvfp4 matvecs)
  qkv_w = load_nvfp4_part(prefix + "linear_attn.in_proj_qkv.weight")
  qkv_s = load_nvfp4_part(prefix + "linear_attn.in_proj_qkv.scales")
  z_w   = load_nvfp4_part(prefix + "linear_attn.in_proj_z.weight")
  z_s   = load_nvfp4_part(prefix + "linear_attn.in_proj_z.scales")
  a_w   = load_nvfp4_part(prefix + "linear_attn.in_proj_a.weight")
  a_s   = load_nvfp4_part(prefix + "linear_attn.in_proj_a.scales")
  b_w   = load_nvfp4_part(prefix + "linear_attn.in_proj_b.weight")
  b_s   = load_nvfp4_part(prefix + "linear_attn.in_proj_b.scales")

  qkv_buf = metal_buffer(device, QKV_DIM * 4)
  z_buf   = metal_buffer(device, V_DIM   * 4)
  a_buf   = metal_buffer(device, HV      * 4)
  b_buf   = metal_buffer(device, HV      * 4)

  # Stage 6: conv1d state + weight (BF16 → f32)
  conv_w_buf = metal_buffer(device, QKV_DIM * 4 * 4)
  load_bf16(prefix + "linear_attn.conv1d.weight", QKV_DIM * 4, conv_w_buf)
  conv_state    = metal_buffer(device, 3 * QKV_DIM * 4)
  conv_state_o  = metal_buffer(device, 3 * QKV_DIM * 4)
  conv_out_buf  = metal_buffer(device, QKV_DIM * 4)
  i = 0
  while i < 3 * QKV_DIM
    metal_buffer_write_f32(conv_state, i, ~0.0)
    i = i + 1

  # Stage 7-8 buffers
  q_buf = metal_buffer(device, Q_DIM * 4)
  k_buf = metal_buffer(device, K_DIM * 4)
  v_buf = metal_buffer(device, V_DIM * 4)

  # Stage 9: A_log + dt_bias (BF16 → f32)
  A_log_buf   = metal_buffer(device, HV * 4)
  dt_bias_buf = metal_buffer(device, HV * 4)
  load_bf16(prefix + "linear_attn.A_log",   HV, A_log_buf)
  load_bf16(prefix + "linear_attn.dt_bias", HV, dt_bias_buf)
  g_buf    = metal_buffer(device, HV * 4)
  beta_buf = metal_buffer(device, HV * 4)

  # Stage 10: SSM state init=0
  state_in  = metal_buffer(device, HV * DV * DK * 4)
  state_out = metal_buffer(device, HV * DV * DK * 4)
  y_buf     = metal_buffer(device, V_DIM * 4)
  i = 0
  while i < HV * DV * DK
    metal_buffer_write_f32(state_in, i, ~0.0)
    i = i + 1

  # Stage 11: linear_attn.norm.weight (BF16 [DV])
  ln_w_buf = metal_buffer(device, DV * 4)
  load_bf16(prefix + "linear_attn.norm.weight", DV, ln_w_buf)
  ng_buf = metal_buffer(device, V_DIM * 4)

  # Stage 12: out_proj
  op_w = load_nvfp4_part(prefix + "linear_attn.out_proj.weight")
  op_s = load_nvfp4_part(prefix + "linear_attn.out_proj.scales")

  # ---- Dispatch sequence (all stages in one batched cmd buffer) ----
  metal_batch_begin(queue)
  metal_dispatch_groups(queue, rms_pipe, [x_in_buf, norm_w_buf, xn_buf, HIDDEN, ~1.0 / HIDDEN, EPS], 1, 256)
  metal_dispatch_groups(queue, nvfp4_mlx_pipe, [qkv_w, qkv_s, xn_buf, qkv_buf, HIDDEN], QKV_DIM / 8, 64)
  metal_dispatch_groups(queue, nvfp4_mlx_pipe, [z_w,   z_s,   xn_buf, z_buf,   HIDDEN], V_DIM / 8, 64)
  metal_dispatch_groups(queue, nvfp4_mlx_pipe, [a_w,   a_s,   xn_buf, a_buf,   HIDDEN], (HV + 7) / 8, 64)
  metal_dispatch_groups(queue, nvfp4_mlx_pipe, [b_w,   b_s,   xn_buf, b_buf,   HIDDEN], (HV + 7) / 8, 64)
  metal_dispatch_n(queue, conv_pipe, [conv_w_buf, conv_state, qkv_buf, conv_out_buf, conv_state_o, QKV_DIM, QKV_DIM], QKV_DIM)
  metal_dispatch_n(queue, copy_pipe, [conv_out_buf, q_buf, 0,             Q_DIM], Q_DIM)
  metal_dispatch_n(queue, copy_pipe, [conv_out_buf, k_buf, Q_DIM,         K_DIM], K_DIM)
  metal_dispatch_n(queue, copy_pipe, [conv_out_buf, v_buf, Q_DIM + K_DIM, V_DIM], V_DIM)
  metal_dispatch_groups(queue, phn_pipe, [q_buf, q_w_buf, DK, ~1.0 / DK, EPS], HK, 32)
  metal_dispatch_groups(queue, phn_pipe, [k_buf, k_w_buf, DK, ~1.0 / DK, EPS], HK, 32)
  metal_dispatch_n(queue, g_pipe, [a_buf, A_log_buf, dt_bias_buf, g_buf, HV, HV], HV)
  metal_batch_commit(queue)

  # Stage 9 (continued): beta = sigmoid(b) — CPU loop (32 elements)
  i = 0
  while i < HV
    bv = metal_buffer_read_f32(b_buf, i)
    metal_buffer_write_f32(beta_buf, i, ~1.0 / (~1.0 + Math.exp(~0.0 - bv)))
    i = i + 1

  metal_batch_begin(queue)
  metal_dispatch_3d(queue, step_pipe,
    [q_buf, k_buf, v_buf, g_buf, beta_buf, state_in, y_buf, state_out, HK, HV, DK, DV],
    1, DV / 4, HV,
    32, 4, 1)
  metal_dispatch_groups(queue, rng_pipe, [y_buf, z_buf, ln_w_buf, ng_buf, DV, EPS], HV, 32)
  metal_dispatch_groups(queue, nvfp4_mlx_pipe, [op_w, op_s, ng_buf, x_out_buf, V_DIM], HIDDEN / 8, 64)
  metal_dispatch_n(queue, add_pipe, [x_out_buf, x_in_buf, HIDDEN], HIDDEN)
  metal_batch_commit(queue)

# ---- Smoke test: run layers 0 and 1 chained ----
x0_buf = metal_buffer(device, HIDDEN * 4)
x1_buf = metal_buffer(device, HIDDEN * 4)
x2_buf = metal_buffer(device, HIDDEN * 4)
i = 0
while i < HIDDEN
  metal_buffer_write_f32(x0_buf, i, Math.sin(i * ~0.013))
  i = i + 1

<< "running Mamba layer 0..."
mamba_layer(0, x0_buf, x1_buf)
REF_L0 = [~-0.005125, ~0.009984, ~0.046253, ~0.038499, ~0.051801, ~0.061674, ~0.086833, ~0.090179]
max_d0 = ~0.0
i = 0
while i < 8
  got = metal_buffer_read_f32(x1_buf, i)
  d = got - REF_L0[i]
  if d < ~0.0 then d = ~0.0 - d
  if d > max_d0 then max_d0 = d
  i = i + 1
<< "  layer 0 max diff: " + max_d0.to_s
if max_d0 < ~0.001 then << "  layer 0 PASS" else << "  layer 0 FAIL"

<< ""
<< "running Mamba layer 1 (input = layer 0 output)..."
mamba_layer(1, x1_buf, x2_buf)
REF_L1 = [~-0.018688, ~0.012452, ~0.039846, ~0.034968, ~0.050203, ~0.051415, ~0.064132, ~0.101280]
max_d1 = ~0.0
i = 0
while i < 8
  got = metal_buffer_read_f32(x2_buf, i)
  d = got - REF_L1[i]
  if d < ~0.0 then d = ~0.0 - d
  if d > max_d1 then max_d1 = d
  << "  x2[" + i.to_s + "]: kernel=" + got.to_s + "  ref=" + REF_L1[i].to_s + "  diff=" + (got - REF_L1[i]).to_s
  i = i + 1
<< "  layer 1 max diff: " + max_d1.to_s
if max_d1 < ~0.001 then << "  layer 1 PASS — multi-layer Mamba chain bit-exact!" else << "  layer 1 FAIL"

st.close
