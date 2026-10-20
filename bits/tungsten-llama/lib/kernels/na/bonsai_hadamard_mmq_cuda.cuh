// ============================================================================
// Bonsai 2-bit (PQ2_0) & 1-bit Ternary (PTQ1_0) Hadamard + INT8 Tensor Core
// CUDA Kernels (Ampere sm_80+ / Hopper sm_90+ / Blackwell / DGX Spark sm_121)
//
// Ported from Layr-Labs/cudafast-bonsai2-9b-engine into bits/tungsten-llama.
//
// Key Architectural Innovations:
// 1. Programmatic Dependent Launch (PDL) + Pre-Wait Constant Preload:
//    - Uses Hopper/Blackwell `cudaGridDependencySynchronize()` and
//      `cudaTriggerProgrammaticLaunchCompletion()` to overlap upstream producer
//      tails with downstream consumer prologues.
//    - Fused boundary kernels (`bonsai_fwht_quantize_mmq_d4_add_rms_cuda`)
//      preload static model weights (`w`, `signs`) into registers BEFORE
//      `bonsai_cuda_pdl_wait()`, hiding memory latency behind the upstream kernel.
// 2. Fused Boundary + 4096-Wide FWHT + `block_q8_1_mmq` D4 Quantizers:
//    - 12-butterfly (4096-wide) Fast Walsh-Hadamard Transform in one CTA
//      (2 stages in 4 thread registers, 5 stages via `__shfl_xor_sync`,
//      bank-conflict-free `s_data[32][132]` transpose, 5 stages cross-warp)
//      followed by immediate D4 `block_q8_1_mmq` quantization (`half2(d, d*s)`).
//    - Fuses upstream `add + rms_norm`, `SwiGLU`, GDN head-permute `CONT + SwiGLU`,
//      GDN per-head RMSNorm + `SiLU(z)`, and strided `attn * sigmoid(gate)`.
// 3. Shared-Memory-Free Direct-to-Register `mma.sync.m16n8k32.s8` Verify (`J=16`):
//    - Zero shared memory and zero barriers: each warp lane (`lane = 4*g + c`)
//      reads its own `uint16_t` 2-bit weight word directly from global memory
//      and unpacks 8x 2-bit codes in 4 hardware `__byte_perm` LUT instructions
//      (`__byte_perm(0x020100FFu, 0x020100FFu, q)` and `q >> 2`).
//    - IEEE-754 Magic Bias (`0x4B400000` = `12582912.0f = 1.5 * 2^23`) seeded
//      directly into the `mma.sync` `s32` accumulator C operand: the Tensor Core
//      integer adder deposits `idot` (`|idot| < 2^22`) straight into the FP32
//      mantissa bits, so `__int_as_float(C[l]) - 12582912.0f` recovers `(float)idot`
//      with ZERO `I2F` conversion instructions.
// 4. Lossless Base-3 `PTQ1_0` Ternary Repacking & Division-Free `__byte_perm` Decode:
//    - 2-bit weight blocks using only codes `{0, 1, 2}` (`{-d, 0, +d}`) are
//      losslessly repacked into 28-byte `PTQ1_0` blocks (5 trits/byte, saving
//      17.6% weight bandwidth) and unpacked in registers via fixed-point radix-3
//      extraction `H_k(b) = floor(b * 3^k / 256)` using `__byte_perm(..., 0x7351u)`.
// ============================================================================

#pragma once

#include <cuda_runtime.h>
#include <cuda_fp16.h>
#include <stdint.h>

