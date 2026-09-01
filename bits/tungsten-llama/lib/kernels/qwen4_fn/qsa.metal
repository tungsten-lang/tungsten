// QSA (Qwen sparse attention) lightning indexer for Qwen3.8-Flash-Next.
// Reference: transformers Qwen4ExpTextQSAIndexer (verbatim semantics):
//   - index_qk_proj [640,2560] -> q [4,128] | raw_k [128] per token
//   - raw keys cached UN-normed/UN-roped; complete blocks of 4 positions are
//     f32-mean-pooled, k_layernorm'd, then roped AT THE BLOCK-START position
//     (first 64 dims, NeoX pairs (i, i+32)) — static once complete
//   - q: q_layernorm then the same rope at the query position
//   - scores[b] = sum_h relu(q_h . blk_b) / sqrt(128); top-512 blocks by
//     score; selected positions = those blocks' 4 tokens + the incomplete
//     tail (which holds the newest 0-3 positions)
// All grids are FIXED-size with bounds read from buffers, so every step
// records into the replayable dispatch programs.

#include <metal_stdlib>
using namespace metal;

// raw_k[pos0 + t] = qk[t, 512 .. 640). Dispatch: n*128 threads.
kernel void qsa_k_write(
  device const float *__restrict__ qk      [[buffer(0)]],   // [n, 640]
  device       float *__restrict__ k_cache [[buffer(1)]],   // [CTX, 128]
  device const int   *__restrict__ pos0    [[buffer(2)]],
  constant int &n [[buffer(3)]],
  uint __tid [[thread_position_in_grid]]
) {
  int gi = int(__tid);
  if (gi >= n * 128) return;
  int t = gi / 128;
  int i = gi % 128;
  k_cache[(pos0[0] + t) * 128 + i] = qk[t * 640 + 512 + i];
}

