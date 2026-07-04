// Single-token f16 matvec. Reads pre-dequanted f16 weights — no inline dequant.
// 1 TG per output row, 32 lanes. Each lane processes K_DIM/32 inputs.

#include <metal_stdlib>
using namespace metal;

[[max_total_threads_per_threadgroup(32)]]
kernel void f16_matvec(
  device const half  *__restrict__ w   [[buffer(0)]],   // [N_ROWS × K_DIM] half row-major
  device const float *__restrict__ x   [[buffer(1)]],   // [K_DIM] f32
  device float       *__restrict__ y   [[buffer(2)]],   // [N_ROWS] f32
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
  if (lane == 0) y[m] = total;
}
