// Same as bf16_embedding_lookup, but the token id is read from a device
// buffer slot instead of a host-supplied scalar. Lets a chained speculative
// draft consume the PREVIOUS draft's argmax without a host round-trip
// (depth-3 device-resident draft chain).
#include <metal_stdlib>
using namespace metal;

static inline float bf16_to_f32(ushort b) {
  return as_type<float>(uint(b) << 16);
}

kernel void bf16_embedding_lookup_buf(
  device const ushort *__restrict__ w   [[buffer(0)]],   // [vocab, hidden] bf16
  device float        *__restrict__ out [[buffer(1)]],   // [hidden] f32
  device const int    *__restrict__ tok [[buffer(2)]],   // token id buffer
  constant int &idx    [[buffer(3)]],
  constant int &hidden [[buffer(4)]],
  uint tid [[thread_position_in_grid]]
) {
  int i = int(tid);
  if (i < hidden) {
    out[i] = bf16_to_f32(w[tok[idx] * hidden + i]);
  }
}
