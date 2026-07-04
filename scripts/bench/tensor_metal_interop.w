# Tensor ↔ Metal 4 interop proof.
#
# Demonstrates that ONE shared MTLBuffer, wrapped as a Tensor, is usable as
# all three faces at once over the SAME bytes:
#   .buffer        → bound into the MTL4 residency set
#   .metal_tensor  → bound into the MTL4 argument table (a cooperative-tensor
#                    matmul kernel reads/writes it)
#   .at / .set     → CPU element access of the result the GPU just wrote
#
# It reuses the proven f16_matmul_m4 cooperative-tensor kernel: C[M,N] =
# A[M,K] · B[N,K]^T with A = B = ones, so the analytic answer is C[i,j] = K.
# The operands are built entirely as Tensors; success means a Tensor's tensor
# face and buffer face name the same allocation the CPU then reads.
#
# Compiled-only (class-side factories) and macOS 26 (MTLTensor). Run via -o.

use core/metal
use core/tensor

# Fill a Metal buffer with f16 ones via the .buffer face. half(1.0) = 0x3C00,
# so an i32 word of 0x3C003C00 writes two f16 ones at once.
fn fill_ones_f16(buf, n_i32_words)
  i = 0
  while i < n_i32_words
    metal_buffer_write_i32(buf, i, 0x3C003C00)
    i = i + 1

KERNEL_DIR = "bits/tungsten-llama/lib/kernels/"
M4_SRC     = read_file(KERNEL_DIR + "f16_matmul_m4.metal")

device      = metal_device()
m4_compiler = metal4_compiler(device)
m4_queue    = metal4_queue(device)
m4_alloc    = metal4_allocator(device)
m4_lib      = metal_compile_source(device, M4_SRC)
m4_pipe     = metal4_pipeline(m4_compiler, m4_lib, "f16_matmul_m4", 128, 1, 1)

M = 64
K = 2048
N = 2048

<< "Tensor <-> Metal 4 interop — C(M,N) = A(M,K)·B(N,K)^T, A=B=ones, M=" + M.to_s + " K=" + K.to_s + " N=" + N.to_s

# Operands as Tensors over fresh shared buffers.
a = Tensor.zeros(device, Tensor.f16, [M, K])
b = Tensor.zeros(device, Tensor.f16, [N, K])
c = Tensor.zeros(device, Tensor.f32, [M, N])

# Fill A and B through the .buffer face (CPU writes to unified memory).
fill_ones_f16(a.buffer, (M * K) / 2)
fill_ones_f16(b.buffer, (N * K) / 2)

# Bind each operand's .metal_tensor face into the argument table...
argtable = metal4_argtable(device, 3)
metal4_argtable_set_tensor(argtable, 0, a.metal_tensor)
metal4_argtable_set_tensor(argtable, 1, b.metal_tensor)
metal4_argtable_set_tensor(argtable, 2, c.metal_tensor)

# ...and each operand's .buffer face into the residency set. Same allocations,
# two faces, one dispatch.
resources = [a.buffer, b.buffer, c.buffer]

n_tg_x = (M + 63) / 64
n_tg_y = (N + 31) / 32
metal4_dispatch_groups_3d(m4_queue, m4_alloc, m4_pipe, argtable, resources, 0, n_tg_x, n_tg_y, 1, 128, 1, 1)

# Read C back through the CPU .at face of the SAME Tensor the GPU wrote.
expected = K.to_f
c00   = c.at([0, 0])
cmid  = c.at([M / 2, N / 2])
clast = c.at([M - 1, N - 1])

err = ~0.0
d = c00 - expected
if d < ~0.0
  d = ~0.0 - d
if d > err
  err = d
d = cmid - expected
if d < ~0.0
  d = ~0.0 - d
if d > err
  err = d
d = clast - expected
if d < ~0.0
  d = ~0.0 - d
if d > err
  err = d

<< "expected C(i,j)      = " + expected.to_s
<< "CPU .at (0,0)        = " + c00.to_s
<< "CPU .at (mid,mid)    = " + cmid.to_s
<< "CPU .at (last,last)  = " + clast.to_s
<< "max abs error        = " + err.to_s

if err < ~1.0
  << "PASS — one Tensor served as MTLTensor (argtable), MTLBuffer (residency), and CPU array (readback) over the same shared bytes."
else
  << "FAIL — readback does not match analytic answer."
