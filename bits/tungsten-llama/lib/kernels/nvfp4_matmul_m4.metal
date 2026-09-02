// NVFP4 weights × FP16 activations matmul via Metal 4 cooperative-tensor matmul2d.
// Runs on the M5 GPU Neural Accelerators (mpp::tensor_ops::matmul2d).
//
// y[m,n] = global_scale * sum_k A[m,k] * decode(W[n,k])   (matches nvfp4_gemm_f32).
//
// Entry points (all execution_simdgroups<4>, 128 threads):
//   nvfp4_matmul_m4      M_TILE=128 N_TILE=64 K_TILE=128  — long prefill (M>=128)
//   nvfp4_matmul_m4_m64  M_TILE=64  N_TILE=64 K_TILE=128  — MULTI_MAX=64 prefill
// Threadgroup memory (both): N_TILE*K_TILE*2 = 64*128*2 = 16384 bytes.
// Dispatch: ((M+M_TILE-1)/M_TILE, (N+63)/64, 1) tg × (128,1,1).
// Tile tuning: docs/prefill-matmul2d-tuning-2026-08-27.md.
//
// Args: 0 A(tensor half), 1 W_packed(uint), 2 W_scales(uchar), 3 C(tensor float),
//       4 K(int), 5 global_scale(float), tg0 B_tile.

#include <metal_stdlib>
#include <MetalPerformancePrimitives/MetalPerformancePrimitives.h>
using namespace metal;
using namespace mpp;
using namespace mpp::tensor_ops;

constant float NVFP4_TABLE[16] = {
     0.0f,  0.5f,  1.0f,  1.5f,  2.0f,  3.0f,  4.0f,  6.0f,
    -0.0f, -0.5f, -1.0f, -1.5f, -2.0f, -3.0f, -4.0f, -6.0f,
};
static inline float e4m3_decode(uint b) {
    b = b & 0x7F; uint e = (b >> 3) & 0xF; uint m = b & 0x7;
    if (e == 0)            return float(m) * (1.0f / 512.0f);
    if (e == 15 && m == 7) return 0.0f;
    return exp2(float(int(e) - 7)) * (1.0f + float(m) * 0.125f);
}

template <int M_TILE, int N_TILE, int K_TILE>
static inline void nvfp4_matmul_m4_impl(
    tensor<device half, dextents<int32_t, 2>> A,
    device const uint  *W_packed,
    device const uchar *W_scales,
    tensor<device float, dextents<int32_t, 2>> C,
    int K, float global_scale,
    threadgroup half *B_tile_tg,
    uint3 tgid, uint3 tid3
) {
    constexpr int THREADS = 128;
    constexpr auto desc = matmul2d_descriptor(
        M_TILE, N_TILE, K_TILE, false, true, false,
        matmul2d_descriptor::mode::multiply_accumulate);
    matmul2d<desc, execution_simdgroups<4>> op;

    auto cT = op.template get_destination_cooperative_tensor<decltype(A), decltype(A), float>();
    for (uint16_t i = 0; i < cT.get_capacity(); ++i) cT[i] = 0.0f;

    const int u32s_per_row   = K / 8;
    const int groups_per_row = K / 16;
    const int n_base = int(tgid.y) * N_TILE;
    const int total_spans = (N_TILE * K_TILE) / 16;
    uint tid = tid3.x;
    int n_k_chunks = K / K_TILE;

    for (int kc = 0; kc < n_k_chunks; ++kc) {
        int k_base = kc * K_TILE;
        for (int span = int(tid); span < total_spans; span += THREADS) {
            int row = (span * 16) / K_TILE;
            int col = (span * 16) % K_TILE;
            int n = n_base + row;
            int k = k_base + col;
            int g = k / 16;
            float s = e4m3_decode(uint(W_scales[n * groups_per_row + g]));
            uint w0 = W_packed[n * u32s_per_row + g * 2];
            uint w1 = W_packed[n * u32s_per_row + g * 2 + 1];
            int base = row * K_TILE + col;
            uint bs[8] = { w0&0xFF,(w0>>8)&0xFF,(w0>>16)&0xFF,(w0>>24)&0xFF,
                           w1&0xFF,(w1>>8)&0xFF,(w1>>16)&0xFF,(w1>>24)&0xFF };
            for (int bi = 0; bi < 8; ++bi) {
                B_tile_tg[base + bi*2 + 0] = half(s * NVFP4_TABLE[bs[bi] & 0xF]);
                B_tile_tg[base + bi*2 + 1] = half(s * NVFP4_TABLE[bs[bi] >> 4]);
            }
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        auto B_ext = dextents<int32_t, 2>(K_TILE, N_TILE);
        array<int32_t, 2> B_str = {1, K_TILE};
        auto B_tile = tensor(B_tile_tg, B_ext, B_str);
        auto mA = A.slice<K_TILE, M_TILE>(k_base, tgid.x * M_TILE);
        auto mB = B_tile.slice<K_TILE, N_TILE>(0, 0);
        op.run(mA, mB, cT);
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    for (uint16_t i = 0; i < cT.get_capacity(); ++i) cT[i] *= global_scale;
    auto mC = C.slice<N_TILE, M_TILE>(tgid.y * N_TILE, tgid.x * M_TILE);
    cT.store(mC);
}

#define DEF_NVFP4_MM(NAME, MT, NT, KT)                                          \
[[max_total_threads_per_threadgroup(128)]]                                      \
kernel void NAME(                                                               \
    tensor<device half, dextents<int32_t, 2>> A [[buffer(0)]],                  \
    device const uint  *W_packed [[buffer(1)]],                                 \
    device const uchar *W_scales [[buffer(2)]],                                 \
    tensor<device float, dextents<int32_t, 2>> C [[buffer(3)]],                 \
    constant int       &K            [[buffer(4)]],                             \
    constant float     &global_scale [[buffer(5)]],                             \
    threadgroup half   *B_tile_tg    [[threadgroup(0)]],                        \
    uint3 tgid [[threadgroup_position_in_grid]],                                \
    uint3 tid3 [[thread_position_in_threadgroup]]                               \
) {                                                                             \
    nvfp4_matmul_m4_impl<MT, NT, KT>(A, W_packed, W_scales, C, K, global_scale, \
                                     B_tile_tg, tgid, tid3);                     \
}

DEF_NVFP4_MM(nvfp4_matmul_m4,     128, 64, 128)
DEF_NVFP4_MM(nvfp4_matmul_m4_m64,  64, 64, 128)
