// int8_hadamard_matmul_na.metal — Signed Block-Hadamard 4096-wide 3-pass
// radix-16 butterfly + fused boundary quantizers + M5 Neural Accelerator
// (`mpp::tensor_ops::matmul2d`) integer `int8 x u2 -> int32` matmul kernels
// for both prefill (64x64 tile, 4x 32x32x128 `execution_simdgroup`) and
// 2..16-row speculative verify (16x32x128 `execution_simdgroup` with 4-way
// K-group split).
//
// Ported from Layr-Labs/mlxfast-bonsai2-9b-engine (`Hadamard.swift`:
// `SignedBlockHadamard`, `PromptInt8Matmul`, `VerifyInt8Matmul`).
//
// Mathematical invariant (exact int32 == exact FP32 within each 128-group):
//   For output (m, n) and 128-element group g:
//     C   = sum_{k in g} q[m, k] * code[n, k]        (exact integer, |C| <= 48,768 < 2^24)
//     t   = s[n, g] * float(C)
//     acc = fma(b[n, g], rsb[m, g], fma(ascale[m, g], t, acc))
//   where q[m, k] in [-127, 127], code[n, k] in {0, 1, 2, 3},
//   ascale[m, g] = amax / 127, and rsb[m, g] = ascale[m, g] * sum_{k in g} q[m, k].
//
// Staged byte permutation within each 16-element word (4 bytes of 2-bit codes):
//   Position p in 0..15 holds element `4 * (p % 4) + (p / 4)`. This allows
//   a 32-bit word `wv` of 16x 2-bit codes to be unpacked into four 32-bit
//   int8x4 words in 4 bit-masks:
//     uint4(wv & 0x03030303u, (wv >> 2) & 0x03030303u,
//           (wv >> 4) & 0x03030303u, (wv >> 6) & 0x03030303u)
//   The activation quantizer writes `char4(q[w], q[4+w], q[8+w], q[12+w])` in
//   the identical order so the inner product is unchanged without per-element
//   byte shuffles during weight staging.

#include <metal_stdlib>
#include <metal_simdgroup>
#include <metal_simdgroup_matrix>
#include <metal_tensor>
#include <MetalPerformancePrimitives/MetalPerformancePrimitives.h>

using namespace metal;

// ---------------------------------------------------------------------------
// 1. Radix-16 In-Register Walsh-Hadamard Butterfly
// ---------------------------------------------------------------------------

METAL_FUNC void hadamard_radix16(thread float* x) {
    #pragma clang loop unroll(full)
    for (short j = 0; j < 16; j += 2) {
        float a = x[j], b = x[j + 1];
        x[j] = a + b;
        x[j + 1] = a - b;
    }
    #pragma clang loop unroll(full)
    for (short j = 0; j < 16; j += 4) {
        #pragma clang loop unroll(full)
        for (short k = 0; k < 2; k++) {
            float a = x[j + k], b = x[j + k + 2];
            x[j + k] = a + b;
            x[j + k + 2] = a - b;
        }
    }
    #pragma clang loop unroll(full)
    for (short j = 0; j < 16; j += 8) {
        #pragma clang loop unroll(full)
        for (short k = 0; k < 4; k++) {
            float a = x[j + k], b = x[j + k + 4];
            x[j + k] = a + b;
            x[j + k + 4] = a - b;
        }
    }
    #pragma clang loop unroll(full)
    for (short k = 0; k < 8; k++) {
        float a = x[k], b = x[k + 8];
        x[k] = a + b;
        x[k + 8] = a - b;
    }
}

// Index of (row, group) in the 64-row tiled constant layout used by
// `PromptInt8Matmul` so each lane loads its 4 row scales as one `float4`.
inline size_t bonsai_q8_cidx(int m, int g, int Kg) {
    const uint ml = uint(m) & 63u;
    return size_t(m >> 6) * size_t(Kg) * 64 + size_t(g) * 64
        + size_t(((ml >> 4) & 1u) * 32u + (ml & 7u) * 4u + ((ml >> 5) & 1u) * 2u + ((ml >> 3) & 1u));
}

// ---------------------------------------------------------------------------
// 2. 4096-Wide 3-Pass Radix-16 Signed Block-Hadamard Transform (FP32)
//    Threadgroup: (256, 1, 1), Grid: (256, num_4096_blocks, 1)
//    Uses padded `buf[256 * 17]` (stride 17) for bank-conflict-free transposes.
// ---------------------------------------------------------------------------

