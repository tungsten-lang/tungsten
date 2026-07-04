# Smoke test for the 4 qwen3.6 Mamba/SSM helper kernels:
#   - compute_g
#   - attn_output_gate
#   - rms_norm_gated
#   - conv1d_depthwise_step
#
# Each tested with deterministic synthetic inputs; first 8 outputs compared
# against MLX-computed references.

use core/metal

K_DIR = "bits/tungsten-llama/lib/kernels/qwen3_6/"

device = metal_device()
queue  = metal_queue(device)

# ===========================================================
# 1. compute_g
# ===========================================================
<< "=== compute_g ==="
HV = 32
a_buf       = metal_buffer(device, HV * 4)
A_log_buf   = metal_buffer(device, HV * 4)
dt_bias_buf = metal_buffer(device, HV * 4)
g_buf       = metal_buffer(device, HV * 4)
i = 0
while i < HV
  metal_buffer_write_f32(A_log_buf,   i, Math.log(~0.5 + ~0.1 * i))
  metal_buffer_write_f32(dt_bias_buf, i, ~0.1 * (i % 5))
  metal_buffer_write_f32(a_buf,       i, Math.sin(i * ~0.05))
  i = i + 1

g_pipe = metal_pipeline(metal_compile_source(device, read_file(K_DIR + "compute_g.metal")), "compute_g")
metal_batch_begin(queue)
metal_dispatch_n(queue, g_pipe, [a_buf, A_log_buf, dt_bias_buf, g_buf, HV, HV], HV)
ms = metal_batch_commit_ms(queue, 0)
<< "  GPU time: " + (ms * ~1000.0).to_s + " µs"

REF_G = [~0.707107, ~0.629665, ~0.549920, ~0.470328, ~0.393385, ~0.438463, ~0.367376, ~0.300835]
max_d = ~0.0
i = 0
while i < 8
  got = metal_buffer_read_f32(g_buf, i)
  d = got - REF_G[i]
  if d < ~0.0
    d = ~0.0 - d
  if d > max_d
    max_d = d
  i = i + 1
<< "  max diff (first 8): " + max_d.to_s
if max_d < ~0.001
  << "  PASS"
else
  << "  FAIL"

# ===========================================================
# 2. attn_output_gate
# ===========================================================
<< ""
<< "=== attn_output_gate ==="
N_ATTN = 4096
ao_buf  = metal_buffer(device, N_ATTN * 4)
gt_buf  = metal_buffer(device, N_ATTN * 4)
i = 0
while i < N_ATTN
  metal_buffer_write_f32(ao_buf, i, Math.sin(i * ~0.013))
  metal_buffer_write_f32(gt_buf, i, Math.cos(i * ~0.011))
  i = i + 1

aog_pipe = metal_pipeline(metal_compile_source(device, read_file(K_DIR + "attn_output_gate.metal")), "attn_output_gate")
metal_batch_begin(queue)
metal_dispatch_n(queue, aog_pipe, [ao_buf, gt_buf, N_ATTN], N_ATTN)
ms = metal_batch_commit_ms(queue, 0)
<< "  GPU time: " + (ms * ~1000.0).to_s + " µs"

REF_AOG = [~0.0, ~0.009503, ~0.019004, ~0.028500, ~0.037988, ~0.047466, ~0.056931, ~0.066382]
max_d = ~0.0
i = 0
while i < 8
  got = metal_buffer_read_f32(ao_buf, i)
  d = got - REF_AOG[i]
  if d < ~0.0
    d = ~0.0 - d
  if d > max_d
    max_d = d
  i = i + 1
<< "  max diff (first 8): " + max_d.to_s
if max_d < ~0.001
  << "  PASS"
else
  << "  FAIL"

