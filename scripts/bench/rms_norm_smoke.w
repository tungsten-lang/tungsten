# RMSNorm GPU kernel correctness smoke.
#
# Build a deterministic input, compute the expected output on the CPU,
# dispatch the kernel, compare element-wise. Catches off-by-one bugs in
# the lane stride, sign errors in the reduction, and missing eps terms.

use core/metal

N = 2048
EPS = ~0.000001

device = metal_device()
msl = read_file("bits/tungsten-llama/lib/rms_norm.metal")
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "rms_norm")
queue = metal_queue(device)

x_buf = metal_buffer(device, N * 4)
w_buf = metal_buffer(device, N * 4)
y_buf = metal_buffer(device, N * 4)
n_buf = metal_buffer(device, 4)
inv_n_buf = metal_buffer(device, 4)
eps_buf = metal_buffer(device, 4)

# Deterministic input: x[i] = (i mod 7) - 3 (small ints in [-3, 3]),
# weights w[i] = 0.5 + (i mod 5) * 0.1 (range [0.5, 0.9]).
i = 0
while i < N
  xi = ~0.0 + ((i % 7) - 3)
  metal_buffer_write_f32(x_buf, i, xi)
  wi = ~0.5 + ((i % 5) * ~0.1)
  metal_buffer_write_f32(w_buf, i, wi)
  i = i + 1

metal_buffer_write_i32(n_buf, 0, N)
metal_buffer_write_f32(inv_n_buf, 0, ~1.0 / N)
metal_buffer_write_f32(eps_buf, 0, EPS)

# CPU reference: compute mean(x²) + eps, then 1/sqrt(...), then y[i] = x[i] * rrms * w[i].
sum_sq = ~0.0
i = 0
while i < N
  v = ~0.0 + ((i % 7) - 3)
  sum_sq = sum_sq + v * v
  i = i + 1
mean_sq = sum_sq / N
rrms = ~1.0 / Math.sqrt(mean_sq + EPS)

# Dispatch: 1 threadgroup, 32 lanes.
bufs = [x_buf, w_buf, y_buf, n_buf, inv_n_buf, eps_buf]
metal_dispatch_groups(queue, pipeline, bufs, 1, 32)

# Compare element-wise.
max_abs_err = ~0.0
i = 0
while i < N
  expected_x = ~0.0 + ((i % 7) - 3)
  expected_w = ~0.5 + ((i % 5) * ~0.1)
  expected = expected_x * rrms * expected_w
  got = metal_buffer_read_f32(y_buf, i)
  err = expected - got
  if err < ~0.0
    err = ~0.0 - err
  if err > max_abs_err
    max_abs_err = err
  i = i + 1

<< "rms_norm smoke (n=" + N.to_s + "):"
<< "  rrms = " + rrms.to_s
<< "  max abs error vs CPU = " + max_abs_err.to_s
if max_abs_err > ~0.001
  << "FAIL: error too large"
  exit 1
<< "OK"