// Build pooled/normed/roped block keys for blocks [b_lo, b_hi). One TG of
// 128 per block slot in a FIXED grid of max_blocks; slots outside the range
// return. cos/sin computed in-kernel (selector-side ULP noise only affects
// exact near-ties in the top-k).
[[max_total_threads_per_threadgroup(128)]]
kernel void qsa_build_blocks(
  device const float *__restrict__ raw_k [[buffer(0)]],   // [CTX, 128]
  device const float *__restrict__ w_ln  [[buffer(1)]],   // [128], includes +1
  device       float *__restrict__ blk   [[buffer(2)]],   // [CTX/4, 128]
  device const int   *__restrict__ range [[buffer(3)]],   // [b_lo, b_hi]
  constant float &eps      [[buffer(4)]],
  constant float &log_base [[buffer(5)]],
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __tid   [[thread_position_in_threadgroup]]
) {
  int b = range[0] + int(__tg_id);
  if (b >= range[1]) return;
  int i = int(__tid);
  int base = b * 4 * 128;
  float pooled = 0.25f * (raw_k[base + i] + raw_k[base + 128 + i] +
                          raw_k[base + 256 + i] + raw_k[base + 384 + i]);
  threadgroup float v[128];
  threadgroup float scratch[4];
  v[i] = pooled;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float ss = pooled * pooled;
  float sm = simd_sum(ss);
  if ((i & 31) == 0) scratch[i >> 5] = sm;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float total = scratch[0] + scratch[1] + scratch[2] + scratch[3];
  float rrms = 1.0f / sqrt(total / 128.0f + eps);
  float nv = (pooled * rrms) * w_ln[i];
  v[i] = nv;
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float outv = nv;
  if (i < 64) {
    // rope at the block-start position over the first 64 dims, pairs (i, i+32)
    int p = i & 31;
    float theta = exp(log_base * (-(float)p / 32.0f));
    float angle = (float)(b * 4) * theta;
    float c = cos(angle);
    float s = sin(angle);
    float a = v[p];
    float bb = v[p + 32];
    outv = (i < 32) ? (a * c - bb * s) : (a * s + bb * c);
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  blk[b * 128 + i] = outv;
}

// scores[t, b] = sum_h relu(q[t,h] . blk[b]) / sqrt(128) for b < nb[t].
// q is already normed+roped. Fixed grid: n * max_blocks threads.
kernel void qsa_scores(
  device const float *__restrict__ q      [[buffer(0)]],   // [n, 4, 128]
  device const float *__restrict__ blk    [[buffer(1)]],   // [CTX/4, 128]
  device       float *__restrict__ scores [[buffer(2)]],   // [n, max_blocks]
  device const int   *__restrict__ nb     [[buffer(3)]],   // [n] complete blocks visible
  constant int &max_blocks [[buffer(4)]],
  constant int &n [[buffer(5)]],
  uint __tid [[thread_position_in_grid]]
) {
  int gi = int(__tid);
  if (gi >= n * max_blocks) return;
  int t = gi / max_blocks;
  int b = gi % max_blocks;
  if (b >= nb[t]) return;
  float acc = 0.0f;
  for (int h = 0; h < 4; h++) {
    float dp = 0.0f;
    device const float *qh = q + (t * 4 + h) * 128;
    device const float *kb = blk + b * 128;
    for (int i = 0; i < 128; i++) dp += qh[i] * kb[i];
    acc += max(dp, 0.0f);
  }
  scores[gi] = acc / sqrt(128.0f);
}

// Per-query top-512-block selection + position-list emit. One TG of 512 per
// query token. Histogram threshold select (256 bins over [min,max]): exact
// top-k except ties inside the threshold bin resolve by block order.
// Emits sel[t, 0..ns) = chosen block positions (4 each, ascending block
// order) followed by the tail positions; ns_out[t] = count.
[[max_total_threads_per_threadgroup(512)]]
kernel void qsa_select(
  device const float *__restrict__ scores [[buffer(0)]],   // [n, max_blocks]
  device const int   *__restrict__ nb     [[buffer(1)]],   // [n]
  device const int   *__restrict__ vis    [[buffer(2)]],   // [n] visible positions (pos+1)
  device       int   *__restrict__ sel    [[buffer(3)]],   // [n, budget+3]
  device       int   *__restrict__ ns_out [[buffer(4)]],   // [n]
  constant int &max_blocks [[buffer(5)]],
  constant int &budget_blocks [[buffer(6)]],               // 512
  uint __tg_id [[threadgroup_position_in_grid]],
  uint __tid   [[thread_position_in_threadgroup]]
) {
  int t = int(__tg_id);
  int tid = int(__tid);
  int blocks = nb[t];
  int visible = vis[t];
  device const float *sc = scores + t * max_blocks;
  device int *out = sel + t * (budget_blocks * 4 + 3);

  threadgroup atomic_int hist[256];
  threadgroup float lo_hi[2];
  threadgroup int cut_info[3];   // [cut_bin, n_above, take_in_bin]

  if (blocks <= budget_blocks) {
    // budget covers everything: all blocks + tail (== dense visibility)
    for (int b = tid; b < blocks; b += 512) {
      out[b * 4 + 0] = b * 4;
      out[b * 4 + 1] = b * 4 + 1;
      out[b * 4 + 2] = b * 4 + 2;
      out[b * 4 + 3] = b * 4 + 3;
    }
    if (tid == 0) {
      int ns = blocks * 4;
      for (int p = blocks * 4; p < visible; p++) {
        out[ns] = p;
        ns++;
      }
      ns_out[t] = ns;
    }
    return;
  }

  // pass 0: min/max (single thread — max_blocks iters, worst 65k)
  if (tid == 0) {
    float mn = sc[0];
    float mx = sc[0];
    for (int b = 1; b < blocks; b++) {
      mn = min(mn, sc[b]);
      mx = max(mx, sc[b]);
    }
    lo_hi[0] = mn;
    lo_hi[1] = mx > mn ? mx : mn + 1.0f;
  }
  for (int i = tid; i < 256; i += 512) atomic_store_explicit(&hist[i], 0, memory_order_relaxed);
  threadgroup_barrier(mem_flags::mem_threadgroup);
  float mn = lo_hi[0];
  float inv_span = 255.0f / (lo_hi[1] - mn);
  // pass 1: histogram
  for (int b = tid; b < blocks; b += 512) {
    int bin = clamp(int((sc[b] - mn) * inv_span), 0, 255);
    atomic_fetch_add_explicit(&hist[bin], 1, memory_order_relaxed);
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  // find the threshold bin scanning from the top
  if (tid == 0) {
    int acc = 0;
    int cut = 0;
    for (int bin = 255; bin >= 0; bin--) {
      int c = atomic_load_explicit(&hist[bin], memory_order_relaxed);
      if (acc + c >= budget_blocks) {
        cut = bin;
        cut_info[0] = bin;
        cut_info[1] = acc;                       // strictly above the bin
        cut_info[2] = budget_blocks - acc;       // take this many from the bin
        break;
      }
      acc += c;
    }
    (void)cut;
  }
  threadgroup_barrier(mem_flags::mem_threadgroup);
  int cut_bin = cut_info[0];
  int take_in_bin = cut_info[2];
  // pass 2: emit in block order — above-bin blocks always; cut-bin blocks
  // until the quota fills (prefix counts via a second scan, single thread
  // for determinism; blocks <= 65k so this is the slow-but-rare path)
  if (tid == 0) {
    int emitted = 0;
    int taken_bin = 0;
    for (int b = 0; b < blocks && emitted < budget_blocks; b++) {
      int bin = clamp(int((sc[b] - mn) * inv_span), 0, 255);
      bool take = false;
      if (bin > cut_bin) take = true;
      else if (bin == cut_bin && taken_bin < take_in_bin) {
        take = true;
        taken_bin++;
      }
      if (take) {
        out[emitted * 4 + 0] = b * 4;
        out[emitted * 4 + 1] = b * 4 + 1;
        out[emitted * 4 + 2] = b * 4 + 2;
        out[emitted * 4 + 3] = b * 4 + 3;
        emitted++;
      }
    }
    int ns = emitted * 4;
    for (int p = blocks * 4; p < visible; p++) {
      out[ns] = p;
      ns++;
    }
    ns_out[t] = ns;
  }
}

// SDPA over an explicit position list. Same arithmetic as sdpa_decode_hd256
// (per-position simd-tree scores, fast::exp softmax, ordered weighted sum),
// positions indirected through sel. Dispatch: n*n_heads TGs of 256.
[[max_total_threads_per_threadgroup(256)]]
kernel void qsa_sdpa_selected(
  device const float *__restrict__ q       [[buffer(0)]],   // [n, heads, 256]
  device const float *__restrict__ k_cache [[buffer(1)]],
  device const float *__restrict__ v_cache [[buffer(2)]],
  device       float *__restrict__ out     [[buffer(3)]],
  device const int   *__restrict__ sel     [[buffer(4)]],   // [n, budget+3]
  device const int   *__restrict__ ns      [[buffer(5)]],   // [n]
  constant int &gqa_factor [[buffer(6)]],
  constant int &n_heads    [[buffer(7)]],
  constant int &kv_dim     [[buffer(8)]],
  constant float &scale    [[buffer(9)]],
  constant int &sel_stride [[buffer(10)]],                  // budget+3
  constant int &n_tok      [[buffer(11)]],
  uint tg   [[threadgroup_position_in_grid]],
  uint tid  [[thread_position_in_threadgroup]],
  uint lane [[thread_index_in_simdgroup]],
  uint simd [[simdgroup_index_in_threadgroup]]
) {
  threadgroup float partial[8];
  threadgroup float scores[2051];
  const int token = int(tg) / n_heads;
  const int q_head = int(tg) - token * n_heads;
  if (token >= n_tok) return;
  const int kv_head = q_head / gqa_factor;
  const int q_off = (token * n_heads + q_head) * 256;
  const int kv_base = kv_head * 256;
  device const int *ts = sel + token * sel_stride;
  const int usable = min(ns[token], 2051);
  for (int p = 0; p < usable; ++p) {
    const int pos = ts[p];
    const float part = q[q_off + int(tid)] * k_cache[kv_base + pos * kv_dim + int(tid)];
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
    result += scores[p] * v_cache[kv_base + ts[p] * kv_dim + int(tid)];
  }
  out[q_off + int(tid)] = result;
}
