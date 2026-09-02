# Neural-Accelerator matmul bench, CLASSIC encoder (no Metal 4 objects).
#
#   na_matmul_bench <kernel.metal> <kernel_name> nvfp4|bf16|f16 MT NT KT
#
# Synthetic data (W = 1.0, scales = 1.0, A = 1.0 -> C = K everywhere); err is
# the max |C - K| over three probed cells. Timing is the batched form: 20
# dispatches inside one concurrent command buffer, best of 5 commits - the
# number a kernel sees when it sits inside a recorded program, not the
# per-dispatch commit+wait floor. Shapes that are not tile-aligned are
# skipped (the cooperative store does not clip).
use core/metal

SRC = read_file(ARGV[0])
KNAME = ARGV[1]
KIND = ARGV[2]
MT = ARGV[3].to_i
NT = ARGV[4].to_i
KT = ARGV[5].to_i
device = metal_device()
queue = metal_queue(device)
lib = metal_compile_source(device, SRC)
pipe = metal_pipeline(lib, KNAME)
ONE = 0x3C003C00
if KIND == "bf16" then ONE = 0x3F803F80

# [M, K, N]: Qwen3.8-27B ffn/attn shapes, flash-next backbone shapes, expert shapes.
shapes = [[128, 2048, 2048], [512, 2048, 2048], [1024, 2048, 2048], [512, 5120, 17408], [1024, 5120, 17408], [1024, 17408, 5120], [512, 5120, 12288], [512, 2560, 512], [512, 2560, 6144], [512, 10240, 320], [512, 320, 10240], [64, 2560, 640], [128, 2560, 640], [512, 2560, 640], [512, 640, 2560]]
<< "NA matmul (classic encoder) " + KIND + " " + KNAME + " tile " + MT.to_s + "x" + NT.to_s + "x" + KT.to_s + " - batched 20 dispatches/commit"
<< "M K N | gflops ms err"
i_shape = 0
while i_shape < shapes.size()
  shape = shapes[i_shape]
  M = shape[0]
  K = shape[1]
  N = shape[2]
  if M % MT != 0 || N % NT != 0 || K % KT != 0
    << M.to_s + " " + K.to_s + " " + N.to_s + " | skipped (not tile-aligned)"
  else
    a_buf = metal_buffer(device, M * K * 2)
    c_buf = metal_buffer(device, M * N * 4)
    k_buf = metal_buffer(device, 4)
    metal_buffer_write_i32(k_buf, 0, K)
    m_buf = metal_buffer(device, 4)
    metal_buffer_write_i32(m_buf, 0, M)
    n_buf = metal_buffer(device, 4)
    metal_buffer_write_i32(n_buf, 0, N)
    i = 0
    while i < (M * K) / 2
      metal_buffer_write_i32(a_buf, i, ONE)
      i = i + 1
    bufs = []
    if KIND == "nvfp4"
      w_packed = metal_buffer(device, N * (K / 8) * 4)
      w_scales = metal_buffer(device, N * (K / 16))
      g_buf = metal_buffer(device, 4)
      metal_buffer_write_f32(g_buf, 0, ~1.0)
      i = 0
      while i < N * (K / 8)
        metal_buffer_write_i32(w_packed, i, 0x22222222)
        i = i + 1
      i = 0
      while i < (N * (K / 16)) / 4
        metal_buffer_write_i32(w_scales, i, 0x38383838)
        i = i + 1
      bufs = [a_buf, w_packed, w_scales, c_buf, k_buf, g_buf, m_buf, n_buf]
    else
      w_buf = metal_buffer(device, N * K * 2)
      i = 0
      while i < (N * K) / 2
        metal_buffer_write_i32(w_buf, i, ONE)
        i = i + 1
      bufs = [a_buf, w_buf, c_buf, k_buf, m_buf, n_buf]
    ntx = M / MT
    nty = N / NT
    metal_dispatch_3d(queue, pipe, bufs, ntx, nty, 1, 128, 1, 1)
    err = ~0.0
    ci = 0
    while ci < 3
      idx = 0
      if ci == 1 then idx = (M * N) / 2
      if ci == 2 then idx = M * N - 1
      d = metal_buffer_read_f32(c_buf, idx) - K.to_f
      if d < ~0.0 then d = ~0.0 - d
      if d > err then err = d
      ci = ci + 1
    iters = 20
    best = ~1.0e18
    trial = 0
    while trial < 5
      t0 = clock
      metal_batch_begin_concurrent(queue)
      i = 0
      while i < iters
        metal_dispatch_3d(queue, pipe, bufs, ntx, nty, 1, 128, 1, 1)
        i = i + 1
      metal_batch_commit(queue)
      ms = (clock - t0) * ~1000.0 / iters
      if ms < best then best = ms
      trial = trial + 1
    gflops = (2 * M.to_f * N.to_f * K.to_f) / (best / ~1000.0) / ~1.0e9
    << M.to_s + " " + K.to_s + " " + N.to_s + " | " + gflops.to_s + " " + best.to_s + " " + err.to_s
  i_shape = i_shape + 1
