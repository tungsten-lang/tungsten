// Elementwise f32 → f16 conversion. Dispatch n threads.
#include <metal_stdlib>
using namespace metal;

kernel void f32_to_f16(
  device const float *src [[buffer(0)]],
  device half        *dst [[buffer(1)]],
  constant int &n [[buffer(2)]],
  uint tid [[thread_position_in_grid]]
) {
  int i = int(tid);
  if (i < n) dst[i] = half(src[i]);
}
