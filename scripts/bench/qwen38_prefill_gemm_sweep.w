# Qwen3.8-27B prefill GEMM chunk-size sweep: matmul2d (M5 Neural Accelerators)
# vs the current simdgroup_matrix GEMM (nvfp4_gemm_f32, tiles m8/m16/m32/m64).
#
# Sweeps M from the decode/verify regime (8) up through long-prefill (8192).
# The current path picks the smallest tile that fits M (m8/m16/m32/m64) and
# loops 64-row chunks past 64. matmul2d always tiles M at 64, so below M=64 it
# over-computes a full 64-row tile — this sweep exposes exactly where that costs
# it (small M) and where the matrix units win (large M).
#
# NVFP4 test data: A=1.0, weight nibble=2 (=1.0), scale=1.0  ->  C[m,n] = K.
# Build (metal4 is in the default runtime): bin/tungsten -o <out> this.w  (COMPILED — perf gate)

use core/metal

KERNEL_DIR = "bits/tungsten-llama/lib/kernels/"
NVFP4_DIR  = "bits/tungsten-llama/lib/kernels/nvfp4/"

device      = metal_device
queue       = metal_queue(device)
m4_compiler = metal4_compiler(device)
m4_queue    = metal4_queue(device)
m4_alloc    = metal4_allocator(device)

m4_lib  = metal_compile_source(device, read_file(KERNEL_DIR + "nvfp4_matmul_m4.metal"))
m4_pipe = metal4_pipeline(m4_compiler, m4_lib, "nvfp4_matmul_m4", 128, 1, 1)

gemm_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_gemm_f32.metal"))
gemm_m8  = metal_pipeline(gemm_lib, "nvfp4_gemm_f32_m8")
gemm_m16 = metal_pipeline(gemm_lib, "nvfp4_gemm_f32_m16")
gemm_m32 = metal_pipeline(gemm_lib, "nvfp4_gemm_f32_m32")
gemm_m64 = metal_pipeline(gemm_lib, "nvfp4_gemm_f32_m64")

gscale = ~1.0

# Qwen3.8-27B heavy projection shapes [K, N, label].
shapes = [
  [5120,  17408, "ffn_gate_up"],
  [17408, 5120,  "ffn_down"],
  [5120,  8192,  "attn_qkv"]
]
m_sizes = [8, 16, 32, 64, 128, 256, 512, 1024, 2048, 4096, 8192]

