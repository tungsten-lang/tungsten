# Metal 4 matmul2d (cooperative tensors) vs simdgroup_matrix v4 — F16 matmul.
# Shape: Lightning QKV-projection prefill at varied batch sizes.
#   M = batch (prefill tokens), K = 2048 (hidden), N = 2048 (n_q_heads * head_dim)
#
# Both kernels compute C[M,N] = A[M,K] * B[N,K]^T with weights stored row-major
# as N×K (project convention). M4 path uses MTL4ArgumentTable + MTLTensor +
# MTL4ComputePipelineDescriptor with requiredThreadsPerThreadgroup; the legacy
# kernel uses the existing buffer-binding dispatch.

use core/metal

KERNEL_DIR = "bits/tungsten-llama/lib/kernels/"
M4_SRC     = read_file(KERNEL_DIR + "f16_matmul_m4.metal")
SIMD_SRC   = read_file(KERNEL_DIR + "nvfp4/f16_matmul_simd_v4_fc.metal")

device      = metal_device()
queue       = metal_queue(device)
m4_compiler = metal4_compiler(device)
m4_queue    = metal4_queue(device)
m4_alloc    = metal4_allocator(device)

m4_lib  = metal_compile_source(device, M4_SRC)
m4_pipe = metal4_pipeline(m4_compiler, m4_lib, "f16_matmul_m4", 128, 1, 1)

K = 2048
N = 2048
shapes = [64, 128, 256, 512, 1024]

<< "Metal 4 matmul2d vs simdgroup_matrix v4 — F16 matmul, K=" + K.to_s + " N=" + N.to_s
<< "shape (M)  | gflops_m4   gflops_simd  speedup  | err_max"
<< "-----------+----------------------------------+--------"

i_shape = 0
while i_shape < shapes.size()
  M = shapes[i_shape]

  a_buf = metal_buffer(device, M * K * 2)
  b_buf = metal_buffer(device, N * K * 2)
  c_buf = metal_buffer(device, M * N * 4)
  m_buf = metal_buffer(device, 4); metal_buffer_write_i32(m_buf, 0, M)
  n_buf = metal_buffer(device, 4); metal_buffer_write_i32(n_buf, 0, N)
  k_buf = metal_buffer(device, 4); metal_buffer_write_i32(k_buf, 0, K)

  # Fill A=ones, B=ones in f16. half(1.0) bit pattern = 0x3C00.
  total_a_words = (M * K) / 2
  i = 0
  while i < total_a_words
    metal_buffer_write_i32(a_buf, i, 0x3C003C00)
    i = i + 1
  total_b_words = (N * K) / 2
  i = 0
  while i < total_b_words
    metal_buffer_write_i32(b_buf, i, 0x3C003C00)
    i = i + 1

  # M4 path: tensors + argtable.
  a_t = metal_tensor_2d(a_buf, METAL_DTYPE_FLOAT16, M, K, 0, 0)
  b_t = metal_tensor_2d(b_buf, METAL_DTYPE_FLOAT16, N, K, 0, 0)
  c_t = metal_tensor_2d(c_buf, METAL_DTYPE_FLOAT32, M, N, 0, 0)
  m4_argtable = metal4_argtable(device, 3)
  metal4_argtable_set_tensor(m4_argtable, 0, a_t)
  metal4_argtable_set_tensor(m4_argtable, 1, b_t)
  metal4_argtable_set_tensor(m4_argtable, 2, c_t)
  m4_resources = [a_buf, b_buf, c_buf]

  n_tg_x = (M + 63) / 64
  n_tg_y = (N + 31) / 32

  # Build SIMD baseline pipeline with function constants for this shape.
  batch_fc = M
  if batch_fc < 8
    batch_fc = 8
  simd_lib = metal_compile_source(device, SIMD_SRC)
  simd_pipe = metal_pipeline_with_int_constants(simd_lib, "f16_matmul_simd_v4_fc", [K, N, batch_fc])
  n_groups_simd = (N / 32) * (batch_fc / 8)

  # Warmup.
  iters_warm = 5
  i = 0
  while i < iters_warm
    metal4_dispatch_groups_3d(m4_queue, m4_alloc, m4_pipe, m4_argtable, m4_resources, 0, n_tg_x, n_tg_y, 1, 128, 1, 1)
    metal_dispatch_groups(queue, simd_pipe, [b_buf, a_buf, c_buf], n_groups_simd, 128)
    i = i + 1

  # Verify M4 against analytic answer C[i,j] = K * 1 * 1 = K.
  metal4_dispatch_groups_3d(m4_queue, m4_alloc, m4_pipe, m4_argtable, m4_resources, 0, n_tg_x, n_tg_y, 1, 128, 1, 1)
  c0    = metal_buffer_read_f32(c_buf, 0)
  c_mid = metal_buffer_read_f32(c_buf, (M * N) / 2)
  c_last= metal_buffer_read_f32(c_buf, M * N - 1)
  expected = K.to_f
  err = ~0.0
  d0 = c0 - expected
  if d0 < ~0.0
    d0 = ~0.0 - d0
  if d0 > err
    err = d0
  d_mid = c_mid - expected
  if d_mid < ~0.0
    d_mid = ~0.0 - d_mid
  if d_mid > err
    err = d_mid
  d_last = c_last - expected
  if d_last < ~0.0
    d_last = ~0.0 - d_last
  if d_last > err
    err = d_last

  # Bench. Best of 5, 30 dispatches each.
  iters = 30
  best_m4 = ~1.0e18
  trial = 0
  while trial < 5
    t0 = clock
    i = 0
    while i < iters
      metal4_dispatch_groups_3d(m4_queue, m4_alloc, m4_pipe, m4_argtable, m4_resources, 0, n_tg_x, n_tg_y, 1, 128, 1, 1)
      i = i + 1
    elapsed = clock - t0
    ms = elapsed * ~1000.0 / iters
    if ms < best_m4
      best_m4 = ms
    trial = trial + 1

  best_simd = ~1.0e18
  trial = 0
  while trial < 5
    metal_batch_begin(queue)
    t0 = clock
    i = 0
    while i < iters
      metal_dispatch_groups(queue, simd_pipe, [b_buf, a_buf, c_buf], n_groups_simd, 128)
      i = i + 1
    metal_batch_commit(queue)
    elapsed = clock - t0
    ms = elapsed * ~1000.0 / iters
    if ms < best_simd
      best_simd = ms
    trial = trial + 1

  flops = 2 * M.to_f * N.to_f * K.to_f
  gflops_m4   = flops / (best_m4   / ~1000.0) / ~1.0e9
  gflops_simd = flops / (best_simd / ~1000.0) / ~1.0e9
  speedup = gflops_m4 / gflops_simd

  line = "  M=" + M.to_s
  while line.size() < 11
    line = line + " "
  line = line + "|  " + gflops_m4.to_s + "    " + gflops_simd.to_s + "    " + speedup.to_s + "x  | " + err.to_s
  << line

  i_shape = i_shape + 1
