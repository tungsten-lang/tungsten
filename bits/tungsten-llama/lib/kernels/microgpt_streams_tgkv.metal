// microGPT streams kernel — variant 3: KV cache in threadgroup memory.
//
// Builds on variant 2 (fp16 + half4). Moves the per-stream KV cache out
// of device memory (which lived in K_pool/V_pool) into threadgroup
// scratch — 1 KB per TG (BLOCK*EMBD*2*2 bytes). Avoids DRAM r/w on the
// hot attention path, since K/V stay on-chip for the lifetime of the
// stream.
//
// Buffers (note: only 4 now, no K_pool/V_pool):
//   buffer(0) W            : half[4192]
//   buffer(1) seeds        : uint[S]
//   buffer(2) out_tokens   : uint[S * N_STEPS]
//   buffer(3) constants    : int[1] = {N_STEPS}

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

inline float dot16(threadgroup const half4 *xh4, device const half *Wrow) {
    half4 w0 = ((device const half4 *)(Wrow))[0];
    half4 w1 = ((device const half4 *)(Wrow))[1];
    half4 w2 = ((device const half4 *)(Wrow))[2];
    half4 w3 = ((device const half4 *)(Wrow))[3];
    float s = dot(float4(w0), float4(xh4[0]));
    s += dot(float4(w1), float4(xh4[1]));
    s += dot(float4(w2), float4(xh4[2]));
    s += dot(float4(w3), float4(xh4[3]));
    return s;
}

kernel void microgpt_streams_tgkv(
    device const half  *W          [[buffer(0)]],
    device       uint  *seeds      [[buffer(1)]],
    device       uint  *out_tokens [[buffer(2)]],
    constant     int   &N_STEPS    [[buffer(3)]],
    uint stream  [[threadgroup_position_in_grid]],
    uint lane    [[thread_position_in_threadgroup]]
) {
    threadgroup half  tg_x[EMBD];
    threadgroup float tg_xr[EMBD];
    threadgroup float tg_q[EMBD];
    threadgroup float tg_attn_out[EMBD];
    threadgroup half  tg_h[MLP_H];
    threadgroup float tg_logits[VOCAB];
    threadgroup float tg_al[BLOCK * HEAD];
    threadgroup int   tg_tok;
    threadgroup int   tg_pos;
    threadgroup uint  tg_rng;

    // KV cache on-chip (per-TG = per-stream).
    threadgroup half tg_kc[BLOCK * EMBD];
    threadgroup half tg_vc[BLOCK * EMBD];

    threadgroup half4 *tg_x_h4 = (threadgroup half4 *)tg_x;
    threadgroup half4 *tg_h_h4 = (threadgroup half4 *)tg_h;

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
            float v = float(W[OFF_WTE + tok * EMBD + lane])
                    + float(W[OFF_WPE + pos * EMBD + lane]);
            tg_x[lane] = half(v);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (lane < uint(EMBD)) {
            float v = float(tg_x[lane]);
            tg_x[lane] = half(v * rmsnorm_scale(v));
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (lane < uint(EMBD)) tg_xr[lane] = float(tg_x[lane]);
        threadgroup_barrier(mem_flags::mem_threadgroup);
        if (lane < uint(EMBD)) {
            float v = float(tg_x[lane]);
            tg_x[lane] = half(v * rmsnorm_scale(v));
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (lane < uint(EMBD)) {
            int row_off = lane * EMBD;
            float qv = dot16(tg_x_h4, W + OFF_WQ + row_off);
            float kv = dot16(tg_x_h4, W + OFF_WK + row_off);
            float vv = dot16(tg_x_h4, W + OFF_WV + row_off);
            tg_q[lane] = qv;
            tg_kc[pos * EMBD + lane] = half(kv);
            tg_vc[pos * EMBD + lane] = half(vv);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        int t_n = pos + 1;

        if (lane % HD == 0 && lane < uint(EMBD)) {
            int hi = int(lane) / HD;
            float maxl = -1e30f;
            for (int t = 0; t < t_n; t++) {
                int koff = t * EMBD + hi * HD;
                float dot4 = tg_q[hi*HD + 0] * float(tg_kc[koff + 0])
                           + tg_q[hi*HD + 1] * float(tg_kc[koff + 1])
                           + tg_q[hi*HD + 2] * float(tg_kc[koff + 2])
                           + tg_q[hi*HD + 3] * float(tg_kc[koff + 3]);
                float val = dot4 * ATTN_SCALE;
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
                o += w * float(tg_vc[t * EMBD + hi * HD + dim_in_head]);
            }
            tg_attn_out[lane] = o;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (lane < uint(EMBD)) {
            float v = 0.0f;
            int row_off = lane * EMBD;
            for (int j = 0; j < EMBD; j++) v += float(W[OFF_WO + row_off + j]) * tg_attn_out[j];
            tg_x[lane] = half(v + tg_xr[lane]);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (lane < uint(EMBD)) tg_xr[lane] = float(tg_x[lane]);
        threadgroup_barrier(mem_flags::mem_threadgroup);
        if (lane < uint(EMBD)) {
            float v = float(tg_x[lane]);
            tg_x[lane] = half(v * rmsnorm_scale(v));
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        {
            int row = int(lane) * 2;
            int row_off0 = OFF_W1 + (row + 0) * EMBD;
            int row_off1 = OFF_W1 + (row + 1) * EMBD;
            float a0 = dot16(tg_x_h4, W + row_off0);
            float a1 = dot16(tg_x_h4, W + row_off1);
            tg_h[row + 0] = half(max(a0, 0.0f));
            tg_h[row + 1] = half(max(a1, 0.0f));
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (lane < uint(EMBD)) {
            int row_off = OFF_W2 + lane * MLP_H;
            float v = 0.0f;
            for (int k = 0; k < MLP_H / 4; k++) {
                half4 w  = ((device const half4 *)(W + row_off))[k];
                v += dot(float4(w), float4(tg_h_h4[k]));
            }
            tg_x[lane] = half(v + tg_xr[lane]);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (lane < uint(EMBD)) {
            float v = float(tg_x[lane]);
            tg_x[lane] = half(v * rmsnorm_scale(v));
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        if (lane < uint(VOCAB)) {
            int row_off = int(lane) * EMBD;
            float v = dot16(tg_x_h4, W + OFF_LM + row_off);
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
