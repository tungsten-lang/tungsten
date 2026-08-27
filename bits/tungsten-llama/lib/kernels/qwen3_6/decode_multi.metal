// Multi-token (n_tok <= MULTI_MAX_TOK = 8) decode helpers for Qwen3.8 block
// verification: the target verifies an anchor plus up to seven drafted
// tokens in ONE causal pass (DFlash2 block 8), and the same kernels serve any
// narrower block, so the width is a runtime argument rather than a kernel
// per width. Derived from decode_quad.metal; the per-token arithmetic and
// summation order of every kernel here is exactly the quad kernel's, so a
// width-n pass is bit-identical to the pair/triplet/quad paths and to n
// serial steps.
//
// Recurrent state: the quad kernels publish one interior snapshot per accept
// boundary (3 MB per gated-delta layer per token). At width 8 that is seven
// extra 3 MB writes per layer, ~1 GB per verify, so this file does the
// DFlash-style "tape replay" instead: the verify writes ONLY the final state
// (the input state stays intact in the other ping-pong buffer) and a
// rollback re-runs the same register loop for the accepted prefix from that
// input state. The replay loop IS the verify loop, so the rolled-back state
// is bit-identical to the state the verify held after that token.

#include <metal_stdlib>
using namespace metal;

constant int MULTI_MAX_TOK = 8;
constant int MULTI_MAX_DECODE_POS = 640;

static inline float bf16_multi_to_f32(ushort b) {
  return as_type<float>(uint(b) << 16);
}

kernel void bf16_embedding_lookup_multi(
  device const ushort *weight [[buffer(0)]],
  device float *out [[buffer(1)]],
  device const int *token_ids [[buffer(2)]],
  constant int &hidden [[buffer(3)]],
  constant int &n_tok [[buffer(4)]],
  uint tid [[thread_position_in_grid]]) {
  const int total = n_tok * hidden;
  if (int(tid) >= total) return;
  const int token = int(tid) / hidden;
  const int col = int(tid) - token * hidden;
  out[tid] = bf16_multi_to_f32(weight[token_ids[token] * hidden + col]);
}

// y[b * n_rows + row] = dot(weight[row], x[b]) for b < n_tok. Small bf16
// projections only (the GDN a/b heads, 48 rows); the dense NVFP4 projections
// use the wide cross-row kernels.
kernel void bf16_matvec_multi(
  device const ushort *weight [[buffer(0)]],
  device const float *x [[buffer(1)]],
  device float *y [[buffer(2)]],
  constant int &k_dim [[buffer(3)]],
  constant int &n_rows [[buffer(4)]],
  constant int &n_tok [[buffer(5)]],
  uint row [[threadgroup_position_in_grid]],
  uint lane [[thread_index_in_simdgroup]]) {
  if (int(row) >= n_rows) return;
  // Any n_tok: process the activation rows in chunks of MULTI_MAX_TOK so the
  // accumulators stay in registers (prefill runs this at 64 rows).
  for (int b0 = 0; b0 < n_tok; b0 += MULTI_MAX_TOK) {
    const int nb = min(n_tok - b0, MULTI_MAX_TOK);
    float acc[MULTI_MAX_TOK];
    for (int b = 0; b < MULTI_MAX_TOK; ++b) acc[b] = 0.0f;
    for (int k = int(lane); k < k_dim; k += 32) {
      const float w = bf16_multi_to_f32(weight[int(row) * k_dim + k]);
      for (int b = 0; b < nb; ++b) acc[b] += w * x[(b0 + b) * k_dim + k];
    }
    for (int b = 0; b < nb; ++b) {
      const float total = simd_sum(acc[b]);
      if (lane == 0) y[(b0 + b) * n_rows + row] = total;
    }
  }
}

kernel void copy_f32_slice_multi(
  device const float *src [[buffer(0)]], device float *dst [[buffer(1)]],
  constant int &src_stride [[buffer(2)]],
  constant int &dst_stride [[buffer(3)]],
  constant int &src_offset [[buffer(4)]],
  constant int &length [[buffer(5)]],
  constant int &n_tok [[buffer(6)]],
  uint tid [[thread_position_in_grid]]) {
  const int total = n_tok * length;
  if (int(tid) >= total) return;
  const int token = int(tid) / length;
  const int i = int(tid) - token * length;
  dst[token * dst_stride + i] = src[token * src_stride + src_offset + i];
}

// Stack one hidden tap for n_tok rows into a [row, tap, hidden] table:
//   dst[(row_offset + t) * n_taps * hidden + tap * hidden + i] = src[t * hidden + i]
// This is the DFlash2 drafter's conditioning input (five taps per position).
kernel void copy_taps_multi(
  device const float *src [[buffer(0)]], device float *dst [[buffer(1)]],
  constant int &hidden [[buffer(2)]],
  constant int &n_taps [[buffer(3)]],
  constant int &tap [[buffer(4)]],
  constant int &row_offset [[buffer(5)]],
  constant int &n_tok [[buffer(6)]],
  uint tid [[thread_position_in_grid]]) {
  const int total = n_tok * hidden;
  if (int(tid) >= total) return;
  const int token = int(tid) / hidden;
  const int i = int(tid) - token * hidden;
  dst[((row_offset + token) * n_taps + tap) * hidden + i] = src[token * hidden + i];
}

