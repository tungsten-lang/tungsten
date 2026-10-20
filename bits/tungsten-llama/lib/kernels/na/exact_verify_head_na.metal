// exact_verify_head_na.metal — Certified Two-Stage Int8 NAX Screen + Exact
// FP32 Shortlist Rescore Top-2 Verify Head (`ExactVerifyHead`).
//
// Ported from Layr-Labs/mlxfast-bonsai2-9b-engine (`Hadamard.swift`:
// `ExactVerifyHead` & `Float16ConstantQMV`).
//
// How it works:
//   1. `VerifyInt8Matmul` computes the approximate int8-quantized LM head
//      logits `L8[row, n]` over the full vocabulary (e.g. N = 248,320) using
//      the M5 Neural Accelerator (`int8 x u2 -> int32`).
//   2. For each row, the maximum deviation between the true FP32 logit `F[n]`
//      and `L8[n]` is bounded deterministically by:
//        E = 1.001 * sum_g ascale[row, g] * (Amax[g] * (0.5 + 127*gf) + Bmax[g] * gi)
//      where `Amax[g]` and `Bmax[g]` depend only on the static LM-head weights
//      and are precomputed once by `hadamard_xhead_bounds`.
//   3. With `i2` the second-largest `L8` value in the row and `tau = i2 - 2*E`,
//      any token outside `S = {n : L8[n] >= tau}` satisfies `F[n] < i2 - E`,
//      while both int8 leaders satisfy `F >= i2 - E`. Thus the exact FP32
//      top-2 is guaranteed to lie inside `S`.
//   4. Only the candidate rows in `S` (typically 2..16 tokens out of 248,320!)
//      are rescored using the exact FP32 `rowsAccumulate` dot product. If
//      `|S| > CAP` or any non-finite value occurs, `flag[row] = 1` triggers
//      the guarded full-vocabulary fallback (`hadamard_xhead_guarded_top2`).

#include <metal_stdlib>
#include <metal_simdgroup>
#include <metal_atomic>

using namespace metal;

struct hadamard_top2 {
    float first_value;
    float second_value;
    uint  first_id;
    uint  second_id;
    uint  count;
};

inline hadamard_top2 hadamard_top2_empty() {
    hadamard_top2 state;
    state.first_value = 0.0f;
    state.second_value = 0.0f;
    state.first_id = 0;
    state.second_id = 0;
    state.count = 0;
    return state;
}

inline bool hadamard_top2_better(float value, uint id, float current_value, uint current_id) {
    bool nan = isnan(value);
    bool current_nan = isnan(current_value);
    if (nan != current_nan) return !nan;
    if (value > current_value) return true;
    if (value < current_value) return false;
    return id < current_id;
}

inline void hadamard_top2_insert(thread hadamard_top2 &state, float value, uint id) {
    if (state.count > 0 && state.first_id == id) return;
    if (state.count > 1 && state.second_id == id) return;
    if (state.count == 0
        || hadamard_top2_better(value, id, state.first_value, state.first_id)) {
        if (state.count > 0) {
            state.second_value = state.first_value;
            state.second_id = state.first_id;
        }
        state.first_value = value;
        state.first_id = id;
        state.count = min(state.count + 1, 2u);
        return;
    }
    if (state.count == 1
        || hadamard_top2_better(value, id, state.second_value, state.second_id)) {
        state.second_value = value;
        state.second_id = id;
        state.count = 2;
    }
}

inline void hadamard_top2_merge(thread hadamard_top2 &state, hadamard_top2 other) {
    if (other.count > 0) hadamard_top2_insert(state, other.first_value, other.first_id);
    if (other.count > 1) hadamard_top2_insert(state, other.second_value, other.second_id);
}

