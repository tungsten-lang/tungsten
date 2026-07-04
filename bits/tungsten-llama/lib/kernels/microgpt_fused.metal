// microGPT in one fused Metal compute shader.
//
// One dispatch per token, one threadgroup per token, single SIMD-group
// (32 threads) per threadgroup. The whole model (4192 fp32 = 17 KB) plus
// KV cache (2 KB) fits in L1; we keep weights in device memory (cached on
// chip after first read) and accumulate per-token state in registers / TG.
//
// Each threadgroup runs the full forward pass for one token autoregressively;
// the host loop calls dispatchThreadgroups once per token. The win over MLX
// is amortizing the per-op kernel launch (MLX issues ~25 dispatches per
// token; we issue 1).
//
// Layout matches `bench_c.c` from talos-vs-macbook:
//   wte  (27,16) wpe (16,16) wq/wk/wv/wo (16,16) w1 (64,16) w2 (16,64)
//   lm_head (27,16). All offsets in #floats.

#include <metal_stdlib>
using namespace metal;

constant int VOCAB = 27;
constant int BLOCK = 16;
constant int EMBD  = 16;
constant int HEAD  = 4;
constant int HD    = 4;
constant int MLP_H = 64;

constant int OFF_WTE = 0;
constant int OFF_WPE = 432;
constant int OFF_WQ  = 688;
constant int OFF_WK  = 944;
constant int OFF_WV  = 1200;
constant int OFF_WO  = 1456;
constant int OFF_W1  = 1712;
constant int OFF_W2  = 2736;
constant int OFF_LM  = 3760;

constant float ATTN_SCALE = 0.5f;       // 1 / sqrt(HD=4)
constant float INV_EMBD   = 0.0625f;    // 1 / 16
constant float EPS        = 1e-5f;
constant float TEMP       = 0.5f;

// Each threadgroup processes one token. 32 threads cooperatively run all
// dot products, RMSNorms, attention, MLP. The KV cache lives in TG memory
// and persists across dispatches via device-memory roundtrip.
//
// Buffers:
//   buffer(0) W       : float[4192]   model weights
//   buffer(1) k_cache : float[256]    BLOCK * EMBD,  read+write
//   buffer(2) v_cache : float[256]    BLOCK * EMBD,  read+write
//   buffer(3) state   : uint[4]       {tok_in, pos, rng_state, tok_out}
//
// state[0] = input token id, state[3] = next-token id sampled from logits.
// host updates state[0..2] between dispatches.

inline float rmsnorm_scale_simd(float xv, uint lane) {
    float sq = xv * xv;
    sq = simd_sum(sq);                    // 16 lanes have sq, sum over 16
    float ms = sq * INV_EMBD;
    return 1.0f / sqrt(ms + EPS);
}