kernel void split_q_gate_multi(
  device const float *q_full [[buffer(0)]],
  device float *queries [[buffer(1)]], device float *gate [[buffer(2)]],
  constant int &n_heads [[buffer(3)]], constant int &head_dim [[buffer(4)]],
  constant int &n_tok [[buffer(5)]],
  uint tid [[thread_position_in_grid]]) {
  const int row = n_heads * head_dim;
  const int total = n_tok * row;
  if (int(tid) >= total) return;
  const int token = int(tid) / row;
  const int local = int(tid) - token * row;
  const int head = local / head_dim;
  const int i = local - head * head_dim;
  const int qbase = token * row * 2 + head * head_dim * 2;
  queries[token * row + local] = q_full[qbase + i];
  gate[token * row + local] = q_full[qbase + head_dim + i];
}

// One threadgroup (one simdgroup) per (token, head); cos/sin tables carry
// rot_half entries per token. Dispatch n_tok * n_heads groups of 32.
[[max_total_threads_per_threadgroup(32)]]
kernel void per_head_norm_partial_rope_multi(
  device float *x [[buffer(0)]], device const float *w [[buffer(1)]],
  device const float *cos_t [[buffer(2)]], device const float *sin_t [[buffer(3)]],
  constant int &head_dim [[buffer(4)]], constant int &rot_half [[buffer(5)]],
  constant int &n_heads [[buffer(6)]], constant float &inv_d [[buffer(7)]],
  constant float &eps [[buffer(8)]],
  constant int &n_tok [[buffer(9)]],
  uint tg [[threadgroup_position_in_grid]],
  uint lane [[thread_index_in_simdgroup]]) {
  const int token = int(tg) / n_heads;
  const int head = int(tg) - token * n_heads;
  if (token >= n_tok) return;
  const int base = (token * n_heads + head) * head_dim;
  float ss = 0.0f;
  for (int i = int(lane); i < head_dim; i += 32) {
    const float v = x[base + i]; ss += v * v;
  }
  const float rrms = rsqrt(simd_sum(ss) * inv_d + eps);
  for (int i = int(lane); i < head_dim; i += 32) x[base + i] *= rrms * w[i];
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int p = int(lane); p < rot_half; p += 32) {
    const int lo = base + p, hi = lo + rot_half;
    const float a = x[lo], b = x[hi];
    const float c = cos_t[token * rot_half + p];
    const float s = sin_t[token * rot_half + p];
    x[lo] = a * c - b * s; x[hi] = a * s + b * c;
  }
}

kernel void kv_write_multi(
  device const float *k_now [[buffer(0)]], device const float *v_now [[buffer(1)]],
  device float *k_cache [[buffer(2)]], device float *v_cache [[buffer(3)]],
  constant int &pos_start [[buffer(4)]], constant int &kv_dim [[buffer(5)]],
  constant int &n_tok [[buffer(6)]],
  uint tid [[thread_position_in_grid]]) {
  const int total = n_tok * kv_dim;
  if (int(tid) >= total) return;
  const int token = int(tid) / kv_dim;
  const int i = int(tid) - token * kv_dim;
  const int cache_i = (pos_start + token) * kv_dim + i;
  k_cache[cache_i] = k_now[token * kv_dim + i];
  v_cache[cache_i] = v_now[token * kv_dim + i];
}