// Precomputes `bounds[g] = Amax_g` and `bounds[G + g] = Bmax_g` once at load
// time over the 2-bit head weights `w` [N, words], `scales` [N, G], `biases` [N, G].
// Grid: (G, 1, 1) threadgroups of 256 threads.
kernel void hadamard_xhead_bounds(
    device const uint32_t* w        [[buffer(0)]],
    device const half*     scales   [[buffer(1)]],
    device const half*     biases   [[buffer(2)]],
    device float*          bounds   [[buffer(3)]],
    constant int&          N        [[buffer(4)]],
    constant int&          words    [[buffer(5)]],
    constant int&          G        [[buffer(6)]],
    uint                   g        [[threadgroup_position_in_grid]],
    uint                   lane     [[thread_index_in_threadgroup]],
    uint                   simd_lid [[thread_index_in_simdgroup]],
    uint                   simd_gid [[simdgroup_index_in_threadgroup]]
) {
    float amax = 0.0f, bmax = 0.0f;
    for (int n = int(lane); n < N; n += 256) {
        const device uint32_t* wr = w + size_t(n) * size_t(words) + g * 8;
        int n1 = 0, n2 = 0, n3 = 0;
        for (int j = 0; j < 8; j++) {
            const uint v = wr[j];
            const uint lo = v & 0x55555555u;
            const uint hi = (v >> 1) & 0x55555555u;
            n3 += popcount(lo & hi);
            n1 += popcount(lo & ~hi);
            n2 += popcount(hi & ~lo);
        }
        const int n0 = 128 - n1 - n2 - n3;
        const float s = float(scales[size_t(n) * size_t(G) + g]);
        const float b = float(biases[size_t(n) * size_t(G) + g]);
        const float a = float(n0) * fabs(b) + float(n1) * fabs(s + b)
            + float(n2) * fabs(2.0f * s + b) + float(n3) * fabs(3.0f * s + b);
        const float bb = 127.0f * (fabs(s) * float(n1 + 2 * n2 + 3 * n3) + 128.0f * fabs(b));
        amax = max(amax, a);
        bmax = max(bmax, bb);
    }
    amax = simd_max(amax);
    bmax = simd_max(bmax);
    threadgroup float sa[8], sb[8];
    if (simd_lid == 0) { sa[simd_gid] = amax; sb[simd_gid] = bmax; }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (lane == 0) {
        for (int i = 1; i < 8; i++) {
            amax = max(amax, sa[i]);
            bmax = max(bmax, sb[i]);
        }
        bounds[g] = amax;
        bounds[G + g] = bmax;
    }
}

// Exact FP32 single-row dot product matching `Float16ConstantQMV.rowsAccumulate`.
METAL_FUNC float hadamard_xhead_eval_row(
    int row,
    int out_row,
    int K,
    int neg,
    uint simd_lid,
    device const float* x,
    device const uint32_t* w,
    device const half* scales,
    device const half* biases
) {
    const int in_w = K / 4;
    const int in_g = K / 128;
    const device uint8_t* ws = (const device uint8_t*)w + size_t(out_row) * size_t(in_w) + simd_lid * 4;
    const device half* sc = scales + size_t(out_row) * size_t(in_g) + simd_lid / 8;
    const device half* bi = biases + size_t(out_row) * size_t(in_g) + simd_lid / 8;
    const device float4* xp = (const device float4*)(x + size_t(row) * size_t(K) + simd_lid * 16);
    float result = 0.0f;
    for (int k = 0; k < K; k += 512) {
        const float s = float(sc[0]);
        const float s0 = s;
        const float s1 = s * 0.25f;
        const float s2 = s * 0.0625f;
        const float s3 = s * 0.015625f;
        const float b = neg ? -s : float(bi[0]);
        const uint packed = *(const device uint*)ws;
        #pragma clang loop unroll(full)
        for (int i = 0; i < 4; i++) {
            const uint q = packed >> (8 * i);
            const float wd0 = fma(s0, float(q & 0x03u), b);
            const float wd1 = fma(s1, float(q & 0x0cu), b);
            const float wd2 = fma(s2, float(q & 0x30u), b);
            const float wd3 = fma(s3, float(q & 0xc0u), b);
            const float4 xv = xp[i];
            result = fma(xv.x, wd0, result);
            result = fma(xv.y, wd1, result);
            result = fma(xv.z, wd2, result);
            result = fma(xv.w, wd3, result);
        }
        ws += 128;
        sc += 4;
        bi += 4;
        xp += 128;
    }
    return simd_sum(result);
}