i_shape = 0
while i_shape < shapes.size()
  shape = shapes[i_shape]
  K = shape[0]
  N = shape[1]
  label = shape[2]

  w_packed = metal_buffer(device, N * (K / 8) * 4)
  w_scales = metal_buffer(device, N * (K / 16))
  wi = 0
  wn = N * (K / 8)
  while wi < wn
    metal_buffer_write_i32(w_packed, wi, 0x22222222)
    wi = wi + 1
  wi = 0
  wn = (N * (K / 16)) / 4
  while wi < wn
    metal_buffer_write_i32(w_scales, wi, 0x38383838)
    wi = wi + 1

  # Current arm reuses one 64-row activation/output chunk.
  x64 = metal_buffer(device, 64 * K * 4)
  y64 = metal_buffer(device, 64 * N * 4)
  xi = 0
  xn = 64 * K
  while xi < xn
    metal_buffer_write_f32(x64, xi, ~1.0)
    xi = xi + 1

  << ""
  << "=== " + label + "  K=" + K.to_s + " N=" + N.to_s + " ==="
  << "  M     | matmul2d ms  simd ms     speedup | GFLOPs_m4  err"

  i_m = 0
  while i_m < m_sizes.size()
    M = m_sizes[i_m]
    m_pad = ((M + 127) / 128) * 128

    # ---- NA arm: matmul2d over m_pad rows (tiles M at 64) ----
    a_buf = metal_buffer(device, m_pad * K * 2)
    c_buf = metal_buffer(device, m_pad * N * 4)
    ai = 0
    an = (m_pad * K) / 2
    while ai < an
      metal_buffer_write_i32(a_buf, ai, 0x3C003C00)
      ai = ai + 1
    k_const = metal_buffer(device, 4)
    metal_buffer_write_i32(k_const, 0, K)
    gscale_buf = metal_buffer(device, 4)
    metal_buffer_write_f32(gscale_buf, 0, ~1.0)

    a_tensor = metal_tensor_2d(a_buf, METAL_DTYPE_FLOAT16, m_pad, K, 0, 0)
    c_tensor = metal_tensor_2d(c_buf, METAL_DTYPE_FLOAT32, m_pad, N, 0, 0)
    at = metal4_argtable(device, 6)
    metal4_argtable_set_tensor(at, 0, a_tensor)
    metal4_argtable_set_buffer(at, 1, w_packed)
    metal4_argtable_set_buffer(at, 2, w_scales)
    metal4_argtable_set_tensor(at, 3, c_tensor)
    metal4_argtable_set_buffer(at, 4, k_const)
    metal4_argtable_set_buffer(at, 5, gscale_buf)
    res = [a_buf, w_packed, w_scales, c_buf, k_const, gscale_buf]
    ntx = m_pad / 128
    nty = (N + 63) / 64

    j = 0
    while j < 3
      metal4_dispatch_groups_3d(m4_queue, m4_alloc, m4_pipe, at, res, 16384, ntx, nty, 1, 128, 1, 1)
      j = j + 1
    expected = K.to_f
    c0 = metal_buffer_read_f32(c_buf, 0)
    err = c0 - expected
    if err < ~0.0 then err = ~0.0 - err

    iters = 10
    best_m4 = ~1.0e18
    trial = 0
    while trial < 3
      t0 = clock
      j = 0
      while j < iters
        metal4_dispatch_groups_3d(m4_queue, m4_alloc, m4_pipe, at, res, 16384, ntx, nty, 1, 128, 1, 1)
        j = j + 1
      dt = (clock - t0) * ~1000.0 / iters
      if dt < best_m4 then best_m4 = dt
      trial = trial + 1

    # ---- Current arm: smallest simdgroup tile that fits M, chunked past 64 ----
    cur_pipe = gemm_m64
    cur_rows = 64
    nchunks = 1
    if M <= 8
      cur_pipe = gemm_m8
      cur_rows = M
    else
      if M <= 16
        cur_pipe = gemm_m16
        cur_rows = M
      else
        if M <= 32
          cur_pipe = gemm_m32
          cur_rows = M
        else
          if M <= 64
            cur_rows = M
          else
            nchunks = (M + 63) / 64
    ngy = (N + 31) / 32

    j = 0
    while j < 3
      metal_batch_begin(queue)
      c = 0
      while c < nchunks
        metal_dispatch_groups(queue, cur_pipe, [w_packed, w_scales, x64, y64, K, N, gscale, cur_rows], ngy, 128)
        c = c + 1
      metal_batch_commit(queue)
      j = j + 1
    best_simd = ~1.0e18
    trial = 0
    while trial < 3
      t0 = clock
      j = 0
      while j < iters
        metal_batch_begin(queue)
        c = 0
        while c < nchunks
          metal_dispatch_groups(queue, cur_pipe, [w_packed, w_scales, x64, y64, K, N, gscale, cur_rows], ngy, 128)
          c = c + 1
        metal_batch_commit(queue)
        j = j + 1
      dt = (clock - t0) * ~1000.0 / iters
      if dt < best_simd then best_simd = dt
      trial = trial + 1

    gflops = (~2.0 * M.to_f * N.to_f * K.to_f) / (best_m4 * ~1000000.0)
    speed = best_simd / best_m4
    << "  " + M.to_s + "\t| " + best_m4.to_s + "\t" + best_simd.to_s + "\t" + speed.to_s + "x | " + gflops.to_s + "\t" + err.to_s
    i_m = i_m + 1
  i_shape = i_shape + 1
