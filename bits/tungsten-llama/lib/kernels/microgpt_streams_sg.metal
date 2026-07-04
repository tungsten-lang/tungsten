// microGPT streams kernel — variant 4: 8-streams-per-TG with
// simdgroup_matrix tensor ops. The headline restructure.
//
// 1 simdgroup (32 threads) handles K=8 streams. Each matmul becomes
// (K=8, EMBD) × (EMBD, N) = 8×N — true matrix-matrix that fits Apple's
// 8×8 cooperative-tensor primitive. The earlier kernels were
// matrix×vector (1 stream per TG); they couldn't use the simdgroup
// matrix coprocessor at all.
//
// Lane mapping for elementwise ops:
//   stream = lane / 4   (0..7) — which of the 8 streams this lane owns
//   elem4  = lane % 4   (0..3) — which 4-elem chunk within EMBD
// So every 4 lanes own one stream's row of EMBD=16 elements.
//
// Buffers:
//   buffer(0) W            : half[4192]
//   buffer(1) W_lm_pad     : half[32 * EMBD]   — LM head padded to 32 rows
//   buffer(2) seeds        : uint[S]            — S = N_TG * 8
//   buffer(3) out_tokens   : uint[S * N_STEPS]
//   buffer(4) seeds_out    : uint[S]
//   buffer(5) constants    : int[1] = {N_STEPS}
//
// Grid: (N_TG * 32, 1, 1) threads in TGs of 32. N_TG = S / 8.

#include <metal_stdlib>
#include <metal_simdgroup_matrix>
using namespace metal;

constant int VOCAB = 27;
constant int BLOCK = 16;
constant int EMBD  = 16;
constant int HEAD  = 4;
constant int HD    = 4;
constant int MLP_H = 64;
constant int K     = 8;     // streams per TG (must equal simdgroup tile size)
constant int VOCAB_PAD = 32;

constant int OFF_WTE = 0;
constant int OFF_WPE = 432;
constant int OFF_WQ  = 688;
constant int OFF_WK  = 944;
constant int OFF_WV  = 1200;
constant int OFF_WO  = 1456;
constant int OFF_W1  = 1712;
constant int OFF_W2  = 2736;

constant float ATTN_SCALE = 0.5f;
constant float INV_EMBD   = 0.0625f;
constant float EPS        = 1e-5f;
constant float TEMP       = 0.5f;
constant int   BOS        = 26;

// Y[K, N] = X[K, EMBD] · W[N, EMBD]^T (W is (out=N, in=EMBD) row-major).
// Iterate output in 8-col tiles; reduce inner dim EMBD=16 in 8-tile chunks.
inline void matmul_8xEMBDxN(threadgroup const half *X, device const half *W,
                            threadgroup half *Y, int N) {
    for (int n_tile = 0; n_tile < N; n_tile += 8) {
        simdgroup_matrix<half, 8, 8> acc(0);
        for (int k_tile = 0; k_tile < EMBD; k_tile += 8) {
            simdgroup_matrix<half, 8, 8> a, b;
            simdgroup_load(a, X + k_tile, EMBD);
            simdgroup_load(b, W + n_tile * EMBD + k_tile, EMBD, ulong2(0, 0), true);
            simdgroup_multiply_accumulate(acc, a, b, acc);
        }
        simdgroup_store(acc, Y + n_tile, N);
    }
}

