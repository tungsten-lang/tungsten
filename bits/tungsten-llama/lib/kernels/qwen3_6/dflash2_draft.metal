// DFlash2 block-diffusion drafter (z-lab/Qwen3.8-27B-DFlash2) for tungsten.
//
// The drafter is a 5-layer qwen3 transformer (hidden 5120, 32/8 heads, head
// dim 128, full RoPE base 1e7) that fills a block of [anchor, MASK x 7] in one
// pass, conditioned on five target hidden taps per committed position, with
// two-tap grouped dynamic convolutions around attention and MLP, and a
// rank-256 codebook selector that walks one path through the per-position
// top-16 candidates. Weights are bf16 (mmap'd, decoded on the fly); all
// activations are f32 -- the proposal side is free, only the target verify
// has to be exact. Row counts are runtime (n_tok <= 8).
//
// Reference: dflash/model_mlx.py (DFlash2DecoderLayer, GroupedDynamicCausalConv,
// CandidateSelector) and dflash_mlx/draft/dflash2.py.

#include <metal_stdlib>
#include <metal_tensor>
#include <MetalPerformancePrimitives/MetalPerformancePrimitives.h>
using namespace metal;

constant int DRAFT_MAX_TOK = 16;
constant int DRAFT_MAX_POS = 640;
constant int DRAFT_TOPK = 16;
constant int DRAFT_RANK = 256;

static inline float bf16d_to_f32(ushort b) {
  return as_type<float>(uint(b) << 16);
}
static inline float bf16d_lo(uint w) { return as_type<float>(w << 16); }
static inline float bf16d_hi(uint w) { return as_type<float>(w & 0xffff0000u); }

// y[b * n_rows + row] (=|+=) dot(w[row], x[b]) for b < n_tok. bf16 weights
// [n_rows, k_dim] (k_dim a multiple of 256), f32 activations [n_tok, k_dim].
// Each SIMD group owns ROWS output rows; a lane covers 8 consecutive k per
// 256-wide block (one 16-byte weight load) and hoists the n_tok activation
// rows once per block so every output row reuses them (the nvfp4 wide
// kernels' shape, applied to bf16).
template <int ROWS, bool ADD_RESIDUAL>
static inline void bf16_wide_multi_impl(
  device const ushort *__restrict__ w,
  device const float  *__restrict__ x,
  device float        *__restrict__ y,
  constant int &k_dim,
  constant int &n_rows,
  constant int &n_tok,
  uint tg_id, uint simd_id, uint simd_lane
) {
  const int row0 = int(tg_id) * (2 * ROWS) + int(simd_id) * ROWS;
  const int lane = int(simd_lane);
  float acc[ROWS][DRAFT_MAX_TOK];
#pragma clang loop unroll(full)
  for (int r = 0; r < ROWS; r++) {
#pragma clang loop unroll(full)
    for (int b = 0; b < DRAFT_MAX_TOK; b++) acc[r][b] = 0.0f;
  }
  for (int kb = 0; kb < k_dim; kb += 256) {
    const int kk = kb + lane * 8;
    if (kk >= k_dim) continue;
    float4 av[DRAFT_MAX_TOK][2];
#pragma clang loop unroll(full)
    for (int b = 0; b < DRAFT_MAX_TOK; b++) {
      if (b < n_tok) {
        device const float4 *xp = (device const float4 *)(&x[b * k_dim + kk]);
        av[b][0] = xp[0];
        av[b][1] = xp[1];
      } else {
        av[b][0] = float4(0.0f);
        av[b][1] = float4(0.0f);
      }
    }
#pragma clang loop unroll(full)
    for (int r = 0; r < ROWS; r++) {
      const int row = row0 + r;
      if (row >= n_rows) continue;
      const uint4 wv = *(device const uint4 *)(&w[row * k_dim + kk]);
      const float4 v0 = float4(bf16d_lo(wv.x), bf16d_hi(wv.x), bf16d_lo(wv.y), bf16d_hi(wv.y));
      const float4 v1 = float4(bf16d_lo(wv.z), bf16d_hi(wv.z), bf16d_lo(wv.w), bf16d_hi(wv.w));
#pragma clang loop unroll(full)
      for (int b = 0; b < DRAFT_MAX_TOK; b++) {
        acc[r][b] += dot(v0, av[b][0]) + dot(v1, av[b][1]);
      }
    }
  }
#pragma clang loop unroll(full)
  for (int r = 0; r < ROWS; r++) {
#pragma clang loop unroll(full)
    for (int b = 0; b < DRAFT_MAX_TOK; b++) acc[r][b] = simd_sum(acc[r][b]);
  }
  if (lane == 0) {
#pragma clang loop unroll(full)
    for (int r = 0; r < ROWS; r++) {
      const int row = row0 + r;
      if (row >= n_rows) continue;
      for (int b = 0; b < n_tok; b++) {
        if (ADD_RESIDUAL) y[b * n_rows + row] += acc[r][b];
        else y[b * n_rows + row] = acc[r][b];
      }
    }
  }
}

#define DEFINE_BF16_WIDE(NAME, ROWS, ADD_RESIDUAL)                          \
[[max_total_threads_per_threadgroup(64)]]                                   \
kernel void NAME(                                                           \
  device const ushort *w [[buffer(0)]], device const float *x [[buffer(1)]], \
  device float *y [[buffer(2)]], constant int &k [[buffer(3)]],             \
  constant int &n [[buffer(4)]], constant int &n_tok [[buffer(5)]],         \
  uint tg [[threadgroup_position_in_grid]],                                 \
  uint sg [[simdgroup_index_in_threadgroup]],                               \
  uint sl [[thread_index_in_simdgroup]]) {                                  \
  bf16_wide_multi_impl<ROWS, ADD_RESIDUAL>(w, x, y, k, n, n_tok, tg, sg, sl); \
}
DEFINE_BF16_WIDE(bf16_wide_multi_r1, 1, false)
DEFINE_BF16_WIDE(bf16_wide_multi_r2, 2, false)
DEFINE_BF16_WIDE(bf16_wide_multi_r4, 4, false)
DEFINE_BF16_WIDE(bf16_wide_multi_r1_residual, 1, true)
DEFINE_BF16_WIDE(bf16_wide_multi_r2_residual, 2, true)
DEFINE_BF16_WIDE(bf16_wide_multi_r4_residual, 4, true)
#undef DEFINE_BF16_WIDE

// Grouped dynamic causal conv (two taps, groups of 16 channels), one of the
// two kernel sets `set` (0 = prepare, 1 = finish):
//   out[t][c] (=|+=) (base[set][0][c] + dyn[t][set*2G + c/16]) * inp[t][c]
//                  + (base[set][1][c] + dyn[t][set*2G + G + c/16]) * inp[t-1][c]
// with inp[-1] = 0 (the shift is over the block's own rows). dyn is the
// kernel_projection output [n_tok][2*2*G], base is base_kernel [2][2][hidden]
// widened to f32, G = hidden / 16.
template <bool ADD_RESIDUAL>
static inline void dyn_conv_apply_impl(
  device const float *inp, device const float *dyn, device const float *base,
  device float *out, int set, int hidden, int n_tok, uint tid
) {
  const int total = n_tok * hidden;
  if (int(tid) >= total) return;
  const int t = int(tid) / hidden;
  const int c = int(tid) - t * hidden;
  const int groups = hidden / 16;
  const int dyn_row = t * (4 * groups) + set * (2 * groups);
  const int g = c / 16;
  const int base_off = set * (2 * hidden);
  float v = (base[base_off + c] + dyn[dyn_row + g]) * inp[t * hidden + c];
  if (t > 0) {
    v += (base[base_off + hidden + c] + dyn[dyn_row + groups + g]) * inp[(t - 1) * hidden + c];
  }
  if (ADD_RESIDUAL) out[tid] += v; else out[tid] = v;
}

kernel void dyn_conv_apply(
  device const float *inp [[buffer(0)]], device const float *dyn [[buffer(1)]],
  device const float *base [[buffer(2)]], device float *out [[buffer(3)]],
  constant int &set [[buffer(4)]], constant int &hidden [[buffer(5)]],
  constant int &n_tok [[buffer(6)]],
  uint tid [[thread_position_in_grid]]) {
  dyn_conv_apply_impl<false>(inp, dyn, base, out, set, hidden, n_tok, tid);
}

kernel void dyn_conv_apply_residual(
  device const float *inp [[buffer(0)]], device const float *dyn [[buffer(1)]],
  device const float *base [[buffer(2)]], device float *out [[buffer(3)]],
  constant int &set [[buffer(4)]], constant int &hidden [[buffer(5)]],
  constant int &n_tok [[buffer(6)]],
  uint tid [[thread_position_in_grid]]) {
  dyn_conv_apply_impl<true>(inp, dyn, base, out, set, hidden, n_tok, tid);
}

