// Two-token decode helpers for Qwen3.5/3.6/3.8 MTP-1 verification.
// Dense NVFP4 projections live in nvfp4_matvec_mlx_scaled_pair.metal; this
// file covers the small layout, attention, convolution, and recurrent ops.

#include <metal_stdlib>
#include <metal_simdgroup>
using namespace metal;

static inline float bf16_pair_to_f32(ushort b) {
  return as_type<float>(uint(b) << 16);
}

kernel void bf16_embedding_lookup_pair(
  device const ushort *weight [[buffer(0)]],
  device float *out           [[buffer(1)]],
  device const int *token_ids [[buffer(2)]],
  constant int &hidden        [[buffer(3)]],
  uint tid [[thread_position_in_grid]]) {
  const int total = 2 * hidden;
  if (int(tid) >= total) return;
  const int token = int(tid) / hidden;
  const int col = int(tid) - token * hidden;
  out[tid] = bf16_pair_to_f32(weight[token_ids[token] * hidden + col]);
}

kernel void bf16_matvec_pair(
  device const ushort *weight [[buffer(0)]],
  device const float *x       [[buffer(1)]],
  device float *y             [[buffer(2)]],
  constant int &k_dim         [[buffer(3)]],
  constant int &n_rows        [[buffer(4)]],
  uint row [[threadgroup_position_in_grid]],
  uint lane [[thread_index_in_simdgroup]]) {
  if (int(row) >= n_rows) return;
  float a0 = 0.0f, a1 = 0.0f;
  for (int k = int(lane); k < k_dim; k += 32) {
    const float w = bf16_pair_to_f32(weight[int(row) * k_dim + k]);
    a0 += w * x[k];
    a1 += w * x[k_dim + k];
  }
  a0 = simd_sum(a0);
  a1 = simd_sum(a1);
  if (lane == 0) {
    y[row] = a0;
    y[n_rows + row] = a1;
  }
}

kernel void concat_f32(
  device const float *left  [[buffer(0)]],
  device const float *right [[buffer(1)]],
  device float *out         [[buffer(2)]],
  constant int &n           [[buffer(3)]],
  uint tid [[thread_position_in_grid]]) {
  if (int(tid) >= n) return;
  out[tid] = left[tid];
  out[n + tid] = right[tid];
}

kernel void copy_pair_row(
  device const float *src [[buffer(0)]],
  device float *dst       [[buffer(1)]],
  constant int &row       [[buffer(2)]],
  constant int &n         [[buffer(3)]],
  uint tid [[thread_position_in_grid]]) {
  if (int(tid) < n) dst[tid] = src[row * n + int(tid)];
}

kernel void copy_f32_slice_pair(
  device const float *src [[buffer(0)]],
  device float *dst       [[buffer(1)]],
  constant int &src_stride [[buffer(2)]],
  constant int &dst_stride [[buffer(3)]],
  constant int &src_offset [[buffer(4)]],
  constant int &length     [[buffer(5)]],
  uint tid [[thread_position_in_grid]]) {
  const int total = 2 * length;
  if (int(tid) >= total) return;
  const int token = int(tid) / length;
  const int i = int(tid) - token * length;
  dst[token * dst_stride + i] = src[token * src_stride + src_offset + i];
}

kernel void split_q_gate_pair(
  device const float *q_full [[buffer(0)]],
  device float *queries      [[buffer(1)]],
  device float *gate         [[buffer(2)]],
  constant int &n_heads      [[buffer(3)]],
  constant int &head_dim     [[buffer(4)]],
  uint tid [[thread_position_in_grid]]) {
  const int row = n_heads * head_dim;
  const int total = 2 * row;
  if (int(tid) >= total) return;
  const int token = int(tid) / row;
  const int local = int(tid) - token * row;
  const int head = local / head_dim;
  const int i = local - head * head_dim;
  const int qbase = token * row * 2 + head * head_dim * 2;
  queries[token * row + local] = q_full[qbase + i];
  gate[token * row + local] = q_full[qbase + head_dim + i];
}

