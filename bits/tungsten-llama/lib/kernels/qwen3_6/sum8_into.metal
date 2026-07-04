// Element-wise reduction: out[m] += y0[m] + y1[m] + … + y7[m].
// Used to fold 8 per-expert MoE outputs into the running residual stream
// after running the experts as 8 independent (potentially concurrent)
// command buffers.

#include <metal_stdlib>
using namespace metal;

kernel void sum8_into(
  device float       *out [[buffer(0)]],
  device const float *y0  [[buffer(1)]],
  device const float *y1  [[buffer(2)]],
  device const float *y2  [[buffer(3)]],
  device const float *y3  [[buffer(4)]],
  device const float *y4  [[buffer(5)]],
  device const float *y5  [[buffer(6)]],
  device const float *y6  [[buffer(7)]],
  device const float *y7  [[buffer(8)]],
  constant int       &n   [[buffer(9)]],
  uint __tid [[thread_position_in_grid]]
) {
  int tid = int(__tid);
  if (tid >= n) return;
  out[tid] = out[tid]
           + y0[tid] + y1[tid] + y2[tid] + y3[tid]
           + y4[tid] + y5[tid] + y6[tid] + y7[tid];
}
