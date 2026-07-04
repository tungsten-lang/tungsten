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
