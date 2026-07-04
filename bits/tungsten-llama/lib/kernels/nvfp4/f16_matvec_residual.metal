// Single-token f16 matvec + residual. y[m] += w[m] · x.

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(32)]]
kernel void f16_matvec_residual(
  device const half  *__restrict__ w   [[buffer(0)]],
  device const float *__restrict__ x   [[buffer(1)]],
  device float       *__restrict__ y   [[buffer(2)]],
  constant int &k_dim [[buffer(3)]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  int m = int(__tg_id);
  int lane = int(__simd_lane);

  float partial = 0.0f;
  for (int i = lane; i < k_dim; i += 32) {
    partial += float(w[m * k_dim + i]) * x[i];
  }
  float total = simd_sum(partial);
  if (lane == 0) y[m] = y[m] + total;
}
