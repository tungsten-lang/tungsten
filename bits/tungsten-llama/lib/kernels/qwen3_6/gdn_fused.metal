// Fused GatedDeltaNet (GDN) Verify & Prompt Kernels for Qwen3.5 / Qwen3.6 / Qwen3.8.
//
// Ported from Layr-Labs/mlxfast-bonsai2-9b-engine (Qwen35.swift):
//   1. qwen35_gdn_dense_ba_rows:
//      Fused dense FP32 `in_proj_b` and `in_proj_a` across a 2..16-row verify
//      window in one launch. Each simdgroup owns one output column and reads
//      that weight row once for all rows.
//   2. qwen35_gdn_verify_fused (Qwen35FusedGDNVerify):
//      Single-launch 16-row GatedDeltaNet verify step fusing:
//        - 3-row conv_state + qkv concatenation (and detached conv_tail output)
//        - 4-tap depthwise conv1d + numerically stable SiLU
//        - Per-head 128-wide q/k RMSNorm with 128^-0.5 scaling
//        - Exact softplus/exp decay gate g and stable sigmoid beta
//        - Register-resident R=16, DVPL=2 recurrence across all T<=16 verify rows
//          using simd_shuffle_xor(4, 2, 1) reductions (8 lanes per 128-wide Dk).
//   3. qwen35_gdn_register_simd / qwen35_gdn_register_simd_state_only:
//      Standalone R=16, DVPL=2 register recurrence with STATE_ONLY mode for
//      rollback tape replay on partial speculative acceptance.
//   4. qwen35_gdn_prompt_conv_qk + qwen35_gdn_prompt_gated:
//      Prompt-width fused conv1d + SiLU + q/k RMSNorm and prompt-width
//      2-simdgroup register recurrence up to 2048 tokens.

#include <metal_stdlib>
using namespace metal;

static inline float qwen35_simd_gate_decay(float a, float bias, float negative_a) {
  #pragma clang fp reassociate(off)
  #pragma clang fp contract(off)
  const float x = a + bias;
  float sp;
  if (metal::isnan(x)) {
    sp = metal::numeric_limits<float>::quiet_NaN();
  } else {
    const float maximum = metal::max(x, 0.0f);
    const float minimum = metal::min(x, 0.0f);
    constexpr float infinity = metal::numeric_limits<float>::infinity();
    if (minimum == -infinity || maximum == infinity) {
      sp = maximum;
    } else {
      const float z = metal::exp(minimum - maximum);
      const float xp1 = 1.0f + z;
      const float logarithm = xp1 == metal::numeric_limits<float>::max()
        ? metal::numeric_limits<float>::max()
        : (xp1 == 1.0f ? z : z * (metal::log(xp1) / (xp1 - 1.0f)));
      sp = maximum + logarithm;
    }
  }
  return metal::precise::exp(negative_a * sp);
}

static inline float qwen35_simd_gate_beta(float b) {
  #pragma clang fp reassociate(off)
  #pragma clang fp contract(off)
  const float y = 1.0f / (1.0f + metal::exp(metal::abs(b)));
  return b < 0.0f ? y : 1.0f - y;
}

