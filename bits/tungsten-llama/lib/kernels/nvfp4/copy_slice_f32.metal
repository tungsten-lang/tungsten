// Copy a contiguous f32 slice: dst[0..n] = src[src_off..src_off+n].
// Dispatch n threads.

#include <metal_stdlib>
using namespace metal;

kernel void copy_slice_f32(
  device const float *src [[buffer(0)]],
  device float       *dst [[buffer(1)]],
  constant int &src_off [[buffer(2)]],
  constant int &n       [[buffer(3)]],
  uint tid [[thread_position_in_grid]]
) {
  int i = int(tid);
  if (i < n) dst[i] = src[src_off + i];
}
