// Tungsten @gpu kernel output — do not edit by hand
#include <metal_stdlib>
using namespace metal;

kernel void per_head_norm_rope_to_cache(
  device float *k_now [[buffer(0)]],
  device float *w [[buffer(1)]],
  device float *cos_tab [[buffer(2)]],
  device float *sin_tab [[buffer(3)]],
  device float *cache [[buffer(4)]],
  constant int &head_dim [[buffer(5)]],
  constant int &head_dim_half [[buffer(6)]],
  constant int &pos [[buffer(7)]],
  constant int &row_size [[buffer(8)]],
  constant float &inv_d [[buffer(9)]],
  constant float &eps [[buffer(10)]],
  uint __tid [[thread_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id [[simdgroup_index_in_threadgroup]]
) {
  int h = int(__tg_id);
  int lane = int(__simd_lane);
  int base = (h * head_dim);
  int cache_base = ((pos * row_size) + base);
  float sum_sq = 0.0f;
  int i = lane;
  while ((i < head_dim)) {
    float v = k_now[(base + i)];
    sum_sq = (sum_sq + (v * v));
    i = (i + 32);
  }
  float total = simd_sum(sum_sq);
  float rrms = (1.0f / sqrt(((total * inv_d) + eps)));
  int p = lane;
  while ((p < head_dim_half)) {
    float a = ((k_now[(base + p)] * rrms) * w[p]);
    float b = ((k_now[((base + p) + head_dim_half)] * rrms) * w[(p + head_dim_half)]);
    float c = cos_tab[p];
    float s = sin_tab[p];
    cache[(cache_base + p)] = ((a * c) - (b * s));
    cache[((cache_base + p) + head_dim_half)] = ((a * s) + (b * c));
    p = (p + 32);
  }
}

