// microGPT, many independent autoregressive streams in one dispatch.
//
// Each threadgroup runs N_STEPS tokens of one independent stream, with its
// own KV cache, RNG, and output buffer. The host launches ONE dispatch and
// gets back S × N_STEPS tokens. No host round-trip per token.
//
// This is the "many-tokens-batched" comparison point — the natural shape
// where MLX-GPU should win on a real workload but doesn't, because MLX
// still issues per-op dispatches under the hood. Here every token of every
// stream stays on-GPU until we hand back the full grid.
//
// Shape: gridDim.x = S (number of streams). Each TG = 32 threads.
//
// Buffers:
//   buffer(0) W            : float[4192]              shared, read-only
//   buffer(1) K_pool       : float[S * BLOCK * EMBD]  per-stream K cache
//   buffer(2) V_pool       : float[S * BLOCK * EMBD]  per-stream V cache
//   buffer(3) seeds        : uint[S]                  per-stream xorshift seed
//   buffer(4) out_tokens   : uint[S * N_STEPS]        token grid (output)
//   buffer(5) constants    : int[1] = {N_STEPS}

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

constant float ATTN_SCALE = 0.5f;
constant float INV_EMBD   = 0.0625f;
constant float EPS        = 1e-5f;
constant float TEMP       = 0.5f;
constant int   BOS        = 26;

inline float rmsnorm_scale(float xv) {
    float sq = xv * xv;
    sq = simd_sum(sq);
    return 1.0f / sqrt(sq * INV_EMBD + EPS);
}

kernel void microgpt_streams(
    device const float *W          [[buffer(0)]],
    device       float *K_pool     [[buffer(1)]],
    device       float *V_pool     [[buffer(2)]],
    device       uint  *seeds      [[buffer(3)]],
    device       uint  *out_tokens [[buffer(4)]],
    constant     int   &N_STEPS    [[buffer(5)]],
    uint stream  [[threadgroup_position_in_grid]],
    uint lane    [[thread_position_in_threadgroup]]
) {
    threadgroup float tg_x[EMBD];
    threadgroup float tg_xr[EMBD];
    threadgroup float tg_q[EMBD];
    threadgroup float tg_attn_out[EMBD];
    threadgroup float tg_h[MLP_H];
    threadgroup float tg_logits[VOCAB];
    threadgroup float tg_al[BLOCK * HEAD];
    threadgroup int   tg_tok;
    threadgroup int   tg_pos;
    threadgroup uint  tg_rng;

    device float *kc = K_pool + stream * BLOCK * EMBD;
    device float *vc = V_pool + stream * BLOCK * EMBD;

    if (lane == 0) {
        tg_tok = BOS;
        tg_pos = 0;
        tg_rng = seeds[stream];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (int step = 0; step < N_STEPS; step++) {
        int tok = tg_tok;
        int pos = tg_pos;

        // x = wte[tok] + wpe[pos]
        if (lane < uint(EMBD)) {
            tg_x[lane] = W[OFF_WTE + tok * EMBD + lane] + W[OFF_WPE + pos * EMBD + lane];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (lane < uint(EMBD)) {
            float v = tg_x[lane];
            tg_x[lane] = v * rmsnorm_scale(v);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (lane < uint(EMBD)) tg_xr[lane] = tg_x[lane];
        threadgroup_barrier(mem_flags::mem_threadgroup);
        if (lane < uint(EMBD)) {
            float v = tg_x[lane];
            tg_x[lane] = v * rmsnorm_scale(v);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        // QKV proj — each lane (0..15) computes one output row of all 3.
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
            kc[pos * EMBD + lane] = kv;
            vc[pos * EMBD + lane] = vv;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        int t_n = pos + 1;

        // Attention: compute softmax(QK^T) per head (lane 0,4,8,12 each handles
        // their head); reduction is small enough we just do it on those lanes.
        if (lane % HD == 0 && lane < uint(EMBD)) {
            int hi = int(lane) / HD;
            float maxl = -1e30f;
            for (int t = 0; t < t_n; t++) {
                int koff = t * EMBD + hi * HD;
                float dot = tg_q[hi*HD + 0] * kc[koff + 0]
                          + tg_q[hi*HD + 1] * kc[koff + 1]
                          + tg_q[hi*HD + 2] * kc[koff + 2]
                          + tg_q[hi*HD + 3] * kc[koff + 3];
                float val = dot * ATTN_SCALE;
                tg_al[hi * BLOCK + t] = val;
                if (val > maxl) maxl = val;
            }
            float s = 0.0f;
            for (int t = 0; t < t_n; t++) {
                float e = exp(tg_al[hi * BLOCK + t] - maxl);
                tg_al[hi * BLOCK + t] = e;
                s += e;
            }
            float inv = 1.0f / s;
            for (int t = 0; t < t_n; t++) tg_al[hi * BLOCK + t] *= inv;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (lane < uint(EMBD)) {
            int hi = int(lane) / HD;
            int dim_in_head = int(lane) % HD;
            float o = 0.0f;
            for (int t = 0; t < t_n; t++) {
                float w = tg_al[hi * BLOCK + t];
                o += w * vc[t * EMBD + hi * HD + dim_in_head];
            }
            tg_attn_out[lane] = o;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        // O proj + residual
        if (lane < uint(EMBD)) {
            float v = 0.0f;
            int row_off = lane * EMBD;
            for (int j = 0; j < EMBD; j++) v += W[OFF_WO + row_off + j] * tg_attn_out[j];
            tg_x[lane] = v + tg_xr[lane];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (lane < uint(EMBD)) tg_xr[lane] = tg_x[lane];
        threadgroup_barrier(mem_flags::mem_threadgroup);
        if (lane < uint(EMBD)) {
            float v = tg_x[lane];
            tg_x[lane] = v * rmsnorm_scale(v);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        // MLP fc1: each of 32 lanes does 2 rows.
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

        // MLP fc2: lane < 16 each row.
        if (lane < uint(EMBD)) {
            float v = 0.0f;
            int row_off = lane * MLP_H;
            for (int j = 0; j < MLP_H; j++) v += W[OFF_W2 + row_off + j] * tg_h[j];
            tg_x[lane] = v + tg_xr[lane];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (lane < uint(EMBD)) {
            float v = tg_x[lane];
            tg_x[lane] = v * rmsnorm_scale(v);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        // lm_head + temperature
        if (lane < uint(VOCAB)) {
            float v = 0.0f;
            int row_off = int(lane) * EMBD;
            for (int j = 0; j < EMBD; j++) v += W[OFF_LM + row_off + j] * tg_x[j];
            tg_logits[lane] = v / TEMP;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        // softmax + sample (lane 0)
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
            uint x = tg_rng;
            x ^= x << 13;  x ^= x >> 17;  x ^= x << 5;
            tg_rng = x;
            float r = float((x >> 8) & 0xFFFFFFu) * (1.0f / float(1u << 24));
            float c = 0.0f;
            int picked = VOCAB - 1;
            for (int i = 0; i < VOCAB - 1; i++) {
                c += tg_logits[i] * inv;
                if (r < c) { picked = i; break; }
            }
            out_tokens[stream * N_STEPS + step] = uint(picked);
            tg_tok = picked;
            int p = pos + 1;
            if (p >= BLOCK) { p = 0; tg_tok = BOS; }
            tg_pos = p;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    if (lane == 0) {
        seeds[stream] = tg_rng;
    }
}
