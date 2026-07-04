# P2.4 smoke: hand-tuned Q8_0 matvec @gpu kernel.
#
# Test case: N=4 output rows, k_dim=32 input cols (1 Q8_0 block per row).
# All quants = 1, scales = {1.0, 2.0, 4.0, 8.0} per row, x = all 1.0.
# Expected y[m] = scale[m] * sum(quants) = scale[m] * 32.

use core/metal

## i8[]: w_q
## f16[]: w_s
## f32[]: x
## f32[]: y
## i32: k_dim
@gpu fn q8_matvec(w_q, w_s, x, y, k_dim)
  m = gpu.thread_position_in_grid.x ## i32
  nb = k_dim / 32 ## i32
  acc = 0.0 ## f32
  b = 0 ## i32
  while b < nb
    s = w_s[m * nb + b] ## f16
    block_acc = 0.0 ## f32
    j = 0 ## i32
    while j < 32
      block_acc = block_acc + w_q[m * k_dim + b * 32 + j] * x[b * 32 + j]
      j = j + 1
    acc = acc + s * block_acc
    b = b + 1
  y[m] = acc

msl = read_file("spec/core/metal_q8_matvec_spec.metal")

device = metal_device()
library = metal_compile_source(device, msl)
pipeline = metal_pipeline(library, "q8_matvec")

N = 4
k_dim = 32

# w_q: 4 rows × 32 i8s = 128 bytes. All quants = 1 → each i32 slot = 0x01010101.
w_q_buf = metal_buffer(device, N * k_dim)
i = 0
while i < (N * k_dim) / 4
  metal_buffer_write_i32(w_q_buf, i, 0x01010101)
  i = i + 1

# w_s: 4 scales (1 block per row), packed as 2 i32 slots (2 f16s each).
# f16 bits: 1.0 = 0x3C00, 2.0 = 0x4000, 4.0 = 0x4400, 8.0 = 0x4800.
# slot 0: low=1.0(0x3C00) high=2.0(0x4000) → 0x40003C00
# slot 1: low=4.0(0x4400) high=8.0(0x4800) → 0x48004400
w_s_buf = metal_buffer(device, N * 2)
metal_buffer_write_i32(w_s_buf, 0, 0x40003C00)
metal_buffer_write_i32(w_s_buf, 1, 0x48004400)

# x: k_dim f32 ones.
x_buf = metal_buffer(device, k_dim * 4)
i = 0
while i < k_dim
  metal_buffer_write_f32(x_buf, i, ~1.0)
  i = i + 1

y_buf = metal_buffer(device, N * 4)
k_buf = metal_buffer(device, 4)
metal_buffer_write_i32(k_buf, 0, k_dim)

queue = metal_queue(device)
metal_dispatch_n(queue, pipeline, [w_q_buf, w_s_buf, x_buf, y_buf, k_buf], N)

r0 = metal_buffer_read_f32(y_buf, 0)
r1 = metal_buffer_read_f32(y_buf, 1)
r2 = metal_buffer_read_f32(y_buf, 2)
r3 = metal_buffer_read_f32(y_buf, 3)

# Expected: y[m] = scale[m] * 32
# row 0: 1.0 * 32 = 32
# row 1: 2.0 * 32 = 64
# row 2: 4.0 * 32 = 128
# row 3: 8.0 * 32 = 256
if r0 == ~32.0 && r1 == ~64.0 && r2 == ~128.0 && r3 == ~256.0
  << "q8 matvec smoke ok"
else
  << "FAIL q8 matvec: " + r0.to_s + " " + r1.to_s + " " + r2.to_s + " " + r3.to_s
  exit 1
