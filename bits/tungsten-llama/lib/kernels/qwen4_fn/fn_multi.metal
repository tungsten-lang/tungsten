// Width-n (runtime batch) variants of the Qwen3.8-Flash-Next-specific ops,
// for MTP width-n verify and multi-stream "aggregate" decode. The GDN and
// attention chains reuse the 27B decode_multi.metal family (identical head
// geometry); these cover what flash-next adds: hyper-connections, the
// 512-expert MoE, and the batched NVFP4 expert gather.
//
// Batch layout convention: token-major — every per-token tensor T of width W
// becomes [n, W] with token t at offset t*W.

#include <metal_stdlib>
#include <metal_simdgroup_matrix>
using namespace metal;

static inline half nvfp4_decode_half(uint nibble) {
  half mag = as_type<half>(ushort((nibble & 7) << 9)) * 16384.0h;
  return (nibble & 8) ? -mag : mag;
}

static inline half e4m3_decode_half(uint b) {
  return as_type<half>(ushort((b & 127) << 7)) * 256.0h;
}

static inline uint load_u32_le(device const uchar *p) {
  return (uint)p[0] | ((uint)p[1] << 8) | ((uint)p[2] << 16) | ((uint)p[3] << 24);
}

static inline float load_f32_le(device const uchar *p) {
  return as_type<float>(load_u32_le(p));
}

// Grouped (1+w) RMSNorm over [n, groups*d]; weight [groups*d] shared across
// tokens. Dispatch: n*groups TGs x 256.
[[max_total_threads_per_threadgroup(256)]]
kernel void grouped_rms_norm_multi(
  device const float *__restrict__ x [[buffer(0)]],   // [n, groups*d]
  device const float *__restrict__ w [[buffer(1)]],   // [groups*d], includes +1
  device       float *__restrict__ y [[buffer(2)]],   // [n, groups*d]
  constant int   &d      [[buffer(3)]],
  constant int   &groups [[buffer(4)]],
  constant float &eps    [[buffer(5)]],
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id   [[simdgroup_index_in_threadgroup]],
  uint __tg_size   [[threads_per_threadgroup]]
) {
  int g = int(__tg_id) % groups;
  int t = int(__tg_id) / groups;
  int base = t * groups * d + g * d;
  int wbase = g * d;
  float sum_sq = 0.0f;
  for (int i = int(__tid_in_tg); i < d; i += int(__tg_size)) {
    float v = x[base + i];
    sum_sq += v * v;
  }
  threadgroup float scratch[32];
  float sm = simd_sum(sum_sq);
  if (__simd_lane == 0) scratch[__simd_id] = sm;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  uint n_simds = __tg_size / 32;
  float partial = (__simd_lane < n_simds) ? scratch[__simd_lane] : 0.0f;
  float total = (__simd_id == 0) ? simd_sum(partial) : 0.0f;
  if (__simd_id == 0 && __simd_lane == 0) scratch[0] = total;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  total = scratch[0];
  float rrms = 1.0f / sqrt(total / float(d) + eps);
  for (int i = int(__tid_in_tg); i < d; i += int(__tg_size)) {
    y[base + i] = x[base + i] * rrms * w[wbase + i];
  }
}

// x[t, i] = (1/S) sum_s sigmoid(up_raw[t, s*d+i]) * n_in[t, s*d+i]
// Dispatch: n*d threads.
[[max_total_threads_per_threadgroup(256)]]
kernel void hc_mix_reduce_multi(
  device const float *__restrict__ up_raw [[buffer(0)]],   // [n, S*d]
  device const float *__restrict__ n_in   [[buffer(1)]],   // [n, S*d]
  device       float *__restrict__ x      [[buffer(2)]],   // [n, d]
  constant int &S [[buffer(3)]],
  constant int &d [[buffer(4)]],
  constant int &n [[buffer(5)]],
  uint __tid [[thread_position_in_grid]]
) {
  int gi = int(__tid);
  if (gi >= n * d) return;
  int t = gi / d;
  int i = gi % d;
  int base = t * S * d;
  float acc = 0.0f;
  for (int s = 0; s < S; s++) {
    float g = 1.0f / (1.0f + exp(-up_raw[base + s * d + i]));
    acc += g * n_in[base + s * d + i];
  }
  x[gi] = acc / float(S);
}

// H[t, s*d+i] += y[t, i] * 2*sigmoid(inj_raw[t, s]/S). Dispatch: n*S*d.
[[max_total_threads_per_threadgroup(256)]]
kernel void hc_combine_multi(
  device       float *__restrict__ H       [[buffer(0)]],  // [n, S*d]
  device const float *__restrict__ y       [[buffer(1)]],  // [n, d]
  device const float *__restrict__ inj_raw [[buffer(2)]],  // [n, S]
  constant int &S [[buffer(3)]],
  constant int &d [[buffer(4)]],
  constant int &n [[buffer(5)]],
  uint __tid [[thread_position_in_grid]]
) {
  int gi = int(__tid);
  if (gi >= n * S * d) return;
  int t = gi / (S * d);
  int r = gi % (S * d);
  int s = r / d;
  int i = r % d;
  float w = 2.0f / (1.0f + exp(-inj_raw[t * S + s] / float(S)));
  H[gi] += y[t * d + i] * w;
}

