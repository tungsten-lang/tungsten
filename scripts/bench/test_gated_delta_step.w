# Smoke test for gated_delta_step.metal — qwen3.6 Mamba/SSM single-step kernel.
#
# Synthetic inputs (deterministic): q[i]=sin(0.013i), k[i]=cos(0.011i),
# v[i]=0.5*sin(0.007i), g[i]=0.9+0.05*cos(0.05i), beta=tanh(0.02i)*0.5+0.5,
# state[i]=0.001*sin(0.0011i). Reference values from MLX's
# `gated_delta_kernel`. Pass criterion: max |y - y_ref| < 1e-3 (f32 path
# both sides, so should be near-bit-exact modulo simd_sum ordering).

use core/metal

KERNEL = "bits/tungsten-llama/lib/kernels/qwen3_6/gated_delta_step.metal"

B  = 1
HK = 16
HV = 32
DK = 128
DV = 128

device = metal_device()
queue  = metal_queue(device)

step_pipe = metal_pipeline(metal_compile_source(device, read_file(KERNEL)), "gated_delta_step")

# Allocate buffers
q_buf       = metal_buffer(device, B * HK * DK * 4)
k_buf       = metal_buffer(device, B * HK * DK * 4)
v_buf       = metal_buffer(device, B * HV * DV * 4)
g_buf       = metal_buffer(device, B * HV * 4)
beta_buf    = metal_buffer(device, B * HV * 4)
state_in    = metal_buffer(device, B * HV * DV * DK * 4)
state_out   = metal_buffer(device, B * HV * DV * DK * 4)
y_buf       = metal_buffer(device, B * HV * DV * 4)

# Fill q, k
i = 0
while i < B * HK * DK
  metal_buffer_write_f32(q_buf, i, Math.sin(i * ~0.013))
  metal_buffer_write_f32(k_buf, i, Math.cos(i * ~0.011))
  i = i + 1

# Fill v
i = 0
while i < B * HV * DV
  metal_buffer_write_f32(v_buf, i, Math.sin(i * ~0.007) * ~0.5)
  i = i + 1

# Fill g, beta
i = 0
while i < B * HV
  metal_buffer_write_f32(g_buf, i, ~0.9 + ~0.05 * Math.cos(i * ~0.05))
  metal_buffer_write_f32(beta_buf, i, Math.sin(i * ~0.02) * ~0.4 + ~0.5)
  i = i + 1

# Fill state_in
i = 0
n_state = B * HV * DV * DK
while i < n_state
  metal_buffer_write_f32(state_in, i, ~0.001 * Math.sin(i * ~0.0011))
  i = i + 1

# Dispatch: TG (32, 4, 1) = 128 threads; grid TGs = (1, DV/4, B*HV)
n_tg_y = DV / 4
n_tg_z = B * HV
total_tgs = 1 * n_tg_y * n_tg_z

<< "running gated_delta_step (B=" + B.to_s + ", Hk=" + HK.to_s + ", Hv=" + HV.to_s + ", Dk=" + DK.to_s + ", Dv=" + DV.to_s + ")"
<< "  dispatch: " + total_tgs.to_s + " TGs of 128 threads"

metal_batch_begin(queue)
# Note: the dispatch needs (1, n_tg_y, n_tg_z) TGs and (32, 4, 1) threads/TG.
# Tungsten's metal_dispatch_groups takes (n_groups, threads_per_tg) — both 1D.
# Use metal_dispatch_3d if available; otherwise flatten z-major.
metal_dispatch_3d(queue, step_pipe,
  [q_buf, k_buf, v_buf, g_buf, beta_buf, state_in, y_buf, state_out, HK, HV, DK, DV],
  1, n_tg_y, n_tg_z,
  32, 4, 1)
ms = metal_batch_commit_ms(queue, 0)
<< "  GPU time: " + (ms * ~1000.0).to_s + " µs"

# MLX reference (head 0, dv 0..7)
REF_Y = [
  ~-0.110851,
  ~-0.309529,
  ~-0.500365,
  ~-0.677864,
  ~-0.836798,
  ~-0.972305,
  ~-1.079988,
  ~-1.156000
]

<< ""
<< "first 8 outputs (head 0, dv 0..7) — kernel vs MLX reference:"
max_abs_diff = ~0.0
worst_idx = -1
i = 0
while i < 8
  got = metal_buffer_read_f32(y_buf, i)
  ref = REF_Y[i]
  d = got - ref
  if d < ~0.0
    d = ~0.0 - d
  if d > max_abs_diff
    max_abs_diff = d
    worst_idx = i
  << "  y[" + i.to_s + "]: kernel=" + got.to_s + "  ref=" + ref.to_s + "  diff=" + (got - ref).to_s
  i = i + 1
<< ""
<< "max |y - y_ref|: " + max_abs_diff.to_s + " (worst at dv=" + worst_idx.to_s + ")"
if max_abs_diff < ~0.001
  << "PASS"
else
  << "FAIL — diff exceeds 1e-3 (f32 both sides; investigate)"