// Token t attends to cache positions [0, pos_start + t]. Dispatch
// n_tok * n_heads groups of 256 threads (one thread per output dim).
[[max_total_threads_per_threadgroup(256)]]
kernel void sdpa_decode_multi_hd256(
  device const float *q [[buffer(0)]], device const float *k_cache [[buffer(1)]],
  device const float *v_cache [[buffer(2)]], device float *out [[buffer(3)]],
  constant int &gqa_factor [[buffer(4)]], constant int &pos_start [[buffer(5)]],
  constant int &n_heads [[buffer(6)]], constant int &kv_dim [[buffer(7)]],
  constant float &scale [[buffer(8)]],
  constant int &n_tok [[buffer(9)]],
  uint tg [[threadgroup_position_in_grid]],
  uint tid [[thread_position_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]],
  uint simd [[simdgroup_index_in_threadgroup]]) {
  threadgroup float partial[8];
  threadgroup float scores[MULTI_MAX_DECODE_POS];
  const int token = int(tg) / n_heads;
  const int q_head = int(tg) - token * n_heads;
  if (token >= n_tok) return;
  const int kv_head = q_head / gqa_factor;
  const int q_off = (token * n_heads + q_head) * 256;
  const int kv_base = kv_head * 256;
  const int usable = min(pos_start + token + 1, MULTI_MAX_DECODE_POS);
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
      const float e = fast::exp(scores[p] - mx); scores[p] = e; denom += e;
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

// Depthwise causal conv, kernel size 4, over n_tok new tokens. state holds
// the 3 inputs preceding the batch; state_out receives the last 3 inputs of
// the whole sequence (what a full accept needs). Interior states are NOT
// published: conv_state_replay rebuilds any prefix's state from the same
// inputs, which are still in the qkv scratch when the accept walk runs.
kernel void conv1d_depthwise_multi(
  device const float *weight [[buffer(0)]], device const float *state [[buffer(1)]],
  device const float *x [[buffer(2)]], device float *out [[buffer(3)]],
  device float *state_out [[buffer(4)]],
  constant int &channels [[buffer(5)]],
  constant int &n_tok [[buffer(6)]],
  uint tid [[thread_position_in_grid]]) {
  const int c = int(tid); if (c >= channels) return;
  float s0 = state[c], s1 = state[channels + c], s2 = state[2 * channels + c];
  const float w0 = weight[4 * c], w1 = weight[4 * c + 1];
  const float w2 = weight[4 * c + 2], w3 = weight[4 * c + 3];
  for (int t = 0; t < n_tok; ++t) {
    const float xt = x[t * channels + c];
    const float z = w0 * s0 + w1 * s1 + w2 * s2 + w3 * xt;
    out[t * channels + c] = z / (1.0f + exp(-z));
    s0 = s1; s1 = s2; s2 = xt;
  }
  state_out[c] = s0; state_out[channels + c] = s1; state_out[2 * channels + c] = s2;
}

// state_out = last three of [state, x_0 .. x_{n_keep-1}]: the conv state after
// committing n_keep of the verified tokens.
kernel void conv_state_replay(
  device const float *state [[buffer(0)]], device const float *x [[buffer(1)]],
  device float *state_out [[buffer(2)]],
  constant int &channels [[buffer(3)]],
  constant int &n_keep [[buffer(4)]],
  uint tid [[thread_position_in_grid]]) {
  const int c = int(tid); if (c >= channels) return;
  float s0 = state[c], s1 = state[channels + c], s2 = state[2 * channels + c];
  for (int t = 0; t < n_keep; ++t) {
    const float xt = x[t * channels + c];
    s0 = s1; s1 = s2; s2 = xt;
  }
  state_out[c] = s0; state_out[channels + c] = s1; state_out[2 * channels + c] = s2;
}

// Serial token recurrence in registers, exactly decode_quad's loop, for
// n_tok tokens. Writes y for every token and ONLY the final state. The same
// kernel performs the rollback replay: dispatch it again with n_tok =
// accepted + 1 from the untouched input state (y is then scratch).
[[max_total_threads_per_threadgroup(128)]]
kernel void gated_delta_multi(
  device const float *q [[buffer(0)]], device const float *k [[buffer(1)]],
  device const float *v [[buffer(2)]], device const float *g_in [[buffer(3)]],
  device const float *beta_in [[buffer(4)]], device const float *state_in [[buffer(5)]],
  device float *y [[buffer(6)]], device float *state_out [[buffer(7)]],
  constant int &Hk [[buffer(8)]], constant int &Hv [[buffer(9)]],
  constant int &Dk [[buffer(10)]], constant int &Dv [[buffer(11)]],
  constant int &n_tok [[buffer(12)]],
  uint3 tg_pos [[threadgroup_position_in_grid]],
  uint3 t_in_tg [[thread_position_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]]) {
  const int hv = int(tg_pos.z), dv = int(tg_pos.y) * 4 + int(t_in_tg.y);
  if (hv >= Hv || dv >= Dv) return;
  const int hk = hv / (Hv / Hk), per_lane = Dk / 32, dk0 = int(lane) * per_lane;
  const int state_off = (hv * Dv + dv) * Dk;
  float state[4];
  for (int i = 0; i < per_lane; ++i) state[i] = state_in[state_off + dk0 + i];
  for (int token = 0; token < n_tok; ++token) {
    const int q_off = (token * Hk + hk) * Dk;
    const int v_off = (token * Hv + hv) * Dv + dv;
    const float decay = g_in[token * Hv + hv], beta = beta_in[token * Hv + hv];
    for (int i = 0; i < per_lane; ++i) state[i] *= decay;
    float mem = 0.0f;
    for (int i = 0; i < per_lane; ++i) mem += state[i] * k[q_off + dk0 + i];
    mem = simd_sum(mem);
    const float delta = (v[v_off] - mem) * beta;
    for (int i = 0; i < per_lane; ++i) state[i] += k[q_off + dk0 + i] * delta;
    float acc = 0.0f;
    for (int i = 0; i < per_lane; ++i) acc += state[i] * q[q_off + dk0 + i];
    acc = simd_sum(acc);
    if (lane == 0) y[v_off] = acc;
  }
  for (int i = 0; i < per_lane; ++i) state_out[state_off + dk0 + i] = state[i];
}