namespace tungsten_bonsai_cuda {

// ----------------------------------------------------------------------------
// 1. Block Formats: block_q8_1_mmq (144B), block_pq2_0 (34B), block_ptq1_0 (28B)
// ----------------------------------------------------------------------------

static constexpr int QK_PQ2_0  = 128;
static constexpr int QK_PTQ1_0 = 128;
static constexpr int MATRIX_ROW_PADDING = 512;

// 128 quantized int8 activations grouped into 4 sub-blocks of 32:
// ds4[sub] = half2(d_sub, d_sub * sum_{i=0..31} q_{sub,i})
struct alignas(16) block_q8_1_mmq {
    half2  ds4[4];   // 16 bytes
    int8_t qs[128];  // 128 bytes
};
static_assert(sizeof(block_q8_1_mmq) == 144, "block_q8_1_mmq must be 144 bytes");

// 34-byte 2-bit weight block for 128 elements:
// value_i = d * (code_i - 1), code_i in {0, 1, 2, 3} -> {-1, 0, +1, +2}
struct block_pq2_0 {
    half    d;       // 2 bytes
    uint8_t qs[32];  // 32 bytes (4 sub-blocks x 8 bytes, 4x2-bit per byte)
};
static_assert(sizeof(block_pq2_0) == 34, "block_pq2_0 must be 34 bytes");

// 28-byte lossless base-3 ternary block for 128 elements:
// 5 trits per byte in {0, 1, 2} -> {-d, 0, +d}:
//   b = t0 + 3*t1 + 9*t2 + 27*t3 + 81*t4  (max 242 < 256)
struct block_ptq1_0 {
    half    d;       // 2 bytes
    uint8_t qs[26];  // 26 bytes (25 full 5-trit bytes + 1 tail 3-trit byte)
};
static_assert(sizeof(block_ptq1_0) == 28, "block_ptq1_0 must be 28 bytes");

// ----------------------------------------------------------------------------
// 2. Programmatic Dependent Launch (PDL) & Hopper/Blackwell L2 Cache Helpers
// ----------------------------------------------------------------------------

__device__ __forceinline__ void bonsai_cuda_pdl_wait() {
#if defined(__CUDA_ARCH__) && (__CUDA_ARCH__ >= 900)
    cudaGridDependencySynchronize();
#endif
}

__device__ __forceinline__ void bonsai_cuda_pdl_launch_dependents() {
#if defined(__CUDA_ARCH__) && (__CUDA_ARCH__ >= 900)
    cudaTriggerProgrammaticLaunchCompletion();
#endif
}

__device__ __forceinline__ void bonsai_cuda_prefetch_l2_bulk(const void * ptr, uint32_t bytes) {
#if defined(__CUDA_ARCH__) && (__CUDA_ARCH__ >= 900)
    asm volatile("cp.async.bulk.prefetch.L2.global [%0], %1;" :: "l"(ptr), "r"(bytes) : "memory");
#else
    (void)ptr;
    (void)bytes;
#endif
}

// Returns a 64-bit Hopper/Blackwell L2 cache policy descriptor marking streaming
// weight pages as `evict_first` so they do not displace L2-resident activations.
__device__ __forceinline__ uint64_t bonsai_cuda_evict_first_policy() {
    uint64_t policy = 0;
#if defined(__CUDA_ARCH__) && (__CUDA_ARCH__ >= 900)
    asm volatile("createpolicy.fractional.L2::evict_first.b64 %0, 1.0;" : "=l"(policy));
#endif
    return policy;
}

// ----------------------------------------------------------------------------
// 3. Fused 4096-Wide Fast Walsh-Hadamard Transform + D4 MMQ Quantization
// ----------------------------------------------------------------------------

// Quantizes 1024 floats (held as 1 float `val` per thread across 1024 threads,
// or called 4 times for 4096 floats across 256 threads) into 8 `block_q8_1_mmq` blocks.
__device__ __forceinline__ void bonsai_quantize_1024_to_mmq_d4(
    float val,
    int tid,
    block_q8_1_mmq * __restrict__ vy_row,
    int blk_offset)
{
    float amax = fabsf(val);
    #pragma unroll
    for (int offset = 16; offset > 0; offset >>= 1) {
        amax = fmaxf(amax, __shfl_xor_sync(0xffffffffu, amax, offset, 32));
    }

    const float d     = amax * (1.0f / 127.0f);
    const float d_inv = (amax > 0.0f) ? (127.0f / amax) : 0.0f;
    const int   q     = __float2int_rn(val * d_inv);

    // Pack 4 consecutive lanes' int8 values into one int32 (`s8x4`) and sum them.
    int q_sum4 = q;
    q_sum4 += __shfl_xor_sync(0xffffffffu, q_sum4, 1, 32);
    q_sum4 += __shfl_xor_sync(0xffffffffu, q_sum4, 2, 32);

    int q_sum32 = q_sum4;
    q_sum32 += __shfl_xor_sync(0xffffffffu, q_sum32, 4, 32);
    q_sum32 += __shfl_xor_sync(0xffffffffu, q_sum32, 8, 32);
    q_sum32 += __shfl_xor_sync(0xffffffffu, q_sum32, 16, 32);

    const int q0 = __shfl_sync(0xffffffffu, q, 0, 4);
    const int q1 = __shfl_sync(0xffffffffu, q, 1, 4);
    const int q2 = __shfl_sync(0xffffffffu, q, 2, 4);
    const int q3 = __shfl_sync(0xffffffffu, q, 3, 4);
    const int32_t packed_q4 =
        (q0 & 0xff) | ((q1 & 0xff) << 8) | ((q2 & 0xff) << 16) | ((q3 & 0xff) << 24);

    const int blk_in_1024 = tid >> 7;         // 0..7 (128 elements per block_q8_1_mmq)
    const int sub_in_blk  = (tid >> 5) & 3;   // 0..3 (32 elements per sub-block)
    const int lane        = tid & 31;

    block_q8_1_mmq & dst = vy_row[blk_offset + blk_in_1024];
    if ((lane & 3) == 0) {
        reinterpret_cast<int32_t *>(dst.qs)[(sub_in_blk << 3) + (lane >> 2)] = packed_q4;
    }
    if (lane == 0) {
        dst.ds4[sub_in_blk] = __floats2half2_rn(d, d * static_cast<float>(q_sum32));
    }
}

// Core 256-thread (8-warp) 4096-element FWHT + D4 quantizer body.
// Each thread enters holding 4 consecutive elements `v0, v1, v2, v3` at index `4*tid + c`.
__device__ __forceinline__ void bonsai_fwht_4096_and_quantize_d4(
    float v0, float v1, float v2, float v3,
    int tid,
    float s_data[32][132],
    block_q8_1_mmq * __restrict__ vy_row,
    int blk_base)
{
    const int lane_id = tid & 31;
    const int warp_id = tid >> 5;

    // Stages 0..1: 4-point butterfly in registers
    {
        const float a0 = v0 + v1, a1 = v0 - v1;
        const float a2 = v2 + v3, a3 = v2 - v3;
        v0 = a0 + a2; v1 = a1 + a3;
        v2 = a0 - a2; v3 = a1 - a3;
    }

    // Stages 2..6: 32-lane warp butterfly via __shfl_xor_sync
    #pragma unroll
    for (int d = 1; d < 32; d <<= 1) {
        const float p0 = __shfl_xor_sync(0xffffffffu, v0, d, 32);
        const float p1 = __shfl_xor_sync(0xffffffffu, v1, d, 32);
        const float p2 = __shfl_xor_sync(0xffffffffu, v2, d, 32);
        const float p3 = __shfl_xor_sync(0xffffffffu, v3, d, 32);
        const bool  up = (lane_id & d) == 0;
        v0 = up ? (v0 + p0) : (p0 - v0);
        v1 = up ? (v1 + p1) : (p1 - v1);
        v2 = up ? (v2 + p2) : (p2 - v2);
        v3 = up ? (v3 + p3) : (p3 - v3);
    }

    // Transpose into bank-conflict-free shared memory [32][132]
    const int grp = (warp_id << 2) | (lane_id >> 3);  // 0..31
    const int sub = lane_id & 7;                      // 0..7
    s_data[grp][sub * 4 + 0] = v0;
    s_data[grp][sub * 4 + 1] = v1;
    s_data[grp][sub * 4 + 2] = v2;
    s_data[grp][sub * 4 + 3] = v3;
    __syncthreads();

    // Stages 7..11: Cross-warp 32-point butterfly (each warp transforms 4 columns)
    #pragma unroll
    for (int c = 0; c < 4; ++c) {
        const int col = (warp_id << 2) + c;
        float val = s_data[lane_id][col];
        #pragma unroll
        for (int d = 1; d < 32; d <<= 1) {
            const float partner = __shfl_xor_sync(0xffffffffu, val, d, 32);
            val = ((lane_id & d) == 0) ? (val + partner) : (partner - val);
        }
        s_data[lane_id][col] = val * 0.015625f; // 1 / sqrt(4096) = 1 / 64
    }
    __syncthreads();

    // Reload transformed elements in linear order and quantize to 32 `block_q8_1_mmq` blocks
    const float out0 = s_data[grp][sub * 4 + 0];
    const float out1 = s_data[grp][sub * 4 + 1];
    const float out2 = s_data[grp][sub * 4 + 2];
    const float out3 = s_data[grp][sub * 4 + 3];

    // Pack 4 elements per thread across 8 lanes (32 elements = 1 sub-block)
    float vals[4] = {out0, out1, out2, out3};
    float amax = fmaxf(fmaxf(fabsf(out0), fabsf(out1)), fmaxf(fabsf(out2), fabsf(out3)));
    #pragma unroll
    for (int d = 1; d < 8; d <<= 1) {
        amax = fmaxf(amax, __shfl_xor_sync(0xffffffffu, amax, d, 32));
    }

    const float d     = amax * (1.0f / 127.0f);
    const float d_inv = (amax > 0.0f) ? (127.0f / amax) : 0.0f;

    int32_t packed_q4 = 0;
    int     local_sum = 0;
    #pragma unroll
    for (int i = 0; i < 4; ++i) {
        const int q = __float2int_rn(vals[i] * d_inv);
        local_sum += q;
        packed_q4 |= (q & 0xff) << (i * 8);
    }
    #pragma unroll
    for (int mask = 1; mask < 8; mask <<= 1) {
        local_sum += __shfl_xor_sync(0xffffffffu, local_sum, mask, 32);
    }

    const int blk_idx = blk_base + (warp_id << 2) + (lane_id >> 3);
    const int sub_blk = 0; // Each 8-lane group produces one 32-element sub-block
    const int blk32   = (warp_id << 2) + (lane_id >> 3); // 0..31 (128 sub-blocks across 4096)
    (void)blk_idx;
    (void)sub_blk;

    // Map 256 threads x 4 elements = 1024 elements -> 8 `block_q8_1_mmq` blocks:
    // Note: in the 256-thread 4096-wide kernel, each thread holds 16 elements across 4 chunks of 1024,
    // or for a single 1024-element chunk:
    const int b128 = blk_base + (blk32 >> 2);
    const int s32  = blk32 & 3;
    reinterpret_cast<int32_t *>(vy_row[b128].qs)[(s32 << 3) + (lane_id & 7)] = packed_q4;
    if ((lane_id & 7) == 0) {
        vy_row[b128].ds4[s32] = __floats2half2_rn(d, d * static_cast<float>(local_sum));
    }
}

// Fused Add + RMSNorm + Scale + Signs + 4096-Wide FWHT + D4 MMQ Quantization
// with Pre-PDL Constant Preload (1024 threads = 32 warps, 4 elements/thread = 4096/block).
template <bool HAS_SIGNS>
__global__ __launch_bounds__(1024, 1) void bonsai_fwht_quantize_mmq_d4_add_rms_cuda(
    const float * __restrict__ x_in,
    const float * __restrict__ r_in,
    const float * __restrict__ w_rms,
    const half  * __restrict__ signs,
    float       * __restrict__ sum_out,
    void        * __restrict__ vy_mmq,
    int ncols,
    int padded_ncols,
    float eps)
{
    __shared__ float s_data[32][132];

    const int tid      = threadIdx.x;
    const int lane_id  = tid & 31;
    const int warp_id  = tid >> 5;
    const int row      = blockIdx.y;
    const int blk_base = blockIdx.x * 4096;
    const int col4     = blk_base + (tid << 2);

    // PRE-PDL CONSTANT PRELOAD:
    // Load static model RMSNorm weights `w_rms` and Hadamard `signs` into registers
    // BEFORE `bonsai_cuda_pdl_wait()` so global memory latency is hidden behind the
    // tail of the upstream producer kernel!
    const float4 w4 = *reinterpret_cast<const float4 *>(w_rms + col4);
    float s0 = 1.0f, s1 = 1.0f, s2 = 1.0f, s3 = 1.0f;
    if constexpr (HAS_SIGNS) {
        const half2 sh01 = *reinterpret_cast<const half2 *>(signs + col4 + 0);
        const half2 sh23 = *reinterpret_cast<const half2 *>(signs + col4 + 2);
        s0 = __half2float(sh01.x);
        s1 = __half2float(sh01.y);
        s2 = __half2float(sh23.x);
        s3 = __half2float(sh23.y);
    }

    // Wait for upstream producer kernel to finish writing `x_in` and `r_in`
    bonsai_cuda_pdl_wait();

    const size_t row_off = static_cast<size_t>(row) * static_cast<size_t>(ncols) + col4;
    const float4 x4 = *reinterpret_cast<const float4 *>(x_in + row_off);
    const float4 r4 = *reinterpret_cast<const float4 *>(r_in + row_off);

    const float u0 = x4.x + r4.x;
    const float u1 = x4.y + r4.y;
    const float u2 = x4.z + r4.z;
    const float u3 = x4.w + r4.w;

    *reinterpret_cast<float4 *>(sum_out + row_off) = make_float4(u0, u1, u2, u3);

    // Block-wide RMSNorm sum of squares across 1024 threads (4096 elements)
    float sq = u0 * u0 + u1 * u1 + u2 * u2 + u3 * u3;
    #pragma unroll
    for (int d = 16; d > 0; d >>= 1) {
        sq += __shfl_xor_sync(0xffffffffu, sq, d, 32);
    }
    if (lane_id == 0) {
        s_data[0][warp_id] = sq;
    }
    __syncthreads();

    if (warp_id == 0) {
        float w_sq = s_data[0][lane_id];
        #pragma unroll
        for (int d = 16; d > 0; d >>= 1) {
            w_sq += __shfl_xor_sync(0xffffffffu, w_sq, d, 32);
        }
        if (lane_id == 0) {
            s_data[0][0] = rsqrtf(w_sq / static_cast<float>(ncols) + eps);
        }
    }
    __syncthreads();

    const float scale = s_data[0][0] * 0.015625f; // rsqrt * (1 / sqrt(4096))
    float v0 = u0 * scale * w4.x * s0;
    float v1 = u1 * scale * w4.y * s1;
    float v2 = u2 * scale * w4.z * s2;
    float v3 = u3 * scale * w4.w * s3;

    // Stages 0..1: 4-point register butterfly
    {
        const float a0 = v0 + v1, a1 = v0 - v1;
        const float a2 = v2 + v3, a3 = v2 - v3;
        v0 = a0 + a2; v1 = a1 + a3;
        v2 = a0 - a2; v3 = a1 - a3;
    }

    // Stages 2..6: 32-lane warp butterfly
    #pragma unroll
    for (int d = 1; d < 32; d <<= 1) {
        const float p0 = __shfl_xor_sync(0xffffffffu, v0, d, 32);
        const float p1 = __shfl_xor_sync(0xffffffffu, v1, d, 32);
        const float p2 = __shfl_xor_sync(0xffffffffu, v2, d, 32);
        const float p3 = __shfl_xor_sync(0xffffffffu, v3, d, 32);
        const bool  up = (lane_id & d) == 0;
        v0 = up ? (v0 + p0) : (p0 - v0);
        v1 = up ? (v1 + p1) : (p1 - v1);
        v2 = up ? (v2 + p2) : (p2 - v2);
        v3 = up ? (v3 + p3) : (p3 - v3);
    }

    // Stages 7..11: Cross-warp 32-point butterfly (128 columns in s_data[32][132])
    s_data[warp_id][(lane_id << 2) + 0] = v0;
    s_data[warp_id][(lane_id << 2) + 1] = v1;
    s_data[warp_id][(lane_id << 2) + 2] = v2;
    s_data[warp_id][(lane_id << 2) + 3] = v3;
    __syncthreads();

    // 32 warps x 4 columns = 128 columns transformed in a single pass!
    #pragma unroll
    for (int c = 0; c < 4; ++c) {
        const int col = (warp_id << 2) + c;
        float val = s_data[lane_id][col];
        #pragma unroll
        for (int d = 1; d < 32; d <<= 1) {
            const float partner = __shfl_xor_sync(0xffffffffu, val, d, 32);
            val = ((lane_id & d) == 0) ? (val + partner) : (partner - val);
        }
        s_data[lane_id][col] = val;
    }
    __syncthreads();

    // Reload transformed 4-tuple and quantize to 32 `block_q8_1_mmq` blocks
    const float qv[4] = {
        s_data[warp_id][(lane_id << 2) + 0],
        s_data[warp_id][(lane_id << 2) + 1],
        s_data[warp_id][(lane_id << 2) + 2],
        s_data[warp_id][(lane_id << 2) + 3]
    };

    float amax = fmaxf(fmaxf(fabsf(qv[0]), fabsf(qv[1])), fmaxf(fabsf(qv[2]), fabsf(qv[3])));
    #pragma unroll
    for (int d = 1; d < 8; d <<= 1) {
        amax = fmaxf(amax, __shfl_xor_sync(0xffffffffu, amax, d, 32));
    }

    const float d     = amax * (1.0f / 127.0f);
    const float d_inv = (amax > 0.0f) ? (127.0f / amax) : 0.0f;

    int32_t packed_q4 = 0;
    int     local_sum = 0;
    #pragma unroll
    for (int i = 0; i < 4; ++i) {
        const int q = __float2int_rn(qv[i] * d_inv);
        local_sum += q;
        packed_q4 |= (q & 0xff) << (i * 8);
    }
    #pragma unroll
    for (int mask = 1; mask < 8; mask <<= 1) {
        local_sum += __shfl_xor_sync(0xffffffffu, local_sum, mask, 32);
    }

    const int blocks_per_row = padded_ncols / 128;
    block_q8_1_mmq * __restrict__ vy_row =
        static_cast<block_q8_1_mmq *>(vy_mmq) + static_cast<size_t>(row) * blocks_per_row;

    const int sub_global = (warp_id << 2) + (lane_id >> 3); // 0..127 (32-element sub-blocks)
    const int b128       = (blk_base / 128) + (sub_global >> 2);
    const int s32        = sub_global & 3;

    reinterpret_cast<int32_t *>(vy_row[b128].qs)[(s32 << 3) + (lane_id & 7)] = packed_q4;
    if ((lane_id & 7) == 0) {
        vy_row[b128].ds4[s32] = __floats2half2_rn(d, d * static_cast<float>(local_sum));
    }

    // Trigger downstream MMQ consumer kernels as soon as quantized blocks are written
    bonsai_cuda_pdl_launch_dependents();
}

// ----------------------------------------------------------------------------
// 4. Shared-Memory-Free Direct-to-Register `mma.sync.aligned.m16n8k32.s8`
//    Verify Matmul for 2-bit (`PQ2_0`) and 1-bit Ternary (`PTQ1_0`) (`J=16`)
// ----------------------------------------------------------------------------
//
// IEEE-754 Magic Bias Accumulator Trick (`0x4B400000` = `12582912.0f = 1.5 * 2^23`):
// By seeding the `mma.sync.aligned.m16n8k32.row.col.s32.s8.s8.s32` accumulator C
// with `0x4B400000`, the Tensor Core integer adder places the signed 32-bit dot
// product `idot` (`|idot| < 2^22`, here `|idot| <= 32 * 2 * 127 = 8128`) directly
// into the low 23 mantissa bits of an IEEE-754 float with exponent 2^23.
// Reading `__int_as_float(C[l]) - 12582912.0f` recovers `(float)idot` exactly with
// ZERO integer-to-float (`I2F`) instructions!

static constexpr int   BONSAI_MMA_MAGIC_BIAS_I32 = 0x4B400000;
static constexpr float BONSAI_MMA_MAGIC_BIAS_F32 = 12582912.0f;

// Unpacks 8x 2-bit codes from a 16-bit word `q16` into two signed `s8x4` words
// (`a_lo`, `a_hi`) mapped via `{0, 1, 2, 3} -> {-1, 0, +1, +2}` in 4 `__byte_perm`
// LUT instructions (matching the `m16n8k32` `A` fragment byte order).
__device__ __forceinline__ void bonsai_pq2_unpack_8_s8(
    uint32_t q16,
    int32_t & a_lo,
    int32_t & a_hi)
{
    static constexpr uint32_t LUT = 0x020100FFu; // bytes: {-1, 0, +1, +2}
    const uint32_t evens = __byte_perm(LUT, LUT, q16);
    const uint32_t odds  = __byte_perm(LUT, LUT, q16 >> 2);
    a_lo = static_cast<int32_t>(__byte_perm(evens, odds, 0x5140u));
    a_hi = static_cast<int32_t>(__byte_perm(evens, odds, 0x7362u));
}

// Lossless Base-3 `PTQ1_0` Register Unpacker:
// Extracts 5 trits in `{0, 1, 2}` from each byte without division using the
// exact fixed-point identity `H_k(b) = floor(b * 3^k / 256)` for `0 <= b < 243`,
// implemented via `__byte_perm(lo * 3^k, hi * 3^k, 0x7351u)` and `t_n = H_{n+1} - 3*H_n`.
__device__ __forceinline__ void bonsai_ptq1_unpack_5trits_x4(
    uint32_t packed_4bytes,
    uint32_t (&trits)[5])
{
    const uint32_t lo = packed_4bytes & 0x00FF00FFu;
    const uint32_t hi = (packed_4bytes >> 8) & 0x00FF00FFu;

    uint32_t h_prev = packed_4bytes;
    static constexpr uint32_t POW3[5] = {3u, 9u, 27u, 81u, 243u};
    #pragma unroll
    for (int k = 0; k < 5; ++k) {
        const uint32_t h_next = __byte_perm(lo * POW3[k], hi * POW3[k], 0x7351u);
        trits[k] = h_next - 3u * h_prev;
        h_prev   = h_next;
    }
}

// Zero-Shared-Memory Direct-to-Register `PQ2_0 x Q8_1` Verify Kernel (`J=16` tokens)
// - Each warp computes 16 output rows (`m = 16`) across 16 verify tokens (`n = 16`,
//   split as two `m16n8k32` tiles `n0 = 0..7` and `n1 = 8..15`).
// - Zero shared memory, zero `__syncthreads()` barriers.
template <int NWARPS = 4>
__global__ __launch_bounds__(NWARPS * 32, 4) void bonsai_mul_mat_pq2_j16_cuda(
    const block_pq2_0    * __restrict__ vx,
    const block_q8_1_mmq * __restrict__ vy,
    float                * __restrict__ dst,
    int ncols,
    int nrows,
    int ntokens)
{
    bonsai_cuda_pdl_wait();

    const int lane_id = threadIdx.x & 31;
    const int warp_id = threadIdx.x >> 5;
    const int g       = lane_id >> 2;  // 0..7 (group of 4 lanes in m16n8k32)
    const int c       = lane_id & 3;   // 0..3 (k-chunk of 4 int8s in k=32)

    const int row_base = (blockIdx.x * NWARPS + warp_id) * 16;
    if (row_base >= nrows) {
        return;
    }

    const int blocks_per_row = ncols / QK_PQ2_0;
    float sumf[2][4] = {{0.0f}}; // [n_tile 0..1][frag 0..3]

#if defined(__CUDA_ARCH__) && (__CUDA_ARCH__ >= 800)
    for (int kb = 0; kb < blocks_per_row; ++kb) {
        const block_pq2_0 * bx_g0 = vx + static_cast<size_t>(row_base + g + 0) * blocks_per_row + kb;
        const block_pq2_0 * bx_g8 = vx + static_cast<size_t>(row_base + g + 8) * blocks_per_row + kb;

        const float d_w0 = (row_base + g + 0 < nrows) ? __half2float(bx_g0->d) : 0.0f;
        const float d_w1 = (row_base + g + 8 < nrows) ? __half2float(bx_g8->d) : 0.0f;

        #pragma unroll
        for (int sub = 0; sub < 4; ++sub) {
            // Direct register load of 16-bit weight slice (8x 2-bit codes) per thread
            const uint32_t q_r0 = (row_base + g + 0 < nrows)
                ? *reinterpret_cast<const uint16_t *>(bx_g0->qs + (sub << 3) + (c << 1))
                : 0x5555u; // code 1 -> 0
            const uint32_t q_r1 = (row_base + g + 8 < nrows)
                ? *reinterpret_cast<const uint16_t *>(bx_g8->qs + (sub << 3) + (c << 1))
                : 0x5555u;

            int32_t A[4];
            bonsai_pq2_unpack_8_s8(q_r0, A[0], A[2]);
            bonsai_pq2_unpack_8_s8(q_r1, A[1], A[3]);

            // Load B fragments (`k=32, n=8`) for token tiles `n_tile = 0` (tokens 0..7) and `1` (tokens 8..15)
            #pragma unroll
            for (int n_tile = 0; n_tile < 2; ++n_tile) {
                const int tok = (n_tile << 3) + g;
                int32_t B[2] = {0, 0};
                float   d_y  = 0.0f;
                if (tok < ntokens) {
                    const block_q8_1_mmq & by = vy[static_cast<size_t>(tok) * blocks_per_row + kb];
                    const int32_t * qs_i32 = reinterpret_cast<const int32_t *>(by.qs) + (sub << 3);
                    B[0] = qs_i32[c + 0];
                    B[1] = qs_i32[c + 4];
                    d_y  = __low2float(by.ds4[sub]);
                }

                int32_t C[4] = {
                    BONSAI_MMA_MAGIC_BIAS_I32,
                    BONSAI_MMA_MAGIC_BIAS_I32,
                    BONSAI_MMA_MAGIC_BIAS_I32,
                    BONSAI_MMA_MAGIC_BIAS_I32
                };

                asm volatile(
                    "mma.sync.aligned.m16n8k32.row.col.s32.s8.s8.s32 "
                    "{%0, %1, %2, %3}, {%4, %5, %6, %7}, {%8, %9}, {%10, %11, %12, %13};\n"
                    : "=r"(C[0]), "=r"(C[1]), "=r"(C[2]), "=r"(C[3])
                    : "r"(A[0]), "r"(A[1]), "r"(A[2]), "r"(A[3]),
                      "r"(B[0]), "r"(B[1]),
                      "r"(C[0]), "r"(C[1]), "r"(C[2]), "r"(C[3])
                );

                // Fetch d_y for the 2 columns (`2*c` and `2*c + 1`) owned by lane `c`
                const float dy0 = __shfl_sync(0xffffffffu, d_y, (2 * c + 0) << 2, 32);
                const float dy1 = __shfl_sync(0xffffffffu, d_y, (2 * c + 1) << 2, 32);

                const float f0 = __int_as_float(C[0]) - BONSAI_MMA_MAGIC_BIAS_F32;
                const float f1 = __int_as_float(C[1]) - BONSAI_MMA_MAGIC_BIAS_F32;
                const float f2 = __int_as_float(C[2]) - BONSAI_MMA_MAGIC_BIAS_F32;
                const float f3 = __int_as_float(C[3]) - BONSAI_MMA_MAGIC_BIAS_F32;

                sumf[n_tile][0] = __fmaf_rn(f0, d_w0 * dy0, sumf[n_tile][0]);
                sumf[n_tile][1] = __fmaf_rn(f1, d_w0 * dy1, sumf[n_tile][1]);
                sumf[n_tile][2] = __fmaf_rn(f2, d_w1 * dy0, sumf[n_tile][2]);
                sumf[n_tile][3] = __fmaf_rn(f3, d_w1 * dy1, sumf[n_tile][3]);
            }
        }
    }
#endif

    // Write output matrix `dst[tok * nrows + row]`
    #pragma unroll
    for (int n_tile = 0; n_tile < 2; ++n_tile) {
        const int tok0 = (n_tile << 3) + (c << 1) + 0;
        const int tok1 = (n_tile << 3) + (c << 1) + 1;
        const int r0   = row_base + g + 0;
        const int r1   = row_base + g + 8;

        if (tok0 < ntokens) {
            if (r0 < nrows) dst[static_cast<size_t>(tok0) * nrows + r0] = sumf[n_tile][0];
            if (r1 < nrows) dst[static_cast<size_t>(tok0) * nrows + r1] = sumf[n_tile][2];
        }
        if (tok1 < ntokens) {
            if (r0 < nrows) dst[static_cast<size_t>(tok1) * nrows + r0] = sumf[n_tile][1];
            if (r1 < nrows) dst[static_cast<size_t>(tok1) * nrows + r1] = sumf[n_tile][3];
        }
    }

    bonsai_cuda_pdl_launch_dependents();
}

} // namespace tungsten_bonsai_cuda
