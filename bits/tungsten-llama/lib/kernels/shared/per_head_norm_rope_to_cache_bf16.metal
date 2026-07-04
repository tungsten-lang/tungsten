// per_head_norm_rope_to_cache writing bf16 KV cache. bf16 keeps f32-equivalent
// dynamic range (8-bit exponent) — safer than f16 for cache values that may
// spike on rare-token attention or long contexts. Storage is 2 bytes/elt
// (half the f32 cache BW). Conversion via bfloat() truncates the bottom 16
// bits of the f32 mantissa — single mask-and-shift on Apple Silicon.
#include <metal_stdlib>
using namespace metal;

kernel void per_head_norm_rope_to_cache_bf16(
  device float  *k_now [[buffer(0)]],
  device float  *w [[buffer(1)]],
  device float  *cos_tab [[buffer(2)]],
  device float  *sin_tab [[buffer(3)]],
  device bfloat *cache [[buffer(4)]],
  constant int &head_dim [[buffer(5)]],
  constant int &head_dim_half [[buffer(6)]],
  constant int &pos [[buffer(7)]],
  constant int &row_size [[buffer(8)]],
  constant float &inv_d [[buffer(9)]],
  constant float &eps [[buffer(10)]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __tg_id     [[threadgroup_position_in_grid]]
) {
  int h = int(__tg_id);
  int lane = int(__simd_lane);
  int base = h * head_dim;
  int cache_base = pos * row_size + base;
  float sum_sq = 0.0f;
  for (int i = lane; i < head_dim; i += 32) {
    float v = k_now[base + i];
    sum_sq += v * v;
  }
  float total = simd_sum(sum_sq);
  float rrms = 1.0f / sqrt(total * inv_d + eps);
  for (int p = lane; p < head_dim_half; p += 32) {
    float a = (k_now[base + p] * rrms) * w[p];
    float b = (k_now[base + p + head_dim_half] * rrms) * w[p + head_dim_half];
    float c = cos_tab[p];
    float s = sin_tab[p];
    cache[cache_base + p]                  = bfloat(a * c - b * s);
    cache[cache_base + p + head_dim_half]  = bfloat(a * s + b * c);
  }
}