kernel void signed_block_hadamard_4096_f32(
    device const float* x           [[buffer(0)]],
    device const float* signs       [[buffer(1)]],
    device float*       y           [[buffer(2)]],
    constant int&       blocks_per_row [[buffer(3)]],
    constant int&       inverse     [[buffer(4)]],
    uint                tid_x       [[thread_index_in_threadgroup]],
    uint2               tgid        [[threadgroup_position_in_grid]]
) {
    #pragma clang fp reassociate(off)
    const short i = short(tid_x);
    const uint block_idx = tgid.y;
    const uint batch_idx = block_idx * 4096u;
    const uint sign_offset = (blocks_per_row == 1)
        ? 0u : (block_idx % uint(blocks_per_row)) * 4096u;

    threadgroup float buf[256 * 17];
    float x_reg[16];

    const short base0 = i << 4;
    const uint in_offset = batch_idx + uint(base0);
    const uint s_offset = sign_offset + uint(base0);
    const device float4* in4 = (const device float4*)(x + in_offset);
    const device float4* s4 = (const device float4*)(signs + s_offset);
    #pragma clang loop unroll(full)
    for (short v = 0; v < 4; v++) {
        float4 val = in4[v];
        if (!inverse) {
            val *= s4[v];
        }
        x_reg[4 * v + 0] = val.x;
        x_reg[4 * v + 1] = val.y;
        x_reg[4 * v + 2] = val.z;
        x_reg[4 * v + 3] = val.w;
    }
    hadamard_radix16(x_reg);
    #pragma clang loop unroll(full)
    for (short r = 0; r < 16; r++) {
        buf[i * 17 + r] = x_reg[r];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    const short k1 = i & 15;
    const short r_base2 = (i - k1);
    #pragma clang loop unroll(full)
    for (short r = 0; r < 16; r++) {
        x_reg[r] = buf[(r_base2 + r) * 17 + k1];
    }
    hadamard_radix16(x_reg);
    #pragma clang loop unroll(full)
    for (short r = 0; r < 16; r++) {
        buf[(r_base2 + r) * 17 + k1] = x_reg[r];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    const short i_hi = i >> 4;
    const short i_lo = i & 15;
    #pragma clang loop unroll(full)
    for (short r = 0; r < 16; r++) {
        x_reg[r] = buf[(i_hi + 16 * r) * 17 + i_lo];
    }
    hadamard_radix16(x_reg);
    #pragma clang loop unroll(full)
    for (short r = 0; r < 16; r++) {
        const uint idx = uint(i + 256 * r);
        float val = x_reg[r] * 0.015625f;
        if (inverse) {
            val *= signs[sign_offset + idx];
        }
        y[batch_idx + idx] = val;
    }
}

// ---------------------------------------------------------------------------
// 3. Fused Boundary + 4096-Wide Hadamard + Int8 Group-128 Quantizers
//    Shared epilogue helper: quantizes 4096 rotated values in `buf` into
//    staged `char4` codes + per-128-group `ascale` and `rsb`.
// ---------------------------------------------------------------------------

METAL_FUNC void hadamard_4096_q8_finish(
    short i,
    uint block_idx,
    uint batch_idx,
    int blocks_per_row,
    int verify_rows,
    thread float* x_reg,
    threadgroup float* buf,
    device int8_t* codes,
    device float* ascale,
    device float* rsb,
    device float* rotated_out
) {
    #pragma clang fp reassociate(off)
    const short base0 = i << 4;
    hadamard_radix16(x_reg);
    #pragma clang loop unroll(full)
    for (short r = 0; r < 16; r++) {
        buf[i * 17 + r] = x_reg[r];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    const short k1 = i & 15;
    const short r_base2 = (i - k1);
    #pragma clang loop unroll(full)
    for (short r = 0; r < 16; r++) {
        x_reg[r] = buf[(r_base2 + r) * 17 + k1];
    }
    hadamard_radix16(x_reg);
    #pragma clang loop unroll(full)
    for (short r = 0; r < 16; r++) {
        buf[(r_base2 + r) * 17 + k1] = x_reg[r];
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    const short i_hi = i >> 4;
    const short i_lo = i & 15;
    #pragma clang loop unroll(full)
    for (short r = 0; r < 16; r++) {
        x_reg[r] = buf[(i_hi + 16 * r) * 17 + i_lo];
    }
    hadamard_radix16(x_reg);
    #pragma clang loop unroll(full)
    for (short r = 0; r < 16; r++) {
        buf[(i_hi + 16 * r) * 17 + i_lo] = x_reg[r] * 0.015625f;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);

    float v[16];
    float amax = 0.0f;
    #pragma clang loop unroll(full)
    for (short r = 0; r < 16; r++) {
        v[r] = buf[i * 17 + r];
        amax = max(amax, fabs(v[r]));
    }
    if (rotated_out != nullptr) {
        device float4* rot4 = (device float4*)(rotated_out + batch_idx + uint(base0));
        #pragma clang loop unroll(full)
        for (short w = 0; w < 4; w++) {
            rot4[w] = float4(v[4 * w + 0], v[4 * w + 1], v[4 * w + 2], v[4 * w + 3]);
        }
    }
    amax = max(amax, simd_shuffle_xor(amax, ushort(1)));
    amax = max(amax, simd_shuffle_xor(amax, ushort(2)));
    amax = max(amax, simd_shuffle_xor(amax, ushort(4)));
    const float qs = amax > 0.0f ? amax * (1.0f / 127.0f) : 1.0f;
    const float iqs = amax > 0.0f ? metal::precise::divide(127.0f, amax) : 0.0f;
    float q[16];
    float part = 0.0f;
    #pragma clang loop unroll(full)
    for (short r = 0; r < 16; r++) {
        q[r] = rint(v[r] * iqs);
        part += q[r];
    }
    part += simd_shuffle_xor(part, ushort(1));
    part += simd_shuffle_xor(part, ushort(2));
    part += simd_shuffle_xor(part, ushort(4));
    device char4* dst = (device char4*)(codes + batch_idx + uint(base0));
    #pragma clang loop unroll(full)
    for (short w = 0; w < 4; w++) {
        dst[w] = char4(char(q[w]), char(q[4 + w]), char(q[8 + w]), char(q[12 + w]));
    }
    if ((i & 7) == 0) {
        const uint row = block_idx / uint(blocks_per_row);
        const uint kg = uint(blocks_per_row) * 32u;
        const uint g = (block_idx % uint(blocks_per_row)) * 32u + uint(i >> 3);
        const size_t qidx = verify_rows > 0
            ? size_t(row) * size_t(kg) + size_t(g)
            : bonsai_q8_cidx(int(row), int(g), int(kg));
        ascale[qidx] = qs;
        rsb[qidx] = qs * part;
    }
}

// 3a. Plain 4096-wide forward Hadamard + Int8 quantizer
kernel void signed_block_hadamard_4096_q8(
    device const float* x              [[buffer(0)]],
    device const float* signs          [[buffer(1)]],
    device int8_t*      codes          [[buffer(2)]],
    device float*       ascale         [[buffer(3)]],
    device float*       rsb            [[buffer(4)]],
    constant int&       blocks_per_row [[buffer(5)]],
    constant int&       verify_rows    [[buffer(6)]],
    uint                tid_x          [[thread_index_in_threadgroup]],
    uint2               tgid           [[threadgroup_position_in_grid]]
) {
    #pragma clang fp reassociate(off)
    const short i = short(tid_x);
    const uint block_idx = tgid.y;
    const uint batch_idx = block_idx * 4096u;
    const uint sign_offset = (blocks_per_row == 1)
        ? 0u : (block_idx % uint(blocks_per_row)) * 4096u;
    if (verify_rows > 0 && block_idx >= uint(verify_rows * blocks_per_row)) {
        device char4* pad = (device char4*)(codes + batch_idx + uint(i) * 16u);
        pad[0] = char4(0); pad[1] = char4(0); pad[2] = char4(0); pad[3] = char4(0);
        return;
    }
    threadgroup float buf[256 * 17];
    float x_reg[16];
    const short base0 = i << 4;
    const device float4* in4 = (const device float4*)(x + batch_idx + uint(base0));
    const device float4* s4 = (const device float4*)(signs + sign_offset + uint(base0));
    #pragma clang loop unroll(full)
    for (short w = 0; w < 4; w++) {
        float4 val = in4[w] * s4[w];
        x_reg[4 * w + 0] = val.x;
        x_reg[4 * w + 1] = val.y;
        x_reg[4 * w + 2] = val.z;
        x_reg[4 * w + 3] = val.w;
    }
    hadamard_4096_q8_finish(
        i, block_idx, batch_idx, blocks_per_row, verify_rows,
        x_reg, buf, codes, ascale, rsb, nullptr);
}

// 3b. Fused SwiGLU (`silu(gate) * up`) + 4096-wide Hadamard + Int8 quantizer
kernel void signed_block_hadamard_swiglu_4096_q8(
    device const float* gate           [[buffer(0)]],
    device const float* up             [[buffer(1)]],
    device const float* signs          [[buffer(2)]],
    device int8_t*      codes          [[buffer(3)]],
    device float*       ascale         [[buffer(4)]],
    device float*       rsb            [[buffer(5)]],
    constant int&       blocks_per_row [[buffer(6)]],
    constant int&       verify_rows    [[buffer(7)]],
    uint                tid_x          [[thread_index_in_threadgroup]],
    uint2               tgid           [[threadgroup_position_in_grid]]
) {
    #pragma clang fp reassociate(off)
    const short i = short(tid_x);
    const uint block_idx = tgid.y;
    const uint batch_idx = block_idx * 4096u;
    const uint sign_offset = (blocks_per_row == 1)
        ? 0u : (block_idx % uint(blocks_per_row)) * 4096u;
    if (verify_rows > 0 && block_idx >= uint(verify_rows * blocks_per_row)) {
        device char4* pad = (device char4*)(codes + batch_idx + uint(i) * 16u);
        pad[0] = char4(0); pad[1] = char4(0); pad[2] = char4(0); pad[3] = char4(0);
        return;
    }
    threadgroup float buf[256 * 17];
    float x_reg[16];
    const short base0 = i << 4;
    const uint in_offset = batch_idx + uint(base0);
    const device float4* in4 = (const device float4*)(gate + in_offset);
    const device float4* up4 = (const device float4*)(up + in_offset);
    const device float4* s4 = (const device float4*)(signs + sign_offset + uint(base0));
    #pragma clang loop unroll(full)
    for (short w = 0; w < 4; w++) {
        const float4 g = in4[w];
        const float4 u = up4[w];
        const float4 e = 1.0f / (1.0f + metal::exp(metal::abs(g)));
        const float4 sigmoid_g = select(1.0f - e, e, g < 0.0f);
        float4 val = ((g * sigmoid_g) * u) * s4[w];
        x_reg[4 * w + 0] = val.x;
        x_reg[4 * w + 1] = val.y;
        x_reg[4 * w + 2] = val.z;
        x_reg[4 * w + 3] = val.w;
    }
    hadamard_4096_q8_finish(
        i, block_idx, batch_idx, blocks_per_row, verify_rows,
        x_reg, buf, codes, ascale, rsb, nullptr);
}

// 3c. Fused `residual + x` + RMSNorm(4096) + Hadamard + Int8 quantizer
kernel void signed_block_hadamard_residual_norm_4096_q8(
    device const float* x              [[buffer(0)]],
    device const float* residual       [[buffer(1)]],
    device const float* norm_weight    [[buffer(2)]],
    device const float* epsilon        [[buffer(3)]],
    device const float* signs          [[buffer(4)]],
    device int8_t*      codes          [[buffer(5)]],
    device float*       ascale         [[buffer(6)]],
    device float*       rsb            [[buffer(7)]],
    device float*       residual_out   [[buffer(8)]],
    constant int&       blocks_per_row [[buffer(9)]],
    constant int&       verify_rows    [[buffer(10)]],
    uint                tid_x          [[thread_index_in_threadgroup]],
    uint                norm_lane      [[thread_index_in_simdgroup]],
    uint                norm_sg        [[simdgroup_index_in_threadgroup]],
    uint2               tgid           [[threadgroup_position_in_grid]]
) {
    #pragma clang fp reassociate(off)
    const short i = short(tid_x);
    const uint block_idx = tgid.y;
    const uint batch_idx = block_idx * 4096u;
    const uint sign_offset = (blocks_per_row == 1)
        ? 0u : (block_idx % uint(blocks_per_row)) * 4096u;
    if (verify_rows > 0 && block_idx >= uint(verify_rows * blocks_per_row)) {
        device char4* pad = (device char4*)(codes + batch_idx + uint(i) * 16u);
        pad[0] = char4(0); pad[1] = char4(0); pad[2] = char4(0); pad[3] = char4(0);
        return;
    }
    threadgroup float norm_sums[32];
    for (uint part = 0; part < 4; ++part) {
        const uint at = batch_idx + (uint(i) + part * 256u) * 4u;
        const float4 value = *((const device float4*)(x + at))
            + *((const device float4*)(residual + at));
        float square_sum = 0.0f;
        #pragma clang loop unroll(full)
        for (int j = 0; j < 4; ++j) square_sum += value[j] * value[j];
        square_sum = simd_sum(square_sum);
        if (norm_lane == 0) norm_sums[norm_sg + part * 8u] = square_sum;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    const float norm_total = simd_sum(norm_sums[norm_lane]);
    const float norm_inv = metal::precise::rsqrt(norm_total / 4096.0f + epsilon[0]);

    threadgroup float buf[256 * 17];
    float x_reg[16];
    const short base0 = i << 4;
    const uint in_offset = batch_idx + uint(base0);
    const uint s_offset = sign_offset + uint(base0);
    const device float4* in4 = (const device float4*)(x + in_offset);
    const device float4* s4 = (const device float4*)(signs + s_offset);
    #pragma clang loop unroll(full)
    for (short w = 0; w < 4; w++) {
        const float4 raw = in4[w] + *((const device float4*)(residual + in_offset) + w);
        *((device float4*)(residual_out + in_offset) + w) = raw;
        const float4 weight = *((const device float4*)(norm_weight + s_offset) + w);
        float4 val = (weight * (raw * norm_inv)) * s4[w];
        x_reg[4 * w + 0] = val.x;
        x_reg[4 * w + 1] = val.y;
        x_reg[4 * w + 2] = val.z;
        x_reg[4 * w + 3] = val.w;
    }
    hadamard_4096_q8_finish(
        i, block_idx, batch_idx, blocks_per_row, verify_rows,
        x_reg, buf, codes, ascale, rsb, nullptr);
}

// 3d. Fused Layer-0 2-bit Embedding Dequant + Inverse Hadamard + RMSNorm(4096) + Forward Hadamard + Int8 Quantizer
kernel void signed_block_hadamard_embed_norm_4096_q8(
    device const int32_t*  indices        [[buffer(0)]],
    device const uint32_t* ew             [[buffer(1)]],
    device const half*     es             [[buffer(2)]],
    device const half*     eb             [[buffer(3)]],
    device const float*    embed_signs    [[buffer(4)]],
    device const float*    norm_weight    [[buffer(5)]],
    device const float*    epsilon        [[buffer(6)]],
    device const float*    signs          [[buffer(7)]],
    device int8_t*         codes          [[buffer(8)]],
    device float*          ascale         [[buffer(9)]],
    device float*          rsb            [[buffer(10)]],
    device float*          residual_out   [[buffer(11)]],
    constant int&          vocab_size     [[buffer(12)]],
    constant int&          verify_rows    [[buffer(13)]],
    uint                   tid_x          [[thread_index_in_threadgroup]],
    uint                   norm_lane      [[thread_index_in_simdgroup]],
    uint                   norm_sg        [[simdgroup_index_in_threadgroup]],
    uint2                  tgid           [[threadgroup_position_in_grid]]
) {
    #pragma clang fp reassociate(off)
    const short i = short(tid_x);
    const uint block_idx = tgid.y;
    const uint batch_idx = block_idx * 4096u;
    if (verify_rows > 0 && block_idx >= uint(verify_rows)) {
        device char4* pad = (device char4*)(codes + batch_idx + uint(i) * 16u);
        pad[0] = char4(0); pad[1] = char4(0); pad[2] = char4(0); pad[3] = char4(0);
        return;
    }
    threadgroup float buf[256 * 17];
    float x_reg[16];
    {
        const int64_t raw_tok = int64_t(indices[block_idx]);
        const int64_t tok = raw_tok < 0 ? raw_tok + int64_t(vocab_size) : raw_tok;
        const uint q = ew[tok * 256 + i];
        const half scale = es[tok * 32 + (i >> 3)];
        const half bias = eb[tok * 32 + (i >> 3)];
        #pragma clang loop unroll(full)
        for (short r = 0; r < 16; r++) {
            const uint8_t d = (q >> (2 * r)) & 0x03u;
            const half deq = scale * d + bias;
            x_reg[r] = float(deq);
        }
        hadamard_radix16(x_reg);
        #pragma clang loop unroll(full)
        for (short r = 0; r < 16; r++) {
            buf[i * 17 + r] = x_reg[r];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        const short ek1 = i & 15;
        const short er_base2 = (i - ek1);
        #pragma clang loop unroll(full)
        for (short r = 0; r < 16; r++) {
            x_reg[r] = buf[(er_base2 + r) * 17 + ek1];
        }
        hadamard_radix16(x_reg);
        #pragma clang loop unroll(full)
        for (short r = 0; r < 16; r++) {
            buf[(er_base2 + r) * 17 + ek1] = x_reg[r];
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        const short ei_hi = i >> 4;
        const short ei_lo = i & 15;
        #pragma clang loop unroll(full)
        for (short r = 0; r < 16; r++) {
            x_reg[r] = buf[(ei_hi + 16 * r) * 17 + ei_lo];
        }
        hadamard_radix16(x_reg);
        #pragma clang loop unroll(full)
        for (short r = 0; r < 16; r++) {
            const uint idx = uint(i + 256 * r);
            const float ef = float(half(x_reg[r] * 0.015625f * embed_signs[idx]));
            buf[(ei_hi + 16 * r) * 17 + ei_lo] = ef;
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    threadgroup float norm_sums[32];
    for (uint part = 0; part < 4; ++part) {
        const uint u = uint(i) + part * 256u;
        const threadgroup float* bp = buf + (u >> 2) * 17u + (u & 3u) * 4u;
        const float4 value = float4(bp[0], bp[1], bp[2], bp[3]);
        float square_sum = 0.0f;
        #pragma clang loop unroll(full)
        for (int j = 0; j < 4; ++j) square_sum += value[j] * value[j];
        square_sum = simd_sum(square_sum);
        if (norm_lane == 0) norm_sums[norm_sg + part * 8u] = square_sum;
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    const float norm_total = simd_sum(norm_sums[norm_lane]);
    const float norm_inv = metal::precise::rsqrt(norm_total / 4096.0f + epsilon[0]);

    const short base0 = i << 4;
    const uint in_offset = batch_idx + uint(base0);
    const device float4* s4 = (const device float4*)(signs + uint(base0));
    #pragma clang loop unroll(full)
    for (short w = 0; w < 4; w++) {
        const threadgroup float* bw = buf + i * 17 + 4 * w;
        const float4 raw = float4(bw[0], bw[1], bw[2], bw[3]);
        *((device float4*)(residual_out + in_offset) + w) = raw;
        const float4 weight = *((const device float4*)(norm_weight + uint(base0)) + w);
        float4 val = (weight * (raw * norm_inv)) * s4[w];
        x_reg[4 * w + 0] = val.x;
        x_reg[4 * w + 1] = val.y;
        x_reg[4 * w + 2] = val.z;
        x_reg[4 * w + 3] = val.w;
    }
    hadamard_4096_q8_finish(
        i, block_idx, batch_idx, 1, verify_rows,
        x_reg, buf, codes, ascale, rsb, nullptr);
}

// 3e. Fused GatedDeltaNet Per-Head (128-wide) RMSNorm + SiLU(gate) + Hadamard + Int8 Quantizer
kernel void signed_block_hadamard_gated_norm_4096_q8(
    device const float* x           [[buffer(0)]],
    device const float* gate        [[buffer(1)]],
    device const float* norm_weight [[buffer(2)]],
    device const float* epsilon     [[buffer(3)]],
    device const float* signs       [[buffer(4)]],
    device int8_t*      codes       [[buffer(5)]],
    device float*       ascale      [[buffer(6)]],
    device float*       rsb         [[buffer(7)]],
    constant int&       verify_rows [[buffer(8)]],
    uint                tid_x       [[thread_index_in_threadgroup]],
    uint                norm_lane   [[thread_index_in_simdgroup]],
    uint                norm_sg     [[simdgroup_index_in_threadgroup]],
    uint2               tgid        [[threadgroup_position_in_grid]]
) {
    #pragma clang fp reassociate(off)
    const short i = short(tid_x);
    const uint block_idx = tgid.y;
    const uint batch_idx = block_idx * 4096u;
    if (verify_rows > 0 && block_idx >= uint(verify_rows)) {
        device char4* pad = (device char4*)(codes + batch_idx + uint(i) * 16u);
        pad[0] = char4(0); pad[1] = char4(0); pad[2] = char4(0); pad[3] = char4(0);
        return;
    }
    threadgroup float head_part[32 * 32];
    {
        const device float4* nx4 = (const device float4*)(x + batch_idx + (uint(i) << 4));
        const uint part_base = (uint(i) >> 3) * 32u + (uint(i) & 7u) * 4u;
        #pragma clang loop unroll(full)
        for (short w = 0; w < 4; w++) {
            const float4 nv = nx4[w];
            float acc = 0.0f;
            acc += nv.x * nv.x;
            acc += nv.y * nv.y;
            acc += nv.z * nv.z;
            acc += nv.w * nv.w;
            head_part[part_base + uint(w)] = acc;
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    float head_inv_value = 0.0f;
    {
        const uint head_base = norm_sg * 4u;
        for (uint k = 0; k < 4u; ++k) {
            const float total = simd_sum(head_part[(head_base + k) * 32u + norm_lane]);
            const float inv = metal::precise::rsqrt(total / 128.0f + epsilon[0]);
            if ((norm_lane >> 3) == k) head_inv_value = inv;
        }
    }

    threadgroup float buf[256 * 17];
    float x_reg[16];
    const short base0 = i << 4;
    const uint in_offset = batch_idx + uint(base0);
    const device float4* in4 = (const device float4*)(x + in_offset);
    const device float4* s4 = (const device float4*)(signs + uint(base0));
    #pragma clang loop unroll(full)
    for (short w = 0; w < 4; w++) {
        const float4 g = *((const device float4*)(gate + in_offset) + w);
        const float4 nw = *((const device float4*)(norm_weight + ((uint(i) & 7u) << 4)) + w);
        const float4 normed = nw * (in4[w] * head_inv_value);
        const float4 e = 1.0f / (1.0f + metal::exp(metal::abs(g)));
        const float4 sigmoid_g = select(1.0f - e, e, g < 0.0f);
        float4 val = ((g * sigmoid_g) * normed) * s4[w];
        x_reg[4 * w + 0] = val.x;
        x_reg[4 * w + 1] = val.y;
        x_reg[4 * w + 2] = val.z;
        x_reg[4 * w + 3] = val.w;
    }
    hadamard_4096_q8_finish(
        i, block_idx, batch_idx, 1, verify_rows,
        x_reg, buf, codes, ascale, rsb, nullptr);
}

// 3f. Fused Full-Attention Head-Major `[1, 16, rows, 256]` Transpose + Sigmoid Gate + Hadamard + Int8 Quantizer
kernel void signed_block_hadamard_attention_gate_4096_q8(
    device const float* x              [[buffer(0)]],
    device const float* gate           [[buffer(1)]],
    device const float* signs          [[buffer(2)]],
    device int8_t*      codes          [[buffer(3)]],
    device float*       ascale         [[buffer(4)]],
    device float*       rsb            [[buffer(5)]],
    constant int&       attention_rows [[buffer(6)]],
    constant int&       verify_rows    [[buffer(7)]],
    uint                tid_x          [[thread_index_in_threadgroup]],
    uint2               tgid           [[threadgroup_position_in_grid]]
) {
    #pragma clang fp reassociate(off)
    const short i = short(tid_x);
    const uint block_idx = tgid.y;
    const uint batch_idx = block_idx * 4096u;
    if (verify_rows > 0 && block_idx >= uint(verify_rows)) {
        device char4* pad = (device char4*)(codes + batch_idx + uint(i) * 16u);
        pad[0] = char4(0); pad[1] = char4(0); pad[2] = char4(0); pad[3] = char4(0);
        return;
    }
    threadgroup float buf[256 * 17];
    float x_reg[16];
    const short base0 = i << 4;
    const device float4* s4 = (const device float4*)(signs + uint(base0));
    #pragma clang loop unroll(full)
    for (short w = 0; w < 4; w++) {
        const uint ag_e = uint(base0) + 4u * uint(w);
        const uint ag_row = block_idx;
        const float4 attn = *((const device float4*)(x
            + ((ag_e >> 8) * uint(attention_rows) + ag_row) * 256u + (ag_e & 255u)));
        const float4 g = *((const device float4*)(gate
            + ag_row * 8192u + (ag_e >> 8) * 512u + 256u + (ag_e & 255u)));
        const float4 e = 1.0f / (1.0f + metal::exp(metal::abs(g)));
        const float4 sigmoid_g = select(1.0f - e, e, g < 0.0f);
        float4 val = (attn * sigmoid_g) * s4[w];
        x_reg[4 * w + 0] = val.x;
        x_reg[4 * w + 1] = val.y;
        x_reg[4 * w + 2] = val.z;
        x_reg[4 * w + 3] = val.w;
    }
    hadamard_4096_q8_finish(
        i, block_idx, batch_idx, 1, verify_rows,
        x_reg, buf, codes, ascale, rsb, nullptr);
}

// ---------------------------------------------------------------------------
// 4. Prompt-Width Integer M5 Neural Accelerator Matmul (`PromptInt8Matmul`)
//    64x64 output tile per threadgroup of 4 simdgroups (128 threads).
//    Each simdgroup runs its own 32x32x128 `int8 x int8 -> int32`
//    `matmul2d<desc, execution_simdgroup>` over double-buffered threadgroup
//    2-bit unpacked weights `bs[2][64 * 128 / 4]`.
// ---------------------------------------------------------------------------

METAL_FUNC void bonsai_q8_prompt_nax_sg_body(
    int K,
    int M,
    int N,
    int bx,
    int neg,
    uint tid,
    uint lane,
    uint sg,
    uint tgid_y,
    device const int8_t* xq,
    device const uint32_t* w,
    device const half* scalesT,
    device const half* biasesT,
    device const float* ascale,
    device const float* rsb,
    device float* out,
    threadgroup uint32_t (&bs)[2][64 * 128 / 4]
) {
    const int Kg = K / 128;
    const int n0 = bx * 64;
    const int m0 = int(tgid_y) * 64;
    const int q = int(sg & 3);
    const int sm = 32 * (q >> 1), sn = 32 * (q & 1);
    const int fm = int(((lane >> 4) & 1) * 4 + ((lane >> 1) & 3));
    const int fn = int((((lane >> 3) & 1) * 2 + (lane & 1)) * 4);
    constexpr auto desc = mpp::tensor_ops::matmul2d_descriptor(
        32, 32, 128, false, true, false, mpp::tensor_ops::matmul2d_descriptor::mode::multiply);
    mpp::tensor_ops::matmul2d<desc, metal::execution_simdgroup> op;
    tensor<device int8_t, dextents<int, 2>, tensor_inline> A((device int8_t*)xq, dextents<int, 2>(K, M));
    tensor<threadgroup int8_t, dextents<int, 2>, tensor_inline> B0((threadgroup int8_t*)bs[0], dextents<int, 2>(128, 64));
    tensor<threadgroup int8_t, dextents<int, 2>, tensor_inline> B1((threadgroup int8_t*)bs[1], dextents<int, 2>(128, 64));
    auto B0s = B0.template slice<128, 32>(0, sn);
    auto B1s = B1.template slice<128, 32>(0, sn);
    auto tA0 = A.template slice<128, 32>(0, m0 + sm);
    auto cT = op.template get_destination_cooperative_tensor<
        metal::remove_addrspace_t<decltype(tA0)>,
        metal::remove_addrspace_t<decltype(B0s)>,
        int32_t>();

    const int sc = int(tid >> 1);
    const int sh = int(tid & 1);
    const device uint32_t* wrow = w + (size_t)(n0 + sc) * (K / 16) + sh * 4;
    auto stage = [&](int g, int buf) {
        const uint4 v = *(const device uint4*)(wrow + g * 8);
        threadgroup uint32_t* dst = bs[buf] + sc * 32 + sh * 16;
        #pragma clang loop unroll(full)
        for (int j = 0; j < 4; j++) {
            const uint32_t wv = v[j];
            *(threadgroup uint4*)(dst + 4 * j) = uint4(
                wv & 0x03030303u, (wv >> 2) & 0x03030303u,
                (wv >> 4) & 0x03030303u, (wv >> 6) & 0x03030303u);
        }
    };
    const int nb = n0 + sn + fn;
    const device half4* sp0 = (const device half4*)(scalesT + nb);
    const device half4* sp1 = (const device half4*)(scalesT + nb + 16);
    const device half4* bp0 = (const device half4*)(biasesT + nb);
    const device half4* bp1 = (const device half4*)(biasesT + nb + 16);
    const int NQ = N / 4;
    const size_t tbase = (size_t)(m0 / 64) * (size_t)Kg * 64 + (size_t)(4 * fm + 2 * (q >> 1));
    float acc[32];
    #pragma clang loop unroll(full)
    for (int i = 0; i < 32; i++) { acc[i] = 0.0f; }

    stage(0, 0);
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (int g = 0; g < Kg; g++) {
        if (g + 1 < Kg) { stage(g + 1, (g + 1) & 1); }
        auto tA = A.template slice<128, 32>(g * 128, m0 + sm);
        if ((g & 1) == 0) { op.run(tA, B0s, cT); } else { op.run(tA, B1s, cT); }
        const float4 s0 = float4(sp0[g * NQ]), s1 = float4(sp1[g * NQ]);
        const float4 b0 = neg ? -s0 : float4(bp0[g * NQ]);
        const float4 b1 = neg ? -s1 : float4(bp1[g * NQ]);
        const float2 a0 = *(const device float2*)(ascale + tbase + (size_t)g * 64);
        const float2 a1 = *(const device float2*)(ascale + tbase + 32 + (size_t)g * 64);
        const float2 r0 = *(const device float2*)(rsb + tbase + (size_t)g * 64);
        const float2 r1 = *(const device float2*)(rsb + tbase + 32 + (size_t)g * 64);
        float as[4], rb[4];
        as[0] = a0.x; as[1] = a0.y; as[2] = a1.x; as[3] = a1.y;
        rb[0] = r0.x; rb[1] = r0.y; rb[2] = r1.x; rb[3] = r1.y;
        #pragma clang loop unroll(full)
        for (int i = 0; i < 32; i++) {
            const int c = i & 3;
            const int nh = (i >> 3) & 1;
            const int mh = ((i >> 2) & 1) | (((i >> 4) & 1) << 1);
            const float s = nh ? s1[c] : s0[c];
            const float b = nh ? b1[c] : b0[c];
            const float t = s * float(cT[i]);
            acc[i] = fma(b, rb[mh], fma(as[mh], t, acc[i]));
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }
    const int mb = m0 + sm + fm;
    #pragma clang loop unroll(full)
    for (int i = 0; i < 32; i += 4) {
        const int mm = mb + 8 * ((i >> 2) & 1) + 16 * ((i >> 4) & 1);
        *(device float4*)(out + (size_t)mm * N + nb + 16 * ((i >> 3) & 1)) =
            float4(acc[i], acc[i + 1], acc[i + 2], acc[i + 3]);
    }
}

[[max_total_threads_per_threadgroup(128)]]
kernel void bonsai_q8_prompt_matmul_nax_sg1(
    device const int8_t*   xq      [[buffer(0)]],
    device const uint32_t* w0      [[buffer(1)]],
    device const half*     s0      [[buffer(2)]],
    device const half*     b0      [[buffer(3)]],
    device const float*    ascale  [[buffer(4)]],
    device const float*    rsb     [[buffer(5)]],
    device const int*      ksz     [[buffer(6)]],
    device float*          out0    [[buffer(7)]],
    constant int&          neg     [[buffer(8)]],
    uint                   tid     [[thread_index_in_threadgroup]],
    uint                   lane    [[thread_index_in_simdgroup]],
    uint                   sg      [[simdgroup_index_in_threadgroup]],
    uint2                  tgid    [[threadgroup_position_in_grid]]
) {
    threadgroup uint32_t bs[2][64 * 128 / 4];
    bonsai_q8_prompt_nax_sg_body(
        ksz[0], ksz[1], ksz[2], int(tgid.x), neg,
        tid, lane, sg, tgid.y, xq, w0, s0, b0, ascale, rsb, out0, bs);
}

[[max_total_threads_per_threadgroup(128)]]
kernel void bonsai_q8_prompt_matmul_nax_sg2(
    device const int8_t*   xq      [[buffer(0)]],
    device const uint32_t* w0      [[buffer(1)]],
    device const uint32_t* w1      [[buffer(2)]],
    device const half*     s0      [[buffer(3)]],
    device const half*     s1      [[buffer(4)]],
    device const half*     b0      [[buffer(5)]],
    device const half*     b1      [[buffer(6)]],
    device const float*    ascale  [[buffer(7)]],
    device const float*    rsb     [[buffer(8)]],
    device const int*      ksz     [[buffer(9)]],
    device float*          out0    [[buffer(10)]],
    device float*          out1    [[buffer(11)]],
    constant int&          neg     [[buffer(12)]],
    uint                   tid     [[thread_index_in_threadgroup]],
    uint                   lane    [[thread_index_in_simdgroup]],
    uint                   sg      [[simdgroup_index_in_threadgroup]],
    uint2                  tgid    [[threadgroup_position_in_grid]]
) {
    int bx = int(tgid.x);
    const device uint32_t* w = w0;
    const device half* scalesT = s0;
    const device half* biasesT = b0;
    device float* out = out0;
    int N = ksz[2];
    if (bx >= N / 64) {
        bx -= N / 64;
        w = w1; scalesT = s1; biasesT = b1; out = out1; N = ksz[3];
    }
    threadgroup uint32_t bs[2][64 * 128 / 4];
    bonsai_q8_prompt_nax_sg_body(
        ksz[0], ksz[1], N, bx, neg,
        tid, lane, sg, tgid.y, xq, w, scalesT, biasesT, ascale, rsb, out, bs);
}

[[max_total_threads_per_threadgroup(128)]]
kernel void bonsai_q8_prompt_matmul_nax_sg3(
    device const int8_t*   xq      [[buffer(0)]],
    device const uint32_t* w0      [[buffer(1)]],
    device const uint32_t* w1      [[buffer(2)]],
    device const uint32_t* w2      [[buffer(3)]],
    device const half*     s0      [[buffer(4)]],
    device const half*     s1      [[buffer(5)]],
    device const half*     s2      [[buffer(6)]],
    device const half*     b0      [[buffer(7)]],
    device const half*     b1      [[buffer(8)]],
    device const half*     b2      [[buffer(9)]],
    device const float*    ascale  [[buffer(10)]],
    device const float*    rsb     [[buffer(11)]],
    device const int*      ksz     [[buffer(12)]],
    device float*          out0    [[buffer(13)]],
    device float*          out1    [[buffer(14)]],
    device float*          out2    [[buffer(15)]],
    constant int&          neg     [[buffer(16)]],
    uint                   tid     [[thread_index_in_threadgroup]],
    uint                   lane    [[thread_index_in_simdgroup]],
    uint                   sg      [[simdgroup_index_in_threadgroup]],
    uint2                  tgid    [[threadgroup_position_in_grid]]
) {
    int bx = int(tgid.x);
    const device uint32_t* w = w0;
    const device half* scalesT = s0;
    const device half* biasesT = b0;
    device float* out = out0;
    int N = ksz[2];
    if (bx >= N / 64) {
        bx -= N / 64;
        w = w1; scalesT = s1; biasesT = b1; out = out1; N = ksz[3];
    }
    if (bx >= N / 64) {
        bx -= N / 64;
        w = w2; scalesT = s2; biasesT = b2; out = out2; N = ksz[4];
    }
    threadgroup uint32_t bs[2][64 * 128 / 4];
    bonsai_q8_prompt_nax_sg_body(
        ksz[0], ksz[1], N, bx, neg,
        tid, lane, sg, tgid.y, xq, w, scalesT, biasesT, ascale, rsb, out, bs);
}

// ---------------------------------------------------------------------------
// 5. Verify-Width (2..16 Rows) Integer M5 Neural Accelerator Matmul
//    (`VerifyInt8Matmul.naxFastKernels`)
//    Each threadgroup of 4 simdgroups (128 threads) computes 32 output columns
//    for all `rows` (2..16) activation rows by splitting the K-group loop 4-way
//    across the 4 simdgroups (`g = sg; g < Kg; g += 4`) using a 16x32x128
//    `matmul2d<desc, execution_simdgroup>` tensor op per simdgroup, then
//    reducing the 4 simdgroup partials in threadgroup memory.
// ---------------------------------------------------------------------------

METAL_FUNC void bonsai_q8_verify_nax_fast_body(
    int K,
    int rows,
    int N,
    int bx,
    int neg,
    uint tid,
    uint lane,
    uint sg,
    device const int8_t* xq,
    device const uint32_t* w,
    device const half* scalesT,
    device const half* biasesT,
    device const float* ascale,
    device const float* rsb,
    device float* out,
    threadgroup uint32_t (&bs)[4][32 * 32]
) {
    #pragma clang fp contract(off)
    #pragma clang fp reassociate(off)
    const int Kg = K / 128;
    const int KW = K / 16;
    const int n0 = bx * 32;
    constexpr auto desc = mpp::tensor_ops::matmul2d_descriptor(
        16, 32, 128, false, true, false, mpp::tensor_ops::matmul2d_descriptor::mode::multiply);
    mpp::tensor_ops::matmul2d<desc, metal::execution_simdgroup> op;
    tensor<device int8_t, dextents<int, 2>, tensor_inline> A((device int8_t*)xq, dextents<int, 2>(K, 16));
    tensor<threadgroup int8_t, dextents<int, 2>, tensor_inline> B((threadgroup int8_t*)bs[sg], dextents<int, 2>(128, 32));
    auto tA0 = A.template slice<128, 16>(0, 0);
    auto cT = op.template get_destination_cooperative_tensor<
        metal::remove_addrspace_t<decltype(tA0)>,
        metal::remove_addrspace_t<decltype(B)>,
        int32_t>();
    const int mrow = int((lane >> 1) & 3u) + 4 * int((lane >> 4) & 1u);
    const int nb = 4 * int(lane & 1u) + 8 * int((lane >> 3) & 1u);
    float acc[16];
    #pragma clang loop unroll(full)
    for (int e = 0; e < 16; e++) { acc[e] = 0.0f; }
    const int mr = min(mrow, rows - 1);
    const int mr1 = min(mrow + 8, rows - 1);
    const device half* scol = scalesT + n0 + nb;
    const device half* bcol = biasesT + n0 + nb;
    const int j = int(lane & 7u);
    const int c = int(lane >> 3);
    const device uint32_t* wcol = w + (size_t)(n0 + c) * KW + j;
    threadgroup uint4* dst = (threadgroup uint4*)bs[sg] + c * 8 + j;
    uint32_t wv[8];
    half4 sA, sB, bA = half4(0.0h), bB = half4(0.0h);
    float fa, frb, fa1 = 0.0f, frb1 = 0.0f;
    {
        const int gl = int(sg);
        #pragma clang loop unroll(full)
        for (int t = 0; t < 8; t++) { wv[t] = wcol[(size_t)(4 * t) * KW + gl * 8]; }
        sA = *(const device half4*)(scol + (size_t)gl * N);
        sB = *(const device half4*)(scol + (size_t)gl * N + 16);
        if (!neg) {
            bA = *(const device half4*)(bcol + (size_t)gl * N);
            bB = *(const device half4*)(bcol + (size_t)gl * N + 16);
        }
        fa = ascale[mr * Kg + gl];
        frb = rsb[mr * Kg + gl];
        if (rows > 8) { fa1 = ascale[mr1 * Kg + gl]; frb1 = rsb[mr1 * Kg + gl]; }
    }
    for (int g = int(sg); g < Kg; g += 4) {
        #pragma clang loop unroll(full)
        for (int t = 0; t < 8; t++) {
            const uint32_t v = wv[t];
            dst[32 * t] = uint4(
                v & 0x03030303u, (v >> 2) & 0x03030303u,
                (v >> 4) & 0x03030303u, (v >> 6) & 0x03030303u);
        }
        const half4 cA = sA, cB = sB;
        const half4 dA = neg ? -sA : bA, dB = neg ? -sB : bB;
        const float ca = fa, crb = frb, ca1 = fa1, crb1 = frb1;
        if (g + 4 < Kg) {
            const int gl = g + 4;
            #pragma clang loop unroll(full)
            for (int t = 0; t < 8; t++) { wv[t] = wcol[(size_t)(4 * t) * KW + gl * 8]; }
            sA = *(const device half4*)(scol + (size_t)gl * N);
            sB = *(const device half4*)(scol + (size_t)gl * N + 16);
            if (!neg) {
                bA = *(const device half4*)(bcol + (size_t)gl * N);
                bB = *(const device half4*)(bcol + (size_t)gl * N + 16);
            }
            fa = ascale[mr * Kg + gl];
            frb = rsb[mr * Kg + gl];
            if (rows > 8) { fa1 = ascale[mr1 * Kg + gl]; frb1 = rsb[mr1 * Kg + gl]; }
        }
        simdgroup_barrier(mem_flags::mem_threadgroup);
        auto tA = A.template slice<128, 16>(g * 128, 0);
        op.run(tA, B, cT);
        #pragma clang loop unroll(full)
        for (int e = 0; e < 4; e++) {
            const float t0 = float(cA[e]) * float(cT[e]);
            acc[e] = fma(float(dA[e]), crb, fma(ca, t0, acc[e]));
            const float t1 = float(cB[e]) * float(cT[8 + e]);
            acc[4 + e] = fma(float(dB[e]), crb, fma(ca, t1, acc[4 + e]));
            if (rows > 8) {
                const float t2 = float(cA[e]) * float(cT[4 + e]);
                acc[8 + e] = fma(float(dA[e]), crb1, fma(ca1, t2, acc[8 + e]));
                const float t3 = float(cB[e]) * float(cT[12 + e]);
                acc[12 + e] = fma(float(dB[e]), crb1, fma(ca1, t3, acc[12 + e]));
            }
        }
        simdgroup_barrier(mem_flags::mem_threadgroup);
    }
    threadgroup float* red = (threadgroup float*)bs[sg];
    if (mrow < rows) {
        #pragma clang loop unroll(full)
        for (int e = 0; e < 4; e++) {
            red[mrow * 32 + nb + e] = acc[e];
            red[mrow * 32 + nb + 16 + e] = acc[4 + e];
        }
    }
    if (rows > 8 && mrow + 8 < rows) {
        #pragma clang loop unroll(full)
        for (int e = 0; e < 4; e++) {
            red[(mrow + 8) * 32 + nb + e] = acc[8 + e];
            red[(mrow + 8) * 32 + nb + 16 + e] = acc[12 + e];
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    const threadgroup float4* r0 = (const threadgroup float4*)bs[0];
    const threadgroup float4* r1 = (const threadgroup float4*)bs[1];
    const threadgroup float4* r2 = (const threadgroup float4*)bs[2];
    const threadgroup float4* r3 = (const threadgroup float4*)bs[3];
    for (int e = int(tid); e < rows * 8; e += 128) {
        float4 v = r0[e] + r1[e];
        v = v + r2[e];
        v = v + r3[e];
        *(device float4*)(out + (size_t)(e >> 3) * N + n0 + 4 * (e & 7)) = v;
    }
}

[[max_total_threads_per_threadgroup(128)]]
kernel void bonsai_q8_verify_matmul_nax_fast1(
    device const int8_t*   xq      [[buffer(0)]],
    device const uint32_t* w0      [[buffer(1)]],
    device const half*     s0      [[buffer(2)]],
    device const half*     b0      [[buffer(3)]],
    device const float*    ascale  [[buffer(4)]],
    device const float*    rsb     [[buffer(5)]],
    device const int*      ksz     [[buffer(6)]],
    device float*          out0    [[buffer(7)]],
    constant int&          neg     [[buffer(8)]],
    uint                   tid     [[thread_index_in_threadgroup]],
    uint                   lane    [[thread_index_in_simdgroup]],
    uint                   sg      [[simdgroup_index_in_threadgroup]],
    uint2                  tgid    [[threadgroup_position_in_grid]]
) {
    threadgroup uint32_t bs[4][32 * 32];
    bonsai_q8_verify_nax_fast_body(
        ksz[0], ksz[1], ksz[2], int(tgid.x), neg,
        tid, lane, sg, xq, w0, s0, b0, ascale, rsb, out0, bs);
}

[[max_total_threads_per_threadgroup(128)]]
kernel void bonsai_q8_verify_matmul_nax_fast2(
    device const int8_t*   xq      [[buffer(0)]],
    device const uint32_t* w0      [[buffer(1)]],
    device const uint32_t* w1      [[buffer(2)]],
    device const half*     s0      [[buffer(3)]],
    device const half*     s1      [[buffer(4)]],
    device const half*     b0      [[buffer(5)]],
    device const half*     b1      [[buffer(6)]],
    device const float*    ascale  [[buffer(7)]],
    device const float*    rsb     [[buffer(8)]],
    device const int*      ksz     [[buffer(9)]],
    device float*          out0    [[buffer(10)]],
    device float*          out1    [[buffer(11)]],
    constant int&          neg     [[buffer(12)]],
    uint                   tid     [[thread_index_in_threadgroup]],
    uint                   lane    [[thread_index_in_simdgroup]],
    uint                   sg      [[simdgroup_index_in_threadgroup]],
    uint2                  tgid    [[threadgroup_position_in_grid]]
) {
    int bx = int(tgid.x);
    const device uint32_t* w = w0;
    const device half* scalesT = s0;
    const device half* biasesT = b0;
    device float* out = out0;
    int N = ksz[2];
    if (bx >= N / 32) {
        bx -= N / 32;
        w = w1; scalesT = s1; biasesT = b1; out = out1; N = ksz[3];
    }
    threadgroup uint32_t bs[4][32 * 32];
    bonsai_q8_verify_nax_fast_body(
        ksz[0], ksz[1], N, bx, neg,
        tid, lane, sg, xq, w, scalesT, biasesT, ascale, rsb, out, bs);
}

[[max_total_threads_per_threadgroup(128)]]
kernel void bonsai_q8_verify_matmul_nax_fast3(
    device const int8_t*   xq      [[buffer(0)]],
    device const uint32_t* w0      [[buffer(1)]],
    device const uint32_t* w1      [[buffer(2)]],
    device const uint32_t* w2      [[buffer(3)]],
    device const half*     s0      [[buffer(4)]],
    device const half*     s1      [[buffer(5)]],
    device const half*     s2      [[buffer(6)]],
    device const half*     b0      [[buffer(7)]],
    device const half*     b1      [[buffer(8)]],
    device const half*     b2      [[buffer(9)]],
    device const float*    ascale  [[buffer(10)]],
    device const float*    rsb     [[buffer(11)]],
    device const int*      ksz     [[buffer(12)]],
    device float*          out0    [[buffer(13)]],
    device float*          out1    [[buffer(14)]],
    device float*          out2    [[buffer(15)]],
    constant int&          neg     [[buffer(16)]],
    uint                   tid     [[thread_index_in_threadgroup]],
    uint                   lane    [[thread_index_in_simdgroup]],
    uint                   sg      [[simdgroup_index_in_threadgroup]],
    uint2                  tgid    [[threadgroup_position_in_grid]]
) {
    int bx = int(tgid.x);
    const device uint32_t* w = w0;
    const device half* scalesT = s0;
    const device half* biasesT = b0;
    device float* out = out0;
    int N = ksz[2];
    if (bx >= N / 32) {
        bx -= N / 32;
        w = w1; scalesT = s1; biasesT = b1; out = out1; N = ksz[3];
    }
    if (bx >= N / 32) {
        bx -= N / 32;
        w = w2; scalesT = s2; biasesT = b2; out = out2; N = ksz[4];
    }
    threadgroup uint32_t bs[4][32 * 32];
    bonsai_q8_verify_nax_fast_body(
        ksz[0], ksz[1], N, bx, neg,
        tid, lane, sg, xq, w, scalesT, biasesT, ascale, rsb, out, bs);
}

// ---------------------------------------------------------------------------
// 6. Wide-Staging Verify-Width (2..16 Rows) Integer M5 Neural Accelerator Matmul
//    (`VerifyInt8Matmul.naxFastWideKernels`, cf2933d + PR #268)
//    Replaces 8 strided 4-byte `uint32_t` weight loads per lane with two 16-byte
//    `uint4` loads (`wr = lane >> 1`, `wq = 4 * (lane & 1)` for rows `wr` and
//    `wr + 16`), rotates threadgroup stores by `rot = wr & 3` (`qq = (q + rot) & 3`)
//    to spread threadgroup memory banks, and prefetches weight `uint4` pairs two
//    K-groups ahead in registers (`wv0/wv1` + `nv0/nv1`).
// ---------------------------------------------------------------------------

METAL_FUNC void bonsai_q8_verify_nax_fast_wide_body(
    int K,
    int rows,
    int N,
    int bx,
    int neg,
    uint tid,
    uint lane,
    uint sg,
    device const int8_t* xq,
    device const uint32_t* w,
    device const half* scalesT,
    device const half* biasesT,
    device const float* ascale,
    device const float* rsb,
    device float* out,
    threadgroup uint32_t (&bs)[4][32 * 32]
) {
    #pragma clang fp contract(off)
    #pragma clang fp reassociate(off)
    const int Kg = K / 128;
    const int KW = K / 16;
    const int n0 = bx * 32;
    constexpr auto desc = mpp::tensor_ops::matmul2d_descriptor(
        16, 32, 128, false, true, false, mpp::tensor_ops::matmul2d_descriptor::mode::multiply);
    mpp::tensor_ops::matmul2d<desc, metal::execution_simdgroup> op;
    tensor<device int8_t, dextents<int, 2>, tensor_inline> A((device int8_t*)xq, dextents<int, 2>(K, 16));
    tensor<threadgroup int8_t, dextents<int, 2>, tensor_inline> B((threadgroup int8_t*)bs[sg], dextents<int, 2>(128, 32));
    auto tA0 = A.template slice<128, 16>(0, 0);
    auto cT = op.template get_destination_cooperative_tensor<
        metal::remove_addrspace_t<decltype(tA0)>,
        metal::remove_addrspace_t<decltype(B)>,
        int32_t>();
    const int mrow = int((lane >> 1) & 3u) + 4 * int((lane >> 4) & 1u);
    const int nb = 4 * int(lane & 1u) + 8 * int((lane >> 3) & 1u);
    float acc[16];
    #pragma clang loop unroll(full)
    for (int e = 0; e < 16; e++) { acc[e] = 0.0f; }
    const int mr = min(mrow, rows - 1);
    const int mr1 = min(mrow + 8, rows - 1);
    const device half* scol = scalesT + n0 + nb;
    const device half* bcol = biasesT + n0 + nb;
    const int wr = int(lane >> 1);
    const int wq = 4 * int(lane & 1u);
    const int rot = wr & 3;
    const device uint4* wcol0 = (const device uint4*)(w + (size_t)(n0 + wr) * KW + wq);
    const device uint4* wcol1 = (const device uint4*)(w + (size_t)(n0 + wr + 16) * KW + wq);
    threadgroup uint4* dst0 = (threadgroup uint4*)bs[sg] + wr * 8 + wq;
    threadgroup uint4* dst1 = (threadgroup uint4*)bs[sg] + (wr + 16) * 8 + wq;
    uint4 wv0, wv1, nv0 = uint4(0u), nv1 = uint4(0u);
    half4 sA, sB, bA = half4(0.0h), bB = half4(0.0h);
    float fa, frb, fa1 = 0.0f, frb1 = 0.0f;
    {
        const int gl = int(sg);
        wv0 = wcol0[(size_t)gl * 2]; wv1 = wcol1[(size_t)gl * 2];
        if (gl + 4 < Kg) { nv0 = wcol0[(size_t)(gl + 4) * 2]; nv1 = wcol1[(size_t)(gl + 4) * 2]; }
        sA = *(const device half4*)(scol + (size_t)gl * N);
        sB = *(const device half4*)(scol + (size_t)gl * N + 16);
        if (!neg) {
            bA = *(const device half4*)(bcol + (size_t)gl * N);
            bB = *(const device half4*)(bcol + (size_t)gl * N + 16);
        }
        fa = ascale[mr * Kg + gl];
        frb = rsb[mr * Kg + gl];
        if (rows > 8) { fa1 = ascale[mr1 * Kg + gl]; frb1 = rsb[mr1 * Kg + gl]; }
    }
    for (int g = int(sg); g < Kg; g += 4) {
        #pragma clang loop unroll(full)
        for (int q = 0; q < 4; q++) {
            const int qq = (q + rot) & 3;
            const uint32_t v0 = qq == 0 ? wv0.x : qq == 1 ? wv0.y : qq == 2 ? wv0.z : wv0.w;
            dst0[qq] = uint4(
                v0 & 0x03030303u, (v0 >> 2) & 0x03030303u,
                (v0 >> 4) & 0x03030303u, (v0 >> 6) & 0x03030303u);
            const uint32_t v1 = qq == 0 ? wv1.x : qq == 1 ? wv1.y : qq == 2 ? wv1.z : wv1.w;
            dst1[qq] = uint4(
                v1 & 0x03030303u, (v1 >> 2) & 0x03030303u,
                (v1 >> 4) & 0x03030303u, (v1 >> 6) & 0x03030303u);
        }
        const half4 cA = sA, cB = sB;
        const half4 dA = neg ? -sA : bA, dB = neg ? -sB : bB;
        const float ca = fa, crb = frb, ca1 = fa1, crb1 = frb1;
        if (g + 4 < Kg) {
            const int gl = g + 4;
            wv0 = nv0; wv1 = nv1;
            if (gl + 4 < Kg) { nv0 = wcol0[(size_t)(gl + 4) * 2]; nv1 = wcol1[(size_t)(gl + 4) * 2]; }
            sA = *(const device half4*)(scol + (size_t)gl * N);
            sB = *(const device half4*)(scol + (size_t)gl * N + 16);
            if (!neg) {
                bA = *(const device half4*)(bcol + (size_t)gl * N);
                bB = *(const device half4*)(bcol + (size_t)gl * N + 16);
            }
            fa = ascale[mr * Kg + gl];
            frb = rsb[mr * Kg + gl];
            if (rows > 8) { fa1 = ascale[mr1 * Kg + gl]; frb1 = rsb[mr1 * Kg + gl]; }
        }
        simdgroup_barrier(mem_flags::mem_threadgroup);
        auto tA = A.template slice<128, 16>(g * 128, 0);
        op.run(tA, B, cT);
        #pragma clang loop unroll(full)
        for (int e = 0; e < 4; e++) {
            const float t0 = float(cA[e]) * float(cT[e]);
            acc[e] = fma(float(dA[e]), crb, fma(ca, t0, acc[e]));
            const float t1 = float(cB[e]) * float(cT[8 + e]);
            acc[4 + e] = fma(float(dB[e]), crb, fma(ca, t1, acc[4 + e]));
            if (rows > 8) {
                const float t2 = float(cA[e]) * float(cT[4 + e]);
                acc[8 + e] = fma(float(dA[e]), crb1, fma(ca1, t2, acc[8 + e]));
                const float t3 = float(cB[e]) * float(cT[12 + e]);
                acc[12 + e] = fma(float(dB[e]), crb1, fma(ca1, t3, acc[12 + e]));
            }
        }
        simdgroup_barrier(mem_flags::mem_threadgroup);
    }
    threadgroup float* red = (threadgroup float*)bs[sg];
    if (mrow < rows) {
        #pragma clang loop unroll(full)
        for (int e = 0; e < 4; e++) {
            red[mrow * 32 + nb + e] = acc[e];
            red[mrow * 32 + nb + 16 + e] = acc[4 + e];
        }
    }
    if (rows > 8 && mrow + 8 < rows) {
        #pragma clang loop unroll(full)
        for (int e = 0; e < 4; e++) {
            red[(mrow + 8) * 32 + nb + e] = acc[8 + e];
            red[(mrow + 8) * 32 + nb + 16 + e] = acc[12 + e];
        }
    }
    threadgroup_barrier(mem_flags::mem_threadgroup);
    const threadgroup float4* r0 = (const threadgroup float4*)bs[0];
    const threadgroup float4* r1 = (const threadgroup float4*)bs[1];
    const threadgroup float4* r2 = (const threadgroup float4*)bs[2];
    const threadgroup float4* r3 = (const threadgroup float4*)bs[3];
    for (int e = int(tid); e < rows * 8; e += 128) {
        float4 v = r0[e] + r1[e];
        v = v + r2[e];
        v = v + r3[e];
        *(device float4*)(out + (size_t)(e >> 3) * N + n0 + 4 * (e & 7)) = v;
    }
}

[[max_total_threads_per_threadgroup(128)]]
kernel void bonsai_q8_verify_matmul_nax_fast_wide1(
    device const int8_t*   xq      [[buffer(0)]],
    device const uint32_t* w0      [[buffer(1)]],
    device const half*     s0      [[buffer(2)]],
    device const half*     b0      [[buffer(3)]],
    device const float*    ascale  [[buffer(4)]],
    device const float*    rsb     [[buffer(5)]],
    device const int*      ksz     [[buffer(6)]],
    device float*          out0    [[buffer(7)]],
    constant int&          neg     [[buffer(8)]],
    uint                   tid     [[thread_index_in_threadgroup]],
    uint                   lane    [[thread_index_in_simdgroup]],
    uint                   sg      [[simdgroup_index_in_threadgroup]],
    uint2                  tgid    [[threadgroup_position_in_grid]]
) {
    threadgroup uint32_t bs[4][32 * 32];
    bonsai_q8_verify_nax_fast_wide_body(
        ksz[0], ksz[1], ksz[2], int(tgid.x), neg,
        tid, lane, sg, xq, w0, s0, b0, ascale, rsb, out0, bs);
}

[[max_total_threads_per_threadgroup(128)]]
kernel void bonsai_q8_verify_matmul_nax_fast_wide2(
    device const int8_t*   xq      [[buffer(0)]],
    device const uint32_t* w0      [[buffer(1)]],
    device const uint32_t* w1      [[buffer(2)]],
    device const half*     s0      [[buffer(3)]],
    device const half*     s1      [[buffer(4)]],
    device const half*     b0      [[buffer(5)]],
    device const half*     b1      [[buffer(6)]],
    device const float*    ascale  [[buffer(7)]],
    device const float*    rsb     [[buffer(8)]],
    device const int*      ksz     [[buffer(9)]],
    device float*          out0    [[buffer(10)]],
    device float*          out1    [[buffer(11)]],
    constant int&          neg     [[buffer(12)]],
    uint                   tid     [[thread_index_in_threadgroup]],
    uint                   lane    [[thread_index_in_simdgroup]],
    uint                   sg      [[simdgroup_index_in_threadgroup]],
    uint2                  tgid    [[threadgroup_position_in_grid]]
) {
    int bx = int(tgid.x);
    const device uint32_t* w = w0;
    const device half* scalesT = s0;
    const device half* biasesT = b0;
    device float* out = out0;
    int N = ksz[2];
    if (bx >= N / 32) {
        bx -= N / 32;
        w = w1; scalesT = s1; biasesT = b1; out = out1; N = ksz[3];
    }
    threadgroup uint32_t bs[4][32 * 32];
    bonsai_q8_verify_nax_fast_wide_body(
        ksz[0], ksz[1], N, bx, neg,
        tid, lane, sg, xq, w, scalesT, biasesT, ascale, rsb, out, bs);
}

[[max_total_threads_per_threadgroup(128)]]
kernel void bonsai_q8_verify_matmul_nax_fast_wide3(
    device const int8_t*   xq      [[buffer(0)]],
    device const uint32_t* w0      [[buffer(1)]],
    device const uint32_t* w1      [[buffer(2)]],
    device const uint32_t* w2      [[buffer(3)]],
    device const half*     s0      [[buffer(4)]],
    device const half*     s1      [[buffer(5)]],
    device const half*     s2      [[buffer(6)]],
    device const half*     b0      [[buffer(7)]],
    device const half*     b1      [[buffer(8)]],
    device const half*     b2      [[buffer(9)]],
    device const float*    ascale  [[buffer(10)]],
    device const float*    rsb     [[buffer(11)]],
    device const int*      ksz     [[buffer(12)]],
    device float*          out0    [[buffer(13)]],
    device float*          out1    [[buffer(14)]],
    device float*          out2    [[buffer(15)]],
    constant int&          neg     [[buffer(16)]],
    uint                   tid     [[thread_index_in_threadgroup]],
    uint                   lane    [[thread_index_in_simdgroup]],
    uint                   sg      [[simdgroup_index_in_threadgroup]],
    uint2                  tgid    [[threadgroup_position_in_grid]]
) {
    int bx = int(tgid.x);
    const device uint32_t* w = w0;
    const device half* scalesT = s0;
    const device half* biasesT = b0;
    device float* out = out0;
    int N = ksz[2];
    if (bx >= N / 32) {
        bx -= N / 32;
        w = w1; scalesT = s1; biasesT = b1; out = out1; N = ksz[3];
    }
    if (bx >= N / 32) {
        bx -= N / 32;
        w = w2; scalesT = s2; biasesT = b2; out = out2; N = ksz[4];
    }
    threadgroup uint32_t bs[4][32 * 32];
    bonsai_q8_verify_nax_fast_wide_body(
        ksz[0], ksz[1], N, bx, neg,
        tid, lane, sg, xq, w, scalesT, biasesT, ascale, rsb, out, bs);
}

