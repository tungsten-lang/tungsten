// Batched f32→bf16 V cache writer for long prefill.
// Reads BATCH_FC × ROW_FC f32 values, writes bf16 into cache at row [0..BATCH-1].
//
// This is the prefill counterpart to v_write_decode_batch_fc, but writes the
// first BATCH rows starting at row 0 (prefill always starts fresh) instead of
// at pos_start. Used after a v_proj matmul writes f32 into a temporary buffer.
#include <metal_stdlib>
using namespace metal;

constant int BATCH_FC [[function_constant(0)]];
constant int ROW_FC   [[function_constant(1)]];

kernel void v_write_batch_bf16_fc(
  device const float *v_now [[buffer(0)]],
  device bfloat      *cache [[buffer(1)]],
  uint __tid [[thread_position_in_grid]]
) {
  int total = BATCH_FC * ROW_FC;
  int i = int(__tid);
  if (i < total) {
    cache[i] = bfloat(v_now[i]);
  }
}
