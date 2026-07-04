// Gather ONE row of a BF16 embedding table into out[hidden].
// ollama's MLX qwen3.6 export stores embed_tokens.weight as BF16
// [vocab, hidden] (no nvfp4 packing / scales), so the per-token embedding
// is a plain row copy with a bf16->f32 widen.
//
// bf16->f32 is the top-16-bits-of-f32 layout: float = (bits << 16).
//
// Dispatch: `hidden` threads. Each writes one f32 output.

#include <metal_stdlib>
using namespace metal;

static inline float bf16_to_f32(ushort b) {
  return as_type<float>(uint(b) << 16);
}

kernel void bf16_embedding_lookup(
  device const ushort *__restrict__ w   [[buffer(0)]],   // [vocab, hidden] bf16
  device float        *__restrict__ out [[buffer(1)]],   // [hidden] f32
  constant int &token_id [[buffer(2)]],
  constant int &hidden   [[buffer(3)]],
  uint tid [[thread_position_in_grid]]
) {
  int i = int(tid);
  if (i < hidden) {
    out[i] = bf16_to_f32(w[token_id * hidden + i]);
  }
}
