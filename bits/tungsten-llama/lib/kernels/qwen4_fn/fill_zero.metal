// Zero-fill a float buffer (state reset for the multi verify mode).
#include <metal_stdlib>
using namespace metal;

kernel void fill_zero(
  device float *b [[buffer(0)]],
  constant int &n [[buffer(1)]],
  uint __tid [[thread_position_in_grid]]
) {
  if (int(__tid) < n) b[__tid] = 0.0f;
}
