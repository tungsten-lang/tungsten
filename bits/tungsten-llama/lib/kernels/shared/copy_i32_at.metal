#include <metal_stdlib>
using namespace metal;

// Single-word device->device copy: dst[dst_idx] = src[src_idx].
// Used by the single-sync speculative round to move a chained draft's
// argmax token id straight into the next verify's token buffer, so the
// host never has to read it back mid-round (the MLX challenge's
// device-resident draft chain, +3.6% RETAINED on the 16K port ledger).
kernel void copy_i32_at(
  device const int *src [[buffer(0)]],
  device int *dst       [[buffer(1)]],
  constant int &src_idx [[buffer(2)]],
  constant int &dst_idx [[buffer(3)]],
  uint tid [[thread_position_in_grid]]) {
  if (tid == 0) dst[dst_idx] = src[src_idx];
}
