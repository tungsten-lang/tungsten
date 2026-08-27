# Numeric check + isolated timing of nvfp4_gemm_f32 (simdgroup-matrix GEMM)
# against the exact cross-row GEMV (nvfp4_wides_b8_r2) on random NVFP4 data.
#   bin/tungsten run scripts/bench/test_nvfp4_gemm_f32.w [K] [N]
use core/metal
NVFP4_DIR = "bits/tungsten-llama/lib/kernels/nvfp4/"
K = ARGV.size() > 0 ? ARGV[0].to_i() : 5120
N = ARGV.size() > 1 ? ARGV[1].to_i() : 5120
M = 8
device = metal_device()
queue = metal_queue(device)
wide_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_matvec_mlx_scaled_wide.metal"))
gemv_pipe = metal_pipeline(wide_lib, "nvfp4_wides_b8_r2")
gemv1_pipe = metal_pipeline(wide_lib, "nvfp4_wide_b1_r2")
gemm_lib = metal_compile_source(device, read_file(NVFP4_DIR + "nvfp4_gemm_f32.metal"))
gemm_pipe = metal_pipeline(gemm_lib, "nvfp4_gemm_f32_m8")
w = metal_buffer(device, N * (K / 8) * 4)
s = metal_buffer(device, N * (K / 16))
x = metal_buffer(device, M * K * 4)
y_gemv = metal_buffer(device, M * N * 4)
y_gemm = metal_buffer(device, M * N * 4)
# Deterministic pseudo-random fill (LCG); nibbles use all 16 codes, scales a
# spread of E4M3 exponents (0x30..0x3f => 0.25..~1.9), activations +-1.
seed = 12345
i = 0
while i < N * (K / 8)
  seed = (seed * 1103515245 + 12345) & 0x7fffffff
  metal_buffer_write_i32(w, i, seed)
  i = i + 1
i = 0
while i < N * (K / 16) / 4
  seed = (seed * 1103515245 + 12345) & 0x7fffffff
  b0 = 0x30 + (seed & 0xf)
  b1 = 0x30 + ((seed >> 4) & 0xf)
  b2 = 0x30 + ((seed >> 8) & 0xf)
  b3 = 0x30 + ((seed >> 12) & 0xf)
  metal_buffer_write_i32(s, i, b0 | (b1 << 8) | (b2 << 16) | (b3 << 24))
  i = i + 1
i = 0
while i < M * K
  seed = (seed * 1103515245 + 12345) & 0x7fffffff
  metal_buffer_write_f32(x, i, (~0.0 + ((seed & 0xffff) - 32768)) / ~32768.0)
  i = i + 1
gscale = ~0.0123
-> run_gemv
  metal_batch_begin(queue)
  metal_dispatch_groups(queue, gemv_pipe, [w, s, x, y_gemv, K, N, gscale], (N + 3) / 4, 64)
  metal_batch_commit(queue)
-> run_gemv1
  metal_batch_begin(queue)
  metal_dispatch_groups(queue, gemv1_pipe, [w, s, x, y_gemv, K, N, gscale], (N + 3) / 4, 64)
  metal_batch_commit(queue)
-> run_gemm
  metal_batch_begin(queue)
  metal_dispatch_groups(queue, gemm_pipe, [w, s, x, y_gemm, K, N, gscale, M], (N + 31) / 32, 128)
  metal_batch_commit(queue)
run_gemv()
run_gemm()
max_abs = ~0.0
max_rel = ~0.0
sum_abs = ~0.0
i = 0
while i < M * N
  a = metal_buffer_read_f32(y_gemv, i)
  b = metal_buffer_read_f32(y_gemm, i)
  d = a - b
  if d < ~0.0 then d = ~0.0 - d
  aa = a < ~0.0 ? ~0.0 - a : a
  if d > max_abs then max_abs = d
  rel = d / (aa + ~1.0e-6)
  if rel > max_rel then max_rel = rel
  sum_abs = sum_abs + aa
  i = i + 1
<< "K=" + K.to_s + " N=" + N.to_s + " M=8: max_abs=" + max_abs.to_s + " max_rel=" + max_rel.to_s + " mean|y|=" + (sum_abs / (M * N)).to_s + " y[0]=" + metal_buffer_read_f32(y_gemv, 0).to_s + "/" + metal_buffer_read_f32(y_gemm, 0).to_s + " y[last]=" + metal_buffer_read_f32(y_gemv, M * N - 1).to_s + "/" + metal_buffer_read_f32(y_gemm, M * N - 1).to_s
# Isolated timing (same weight tile, cache-served -- valid only as an A/B
# between kernels doing the same weight traffic).
reps = 20
t_gemv = []
t_gemm = []
t_gemv1 = []
r = 0
while r < reps
  t0 = ccall("__w_clock_ms")
  run_gemv()
  t_gemv.push(ccall("__w_clock_ms") - t0)
  t0 = ccall("__w_clock_ms")
  run_gemm()
  t_gemm.push(ccall("__w_clock_ms") - t0)
  t0 = ccall("__w_clock_ms")
  run_gemv1()
  t_gemv1.push(ccall("__w_clock_ms") - t0)
  r = r + 1
<< "isolated median ms: gemv b1=" + t_gemv1.sort()[reps / 2].to_s + " gemv wides_b8_r2=" + t_gemv.sort()[reps / 2].to_s + " gemm_f32_m8=" + t_gemm.sort()[reps / 2].to_s
