# MLX dispatch — Apple MLX (Metal-backed GPU compute) bridge.
#
# Thin wrappers over the runtime's `w_mlx_sgemm_nn` bridges (see
# `runtime/mlx_bridge.c`). The bridge wraps Tungsten f32 arrays as
# mlx_array views and dispatches mlx_matmul on the default GPU
# stream — no kernel JIT round-trip per call, no CPU↔GPU copy on
# Apple Silicon (unified memory).
#
# Usage:
#   a = f32_array(m * k)
#   b = f32_array(k * n)
#   c = f32_array(m * n)
#   fill_a(a); fill_b(b)
#   mlx_sgemm(a, b, c, m, n, k)        # C = A · B on GPU, result in C
#
# To skip the GPU→CPU readback (benchmark mode):
#   mlx_sgemm_no_readback(a, b, c, m, n, k)
#
# This bridge is OPT-IN — it compiles only when the build hooks
# `runtime/mlx_bridge.c` in via TUNGSTEN_C_INCLUDES, since linking the
# mlx-c dylib bloats every binary by ~180 MB. See
# `benchmarks/linalg/tungsten/build_mlx_bench.sh` for the canonical
# wiring.

# Single-precision GPU matmul: C = A · B (row-major).
# A is M×K, B is K×N, C is M×N. After the call, C contains the
# matmul result in CPU-addressable memory.
fn mlx_sgemm(a, b, c, m, n, k)
  ccall("w_mlx_sgemm_nn", a, b, c, m, n, k)

# Same as `mlx_sgemm` but skips the GPU→CPU memcpy. Useful for
# benchmark timing where you want pure matmul + dispatch cost,
# without the readback skewing the number. The mlx_array_eval
# still synchronizes, so the call returns only after the GPU
# kernel has completed.
fn mlx_sgemm_no_readback(a, b, c, m, n, k)
  ccall("w_mlx_sgemm_nn_no_readback", a, b, c, m, n, k)

# Schedules `iters` independent A·B matmuls and forces a single
# eval barrier at the end. Measures MLX's peak GPU throughput —
# no per-call sync, no readback. Used for "what's the headroom
# above the per-call-eval number" benchmarks.
fn mlx_sgemm_batch(a, b, c, m, n, k, iters)
  ccall("w_mlx_sgemm_batch", a, b, c, m, n, k, iters)

# Double-precision (f64) matmul. Note: Metal lacks native f64; MLX
# may fall back to CPU stream for this, so it's strictly slower than
# sgemm on Apple Silicon.
fn mlx_dgemm(a, b, c, m, n, k)
  ccall("w_mlx_dgemm_nn", a, b, c, m, n, k)

# Half-precision (f16) matmul. Inputs and outputs are f16 arrays
# (ebits = -16). Tungsten can't write f16 scalars directly — call
# a conversion kernel up-front to populate the inputs.
fn mlx_hgemm(a, b, c, m, n, k)
  ccall("w_mlx_hgemm_nn", a, b, c, m, n, k)

# bfloat16 matmul. Inputs and outputs are bf16 arrays (ebits = -116).
# As with f16, callers populate inputs via a conversion kernel.
fn mlx_bgemm(a, b, c, m, n, k)
  ccall("w_mlx_bgemm_nn", a, b, c, m, n, k)

# CPU-side f32 → bf16 array conversion. `src` is f32[], `dst` is bf16[].
# Use this to populate bf16 inputs from f32 fill code.
fn f32_to_bf16(src, dst, len)
  ccall("w_f32_to_bf16_array", src, dst, len)

# ---- Elementwise graph ops (f32 arrays; in/out same shape) ----
# These schedule MLX ops on the default GPU stream; call mlx_eval to sync.

fn mlx_add(a, b, out, n)
  ccall("w_mlx_add_f32", a, b, out, n)

fn mlx_mul(a, b, out, n)
  ccall("w_mlx_mul_f32", a, b, out, n)

fn mlx_sub(a, b, out, n)
  ccall("w_mlx_sub_f32", a, b, out, n)

fn mlx_div(a, b, out, n)
  ccall("w_mlx_div_f32", a, b, out, n)

fn mlx_exp(a, out, n)
  ccall("w_mlx_exp_f32", a, out, n)

fn mlx_log(a, out, n)
  ccall("w_mlx_log_f32", a, out, n)

fn mlx_sqrt(a, out, n)
  ccall("w_mlx_sqrt_f32", a, out, n)

fn mlx_tanh(a, out, n)
  ccall("w_mlx_tanh_f32", a, out, n)

# ---- Reductions / softmax ----
# sum/max over all elements (axis-all). Axis-selective variants later.
fn mlx_sum(a, n)
  ccall("w_mlx_sum_f32", a, n)

fn mlx_max(a, n)
  ccall("w_mlx_max_f32", a, n)

# Row-wise softmax for matrix stored row-major M×N in flat f32 array.
fn mlx_softmax_rows(a, out, m, n)
  ccall("w_mlx_softmax_rows_f32", a, out, m, n)

# ---- FFT (complex split: re/im f32 length n, power of 2) ----
fn mlx_fft(re, im, n, inverse)
  ccall("w_mlx_fft_f32", re, im, n, inverse)

# ---- RNG ----
fn mlx_random_uniform(out, n, lo, hi, seed)
  ccall("w_mlx_random_uniform_f32", out, n, lo, hi, seed)

fn mlx_random_normal(out, n, mean, std, seed)
  ccall("w_mlx_random_normal_f32", out, n, mean, std, seed)

# ---- Eval / compile control ----
# Force evaluation of pending graph (sync GPU).
fn mlx_eval
  ccall("w_mlx_eval")

# Optional: mark arrays as graph inputs for mlx_compile (when bridge supports).
fn mlx_compile_begin
  ccall("w_mlx_compile_begin")

fn mlx_compile_end
  ccall("w_mlx_compile_end")