[[max_total_threads_per_threadgroup(32)]]
kernel void per_head_norm_partial_rope_pair(
  device float *x           [[buffer(0)]],
  device const float *w     [[buffer(1)]],
  device const float *cos_t [[buffer(2)]],
  device const float *sin_t [[buffer(3)]],
  constant int &head_dim    [[buffer(4)]],
  constant int &rot_half    [[buffer(5)]],
  constant int &n_heads     [[buffer(6)]],
  constant float &inv_d     [[buffer(7)]],
  constant float &eps       [[buffer(8)]],
  uint tg [[threadgroup_position_in_grid]],
  uint lane [[thread_index_in_simdgroup]]) {
  const int token = int(tg) / n_heads;
  const int head = int(tg) - token * n_heads;
  if (token >= 2) return;
  const int base = (token * n_heads + head) * head_dim;
  float ss = 0.0f;
  for (int i = int(lane); i < head_dim; i += 32) {
    const float v = x[base + i];
    ss += v * v;
  }
  const float rrms = rsqrt(simd_sum(ss) * inv_d + eps);
  for (int i = int(lane); i < head_dim; i += 32) {
    x[base + i] *= rrms * w[i];
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int p = int(lane); p < rot_half; p += 32) {
    const int lo = base + p;
    const int hi = lo + rot_half;
    const float a = x[lo], b = x[hi];
    const float c = cos_t[token * rot_half + p];
    const float s = sin_t[token * rot_half + p];
    x[lo] = a * c - b * s;
    x[hi] = a * s + b * c;
  }
}

kernel void kv_write_pair(
  device const float *k_now [[buffer(0)]],
  device const float *v_now [[buffer(1)]],
  device float *k_cache     [[buffer(2)]],
  device float *v_cache     [[buffer(3)]],
  constant int &pos_start   [[buffer(4)]],
  constant int &kv_dim      [[buffer(5)]],
  uint tid [[thread_position_in_grid]]) {
  const int total = 2 * kv_dim;
  if (int(tid) >= total) return;
  const int token = int(tid) / kv_dim;
  const int i = int(tid) - token * kv_dim;
  const int cache_i = (pos_start + token) * kv_dim + i;
  k_cache[cache_i] = k_now[token * kv_dim + i];
  v_cache[cache_i] = v_now[token * kv_dim + i];
}

constant int PAIR_MAX_DECODE_POS = 128;

