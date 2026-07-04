// kv_write writing into a bf16 cache. bf16(f32) is a top-16-bits truncation —
// no overflow check needed (range matches f32).
#include <metal_stdlib>
using namespace metal;

kernel void kv_write_bf16(
  device float  *k_now [[buffer(0)]],
  device bfloat *cache [[buffer(1)]],
  constant int &pos [[buffer(2)]],
  constant int &row_size [[buffer(3)]],
  uint __tid [[thread_position_in_grid]]
) {
  int i = int(__tid);
  if (i < row_size) {
    cache[pos * row_size + i] = bfloat(k_now[i]);
  }
}
