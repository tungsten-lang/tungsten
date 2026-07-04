# Smoke test for NVFP4 matmul via Metal 4 matmul2d (dequant-into-tile).
# Synthetic data: all weights = NVFP4 value 1.0, all scales = 1.0, all
# activations = 1.0 → C[m,n] = K everywhere.

use core/metal

KERNEL_DIR = "bits/tungsten-llama/lib/kernels/"
SRC = read_file(KERNEL_DIR + "nvfp4_matmul_m4.metal")

device      = metal_device()
m4_compiler = metal4_compiler(device)
m4_queue    = metal4_queue(device)
m4_alloc    = metal4_allocator(device)

lib  = metal_compile_source(device, SRC)
pipe = metal4_pipeline(m4_compiler, lib, "nvfp4_matmul_m4", 128, 1, 1)

shapes = [
  [64,    2048, 2048],
  [128,   2048, 2048],
  [256,   2048, 2048],
  [512,   2048, 2048],
  [1024,  2048, 2048]
]

<< "NVFP4 matmul via matmul2d (dequant-into-tile) — F16 acts × NVFP4 weights, K=2048 N=2048"
<< "shape (M)  | gflops      ms/call    err_max  | weights_GB/s"
<< "-----------+----------------------------------+-------------"

i_shape = 0
while i_shape < shapes.size()
  shape = shapes[i_shape]
  M = shape[0]
  K = shape[1]
  N = shape[2]

  a_buf       = metal_buffer(device, M * K * 2)               # half
  w_packed    = metal_buffer(device, N * (K / 8) * 4)         # uint32[N*K/8]
  w_scales    = metal_buffer(device, N * (K / 16))            # uchar[N*K/16]
  c_buf       = metal_buffer(device, M * N * 4)               # float
  k_const_buf = metal_buffer(device, 4)
  metal_buffer_write_i32(k_const_buf, 0, K)

  # Fill A = ones (half(1.0) = 0x3C00). 2 halfs per i32.
  total_a_words = (M * K) / 2
  i = 0
  while i < total_a_words
    metal_buffer_write_i32(a_buf, i, 0x3C003C00)
    i = i + 1

  # Fill W_packed: every byte = 0x22 (low nibble = 2, high nibble = 2 → both fp16=1.0).
  # 4 bytes per i32 word, all 0x22 → 0x22222222.
  total_w_words = (N * (K / 8))
  i = 0
  while i < total_w_words
    metal_buffer_write_i32(w_packed, i, 0x22222222)
    i = i + 1

  # Fill W_scales: every byte = 0x38 (E4M3 → 1.0). Pack 4 per i32.
  total_s_words = (N * (K / 16)) / 4
  i = 0
  while i < total_s_words
    metal_buffer_write_i32(w_scales, i, 0x38383838)
    i = i + 1

  # Wrap A and C as MTLTensors. W stays as raw buffers.
  a_tensor = metal_tensor_2d(a_buf, METAL_DTYPE_FLOAT16, M, K, 0, 0)
  c_tensor = metal_tensor_2d(c_buf, METAL_DTYPE_FLOAT32, M, N, 0, 0)

  argtable = metal4_argtable(device, 5)
  metal4_argtable_set_tensor(argtable, 0, a_tensor)
  metal4_argtable_set_buffer(argtable, 1, w_packed)
  metal4_argtable_set_buffer(argtable, 2, w_scales)
  metal4_argtable_set_tensor(argtable, 3, c_tensor)
  metal4_argtable_set_buffer(argtable, 4, k_const_buf)

  resources = [a_buf, w_packed, w_scales, c_buf, k_const_buf]

  n_tg_x = (M + 63) / 64
  n_tg_y = (N + 31) / 32

  # Warmup.
  i = 0
  while i < 3
    metal4_dispatch_groups_3d(m4_queue, m4_alloc, pipe, argtable, resources, 4096, n_tg_x, n_tg_y, 1, 128, 1, 1)
    i = i + 1

  # Verify a few cells.
  metal4_dispatch_groups_3d(m4_queue, m4_alloc, pipe, argtable, resources, 4096, n_tg_x, n_tg_y, 1, 128, 1, 1)
  expected = K.to_f
  c0    = metal_buffer_read_f32(c_buf, 0)
  c_mid = metal_buffer_read_f32(c_buf, (M * N) / 2)
  c_last= metal_buffer_read_f32(c_buf, M * N - 1)
  << "    debug M=" + M.to_s + " expected=" + expected.to_s + " c0=" + c0.to_s + " mid=" + c_mid.to_s + " last=" + c_last.to_s
  err = ~0.0
  d = c0 - expected
  if d < ~0.0
    d = ~0.0 - d
  if d > err
    err = d
  d = c_mid - expected
  if d < ~0.0
    d = ~0.0 - d
  if d > err
    err = d
  d = c_last - expected
  if d < ~0.0
    d = ~0.0 - d
  if d > err
    err = d

  # Bench. Best of 5 trials × 30 dispatches.
  iters = 30
  best = ~1.0e18
  trial = 0
  while trial < 5
    t0 = clock
    i = 0
    while i < iters
      metal4_dispatch_groups_3d(m4_queue, m4_alloc, pipe, argtable, resources, 4096, n_tg_x, n_tg_y, 1, 128, 1, 1)
      i = i + 1
    elapsed = clock - t0
    ms = elapsed * ~1000.0 / iters
    if ms < best
      best = ms
    trial = trial + 1

  flops = 2 * M.to_f * N.to_f * K.to_f
  gflops = flops / (best / ~1000.0) / ~1.0e9
  # Weights bytes: N * K * 4/8 (4-bit + 1B/16 scales).
  weight_bytes = N.to_f * K.to_f * (~0.5 + ~1.0 / ~16.0)
  weight_gbs = weight_bytes / (best / ~1000.0) / ~1.0e9

  line = "  M=" + M.to_s
  while line.size() < 11
    line = line + " "
  line = line + "|  " + gflops.to_s + "    " + best.to_s + "    " + err.to_s + "  | " + weight_gbs.to_s
  << line

  i_shape = i_shape + 1