// ----------------------------------------------------------------------------
// 1. Dense FP32 [in_proj_b | in_proj_a] across 2..16 verify rows
// ----------------------------------------------------------------------------
[[max_total_threads_per_threadgroup(64)]]
kernel void qwen35_gdn_dense_ba_rows(
  device const float *x [[buffer(0)]],
  device const float *wb [[buffer(1)]],
  device const float *wa [[buffer(2)]],
  device float *b [[buffer(3)]],
  device float *a [[buffer(4)]],
  constant int &rows [[buffer(5)]],
  constant int &K [[buffer(6)]],
  constant int &N [[buffer(7)]],
  uint lane [[thread_index_in_simdgroup]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint2 tgid [[threadgroup_position_in_grid]]
) {
  const uint n = tgid.y * 2u + sg;
  if (n >= 2u * uint(N)) return;
  const bool is_a = n >= uint(N);
  const uint col = is_a ? (n - uint(N)) : n;
  const device float4 *wr = (const device float4 *)((is_a ? wa : wb) + col * uint(K));
  float acc[16];
  for (int v = 0; v < 16; v++) acc[v] = 0.0f;
  for (int k4 = int(lane); k4 < K / 4; k4 += 32) {
    const float4 wv = wr[k4];
    for (int v = 0; v < rows; v++) {
      const float4 xv = ((const device float4 *)(x + v * K))[k4];
      acc[v] = fma(xv.x, wv.x, acc[v]);
      acc[v] = fma(xv.y, wv.y, acc[v]);
      acc[v] = fma(xv.z, wv.z, acc[v]);
      acc[v] = fma(xv.w, wv.w, acc[v]);
    }
  }
  for (int v = 0; v < rows; v++) {
    const float total = simd_sum(acc[v]);
    if (lane == 0) (is_a ? a : b)[v * N + int(col)] = total;
  }
}

// ----------------------------------------------------------------------------
// 2. Single-Launch 16-Row Fused GDN Verify (Qwen35FusedGDNVerify)
//    Grid: (1, Dv / 32, B * Hv) threadgroups of 128 threads (4 simdgroups).
//    For Dk=128, Dv=128: grid = (1, 4, Hv), threadgroup = (128, 1, 1).
// ----------------------------------------------------------------------------
[[max_total_threads_per_threadgroup(128)]]
kernel void qwen35_gdn_verify_fused(
  device const float *conv_state [[buffer(0)]],   // [1, 3, C]
  device const float *qkv [[buffer(1)]],          // [1, T, C] (T <= 16)
  device const float *conv_weight [[buffer(2)]],  // [C, 4, 1]
  device const float *a [[buffer(3)]],            // [1, T, Hv]
  device const float *b [[buffer(4)]],            // [1, T, Hv]
  device const float *a_log [[buffer(5)]],        // [Hv]
  device const float *dt_bias [[buffer(6)]],      // [Hv]
  device const float *state_in [[buffer(7)]],     // [1, Hv, Dv, Dk]
  device float *conv_in [[buffer(8)]],            // [1, 3 + T, C]
  device float *conv_out [[buffer(9)]],           // [1, T, C]
  device float *q_out [[buffer(10)]],             // [1, T, Hk, Dk]
  device float *k_out [[buffer(11)]],             // [1, T, Hk, Dk]
  device float *y [[buffer(12)]],                 // [1, T, Hv, Dv]
  device float *state_out [[buffer(13)]],         // [1, Hv, Dv, Dk]
  device float *conv_tail [[buffer(14)]],         // [1, 3, C]
  constant int &T_in [[buffer(15)]],
  constant int &Hk [[buffer(16)]],
  constant int &Hv [[buffer(17)]],
  uint tid [[thread_index_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint3 tgid [[threadgroup_position_in_grid]]
) {
  constexpr int Dk = 128;
  constexpr int Dv = 128;
  constexpr int MAX_T = 16;
  constexpr int R = 16;
  constexpr int DVPL = 2;
  constexpr int LPD = Dk / R;            // 8 lanes per 128-wide Dk
  constexpr int DVPS = (32 / LPD) * DVPL; // 8 Dv cols per simdgroup
  constexpr int DVPT = DVPS * 4;         // 32 Dv cols per threadgroup
  constexpr uint EPS_BITS = 0x358637bdu;     // 1e-6f
  constexpr uint Q_SCALE_BITS = 0x3bfe0000u; // (128^-0.5)^2 = 1/128 = 0.0078125f
  constexpr uint K_SCALE_BITS = 0x3db504f3u; // 128^-0.5 = 0.0883883476f

  const uint T = uint(T_in);
  const uint C = uint(2 * Hk * Dk + Hv * Dv);
  threadgroup float qk_raw[2 * MAX_T * Dk];
  threadgroup float v_tile[MAX_T * DVPT];

  const uint n = tgid.z;
  const uint b_idx = n / uint(Hv);
  const uint hv_idx = n % uint(Hv);
  const uint hk_idx = hv_idx / uint(Hv / Hk);
  const uint dvblock = tgid.y;
  const bool owns_qk = (hv_idx % uint(Hv / Hk)) == 0u && dvblock == 0u;
  const uint dk0 = (lane % uint(LPD)) * uint(R);
  const uint dvlocal = sg * uint(DVPS) + (lane / uint(LPD)) * uint(DVPL);
  const uint dvbase = dvblock * uint(DVPT) + dvlocal;

  // Load recurrent state first to overlap with conv1d + RMSNorm below.
  float state[DVPL][R];
  #pragma clang loop unroll(full)
  for (int d = 0; d < DVPL; ++d) {
    const device float4 *s_in4 =
      (const device float4 *)(state_in + (n * uint(Dv) + dvbase + uint(d)) * uint(Dk) + dk0);
    #pragma clang loop unroll(full)
    for (int j = 0; j < R / 4; ++j) {
      const float4 s4 = s_in4[j];
      state[d][4 * j + 0] = s4.x;
      state[d][4 * j + 1] = s4.y;
      state[d][4 * j + 2] = s4.z;
      state[d][4 * j + 3] = s4.w;
    }
  }

  {
    #pragma clang fp reassociate(off)
    // Conv + SiLU of the q/k channels of key head hk_idx.
    #pragma clang loop unroll(full)
    for (uint part = 0; part < 2u; ++part) {
      const uint c = part * uint(Hk * Dk) + hk_idx * uint(Dk) + tid;
      float xin[3 + MAX_T];
      #pragma clang loop unroll(full)
      for (uint t = 0; t < 3u + uint(MAX_T); ++t) {
        if (t < 3u + T) xin[t] = t < 3u ? conv_state[t * C + c] : qkv[(t - 3u) * C + c];
      }
      const float4 w4 = ((const device float4 *)conv_weight)[c];
      const float w[4] = {w4.x, w4.y, w4.z, w4.w};
      if (owns_qk) {
        #pragma clang loop unroll(full)
        for (uint t = 0; t < 3u + uint(MAX_T); ++t) {
          if (t < 3u + T) {
            conv_in[t * C + c] = xin[t];
            if (t >= T) {
              const uint xb = as_type<uint>(xin[t]);
              conv_tail[(t - T) * C + c] = as_type<float>(xb == 0x80000000u ? 0u : xb);
            }
          }
        }
      }
      #pragma clang loop unroll(full)
      for (uint p = 0; p < uint(MAX_T); ++p) {
        if (p < T) {
          float acc = 0.0f;
          #pragma clang loop unroll(full)
          for (uint tap = 0; tap < 4u; ++tap) {
            acc = fma(xin[p + tap], w[tap], acc);
          }
          const float e = 1.0f / (1.0f + metal::exp(metal::abs(acc)));
          const float sig = acc < 0.0f ? e : 1.0f - e;
          const float out = acc * sig;
          qk_raw[(part * uint(MAX_T) + p) * uint(Dk) + tid] = out;
          if (owns_qk) conv_out[p * C + c] = out;
        }
      }
    }

    // Conv + SiLU for this threadgroup's 32 value channels.
    {
      const uint col = tid % uint(DVPT);
      const uint c = 2u * uint(Hk * Dk) + hv_idx * uint(Dv) + dvblock * uint(DVPT) + col;
      for (uint t = tid / uint(DVPT); t < 3u + T; t += 128u / uint(DVPT)) {
        const float xv = t < 3u ? conv_state[t * C + c] : qkv[(t - 3u) * C + c];
        conv_in[t * C + c] = xv;
        if (t >= T) {
          const uint xb = as_type<uint>(xv);
          conv_tail[(t - T) * C + c] = as_type<float>(xb == 0x80000000u ? 0u : xb);
        }
      }
      for (uint p = tid / uint(DVPT); p < T; p += 128u / uint(DVPT)) {
        float acc = 0.0f;
        for (uint tap = 0; tap < 4u; ++tap) {
          const uint r = p + tap;
          const float v = r < 3u ? conv_state[r * C + c] : qkv[(r - 3u) * C + c];
          acc = fma(v, conv_weight[c * 4u + tap], acc);
        }
        const float e = 1.0f / (1.0f + metal::exp(metal::abs(acc)));
        const float sig = acc < 0.0f ? e : 1.0f - e;
        const float out = acc * sig;
        v_tile[p * uint(DVPT) + col] = out;
        conv_out[p * C + c] = out;
      }
    }
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);

  {
    #pragma clang fp reassociate(off)
    // Per-head 128-wide q/k RMSNorm: one simdgroup per (row, q or k).
    for (uint job = sg; job < 2u * T; job += 4u) {
      const uint part = job % 2u;
      const uint t = job / 2u;
      threadgroup float *row = qk_raw + (part * uint(MAX_T) + t) * uint(Dk);
      const float4 x4 = ((threadgroup const float4 *)(row + lane * 4u))[0];
      const float x[4] = {x4.x, x4.y, x4.z, x4.w};
      float sum = 0.0f;
      for (int i = 0; i < 4; ++i) {
        sum += x[i] * x[i];
      }
      const float eps = as_type<float>(EPS_BITS);
      const float inv = metal::precise::rsqrt(simd_sum(sum) / 128.0f + eps);
      const float scale = as_type<float>(part == 0u ? Q_SCALE_BITS : K_SCALE_BITS);
      const float4 normed = float4(
        scale * (x[0] * inv),
        scale * (x[1] * inv),
        scale * (x[2] * inv),
        scale * (x[3] * inv)
      );
      ((threadgroup float4 *)(row + lane * 4u))[0] = normed;
      if (owns_qk) {
        device float *dst = (part == 0u ? q_out : k_out) + (t * uint(Hk) + hk_idx) * uint(Dk) + lane * 4u;
        ((device float4 *)dst)[0] = normed;
      }
    }
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);

  // Register recurrence reading q/k/v from threadgroup memory.
  threadgroup const float *q_ = qk_raw + dk0;
  threadgroup const float *k_ = qk_raw + uint(MAX_T * Dk) + dk0;
  threadgroup const float *v_ = v_tile + dvlocal;
  const device float *a_ = a + b_idx * T * uint(Hv) + hv_idx;
  const device float *bb_ = b + b_idx * T * uint(Hv) + hv_idx;
  float negative_a = 0.0f;
  float bias = 0.0f;
  if (lane == 0) {
    negative_a = -metal::precise::exp(a_log[hv_idx]);
    bias = dt_bias[hv_idx];
  }
  device float *y_ = y + (b_idx * T * uint(Hv) + hv_idx) * uint(Dv) + dvbase;
  float kr[R];
  float qr[R];
  for (int t = 0; t < int(T); ++t) {
    float local_g = 0.0f, local_beta = 0.0f;
    if (lane == 0) {
      local_g = qwen35_simd_gate_decay(a_[0], bias, negative_a);
      local_beta = qwen35_simd_gate_beta(bb_[0]);
    }
    const float gt = simd_broadcast(local_g, 0);
    const float bt = simd_broadcast(local_beta, 0);
    #pragma clang loop unroll(full)
    for (int j = 0; j < R / 4; ++j) {
      const float4 k4 = ((threadgroup const float4 *)k_)[j];
      kr[4 * j] = k4.x; kr[4 * j + 1] = k4.y; kr[4 * j + 2] = k4.z; kr[4 * j + 3] = k4.w;
      const float4 q4 = ((threadgroup const float4 *)q_)[j];
      qr[4 * j] = q4.x; qr[4 * j + 1] = q4.y; qr[4 * j + 2] = q4.z; qr[4 * j + 3] = q4.w;
    }
    float kv[DVPL];
    float vt[DVPL];
    const float2 v2 = *((threadgroup const float2 *)v_);
    vt[0] = v2.x; vt[1] = v2.y;
    #pragma clang loop unroll(full)
    for (int d = 0; d < DVPL; ++d) {
      float a0 = 0.f, a1 = 0.f, a2 = 0.f, a3 = 0.f;
      #pragma clang loop unroll(full)
      for (int j = 0; j < R / 4; ++j) {
        state[d][4 * j] *= gt; state[d][4 * j + 1] *= gt;
        state[d][4 * j + 2] *= gt; state[d][4 * j + 3] *= gt;
        a0 = fma(state[d][4 * j], kr[4 * j], a0);
        a1 = fma(state[d][4 * j + 1], kr[4 * j + 1], a1);
        a2 = fma(state[d][4 * j + 2], kr[4 * j + 2], a2);
        a3 = fma(state[d][4 * j + 3], kr[4 * j + 3], a3);
      }
      kv[d] = (a0 + a1) + (a2 + a3);
    }
    kv[0] += simd_shuffle_xor(kv[0], 4);
    kv[1] += simd_shuffle_xor(kv[1], 4);
    kv[0] += simd_shuffle_xor(kv[0], 2);
    kv[1] += simd_shuffle_xor(kv[1], 2);
    kv[0] += simd_shuffle_xor(kv[0], 1);
    kv[1] += simd_shuffle_xor(kv[1], 1);
    float out[DVPL];
    #pragma clang loop unroll(full)
    for (int d = 0; d < DVPL; ++d) {
      const float delta = (vt[d] - kv[d]) * bt;
      float o0 = 0.f, o1 = 0.f, o2 = 0.f, o3 = 0.f;
      #pragma clang loop unroll(full)
      for (int j = 0; j < R / 4; ++j) {
        state[d][4 * j] = fma(kr[4 * j], delta, state[d][4 * j]);
        state[d][4 * j + 1] = fma(kr[4 * j + 1], delta, state[d][4 * j + 1]);
        state[d][4 * j + 2] = fma(kr[4 * j + 2], delta, state[d][4 * j + 2]);
        state[d][4 * j + 3] = fma(kr[4 * j + 3], delta, state[d][4 * j + 3]);
        o0 = fma(state[d][4 * j], qr[4 * j], o0);
        o1 = fma(state[d][4 * j + 1], qr[4 * j + 1], o1);
        o2 = fma(state[d][4 * j + 2], qr[4 * j + 2], o2);
        o3 = fma(state[d][4 * j + 3], qr[4 * j + 3], o3);
      }
      out[d] = (o0 + o1) + (o2 + o3);
    }
    out[0] += simd_shuffle_xor(out[0], 4);
    out[1] += simd_shuffle_xor(out[1], 4);
    out[0] += simd_shuffle_xor(out[0], 2);
    out[1] += simd_shuffle_xor(out[1], 2);
    out[0] += simd_shuffle_xor(out[0], 1);
    out[1] += simd_shuffle_xor(out[1], 1);
    if (lane % uint(LPD) == 0u) {
      *((device float2 *)y_) = float2(out[0], out[1]);
    }
    q_ += Dk;
    y_ += uint(Hv * Dv);
    k_ += Dk;
    v_ += DVPT;
    a_ += uint(Hv);
    bb_ += uint(Hv);
  }
  #pragma clang loop unroll(full)
  for (int d = 0; d < DVPL; ++d) {
    device float4 *s_out4 =
      (device float4 *)(state_out + (n * uint(Dv) + dvbase + uint(d)) * uint(Dk) + dk0);
    #pragma clang loop unroll(full)
    for (int j = 0; j < R / 4; ++j) {
      s_out4[j] = float4(state[d][4 * j + 0], state[d][4 * j + 1], state[d][4 * j + 2], state[d][4 * j + 3]);
    }
  }
}

// ----------------------------------------------------------------------------
// 3. Register Recurrence with STATE_ONLY Rollback Replay (Qwen35RegisterGatedSIMD)
// ----------------------------------------------------------------------------
template <bool STATE_ONLY>
static inline void qwen35_gdn_register_simd_impl(
  device const float *q,
  device const float *k,
  device const float *v,
  device const float *a,
  device const float *b,
  device const float *a_log,
  device const float *dt_bias,
  device const float *state_in,
  device float *y,
  device float *state_out,
  uint T,
  uint Hk,
  uint Hv,
  uint lane,
  uint sg,
  uint3 tgid
) {
  constexpr int Dk = 128;
  constexpr int Dv = 128;
  constexpr int R = 16;
  constexpr int DVPL = 2;
  constexpr int LPD = Dk / R;
  constexpr int DVPS = (32 / LPD) * DVPL;
  constexpr int DVPT = DVPS * 4;
  const uint n = tgid.z;
  const uint b_idx = n / Hv;
  const uint hv_idx = n % Hv;
  const uint hk_idx = hv_idx / (Hv / Hk);
  const uint dk0 = (lane % uint(LPD)) * uint(R);
  const uint dvbase = tgid.y * uint(DVPT) + sg * uint(DVPS) + (lane / uint(LPD)) * uint(DVPL);
  const device float *q_ = q + (b_idx * T * Hk + hk_idx) * uint(Dk) + dk0;
  const device float *k_ = k + (b_idx * T * Hk + hk_idx) * uint(Dk) + dk0;
  const device float *v_ = v + (b_idx * T * Hv + hv_idx) * uint(Dv) + dvbase;
  const device float *a_ = a + b_idx * T * Hv + hv_idx;
  const device float *bb_ = b + b_idx * T * Hv + hv_idx;
  float negative_a = 0.0f;
  float bias = 0.0f;
  if (lane == 0) {
    negative_a = -metal::precise::exp(a_log[hv_idx]);
    bias = dt_bias[hv_idx];
  }
  device float *y_ = y + (b_idx * T * Hv + hv_idx) * uint(Dv) + dvbase;
  float state[DVPL][R];
  #pragma clang loop unroll(full)
  for (int d = 0; d < DVPL; ++d) {
    const device float4 *s_in4 =
      (const device float4 *)(state_in + (n * uint(Dv) + dvbase + uint(d)) * uint(Dk) + dk0);
    #pragma clang loop unroll(full)
    for (int j = 0; j < R / 4; ++j) {
      const float4 s4 = s_in4[j];
      state[d][4 * j + 0] = s4.x;
      state[d][4 * j + 1] = s4.y;
      state[d][4 * j + 2] = s4.z;
      state[d][4 * j + 3] = s4.w;
    }
  }
  float kr[R];
  float qr[R];
  for (uint t = 0; t < T; ++t) {
    float local_g = 0.0f, local_beta = 0.0f;
    if (lane == 0) {
      local_g = qwen35_simd_gate_decay(a_[0], bias, negative_a);
      local_beta = qwen35_simd_gate_beta(bb_[0]);
    }
    const float gt = simd_broadcast(local_g, 0);
    const float bt = simd_broadcast(local_beta, 0);
    #pragma clang loop unroll(full)
    for (int j = 0; j < R / 4; ++j) {
      const float4 k4 = ((const device float4 *)k_)[j];
      kr[4 * j] = k4.x; kr[4 * j + 1] = k4.y; kr[4 * j + 2] = k4.z; kr[4 * j + 3] = k4.w;
      if (!STATE_ONLY) {
        const float4 q4 = ((const device float4 *)q_)[j];
        qr[4 * j] = q4.x; qr[4 * j + 1] = q4.y; qr[4 * j + 2] = q4.z; qr[4 * j + 3] = q4.w;
      }
    }
    float kv[DVPL];
    float vt[DVPL];
    const float2 v2 = *((const device float2 *)v_);
    vt[0] = v2.x; vt[1] = v2.y;
    #pragma clang loop unroll(full)
    for (int d = 0; d < DVPL; ++d) {
      float a0 = 0.f, a1 = 0.f, a2 = 0.f, a3 = 0.f;
      #pragma clang loop unroll(full)
      for (int j = 0; j < R / 4; ++j) {
        state[d][4 * j] *= gt; state[d][4 * j + 1] *= gt;
        state[d][4 * j + 2] *= gt; state[d][4 * j + 3] *= gt;
        a0 = fma(state[d][4 * j], kr[4 * j], a0);
        a1 = fma(state[d][4 * j + 1], kr[4 * j + 1], a1);
        a2 = fma(state[d][4 * j + 2], kr[4 * j + 2], a2);
        a3 = fma(state[d][4 * j + 3], kr[4 * j + 3], a3);
      }
      kv[d] = (a0 + a1) + (a2 + a3);
    }
    kv[0] += simd_shuffle_xor(kv[0], 4);
    kv[1] += simd_shuffle_xor(kv[1], 4);
    kv[0] += simd_shuffle_xor(kv[0], 2);
    kv[1] += simd_shuffle_xor(kv[1], 2);
    kv[0] += simd_shuffle_xor(kv[0], 1);
    kv[1] += simd_shuffle_xor(kv[1], 1);
    if (STATE_ONLY) {
      #pragma clang loop unroll(full)
      for (int d = 0; d < DVPL; ++d) {
        const float delta = (vt[d] - kv[d]) * bt;
        #pragma clang loop unroll(full)
        for (int j = 0; j < R / 4; ++j) {
          state[d][4 * j] = fma(kr[4 * j], delta, state[d][4 * j]);
          state[d][4 * j + 1] = fma(kr[4 * j + 1], delta, state[d][4 * j + 1]);
          state[d][4 * j + 2] = fma(kr[4 * j + 2], delta, state[d][4 * j + 2]);
          state[d][4 * j + 3] = fma(kr[4 * j + 3], delta, state[d][4 * j + 3]);
        }
      }
    } else {
      float out[DVPL];
      #pragma clang loop unroll(full)
      for (int d = 0; d < DVPL; ++d) {
        const float delta = (vt[d] - kv[d]) * bt;
        float o0 = 0.f, o1 = 0.f, o2 = 0.f, o3 = 0.f;
        #pragma clang loop unroll(full)
        for (int j = 0; j < R / 4; ++j) {
          state[d][4 * j] = fma(kr[4 * j], delta, state[d][4 * j]);
          state[d][4 * j + 1] = fma(kr[4 * j + 1], delta, state[d][4 * j + 1]);
          state[d][4 * j + 2] = fma(kr[4 * j + 2], delta, state[d][4 * j + 2]);
          state[d][4 * j + 3] = fma(kr[4 * j + 3], delta, state[d][4 * j + 3]);
          o0 = fma(state[d][4 * j], qr[4 * j], o0);
          o1 = fma(state[d][4 * j + 1], qr[4 * j + 1], o1);
          o2 = fma(state[d][4 * j + 2], qr[4 * j + 2], o2);
          o3 = fma(state[d][4 * j + 3], qr[4 * j + 3], o3);
        }
        out[d] = (o0 + o1) + (o2 + o3);
      }
      out[0] += simd_shuffle_xor(out[0], 4);
      out[1] += simd_shuffle_xor(out[1], 4);
      out[0] += simd_shuffle_xor(out[0], 2);
      out[1] += simd_shuffle_xor(out[1], 2);
      out[0] += simd_shuffle_xor(out[0], 1);
      out[1] += simd_shuffle_xor(out[1], 1);
      if (lane % uint(LPD) == 0u) {
        *((device float2 *)y_) = float2(out[0], out[1]);
      }
      q_ += Hk * uint(Dk);
      y_ += Hv * uint(Dv);
    }
    k_ += Hk * uint(Dk);
    v_ += Hv * uint(Dv);
    a_ += Hv;
    bb_ += Hv;
  }
  #pragma clang loop unroll(full)
  for (int d = 0; d < DVPL; ++d) {
    device float4 *s_out4 =
      (device float4 *)(state_out + (n * uint(Dv) + dvbase + uint(d)) * uint(Dk) + dk0);
    #pragma clang loop unroll(full)
    for (int j = 0; j < R / 4; ++j) {
      s_out4[j] = float4(state[d][4 * j + 0], state[d][4 * j + 1], state[d][4 * j + 2], state[d][4 * j + 3]);
    }
  }
}

[[max_total_threads_per_threadgroup(128)]]
kernel void qwen35_gdn_register_simd(
  device const float *q [[buffer(0)]],
  device const float *k [[buffer(1)]],
  device const float *v [[buffer(2)]],
  device const float *a [[buffer(3)]],
  device const float *b [[buffer(4)]],
  device const float *a_log [[buffer(5)]],
  device const float *dt_bias [[buffer(6)]],
  device const float *state_in [[buffer(7)]],
  device float *y [[buffer(8)]],
  device float *state_out [[buffer(9)]],
  constant int &T [[buffer(10)]],
  constant int &Hk [[buffer(11)]],
  constant int &Hv [[buffer(12)]],
  uint lane [[thread_index_in_simdgroup]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint3 tgid [[threadgroup_position_in_grid]]
) {
  qwen35_gdn_register_simd_impl<false>(
    q, k, v, a, b, a_log, dt_bias, state_in, y, state_out, uint(T), uint(Hk), uint(Hv), lane, sg, tgid);
}

[[max_total_threads_per_threadgroup(128)]]
kernel void qwen35_gdn_register_simd_state_only(
  device const float *k [[buffer(0)]],
  device const float *v [[buffer(1)]],
  device const float *a [[buffer(2)]],
  device const float *b [[buffer(3)]],
  device const float *a_log [[buffer(4)]],
  device const float *dt_bias [[buffer(5)]],
  device const float *state_in [[buffer(6)]],
  device float *state_out [[buffer(7)]],
  constant int &T [[buffer(8)]],
  constant int &Hk [[buffer(9)]],
  constant int &Hv [[buffer(10)]],
  uint lane [[thread_index_in_simdgroup]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint3 tgid [[threadgroup_position_in_grid]]
) {
  qwen35_gdn_register_simd_impl<true>(
    k, k, v, a, b, a_log, dt_bias, state_in, state_out, state_out, uint(T), uint(Hk), uint(Hv), lane, sg, tgid);
}

// ----------------------------------------------------------------------------
// 4. Prompt-Width Fused Conv+SiLU+QK-RMSNorm & Gated Register Recurrence
// ----------------------------------------------------------------------------
[[max_total_threads_per_threadgroup(32)]]
kernel void qwen35_gdn_prompt_conv_qk(
  device const float *state [[buffer(0)]],
  device const float *qkv [[buffer(1)]],
  device const float *conv_weight [[buffer(2)]],
  device float *q_out [[buffer(3)]],
  device float *k_out [[buffer(4)]],
  device float *v_out [[buffer(5)]],
  constant int &Hk [[buffer(6)]],
  constant int &Hv [[buffer(7)]],
  uint lane [[thread_index_in_simdgroup]],
  uint2 tgid [[threadgroup_position_in_grid]]
) {
  #pragma clang fp reassociate(off)
  constexpr uint EPS_BITS = 0x358637bdu;
  constexpr uint Q_SCALE_BITS = 0x3bfe0000u;
  constexpr uint K_SCALE_BITS = 0x3db504f3u;
  const uint groups = uint(2 * Hk + Hv);
  const uint t = tgid.y / groups;
  const uint gi = tgid.y % groups;
  const uint C = groups * 128u;
  const uint c0 = gi * 128u + lane * 4u;
  float val[4];
  for (int i = 0; i < 4; ++i) {
    const uint c = c0 + uint(i);
    float acc = 0.0f;
    for (uint tap = 0; tap < 4u; ++tap) {
      const uint r = t + tap;
      const float v = r < 3u ? state[r * C + c] : qkv[(r - 3u) * C + c];
      acc = fma(v, conv_weight[c * 4u + tap], acc);
    }
    const float e = 1.0f / (1.0f + metal::exp(metal::abs(acc)));
    const float sig = acc < 0.0f ? e : 1.0f - e;
    val[i] = acc * sig;
  }
  if (gi >= uint(2 * Hk)) {
    const uint o = (t * uint(Hv) + (gi - uint(2 * Hk))) * 128u + lane * 4u;
    ((device float4 *)(v_out + o))[0] = float4(val[0], val[1], val[2], val[3]);
    return;
  }
  float sum = 0.0f;
  for (int i = 0; i < 4; ++i) {
    sum += val[i] * val[i];
  }
  const float eps = as_type<float>(EPS_BITS);
  const float inv = metal::precise::rsqrt(simd_sum(sum) / 128.0f + eps);
  const bool is_q = gi < uint(Hk);
  const float scale = as_type<float>(is_q ? Q_SCALE_BITS : K_SCALE_BITS);
  const uint o = (t * uint(Hk) + (is_q ? gi : gi - uint(Hk))) * 128u + lane * 4u;
  ((device float4 *)((is_q ? q_out : k_out) + o))[0] = float4(
    scale * (val[0] * inv),
    scale * (val[1] * inv),
    scale * (val[2] * inv),
    scale * (val[3] * inv)
  );
}

[[max_total_threads_per_threadgroup(64)]]
kernel void qwen35_gdn_prompt_gated(
  device const float *q [[buffer(0)]],
  device const float *k [[buffer(1)]],
  device const float *v [[buffer(2)]],
  device const float *ba [[buffer(3)]],
  device const float *a_log [[buffer(4)]],
  device const float *dt_bias [[buffer(5)]],
  device const float *state_in [[buffer(6)]],
  device float *y [[buffer(7)]],
  device float *state_out [[buffer(8)]],
  constant int &T_in [[buffer(9)]],
  constant int &Hk_in [[buffer(10)]],
  constant int &Hv_in [[buffer(11)]],
  uint tid [[thread_index_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint3 tgid [[threadgroup_position_in_grid]]
) {
  constexpr int Dk = 128;
  constexpr int Dv = 128;
  constexpr int MAX_T = 2048;
  constexpr int R = 16;
  constexpr int DVPL = 2;
  constexpr int LPD = Dk / R;
  constexpr int DVPS = (32 / LPD) * DVPL;
  constexpr int DVPT = DVPS * 2;
  const uint T = uint(T_in);
  const uint Hk = uint(Hk_in);
  const uint Hv = uint(Hv_in);
  const uint n = tgid.z;
  const uint b_idx = n / Hv;
  const uint hv_idx = n % Hv;
  const uint hk_idx = hv_idx / (Hv / Hk);
  threadgroup float gate_g[MAX_T];
  threadgroup float gate_beta[MAX_T];
  {
    const float negative_a = -metal::precise::exp(a_log[hv_idx]);
    const float bias = dt_bias[hv_idx];
    const device float *ba_ = ba + b_idx * T * (2u * Hv);
    for (uint t = tid; t < T; t += 64u) {
      gate_g[t] = qwen35_simd_gate_decay(ba_[t * (2u * Hv) + Hv + hv_idx], bias, negative_a);
      gate_beta[t] = qwen35_simd_gate_beta(ba_[t * (2u * Hv) + hv_idx]);
    }
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  const uint dk0 = (lane % uint(LPD)) * uint(R);
  const uint dvbase = tgid.y * uint(DVPT) + sg * uint(DVPS) + (lane / uint(LPD)) * uint(DVPL);
  const device float *q_ = q + (b_idx * T * Hk + hk_idx) * uint(Dk) + dk0;
  const device float *k_ = k + (b_idx * T * Hk + hk_idx) * uint(Dk) + dk0;
  const device float *v_ = v + (b_idx * T * Hv + hv_idx) * uint(Dv) + dvbase;
  device float *y_ = y + (b_idx * T * Hv + hv_idx) * uint(Dv) + dvbase;
  float state[DVPL][R];
  #pragma clang loop unroll(full)
  for (int d = 0; d < DVPL; ++d) {
    const device float4 *s_in4 =
      (const device float4 *)(state_in + (n * uint(Dv) + dvbase + uint(d)) * uint(Dk) + dk0);
    #pragma clang loop unroll(full)
    for (int j = 0; j < R / 4; ++j) {
      const float4 s4 = s_in4[j];
      state[d][4 * j + 0] = s4.x;
      state[d][4 * j + 1] = s4.y;
      state[d][4 * j + 2] = s4.z;
      state[d][4 * j + 3] = s4.w;
    }
  }
  float kr[R];
  float qr[R];
  for (uint t = 0; t < T; ++t) {
    const float gt = gate_g[t];
    const float bt = gate_beta[t];
    #pragma clang loop unroll(full)
    for (int j = 0; j < R / 4; ++j) {
      const float4 k4 = ((const device float4 *)k_)[j];
      kr[4 * j] = k4.x; kr[4 * j + 1] = k4.y; kr[4 * j + 2] = k4.z; kr[4 * j + 3] = k4.w;
      const float4 q4 = ((const device float4 *)q_)[j];
      qr[4 * j] = q4.x; qr[4 * j + 1] = q4.y; qr[4 * j + 2] = q4.z; qr[4 * j + 3] = q4.w;
    }
    float kv[DVPL];
    float vt[DVPL];
    #pragma clang loop unroll(full)
    for (int d = 0; d < DVPL; ++d) {
      vt[d] = v_[d];
      float a0 = 0.f, a1 = 0.f, a2 = 0.f, a3 = 0.f;
      #pragma clang loop unroll(full)
      for (int j = 0; j < R / 4; ++j) {
        state[d][4 * j] *= gt; state[d][4 * j + 1] *= gt;
        state[d][4 * j + 2] *= gt; state[d][4 * j + 3] *= gt;
        a0 = fma(state[d][4 * j], kr[4 * j], a0);
        a1 = fma(state[d][4 * j + 1], kr[4 * j + 1], a1);
        a2 = fma(state[d][4 * j + 2], kr[4 * j + 2], a2);
        a3 = fma(state[d][4 * j + 3], kr[4 * j + 3], a3);
      }
      kv[d] = (a0 + a1) + (a2 + a3);
    }
    kv[0] += simd_shuffle_xor(kv[0], 4);
    kv[1] += simd_shuffle_xor(kv[1], 4);
    kv[0] += simd_shuffle_xor(kv[0], 2);
    kv[1] += simd_shuffle_xor(kv[1], 2);
    kv[0] += simd_shuffle_xor(kv[0], 1);
    kv[1] += simd_shuffle_xor(kv[1], 1);
    float out[DVPL];
    #pragma clang loop unroll(full)
    for (int d = 0; d < DVPL; ++d) {
      const float delta = (vt[d] - kv[d]) * bt;
      float o0 = 0.f, o1 = 0.f, o2 = 0.f, o3 = 0.f;
      #pragma clang loop unroll(full)
      for (int j = 0; j < R / 4; ++j) {
        state[d][4 * j] = fma(kr[4 * j], delta, state[d][4 * j]);
        state[d][4 * j + 1] = fma(kr[4 * j + 1], delta, state[d][4 * j + 1]);
        state[d][4 * j + 2] = fma(kr[4 * j + 2], delta, state[d][4 * j + 2]);
        state[d][4 * j + 3] = fma(kr[4 * j + 3], delta, state[d][4 * j + 3]);
        o0 = fma(state[d][4 * j], qr[4 * j], o0);
        o1 = fma(state[d][4 * j + 1], qr[4 * j + 1], o1);
        o2 = fma(state[d][4 * j + 2], qr[4 * j + 2], o2);
        o3 = fma(state[d][4 * j + 3], qr[4 * j + 3], o3);
      }
      out[d] = (o0 + o1) + (o2 + o3);
    }
    out[0] += simd_shuffle_xor(out[0], 4);
    out[1] += simd_shuffle_xor(out[1], 4);
    out[0] += simd_shuffle_xor(out[0], 2);
    out[1] += simd_shuffle_xor(out[1], 2);
    out[0] += simd_shuffle_xor(out[0], 1);
    out[1] += simd_shuffle_xor(out[1], 1);
    if (lane % uint(LPD) == 0u) {
      for (int d = 0; d < DVPL; ++d) {
        y_[d] = out[d];
      }
    }
    q_ += Hk * uint(Dk);
    k_ += Hk * uint(Dk);
    v_ += Hv * uint(Dv);
    y_ += Hv * uint(Dv);
  }
  #pragma clang loop unroll(full)
  for (int d = 0; d < DVPL; ++d) {
    device float4 *s_out4 =
      (device float4 *)(state_out + (n * uint(Dv) + dvbase + uint(d)) * uint(Dk) + dk0);
    #pragma clang loop unroll(full)
    for (int j = 0; j < R / 4; ++j) {
      s_out4[j] = float4(state[d][4 * j + 0], state[d][4 * j + 1], state[d][4 * j + 2], state[d][4 * j + 3]);
    }
  }
}

// ----------------------------------------------------------------------------
// 5. In-Kernel Lazy Recurrent Rollback + Replay Verify Kernel
//    (`qwen35_gdn_verify_lazy_rollback`, ported from `cudafast-bonsai2-9b-engine`
//    `llama.cpp/ggml/src/ggml-cuda/gated_delta_net_kernel.cuh`)
//
//    Eliminates both eager per-token 2 MB state snapshots (32 MB for 16 verify
//    tokens) and separate post-verify host-launched state-repair kernels:
//    - `state_io` `[B * Hv, Dv, Dk]` holds the base state at the start of the
//      previous verify window.
//    - `record_io` `[B * Hv, MAX_W, Dk + Dv + 2]` holds the compact per-token
//      inputs `(k[128], v[128], g, beta)` from the previous verify window
//      (258 floats/head/token = 528 KB total vs 32 MB for 16 full snapshots).
//    - On entry to verify round N+1, if `replay_tokens > 0` (`1 + accepted` from
//      round N), each threadgroup replays `0 ..< replay_tokens` in registers
//      from `record_io`, commits the new base state to `state_io`, and
//      immediately executes the new `T` verify tokens while recording their
//      compact `(k, v, g, beta)` tuples into `record_io`.
// ----------------------------------------------------------------------------
[[max_total_threads_per_threadgroup(128)]]
kernel void qwen35_gdn_verify_lazy_rollback(
  device const float *q [[buffer(0)]],
  device const float *k [[buffer(1)]],
  device const float *v [[buffer(2)]],
  device const float *a [[buffer(3)]],
  device const float *b [[buffer(4)]],
  device const float *a_log [[buffer(5)]],
  device const float *dt_bias [[buffer(6)]],
  device float *state_io [[buffer(7)]],
  device float *record_io [[buffer(8)]],
  device float *y [[buffer(9)]],
  constant int &T_in [[buffer(10)]],
  constant int &replay_tokens_in [[buffer(11)]],
  constant int &Hk_in [[buffer(12)]],
  constant int &Hv_in [[buffer(13)]],
  uint lane [[thread_index_in_simdgroup]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint3 tgid [[threadgroup_position_in_grid]]
) {
  constexpr int Dk = 128;
  constexpr int Dv = 128;
  constexpr int R = 16;
  constexpr int DVPL = 2;
  constexpr int LPD = Dk / R;
  constexpr int DVPS = (32 / LPD) * DVPL;
  constexpr int DVPT = DVPS * 4;
  constexpr int MAX_W = 16;
  constexpr int REC_STRIDE = Dk + DVPT + 2;

  const uint T = uint(T_in);
  const uint replay_tokens = uint(max(0, min(replay_tokens_in, MAX_W)));
  const uint Hk = uint(Hk_in);
  const uint Hv = uint(Hv_in);
  const uint n = tgid.z;
  const uint b_idx = n / Hv;
  const uint hv_idx = n % Hv;
  const uint hk_idx = hv_idx / (Hv / Hk);
  const uint dk0 = (lane % uint(LPD)) * uint(R);
  const uint dv_local = sg * uint(DVPS) + (lane / uint(LPD)) * uint(DVPL);
  const uint dvbase = tgid.y * uint(DVPT) + dv_local;

  float state[DVPL][R];
  #pragma clang loop unroll(full)
  for (int d = 0; d < DVPL; ++d) {
    const device float4 *s_in4 =
      (const device float4 *)(state_io + (n * uint(Dv) + dvbase + uint(d)) * uint(Dk) + dk0);
    #pragma clang loop unroll(full)
    for (int j = 0; j < R / 4; ++j) {
      const float4 s4 = s_in4[j];
      state[d][4 * j + 0] = s4.x;
      state[d][4 * j + 1] = s4.y;
      state[d][4 * j + 2] = s4.z;
      state[d][4 * j + 3] = s4.w;
    }
  }

  device float *tg_rec = record_io + (n * 2u + tgid.y) * uint(MAX_W * REC_STRIDE);
  float kr[R];
  float qr[R];

  // Phase 1: Lazily replay accepted tokens from the previous verify window in registers
  if (replay_tokens > 0u) {
    for (uint rt = 0; rt < replay_tokens; ++rt) {
      const device float *rec_t = tg_rec + rt * uint(REC_STRIDE);
      const float gt = rec_t[Dk + DVPT + 0];
      const float bt = rec_t[Dk + DVPT + 1];
      const device float4 *rk4 = (const device float4 *)(rec_t + dk0);
      #pragma clang loop unroll(full)
      for (int j = 0; j < R / 4; ++j) {
        const float4 k4 = rk4[j];
        kr[4 * j + 0] = k4.x;
        kr[4 * j + 1] = k4.y;
        kr[4 * j + 2] = k4.z;
        kr[4 * j + 3] = k4.w;
      }
      const float2 rv2 = *((const device float2 *)(rec_t + uint(Dk) + dv_local));
      float vt[DVPL] = {rv2.x, rv2.y};
      float kv[DVPL];
      #pragma clang loop unroll(full)
      for (int d = 0; d < DVPL; ++d) {
        float a0 = 0.f, a1 = 0.f, a2 = 0.f, a3 = 0.f;
        #pragma clang loop unroll(full)
        for (int j = 0; j < R / 4; ++j) {
          state[d][4 * j + 0] *= gt;
          state[d][4 * j + 1] *= gt;
          state[d][4 * j + 2] *= gt;
          state[d][4 * j + 3] *= gt;
          a0 = fma(state[d][4 * j + 0], kr[4 * j + 0], a0);
          a1 = fma(state[d][4 * j + 1], kr[4 * j + 1], a1);
          a2 = fma(state[d][4 * j + 2], kr[4 * j + 2], a2);
          a3 = fma(state[d][4 * j + 3], kr[4 * j + 3], a3);
        }
        kv[d] = (a0 + a1) + (a2 + a3);
      }
      kv[0] += simd_shuffle_xor(kv[0], 4);
      kv[1] += simd_shuffle_xor(kv[1], 4);
      kv[0] += simd_shuffle_xor(kv[0], 2);
      kv[1] += simd_shuffle_xor(kv[1], 2);
      kv[0] += simd_shuffle_xor(kv[0], 1);
      kv[1] += simd_shuffle_xor(kv[1], 1);
      #pragma clang loop unroll(full)
      for (int d = 0; d < DVPL; ++d) {
        const float delta = (vt[d] - kv[d]) * bt;
        #pragma clang loop unroll(full)
        for (int j = 0; j < R / 4; ++j) {
          state[d][4 * j + 0] = fma(kr[4 * j + 0], delta, state[d][4 * j + 0]);
          state[d][4 * j + 1] = fma(kr[4 * j + 1], delta, state[d][4 * j + 1]);
          state[d][4 * j + 2] = fma(kr[4 * j + 2], delta, state[d][4 * j + 2]);
          state[d][4 * j + 3] = fma(kr[4 * j + 3], delta, state[d][4 * j + 3]);
        }
      }
    }
    // Commit replayed base state to `state_io` and synchronize threadgroup before overwriting `tg_rec`
    #pragma clang loop unroll(full)
    for (int d = 0; d < DVPL; ++d) {
      device float4 *s_out4 =
        (device float4 *)(state_io + (n * uint(Dv) + dvbase + uint(d)) * uint(Dk) + dk0);
      #pragma clang loop unroll(full)
      for (int j = 0; j < R / 4; ++j) {
        s_out4[j] = float4(state[d][4 * j + 0], state[d][4 * j + 1], state[d][4 * j + 2], state[d][4 * j + 3]);
      }
    }
    threadgroup_barrier(mem_flags::mem_device);
  }

  // Phase 2: Execute current verify window and record compact per-token inputs into `tg_rec`
  const device float *q_ = q + (b_idx * T * Hk + hk_idx) * uint(Dk) + dk0;
  const device float *k_ = k + (b_idx * T * Hk + hk_idx) * uint(Dk) + dk0;
  const device float *v_ = v + (b_idx * T * Hv + hv_idx) * uint(Dv) + dvbase;
  const device float *a_ = a + b_idx * T * Hv + hv_idx;
  const device float *bb_ = b + b_idx * T * Hv + hv_idx;
  device float *y_ = y + (b_idx * T * Hv + hv_idx) * uint(Dv) + dvbase;

  float negative_a = 0.0f;
  float bias = 0.0f;
  if (lane == 0) {
    negative_a = -metal::precise::exp(a_log[hv_idx]);
    bias = dt_bias[hv_idx];
  }

  for (uint t = 0; t < T; ++t) {
    float local_g = 0.0f, local_beta = 0.0f;
    if (lane == 0) {
      local_g = qwen35_simd_gate_decay(a_[0], bias, negative_a);
      local_beta = qwen35_simd_gate_beta(bb_[0]);
    }
    const float gt = simd_broadcast(local_g, 0);
    const float bt = simd_broadcast(local_beta, 0);
    #pragma clang loop unroll(full)
    for (int j = 0; j < R / 4; ++j) {
      const float4 k4 = ((const device float4 *)k_)[j];
      kr[4 * j + 0] = k4.x; kr[4 * j + 1] = k4.y; kr[4 * j + 2] = k4.z; kr[4 * j + 3] = k4.w;
      const float4 q4 = ((const device float4 *)q_)[j];
      qr[4 * j + 0] = q4.x; qr[4 * j + 1] = q4.y; qr[4 * j + 2] = q4.z; qr[4 * j + 3] = q4.w;
    }
    const float2 v2 = *((const device float2 *)v_);
    float vt[DVPL] = {v2.x, v2.y};

    // Store compact per-threadgroup record for lazy rollback on next verify step
    if (t < uint(MAX_W)) {
      device float *rec_t = tg_rec + t * uint(REC_STRIDE);
      if (sg == 0u && lane < uint(LPD)) {
        device float4 *rk4 = (device float4 *)(rec_t + dk0);
        #pragma clang loop unroll(full)
        for (int j = 0; j < R / 4; ++j) {
          rk4[j] = float4(kr[4 * j + 0], kr[4 * j + 1], kr[4 * j + 2], kr[4 * j + 3]);
        }
        if (lane == 0u) {
          rec_t[Dk + DVPT + 0] = gt;
          rec_t[Dk + DVPT + 1] = bt;
        }
      }
      if (lane % uint(LPD) == 0u) {
        *((device float2 *)(rec_t + uint(Dk) + dv_local)) = v2;
      }
    }

    float kv[DVPL];
    #pragma clang loop unroll(full)
    for (int d = 0; d < DVPL; ++d) {
      float a0 = 0.f, a1 = 0.f, a2 = 0.f, a3 = 0.f;
      #pragma clang loop unroll(full)
      for (int j = 0; j < R / 4; ++j) {
        state[d][4 * j + 0] *= gt; state[d][4 * j + 1] *= gt;
        state[d][4 * j + 2] *= gt; state[d][4 * j + 3] *= gt;
        a0 = fma(state[d][4 * j + 0], kr[4 * j + 0], a0);
        a1 = fma(state[d][4 * j + 1], kr[4 * j + 1], a1);
        a2 = fma(state[d][4 * j + 2], kr[4 * j + 2], a2);
        a3 = fma(state[d][4 * j + 3], kr[4 * j + 3], a3);
      }
      kv[d] = (a0 + a1) + (a2 + a3);
    }
    kv[0] += simd_shuffle_xor(kv[0], 4);
    kv[1] += simd_shuffle_xor(kv[1], 4);
    kv[0] += simd_shuffle_xor(kv[0], 2);
    kv[1] += simd_shuffle_xor(kv[1], 2);
    kv[0] += simd_shuffle_xor(kv[0], 1);
    kv[1] += simd_shuffle_xor(kv[1], 1);

    float out[DVPL];
    #pragma clang loop unroll(full)
    for (int d = 0; d < DVPL; ++d) {
      const float delta = (vt[d] - kv[d]) * bt;
      float o0 = 0.f, o1 = 0.f, o2 = 0.f, o3 = 0.f;
      #pragma clang loop unroll(full)
      for (int j = 0; j < R / 4; ++j) {
        state[d][4 * j + 0] = fma(kr[4 * j + 0], delta, state[d][4 * j + 0]);
        state[d][4 * j + 1] = fma(kr[4 * j + 1], delta, state[d][4 * j + 1]);
        state[d][4 * j + 2] = fma(kr[4 * j + 2], delta, state[d][4 * j + 2]);
        state[d][4 * j + 3] = fma(kr[4 * j + 3], delta, state[d][4 * j + 3]);
        o0 = fma(state[d][4 * j + 0], qr[4 * j + 0], o0);
        o1 = fma(state[d][4 * j + 1], qr[4 * j + 1], o1);
        o2 = fma(state[d][4 * j + 2], qr[4 * j + 2], o2);
        o3 = fma(state[d][4 * j + 3], qr[4 * j + 3], o3);
      }
      out[d] = (o0 + o1) + (o2 + o3);
    }
    out[0] += simd_shuffle_xor(out[0], 4);
    out[1] += simd_shuffle_xor(out[1], 4);
    out[0] += simd_shuffle_xor(out[0], 2);
    out[1] += simd_shuffle_xor(out[1], 2);
    out[0] += simd_shuffle_xor(out[0], 1);
    out[1] += simd_shuffle_xor(out[1], 1);
    if (lane % uint(LPD) == 0u) {
      *((device float2 *)y_) = float2(out[0], out[1]);
    }
    q_ += Hk * uint(Dk);
    k_ += Hk * uint(Dk);
    v_ += Hv * uint(Dv);
    y_ += Hv * uint(Dv);
    a_ += Hv;
    bb_ += Hv;
  }
}

