#include <metal_stdlib>
using namespace metal;
kernel void attn_scores_noop(
  device float *q [[buffer(0)]], device float *k_cache [[buffer(1)]],
  device float *scores [[buffer(2)]], constant int &head_dim [[buffer(3)]],
  constant int &n_kv_heads [[buffer(4)]], constant int &group_size [[buffer(5)]],
  constant int &n_pos [[buffer(6)]], constant float &scale [[buffer(7)]],
  uint tid [[thread_position_in_grid]]
) { scores[tid] = 0.0f; }
