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
using namespace metal;

constant int DRAFT_MAX_TOK = 8;
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