[[max_total_threads_per_threadgroup(256)]]
kernel void sdpa_decode_pair_hd256(
  device const float *q       [[buffer(0)]],
  device const float *k_cache [[buffer(1)]],
  device const float *v_cache [[buffer(2)]],
  device float *out           [[buffer(3)]],
  constant int &gqa_factor    [[buffer(4)]],
  constant int &pos_start     [[buffer(5)]],
  constant int &n_heads       [[buffer(6)]],
  constant int &kv_dim        [[buffer(7)]],
  constant float &scale       [[buffer(8)]],
  uint tg [[threadgroup_position_in_grid]],
  uint tid [[thread_position_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]],
  uint simd [[simdgroup_index_in_threadgroup]]) {
  threadgroup float partial[8];
  threadgroup float scores[PAIR_MAX_DECODE_POS];
  const int token = int(tg) / n_heads;
  const int q_head = int(tg) - token * n_heads;
  if (token >= 2) return;
  const int kv_head = q_head / gqa_factor;
  const int q_off = (token * n_heads + q_head) * 256;
  const int kv_base = kv_head * 256;
  const int usable = min(pos_start + token + 1, PAIR_MAX_DECODE_POS);

  for (int p = 0; p < usable; ++p) {
    const float part = q[q_off + int(tid)] *
      k_cache[kv_base + p * kv_dim + int(tid)];
    const float sg = simd_sum(part);
    if (lane == 0) partial[simd] = sg;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (simd == 0) {
      const float v = lane < 8 ? partial[lane] : 0.0f;
      const float total = simd_sum(v);
      if (lane == 0) scores[p] = total * scale;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
  }
  if (tid == 0) {
    float mx = -INFINITY;
    for (int p = 0; p < usable; ++p) mx = max(mx, scores[p]);
    float denom = 0.0f;
    for (int p = 0; p < usable; ++p) {
      const float e = fast::exp(scores[p] - mx);
      scores[p] = e;
      denom += e;
    }
    const float inv = denom == 0.0f ? 0.0f : 1.0f / denom;
    for (int p = 0; p < usable; ++p) scores[p] *= inv;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float result = 0.0f;
  for (int p = 0; p < usable; ++p) {
    result += scores[p] * v_cache[kv_base + p * kv_dim + int(tid)];
  }
  out[q_off + int(tid)] = result;
}

kernel void conv1d_depthwise_pair(
  device const float *weight [[buffer(0)]],
  device const float *state  [[buffer(1)]],
  device const float *x      [[buffer(2)]],
  device float *out          [[buffer(3)]],
  device float *state_mid    [[buffer(4)]],
  device float *state_out    [[buffer(5)]],
  constant int &channels     [[buffer(6)]],
  uint tid [[thread_position_in_grid]]) {
  const int c = int(tid);
  if (c >= channels) return;
  const float s0 = state[c];
  const float s1 = state[channels + c];
  const float s2 = state[2 * channels + c];
  const float x0 = x[c];
  const float x1 = x[channels + c];
  const float w0 = weight[4 * c], w1 = weight[4 * c + 1];
  const float w2 = weight[4 * c + 2], w3 = weight[4 * c + 3];
  const float z0 = w0 * s0 + w1 * s1 + w2 * s2 + w3 * x0;
  const float z1 = w0 * s1 + w1 * s2 + w2 * x0 + w3 * x1;
  out[c] = z0 / (1.0f + exp(-z0));
  out[channels + c] = z1 / (1.0f + exp(-z1));
  state_mid[c] = s1;
  state_mid[channels + c] = s2;
  state_mid[2 * channels + c] = x0;
  state_out[c] = s2;
  state_out[channels + c] = x0;
  state_out[2 * channels + c] = x1;
}

[[max_total_threads_per_threadgroup(128)]]
kernel void gated_delta_pair(
  device const float *q        [[buffer(0)]],
  device const float *k        [[buffer(1)]],
  device const float *v        [[buffer(2)]],
  device const float *g_in     [[buffer(3)]],
  device const float *beta_in  [[buffer(4)]],
  device const float *state_in [[buffer(5)]],
  device float *y              [[buffer(6)]],
  device float *state_mid      [[buffer(7)]],
  device float *state_out      [[buffer(8)]],
  constant int &Hk [[buffer(9)]],
  constant int &Hv [[buffer(10)]],
  constant int &Dk [[buffer(11)]],
  constant int &Dv [[buffer(12)]],
  uint3 tg_pos [[threadgroup_position_in_grid]],
  uint3 t_in_tg [[thread_position_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]]) {
  const int hv = int(tg_pos.z);
  const int dv = int(tg_pos.y) * 4 + int(t_in_tg.y);
  if (hv >= Hv || dv >= Dv) return;
  const int hk = hv / (Hv / Hk);
  const int per_lane = Dk / 32;
  const int dk0 = int(lane) * per_lane;
  const int state_off = (hv * Dv + dv) * Dk;
  float state[4];
  for (int i = 0; i < per_lane; ++i) state[i] = state_in[state_off + dk0 + i];

  for (int token = 0; token < 2; ++token) {
    const int q_off = (token * Hk + hk) * Dk;
    const int v_off = (token * Hv + hv) * Dv + dv;
    const float decay = g_in[token * Hv + hv];
    const float beta = beta_in[token * Hv + hv];
    for (int i = 0; i < per_lane; ++i) state[i] *= decay;
    float mem = 0.0f;
    for (int i = 0; i < per_lane; ++i) mem += state[i] * k[q_off + dk0 + i];
    mem = simd_sum(mem);
    const float delta = (v[v_off] - mem) * beta;
    for (int i = 0; i < per_lane; ++i) {
      state[i] += k[q_off + dk0 + i] * delta;
    }
    float acc = 0.0f;
    for (int i = 0; i < per_lane; ++i) acc += state[i] * q[q_off + dk0 + i];
    acc = simd_sum(acc);
    if (lane == 0) y[v_off] = acc;
    device float *state_dst = token == 0 ? state_mid : state_out;
    for (int i = 0; i < per_lane; ++i) state_dst[state_off + dk0 + i] = state[i];
  }
}
