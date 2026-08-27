// Device-side f32 block copy with explicit source AND destination offsets:
//   dst[dst_off + i] = src[src_off + i]   for i in [0, n)
// copy_f32_slice only offsets the source and copy_pair_row only selects a
// source row, so neither can append a row into a larger device-resident
// table. Used by the tap dump to stack per-position hidden taps into one
// [pos, tap, hidden] buffer that is read back once at the end of the run.
#include <metal_stdlib>
using namespace metal;

kernel void copy_f32_at(
  device const float *src [[buffer(0)]],
  device float *dst       [[buffer(1)]],
  constant int &src_off   [[buffer(2)]],
  constant int &dst_off   [[buffer(3)]],
  constant int &n         [[buffer(4)]],
  uint tid [[thread_position_in_grid]]) {
  const int i = int(tid);
  if (i < n) dst[dst_off + i] = src[src_off + i];
}