kernel void microgpt_streams_sg(
    device const half  *W          [[buffer(0)]],
    device const half  *W_lm_pad   [[buffer(1)]],
    device       uint  *seeds      [[buffer(2)]],
    device       uint  *out_tokens [[buffer(3)]],
    device       uint  *seeds_out  [[buffer(4)]],
    constant     int   &N_STEPS    [[buffer(5)]],
    uint tg      [[threadgroup_position_in_grid]],
    uint lane    [[thread_position_in_threadgroup]]
) {
    threadgroup half  tg_x[K * EMBD];
    threadgroup half  tg_xr[K * EMBD];
    threadgroup half  tg_q[K * EMBD];
    threadgroup half  tg_kv_temp[K * EMBD * 2];   // k, v projections back-to-back
    threadgroup half  tg_attn_out[K * EMBD];
    threadgroup half  tg_h[K * MLP_H];
    threadgroup float tg_logits[K * VOCAB_PAD];
    threadgroup int   tg_tok[K];
    threadgroup int   tg_pos[K];
    threadgroup uint  tg_rng[K];
    threadgroup half  tg_kc[K * BLOCK * EMBD];
    threadgroup half  tg_vc[K * BLOCK * EMBD];

    uint stream = lane / (EMBD / 4);    // lane / 4 → stream id (0..7)
    uint elem4  = lane % (EMBD / 4);    // lane mod 4 → 4-elem chunk in EMBD

    if (lane < uint(K)) {
        tg_tok[lane] = BOS;
        tg_pos[lane] = 0;
        tg_rng[lane] = seeds[tg * K + lane];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    for (int step = 0; step < N_STEPS; step++) {
        int tok_l = tg_tok[stream];
        int pos_l = tg_pos[stream];

        // Embed: each lane writes 4 elements of one stream.
        {
            uint base = elem4 * 4;
            threadgroup half *xrow = &tg_x[stream * EMBD];
            for (int e = 0; e < 4; e++) {
                xrow[base + e] = W[OFF_WTE + tok_l * EMBD + base + e]
                               + W[OFF_WPE + pos_l * EMBD + base + e];
            }
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        // Pre-attn RMSnorm (twice — matches reference).
        {
            threadgroup half *xrow = &tg_x[stream * EMBD];
            uint base = elem4 * 4;
            float sq = 0;
            for (int e = 0; e < 4; e++) sq += float(xrow[base + e]) * float(xrow[base + e]);
            sq += simd_shuffle_xor(sq, 1);
            sq += simd_shuffle_xor(sq, 2);
            float scale = 1.0f / sqrt(sq * INV_EMBD + EPS);
            for (int e = 0; e < 4; e++) xrow[base + e] = half(float(xrow[base + e]) * scale);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        // Save residual + second RMSnorm.
        {
            threadgroup half *xrow  = &tg_x[stream * EMBD];
            threadgroup half *xrrow = &tg_xr[stream * EMBD];
            uint base = elem4 * 4;
            for (int e = 0; e < 4; e++) xrrow[base + e] = xrow[base + e];
            float sq = 0;
            for (int e = 0; e < 4; e++) sq += float(xrow[base + e]) * float(xrow[base + e]);
            sq += simd_shuffle_xor(sq, 1);
            sq += simd_shuffle_xor(sq, 2);
            float scale = 1.0f / sqrt(sq * INV_EMBD + EPS);
            for (int e = 0; e < 4; e++) xrow[base + e] = half(float(xrow[base + e]) * scale);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        // QKV projections.
        matmul_8xEMBDxN(tg_x, W + OFF_WQ, tg_q,                     EMBD);
        matmul_8xEMBDxN(tg_x, W + OFF_WK, tg_kv_temp,               EMBD);
        matmul_8xEMBDxN(tg_x, W + OFF_WV, tg_kv_temp + K * EMBD,    EMBD);
        threadgroup_barrier(mem_flags::mem_threadgroup);

        // Cache K, V at this stream's pos.
        {
            uint base = elem4 * 4;
            threadgroup half *kc_s  = &tg_kc[stream * BLOCK * EMBD + pos_l * EMBD];
            threadgroup half *vc_s  = &tg_vc[stream * BLOCK * EMBD + pos_l * EMBD];
            threadgroup half *k_proj = &tg_kv_temp[stream * EMBD];
            threadgroup half *v_proj = &tg_kv_temp[K * EMBD + stream * EMBD];
            for (int e = 0; e < 4; e++) {
                kc_s[base + e] = k_proj[base + e];
                vc_s[base + e] = v_proj[base + e];
            }
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        int t_n = pos_l + 1;

        // Attention: per stream, per head. 4 lanes-per-stream × 1 head each = 4 heads.
        {
            threadgroup half *q_s   = &tg_q[stream * EMBD];
            threadgroup half *kc_s  = &tg_kc[stream * BLOCK * EMBD];
            threadgroup half *vc_s  = &tg_vc[stream * BLOCK * EMBD];
            threadgroup half *out_s = &tg_attn_out[stream * EMBD];
            uint hi = elem4;
            float al[BLOCK];
            float maxl = -1e30f;
            for (int t = 0; t < t_n; t++) {
                int koff = t * EMBD + hi * HD;
                float dotv = float(q_s[hi*HD+0]) * float(kc_s[koff+0])
                           + float(q_s[hi*HD+1]) * float(kc_s[koff+1])
                           + float(q_s[hi*HD+2]) * float(kc_s[koff+2])
                           + float(q_s[hi*HD+3]) * float(kc_s[koff+3]);
                float val = dotv * ATTN_SCALE;
                al[t] = val;
                if (val > maxl) maxl = val;
            }
            float s = 0.0f;
            for (int t = 0; t < t_n; t++) { al[t] = exp(al[t] - maxl); s += al[t]; }
            float inv = 1.0f / s;
            float o0=0, o1=0, o2=0, o3=0;
            for (int t = 0; t < t_n; t++) {
                float w_t = al[t] * inv;
                int voff = t * EMBD + hi * HD;
                o0 += w_t * float(vc_s[voff+0]);
                o1 += w_t * float(vc_s[voff+1]);
                o2 += w_t * float(vc_s[voff+2]);
                o3 += w_t * float(vc_s[voff+3]);
            }
            out_s[hi*HD+0] = half(o0);
            out_s[hi*HD+1] = half(o1);
            out_s[hi*HD+2] = half(o2);
            out_s[hi*HD+3] = half(o3);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        // WO + residual.
        matmul_8xEMBDxN(tg_attn_out, W + OFF_WO, tg_x, EMBD);
        threadgroup_barrier(mem_flags::mem_threadgroup);
        {
            threadgroup half *xrow  = &tg_x[stream * EMBD];
            threadgroup half *xrrow = &tg_xr[stream * EMBD];
            uint base = elem4 * 4;
            for (int e = 0; e < 4; e++) xrow[base + e] += xrrow[base + e];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        // Save residual + RMSnorm.
        {
            threadgroup half *xrow  = &tg_x[stream * EMBD];
            threadgroup half *xrrow = &tg_xr[stream * EMBD];
            uint base = elem4 * 4;
            for (int e = 0; e < 4; e++) xrrow[base + e] = xrow[base + e];
            float sq = 0;
            for (int e = 0; e < 4; e++) sq += float(xrow[base + e]) * float(xrow[base + e]);
            sq += simd_shuffle_xor(sq, 1);
            sq += simd_shuffle_xor(sq, 2);
            float scale = 1.0f / sqrt(sq * INV_EMBD + EPS);
            for (int e = 0; e < 4; e++) xrow[base + e] = half(float(xrow[base + e]) * scale);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        // MLP fc1: (K=8, EMBD=16) × (EMBD=16, MLP_H=64) → (K=8, 64). 8 simdgroup tiles.
        matmul_8xEMBDxN(tg_x, W + OFF_W1, tg_h, MLP_H);
        threadgroup_barrier(mem_flags::mem_threadgroup);

        // ReLU per stream — 4 lanes per stream × 16 elems each = 64 hidden.
        {
            threadgroup half *hrow = &tg_h[stream * MLP_H];
            uint base = elem4 * 16;
            for (int e = 0; e < 16; e++) hrow[base + e] = max(hrow[base + e], half(0));
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        // MLP fc2: (K=8, MLP_H=64) × (MLP_H=64, EMBD=16) → (K=8, 16).
        // matmul_8xEMBDxN expects inner=EMBD, so inline a 2-output × 8-inner-tile loop.
        {
            for (int n_tile = 0; n_tile < EMBD; n_tile += 8) {
                simdgroup_matrix<half, 8, 8> acc(0);
                for (int k_tile = 0; k_tile < MLP_H; k_tile += 8) {
                    simdgroup_matrix<half, 8, 8> a, b;
                    simdgroup_load(a, &tg_h[k_tile], MLP_H);
                    simdgroup_load(b, W + OFF_W2 + n_tile * MLP_H + k_tile, MLP_H, ulong2(0, 0), true);
                    simdgroup_multiply_accumulate(acc, a, b, acc);
                }
                simdgroup_store(acc, &tg_x[n_tile], EMBD);
            }
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        {
            threadgroup half *xrow  = &tg_x[stream * EMBD];
            threadgroup half *xrrow = &tg_xr[stream * EMBD];
            uint base = elem4 * 4;
            for (int e = 0; e < 4; e++) xrow[base + e] += xrrow[base + e];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        // Final RMSnorm.
        {
            threadgroup half *xrow = &tg_x[stream * EMBD];
            uint base = elem4 * 4;
            float sq = 0;
            for (int e = 0; e < 4; e++) sq += float(xrow[base + e]) * float(xrow[base + e]);
            sq += simd_shuffle_xor(sq, 1);
            sq += simd_shuffle_xor(sq, 2);
            float scale = 1.0f / sqrt(sq * INV_EMBD + EPS);
            for (int e = 0; e < 4; e++) xrow[base + e] = half(float(xrow[base + e]) * scale);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        // LM head: (K=8, EMBD=16) × (VOCAB_PAD=32, EMBD=16) → (K=8, 32).
        // Last 5 rows of W_lm_pad are zeros so logits[27..31] are masked.
        {
            for (int n_tile = 0; n_tile < VOCAB_PAD; n_tile += 8) {
                simdgroup_matrix<half, 8, 8> acc(0);
                for (int k_tile = 0; k_tile < EMBD; k_tile += 8) {
                    simdgroup_matrix<half, 8, 8> a, b;
                    simdgroup_load(a, &tg_x[k_tile], EMBD);
                    simdgroup_load(b, W_lm_pad + n_tile * EMBD + k_tile, EMBD, ulong2(0, 0), true);
                    simdgroup_multiply_accumulate(acc, a, b, acc);
                }
                threadgroup half tile_h[8 * 8];
                simdgroup_store(acc, tile_h, 8);
                threadgroup_barrier(mem_flags::mem_threadgroup);
                if (lane < 32) {
                    uint s = lane / 4;
                    uint c = lane % 4;
                    tg_logits[s * VOCAB_PAD + n_tile + c * 2 + 0] = float(tile_h[s * 8 + c * 2 + 0]) / TEMP;
                    tg_logits[s * VOCAB_PAD + n_tile + c * 2 + 1] = float(tile_h[s * 8 + c * 2 + 1]) / TEMP;
                }
                threadgroup_barrier(mem_flags::mem_threadgroup);
            }
        }

        // Sample: lanes 0..7 = streams.
        if (lane < uint(K)) {
            uint s = lane;
            threadgroup float *lg = &tg_logits[s * VOCAB_PAD];
            float maxl = lg[0];
            for (int i = 1; i < VOCAB; i++) if (lg[i] > maxl) maxl = lg[i];
            float ssum = 0;
            for (int i = 0; i < VOCAB; i++) { lg[i] = exp(lg[i] - maxl); ssum += lg[i]; }
            float inv = 1.0f / ssum;
            uint x = tg_rng[s];
            x ^= x << 13;  x ^= x >> 17;  x ^= x << 5;
            tg_rng[s] = x;
            float r = float((x >> 8) & 0xFFFFFFu) * (1.0f / float(1u << 24));
            float c = 0;
            int picked = VOCAB - 1;
            for (int i = 0; i < VOCAB - 1; i++) {
                c += lg[i] * inv;
                if (r < c) { picked = i; break; }
            }
            uint stream_global = tg * K + s;
            out_tokens[stream_global * N_STEPS + step] = uint(picked);
            tg_tok[s] = picked;
            int p = tg_pos[s] + 1;
            if (p >= BLOCK) { p = 0; tg_tok[s] = BOS; }
            tg_pos[s] = p;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    if (lane < uint(K)) seeds_out[tg * K + lane] = tg_rng[lane];
}