kernel void microgpt_fused(
    device const float *W       [[buffer(0)]],
    device       float *k_cache [[buffer(1)]],
    device       float *v_cache [[buffer(2)]],
    device       uint  *state   [[buffer(3)]],
    uint lane [[thread_position_in_threadgroup]]
) {
    int tok = int(state[0]);
    int pos = int(state[1]);
    uint rng = state[2];

    // Per-thread holds one EMBD lane (lane 0..15 active for embed+attn output).
    // Lanes 16..31 do MLP-hidden work in parallel.
    threadgroup float tg_x[EMBD];
    threadgroup float tg_h[MLP_H];      // MLP hidden
    threadgroup float tg_q[EMBD];
    threadgroup float tg_k[EMBD];
    threadgroup float tg_v[EMBD];
    threadgroup float tg_logits[VOCAB];

    // x = wte[tok] + wpe[pos]
    if (lane < uint(EMBD)) {
        tg_x[lane] = W[OFF_WTE + tok * EMBD + lane] + W[OFF_WPE + pos * EMBD + lane];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // RMSNorm in-place (twice: pre-attn input passes through one rms, the
    // residual save happens after, then matches the C reference behavior).
    if (lane < uint(EMBD)) {
        float v = tg_x[lane];
        float scale = rmsnorm_scale_simd(v, lane);
        tg_x[lane] = v * scale;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Save residual (before second rmsnorm) — replicates C's `memcpy(xr, x);`
    threadgroup float tg_xr[EMBD];
    if (lane < uint(EMBD)) tg_xr[lane] = tg_x[lane];
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Second RMSNorm before QKV projection.
    if (lane < uint(EMBD)) {
        float v = tg_x[lane];
        float scale = rmsnorm_scale_simd(v, lane);
        tg_x[lane] = v * scale;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Q, K, V projection — each lane computes one output row.
    if (lane < uint(EMBD)) {
        float qv = 0.0f, kv = 0.0f, vv = 0.0f;
        int row_off = lane * EMBD;
        for (int j = 0; j < EMBD; j++) {
            float xj = tg_x[j];
            qv += W[OFF_WQ + row_off + j] * xj;
            kv += W[OFF_WK + row_off + j] * xj;
            vv += W[OFF_WV + row_off + j] * xj;
        }
        tg_q[lane] = qv;
        tg_k[lane] = kv;
        tg_v[lane] = vv;
        // cache k, v at pos
        k_cache[pos * EMBD + lane] = kv;
        v_cache[pos * EMBD + lane] = vv;
    }
    threadgroup_barrier(mem_flags::mem_device | mem_flags::mem_threadgroup);

    // Multi-head attention. Each of 4 heads has 4-dim Q, K, V.
    // Lane 0..3 → head 0, lane 4..7 → head 1, etc. Each lane holds one
    // dim within its head's output. We compute attention for all heads in
    // parallel.
    threadgroup float tg_attn_out[EMBD];
    threadgroup float tg_al[BLOCK * HEAD];   // 16 positions × 4 heads
    int t_n = pos + 1;
    if (lane < uint(EMBD)) {
        int hi = int(lane) / HD;
        int dim_in_head = int(lane) % HD;
        // Per-head: each lane in the head computes attention scores for
        // all positions, but only lane==0 does the max/softmax-reduce.
        // Simplified: lane 0 of each head computes all of QK^T and writes
        // to tg_al[hi*BLOCK..]. Then lane 0 of head reduces softmax, then
        // each lane in the head computes its output dim.
        // For simplicity here, ALL lanes recompute the full per-head dot
        // products into local. (32 threads × 16 positions × 4 dims = 2048
        // ops total for the attention block — cheap.)
        float maxl = -1e30f;
        // First pass: dot product for each pos t.
        // Stash in TG: tg_al[hi * BLOCK + t]
        if (dim_in_head == 0) {
            for (int t = 0; t < t_n; t++) {
                int koff = t * EMBD + hi * HD;
                float dot = tg_q[hi*HD + 0] * k_cache[koff + 0]
                          + tg_q[hi*HD + 1] * k_cache[koff + 1]
                          + tg_q[hi*HD + 2] * k_cache[koff + 2]
                          + tg_q[hi*HD + 3] * k_cache[koff + 3];
                float val = dot * ATTN_SCALE;
                tg_al[hi * BLOCK + t] = val;
                if (val > maxl) maxl = val;
            }
            // softmax
            float s = 0.0f;
            for (int t = 0; t < t_n; t++) {
                float e = exp(tg_al[hi * BLOCK + t] - maxl);
                tg_al[hi * BLOCK + t] = e;
                s += e;
            }
            float inv = 1.0f / s;
            for (int t = 0; t < t_n; t++) {
                tg_al[hi * BLOCK + t] *= inv;
            }
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    // Each lane computes its output dim within its head.
    if (lane < uint(EMBD)) {
        int hi = int(lane) / HD;
        int dim_in_head = int(lane) % HD;
        float o = 0.0f;
        for (int t = 0; t < t_n; t++) {
            float w = tg_al[hi * BLOCK + t];
            int voff = t * EMBD + hi * HD + dim_in_head;
            o += w * v_cache[voff];
        }
        tg_attn_out[lane] = o;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // O projection + residual.
    if (lane < uint(EMBD)) {
        float v = 0.0f;
        int row_off = lane * EMBD;
        for (int j = 0; j < EMBD; j++) {
            v += W[OFF_WO + row_off + j] * tg_attn_out[j];
        }
        tg_x[lane] = v + tg_xr[lane];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Save residual; pre-MLP RMSNorm.
    if (lane < uint(EMBD)) tg_xr[lane] = tg_x[lane];
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (lane < uint(EMBD)) {
        float v = tg_x[lane];
        float scale = rmsnorm_scale_simd(v, lane);
        tg_x[lane] = v * scale;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // MLP fc1: 16 → 64. Each pair of (lane, half) handles 2 output rows.
    // lane 0..31 maps to rows 0..31; we run twice (lane → row, lane+32 → row).
    {
        int row = int(lane) * 2;
        float a0 = 0.0f, a1 = 0.0f;
        for (int j = 0; j < EMBD; j++) {
            float xj = tg_x[j];
            a0 += W[OFF_W1 + (row + 0) * EMBD + j] * xj;
            a1 += W[OFF_W1 + (row + 1) * EMBD + j] * xj;
        }
        tg_h[row + 0] = max(a0, 0.0f);
        tg_h[row + 1] = max(a1, 0.0f);
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // MLP fc2: 64 → 16. Lane < 16 computes one row.
    if (lane < uint(EMBD)) {
        float v = 0.0f;
        int row_off = lane * MLP_H;
        for (int j = 0; j < MLP_H; j++) {
            v += W[OFF_W2 + row_off + j] * tg_h[j];
        }
        tg_x[lane] = v + tg_xr[lane];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Final RMSNorm.
    if (lane < uint(EMBD)) {
        float v = tg_x[lane];
        float scale = rmsnorm_scale_simd(v, lane);
        tg_x[lane] = v * scale;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // lm_head: 16 → 27. Lanes 0..26 each compute one logit; lane 27..31 idle.
    if (lane < uint(VOCAB)) {
        float v = 0.0f;
        int row_off = int(lane) * EMBD;
        for (int j = 0; j < EMBD; j++) {
            v += W[OFF_LM + row_off + j] * tg_x[j];
        }
        tg_logits[lane] = v / TEMP;     // temperature scaling
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    // Softmax over 27 logits + multinomial sample. Done by lane 0.
    if (lane == 0) {
        float maxl = tg_logits[0];
        for (int i = 1; i < VOCAB; i++) if (tg_logits[i] > maxl) maxl = tg_logits[i];
        float s = 0.0f;
        for (int i = 0; i < VOCAB; i++) {
            float e = exp(tg_logits[i] - maxl);
            tg_logits[i] = e;
            s += e;
        }
        float inv = 1.0f / s;
        // xorshift32
        uint x = rng;
        x ^= x << 13;  x ^= x >> 17;  x ^= x << 5;
        state[2] = x;
        // r in [0, 1)
        float r = float((x >> 8) & 0xFFFFFFu) * (1.0f / float(1u << 24));
        float c = 0.0f;
        int picked = VOCAB - 1;
        for (int i = 0; i < VOCAB - 1; i++) {
            c += tg_logits[i] * inv;
            if (r < c) { picked = i; break; }
        }
        state[3] = uint(picked);
    }
}