# ===========================================================
# 3. rms_norm_gated  (single cell, Dv=128)
# ===========================================================
<< ""
<< "=== rms_norm_gated ==="
DV = 128
h_buf    = metal_buffer(device, DV * 4)
gate_buf = metal_buffer(device, DV * 4)
w_buf    = metal_buffer(device, DV * 4)
out_buf  = metal_buffer(device, DV * 4)
i = 0
while i < DV
  metal_buffer_write_f32(h_buf,    i, Math.sin(i * ~0.07))
  metal_buffer_write_f32(gate_buf, i, Math.cos(i * ~0.09))
  metal_buffer_write_f32(w_buf,    i, ~1.0 + ~0.01 * i)
  i = i + 1

rng_pipe = metal_pipeline(metal_compile_source(device, read_file(K_DIR + "rms_norm_gated.metal")), "rms_norm_gated")
metal_batch_begin(queue)
metal_dispatch_groups(queue, rng_pipe, [h_buf, gate_buf, w_buf, out_buf, DV, ~0.000001], 1, 32)
ms = metal_batch_commit_ms(queue, 0)
<< "  GPU time: " + (ms * ~1000.0).to_s + " µs"

REF_RNG = [~0.0, ~0.071144, ~0.141138, ~0.207422, ~0.267531, ~0.319201, ~0.360460, ~0.389720]
max_d = ~0.0
i = 0
while i < 8
  got = metal_buffer_read_f32(out_buf, i)
  d = got - REF_RNG[i]
  if d < ~0.0
    d = ~0.0 - d
  if d > max_d
    max_d = d
  i = i + 1
<< "  max diff (first 8): " + max_d.to_s
if max_d < ~0.001
  << "  PASS"
else
  << "  FAIL"

# ===========================================================
# 4. conv1d_depthwise_step  (B=1, T=1, C=8192, kernel=4)
# ===========================================================
<< ""
<< "=== conv1d_depthwise_step ==="
C_CONV = 8192
w_conv_buf  = metal_buffer(device, C_CONV * 4 * 4)
state_buf   = metal_buffer(device, 3 * C_CONV * 4)
x_conv_buf  = metal_buffer(device, C_CONV * 4)
out_conv_buf  = metal_buffer(device, C_CONV * 4)
state_out_buf = metal_buffer(device, 3 * C_CONV * 4)

# Fill weight: weight[c, k] = 0.25 + 0.01 * (idx % 4) where idx = c*4 + k
i = 0
while i < C_CONV * 4
  metal_buffer_write_f32(w_conv_buf, i, ~0.25 + ~0.01 * (i % 4))
  i = i + 1
# Fill state: state[j, c] = 0.1 * cos(c * 0.005 + j)
j = 0
while j < 3
  c = 0
  while c < C_CONV
    metal_buffer_write_f32(state_buf, j * C_CONV + c, ~0.1 * Math.cos(c * ~0.005 + j))
    c = c + 1
  j = j + 1
# Fill x_new: x_new[c] = sin(c * 0.013)
c = 0
while c < C_CONV
  metal_buffer_write_f32(x_conv_buf, c, Math.sin(c * ~0.013))
  c = c + 1

conv_pipe = metal_pipeline(metal_compile_source(device, read_file(K_DIR + "conv1d_depthwise_step.metal")), "conv1d_depthwise_step")
metal_batch_begin(queue)
metal_dispatch_n(queue, conv_pipe, [w_conv_buf, state_buf, x_conv_buf, out_conv_buf, state_out_buf, C_CONV, C_CONV], C_CONV)
ms = metal_batch_commit_ms(queue, 0)
<< "  GPU time: " + (ms * ~1000.0).to_s + " µs"

REF_CONV = [~0.014099, ~0.015853, ~0.017612, ~0.019376, ~0.021145, ~0.022917, ~0.024694, ~0.026473]
max_d = ~0.0
i = 0
while i < 8
  got = metal_buffer_read_f32(out_conv_buf, i)
  d = got - REF_CONV[i]
  if d < ~0.0
    d = ~0.0 - d
  if d > max_d
    max_d = d
  i = i + 1
<< "  max diff (first 8): " + max_d.to_s
if max_d < ~0.001
  << "  PASS"
else
  << "  FAIL"

<< ""
<< "all 4 mamba helper kernels tested."