// Block attention, head dim 128: query row t (block position ctx_len + t)
// attends to the context cache rows [0, ctx_len) within the sliding window
// and to ALL n_tok block rows (the block is bidirectional). One 128-thread
// group per (token, head); thread = output dim. Layouts: q [n][n_heads][128],
// caches [pos][n_kv][128], block K/V [n][n_kv][128], out [n][n_heads][128].
[[max_total_threads_per_threadgroup(128)]]
kernel void sdpa_draft_hd128(
  device const float *q [[buffer(0)]],
  device const float *k_cache [[buffer(1)]], device const float *v_cache [[buffer(2)]],
  device const float *k_blk [[buffer(3)]], device const float *v_blk [[buffer(4)]],
  device float *out [[buffer(5)]],
  constant int &n_heads [[buffer(6)]], constant int &n_kv [[buffer(7)]],
  constant int &ctx_len [[buffer(8)]], constant int &n_tok [[buffer(9)]],
  constant int &window [[buffer(10)]], constant float &scale [[buffer(11)]],
  uint tg [[threadgroup_position_in_grid]],
  uint tid [[thread_position_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]],
  uint simd [[simdgroup_index_in_threadgroup]]) {
  threadgroup float partial[4];
  threadgroup float scores[DRAFT_MAX_POS + DRAFT_MAX_TOK];
  const int token = int(tg) / n_heads;
  const int head = int(tg) - token * n_heads;
  if (token >= n_tok) return;
  const int kvh = head / (n_heads / n_kv);
  const int q_off = (token * n_heads + head) * 128;
  const int qpos = ctx_len + token;
  const float qv = q[q_off + int(tid)];
  const int usable_ctx = min(ctx_len, DRAFT_MAX_POS);
  const int total = usable_ctx + n_tok;
  for (int p = 0; p < total; ++p) {
    float kv;
    bool visible;
    if (p < usable_ctx) {
      kv = k_cache[(p * n_kv + kvh) * 128 + int(tid)];
      visible = (qpos - p) < window;
    } else {
      kv = k_blk[((p - usable_ctx) * n_kv + kvh) * 128 + int(tid)];
      visible = true;
    }
    const float sg = simd_sum(qv * kv);
    if (lane == 0) partial[simd] = sg;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (simd == 0) {
      const float v = lane < 4 ? partial[lane] : 0.0f;
      const float tot = simd_sum(v);
      if (lane == 0) scores[p] = visible ? tot * scale : -INFINITY;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
  }
  if (tid == 0) {
    float mx = -INFINITY;
    for (int p = 0; p < total; ++p) mx = max(mx, scores[p]);
    float denom = 0.0f;
    for (int p = 0; p < total; ++p) {
      const float e = fast::exp(scores[p] - mx); scores[p] = e; denom += e;
    }
    const float inv = denom == 0.0f ? 0.0f : 1.0f / denom;
    for (int p = 0; p < total; ++p) scores[p] *= inv;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float result = 0.0f;
  for (int p = 0; p < usable_ctx; ++p) {
    result += scores[p] * v_cache[(p * n_kv + kvh) * 128 + int(tid)];
  }
  for (int j = 0; j < n_tok; ++j) {
    result += scores[usable_ctx + j] * v_blk[(j * n_kv + kvh) * 128 + int(tid)];
  }
  out[q_off + int(tid)] = result;
}

// Exact top-16 (value desc, ties to the lowest index) of each logits row.
// One 256-thread group per row: every thread keeps a sorted 16-list over its
// strided slice, then 16 rounds of a group-wide argmax over the list heads.
// cand[row][k] = index, unary[row][k] = logit, k in descending order.
static inline bool topk_better(float av, int ai, float bv, int bi) {
  return av > bv || (av == bv && ai < bi);
}

[[max_total_threads_per_threadgroup(256)]]
kernel void topk16_rows(
  device const float *logits [[buffer(0)]],
  device int *cand [[buffer(1)]], device float *unary [[buffer(2)]],
  constant int &vocab [[buffer(3)]],
  constant int &row_start [[buffer(4)]],
  uint tg [[threadgroup_position_in_grid]],
  uint tid [[thread_position_in_threadgroup]],
  uint nthr [[threads_per_threadgroup]]) {
  const int row = row_start + int(tg);
  device const float *lg = logits + row * vocab;
  float lv[DRAFT_TOPK];
  int li[DRAFT_TOPK];
  for (int k = 0; k < DRAFT_TOPK; ++k) { lv[k] = -INFINITY; li[k] = INT_MAX; }
  for (int i = int(tid); i < vocab; i += int(nthr)) {
    const float v = lg[i];
    if (!topk_better(v, i, lv[DRAFT_TOPK - 1], li[DRAFT_TOPK - 1])) continue;
    int k = DRAFT_TOPK - 1;
    while (k > 0 && topk_better(v, i, lv[k - 1], li[k - 1])) {
      lv[k] = lv[k - 1]; li[k] = li[k - 1]; --k;
    }
    lv[k] = v; li[k] = i;
  }
  threadgroup float sv[256];
  threadgroup int si[256];
  threadgroup int winner;
  int head = 0;
  for (int round = 0; round < DRAFT_TOPK; ++round) {
    sv[tid] = head < DRAFT_TOPK ? lv[head] : -INFINITY;
    si[tid] = head < DRAFT_TOPK ? li[head] : INT_MAX;
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (uint s = nthr / 2; s > 0; s >>= 1) {
      if (tid < s && topk_better(sv[tid + s], si[tid + s], sv[tid], si[tid])) {
        sv[tid] = sv[tid + s]; si[tid] = si[tid + s];
      }
      threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    if (tid == 0) {
      cand[row * DRAFT_TOPK + round] = si[0];
      unary[row * DRAFT_TOPK + round] = sv[0];
      winner = si[0];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (head < DRAFT_TOPK && li[head] == winner) ++head;
    threadgroup_barrier(mem_flags::mem_threadgroup);
  }
}

// Codebook selector walk over block rows 1..n_tok-1 (row 0 is the anchor).
//   edge[k] = sum_r pred[predecessor][r] * hp[row][r] * succ[cand[row][k]][r]
//   pick = argmax_k (unary[row][k] + edge[k]);  predecessor = cand[row][pick]
// One 256-thread group; simdgroup s scores candidates 2s and 2s+1 with an
// 8-per-lane dot over the rank-256 vectors. Writes the chosen ids into
// token_slots[1..n_tok-1] (the verify's device-resident token buffer) and
// draft_out[0..n_tok-2] for the host.
[[max_total_threads_per_threadgroup(256)]]
kernel void selector_walk(
  device const float *hp [[buffer(0)]],
  device const ushort *pred_cb [[buffer(1)]], device const ushort *succ_cb [[buffer(2)]],
  device const int *cand [[buffer(3)]], device const float *unary [[buffer(4)]],
  device int *token_slots [[buffer(5)]], device int *draft_out [[buffer(6)]],
  constant int &n_tok [[buffer(7)]],
  uint tid [[thread_position_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]],
  uint simd [[simdgroup_index_in_threadgroup]]) {
  threadgroup float edge[DRAFT_TOPK];
  threadgroup int predecessor;
  if (tid == 0) predecessor = token_slots[0];
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int row = 1; row < n_tok; ++row) {
    const int pid = predecessor;
    for (int c = int(simd) * 2; c < int(simd) * 2 + 2; ++c) {
      const int cid = cand[row * DRAFT_TOPK + c];
      float d = 0.0f;
      for (int r = int(lane) * 8; r < int(lane) * 8 + 8; ++r) {
        d += bf16d_to_f32(pred_cb[pid * DRAFT_RANK + r]) * hp[row * DRAFT_RANK + r]
           * bf16d_to_f32(succ_cb[cid * DRAFT_RANK + r]);
      }
      d = simd_sum(d);
      if (lane == 0) edge[c] = d;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (tid == 0) {
      float best = -INFINITY; int bk = 0;
      for (int k = 0; k < DRAFT_TOPK; ++k) {
        const float sc = unary[row * DRAFT_TOPK + k] + edge[k];
        if (sc > best) { best = sc; bk = k; }
      }
      const int chosen = cand[row * DRAFT_TOPK + bk];
      predecessor = chosen;
      token_slots[row] = chosen;
      draft_out[row - 1] = chosen;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
  }
}

// ============================================================================
// Full DFlash 2 (DF2Fast) M5 Neural Accelerator Suite (16-row Block Diffusion)
// Ported from Layr-Labs/mlxfast-bonsai2-9b-engine (DFlash2Draft.swift):
//   1. df2_act_q8 / df2_act_q8_swiglu: per-row group-32 int8 activation quantizer
//   2. df2_i8_matmul{1,2,3}: 16x32x32 NAX int8 x u8(g32) matmul for 1..3 linears
//   3. df2_act_q8g{64,128}{,_swiglu,_hm}: per-row group-64/128 int8 quantizer
//      with optional SwiGLU and head-major [1, 32, R, 128] direct read
//   4. df2_act_q8g{64,128}_conv0: fused dynConv(part: 0) + group-64/128 int8 quant
//   5. df2_w4g{64,128}_{1,2,3}: 16x32x{64,128} NAX int8 x u4 matmul for 1..3
//      sibling drafter linears with register prefetch & 8-way K-split
//   6. df2_qkv_norm_rope / df2_ctx_kv_norm_rope / df2_qkv_all_norm_rope:
//      fused qNorm + kNorm + YarnRoPE (mscale + RoPE) + head-major transpose
//   7. df2_dyn_conv / df2_dyn_conv_rms_4096: fused dynConv(part: 1, residual)
//      + 4096-wide RMSNorm in one launch
//   8. df2_topk16_mb8 + df2_selector_mb8: 8-block/row parallel top-16 (120
//      threadgroups for P=15) + single-block top-16 merge & rank-256 codebook walk
// ============================================================================

template <bool SWIGLU>
static inline void df2_act_q8_impl(
  device const float *x,
  device const float *x2,
  device const int *ksz,
  device char *xq,
  device float *ascale,
  device float *xs,
  uint tid,
  uint tpb,
  uint2 tgid
) {
  const int K = ksz[0];
  const int R = ksz[1];
  const int G = K / 32;
  const int m = int(tgid.y);
  for (int g = int(tid); g < G; g += int(tpb)) {
    float v[32];
    float amax = 0.0f, sum = 0.0f;
    if (m < R) {
      for (int u = 0; u < 32; u++) {
        float a = float(x[(size_t)m * K + g * 32 + u]);
        if (SWIGLU) {
          const float b = float(x2[(size_t)m * K + g * 32 + u]);
          a = a / (1.0f + metal::exp(-a)) * b;
        }
        v[u] = a;
        amax = max(amax, fabs(a));
        sum += a;
      }
    } else {
      for (int u = 0; u < 32; u++) v[u] = 0.0f;
    }
    const float a = amax > 0.0f ? amax / 127.0f : 1.0f;
    const float ia = 1.0f / a;
    device char4 *dst = (device char4 *)(xq + (size_t)m * K + g * 32);
    for (int u = 0; u < 8; u++) {
      dst[u] = char4(int4(rint(float4(v[4 * u], v[4 * u + 1], v[4 * u + 2], v[4 * u + 3]) * ia)));
    }
    ascale[m * G + g] = m < R ? a : 0.0f;
    xs[m * G + g] = sum;
  }
}

[[max_total_threads_per_threadgroup(128)]]
kernel void df2_act_q8(
  device const float *x [[buffer(0)]],
  device const int *ksz [[buffer(1)]],
  device char *xq [[buffer(2)]],
  device float *ascale [[buffer(3)]],
  device float *xs [[buffer(4)]],
  uint tid [[thread_index_in_threadgroup]],
  uint2 tpb [[threads_per_threadgroup]],
  uint2 tgid [[threadgroup_position_in_grid]]
) {
  df2_act_q8_impl<false>(x, x, ksz, xq, ascale, xs, tid, tpb.x, tgid);
}

[[max_total_threads_per_threadgroup(128)]]
kernel void df2_act_q8_swiglu(
  device const float *x [[buffer(0)]],
  device const float *x2 [[buffer(1)]],
  device const int *ksz [[buffer(2)]],
  device char *xq [[buffer(3)]],
  device float *ascale [[buffer(4)]],
  device float *xs [[buffer(5)]],
  uint tid [[thread_index_in_threadgroup]],
  uint2 tpb [[threads_per_threadgroup]],
  uint2 tgid [[threadgroup_position_in_grid]]
) {
  df2_act_q8_impl<true>(x, x2, ksz, xq, ascale, xs, tid, tpb.x, tgid);
}

template <int SPLIT>
static inline void df2_i8_matmul_core(
  device const char *xq,
  device const uint32_t *w,
  device const float *sT,
  device const float *bT,
  device const float *ascale,
  device const float *xs,
  device float *out,
  int K,
  int rows,
  int N,
  int bx,
  uint tid,
  uint lane,
  uint sg,
  threadgroup uint32_t (&bs)[SPLIT][32 * 8],
  threadgroup float (&red)[SPLIT][16 * 32]
) {
  const int G = K / 32;
  const int n0 = bx * 32;
  constexpr auto desc = mpp::tensor_ops::matmul2d_descriptor(
    16, 32, 32, false, true, false, mpp::tensor_ops::matmul2d_descriptor::mode::multiply);
  mpp::tensor_ops::matmul2d<desc, metal::execution_simdgroup> op;
  tensor<device int8_t, dextents<int, 2>, tensor_inline> A((device int8_t *)xq, dextents<int, 2>(K, 16));
  tensor<threadgroup int8_t, dextents<int, 2>, tensor_inline> Bt((threadgroup int8_t *)bs[sg], dextents<int, 2>(32, 32));
  auto tA0 = A.template slice<32, 16>(0, 0);
  auto cT = op.template get_destination_cooperative_tensor<
    metal::remove_addrspace_t<decltype(tA0)>,
    metal::remove_addrspace_t<decltype(Bt)>,
    int32_t>();
  const int mrow = int((lane >> 1) & 3u) + 4 * int((lane >> 4) & 1u);
  const int nb = 4 * int(lane & 1u) + 8 * int((lane >> 3) & 1u);
  bool ok = cT.get_capacity() == 16;
  for (int i = 0; i < 16 && ok; i++) {
    auto ids = cT.get_multidimensional_index(i);
    ok = ids[0] == nb + (i & 3) + 16 * (i >> 3) && ids[1] == mrow + 8 * ((i >> 2) & 1);
  }
  float acc[16], accb[16];
  for (int i = 0; i < 16; i++) { acc[i] = 0.0f; accb[i] = 0.0f; }
  const int m0 = mrow, m1 = mrow + 8;
  const int sj = int(lane & 7u), sc = int(lane >> 3);
  const device uint32_t *wsrc = w + (size_t)(n0 + sc) * (K / 4) + sj;
  threadgroup uint32_t *sdst = bs[sg] + sc * 8 + sj;
  uint32_t wv[8];
  for (int t = 0; t < 8; t++) { wv[t] = wsrc[(size_t)(4 * t) * (K / 4) + int(sg) * 8]; }
  for (int g = int(sg); g < G; g += SPLIT) {
    for (int t = 0; t < 8; t++) { sdst[32 * t] = wv[t] ^ 0x80808080u; }
    if (g + SPLIT < G) {
      for (int t = 0; t < 8; t++) { wv[t] = wsrc[(size_t)(4 * t) * (K / 4) + (g + SPLIT) * 8]; }
    }
    simdgroup_barrier(mem_flags::mem_threadgroup);
    auto tA = A.template slice<32, 16>(g * 32, 0);
    op.run(tA, Bt, cT);
    const device float *sr = sT + (size_t)g * N + n0 + nb;
    const device float *br = bT + (size_t)g * N + n0 + nb;
    const float4 s0v = *(const device float4 *)sr, s1v = *(const device float4 *)(sr + 16);
    const float4 b0v = fma(float4(128.0f), s0v, *(const device float4 *)br);
    const float4 b1v = fma(float4(128.0f), s1v, *(const device float4 *)(br + 16));
    const float a0 = ascale[m0 * G + g], a1 = ascale[m1 * G + g];
    const float x0 = xs[m0 * G + g], x1 = xs[m1 * G + g];
    for (int i = 0; i < 16; i++) {
      const int j = (i & 3);
      const float s = (i >> 3) ? s1v[j] : s0v[j];
      const float b = (i >> 3) ? b1v[j] : b0v[j];
      const bool hi = (i >> 2) & 1;
      acc[i] = fma(s * (hi ? a1 : a0), float(cT[i]), acc[i]);
      accb[i] = fma(b, hi ? x1 : x0, accb[i]);
    }
    simdgroup_barrier(mem_flags::mem_threadgroup);
  }
  for (int i = 0; i < 16; i++) {
    const int m = mrow + 8 * ((i >> 2) & 1), n = nb + (i & 3) + 16 * (i >> 3);
    red[sg][m * 32 + n] = acc[i] + accb[i];
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int e = int(tid); e < rows * 32; e += SPLIT * 32) {
    float v = 0.0f;
    for (int q = 0; q < SPLIT; q++) { v += red[q][e]; }
    out[(size_t)(e >> 5) * N + n0 + (e & 31)] = ok ? v : as_type<float>(0x7fc00000u);
  }
}

[[max_total_threads_per_threadgroup(256)]]
kernel void df2_i8_matmul1(
  device const char *xq [[buffer(0)]],
  device const uint32_t *w0 [[buffer(1)]],
  device const float *s0 [[buffer(2)]],
  device const float *b0 [[buffer(3)]],
  device const float *ascale [[buffer(4)]],
  device const float *xs [[buffer(5)]],
  device const int *ksz [[buffer(6)]],
  device float *out0 [[buffer(7)]],
  uint tid [[thread_index_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint tgid [[threadgroup_position_in_grid]]
) {
  threadgroup uint32_t bs[8][32 * 8];
  threadgroup float red[8][16 * 32];
  df2_i8_matmul_core<8>(xq, w0, s0, b0, ascale, xs, out0, ksz[0], ksz[1], ksz[2], int(tgid), tid, lane, sg, bs, red);
}

[[max_total_threads_per_threadgroup(256)]]
kernel void df2_i8_matmul2(
  device const char *xq [[buffer(0)]],
  device const uint32_t *w0 [[buffer(1)]],
  device const uint32_t *w1 [[buffer(2)]],
  device const float *s0 [[buffer(3)]],
  device const float *s1 [[buffer(4)]],
  device const float *b0 [[buffer(5)]],
  device const float *b1 [[buffer(6)]],
  device const float *ascale [[buffer(7)]],
  device const float *xs [[buffer(8)]],
  device const int *ksz [[buffer(9)]],
  device float *out0 [[buffer(10)]],
  device float *out1 [[buffer(11)]],
  uint tid [[thread_index_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint tgid [[threadgroup_position_in_grid]]
) {
  int bx = int(tgid);
  device const uint32_t *w = w0;
  device const float *sT = s0;
  device const float *bT = b0;
  device float *out = out0;
  int N = ksz[2];
  if (bx >= N / 32) { bx -= N / 32; w = w1; sT = s1; bT = b1; out = out1; N = ksz[3]; }
  threadgroup uint32_t bs[8][32 * 8];
  threadgroup float red[8][16 * 32];
  df2_i8_matmul_core<8>(xq, w, sT, bT, ascale, xs, out, ksz[0], ksz[1], N, bx, tid, lane, sg, bs, red);
}

[[max_total_threads_per_threadgroup(256)]]
kernel void df2_i8_matmul3(
  device const char *xq [[buffer(0)]],
  device const uint32_t *w0 [[buffer(1)]],
  device const uint32_t *w1 [[buffer(2)]],
  device const uint32_t *w2 [[buffer(3)]],
  device const float *s0 [[buffer(4)]],
  device const float *s1 [[buffer(5)]],
  device const float *s2 [[buffer(6)]],
  device const float *b0 [[buffer(7)]],
  device const float *b1 [[buffer(8)]],
  device const float *b2 [[buffer(9)]],
  device const float *ascale [[buffer(10)]],
  device const float *xs [[buffer(11)]],
  device const int *ksz [[buffer(12)]],
  device float *out0 [[buffer(13)]],
  device float *out1 [[buffer(14)]],
  device float *out2 [[buffer(15)]],
  uint tid [[thread_index_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint tgid [[threadgroup_position_in_grid]]
) {
  int bx = int(tgid);
  device const uint32_t *w = w0;
  device const float *sT = s0;
  device const float *bT = b0;
  device float *out = out0;
  int N = ksz[2];
  if (bx >= N / 32) { bx -= N / 32; w = w1; sT = s1; bT = b1; out = out1; N = ksz[3]; }
  if (bx >= N / 32) { bx -= N / 32; w = w2; sT = s2; bT = b2; out = out2; N = ksz[4]; }
  threadgroup uint32_t bs[8][32 * 8];
  threadgroup float red[8][16 * 32];
  df2_i8_matmul_core<8>(xq, w, sT, bT, ascale, xs, out, ksz[0], ksz[1], N, bx, tid, lane, sg, bs, red);
}

template <int KG, bool SWIGLU, bool HEAD_MAJOR>
static inline void df2_act_q8g_impl(
  device const float *x,
  device const float *x2,
  device const int *ksz,
  device char *xq,
  device float *ascale,
  device float *xs,
  uint gid_x,
  uint lane,
  uint2 tgid
) {
  const int K = ksz[0];
  const int R = ksz[1];
  const int G = K / KG;
  const int tid = int(gid_x);
  const int c0 = tid * 16;
  if (c0 >= K) return;
  const int m = int(tgid.y);
  const int g = tid / (KG / 16);
  const size_t dstBase = (size_t)m * K + c0;
  if (m >= R) {
    device char4 *dst = (device char4 *)(xq + dstBase);
    for (int u = 0; u < 4; u++) { dst[u] = char4(0); }
    if ((tid & ((KG / 16) - 1)) == 0) {
      ascale[m * G + g] = 0.0f;
      xs[m * G + g] = 0.0f;
    }
    return;
  }
  const size_t srcBase = HEAD_MAJOR
    ? (((size_t)(c0 >> 7) * R + m) * 128 + (c0 & 127))
    : dstBase;
  float nv[16];
  float local_amax = 0.0f;
  for (int u = 0; u < 16; u++) {
    float a = float(x[srcBase + u]);
    if (SWIGLU) {
      const float b = float(x2[srcBase + u]);
      a = a / (1.0f + metal::exp(-a)) * b;
    }
    nv[u] = a;
    local_amax = max(local_amax, fabs(a));
  }
  local_amax = max(local_amax, simd_shuffle_xor(local_amax, 1));
  local_amax = max(local_amax, simd_shuffle_xor(local_amax, 2));
  if (KG == 128) {
    local_amax = max(local_amax, simd_shuffle_xor(local_amax, 4));
  }
  float seq_sum = 0.0f;
  const uint grpBase = lane & ~uint((KG / 16) - 1);
  for (int step = 0; step < (KG / 16); step++) {
    seq_sum = simd_shuffle(seq_sum, ushort(grpBase | uint(step > 0 ? step - 1 : 0)));
    if ((int(lane) & ((KG / 16) - 1)) == step) {
      for (int u = 0; u < 16; u++) { seq_sum += nv[u]; }
    }
  }
  const float a = local_amax > 0.0f ? local_amax / 127.0f : 1.0f;
  const float ia = 1.0f / a;
  device char4 *dst = (device char4 *)(xq + dstBase);
  for (int u = 0; u < 4; u++) {
    const float4 fv = float4(nv[4 * u], nv[4 * u + 1], nv[4 * u + 2], nv[4 * u + 3]);
    dst[u] = char4(int4(rint(fv * ia)));
  }
  if ((int(lane) & ((KG / 16) - 1)) == (KG / 16) - 1) {
    ascale[m * G + g] = a;
    xs[m * G + g] = seq_sum;
  }
}

#define DEFINE_DF2_ACT_Q8G(NAME, KG, SWIGLU, HM)                               \
[[max_total_threads_per_threadgroup(256)]]                                     \
kernel void NAME(                                                              \
  device const float *x [[buffer(0)]],                                         \
  device const float *x2 [[buffer(1)]],                                        \
  device const int *ksz [[buffer(2)]],                                         \
  device char *xq [[buffer(3)]],                                               \
  device float *ascale [[buffer(4)]],                                          \
  device float *xs [[buffer(5)]],                                              \
  uint2 gid [[thread_position_in_grid]],                                       \
  uint lane [[thread_index_in_simdgroup]],                                     \
  uint2 tgid [[threadgroup_position_in_grid]]) {                               \
  df2_act_q8g_impl<KG, SWIGLU, HM>(x, x2, ksz, xq, ascale, xs, gid.x, lane, tgid); \
}
DEFINE_DF2_ACT_Q8G(df2_act_q8g64, 64, false, false)
DEFINE_DF2_ACT_Q8G(df2_act_q8g64_swiglu, 64, true, false)
DEFINE_DF2_ACT_Q8G(df2_act_q8g64_hm, 64, false, true)
DEFINE_DF2_ACT_Q8G(df2_act_q8g128, 128, false, false)
DEFINE_DF2_ACT_Q8G(df2_act_q8g128_swiglu, 128, true, false)
DEFINE_DF2_ACT_Q8G(df2_act_q8g128_hm, 128, false, true)
#undef DEFINE_DF2_ACT_Q8G

template <int KG>
static inline void df2_act_q8g_conv0_impl(
  device const float *h,
  device const float *dyn,
  device const float *base,
  device const int *ksz,
  device char *xq,
  device float *ascale,
  device float *xs,
  uint gid_x,
  uint lane,
  uint2 tgid
) {
  const int K = ksz[0];
  const int R = ksz[1];
  const int G = K / KG;
  const int tid = int(gid_x);
  const int c0 = tid * 16;
  if (c0 >= K) return;
  const int m = int(tgid.y);
  const int g = tid / (KG / 16);
  const size_t rowBase = (size_t)m * K + c0;
  if (m >= R) {
    device char4 *dst = (device char4 *)(xq + rowBase);
    for (int u = 0; u < 4; u++) { dst[u] = char4(0); }
    if ((tid & ((KG / 16) - 1)) == 0) {
      ascale[m * G + g] = 0.0f;
      xs[m * G + g] = 0.0f;
    }
    return;
  }
  const int dw = 4 * (K / 16);
  const float d0 = float(dyn[m * dw + tid]);
  const float d1 = m >= 1 ? float(dyn[m * dw + (K >> 4) + tid]) : 0.0f;
  float nv[16];
  float local_amax = 0.0f;
  for (int u = 0; u < 16; u++) {
    const int c = c0 + u;
    float a = (float(base[c]) + d0) * float(h[rowBase + u]);
    if (m >= 1) {
      a += (float(base[K + c]) + d1) * float(h[rowBase - K + u]);
    }
    nv[u] = a;
    local_amax = max(local_amax, fabs(a));
  }
  local_amax = max(local_amax, simd_shuffle_xor(local_amax, 1));
  local_amax = max(local_amax, simd_shuffle_xor(local_amax, 2));
  if (KG == 128) {
    local_amax = max(local_amax, simd_shuffle_xor(local_amax, 4));
  }
  float seq_sum = 0.0f;
  const uint grpBase = lane & ~uint((KG / 16) - 1);
  for (int step = 0; step < (KG / 16); step++) {
    seq_sum = simd_shuffle(seq_sum, ushort(grpBase | uint(step > 0 ? step - 1 : 0)));
    if ((int(lane) & ((KG / 16) - 1)) == step) {
      for (int u = 0; u < 16; u++) { seq_sum += nv[u]; }
    }
  }
  const float a = local_amax > 0.0f ? local_amax / 127.0f : 1.0f;
  const float ia = 1.0f / a;
  device char4 *dst = (device char4 *)(xq + rowBase);
  for (int u = 0; u < 4; u++) {
    const float4 fv = float4(nv[4 * u], nv[4 * u + 1], nv[4 * u + 2], nv[4 * u + 3]);
    dst[u] = char4(int4(rint(fv * ia)));
  }
  if ((int(lane) & ((KG / 16) - 1)) == (KG / 16) - 1) {
    ascale[m * G + g] = a;
    xs[m * G + g] = seq_sum;
  }
}

[[max_total_threads_per_threadgroup(256)]]
kernel void df2_act_q8g64_conv0(
  device const float *h [[buffer(0)]],
  device const float *dyn [[buffer(1)]],
  device const float *base [[buffer(2)]],
  device const int *ksz [[buffer(3)]],
  device char *xq [[buffer(4)]],
  device float *ascale [[buffer(5)]],
  device float *xs [[buffer(6)]],
  uint2 gid [[thread_position_in_grid]],
  uint lane [[thread_index_in_simdgroup]],
  uint2 tgid [[threadgroup_position_in_grid]]
) {
  df2_act_q8g_conv0_impl<64>(h, dyn, base, ksz, xq, ascale, xs, gid.x, lane, tgid);
}

[[max_total_threads_per_threadgroup(256)]]
kernel void df2_act_q8g128_conv0(
  device const float *h [[buffer(0)]],
  device const float *dyn [[buffer(1)]],
  device const float *base [[buffer(2)]],
  device const int *ksz [[buffer(3)]],
  device char *xq [[buffer(4)]],
  device float *ascale [[buffer(5)]],
  device float *xs [[buffer(6)]],
  uint2 gid [[thread_position_in_grid]],
  uint lane [[thread_index_in_simdgroup]],
  uint2 tgid [[threadgroup_position_in_grid]]
) {
  df2_act_q8g_conv0_impl<128>(h, dyn, base, ksz, xq, ascale, xs, gid.x, lane, tgid);
}

template <int GROUP, int SPLIT>
static inline void df2_w4_nax_core(
  device const char *xq,
  device const uint32_t *w,
  device const half *sT,
  device const half *bT,
  device const float *ascale,
  device const float *xs,
  device float *out,
  int K,
  int rows,
  int N,
  int bx,
  uint tid,
  uint lane,
  uint sg,
  threadgroup uint4 *tiles
) {
  #define DF2_LO(v) ((((v) & 0x0F0F0F0Fu) + 0x78787878u) ^ 0x80808080u)
  #define DF2_HI(v) (((((v) >> 4) & 0x0F0F0F0Fu) + 0x78787878u) ^ 0x80808080u)
  constexpr int RU = GROUP / 32;
  constexpr int TW = GROUP / 16;
  const int G = K / GROUP;
  const int n0 = bx * 32;
  constexpr auto desc = mpp::tensor_ops::matmul2d_descriptor(
    16, 32, GROUP, false, true, false, mpp::tensor_ops::matmul2d_descriptor::mode::multiply);
  mpp::tensor_ops::matmul2d<desc, metal::execution_simdgroup> op;
  tensor<device int8_t, dextents<int, 2>, tensor_inline> A((device int8_t *)xq, dextents<int, 2>(K, 16));
  threadgroup uint4 *bs = tiles + sg * (32 * TW);
  tensor<threadgroup int8_t, dextents<int, 2>, tensor_inline> Bt((threadgroup int8_t *)bs, dextents<int, 2>(GROUP, 32));
  auto tA0 = A.template slice<GROUP, 16>(0, 0);
  auto cT = op.template get_destination_cooperative_tensor<
    metal::remove_addrspace_t<decltype(tA0)>,
    metal::remove_addrspace_t<decltype(Bt)>,
    int32_t>();
  const int mrow = int((lane >> 1) & 3u) + 4 * int((lane >> 4) & 1u);
  const int nb = 4 * int(lane & 1u) + 8 * int((lane >> 3) & 1u);
  bool ok = cT.get_capacity() == 16;
  for (int i = 0; i < 16 && ok; i++) {
    auto ids = cT.get_multidimensional_index(i);
    ok = ids[0] == nb + (i & 3) + 16 * (i >> 3) && ids[1] == mrow + 8 * ((i >> 2) & 1);
  }
  float acc[16], accb[16];
  for (int i = 0; i < 16; i++) { acc[i] = 0.0f; accb[i] = 0.0f; }
  const int m0 = mrow, m1 = mrow + 8;
  const int lr = int(lane) / RU, lc = int(lane) % RU;
  const size_t rowU4 = (size_t)K / 32;
  const device uint4 *wsrc = (const device uint4 *)w + (size_t)(n0 + lr) * rowU4 + lc;
  uint4 wv[RU];
  for (int p = 0; p < RU; p++) { wv[p] = wsrc[(size_t)(p * (32 / RU)) * rowU4 + int(sg) * RU]; }
  for (int g = int(sg); g < G; g += SPLIT) {
    for (int p = 0; p < RU; p++) {
      const int r = lr + p * (32 / RU);
      const uint4 x = wv[p];
      bs[r * TW + 2 * lc] = uint4(DF2_LO(x.x), DF2_HI(x.x), DF2_LO(x.y), DF2_HI(x.y));
      bs[r * TW + 2 * lc + 1] = uint4(DF2_LO(x.z), DF2_HI(x.z), DF2_LO(x.w), DF2_HI(x.w));
    }
    if (g + SPLIT < G) {
      for (int p = 0; p < RU; p++) { wv[p] = wsrc[(size_t)(p * (32 / RU)) * rowU4 + (g + SPLIT) * RU]; }
    }
    simdgroup_barrier(mem_flags::mem_threadgroup);
    auto tA = A.template slice<GROUP, 16>(g * GROUP, 0);
    op.run(tA, Bt, cT);
    const device half *sr = sT + (size_t)g * N + n0 + nb;
    const device half *br = bT + (size_t)g * N + n0 + nb;
    const float4 s0v = float4(*(const device half4 *)sr), s1v = float4(*(const device half4 *)(sr + 16));
    const float4 b0v = fma(float4(8.0f), s0v, float4(*(const device half4 *)br));
    const float4 b1v = fma(float4(8.0f), s1v, float4(*(const device half4 *)(br + 16)));
    const float a0 = ascale[m0 * G + g], a1 = ascale[m1 * G + g];
    const float x0 = xs[m0 * G + g], x1 = xs[m1 * G + g];
    for (int i = 0; i < 16; i++) {
      const int j = (i & 3);
      const float s = (i >> 3) ? s1v[j] : s0v[j];
      const float b = (i >> 3) ? b1v[j] : b0v[j];
      const bool hi = (i >> 2) & 1;
      acc[i] = fma(s * (hi ? a1 : a0), float(cT[i]), acc[i]);
      accb[i] = fma(b, hi ? x1 : x0, accb[i]);
    }
    simdgroup_barrier(mem_flags::mem_threadgroup);
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  threadgroup float *red = (threadgroup float *)tiles;
  for (int i = 0; i < 16; i++) {
    const int m = mrow + 8 * ((i >> 2) & 1), n = nb + (i & 3) + 16 * (i >> 3);
    red[sg * 512 + m * 32 + n] = acc[i] + accb[i];
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int e = int(tid); e < rows * 32; e += SPLIT * 32) {
    float v = 0.0f;
    for (int q = 0; q < SPLIT; q++) { v += red[q * 512 + e]; }
    out[(size_t)(e >> 5) * N + n0 + (e & 31)] = ok ? v : as_type<float>(0x7fc00000u);
  }
  #undef DF2_LO
  #undef DF2_HI
}

#define DEFINE_DF2_W4_KERNELS(GROUP)                                           \
[[max_total_threads_per_threadgroup(256)]]                                     \
kernel void df2_w4g##GROUP##_1(                                                \
  device const char *xq [[buffer(0)]],                                         \
  device const uint32_t *w0 [[buffer(1)]],                                     \
  device const half *s0 [[buffer(2)]],                                         \
  device const half *b0 [[buffer(3)]],                                         \
  device const float *ascale [[buffer(4)]],                                    \
  device const float *xs [[buffer(5)]],                                        \
  device const int *ksz [[buffer(6)]],                                         \
  device float *out0 [[buffer(7)]],                                            \
  uint tid [[thread_index_in_threadgroup]],                                    \
  uint lane [[thread_index_in_simdgroup]],                                     \
  uint sg [[simdgroup_index_in_threadgroup]],                                  \
  uint tgid [[threadgroup_position_in_grid]]) {                                \
  threadgroup uint4 tiles[8 * 32 * (GROUP / 16)];                              \
  df2_w4_nax_core<GROUP, 8>(xq, w0, s0, b0, ascale, xs, out0, ksz[0], ksz[1], ksz[2], int(tgid), tid, lane, sg, tiles); \
}                                                                              \
[[max_total_threads_per_threadgroup(256)]]                                     \
kernel void df2_w4g##GROUP##_2(                                                \
  device const char *xq [[buffer(0)]],                                         \
  device const uint32_t *w0 [[buffer(1)]],                                     \
  device const uint32_t *w1 [[buffer(2)]],                                     \
  device const half *s0 [[buffer(3)]],                                         \
  device const half *s1 [[buffer(4)]],                                         \
  device const half *b0 [[buffer(5)]],                                         \
  device const half *b1 [[buffer(6)]],                                         \
  device const float *ascale [[buffer(7)]],                                    \
  device const float *xs [[buffer(8)]],                                        \
  device const int *ksz [[buffer(9)]],                                         \
  device float *out0 [[buffer(10)]],                                           \
  device float *out1 [[buffer(11)]],                                           \
  uint tid [[thread_index_in_threadgroup]],                                    \
  uint lane [[thread_index_in_simdgroup]],                                     \
  uint sg [[simdgroup_index_in_threadgroup]],                                  \
  uint tgid [[threadgroup_position_in_grid]]) {                                \
  int bx = int(tgid);                                                          \
  device const uint32_t *w = w0; device const half *sT = s0; device const half *bT = b0; \
  device float *out = out0; int N = ksz[2];                                    \
  if (bx >= N / 32) { bx -= N / 32; w = w1; sT = s1; bT = b1; out = out1; N = ksz[3]; } \
  threadgroup uint4 tiles[8 * 32 * (GROUP / 16)];                              \
  df2_w4_nax_core<GROUP, 8>(xq, w, sT, bT, ascale, xs, out, ksz[0], ksz[1], N, bx, tid, lane, sg, tiles); \
}                                                                              \
[[max_total_threads_per_threadgroup(256)]]                                     \
kernel void df2_w4g##GROUP##_3(                                                \
  device const char *xq [[buffer(0)]],                                         \
  device const uint32_t *w0 [[buffer(1)]],                                     \
  device const uint32_t *w1 [[buffer(2)]],                                     \
  device const uint32_t *w2 [[buffer(3)]],                                     \
  device const half *s0 [[buffer(4)]],                                         \
  device const half *s1 [[buffer(5)]],                                         \
  device const half *s2 [[buffer(6)]],                                         \
  device const half *b0 [[buffer(7)]],                                         \
  device const half *b1 [[buffer(8)]],                                         \
  device const half *b2 [[buffer(9)]],                                         \
  device const float *ascale [[buffer(10)]],                                   \
  device const float *xs [[buffer(11)]],                                       \
  device const int *ksz [[buffer(12)]],                                        \
  device float *out0 [[buffer(13)]],                                           \
  device float *out1 [[buffer(14)]],                                           \
  device float *out2 [[buffer(15)]],                                           \
  uint tid [[thread_index_in_threadgroup]],                                    \
  uint lane [[thread_index_in_simdgroup]],                                     \
  uint sg [[simdgroup_index_in_threadgroup]],                                  \
  uint tgid [[threadgroup_position_in_grid]]) {                                \
  int bx = int(tgid);                                                          \
  device const uint32_t *w = w0; device const half *sT = s0; device const half *bT = b0; \
  device float *out = out0; int N = ksz[2];                                    \
  if (bx >= N / 32) { bx -= N / 32; w = w1; sT = s1; bT = b1; out = out1; N = ksz[3]; } \
  if (bx >= N / 32) { bx -= N / 32; w = w2; sT = s2; bT = b2; out = out2; N = ksz[4]; } \
  threadgroup uint4 tiles[8 * 32 * (GROUP / 16)];                              \
  df2_w4_nax_core<GROUP, 8>(xq, w, sT, bT, ascale, xs, out, ksz[0], ksz[1], N, bx, tid, lane, sg, tiles); \
}                                                                              \
[[max_total_threads_per_threadgroup(256)]]                                     \
kernel void df2_w4g##GROUP##_4(                                                \
  device const char *xq [[buffer(0)]],                                         \
  device const uint32_t *w0 [[buffer(1)]],                                     \
  device const uint32_t *w1 [[buffer(2)]],                                     \
  device const uint32_t *w2 [[buffer(3)]],                                     \
  device const uint32_t *w3 [[buffer(4)]],                                     \
  device const half *s0 [[buffer(5)]],                                         \
  device const half *s1 [[buffer(6)]],                                         \
  device const half *s2 [[buffer(7)]],                                         \
  device const half *s3 [[buffer(8)]],                                         \
  device const half *b0 [[buffer(9)]],                                         \
  device const half *b1 [[buffer(10)]],                                        \
  device const half *b2 [[buffer(11)]],                                        \
  device const half *b3 [[buffer(12)]],                                        \
  device const float *ascale [[buffer(13)]],                                   \
  device const float *xs [[buffer(14)]],                                       \
  device const int *ksz [[buffer(15)]],                                        \
  device float *out0 [[buffer(16)]],                                           \
  device float *out1 [[buffer(17)]],                                           \
  device float *out2 [[buffer(18)]],                                           \
  device float *out3 [[buffer(19)]],                                           \
  uint tid [[thread_index_in_threadgroup]],                                    \
  uint lane [[thread_index_in_simdgroup]],                                     \
  uint sg [[simdgroup_index_in_threadgroup]],                                  \
  uint tgid [[threadgroup_position_in_grid]]) {                                \
  int bx = int(tgid);                                                          \
  device const uint32_t *w = w0; device const half *sT = s0; device const half *bT = b0; \
  device float *out = out0; int N = ksz[2];                                    \
  if (bx >= N / 32) { bx -= N / 32; w = w1; sT = s1; bT = b1; out = out1; N = ksz[3]; } \
  if (bx >= N / 32) { bx -= N / 32; w = w2; sT = s2; bT = b2; out = out2; N = ksz[4]; } \
  if (bx >= N / 32) { bx -= N / 32; w = w3; sT = s3; bT = b3; out = out3; N = ksz[5]; } \
  threadgroup uint4 tiles[8 * 32 * (GROUP / 16)];                              \
  df2_w4_nax_core<GROUP, 8>(xq, w, sT, bT, ascale, xs, out, ksz[0], ksz[1], N, bx, tid, lane, sg, tiles); \
}                                                                              \
[[max_total_threads_per_threadgroup(256)]]                                     \
kernel void df2_w4g##GROUP##_5(                                                \
  device const char *xq [[buffer(0)]],                                         \
  device const uint32_t *w0 [[buffer(1)]],                                     \
  device const uint32_t *w1 [[buffer(2)]],                                     \
  device const uint32_t *w2 [[buffer(3)]],                                     \
  device const uint32_t *w3 [[buffer(4)]],                                     \
  device const uint32_t *w4 [[buffer(5)]],                                     \
  device const half *s0 [[buffer(6)]],                                         \
  device const half *s1 [[buffer(7)]],                                         \
  device const half *s2 [[buffer(8)]],                                         \
  device const half *s3 [[buffer(9)]],                                         \
  device const half *s4 [[buffer(10)]],                                        \
  device const half *b0 [[buffer(11)]],                                        \
  device const half *b1 [[buffer(12)]],                                        \
  device const half *b2 [[buffer(13)]],                                        \
  device const half *b3 [[buffer(14)]],                                        \
  device const half *b4 [[buffer(15)]],                                        \
  device const float *ascale [[buffer(16)]],                                   \
  device const float *xs [[buffer(17)]],                                       \
  device const int *ksz [[buffer(18)]],                                        \
  device float *out0 [[buffer(19)]],                                           \
  device float *out1 [[buffer(20)]],                                           \
  device float *out2 [[buffer(21)]],                                           \
  device float *out3 [[buffer(22)]],                                           \
  device float *out4 [[buffer(23)]],                                           \
  uint tid [[thread_index_in_threadgroup]],                                    \
  uint lane [[thread_index_in_simdgroup]],                                     \
  uint sg [[simdgroup_index_in_threadgroup]],                                  \
  uint tgid [[threadgroup_position_in_grid]]) {                                \
  int bx = int(tgid);                                                          \
  device const uint32_t *w = w0; device const half *sT = s0; device const half *bT = b0; \
  device float *out = out0; int N = ksz[2];                                    \
  if (bx >= N / 32) { bx -= N / 32; w = w1; sT = s1; bT = b1; out = out1; N = ksz[3]; } \
  if (bx >= N / 32) { bx -= N / 32; w = w2; sT = s2; bT = b2; out = out2; N = ksz[4]; } \
  if (bx >= N / 32) { bx -= N / 32; w = w3; sT = s3; bT = b3; out = out3; N = ksz[5]; } \
  if (bx >= N / 32) { bx -= N / 32; w = w4; sT = s4; bT = b4; out = out4; N = ksz[6]; } \
  threadgroup uint4 tiles[8 * 32 * (GROUP / 16)];                              \
  df2_w4_nax_core<GROUP, 8>(xq, w, sT, bT, ascale, xs, out, ksz[0], ksz[1], N, bx, tid, lane, sg, tiles); \
}                                                                              \
[[max_total_threads_per_threadgroup(256)]]                                     \
kernel void df2_w4g##GROUP##_6(                                                \
  device const char *xq [[buffer(0)]],                                         \
  device const uint32_t *w0 [[buffer(1)]],                                     \
  device const uint32_t *w1 [[buffer(2)]],                                     \
  device const uint32_t *w2 [[buffer(3)]],                                     \
  device const uint32_t *w3 [[buffer(4)]],                                     \
  device const uint32_t *w4 [[buffer(5)]],                                     \
  device const uint32_t *w5 [[buffer(6)]],                                     \
  device const half *s0 [[buffer(7)]],                                         \
  device const half *s1 [[buffer(8)]],                                         \
  device const half *s2 [[buffer(9)]],                                         \
  device const half *s3 [[buffer(10)]],                                        \
  device const half *s4 [[buffer(11)]],                                        \
  device const half *s5 [[buffer(12)]],                                        \
  device const half *b0 [[buffer(13)]],                                        \
  device const half *b1 [[buffer(14)]],                                        \
  device const half *b2 [[buffer(15)]],                                        \
  device const half *b3 [[buffer(16)]],                                        \
  device const half *b4 [[buffer(17)]],                                        \
  device const half *b5 [[buffer(18)]],                                        \
  device const float *ascale [[buffer(19)]],                                   \
  device const float *xs [[buffer(20)]],                                       \
  device const int *ksz [[buffer(21)]],                                        \
  device float *out0 [[buffer(22)]],                                           \
  device float *out1 [[buffer(23)]],                                           \
  device float *out2 [[buffer(24)]],                                           \
  device float *out3 [[buffer(25)]],                                           \
  device float *out4 [[buffer(26)]],                                           \
  device float *out5 [[buffer(27)]],                                           \
  uint tid [[thread_index_in_threadgroup]],                                    \
  uint lane [[thread_index_in_simdgroup]],                                     \
  uint sg [[simdgroup_index_in_threadgroup]],                                  \
  uint tgid [[threadgroup_position_in_grid]]) {                                \
  int bx = int(tgid);                                                          \
  device const uint32_t *w = w0; device const half *sT = s0; device const half *bT = b0; \
  device float *out = out0; int N = ksz[2];                                    \
  if (bx >= N / 32) { bx -= N / 32; w = w1; sT = s1; bT = b1; out = out1; N = ksz[3]; } \
  if (bx >= N / 32) { bx -= N / 32; w = w2; sT = s2; bT = b2; out = out2; N = ksz[4]; } \
  if (bx >= N / 32) { bx -= N / 32; w = w3; sT = s3; bT = b3; out = out3; N = ksz[5]; } \
  if (bx >= N / 32) { bx -= N / 32; w = w4; sT = s4; bT = b4; out = out4; N = ksz[6]; } \
  if (bx >= N / 32) { bx -= N / 32; w = w5; sT = s5; bT = b5; out = out5; N = ksz[7]; } \
  threadgroup uint4 tiles[8 * 32 * (GROUP / 16)];                              \
  df2_w4_nax_core<GROUP, 8>(xq, w, sT, bT, ascale, xs, out, ksz[0], ksz[1], N, bx, tid, lane, sg, tiles); \
}
DEFINE_DF2_W4_KERNELS(64)
DEFINE_DF2_W4_KERNELS(128)
#undef DEFINE_DF2_W4_KERNELS

[[max_total_threads_per_threadgroup(128)]]
kernel void df2_qkv_norm_rope(
  device const float *q [[buffer(0)]],
  device const float *k [[buffer(1)]],
  device const float *v [[buffer(2)]],
  device const float *qw [[buffer(3)]],
  device const float *kw [[buffer(4)]],
  device const float *freqs [[buffer(5)]],
  device const int *params [[buffer(6)]],
  device const float *fparams [[buffer(7)]],
  device float *q_out [[buffer(8)]],
  device float *k_out [[buffer(9)]],
  device float *v_out [[buffer(10)]],
  uint lane [[thread_index_in_simdgroup]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint tgid [[threadgroup_position_in_grid]]
) {
  const int L = params[0];
  const int offset = params[1];
  const float eps = fparams[0];
  const float mscale = fparams[1];
  const int vecIdx = int(tgid) * 4 + int(sg);
  if (vecIdx >= 48 * L) return;
  const int hTotal = vecIdx / L;
  const int s = vecIdx % L;
  const int d0 = int(lane);
  const int d1 = d0 + 32;
  if (hTotal >= 40) {
    const int h = hTotal - 40;
    const size_t srcBase = ((size_t)s * 8 + h) * 128;
    const size_t dstBase = ((size_t)h * L + s) * 128;
    v_out[dstBase + d0] = float(v[srcBase + d0]);
    v_out[dstBase + d0 + 64] = float(v[srcBase + d0 + 64]);
    v_out[dstBase + d1] = float(v[srcBase + d1]);
    v_out[dstBase + d1 + 64] = float(v[srcBase + d1 + 64]);
    return;
  }
  const bool isK = hTotal >= 32;
  const int h = isK ? (hTotal - 32) : hTotal;
  const int H = isK ? 8 : 32;
  const device float *src = isK ? k : q;
  const size_t srcBase = ((size_t)s * H + h) * 128;
  const size_t dstBase = ((size_t)h * L + s) * 128;
  float acc = 0.0f;
  for (int i = 0; i < 4; i++) {
    const float xi = float(src[srcBase + 4 * int(lane) + i]);
    acc += xi * xi;
  }
  const float inv_mean = metal::precise::rsqrt(simd_sum(acc) / 128u + eps);
  const float x0 = float(src[srcBase + d0]);
  const float y0 = float(src[srcBase + d0 + 64]);
  const float x1 = float(src[srcBase + d1]);
  const float y1 = float(src[srcBase + d1 + 64]);
  const device float *w = isK ? kw : qw;
  const float nx0 = (w[d0] * (x0 * inv_mean)) * mscale;
  const float ny0 = (w[d0 + 64] * (y0 * inv_mean)) * mscale;
  const float nx1 = (w[d1] * (x1 * inv_mean)) * mscale;
  const float ny1 = (w[d1 + 64] * (y1 * inv_mean)) * mscale;
  const float pos = float(offset + s);
  const float th0 = pos * (1.0f / freqs[d0]);
  const float c0 = metal::fast::cos(th0), s0 = metal::fast::sin(th0);
  const float th1 = pos * (1.0f / freqs[d1]);
  const float c1 = metal::fast::cos(th1), s1 = metal::fast::sin(th1);
  device float *dst = isK ? k_out : q_out;
  dst[dstBase + d0] = nx0 * c0 - ny0 * s0;
  dst[dstBase + d0 + 64] = nx0 * s0 + ny0 * c0;
  dst[dstBase + d1] = nx1 * c1 - ny1 * s1;
  dst[dstBase + d1 + 64] = nx1 * s1 + ny1 * c1;
}

[[max_total_threads_per_threadgroup(128)]]
kernel void df2_ctx_kv_norm_rope(
  device const float *k [[buffer(0)]],
  device const float *v [[buffer(1)]],
  device const float *kw [[buffer(2)]],
  device const float *freqs [[buffer(3)]],
  device const int *params [[buffer(4)]],
  device const float *fparams [[buffer(5)]],
  device float *k_out [[buffer(6)]],
  device float *v_out [[buffer(7)]],
  uint lane [[thread_index_in_simdgroup]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint tgid [[threadgroup_position_in_grid]]
) {
  const int C = params[0];
  const int offset = params[1];
  const float eps = fparams[0];
  const float mscale = fparams[1];
  const int vecIdx = int(tgid) * 4 + int(sg);
  if (vecIdx >= 16 * C) return;
  const int hTotal = vecIdx / C;
  const int s = vecIdx % C;
  const int d0 = int(lane);
  const int d1 = d0 + 32;
  if (hTotal >= 8) {
    const int h = hTotal - 8;
    const size_t srcBase = ((size_t)s * 8 + h) * 128;
    const size_t dstBase = ((size_t)h * C + s) * 128;
    v_out[dstBase + d0] = float(v[srcBase + d0]);
    v_out[dstBase + d0 + 64] = float(v[srcBase + d0 + 64]);
    v_out[dstBase + d1] = float(v[srcBase + d1]);
    v_out[dstBase + d1 + 64] = float(v[srcBase + d1 + 64]);
    return;
  }
  const int h = hTotal;
  const size_t srcBase = ((size_t)s * 8 + h) * 128;
  const size_t dstBase = ((size_t)h * C + s) * 128;
  float acc = 0.0f;
  for (int i = 0; i < 4; i++) {
    const float xi = float(k[srcBase + 4 * int(lane) + i]);
    acc += xi * xi;
  }
  const float inv_mean = metal::precise::rsqrt(simd_sum(acc) / 128u + eps);
  const float x0 = float(k[srcBase + d0]);
  const float y0 = float(k[srcBase + d0 + 64]);
  const float x1 = float(k[srcBase + d1]);
  const float y1 = float(k[srcBase + d1 + 64]);
  const float nx0 = (kw[d0] * (x0 * inv_mean)) * mscale;
  const float ny0 = (kw[d0 + 64] * (y0 * inv_mean)) * mscale;
  const float nx1 = (kw[d1] * (x1 * inv_mean)) * mscale;
  const float ny1 = (kw[d1 + 64] * (y1 * inv_mean)) * mscale;
  const float pos = float(offset + s);
  const float th0 = pos * (1.0f / freqs[d0]);
  const float c0 = metal::fast::cos(th0), s0 = metal::fast::sin(th0);
  const float th1 = pos * (1.0f / freqs[d1]);
  const float c1 = metal::fast::cos(th1), s1 = metal::fast::sin(th1);
  k_out[dstBase + d0] = nx0 * c0 - ny0 * s0;
  k_out[dstBase + d0 + 64] = nx0 * s0 + ny0 * c0;
  k_out[dstBase + d1] = nx1 * c1 - ny1 * s1;
  k_out[dstBase + d1 + 64] = nx1 * s1 + ny1 * c1;
}

[[max_total_threads_per_threadgroup(128)]]
kernel void df2_qkv_all_norm_rope(
  device const float *q [[buffer(0)]],
  device const float *bk [[buffer(1)]],
  device const float *bv [[buffer(2)]],
  device const float *ck [[buffer(3)]],
  device const float *cv [[buffer(4)]],
  device const float *qw [[buffer(5)]],
  device const float *kw [[buffer(6)]],
  device const float *freqs [[buffer(7)]],
  device const int *params [[buffer(8)]],
  device const float *fparams [[buffer(9)]],
  device float *q_out [[buffer(10)]],
  device float *k_out [[buffer(11)]],
  device float *v_out [[buffer(12)]],
  uint lane [[thread_index_in_simdgroup]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint tgid [[threadgroup_position_in_grid]]
) {
  const int L = params[0];
  const int C = params[1];
  const int offset = params[2];
  const int CL = C + L;
  const float eps = fparams[0];
  const float mscale = fparams[1];
  const int vecIdx = int(tgid) * 4 + int(sg);
  if (vecIdx >= 32 * L + 16 * CL) return;
  const int d0 = int(lane);
  const int d1 = d0 + 32;
  if (vecIdx >= 32 * L + 8 * CL) {
    const int vIdx = vecIdx - (32 * L + 8 * CL);
    const int h = vIdx / CL;
    const int t = vIdx % CL;
    const device float *vsrc = (t < C) ? cv : bv;
    const int s = (t < C) ? t : (t - C);
    const size_t srcBase = ((size_t)s * 8 + h) * 128;
    const size_t dstBase = ((size_t)h * CL + t) * 128;
    v_out[dstBase + d0] = float(vsrc[srcBase + d0]);
    v_out[dstBase + d0 + 64] = float(vsrc[srcBase + d0 + 64]);
    v_out[dstBase + d1] = float(vsrc[srcBase + d1]);
    v_out[dstBase + d1 + 64] = float(vsrc[srcBase + d1 + 64]);
    return;
  }
  const bool isK = vecIdx >= 32 * L;
  int h, t, s, H, S_out;
  const device float *src;
  const device float *w;
  device float *dst;
  float pos;
  if (!isK) {
    h = vecIdx / L;
    s = vecIdx % L;
    t = s;
    H = 32;
    S_out = L;
    src = q;
    w = qw;
    dst = q_out;
    pos = float(offset + C + s);
  } else {
    const int kIdx = vecIdx - 32 * L;
    h = kIdx / CL;
    t = kIdx % CL;
    s = (t < C) ? t : (t - C);
    H = 8;
    S_out = CL;
    src = (t < C) ? ck : bk;
    w = kw;
    dst = k_out;
    pos = float(offset + t);
  }
  const size_t srcBase = ((size_t)s * H + h) * 128;
  const size_t dstBase = ((size_t)h * S_out + t) * 128;
  float acc = 0.0f;
  for (int i = 0; i < 4; i++) {
    const float xi = float(src[srcBase + 4 * int(lane) + i]);
    acc += xi * xi;
  }
  const float inv_mean = metal::precise::rsqrt(simd_sum(acc) / 128u + eps);
  const float x0 = float(src[srcBase + d0]);
  const float y0 = float(src[srcBase + d0 + 64]);
  const float x1 = float(src[srcBase + d1]);
  const float y1 = float(src[srcBase + d1 + 64]);
  const float nx0 = (w[d0] * (x0 * inv_mean)) * mscale;
  const float ny0 = (w[d0 + 64] * (y0 * inv_mean)) * mscale;
  const float nx1 = (w[d1] * (x1 * inv_mean)) * mscale;
  const float ny1 = (w[d1 + 64] * (y1 * inv_mean)) * mscale;
  const float th0 = pos * (1.0f / freqs[d0]);
  const float c0 = metal::fast::cos(th0), s0 = metal::fast::sin(th0);
  const float th1 = pos * (1.0f / freqs[d1]);
  const float c1 = metal::fast::cos(th1), s1 = metal::fast::sin(th1);
  dst[dstBase + d0] = nx0 * c0 - ny0 * s0;
  dst[dstBase + d0 + 64] = nx0 * s0 + ny0 * c0;
  dst[dstBase + d1] = nx1 * c1 - ny1 * s1;
  dst[dstBase + d1 + 64] = nx1 * s1 + ny1 * c1;
}

template <int KG>
static inline void df2_rms_q8g_impl(
  device const float *x,
  device const float *weight,
  device const int *dsz,
  device const float *eps_arr,
  device float *out_norm,
  device char *xq,
  device float *ascale,
  device float *xs,
  uint tid,
  uint lane,
  uint sg,
  uint2 tgid,
  threadgroup float (&shared_sq)[32]
) {
  constexpr int D = 4096;
  const int l = int(tgid.y);
  const int L = dsz[1];
  const int c0 = int(tid) * 16;
  const int G = D / KG;
  const int g = int(tid) / (KG / 16);
  if (l >= L) {
    if (l < 16) {
      const size_t qRowBase = (size_t)l * D + c0;
      device char4 *dst = (device char4 *)(xq + qRowBase);
      for (int u = 0; u < 4; u++) { dst[u] = char4(0); }
      if ((int(tid) & ((KG / 16) - 1)) == 0) {
        ascale[l * G + g] = 0.0f;
        xs[l * G + g] = 0.0f;
      }
    }
    return;
  }
  const size_t rowBase = (size_t)l * D + c0;
  float v[16];
  float s4[4];
  for (int k = 0; k < 4; k++) {
    float ak = 0.0f;
    for (int i = 0; i < 4; i++) {
      const int u = 4 * k + i;
      const float a = float(x[rowBase + u]);
      v[u] = a;
      ak += a * a;
    }
    s4[k] = ak;
  }
  float sq = (s4[0] + s4[1]) + (s4[2] + s4[3]);
  sq += simd_shuffle_xor(sq, 1);
  sq += simd_shuffle_xor(sq, 2);
  sq += simd_shuffle_xor(sq, 4);
  if ((lane & 7u) == 0) { shared_sq[(sg << 2) | (lane >> 3)] = sq; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  if (sg == 0) {
    const float tot = simd_sum(shared_sq[lane]);
    if (lane == 0) {
      shared_sq[0] = metal::precise::rsqrt(tot / uint(D) + eps_arr[0]);
    }
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  const float scale = shared_sq[0];
  float nv[16];
  float local_amax = 0.0f;
  for (int u = 0; u < 16; u++) {
    const float y = float(weight[c0 + u]) * (v[u] * scale);
    out_norm[rowBase + u] = y;
    nv[u] = y;
    local_amax = max(local_amax, fabs(y));
  }
  local_amax = max(local_amax, simd_shuffle_xor(local_amax, 1));
  local_amax = max(local_amax, simd_shuffle_xor(local_amax, 2));
  if (KG == 128) {
    local_amax = max(local_amax, simd_shuffle_xor(local_amax, 4));
  }
  float seq_sum = 0.0f;
  const uint grpBase = lane & ~uint((KG / 16) - 1);
  for (int step = 0; step < (KG / 16); step++) {
    seq_sum = simd_shuffle(seq_sum, ushort(grpBase | uint(step > 0 ? step - 1 : 0)));
    if ((int(lane) & ((KG / 16) - 1)) == step) {
      for (int u = 0; u < 16; u++) { seq_sum += nv[u]; }
    }
  }
  const float a = local_amax > 0.0f ? local_amax / 127.0f : 1.0f;
  const float ia = 1.0f / a;
  device char4 *dst = (device char4 *)(xq + rowBase);
  for (int u = 0; u < 4; u++) {
    const float4 fv = float4(nv[4 * u], nv[4 * u + 1], nv[4 * u + 2], nv[4 * u + 3]);
    dst[u] = char4(int4(rint(fv * ia)));
  }
  if ((int(lane) & ((KG / 16) - 1)) == (KG / 16) - 1) {
    ascale[l * G + g] = a;
    xs[l * G + g] = seq_sum;
  }
}

[[max_total_threads_per_threadgroup(256)]]
kernel void df2_rms_q8g64(
  device const float *x [[buffer(0)]],
  device const float *weight [[buffer(1)]],
  device const int *dsz [[buffer(2)]],
  device const float *eps_arr [[buffer(3)]],
  device float *out_norm [[buffer(4)]],
  device char *xq [[buffer(5)]],
  device float *ascale [[buffer(6)]],
  device float *xs [[buffer(7)]],
  uint tid [[thread_index_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint2 tgid [[threadgroup_position_in_grid]]
) {
  threadgroup float shared_sq[32];
  df2_rms_q8g_impl<64>(x, weight, dsz, eps_arr, out_norm, xq, ascale, xs, tid, lane, sg, tgid, shared_sq);
}

[[max_total_threads_per_threadgroup(256)]]
kernel void df2_rms_q8g128(
  device const float *x [[buffer(0)]],
  device const float *weight [[buffer(1)]],
  device const int *dsz [[buffer(2)]],
  device const float *eps_arr [[buffer(3)]],
  device float *out_norm [[buffer(4)]],
  device char *xq [[buffer(5)]],
  device float *ascale [[buffer(6)]],
  device float *xs [[buffer(7)]],
  uint tid [[thread_index_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint2 tgid [[threadgroup_position_in_grid]]
) {
  threadgroup float shared_sq[32];
  df2_rms_q8g_impl<128>(x, weight, dsz, eps_arr, out_norm, xq, ascale, xs, tid, lane, sg, tgid, shared_sq);
}

[[max_total_threads_per_threadgroup(256)]]
kernel void df2_dyn_conv_rms_4096(
  device const float *h [[buffer(0)]],
  device const float *dyn [[buffer(1)]],
  device const float *base [[buffer(2)]],
  device const float *res [[buffer(3)]],
  device const float *weight [[buffer(4)]],
  device const int *dsz [[buffer(5)]],
  device const float *eps_arr [[buffer(6)]],
  device float *out_res [[buffer(7)]],
  device float *out_norm [[buffer(8)]],
  uint tid [[thread_index_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint2 tgid [[threadgroup_position_in_grid]]
) {
  constexpr int D = 4096;
  const int l = int(tgid.y);
  const int L = dsz[1];
  if (l >= L) return;
  const int dw = 4 * (D / 16);
  const int g = int(tid);
  const int c0 = g * 16;
  const size_t rowBase = (size_t)l * D + c0;
  const float d0 = float(dyn[l * dw + (dw / 2) + g]);
  const float d1 = l >= 1 ? float(dyn[l * dw + (dw / 2) + (D / 16) + g]) : 0.0f;
  float v[16];
  float s4[4];
  for (int k = 0; k < 4; k++) {
    float ak = 0.0f;
    for (int i = 0; i < 4; i++) {
      const int u = 4 * k + i;
      const int c = c0 + u;
      float acc = float(res[rowBase + u]) + (float(base[2 * D + c]) + d0) * float(h[rowBase + u]);
      if (l >= 1) {
        acc += (float(base[3 * D + c]) + d1) * float(h[rowBase - D + u]);
      }
      v[u] = acc;
      out_res[rowBase + u] = acc;
      ak += acc * acc;
    }
    s4[k] = ak;
  }
  float sq = (s4[0] + s4[1]) + (s4[2] + s4[3]);
  sq += simd_shuffle_xor(sq, 1);
  sq += simd_shuffle_xor(sq, 2);
  sq += simd_shuffle_xor(sq, 4);
  threadgroup float shared_sq[32];
  if ((lane & 7u) == 0) { shared_sq[(sg << 2) | (lane >> 3)] = sq; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  if (sg == 0) {
    const float tot = simd_sum(shared_sq[lane]);
    if (lane == 0) {
      shared_sq[0] = metal::precise::rsqrt(tot / uint(D) + eps_arr[0]);
    }
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  const float scale = shared_sq[0];
  for (int u = 0; u < 16; u++) {
    out_norm[rowBase + u] = float(weight[c0 + u]) * (v[u] * scale);
  }
}

template <int KG, bool WRITE_RES>
static inline void df2_dyn_conv_rms_q8g_impl(
  device const float *h,
  device const float *dyn,
  device const float *base,
  device const float *res,
  device const float *weight,
  device const int *dsz,
  device const float *eps_arr,
  device float *out_res,
  device float *out_norm,
  device char *xq,
  device float *ascale,
  device float *xs,
  uint tid,
  uint lane,
  uint sg,
  uint2 tgid,
  threadgroup float (&shared_sq)[32]
) {
  constexpr int D = 4096;
  const int l = int(tgid.y);
  const int L = dsz[1];
  const int qStart = dsz[2];
  const int qm = l - qStart;
  const int c0 = int(tid) * 16;
  const int G = D / KG;
  const int qg = int(tid) / (KG / 16);
  if (!WRITE_RES && l < qStart) return;
  if (l >= L) {
    if (qm >= 0 && qm < 16) {
      const size_t qRowBase = (size_t)qm * D + c0;
      device char4 *dst = (device char4 *)(xq + qRowBase);
      for (int u = 0; u < 4; u++) { dst[u] = char4(0); }
      if ((int(tid) & ((KG / 16) - 1)) == 0) {
        ascale[qm * G + qg] = 0.0f;
        xs[qm * G + qg] = 0.0f;
      }
    }
    return;
  }
  const int dw = 4 * (D / 16);
  const int g = int(tid);
  const size_t rowBase = (size_t)l * D + c0;
  const float d0 = float(dyn[l * dw + (dw / 2) + g]);
  const float d1 = l >= 1 ? float(dyn[l * dw + (dw / 2) + (D / 16) + g]) : 0.0f;
  float v[16];
  float s4[4];
  for (int k = 0; k < 4; k++) {
    float ak = 0.0f;
    for (int i = 0; i < 4; i++) {
      const int u = 4 * k + i;
      const int c = c0 + u;
      float acc = float(res[rowBase + u]) + (float(base[2 * D + c]) + d0) * float(h[rowBase + u]);
      if (l >= 1) {
        acc += (float(base[3 * D + c]) + d1) * float(h[rowBase - D + u]);
      }
      v[u] = acc;
      if (WRITE_RES) { out_res[rowBase + u] = acc; }
      ak += acc * acc;
    }
    s4[k] = ak;
  }
  float sq = (s4[0] + s4[1]) + (s4[2] + s4[3]);
  sq += simd_shuffle_xor(sq, 1);
  sq += simd_shuffle_xor(sq, 2);
  sq += simd_shuffle_xor(sq, 4);
  if ((lane & 7u) == 0) { shared_sq[(sg << 2) | (lane >> 3)] = sq; }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  if (sg == 0) {
    const float tot = simd_sum(shared_sq[lane]);
    if (lane == 0) {
      shared_sq[0] = metal::precise::rsqrt(tot / uint(D) + eps_arr[0]);
    }
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  const float scale = shared_sq[0];
  float nv[16];
  float local_amax = 0.0f;
  for (int u = 0; u < 16; u++) {
    const float y = float(weight[c0 + u]) * (v[u] * scale);
    nv[u] = y;
    local_amax = max(local_amax, fabs(y));
  }
  if (qm >= 0 && qm < 16) {
    const size_t qRowBase = (size_t)qm * D + c0;
    for (int u = 0; u < 16; u++) {
      out_norm[qRowBase + u] = nv[u];
    }
    local_amax = max(local_amax, simd_shuffle_xor(local_amax, 1));
    local_amax = max(local_amax, simd_shuffle_xor(local_amax, 2));
    if (KG == 128) {
      local_amax = max(local_amax, simd_shuffle_xor(local_amax, 4));
    }
    float seq_sum = 0.0f;
    const uint grpBase = lane & ~uint((KG / 16) - 1);
    for (int step = 0; step < (KG / 16); step++) {
      seq_sum = simd_shuffle(seq_sum, ushort(grpBase | uint(step > 0 ? step - 1 : 0)));
      if ((int(lane) & ((KG / 16) - 1)) == step) {
        for (int u = 0; u < 16; u++) { seq_sum += nv[u]; }
      }
    }
    const float a = local_amax > 0.0f ? local_amax / 127.0f : 1.0f;
    const float ia = 1.0f / a;
    device char4 *dst = (device char4 *)(xq + qRowBase);
    for (int u = 0; u < 4; u++) {
      const float4 fv = float4(nv[4 * u], nv[4 * u + 1], nv[4 * u + 2], nv[4 * u + 3]);
      dst[u] = char4(int4(rint(fv * ia)));
    }
    if ((int(lane) & ((KG / 16) - 1)) == (KG / 16) - 1) {
      ascale[qm * G + qg] = a;
      xs[qm * G + qg] = seq_sum;
    }
  }
}

#define DEFINE_DF2_DYN_CONV_RMS_Q8G(NAME, KG, WRITE_RES)                       \
[[max_total_threads_per_threadgroup(256)]]                                     \
kernel void NAME(                                                              \
  device const float *h [[buffer(0)]],                                         \
  device const float *dyn [[buffer(1)]],                                       \
  device const float *base [[buffer(2)]],                                      \
  device const float *res [[buffer(3)]],                                       \
  device const float *weight [[buffer(4)]],                                    \
  device const int *dsz [[buffer(5)]],                                         \
  device const float *eps_arr [[buffer(6)]],                                   \
  device float *out_res [[buffer(7)]],                                         \
  device float *out_norm [[buffer(8)]],                                        \
  device char *xq [[buffer(9)]],                                               \
  device float *ascale [[buffer(10)]],                                         \
  device float *xs [[buffer(11)]],                                             \
  uint tid [[thread_index_in_threadgroup]],                                    \
  uint lane [[thread_index_in_simdgroup]],                                     \
  uint sg [[simdgroup_index_in_threadgroup]],                                  \
  uint2 tgid [[threadgroup_position_in_grid]]) {                               \
  threadgroup float shared_sq[32];                                             \
  df2_dyn_conv_rms_q8g_impl<KG, WRITE_RES>(                                    \
    h, dyn, base, res, weight, dsz, eps_arr, out_res, out_norm, xq, ascale, xs, \
    tid, lane, sg, tgid, shared_sq);                                           \
}
DEFINE_DF2_DYN_CONV_RMS_Q8G(df2_dyn_conv_rms_q8g64, 64, true)
DEFINE_DF2_DYN_CONV_RMS_Q8G(df2_dyn_conv_rms_q8g64_tail, 64, false)
DEFINE_DF2_DYN_CONV_RMS_Q8G(df2_dyn_conv_rms_q8g128, 128, true)
DEFINE_DF2_DYN_CONV_RMS_Q8G(df2_dyn_conv_rms_q8g128_tail, 128, false)
#undef DEFINE_DF2_DYN_CONV_RMS_Q8G

[[max_total_threads_per_threadgroup(256)]]
kernel void df2_topk16_mb8(
  device const float *logits [[buffer(0)]],
  device const int *vsz [[buffer(1)]],
  device int *ids [[buffer(2)]],
  device float *vals [[buffer(3)]],
  uint tid [[thread_index_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]],
  uint sg [[simdgroup_index_in_threadgroup]],
  uint2 tgid [[threadgroup_position_in_grid]]
) {
  const uint row = tgid.x;
  const uint blk = tgid.y;
  const int Vn = vsz[0];
  const device float *lr = logits + (size_t)row * Vn;
  const float NEG = -INFINITY;
  float tv[4] = {NEG, NEG, NEG, NEG};
  int ti[4] = {0x7fffffff, 0x7fffffff, 0x7fffffff, 0x7fffffff};
  for (int n = int(blk * 256u + tid); n < Vn; n += 2048) {
    const float v = lr[n];
    if (v > tv[3]) {
      int k = 3;
      while (k > 0 && v > tv[k - 1]) { tv[k] = tv[k - 1]; ti[k] = ti[k - 1]; k--; }
      tv[k] = v;
      ti[k] = n;
    }
  }
  threadgroup float wv[128];
  threadgroup int wi[128];
  for (int r = 0; r < 16; r++) {
    const float bv = tv[0];
    const int bi = ti[0];
    const float m = simd_max(bv);
    const int best_id = simd_min(bv == m ? bi : 0x7fffffff);
    if (bv == m && bi == best_id) {
      wv[sg * 16 + r] = m;
      wi[sg * 16 + r] = best_id;
      tv[0] = tv[1]; tv[1] = tv[2]; tv[2] = tv[3]; tv[3] = NEG;
      ti[0] = ti[1]; ti[1] = ti[2]; ti[2] = ti[3]; ti[3] = 0x7fffffff;
    }
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  if (sg == 0) {
    float sv[4];
    int si[4];
    for (int k = 0; k < 4; k++) {
      sv[k] = wv[lane * 4 + k];
      si[k] = wi[lane * 4 + k];
    }
    const size_t outBase = ((size_t)row * 8u + blk) * 16u;
    for (int r = 0; r < 16; r++) {
      float bv = NEG;
      int bi = 0x7fffffff;
      int bk = 0;
      for (int k = 0; k < 4; k++) {
        const float v = sv[k];
        const int id = si[k];
        if (v > bv || (v == bv && id < bi)) { bv = v; bi = id; bk = k; }
      }
      const float m = simd_max(bv);
      const int best_id = simd_min(bv == m ? bi : 0x7fffffff);
      if (bv == m && bi == best_id) {
        ids[outBase + r] = best_id;
        vals[outBase + r] = m;
        sv[bk] = NEG;
      }
    }
  }
}

[[max_total_threads_per_threadgroup(512)]]
kernel void df2_selector_mb8(
  device const int *cand [[buffer(0)]],
  device const float *unary [[buffer(1)]],
  device const float *proj [[buffer(2)]],
  device const float *pred [[buffer(3)]],
  device const float *succ [[buffer(4)]],
  device const int *anchor [[buffer(5)]],
  constant int &P [[buffer(6)]],
  device int *path [[buffer(7)]],
  uint tid [[thread_index_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]],
  uint sg [[simdgroup_index_in_threadgroup]]
) {
  const float NEG = -INFINITY;
  threadgroup int tc[16][16];
  threadgroup float tu[16][16];
  for (int p = int(sg); p < P; p += 16) {
    float cv[4];
    int ci[4];
    const size_t base = (size_t)p * 128u + lane * 4u;
    for (int k = 0; k < 4; k++) {
      cv[k] = float(unary[base + k]);
      ci[k] = cand[base + k];
    }
    for (int r = 0; r < 16; r++) {
      float bv = NEG;
      int bi = 0x7fffffff;
      int bk = 0;
      for (int k = 0; k < 4; k++) {
        const float v = cv[k];
        const int id = ci[k];
        if (v > bv || (v == bv && id < bi)) { bv = v; bi = id; bk = k; }
      }
      const float m = simd_max(bv);
      const int best_id = simd_min(bv == m ? bi : 0x7fffffff);
      if (bv == m && bi == best_id) {
        tc[p][r] = best_id;
        tu[p][r] = m;
        cv[bk] = NEG;
      }
    }
  }
  threadgroup float ev[2][16];
  threadgroup_barrier(mem_flags::mem_threadgroup);
  int pr = anchor[0];
  for (int p = 0; p < P; p++) {
    const int c = tc[p][sg];
    float acc = 0.0f;
    for (int r = int(lane); r < 256; r += 32) {
      acc += float(pred[(size_t)pr * 256 + r]) * float(proj[p * 256 + r]) * float(succ[(size_t)c * 256 + r]);
    }
    acc = simd_sum(acc);
    const int buf = p & 1;
    if (lane == 0) { ev[buf][sg] = tu[p][sg] + acc; }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    const float v = lane < 16u ? ev[buf][lane] : NEG;
    const float m = simd_max(v);
    const uint best = simd_min(v == m ? lane : 16u);
    pr = tc[p][best];
    if (tid == 0) { path[p] = pr; }
  }
}

