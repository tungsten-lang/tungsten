// One-shot F16 → F32 conversion. Used at load time to widen Lightning's
// F16 RMSNorm / per-head-norm weights into the F32 layout our existing
// rms_norm and per_head_norm kernels expect. Trivial dispatch — runs
// once per weight tensor at startup.

#include <metal_stdlib>
using namespace metal;

kernel void f16_to_f32(
  device const half *__restrict__ src [[buffer(0)]],
  device float      *__restrict__ dst [[buffer(1)]],
  constant int &n [[buffer(2)]],
  uint tid [[thread_position_in_grid]]
) {
  if (int(tid) < n) {
    dst[tid] = float(src[tid]);
  }
}
