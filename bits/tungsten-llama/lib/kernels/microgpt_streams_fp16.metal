// microGPT streams kernel — variant 1: fp16 storage, fp32 accumulators.
//
// Same shape as microgpt_streams.metal: gridDim.x = S streams, 32 threads
// per TG, one stream per TG. The weight buffer and KV cache are fp16 (half
// the bandwidth pressure); arithmetic upcasts to fp32 in flight.
//
// This is the cheapest possible win — no per-thread restructuring, just
// narrower storage. Reference (talos-vs-macbook bench_mlx_metal_fp16.py):
// 175M tok/s vs 134M for the fp32-scalar baseline.
//
// Buffers:
//   buffer(0) W            : half[4192]
//   buffer(1) K_pool       : half[S * BLOCK * EMBD]
//   buffer(2) V_pool       : half[S * BLOCK * EMBD]
//   buffer(3) seeds        : uint[S]
//   buffer(4) out_tokens   : uint[S * N_STEPS]
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

kernel void microgpt_streams_fp16(
    device const half  *W          [[buffer(0)]],
    device       half  *K_pool     [[buffer(1)]],
    device       half  *V_pool     [[buffer(2)]],
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

    device half *kc = K_pool + stream * BLOCK * EMBD;
    device half *vc = V_pool + stream * BLOCK * EMBD;

    if (lane == 0) {
        tg_tok = BOS;
        tg_pos = 0;
        tg_rng = seeds[stream];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (int step = 0; step < N_STEPS; step++) {
        int tok = tg_tok;
        int pos = tg_pos;

        if (lane < uint(EMBD)) {
            tg_x[lane] = float(W[OFF_WTE + tok * EMBD + lane])
                       + float(W[OFF_WPE + pos * EMBD + lane]);
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

        if (lane < uint(EMBD)) {
            float qv = 0.0f, kv = 0.0f, vv = 0.0f;
            int row_off = lane * EMBD;
            for (int j = 0; j < EMBD; j++) {
                float xj = tg_x[j];
                qv += float(W[OFF_WQ + row_off + j]) * xj;
                kv += float(W[OFF_WK + row_off + j]) * xj;
                vv += float(W[OFF_WV + row_off + j]) * xj;
            }
            tg_q[lane] = qv;
            kc[pos * EMBD + lane] = half(kv);
            vc[pos * EMBD + lane] = half(vv);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        int t_n = pos + 1;

        if (lane % HD == 0 && lane < uint(EMBD)) {
            int hi = int(lane) / HD;
            float maxl = -1e30f;
            for (int t = 0; t < t_n; t++) {
                int koff = t * EMBD + hi * HD;
                float dot = tg_q[hi*HD + 0] * float(kc[koff + 0])
                          + tg_q[hi*HD + 1] * float(kc[koff + 1])
                          + tg_q[hi*HD + 2] * float(kc[koff + 2])
                          + tg_q[hi*HD + 3] * float(kc[koff + 3]);
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
                o += w * float(vc[t * EMBD + hi * HD + dim_in_head]);
            }
            tg_attn_out[lane] = o;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (lane < uint(EMBD)) {
            float v = 0.0f;
            int row_off = lane * EMBD;
            for (int j = 0; j < EMBD; j++) v += float(W[OFF_WO + row_off + j]) * tg_attn_out[j];
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

        {
            int row = int(lane) * 2;
            float a0 = 0.0f, a1 = 0.0f;
            for (int j = 0; j < EMBD; j++) {
                float xj = tg_x[j];
                a0 += float(W[OFF_W1 + (row + 0) * EMBD + j]) * xj;
                a1 += float(W[OFF_W1 + (row + 1) * EMBD + j]) * xj;
            }
            tg_h[row + 0] = max(a0, 0.0f);
            tg_h[row + 1] = max(a1, 0.0f);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (lane < uint(EMBD)) {
            float v = 0.0f;
            int row_off = lane * MLP_H;
            for (int j = 0; j < MLP_H; j++) v += float(W[OFF_W2 + row_off + j]) * tg_h[j];
            tg_x[lane] = v + tg_xr[lane];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (lane < uint(EMBD)) {
            float v = tg_x[lane];
            tg_x[lane] = v * rmsnorm_scale(v);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (lane < uint(VOCAB)) {
            float v = 0.0f;
            int row_off = int(lane) * EMBD;
            for (int j = 0; j < EMBD; j++) v += float(W[OFF_LM + row_off + j]) * tg_x[j];
            tg_logits[lane] = v / TEMP;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

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