// Parallel 64-block scan over `logits` [rows, NV]:
// Grid: (BLOCKS, rows, 1) threadgroups of 256 threads.
constant constexpr int XHEAD_CAP = 256;
constant constexpr int XHEAD_BLOCKS = 64;
constant constexpr int XHEAD_BLOCK_THREADS = 256;

kernel void hadamard_xhead_select_scan(
    device const float* logits      [[buffer(0)]],
    device int*         part_ids    [[buffer(1)]],
    device float*       part_values [[buffer(2)]],
    device int*         part_meta   [[buffer(3)]],
    constant int&       NV          [[buffer(4)]],
    uint2               tgid        [[threadgroup_position_in_grid]],
    uint                lane        [[thread_index_in_threadgroup]],
    uint                simd_lid    [[thread_index_in_simdgroup]],
    uint                simd_gid    [[simdgroup_index_in_threadgroup]]
) {
    const uint block = tgid.x;
    const uint row = tgid.y;
    const int quads = NV / (4 * XHEAD_BLOCKS);
    const uint first = block * uint(quads) * 4u;
    const device float4* lq = (const device float4*)(logits + size_t(row) * size_t(NV) + first);
    threadgroup hadamard_top2 scratch[XHEAD_BLOCK_THREADS / 32];
    threadgroup int scratch_bad[XHEAD_BLOCK_THREADS / 32];
    hadamard_top2 local = hadamard_top2_empty();
    bool bad = false;
    for (int q = int(lane); q < quads; q += XHEAD_BLOCK_THREADS) {
        const float4 v4 = lq[q];
        for (int i = 0; i < 4; i++) {
            const float v = v4[i];
            bad = bad || !isfinite(v);
            if (local.count == 2 && !(v > local.second_value)) continue;
            hadamard_top2_insert(local, v, first + uint(q) * 4u + uint(i));
        }
    }
    for (uint stride = 16; stride > 0; stride >>= 1) {
        hadamard_top2 other;
        other.first_value = simd_shuffle_down(local.first_value, stride);
        other.second_value = simd_shuffle_down(local.second_value, stride);
        other.first_id = simd_shuffle_down(local.first_id, stride);
        other.second_id = simd_shuffle_down(local.second_id, stride);
        other.count = simd_shuffle_down(local.count, stride);
        if (simd_lid < stride) hadamard_top2_merge(local, other);
    }
    const int any_bad = simd_max(bad ? 1 : 0);
    if (simd_lid == 0) {
        scratch[simd_gid] = local;
        scratch_bad[simd_gid] = any_bad;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (lane == 0) {
        int b = scratch_bad[0];
        for (uint s = 1; s < XHEAD_BLOCK_THREADS / 32; s++) {
            hadamard_top2_merge(local, scratch[s]);
            b |= scratch_bad[s];
        }
        const uint p = row * uint(XHEAD_BLOCKS) + block;
        part_ids[p * 2] = int(local.first_id);
        part_ids[p * 2 + 1] = int(local.second_id);
        part_values[p * 2] = local.first_value;
        part_values[p * 2 + 1] = local.second_value;
        part_meta[p] = b | int(local.count << 1);
    }
}

// Per-(row, block) shortlist filter (`L8 >= tau`) and exact FP32 rescore.
// Grid: (BLOCKS, rows, 1) threadgroups of 256 threads.
kernel void hadamard_xhead_select_rescore(
    device const float*    logits      [[buffer(0)]],
    device const float*    ascale      [[buffer(1)]],
    device const float*    bounds      [[buffer(2)]],
    device const float*    x           [[buffer(3)]],
    device const uint32_t* w           [[buffer(4)]],
    device const half*     scales      [[buffer(5)]],
    device const half*     biases      [[buffer(6)]],
    device const int*      part_ids    [[buffer(7)]],
    device const float*    part_values [[buffer(8)]],
    device const int*      part_meta   [[buffer(9)]],
    device int*            blk_ids     [[buffer(10)]],
    device float*          blk_values  [[buffer(11)]],
    device int*            blk_meta    [[buffer(12)]],
    device float*          row_e       [[buffer(13)]],
    constant int&          K           [[buffer(14)]],
    constant int&          NV          [[buffer(15)]],
    constant int&          neg         [[buffer(16)]],
    uint2                  tgid        [[threadgroup_position_in_grid]],
    uint                   lane        [[thread_index_in_threadgroup]],
    uint                   simd_lid    [[thread_index_in_simdgroup]],
    uint                   simd_gid    [[simdgroup_index_in_threadgroup]]
) {
    const uint block = tgid.x;
    const uint row = tgid.y;
    const int in_g = K / 128;
    threadgroup atomic_int cand_count;
    threadgroup int cand_ids[XHEAD_CAP];
    threadgroup float cand_values[XHEAD_CAP];
    threadgroup float shared_tau[2];
    threadgroup int shared_bad;
    if (lane == 0) atomic_store_explicit(&cand_count, 0, memory_order_relaxed);
    if (simd_gid == 0) {
        hadamard_top2 local = hadamard_top2_empty();
        int pbad = 0;
        for (uint pb = simd_lid; pb < uint(XHEAD_BLOCKS); pb += 32) {
            const uint p = row * uint(XHEAD_BLOCKS) + pb;
            const int meta = part_meta[p];
            hadamard_top2 o;
            o.first_value = part_values[p * 2];
            o.second_value = part_values[p * 2 + 1];
            o.first_id = uint(part_ids[p * 2]);
            o.second_id = uint(part_ids[p * 2 + 1]);
            o.count = uint(meta >> 1);
            hadamard_top2_merge(local, o);
            pbad |= meta & 1;
        }
        for (uint stride = 16; stride > 0; stride >>= 1) {
            hadamard_top2 other;
            other.first_value = simd_shuffle_down(local.first_value, stride);
            other.second_value = simd_shuffle_down(local.second_value, stride);
            other.first_id = simd_shuffle_down(local.first_id, stride);
            other.second_id = simd_shuffle_down(local.second_id, stride);
            other.count = simd_shuffle_down(local.count, stride);
            if (simd_lid < stride) hadamard_top2_merge(local, other);
        }
        pbad = simd_max(pbad);
        if (simd_lid == 0) {
            float e = 0.0f;
            for (int g = 0; g < in_g; g++) {
                e += ascale[row * uint(in_g) + uint(g)]
                    * (bounds[g] * (0.5f + 127.0f * 3.0e-5f) + bounds[in_g + g] * 1.0e-5f);
            }
            e *= 1.001f;
            const float t = local.second_value - 2.0f * e;
            shared_tau[0] = t - (fabs(t) * 2.4e-7f + 1.0e-30f);
            shared_tau[1] = e;
            shared_bad = (pbad != 0 || local.count < 2 || !isfinite(e) || !isfinite(t)) ? 1 : 0;
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    const float tau = shared_tau[0];
    const int quads = NV / (4 * XHEAD_BLOCKS);
    const uint first = block * uint(quads) * 4u;
    const device float4* lq = (const device float4*)(logits + size_t(row) * size_t(NV) + first);
    for (int q = int(lane); q < quads; q += XHEAD_BLOCK_THREADS) {
        const float4 v4 = lq[q];
        for (int i = 0; i < 4; i++) {
            if (v4[i] >= tau) {
                const int slot = atomic_fetch_add_explicit(&cand_count, 1, memory_order_relaxed);
                if (slot < XHEAD_CAP) cand_ids[slot] = int(first + uint(q) * 4u + uint(i));
            }
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    const int count = atomic_load_explicit(&cand_count, memory_order_relaxed);
    const int used = count > XHEAD_CAP ? 0 : count;
    for (int c = int(simd_gid); c < used; c += XHEAD_BLOCK_THREADS / 32) {
        const int out_row = cand_ids[c];
        const float total = hadamard_xhead_eval_row(
            int(row), out_row, K, neg, simd_lid, x, w, scales, biases);
        if (simd_lid == 0) cand_values[c] = total;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    if (lane == 0) {
        hadamard_top2 best = hadamard_top2_empty();
        bool nonfinite = false;
        for (int c = 0; c < used; c++) {
            nonfinite = nonfinite || !isfinite(cand_values[c]);
            hadamard_top2_insert(best, cand_values[c], uint(cand_ids[c]));
        }
        const uint p = row * uint(XHEAD_BLOCKS) + block;
        blk_ids[p * 2] = int(best.first_id);
        blk_ids[p * 2 + 1] = int(best.second_id);
        blk_values[p * 2] = best.first_value;
        blk_values[p * 2 + 1] = best.second_value;
        blk_meta[p * 4] = count;
        blk_meta[p * 4 + 1] = int(best.count);
        blk_meta[p * 4 + 2] = nonfinite ? 1 : 0;
        blk_meta[p * 4 + 3] = shared_bad;
        if (block == 0) row_e[row] = shared_tau[1];
    }
}

// One simdgroup per row merges the 64 block top-2s into the certified FP32 top-2.
// Grid: (rows, 1, 1) threadgroups of 32 threads.
kernel void hadamard_xhead_select_merge(
    device const int*   blk_ids    [[buffer(0)]],
    device const float* blk_values [[buffer(1)]],
    device const int*   blk_meta   [[buffer(2)]],
    device const float* row_e      [[buffer(3)]],
    device int*         sel_ids    [[buffer(4)]],
    device float*       sel_values [[buffer(5)]],
    device int*         flag       [[buffer(6)]],
    device float*       info       [[buffer(7)]],
    uint                row        [[threadgroup_position_in_grid]],
    uint                simd_lid   [[thread_index_in_simdgroup]]
) {
    hadamard_top2 best = hadamard_top2_empty();
    int count = 0, nonfinite = 0, bad = 0;
    for (uint pb = simd_lid; pb < uint(XHEAD_BLOCKS); pb += 32) {
        const uint p = row * uint(XHEAD_BLOCKS) + pb;
        count += blk_meta[p * 4];
        const int valid = blk_meta[p * 4 + 1];
        nonfinite |= blk_meta[p * 4 + 2];
        bad |= blk_meta[p * 4 + 3];
        if (valid > 0) hadamard_top2_insert(best, blk_values[p * 2], uint(blk_ids[p * 2]));
        if (valid > 1) hadamard_top2_insert(best, blk_values[p * 2 + 1], uint(blk_ids[p * 2 + 1]));
    }
    for (uint stride = 16; stride > 0; stride >>= 1) {
        hadamard_top2 other;
        other.first_value = simd_shuffle_down(best.first_value, stride);
        other.second_value = simd_shuffle_down(best.second_value, stride);
        other.first_id = simd_shuffle_down(best.first_id, stride);
        other.second_id = simd_shuffle_down(best.second_id, stride);
        other.count = simd_shuffle_down(best.count, stride);
        if (simd_lid < stride) hadamard_top2_merge(best, other);
    }
    count = simd_sum(count);
    nonfinite = simd_max(nonfinite);
    bad = simd_max(bad);
    if (simd_lid == 0) {
        const bool fallback = bad != 0 || count > XHEAD_CAP || nonfinite != 0 || best.count < 2;
        sel_ids[row * 2] = int(best.first_id);
        sel_ids[row * 2 + 1] = int(best.second_id);
        sel_values[row * 2] = best.first_value;
        sel_values[row * 2 + 1] = best.second_value;
        flag[row] = fallback ? 1 : 0;
        info[row * 2] = row_e[row];
        info[row * 2 + 1] = float(count);
    }
}