// Router: per-token softmax + top-10 + renormalize. One TG of 512 per token.
[[max_total_threads_per_threadgroup(512)]]
kernel void router_softmax_topk10_multi(
  device const float *logits      [[buffer(0)]],   // [n, 512]
  device int         *top_indices [[buffer(1)]],   // [n, 10]
  device float       *top_scores  [[buffer(2)]],   // [n, 10]
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __tid   [[thread_position_in_threadgroup]]
) {
  const int N = 512;
  const int K = 10;
  threadgroup float reduce_vals[512];
  threadgroup int   reduce_ids[512];
  threadgroup float probs[512];
  threadgroup float chosen_scores[10];
  threadgroup int   chosen_ids[10];
  threadgroup float scratch_sum[1];

  int t = int(__tg_id);
  int tid = int(__tid);
  float my_logit = logits[t * N + tid];

  reduce_vals[tid] = my_logit;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int stride = N / 2; stride > 0; stride >>= 1) {
    if (tid < stride) reduce_vals[tid] = max(reduce_vals[tid], reduce_vals[tid + stride]);
    threadgroup_barrier(mem_flags::mem_threadgroup);
  }
  float max_logit = reduce_vals[0];
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float my_exp = exp(my_logit - max_logit);
  reduce_vals[tid] = my_exp;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int stride = N / 2; stride > 0; stride >>= 1) {
    if (tid < stride) reduce_vals[tid] += reduce_vals[tid + stride];
    threadgroup_barrier(mem_flags::mem_threadgroup);
  }
  float sum_exp = reduce_vals[0];
  threadgroup_barrier(mem_flags::mem_threadgroup);
  probs[tid] = my_exp / sum_exp;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int k = 0; k < K; k++) {
    reduce_vals[tid] = probs[tid];
    reduce_ids[tid]  = tid;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (int stride = N / 2; stride > 0; stride >>= 1) {
      if (tid < stride) {
        bool take = (reduce_vals[tid + stride] > reduce_vals[tid]) ||
                    (reduce_vals[tid + stride] == reduce_vals[tid] &&
                     reduce_ids[tid + stride] < reduce_ids[tid]);
        if (take) {
          reduce_vals[tid] = reduce_vals[tid + stride];
          reduce_ids[tid]  = reduce_ids[tid + stride];
        }
      }
      threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) {
      chosen_scores[k] = reduce_vals[0];
      chosen_ids[k]    = reduce_ids[0];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (tid == chosen_ids[k]) probs[tid] = -1.0e30f;
    threadgroup_barrier(mem_flags::mem_threadgroup);
  }
  if (tid == 0) {
    float s = 0.0f;
    for (int k = 0; k < K; k++) s += chosen_scores[k];
    scratch_sum[0] = s;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  if (tid < K) {
    top_indices[t * K + tid] = chosen_ids[tid];
    top_scores[t * K + tid]  = chosen_scores[tid] / scratch_sum[0];
  }
}

// Batched expert gather: per-token expert sets. y[t, k, m]; indices [n, K];
// x is [n, k_dim] (x_stride = k_dim, x per token) or [n, K, k_dim]
// (x_stride2 per (t, k), for the down projection).
// Dispatch: n * K * (n_rows/8) TGs of 64.
[[max_total_threads_per_threadgroup(64)]]
kernel void moe_gather_matvec_multi(
  device const uchar *__restrict__ q0 [[buffer(0)]],
  device const uchar *__restrict__ q1 [[buffer(1)]],
  device const uchar *__restrict__ q2 [[buffer(2)]],
  device const uchar *__restrict__ q3 [[buffer(3)]],
  device const int   *__restrict__ indices  [[buffer(4)]],   // [n, K]
  device const int   *__restrict__ slot_map [[buffer(5)]],   // [512]
  device const float *__restrict__ x        [[buffer(6)]],
  device float       *__restrict__ y        [[buffer(7)]],   // [n, K, n_rows]
  constant int &k_dim    [[buffer(8)]],
  constant int &n_rows   [[buffer(9)]],
  constant int &w0       [[buffer(10)]],
  constant int &w_stride [[buffer(11)]],
  constant int &s0       [[buffer(12)]],
  constant int &s_stride [[buffer(13)]],
  constant int &g0       [[buffer(14)]],
  constant int &g_stride [[buffer(15)]],
  constant int &K        [[buffer(16)]],   // experts per token
  constant int &x_is_per_expert [[buffer(17)]],  // 0: x[t,:]; 1: x[t,k,:]
  device const uchar *__restrict__ hot [[buffer(18)]],
  constant int &hw0 [[buffer(19)]],
  constant int &hs0 [[buffer(20)]],
  constant int &hg0 [[buffer(21)]],
  device const int *__restrict__ order [[buffer(22)]],  // [n*K] pair ids, expert-sorted
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __simd_id   [[simdgroup_index_in_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  const int n_groups     = k_dim / 16;
  const int u32s_per_row = k_dim / 8;
  const int tgs_per_k    = n_rows / 8;

  int tg      = int(__tg_id);
  // Expert-sorted iteration: adjacent TGs hit the same expert's weights, so
  // repeats come from L2 instead of a fresh DRAM stream per (token, k).
  int tk      = order[tg / tgs_per_k];   // t*K + k
  int m_block = tg % tgs_per_k;
  int expert  = indices[tk];
  int t       = tk / K;
  int slot    = slot_map[expert];
  int m_start = m_block * 8 + int(__simd_id) * 4;
  int lane    = int(__simd_lane);

  bool is_hot = (slot & (1 << 30)) != 0;
  device const uchar *base = is_hot ? hot
                           : (expert < 128) ? q0
                           : (expert < 256) ? q1
                           : (expert < 384) ? q2 : q3;
  int bw0 = is_hot ? hw0 : w0;
  int bs0 = is_hot ? hs0 : s0;
  int bg0 = is_hot ? hg0 : g0;
  slot = slot & 0xFFFF;
  device const uchar *w_bytes = base + (ulong)(uint)bw0 + (ulong)(uint)slot * (ulong)(uint)w_stride;
  device const uchar *s_bytes = base + (ulong)(uint)bs0 + (ulong)(uint)slot * (ulong)(uint)s_stride;
  float ws2 = load_f32_le(base + (ulong)(uint)bg0 + (ulong)(uint)slot * (ulong)(uint)g_stride);

  int x_base = x_is_per_expert != 0 ? tk * k_dim : t * k_dim;

  float result0 = 0.0f, result1 = 0.0f, result2 = 0.0f, result3 = 0.0f;
  for (int g_block = 0; g_block < n_groups; g_block += 32) {
    int g = g_block + lane;
    if (g >= n_groups) continue;
    device const float4 *xp = (device const float4 *)(&x[x_base + g * 16]);
    float4 x0 = xp[0], x1 = xp[1], x2 = xp[2], x3 = xp[3];
#define DO_ROW(R, accum)                                                  \
    {                                                                     \
      int row = m_start + (R);                                            \
      device const uchar *w_row = w_bytes + (ulong)(uint)row * (ulong)((uint)u32s_per_row * 4u) + (ulong)((uint)g * 8u); \
      uint w0v = load_u32_le(w_row);                                      \
      uint w1v = load_u32_le(w_row + 4);                                  \
      uint sb = (uint)s_bytes[(ulong)(uint)row * (ulong)(uint)n_groups + (ulong)(uint)g]; \
      float scale = float(e4m3_decode_half(sb));                          \
      uint b00 = w0v & 0xFF, b01 = (w0v >>  8) & 0xFF;                    \
      uint b02 = (w0v >> 16) & 0xFF, b03 = (w0v >> 24) & 0xFF;            \
      uint b10 = w1v & 0xFF, b11 = (w1v >>  8) & 0xFF;                    \
      uint b12 = (w1v >> 16) & 0xFF, b13 = (w1v >> 24) & 0xFF;            \
      float4 wv0 = float4(nvfp4_decode_half(b00 & 0xF), nvfp4_decode_half(b00 >> 4), nvfp4_decode_half(b01 & 0xF), nvfp4_decode_half(b01 >> 4)); \
      float4 wv1 = float4(nvfp4_decode_half(b02 & 0xF), nvfp4_decode_half(b02 >> 4), nvfp4_decode_half(b03 & 0xF), nvfp4_decode_half(b03 >> 4)); \
      float4 wv2 = float4(nvfp4_decode_half(b10 & 0xF), nvfp4_decode_half(b10 >> 4), nvfp4_decode_half(b11 & 0xF), nvfp4_decode_half(b11 >> 4)); \
      float4 wv3 = float4(nvfp4_decode_half(b12 & 0xF), nvfp4_decode_half(b12 >> 4), nvfp4_decode_half(b13 & 0xF), nvfp4_decode_half(b13 >> 4)); \
      float dp = dot(wv0, x0) + dot(wv1, x1) + dot(wv2, x2) + dot(wv3, x3); \
      accum += scale * dp;                                                \
    }
    DO_ROW(0, result0)
    DO_ROW(1, result1)
    DO_ROW(2, result2)
    DO_ROW(3, result3)
#undef DO_ROW
  }
  result0 = simd_sum(result0);
  result1 = simd_sum(result1);
  result2 = simd_sum(result2);
  result3 = simd_sum(result3);
  if (lane == 0) {
    int y_base = tk * n_rows + m_start;
    y[y_base + 0] = result0 * ws2;
    y[y_base + 1] = result1 * ws2;
    y[y_base + 2] = result2 * ws2;
    y[y_base + 3] = result3 * ws2;
  }
}

// Batched MoE output: y[t, i] = sum_k w[t,k] d[t,k,i] + sigmoid(gate[t]) sh[t,i]
// Dispatch: n*dim threads.
[[max_total_threads_per_threadgroup(256)]]
kernel void moe_output_multi(
  device const float *__restrict__ d        [[buffer(0)]],  // [n, K, dim]
  device const float *__restrict__ w        [[buffer(1)]],  // [n, K]
  device const float *__restrict__ shared_y [[buffer(2)]],  // [n, dim]
  device const float *__restrict__ gate_raw [[buffer(3)]],  // [n]
  device       float *__restrict__ y        [[buffer(4)]],  // [n, dim]
  constant int &K   [[buffer(5)]],
  constant int &dim [[buffer(6)]],
  constant int &n   [[buffer(7)]],
  uint __tid [[thread_position_in_grid]]
) {
  int gi = int(__tid);
  if (gi >= n * dim) return;
  int t = gi / dim;
  int i = gi % dim;
  float acc = 0.0f;
  for (int k = 0; k < K; k++) {
    acc += w[t * K + k] * d[(t * K + k) * dim + i];
  }
  float g = 1.0f / (1.0f + exp(-gate_raw[t]));
  y[gi] = acc + g * shared_y[t * dim + i];
}

// Batched PLE gate: gate[t,s] over the [n, 4, 2560] views.
// Dispatch: n*S TGs x 256.
[[max_total_threads_per_threadgroup(256)]]
kernel void ple_gate_multi(
  device const float *__restrict__ kn [[buffer(0)]],   // [n, S*d]
  device const float *__restrict__ qn [[buffer(1)]],   // [n, S*d]
  device const float *__restrict__ v  [[buffer(2)]],   // [n, d]
  device       float *__restrict__ gv [[buffer(3)]],   // [n, S*d]
  constant int &d [[buffer(4)]],
  constant int &S [[buffer(5)]],
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __tid_in_tg [[thread_position_in_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]],
  uint __simd_id   [[simdgroup_index_in_threadgroup]],
  uint __tg_size   [[threads_per_threadgroup]]
) {
  int s = int(__tg_id) % S;
  int t = int(__tg_id) / S;
  int base = t * S * d + s * d;
  float dp = 0.0f;
  for (int i = int(__tid_in_tg); i < d; i += int(__tg_size)) {
    dp += kn[base + i] * qn[base + i];
  }
  threadgroup float scratch[32];
  float sm = simd_sum(dp);
  if (__simd_lane == 0) scratch[__simd_id] = sm;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  uint n_simds = __tg_size / 32;
  float partial = (__simd_lane < n_simds) ? scratch[__simd_lane] : 0.0f;
  float total = (__simd_id == 0) ? simd_sum(partial) : 0.0f;
  if (__simd_id == 0 && __simd_lane == 0) scratch[0] = total;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  total = scratch[0] / sqrt(float(d));
  float mag = sqrt(max(fabs(total), 1.0e-6f));
  float signed_sqrt = (total < 0.0f) ? -mag : mag;
  float gate = 1.0f / (1.0f + exp(-signed_sqrt));
  for (int i = int(__tid_in_tg); i < d; i += int(__tg_size)) {
    gv[base + i] = gate * v[t * d + i];
  }
}

// Batched dilated PLE conv step: n sequential tokens of ONE stream.
// State advances by n; taps reach back through the in-flight tokens.
// window[c] = [state(9) | nc_0 | ... | nc_{n-1}]; token t taps at
// (9+t)-9, -6, -3, 0 relative positions inside the window.
// Dispatch: n*C threads. state_out = last 9 columns of the window.
[[max_total_threads_per_threadgroup(256)]]
kernel void ple_conv_dilated_multi(
  device const float *__restrict__ weight    [[buffer(0)]],   // [C, 4, 1]
  device const float *__restrict__ state     [[buffer(1)]],   // [9, C]
  device const float *__restrict__ nc        [[buffer(2)]],   // [n, C]
  device const float *__restrict__ gv        [[buffer(3)]],   // [n, C]
  device       float *__restrict__ H         [[buffer(4)]],   // [n, C] in place
  device       float *__restrict__ state_out [[buffer(5)]],   // [9, C]
  constant int &C [[buffer(6)]],
  constant int &n [[buffer(7)]],
  uint __tid [[thread_position_in_grid]]
) {
  int gi = int(__tid);
  if (gi >= n * C) return;
  int t = gi / C;
  int c = gi % C;

  // virtual window index of this token's newest sample: wpos = 9 + t
  // taps: wpos-9, wpos-6, wpos-3, wpos
  float taps[4];
  for (int j = 0; j < 4; j++) {
    int wp = 9 + t - (3 - j) * 3;
    taps[j] = (wp < 9) ? state[wp * C + c] : nc[(wp - 9) * C + c];
  }
  float w0 = weight[c * 4 + 0];
  float w1 = weight[c * 4 + 1];
  float w2 = weight[c * 4 + 2];
  float w3 = weight[c * 4 + 3];
  float conv_out = w0 * taps[0] + w1 * taps[1] + w2 * taps[2] + w3 * taps[3];
  float sig = 1.0f / (1.0f + exp(-conv_out));
  H[gi] += gv[gi] + conv_out * sig;

  // slide: state_out row r = window[n + r] (only thread t == 0 writes)
  if (t == 0) {
    for (int r = 0; r < 9; r++) {
      int wp = n + r;
      state_out[r * C + c] = (wp < 9) ? state[wp * C + c] : nc[(wp - 9) * C + c];
    }
  }
}

// Width-n gdn_conv_split: depthwise conv4 + silu + q|k|v split over n new
// tokens, serial state in registers per channel (same tape-replay contract as
// the 27B conv1d_depthwise_multi: only the final [3, C] state is written).
// The silu is spelled conv_out * sigmoid(conv_out) — EXACTLY the serial
// gdn_conv_split expression, NOT z/(1+exp(-z)); the two differ in ULPs and
// the verify gate demands bit-identity with the serial path.
kernel void gdn_conv_split_multi(
  device const float *__restrict__ weight    [[buffer(0)]],   // [C, 4, 1]
  device const float *__restrict__ state     [[buffer(1)]],   // [3, C] older first
  device const float *__restrict__ x         [[buffer(2)]],   // [n, C]
  device       float *__restrict__ q_out     [[buffer(3)]],   // [n, q_dim]
  device       float *__restrict__ k_out     [[buffer(4)]],   // [n, k_dim]
  device       float *__restrict__ v_out     [[buffer(5)]],   // [n, v_dim]
  device       float *__restrict__ state_out [[buffer(6)]],   // [3, C]
  constant int &C     [[buffer(7)]],
  constant int &q_dim [[buffer(8)]],
  constant int &k_dim [[buffer(9)]],
  constant int &n_tok [[buffer(10)]],
  uint __tid [[thread_position_in_grid]]
) {
  int c = int(__tid);
  if (c >= C) return;

  float s0 = state[0 * C + c];
  float s1 = state[1 * C + c];
  float s2 = state[2 * C + c];
  float w0 = weight[c * 4 + 0];
  float w1 = weight[c * 4 + 1];
  float w2 = weight[c * 4 + 2];
  float w3 = weight[c * 4 + 3];
  int v_dim = C - q_dim - k_dim;

  for (int t = 0; t < n_tok; ++t) {
    float x_new = x[t * C + c];
    float conv_out = w0 * s0 + w1 * s1 + w2 * s2 + w3 * x_new;
    float sig = 1.0f / (1.0f + exp(-conv_out));
    float y = conv_out * sig;
    if (c < q_dim) {
      q_out[t * q_dim + c] = y;
    } else if (c < q_dim + k_dim) {
      k_out[t * k_dim + (c - q_dim)] = y;
    } else {
      v_out[t * v_dim + (c - q_dim - k_dim)] = y;
    }
    s0 = s1; s1 = s2; s2 = x_new;
  }
  state_out[0 * C + c] = s0;
  state_out[1 * C + c] = s1;
  state_out[2 * C + c] = s2;
}

// Width-n gdn_g_beta: a/b are token-major [n, Hv]; A_log/dt_bias stay [Hv].
kernel void gdn_g_beta_multi(
  device const float *__restrict__ a       [[buffer(0)]],   // [n, Hv]
  device const float *__restrict__ b       [[buffer(1)]],   // [n, Hv]
  device const float *__restrict__ A_log   [[buffer(2)]],   // [Hv]
  device const float *__restrict__ dt_bias [[buffer(3)]],   // [Hv]
  device       float *__restrict__ g       [[buffer(4)]],   // [n, Hv]
  device       float *__restrict__ beta    [[buffer(5)]],   // [n, Hv]
  constant int &Hv    [[buffer(6)]],
  constant int &n_tok [[buffer(7)]],
  uint __tid [[thread_position_in_grid]]
) {
  int i = int(__tid);
  if (i >= n_tok * Hv) return;
  int h = i % Hv;
  float a_val = a[i] + dt_bias[h];
  float sp = log(1.0f + exp(a_val));
  g[i] = exp(-exp(A_log[h]) * sp);
  beta[i] = 1.0f / (1.0f + exp(-b[i]));
}

// Fused per-head norm + optional partial NeoX rope over n tokens, cloning the
// SERIAL per_head_norm + partial_rope_neox expressions EXACTLY:
// 1.0f/sqrt (not rsqrt) and (x*rrms)*w (not x*(rrms*w)) — the verify gate
// demands bit-identity with the serial path. rot_half = 0 skips rope (GDN
// q/k norms). Dispatch: n*n_heads TGs x 32.
[[max_total_threads_per_threadgroup(32)]]
kernel void fn_phn_rope_multi(
  device float *x [[buffer(0)]],
  device const float *w [[buffer(1)]],
  device const float *cos_t [[buffer(2)]],   // [n, rot_half]
  device const float *sin_t [[buffer(3)]],   // [n, rot_half]
  constant int   &head_dim [[buffer(4)]],
  constant int   &rot_half [[buffer(5)]],
  constant int   &n_heads  [[buffer(6)]],
  constant float &inv_d    [[buffer(7)]],
  constant float &eps      [[buffer(8)]],
  constant int   &n_tok    [[buffer(9)]],
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  int token = int(__tg_id) / n_heads;
  int head = int(__tg_id) - token * n_heads;
  if (token >= n_tok) return;
  int base = (token * n_heads + head) * head_dim;
  int lane = int(__simd_lane);
  float sum_sq = 0.0f;
  for (int i = lane; i < head_dim; i += 32) {
    float v = x[base + i];
    sum_sq = sum_sq + v * v;
  }
  float total = simd_sum(sum_sq);
  float rrms = 1.0f / sqrt(total * inv_d + eps);
  for (int i = lane; i < head_dim; i += 32) {
    x[base + i] = (x[base + i] * rrms) * w[i];
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int p = lane; p < rot_half; p += 32) {
    int lo = base + p;
    int hi = lo + rot_half;
    float a = x[lo];
    float b = x[hi];
    float c = cos_t[token * rot_half + p];
    float s = sin_t[token * rot_half + p];
    x[lo] = a * c - b * s;
    x[hi] = a * s + b * c;
  }
}


// Stable counting sort of the (token, expert-slot) pairs by expert id.
// One TG of 512 threads; nK <= 512*... pairs (64 tokens x 10). Thread e owns
// expert e: counts its pairs, takes a prefix sum, then emits its pairs in
// token order — deterministic. Dispatch: 1 TG x 512.
[[max_total_threads_per_threadgroup(512)]]
kernel void moe_sort_pairs(
  device const int *__restrict__ indices [[buffer(0)]],   // [n, K]
  device       int *__restrict__ order   [[buffer(1)]],   // [n*K]
  device       int *__restrict__ offs_out [[buffer(3)]],  // [513] segment offsets
  constant int &nk [[buffer(2)]],
  uint __tid [[thread_position_in_threadgroup]]
) {
  threadgroup int counts[512];
  int e = int(__tid);
  int c = 0;
  for (int p = 0; p < nk; p++) {
    if (indices[p] == e) c++;
  }
  counts[e] = c;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  // exclusive prefix sum (single thread — 512 adds, negligible)
  threadgroup int offsets[512];
  if (e == 0) {
    int acc = 0;
    for (int i = 0; i < 512; i++) {
      offsets[i] = acc;
      acc += counts[i];
    }
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  int at = offsets[e];
  for (int p = 0; p < nk; p++) {
    if (indices[p] == e) {
      order[at] = p;
      at++;
    }
  }
  offs_out[e] = offsets[e];
  if (e == 0) offs_out[512] = nk;
}


// Token-block-parallel bf16 matvec: same arithmetic as bf16_matvec_multi
// (lane-strided k, simd_sum) but the 8-token sub-batch loop moves onto the
// TG grid, so small-row projections get rows x ceil(n/8) threadgroups
// instead of rows — the hyper-connection chain's barriers stop exposing
// multi-millisecond single-TG latencies. Weights re-read once per token
// block, exactly like the in-kernel loop did.
// Dispatch: rows * ceil(n/8) TGs of 32.
kernel void bf16_matvec_multi_p(
  device const ushort *__restrict__ weight [[buffer(0)]],
  device const float  *__restrict__ x      [[buffer(1)]],
  device       float  *__restrict__ y      [[buffer(2)]],
  constant int &k_dim  [[buffer(3)]],
  constant int &n_rows [[buffer(4)]],
  constant int &n_tok  [[buffer(5)]],
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  const int blocks = (n_tok + 7) / 8;
  int tg = int(__tg_id);
  int row = tg / blocks;
  int b0 = (tg % blocks) * 8;
  if (row >= n_rows) return;
  const int nb = min(n_tok - b0, 8);
  int lane = int(__simd_lane);
  float acc[8];
  for (int b = 0; b < 8; ++b) acc[b] = 0.0f;
  for (int k = lane; k < k_dim; k += 32) {
    const float w = as_type<float>(uint(weight[row * k_dim + k]) << 16);
    for (int b = 0; b < nb; ++b) acc[b] += w * x[(b0 + b) * k_dim + k];
  }
  for (int b = 0; b < nb; ++b) {
    const float total = simd_sum(acc[b]);
    if (lane == 0) y[(b0 + b) * n_rows + row] = total;
  }
}


// Grouped per-expert matvec for prefill chunks: each expert's weight tile is
// decoded ONCE per 8-token block of its token list instead of once per
// (token, slot) pair — expert traffic and nibble-decode ALU drop by
// ~c_e/ceil(c_e/8) (~5x at chunk 512). Registers follow the
// nvfp4_wide b8_r4 pattern: 2 simdgroups x 4 rows, acc[4][8] per lane.
// Dispatch: 512 * (n_rows/8) TGs of 64.
[[max_total_threads_per_threadgroup(64)]]
kernel void moe_grouped_matvec(
  device const uchar *__restrict__ q0 [[buffer(0)]],
  device const uchar *__restrict__ q1 [[buffer(1)]],
  device const uchar *__restrict__ q2 [[buffer(2)]],
  device const uchar *__restrict__ q3 [[buffer(3)]],
  device const int   *__restrict__ order    [[buffer(4)]],   // [n*K] expert-sorted pair ids
  device const int   *__restrict__ offs     [[buffer(5)]],   // [513]
  device const int   *__restrict__ slot_map [[buffer(6)]],
  device const float *__restrict__ x        [[buffer(7)]],
  device float       *__restrict__ y        [[buffer(8)]],   // [n*K, n_rows] per PAIR
  constant int &k_dim    [[buffer(9)]],
  constant int &n_rows   [[buffer(10)]],
  constant int &w0       [[buffer(11)]],
  constant int &w_stride [[buffer(12)]],
  constant int &s0       [[buffer(13)]],
  constant int &s_stride [[buffer(14)]],
  constant int &g0       [[buffer(15)]],
  constant int &g_stride [[buffer(16)]],
  constant int &K        [[buffer(17)]],
  constant int &x_is_per_pair [[buffer(18)]],  // 0: x[t,:]; 1: x[pair,:]
  uint __tg_id     [[threadgroup_position_in_grid]],
  uint __simd_id   [[simdgroup_index_in_threadgroup]],
  uint __simd_lane [[thread_index_in_simdgroup]]
) {
  const int n_groups     = k_dim / 16;
  const int u32s_per_row = k_dim / 8;
  const int tgs_per_e    = n_rows / 8;
  int tg      = int(__tg_id);
  int expert  = tg / tgs_per_e;
  int m_block = tg % tgs_per_e;
  int seg_lo  = offs[expert];
  int seg_hi  = offs[expert + 1];
  if (seg_lo >= seg_hi) return;
  int slot = slot_map[expert] & 0xFFFF;
  device const uchar *base = (expert < 128) ? q0
                           : (expert < 256) ? q1
                           : (expert < 384) ? q2 : q3;
  device const uchar *w_bytes = base + (ulong)(uint)w0 + (ulong)(uint)slot * (ulong)(uint)w_stride;
  device const uchar *s_bytes = base + (ulong)(uint)s0 + (ulong)(uint)slot * (ulong)(uint)s_stride;
  float ws2 = load_f32_le(base + (ulong)(uint)g0 + (ulong)(uint)slot * (ulong)(uint)g_stride);
  int m_start = m_block * 8 + int(__simd_id) * 4;
  int lane    = int(__simd_lane);

  for (int tb = seg_lo; tb < seg_hi; tb += 4) {
    const int nb = min(seg_hi - tb, 4);
    int xbase[4];
    for (int b = 0; b < nb; b++) {
      int pair = order[tb + b];
      xbase[b] = x_is_per_pair != 0 ? pair * k_dim : (pair / K) * k_dim;
    }
    float acc[4][4];
    for (int r = 0; r < 4; r++)
      for (int b = 0; b < 4; b++) acc[r][b] = 0.0f;

    for (int g_block = 0; g_block < n_groups; g_block += 32) {
      int g = g_block + lane;
      if (g >= n_groups) continue;
      float4 av[4][4];
      for (int b = 0; b < nb; b++) {
        device const float4 *xp = (device const float4 *)(&x[xbase[b] + g * 16]);
        av[b][0] = xp[0]; av[b][1] = xp[1]; av[b][2] = xp[2]; av[b][3] = xp[3];
      }
#define GDO_ROW(R)                                                          \
      {                                                                     \
        int row = m_start + (R);                                            \
        device const uint *w_row = (device const uint *)(w_bytes + (ulong)(uint)row * (ulong)((uint)u32s_per_row * 4u) + (ulong)((uint)g * 8u)); \
        uint w0v = w_row[0];                                                \
        uint w1v = w_row[1];                                                \
        uint sb = (uint)s_bytes[(ulong)(uint)row * (ulong)(uint)n_groups + (ulong)(uint)g]; \
        float scale = float(e4m3_decode_half(sb));                          \
        uint b00 = w0v & 0xFF, b01 = (w0v >>  8) & 0xFF;                    \
        uint b02 = (w0v >> 16) & 0xFF, b03 = (w0v >> 24) & 0xFF;            \
        uint b10 = w1v & 0xFF, b11 = (w1v >>  8) & 0xFF;                    \
        uint b12 = (w1v >> 16) & 0xFF, b13 = (w1v >> 24) & 0xFF;            \
        float4 wv0 = float4(nvfp4_decode_half(b00 & 0xF), nvfp4_decode_half(b00 >> 4), nvfp4_decode_half(b01 & 0xF), nvfp4_decode_half(b01 >> 4)); \
        float4 wv1 = float4(nvfp4_decode_half(b02 & 0xF), nvfp4_decode_half(b02 >> 4), nvfp4_decode_half(b03 & 0xF), nvfp4_decode_half(b03 >> 4)); \
        float4 wv2 = float4(nvfp4_decode_half(b10 & 0xF), nvfp4_decode_half(b10 >> 4), nvfp4_decode_half(b11 & 0xF), nvfp4_decode_half(b11 >> 4)); \
        float4 wv3 = float4(nvfp4_decode_half(b12 & 0xF), nvfp4_decode_half(b12 >> 4), nvfp4_decode_half(b13 & 0xF), nvfp4_decode_half(b13 >> 4)); \
        for (int b = 0; b < nb; b++) {                                      \
          float dp = dot(wv0, av[b][0]) + dot(wv1, av[b][1]) +              \
                     dot(wv2, av[b][2]) + dot(wv3, av[b][3]);               \
          acc[R][b] += scale * dp;                                          \
        }                                                                   \
      }
      GDO_ROW(0)
      GDO_ROW(1)
      GDO_ROW(2)
      GDO_ROW(3)
#undef GDO_ROW
    }
    for (int r = 0; r < 4; r++) {
      for (int b = 0; b < nb; b++) {
        float total = simd_sum(acc[r][b]);
        if (lane == 0) {
          int pair = order[tb + b];
          y[pair * n_rows + m_start + r] = total * ws2;
        }
      }
    }
  }
}


// Prefill-shape SDPA: same math as sdpa_decode_multi_hd256 but the score
// phase assigns POSITIONS to threads (each thread runs its own serial
// 256-wide dot) — no per-position threadgroup barriers, which at chunked
// prefill exposed ~2 barriers x every visible position per (token, head).
// Softmax and the weighted sum are unchanged in structure.
// Dispatch: n_tok * n_heads TGs of 256.
[[max_total_threads_per_threadgroup(256)]]
kernel void sdpa_prefill_multi_hd256(
  device const float *__restrict__ q       [[buffer(0)]],
  device const float *__restrict__ k_cache [[buffer(1)]],
  device const float *__restrict__ v_cache [[buffer(2)]],
  device       float *__restrict__ out     [[buffer(3)]],
  constant int &gqa_factor [[buffer(4)]],
  device const int *__restrict__ pos_start [[buffer(5)]],
  constant int &n_heads [[buffer(6)]],
  constant int &kv_dim  [[buffer(7)]],
  constant float &scale [[buffer(8)]],
  constant int &n_tok   [[buffer(9)]],
  uint tg  [[threadgroup_position_in_grid]],
  uint tid [[thread_position_in_threadgroup]]
) {
  threadgroup float scores[2051];
  threadgroup float qs[256];
  const int token = int(tg) / n_heads;
  const int q_head = int(tg) - token * n_heads;
  if (token >= n_tok) return;
  const int kv_head = q_head / gqa_factor;
  const int q_off = (token * n_heads + q_head) * 256;
  const int kv_base = kv_head * 256;
  const int usable = min(pos_start[0] + token + 1, 2051);
  qs[tid] = q[q_off + int(tid)];
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int p = int(tid); p < usable; p += 256) {
    device const float *kr = k_cache + kv_base + p * kv_dim;
    float dp = 0.0f;
    for (int i = 0; i < 256; i++) dp += qs[i] * kr[i];
    scores[p] = dp * scale;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  // parallel softmax: 256-thread strided max/sum with simd + TG reduction
  threadgroup float red[8];
  float lmx = -INFINITY;
  for (int p = int(tid); p < usable; p += 256) lmx = max(lmx, scores[p]);
  float smx = simd_max(lmx);
  if ((tid & 31) == 0) red[tid >> 5] = smx;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float mx = max(max(max(red[0], red[1]), max(red[2], red[3])),
                 max(max(red[4], red[5]), max(red[6], red[7])));
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float lsum = 0.0f;
  for (int p = int(tid); p < usable; p += 256) {
    const float e = fast::exp(scores[p] - mx);
    scores[p] = e;
    lsum += e;
  }
  float ssum = simd_sum(lsum);
  if ((tid & 31) == 0) red[tid >> 5] = ssum;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float denom = red[0] + red[1] + red[2] + red[3] + red[4] + red[5] + red[6] + red[7];
  const float inv = denom == 0.0f ? 0.0f : 1.0f / denom;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float result = 0.0f;
  for (int p = 0; p < usable; ++p) {
    result += scores[p] * v_cache[kv_base + p * kv_dim + int(tid)];
  }
  out[q_off + int(tid)] = result * inv;
}


// Stage activation rows into expert-sorted contiguous order so the grouped
// GEMM can tile them with simdgroup_load. Dispatch: nk * k_dim threads.
kernel void moe_stage_x(
  device const float *__restrict__ x     [[buffer(0)]],
  device       float *__restrict__ xg    [[buffer(1)]],   // [nk, k_dim]
  device const int   *__restrict__ order [[buffer(2)]],
  constant int &k_dim [[buffer(3)]],
  constant int &K     [[buffer(4)]],
  constant int &x_is_per_pair [[buffer(5)]],
  constant int &nk    [[buffer(6)]],
  uint __tid [[thread_position_in_grid]]
) {
  int gi = int(__tid);
  if (gi >= nk * k_dim) return;
  int srow = gi / k_dim;
  int i = gi % k_dim;
  int pair = order[srow];
  int src = x_is_per_pair != 0 ? pair : pair / K;
  xg[srow * k_dim + i] = x[src * k_dim + i];
}

// Half-precision staging for the half-MMA expert GEMM.
kernel void moe_stage_x_h(
  device const float *__restrict__ x     [[buffer(0)]],
  device       half  *__restrict__ xg    [[buffer(1)]],
  device const int   *__restrict__ order [[buffer(2)]],
  constant int &k_dim [[buffer(3)]],
  constant int &K     [[buffer(4)]],
  constant int &x_is_per_pair [[buffer(5)]],
  constant int &nk    [[buffer(6)]],
  uint __tid [[thread_position_in_grid]]
) {
  int gi = int(__tid);
  if (gi >= nk * k_dim) return;
  int srow = gi / k_dim;
  int i = gi % k_dim;
  int pair = order[srow];
  int src = x_is_per_pair != 0 ? pair : pair / K;
  xg[srow * k_dim + i] = half(x[src * k_dim + i]);
}

// Per-expert NVFP4 GEMM on simdgroup MMA over the staged activations: the
// nvfp4_gemm_f32 tile plan (4 simdgroups x 8 output rows, K stepped 16 wide
// through threadgroup memory, one nibble decode per weight per m-tile) with
// expert/quarter indirection and per-pair scatter on store.
// Dispatch: 512 * (n_rows/32) TGs of 128.
[[max_total_threads_per_threadgroup(128)]]
kernel void moe_gemm_m8(
  device const uchar *__restrict__ q0 [[buffer(0)]],
  device const uchar *__restrict__ q1 [[buffer(1)]],
  device const uchar *__restrict__ q2 [[buffer(2)]],
  device const uchar *__restrict__ q3 [[buffer(3)]],
  device const int   *__restrict__ order    [[buffer(4)]],
  device const int   *__restrict__ offs     [[buffer(5)]],   // [513]
  device const int   *__restrict__ slot_map [[buffer(6)]],
  device const float *__restrict__ xg       [[buffer(7)]],   // [nk, k_dim] staged
  device float       *__restrict__ y        [[buffer(8)]],   // [n*K, n_rows] per pair
  constant int &k_dim    [[buffer(9)]],
  constant int &n_rows   [[buffer(10)]],
  constant int &w0       [[buffer(11)]],
  constant int &w_stride [[buffer(12)]],
  constant int &s0       [[buffer(13)]],
  constant int &s_stride [[buffer(14)]],
  constant int &g0       [[buffer(15)]],
  constant int &g_stride [[buffer(16)]],
  constant int &na_min   [[buffer(17)]],   // experts with >= na_min rows belong to moe_gemm_na (FN_NA_MOE); pass INT_MAX-ish otherwise
  uint tg_id  [[threadgroup_position_in_grid]],
  uint simd_id [[simdgroup_index_in_threadgroup]],
  uint lane   [[thread_index_in_simdgroup]]
) {
  const int tgs_per_e = n_rows / 32;
  const int expert = int(tg_id) / tgs_per_e;
  const int seg_lo = offs[expert];
  const int c = offs[expert + 1] - seg_lo;
  if (c <= 0 || c >= na_min) return;
  const int n0 = (int(tg_id) % tgs_per_e) * 32 + int(simd_id) * 8;
  const int n_groups = k_dim / 16;
  const int u32s_per_row = k_dim / 8;
  const int slot = slot_map[expert] & 0xFFFF;
  device const uchar *base = (expert < 128) ? q0
                           : (expert < 256) ? q1
                           : (expert < 384) ? q2 : q3;
  device const uint  *wq = (device const uint *)(base + (ulong)(uint)w0 + (ulong)(uint)slot * (ulong)(uint)w_stride);
  device const uchar *sq = base + (ulong)(uint)s0 + (ulong)(uint)slot * (ulong)(uint)s_stride;
  const float ws2 = load_f32_le(base + (ulong)(uint)g0 + (ulong)(uint)slot * (ulong)(uint)g_stride);

  threadgroup float tile[4 * 128 + 3 * 512 + 512];
  threadgroup float a_tile[2 * 512];
  threadgroup float stage[4 * 64];
  // ping-pong pair per simdgroup: [simd][2][128] with the second half at +512
  threadgroup float *bt = tile + int(simd_id) * 128;
  threadgroup float *at_buf = a_tile;
  threadgroup float *st = stage + int(simd_id) * 64;

  const int r = int(lane) >> 2;
  const int qq = int(lane) & 3;
  const int row = min(n0 + r, n_rows - 1);
  device const uint  *wrow = wq + row * u32s_per_row;
  device const uchar *srow = sq + row * n_groups;

  // Up to 4 live C tiles (32 staged rows) per outer pass: ONE nibble decode
  // serves them all. C[4] = 8 floats/lane — no spill.
  for (int mt0 = 0; mt0 < c; mt0 += 32) {
    const int mtiles = min((c - mt0 + 7) / 8, 4);
    simdgroup_matrix<float, 8, 8> C[4];
    for (int i2 = 0; i2 < 4; i2++) C[i2] = simdgroup_matrix<float, 8, 8>(0.0f);
    // Ping-pong tile buffers: ONE barrier per K-group; the decode of group
    // g+1 overlaps the MMAs of group g (different buffer halves).
#define GEMM_DECODE(GIDX, BUF)                                              \
    {                                                                       \
      const uint w = wrow[(GIDX) * 2 + (qq >> 1)];                          \
      const uint b0 = (w >> ((qq & 1) * 16)) & 0xff;                        \
      const uint b1 = (w >> ((qq & 1) * 16 + 8)) & 0xff;                    \
      const float sc = float(e4m3_decode_half(uint(srow[(GIDX)])));         \
      threadgroup float *dst = (BUF);                                       \
      const int kb = qq * 4;                                                \
      dst[(kb + 0) * 8 + r] = float(nvfp4_decode_half(b0 & 0xf)) * sc;      \
      dst[(kb + 1) * 8 + r] = float(nvfp4_decode_half(b0 >> 4)) * sc;       \
      dst[(kb + 2) * 8 + r] = float(nvfp4_decode_half(b1 & 0xf)) * sc;      \
      dst[(kb + 3) * 8 + r] = float(nvfp4_decode_half(b1 >> 4)) * sc;       \
    }
    GEMM_DECODE(0, bt)
    // cooperative A staging: the 32 staged rows x 16-k slice is IDENTICAL for
    // all 4 simdgroups (they differ only in output rows) — load it once per
    // K-step with the whole TG instead of 4x2 device simdgroup_loads each.
    {
      const int tg_lane = int(simd_id) * 32 + int(lane);
      const int ar = tg_lane >> 2;          // 0..31 staged row
      const int ac = (tg_lane & 3) * 4;     // 0,4,8,12
      const int arow = seg_lo + mt0 + min(ar, c - mt0 - 1);
      device const float *asrc0 = xg + (ulong)arow * (ulong)k_dim;
      for (int i3 = 0; i3 < 4; i3++)
        at_buf[ar * 16 + ac + i3] = asrc0[ac + i3];
    }
    for (int g = 0; g < n_groups; g++) {
      threadgroup_barrier(mem_flags::mem_threadgroup);
      threadgroup float *cur = (g & 1) ? (bt + 512) : bt;
      threadgroup float *nxt = (g & 1) ? bt : (bt + 512);
      threadgroup float *acur = (g & 1) ? (at_buf + 512) : at_buf;
      threadgroup float *anxt = (g & 1) ? at_buf : (at_buf + 512);
      if (g + 1 < n_groups) {
        GEMM_DECODE(g + 1, nxt)
        const int tg_lane = int(simd_id) * 32 + int(lane);
        const int ar = tg_lane >> 2;
        const int ac = (tg_lane & 3) * 4;
        const int arow = seg_lo + mt0 + min(ar, c - mt0 - 1);
        device const float *asrc = xg + (ulong)arow * (ulong)k_dim + (ulong)((g + 1) * 16);
        for (int i3 = 0; i3 < 4; i3++)
          anxt[ar * 16 + ac + i3] = asrc[ac + i3];
      }
      simdgroup_matrix<float, 8, 8> B0, B1, A0, A1;
      simdgroup_load(B0, cur, 8);
      simdgroup_load(B1, cur + 64, 8);
      for (int i2 = 0; i2 < mtiles; i2++) {
        simdgroup_load(A0, acur + i2 * 8 * 16, 16);
        simdgroup_load(A1, acur + i2 * 8 * 16 + 8, 16);
        simdgroup_multiply_accumulate(C[i2], A0, B0, C[i2]);
        simdgroup_multiply_accumulate(C[i2], A1, B1, C[i2]);
      }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
#undef GEMM_DECODE
    for (int i2 = 0; i2 < mtiles; i2++) {
      const int mt = mt0 + i2 * 8;
      const int m_rows = min(c - mt, 8);
      simdgroup_store(C[i2], st, 8);
      simdgroup_barrier(mem_flags::mem_threadgroup);
      for (int e2 = int(lane); e2 < 64; e2 += 32) {
        const int m = e2 >> 3;
        const int n = n0 + (e2 & 7);
        if (m < m_rows && n < n_rows) {
          const int pair = order[seg_lo + mt + m];
          y[pair * n_rows + n] = st[e2] * ws2;
        }
      }
      simdgroup_barrier(mem_flags::mem_threadgroup);
    }
  }
}


kernel void moe_gemm_m8_h(
  device const uchar *__restrict__ q0 [[buffer(0)]],
  device const uchar *__restrict__ q1 [[buffer(1)]],
  device const uchar *__restrict__ q2 [[buffer(2)]],
  device const uchar *__restrict__ q3 [[buffer(3)]],
  device const int   *__restrict__ order    [[buffer(4)]],
  device const int   *__restrict__ offs     [[buffer(5)]],   // [513]
  device const int   *__restrict__ slot_map [[buffer(6)]],
  device const half  *__restrict__ xg       [[buffer(7)]],   // [nk, k_dim] staged f16
  device float       *__restrict__ y        [[buffer(8)]],   // [n*K, n_rows] per pair
  constant int &k_dim    [[buffer(9)]],
  constant int &n_rows   [[buffer(10)]],
  constant int &w0       [[buffer(11)]],
  constant int &w_stride [[buffer(12)]],
  constant int &s0       [[buffer(13)]],
  constant int &s_stride [[buffer(14)]],
  constant int &g0       [[buffer(15)]],
  constant int &g_stride [[buffer(16)]],
  uint tg_id  [[threadgroup_position_in_grid]],
  uint simd_id [[simdgroup_index_in_threadgroup]],
  uint lane   [[thread_index_in_simdgroup]]
) {
  const int tgs_per_e = n_rows / 32;
  const int expert = int(tg_id) / tgs_per_e;
  const int seg_lo = offs[expert];
  const int c = offs[expert + 1] - seg_lo;
  if (c <= 0) return;
  const int n0 = (int(tg_id) % tgs_per_e) * 32 + int(simd_id) * 8;
  const int n_groups = k_dim / 16;
  const int u32s_per_row = k_dim / 8;
  const int slot = slot_map[expert] & 0xFFFF;
  device const uchar *base = (expert < 128) ? q0
                           : (expert < 256) ? q1
                           : (expert < 384) ? q2 : q3;
  device const uint  *wq = (device const uint *)(base + (ulong)(uint)w0 + (ulong)(uint)slot * (ulong)(uint)w_stride);
  device const uchar *sq = base + (ulong)(uint)s0 + (ulong)(uint)slot * (ulong)(uint)s_stride;
  const float ws2 = load_f32_le(base + (ulong)(uint)g0 + (ulong)(uint)slot * (ulong)(uint)g_stride);

  threadgroup half tile[4 * 128];
  threadgroup float stage[4 * 64];
  threadgroup half *bt = tile + int(simd_id) * 128;
  threadgroup float *st = stage + int(simd_id) * 64;

  const int r = int(lane) >> 2;
  const int qq = int(lane) & 3;
  const int row = min(n0 + r, n_rows - 1);
  device const uint  *wrow = wq + row * u32s_per_row;
  device const uchar *srow = sq + row * n_groups;

  // Up to 4 live C tiles (32 staged rows) per outer pass: ONE nibble decode
  // serves them all. C[4] = 8 floats/lane — no spill.
  for (int mt0 = 0; mt0 < c; mt0 += 32) {
    const int mtiles = min((c - mt0 + 7) / 8, 4);
    simdgroup_matrix<half, 8, 8> C[4];
    for (int i2 = 0; i2 < 4; i2++) C[i2] = simdgroup_matrix<half, 8, 8>(0.0h);
    for (int g = 0; g < n_groups; g++) {
      const uint w = wrow[g * 2 + (qq >> 1)];
      const uint b0 = (w >> ((qq & 1) * 16)) & 0xff;
      const uint b1 = (w >> ((qq & 1) * 16 + 8)) & 0xff;
      const float sc = float(e4m3_decode_half(uint(srow[g])));
      // write the tile K-MAJOR so the B loads skip the transposed-load path
      threadgroup half *dst = bt;
      const int kb = qq * 4;
      dst[(kb + 0) * 8 + r] = half(float(nvfp4_decode_half(b0 & 0xf)) * sc);
      dst[(kb + 1) * 8 + r] = half(float(nvfp4_decode_half(b0 >> 4)) * sc);
      dst[(kb + 2) * 8 + r] = half(float(nvfp4_decode_half(b1 & 0xf)) * sc);
      dst[(kb + 3) * 8 + r] = half(float(nvfp4_decode_half(b1 >> 4)) * sc);
      simdgroup_barrier(mem_flags::mem_threadgroup);
      simdgroup_matrix<half, 8, 8> B0, B1, A0, A1;
      simdgroup_load(B0, bt, 8);
      simdgroup_load(B1, bt + 64, 8);
      const int k0 = g * 16;
      for (int i2 = 0; i2 < mtiles; i2++) {
        simdgroup_load(A0, xg + (ulong)(seg_lo + mt0 + i2 * 8) * (ulong)k_dim + k0, (ulong)k_dim);
        simdgroup_load(A1, xg + (ulong)(seg_lo + mt0 + i2 * 8) * (ulong)k_dim + k0 + 8, (ulong)k_dim);
        simdgroup_multiply_accumulate(C[i2], A0, B0, C[i2]);
        simdgroup_multiply_accumulate(C[i2], A1, B1, C[i2]);
      }
      simdgroup_barrier(mem_flags::mem_threadgroup);
    }
    for (int i2 = 0; i2 < mtiles; i2++) {
      const int mt = mt0 + i2 * 8;
      const int m_rows = min(c - mt, 8);
      simdgroup_matrix<float, 8, 8> Cf;
      simdgroup_store(C[i2], (threadgroup half *)st, 8);
      simdgroup_barrier(mem_flags::mem_threadgroup);
      (void)Cf;
      simdgroup_barrier(mem_flags::mem_threadgroup);
      for (int e2 = int(lane); e2 < 64; e2 += 32) {
        const int m = e2 >> 3;
        const int n = n0 + (e2 & 7);
        if (m < m_rows && n < n_rows) {
          const int pair = order[seg_lo + mt + m];
          y[pair * n_rows + n] = float(((threadgroup half *)st)[e2]) * ws2;
        }
      }
      simdgroup_barrier(mem_flags::mem_threadgroup);
    }
  }
}


// Parallel-over-tokens conv+split: the depthwise conv4 needs only the 3
// prior inputs, so (t, c) pairs are independent — no serial token loop.
// state rows supply t < 3; state_out = the last 3 inputs of the chunk.
// Dispatch: n * C threads.
kernel void gdn_conv_split_par(
  device const float *__restrict__ weight    [[buffer(0)]],   // [C, 4, 1]
  device const float *__restrict__ state     [[buffer(1)]],   // [3, C]
  device const float *__restrict__ x         [[buffer(2)]],   // [n, C]
  device       float *__restrict__ q_out     [[buffer(3)]],
  device       float *__restrict__ k_out     [[buffer(4)]],
  device       float *__restrict__ v_out     [[buffer(5)]],
  device       float *__restrict__ state_out [[buffer(6)]],   // [3, C]
  constant int &C     [[buffer(7)]],
  constant int &q_dim [[buffer(8)]],
  constant int &k_dim [[buffer(9)]],
  constant int &n_tok [[buffer(10)]],
  uint __tid [[thread_position_in_grid]]
) {
  int gi = int(__tid);
  if (gi >= n_tok * C) return;
  int t = gi / C;
  int c = gi % C;
  float taps[4];
  for (int j = 0; j < 4; j++) {
    int tt = t - 3 + j;
    taps[j] = (tt < 0) ? state[(tt + 3) * C + c] : x[tt * C + c];
  }
  float w0 = weight[c * 4 + 0];
  float w1 = weight[c * 4 + 1];
  float w2 = weight[c * 4 + 2];
  float w3 = weight[c * 4 + 3];
  float conv_out = w0 * taps[0] + w1 * taps[1] + w2 * taps[2] + w3 * taps[3];
  float sig = 1.0f / (1.0f + exp(-conv_out));
  float yv = conv_out * sig;
  int v_dim = C - q_dim - k_dim;
  if (c < q_dim) q_out[t * q_dim + c] = yv;
  else if (c < q_dim + k_dim) k_out[t * k_dim + (c - q_dim)] = yv;
  else v_out[t * v_dim + (c - q_dim - k_dim)] = yv;
  if (t == 0) {
    for (int r = 0; r < 3; r++) {
      int tt = n_tok - 3 + r;
      state_out[r * C + c] = (tt < 0) ? state[(tt + 3) * C + c] : x[tt * C + c];
    }
  }
}


// f32 -> bf16 truncation for M4 activation staging.
kernel void f32_to_bf16(
  device const float  *__restrict__ src [[buffer(0)]],
  device       ushort *__restrict__ dst [[buffer(1)]],
  constant int &n [[buffer(2)]],
  uint __tid [[thread_position_in_grid]]
) {
  if (int(__tid) >= n) return;
  dst[__tid] = ushort(as_type<uint>(src[__tid]) >> 16);
}

// Round-to-nearest-even f32 -> bf16 (the truncating twin above keeps its
// bit-exact role in the ids-gated paths). Activation staging for the
// Neural-Accelerator GEMMs (FN_NA): halves the staging error of truncation.
kernel void f32_to_bf16_rne(
  device const float  *__restrict__ src [[buffer(0)]],
  device       ushort *__restrict__ dst [[buffer(1)]],
  constant int &n [[buffer(2)]],
  uint __tid [[thread_position_in_grid]]
) {
  if (int(__tid) >= n) return;
  uint u = as_type<uint>(src[__tid]);
  if ((u & 0x7f800000u) == 0x7f800000u) { dst[__tid] = ushort(u >> 16); return; }  // inf/nan: truncate
  uint lsb = (u >> 16) & 1u;
  dst[__tid] = ushort((u + 0x7fffu + lsb) >> 16);
}



[[max_total_threads_per_threadgroup(128)]]
kernel void moe_gemm_m8_v1(
  device const uchar *__restrict__ q0 [[buffer(0)]],
  device const uchar *__restrict__ q1 [[buffer(1)]],
  device const uchar *__restrict__ q2 [[buffer(2)]],
  device const uchar *__restrict__ q3 [[buffer(3)]],
  device const int   *__restrict__ order    [[buffer(4)]],
  device const int   *__restrict__ offs     [[buffer(5)]],   // [513]
  device const int   *__restrict__ slot_map [[buffer(6)]],
  device const float *__restrict__ xg       [[buffer(7)]],   // [nk, k_dim] staged
  device float       *__restrict__ y        [[buffer(8)]],   // [n*K, n_rows] per pair
  constant int &k_dim    [[buffer(9)]],
  constant int &n_rows   [[buffer(10)]],
  constant int &w0       [[buffer(11)]],
  constant int &w_stride [[buffer(12)]],
  constant int &s0       [[buffer(13)]],
  constant int &s_stride [[buffer(14)]],
  constant int &g0       [[buffer(15)]],
  constant int &g_stride [[buffer(16)]],
  uint tg_id  [[threadgroup_position_in_grid]],
  uint simd_id [[simdgroup_index_in_threadgroup]],
  uint lane   [[thread_index_in_simdgroup]]
) {
  const int tgs_per_e = n_rows / 32;
  const int expert = int(tg_id) / tgs_per_e;
  const int seg_lo = offs[expert];
  const int c = offs[expert + 1] - seg_lo;
  if (c <= 0) return;
  const int n0 = (int(tg_id) % tgs_per_e) * 32 + int(simd_id) * 8;
  const int n_groups = k_dim / 16;
  const int u32s_per_row = k_dim / 8;
  const int slot = slot_map[expert] & 0xFFFF;
  device const uchar *base = (expert < 128) ? q0
                           : (expert < 256) ? q1
                           : (expert < 384) ? q2 : q3;
  device const uint  *wq = (device const uint *)(base + (ulong)(uint)w0 + (ulong)(uint)slot * (ulong)(uint)w_stride);
  device const uchar *sq = base + (ulong)(uint)s0 + (ulong)(uint)slot * (ulong)(uint)s_stride;
  const float ws2 = load_f32_le(base + (ulong)(uint)g0 + (ulong)(uint)slot * (ulong)(uint)g_stride);

  threadgroup float tile[4 * 128 + 3 * 512 + 512];
  threadgroup float stage[4 * 64];
  // ping-pong pair per simdgroup: [simd][2][128] with the second half at +512
  threadgroup float *bt = tile + int(simd_id) * 128;
  threadgroup float *st = stage + int(simd_id) * 64;

  const int r = int(lane) >> 2;
  const int qq = int(lane) & 3;
  const int row = min(n0 + r, n_rows - 1);
  device const uint  *wrow = wq + row * u32s_per_row;
  device const uchar *srow = sq + row * n_groups;

  // Up to 4 live C tiles (32 staged rows) per outer pass: ONE nibble decode
  // serves them all. C[4] = 8 floats/lane — no spill.
  for (int mt0 = 0; mt0 < c; mt0 += 32) {
    const int mtiles = min((c - mt0 + 7) / 8, 4);
    simdgroup_matrix<float, 8, 8> C[4];
    for (int i2 = 0; i2 < 4; i2++) C[i2] = simdgroup_matrix<float, 8, 8>(0.0f);
    // Ping-pong tile buffers: ONE barrier per K-group; the decode of group
    // g+1 overlaps the MMAs of group g (different buffer halves).
#define GEMM_DECODE_V1(GIDX, BUF)                                              \
    {                                                                       \
      const uint w = wrow[(GIDX) * 2 + (qq >> 1)];                          \
      const uint b0 = (w >> ((qq & 1) * 16)) & 0xff;                        \
      const uint b1 = (w >> ((qq & 1) * 16 + 8)) & 0xff;                    \
      const float sc = float(e4m3_decode_half(uint(srow[(GIDX)])));         \
      threadgroup float *dst = (BUF);                                       \
      const int kb = qq * 4;                                                \
      dst[(kb + 0) * 8 + r] = float(nvfp4_decode_half(b0 & 0xf)) * sc;      \
      dst[(kb + 1) * 8 + r] = float(nvfp4_decode_half(b0 >> 4)) * sc;       \
      dst[(kb + 2) * 8 + r] = float(nvfp4_decode_half(b1 & 0xf)) * sc;      \
      dst[(kb + 3) * 8 + r] = float(nvfp4_decode_half(b1 >> 4)) * sc;       \
    }
    GEMM_DECODE_V1(0, bt)
    for (int g = 0; g < n_groups; g++) {
      simdgroup_barrier(mem_flags::mem_threadgroup);
      threadgroup float *cur = (g & 1) ? (bt + 512) : bt;
      threadgroup float *nxt = (g & 1) ? bt : (bt + 512);
      if (g + 1 < n_groups) GEMM_DECODE_V1(g + 1, nxt)
      simdgroup_matrix<float, 8, 8> B0, B1, A0, A1;
      simdgroup_load(B0, cur, 8);
      simdgroup_load(B1, cur + 64, 8);
      const int k0 = g * 16;
      for (int i2 = 0; i2 < mtiles; i2++) {
        simdgroup_load(A0, xg + (ulong)(seg_lo + mt0 + i2 * 8) * (ulong)k_dim + k0, (ulong)k_dim);
        simdgroup_load(A1, xg + (ulong)(seg_lo + mt0 + i2 * 8) * (ulong)k_dim + k0 + 8, (ulong)k_dim);
        simdgroup_multiply_accumulate(C[i2], A0, B0, C[i2]);
        simdgroup_multiply_accumulate(C[i2], A1, B1, C[i2]);
      }
    }
    simdgroup_barrier(mem_flags::mem_threadgroup);
#undef GEMM_DECODE_V1
    for (int i2 = 0; i2 < mtiles; i2++) {
      const int mt = mt0 + i2 * 8;
      const int m_rows = min(c - mt, 8);
      simdgroup_store(C[i2], st, 8);
      simdgroup_barrier(mem_flags::mem_threadgroup);
      for (int e2 = int(lane); e2 < 64; e2 += 32) {
        const int m = e2 >> 3;
        const int n = n0 + (e2 & 7);
        if (m < m_rows && n < n_rows) {
          const int pair = order[seg_lo + mt + m];
          y[pair * n_rows + n] = st[e2] * ws2;
        }
      }
      simdgroup_barrier(mem_flags::mem_threadgroup);
    }
  }
}


// Half-stored scores: 4.1 KB TG memory instead of 8.2 -> 2x occupancy.
kernel void sdpa_prefill_multi_hd256_hs(
  device const float *__restrict__ q       [[buffer(0)]],
  device const float *__restrict__ k_cache [[buffer(1)]],
  device const float *__restrict__ v_cache [[buffer(2)]],
  device       float *__restrict__ out     [[buffer(3)]],
  constant int &gqa_factor [[buffer(4)]],
  device const int *__restrict__ pos_start [[buffer(5)]],
  constant int &n_heads [[buffer(6)]],
  constant int &kv_dim  [[buffer(7)]],
  constant float &scale [[buffer(8)]],
  constant int &n_tok   [[buffer(9)]],
  uint tg  [[threadgroup_position_in_grid]],
  uint tid [[thread_position_in_threadgroup]]
) {
  threadgroup half scores[2051];
  threadgroup float qs[256];
  const int token = int(tg) / n_heads;
  const int q_head = int(tg) - token * n_heads;
  if (token >= n_tok) return;
  const int kv_head = q_head / gqa_factor;
  const int q_off = (token * n_heads + q_head) * 256;
  const int kv_base = kv_head * 256;
  const int usable = min(pos_start[0] + token + 1, 2051);
  qs[tid] = q[q_off + int(tid)];
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int p = int(tid); p < usable; p += 256) {
    device const float *kr = k_cache + kv_base + p * kv_dim;
    float dp = 0.0f;
    for (int i = 0; i < 256; i++) dp += qs[i] * kr[i];
    scores[p] = half(dp * scale);
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  // parallel softmax: 256-thread strided max/sum with simd + TG reduction
  threadgroup float red[8];
  float lmx = -INFINITY;
  for (int p = int(tid); p < usable; p += 256) lmx = max(lmx, float(scores[p]));
  float smx = simd_max(lmx);
  if ((tid & 31) == 0) red[tid >> 5] = smx;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float mx = max(max(max(red[0], red[1]), max(red[2], red[3])),
                 max(max(red[4], red[5]), max(red[6], red[7])));
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float lsum = 0.0f;
  for (int p = int(tid); p < usable; p += 256) {
    const float e = fast::exp(float(scores[p]) - mx);
    scores[p] = half(e);
    lsum += e;
  }
  float ssum = simd_sum(lsum);
  if ((tid & 31) == 0) red[tid >> 5] = ssum;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float denom = red[0] + red[1] + red[2] + red[3] + red[4] + red[5] + red[6] + red[7];
  const float inv = denom == 0.0f ? 0.0f : 1.0f / denom;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float result = 0.0f;
  for (int p = 0; p < usable; ++p) {
    result += float(scores[p]) * v_cache[kv_base + p * kv_dim + int(tid)];
  }
  out[q_off + int(tid)] = result * inv;
}



// bf16 -> f16 one-time weight conversion for the Neural-Accelerator path.
kernel void bf16_to_f16(
  device const ushort *__restrict__ src [[buffer(0)]],
  device       half   *__restrict__ dst [[buffer(1)]],
  constant int &n [[buffer(2)]],
  uint __tid [[thread_position_in_grid]]
) {
  if (int(__tid) >= n) return;
  dst[__tid] = half(as_type<float>(uint(src[__tid]) << 16));
}
