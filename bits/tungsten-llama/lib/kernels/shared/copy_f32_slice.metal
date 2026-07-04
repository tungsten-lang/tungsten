#include <metal_stdlib>
using namespace metal;

kernel void copy_f32_slice(
  device const float *src [[buffer(0)]],
  device float *dst [[buffer(1)]],
  constant int &src_off [[buffer(2)]],
  constant int &n [[buffer(3)]],
  uint tid [[thread_position_in_grid]]
) {
  int i = int(tid);
  if (i < n) dst[i] = src[src_off + i];
}
