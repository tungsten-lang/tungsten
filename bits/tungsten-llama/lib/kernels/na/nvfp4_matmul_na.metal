// NVFP4 weights x FP16 activations matmul on the M5 GPU Neural Accelerators
// (mpp::tensor_ops::matmul2d), dispatched from a CLASSIC compute encoder.
//
// The "na" kernel family takes plain device pointers and builds the tensor
// views in-shader, so it needs no MTLTensor binding, no Metal-4 argument
// table, command buffer, or residency set: it drops into the existing
// concurrent command buffers and recorded programs next to every other
// kernel, and the no-copy mmap'd weights stay on the classic driver path.
// Measured 2026-09-02: err 0, 44.4 TFLOPS on ffn_gate_up (M=1024, K=5120,
// N=17408) - identical to the Metal-4 argument-table dispatch.
//
//   y[m,n] = global_scale * sum_k A[m,k] * decode(W[n,k])   (matches nvfp4_gemm_f32)
//
// Entry points (execution_simdgroups<4>, 128 threads, static 16 KB tile):
//   nvfp4_matmul_na      M_TILE=128 N_TILE=64 K_TILE=128  - prefill chunks >= 128
//   nvfp4_matmul_na_m64  M_TILE=64  N_TILE=64 K_TILE=128  - 64-row chunks
// Dispatch ((M+M_TILE-1)/M_TILE, (N+63)/64, 1) tg x (128,1,1).
//
// REQUIREMENTS (the cooperative-tensor store does NOT clip to extents):
//   M % M_TILE == 0 (pad the activation/output scratch to the tile),
//   N % 64 == 0, K % 128 == 0. Rows/cols beyond the true extent are written.
//
// Args: 0 A (half*, [M][K]), 1 W_packed (uint*), 2 W_scales (uchar*),
//       3 C (float*, [M][N]), 4 K, 5 global_scale, 6 M, 7 N.
// Tile tuning: docs/prefill-matmul2d-tuning-2026-08-27.md (128x64x128 sg4 =
// 2.4x the 64x32x64 tile); classic-encoder form: docs/na-classic-encoder-2026-09-02.md.

#include <metal_stdlib>
#include <MetalPerformancePrimitives/MetalPerformancePrimitives.h>
using namespace metal;
using namespace mpp;
using namespace mpp::tensor_ops;

constant float NVFP4_NA_TABLE[16] = {
     0.0f,  0.5f,  1.0f,  1.5f,  2.0f,  3.0f,  4.0f,  6.0f,
    -0.0f, -0.5f, -1.0f, -1.5f, -2.0f, -3.0f, -4.0f, -6.0f,
};
static inline float nvfp4_na_e4m3_decode(uint b) {
    b = b & 0x7F; uint e = (b >> 3) & 0xF; uint m = b & 0x7;
    if (e == 0)            return float(m) * (1.0f / 512.0f);
    if (e == 15 && m == 7) return 0.0f;
    return exp2(float(int(e) - 7)) * (1.0f + float(m) * 0.125f);
}

