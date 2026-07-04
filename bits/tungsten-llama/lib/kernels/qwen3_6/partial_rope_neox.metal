// Partial NeoX RoPE for qwen3.6 (head_dim=256, rotary_dim=64).
//
// Rotates only the first ROT_DIM dimensions of each head; remaining
// (head_dim - rot_dim) dims pass through untouched.
//
// NeoX layout: pair (i, i + rot_dim/2) for i in [0, rot_dim/2).
// cos_tab/sin_tab are length rot_dim/2 (32 for qwen3.6).
//
// Dispatch: n_heads * (rot_dim/2) threads.

#include <metal_stdlib>
using namespace metal;

kernel void partial_rope_neox(
  device float *x         [[buffer(0)]],
  device const float *cos_tab [[buffer(1)]],
  device const float *sin_tab [[buffer(2)]],
  constant int &head_dim     [[buffer(3)]],
  constant int &rot_dim_half [[buffer(4)]],
  constant int &n_heads      [[buffer(5)]],
  uint __tid [[thread_position_in_grid]]
) {
  int tid  = int(__tid);
  int head = tid / rot_dim_half;
  int pair = tid % rot_dim_half;
  if (head >= n_heads) return;
  int base = head * head_dim;
  int i_lo = base + pair;
  int i_hi = base + pair + rot_dim_half;
  float a = x[i_lo];
  float b = x[i_hi];
  float c = cos_tab[pair];
  float s = sin_tab[pair];
  x[i_lo] = a * c - b * s;
  x[i_hi] = a * s + b * c;
}
