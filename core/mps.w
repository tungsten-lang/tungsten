# MPS dispatch — direct Apple Metal Performance Shaders matmul.
#
# Bypasses MLX. Calls Apple's MPSMatrixMultiplication via the
# runtime ObjC bridge (`runtime/mps_bridge.m`). Since MLX is a graph
# layer over MPS, this should match or beat MLX while avoiding its
# Python-array-semantics overhead.
#
# Opt-in build: link with mps_bridge.m + MetalPerformanceShaders.framework
# via TUNGSTEN_C_INCLUDES (see benchmarks/linalg/tungsten/build_mps_bench.sh).

# Single-precision matmul: C = A · B (row-major, no transpose).
# A is M×K, B is K×N, C is M×N.
# Uses zero-copy MTLBuffer wrapping of the WArrays' f32 storage.
fn mps_sgemm(a, b, c, m, n, k)
  ccall("w_mps_sgemm_nn", a, b, c, m, n, k)

# Batched: K chained matmuls (C₀=A·B, C_i = C_{i-1}·B for i≥1),
# single waitUntilCompleted at the end. Measures peak MPS throughput
# the same way matmul_mlx_batch measures peak MLX throughput.
# Requires M == N == K (square).
fn mps_sgemm_batch(a, b, c, m, n, k, iters)
  ccall("w_mps_sgemm_batch", a, b, c, m, n, k, iters)

# MPSGraph variants — newer API likely used by MLX internally.
# Should expose tf32-equivalent precision and tensor accelerators.
fn mpsg_sgemm(a, b, c, m, n, k)
  ccall("w_mpsg_sgemm_nn", a, b, c, m, n, k)

fn mpsg_sgemm_batch(a, b, c, m, n, k, iters)
  ccall("w_mpsg_sgemm_batch", a, b, c, m, n, k, iters)
