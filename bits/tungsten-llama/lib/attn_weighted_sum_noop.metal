#include <metal_stdlib>
using namespace metal;
kernel void attn_weighted_sum_noop(
  device float *scores [[buffer(0)]], device float *v_cache [[buffer(1)]],
  device float *out [[buffer(2)]], constant int &head_dim [[buffer(3)]],
  constant int &n_kv_heads [[buffer(4)]], constant int &group_size [[buffer(5)]],
  constant int &n_pos [[buffer(6)]],
  uint tid [[thread_position_in_grid]]
) { out[tid] = 0.0f; }
