// Width-n (runtime batch) variants of the Qwen3.8-Flash-Next-specific ops,
// for MTP width-n verify and multi-stream "aggregate" decode. The GDN and
// attention chains reuse the 27B decode_multi.metal family (identical head
// geometry); these cover what flash-next adds: hyper-connections, the
// 512-expert MoE, and the batched NVFP4 expert gather.
//
// Batch layout convention: token-major — every per-token tensor T of width W
// becomes [n, W] with token t at offset t*W.

#include <metal_stdlib>
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
}
