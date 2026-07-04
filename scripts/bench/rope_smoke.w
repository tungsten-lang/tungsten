# RoPE NEOX kernel correctness smoke. Compute the rotation on the CPU
# for a known position + theta_base, dispatch the kernel, compare.

use core/metal

HEAD_DIM = 128
HEAD_DIM_HALF = 64
N_HEADS = 32         # qwen3 q-projection layout
POS = 17             # arbitrary token position
BASE = ~1000000.0    # qwen3 freq_base

device = metal_device()
msl = read_file("bits/tungsten-llama/lib/rope.metal")
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "rope_neox")
queue = metal_queue(device)

x_buf       = metal_buffer(device, N_HEADS * HEAD_DIM * 4)
cos_buf     = metal_buffer(device, HEAD_DIM_HALF * 4)
sin_buf     = metal_buffer(device, HEAD_DIM_HALF * 4)
hd_buf      = metal_buffer(device, 4)
hdh_buf     = metal_buffer(device, 4)
nh_buf      = metal_buffer(device, 4)

# CPU-side: build the cos/sin tables for this position.
# theta_i = base^(-2i/head_dim); angle = pos * theta_i.
inv_hd = ~2.0 / HEAD_DIM
log_base = Math.log(BASE)
i = 0
while i < HEAD_DIM_HALF
  theta = Math.exp(log_base * (~0.0 - i * inv_hd))
  angle = POS * theta
  metal_buffer_write_f32(cos_buf, i, Math.cos(angle))
  metal_buffer_write_f32(sin_buf, i, Math.sin(angle))
  i = i + 1

# Deterministic input: x[i] = sin(i * 0.0123) so values are in [-1, 1].
n_total = N_HEADS * HEAD_DIM
i = 0
while i < n_total
  metal_buffer_write_f32(x_buf, i, Math.sin(i * ~0.0123))
  i = i + 1

metal_buffer_write_i32(hd_buf, 0, HEAD_DIM)
metal_buffer_write_i32(hdh_buf, 0, HEAD_DIM_HALF)
metal_buffer_write_i32(nh_buf, 0, N_HEADS)

# Dispatch one thread per (head, pair).
total_pairs = N_HEADS * HEAD_DIM_HALF
bufs = [x_buf, cos_buf, sin_buf, hd_buf, hdh_buf, nh_buf]
metal_dispatch_n(queue, pipeline, bufs, total_pairs)

# CPU reference and compare.
max_abs_err = ~0.0
h = 0
while h < N_HEADS
  base = h * HEAD_DIM
  i = 0
  while i < HEAD_DIM_HALF
    a_orig = Math.sin((base + i) * ~0.0123)
    b_orig = Math.sin((base + i + HEAD_DIM_HALF) * ~0.0123)
    theta = Math.exp(log_base * (~0.0 - i * inv_hd))
    angle = POS * theta
    c = Math.cos(angle)
    s = Math.sin(angle)
    expected_lo = a_orig * c - b_orig * s
    expected_hi = a_orig * s + b_orig * c

    got_lo = metal_buffer_read_f32(x_buf, base + i)
    got_hi = metal_buffer_read_f32(x_buf, base + i + HEAD_DIM_HALF)

    err = expected_lo - got_lo
    if err < ~0.0
      err = ~0.0 - err
    if err > max_abs_err
      max_abs_err = err
    err = expected_hi - got_hi
    if err < ~0.0
      err = ~0.0 - err
    if err > max_abs_err
      max_abs_err = err
    i = i + 1
  h = h + 1

<< "rope_neox smoke (heads=" + N_HEADS.to_s + ", head_dim=" + HEAD_DIM.to_s + ", pos=" + POS.to_s + "):"
<< "  max abs error vs CPU = " + max_abs_err.to_s
if max_abs_err > ~0.0001
  << "FAIL"
  exit 1
<< "OK"