template <int M_TILE, int N_TILE, int K_TILE, typename TA, typename TC>
static inline void nvfp4_matmul_na_impl(
    TA A,
    device const uint  *W_packed,
    device const uchar *W_scales,
    TC C,
    int K, float global_scale,
    threadgroup half *B_tile_tg,
    uint3 tgid, uint3 tid3
) {
    constexpr int THREADS = 128;
    constexpr auto desc = matmul2d_descriptor(
        M_TILE, N_TILE, K_TILE, false, true, false,
        matmul2d_descriptor::mode::multiply_accumulate);
    matmul2d<desc, execution_simdgroups<4>> op;

    auto cT = op.template get_destination_cooperative_tensor<TA, TA, float>();
    for (uint16_t i = 0; i < cT.get_capacity(); ++i) cT[i] = 0.0f;

    const int u32s_per_row   = K / 8;
    const int groups_per_row = K / 16;
    const int n_base = int(tgid.y) * N_TILE;
    const int total_spans = (N_TILE * K_TILE) / 16;
    uint tid = tid3.x;
    int n_k_chunks = K / K_TILE;

    for (int kc = 0; kc < n_k_chunks; ++kc) {
        int k_base = kc * K_TILE;
        // Dequantize the [N_TILE][K_TILE] weight tile into threadgroup memory:
        // one 16-wide NVFP4 group (2 u32 + 1 scale byte) per span.
        for (int span = int(tid); span < total_spans; span += THREADS) {
            int row = (span * 16) / K_TILE;
            int col = (span * 16) % K_TILE;
            int n = n_base + row;
            int k = k_base + col;
            int g = k / 16;
            float s = nvfp4_na_e4m3_decode(uint(W_scales[n * groups_per_row + g]));
            uint w0 = W_packed[n * u32s_per_row + g * 2];
            uint w1 = W_packed[n * u32s_per_row + g * 2 + 1];
            int base = row * K_TILE + col;
            uint bs[8] = { w0&0xFF,(w0>>8)&0xFF,(w0>>16)&0xFF,(w0>>24)&0xFF,
                           w1&0xFF,(w1>>8)&0xFF,(w1>>16)&0xFF,(w1>>24)&0xFF };
            for (int bi = 0; bi < 8; ++bi) {
                B_tile_tg[base + bi*2 + 0] = half(s * NVFP4_NA_TABLE[bs[bi] & 0xF]);
                B_tile_tg[base + bi*2 + 1] = half(s * NVFP4_NA_TABLE[bs[bi] >> 4]);
            }
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        auto B_ext = dextents<int32_t, 2>(K_TILE, N_TILE);
        array<int32_t, 2> B_str = {1, K_TILE};
        auto B_tile = tensor(B_tile_tg, B_ext, B_str);
        auto mA = A.template slice<K_TILE, M_TILE>(k_base, tgid.x * M_TILE);
        auto mB = B_tile.template slice<K_TILE, N_TILE>(0, 0);
        op.run(mA, mB, cT);
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    for (uint16_t i = 0; i < cT.get_capacity(); ++i) cT[i] *= global_scale;
    auto mC = C.template slice<N_TILE, M_TILE>(tgid.y * N_TILE, tgid.x * M_TILE);
    cT.store(mC);
}

#define DEF_NVFP4_NA(NAME, MT, NT, KT)                                          \
[[max_total_threads_per_threadgroup(128)]]                                      \
kernel void NAME(                                                               \
    device half        *A_ptr    [[buffer(0)]],                                 \
    device const uint  *W_packed [[buffer(1)]],                                 \
    device const uchar *W_scales [[buffer(2)]],                                 \
    device float       *C_ptr    [[buffer(3)]],                                 \
    constant int       &K            [[buffer(4)]],                             \
    constant float     &global_scale [[buffer(5)]],                             \
    constant int       &M            [[buffer(6)]],                             \
    constant int       &N            [[buffer(7)]],                             \
    uint3 tgid [[threadgroup_position_in_grid]],                                \
    uint3 tid3 [[thread_position_in_threadgroup]]                               \
) {                                                                             \
    threadgroup half B_tile_tg[NT * KT];                                        \
    auto A = tensor(A_ptr, dextents<int32_t, 2>(K, M), array<int32_t, 2>{1, K}); \
    auto C = tensor(C_ptr, dextents<int32_t, 2>(N, M), array<int32_t, 2>{1, N}); \
    nvfp4_matmul_na_impl<MT, NT, KT>(A, W_packed, W_scales, C, K, global_scale, \
                                     B_tile_tg, tgid, tid3);                     \
}

DEF_NVFP4_NA(nvfp4_matmul_na,     128, 64, 128)
DEF_NVFP4_NA(nvfp4_matmul_na_m64,  64, 64, 128)
