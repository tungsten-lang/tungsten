// NVFP4 weights × FP16 activations matmul via Metal 4 cooperative-tensor matmul2d.
//
// Strategy: K-chunk tiled. Per outer K-chunk:
//   1. 128 threads of the threadgroup cooperatively dequantize a
//      32 (N) × 64 (K) tile of B from packed nibbles + E4M3 scales
//      into half values in TG memory.
//   2. matmul2d.run() in multiply_accumulate mode adds the K-chunk's
//      contribution to a cooperative_tensor accumulator that survives
//      across iterations.
// After all K-chunks are processed, the accumulator is stored to C.
//
// Project layout convention (matches the rest of nvfp4_*.metal):
//   W_packed: uint32[N * K/8]   — 8 nibbles per u32, low-nibble-first per byte
//   W_scales: uchar[N * K/16]   — one E4M3 fp8 scale per group of 16 weights
//   A:        half[M * K]       — row-major activations (M × K)
//   C:        float[M * N]      — row-major output (M × N), accumulated
//
// Apple tensor convention (innermost dim first). For row-major (M, K) data:
//   A's tensor extents are (K, M); strides (1, K).
//
// Tile: M_tile=64, N_tile=32, K_tile=64. Threadgroup: 128 threads (4 SIMDs).
// Dispatch: ((M+63)/64, (N+31)/32, 1) threadgroups × (128, 1, 1) threads.
// Pipeline must be built via metal4_pipeline (requiredThreadsPerThreadgroup=128).

#include <metal_stdlib>
#include <MetalPerformancePrimitives/MetalPerformancePrimitives.h>
using namespace metal;
using namespace mpp;
using namespace mpp::tensor_ops;

constant float NVFP4_TABLE[16] = {
     0.0f,  0.5f,  1.0f,  1.5f,
     2.0f,  3.0f,  4.0f,  6.0f,
    -0.0f, -0.5f, -1.0f, -1.5f,
    -2.0f, -3.0f, -4.0f, -6.0f,
};

static inline float e4m3_decode(uint b) {
    b = b & 0x7F;
    uint e = (b >> 3) & 0xF;
    uint m = b & 0x7;
    if (e == 0)               return float(m) * (1.0f / 512.0f);
    if (e == 15 && m == 7)    return 0.0f;
    float mantissa = 1.0f + float(m) * 0.125f;
    return exp2(float(int(e) - 7)) * mantissa;
}

[[max_total_threads_per_threadgroup(128)]]
kernel void nvfp4_matmul_m4(
    tensor<device half, dextents<int32_t, 2>> A [[buffer(0)]],   // extents (K, M)
    device const uint  *W_packed [[buffer(1)]],
    device const uchar *W_scales [[buffer(2)]],
    tensor<device float, dextents<int32_t, 2>> C [[buffer(3)]],  // extents (N, M)
    constant int       &K        [[buffer(4)]],
    threadgroup half   *B_tile_tg [[threadgroup(0)]],            // 32 rows × 64 cols half = 4096 B
    uint3 tgid [[threadgroup_position_in_grid]],
    uint3 tid3 [[thread_position_in_threadgroup]]
) {
    constexpr int M_TILE = 64;
    constexpr int N_TILE = 32;
    constexpr int K_TILE = 64;

    constexpr auto desc = matmul2d_descriptor(
        M_TILE, N_TILE, K_TILE,
        false, true, false,
        matmul2d_descriptor::mode::multiply_accumulate
    );
    matmul2d<desc, execution_simdgroups<4>> op;

    // Cooperative-tensor accumulator (zero-initialized, persists across K-chunks).
    auto cT = op.get_destination_cooperative_tensor<
                  decltype(A), decltype(A), float>();
    for (uint16_t i = 0; i < cT.get_capacity(); ++i) {
        cT[i] = 0.0f;
    }

    // u32s per row of W_packed (= K nibbles / 8 nibbles per u32).
    const int u32s_per_row = K / 8;
    const int groups_per_row = K / 16;             // scale groups per row

    // Per-N-tile: 32 rows of B starting at tgid.y * 32.
    const int n_base = int(tgid.y) * N_TILE;

    // Outer K-chunk loop.
    uint tid = tid3.x;
    int n_k_chunks = K / K_TILE;
    for (int kc = 0; kc < n_k_chunks; ++kc) {
        int k_base = kc * K_TILE;

        // 128 threads cooperatively fill the 32 × 64 = 2048-element B_tile_tg.
        // Each thread handles 16 elements (2048 / 128). Layout: row-major, 64
        // cols per row. Each "row" is one of the 32 N-rows in this tile;
        // each "col" is k_base + col_idx in K.
        //
        // Threading: tid 0..127.
        //   row = (tid * 16) / 64     // 0..31
        //   col_start = (tid * 16) % 64
        // This gives each thread a contiguous 16-element span within one row.
        for (int chunk = 0; chunk < 16; chunk += 16) {
            // (kept loop structure for future per-thread tuning)
            int linear_start = int(tid) * 16 + chunk;
            if (linear_start >= 32 * 64) break;
            int row = linear_start / 64;
            int col = linear_start % 64;
            int n   = n_base + row;
            int k   = k_base + col;

            // For this 16-element span (col..col+15), all elements are in the
            // same scale-group (group_size=16 aligned with col since col % 16 == 0).
            int g = k / 16;            // group index within the row
            uchar scale_byte = W_scales[n * groups_per_row + g];
            float s = e4m3_decode(uint(scale_byte));

            // Load 2 u32s (= 16 nibbles).
            uint w0 = W_packed[n * u32s_per_row + g * 2];
            uint w1 = W_packed[n * u32s_per_row + g * 2 + 1];

            // Decode 16 nibbles, scale, store to TG memory.
            uint b00 = w0 & 0xFF, b01 = (w0 >> 8) & 0xFF, b02 = (w0 >> 16) & 0xFF, b03 = (w0 >> 24) & 0xFF;
            uint b10 = w1 & 0xFF, b11 = (w1 >> 8) & 0xFF, b12 = (w1 >> 16) & 0xFF, b13 = (w1 >> 24) & 0xFF;

            B_tile_tg[row * 64 + col +  0] = half(s * NVFP4_TABLE[b00 & 0xF]);
            B_tile_tg[row * 64 + col +  1] = half(s * NVFP4_TABLE[b00 >> 4]);
            B_tile_tg[row * 64 + col +  2] = half(s * NVFP4_TABLE[b01 & 0xF]);
            B_tile_tg[row * 64 + col +  3] = half(s * NVFP4_TABLE[b01 >> 4]);
            B_tile_tg[row * 64 + col +  4] = half(s * NVFP4_TABLE[b02 & 0xF]);
            B_tile_tg[row * 64 + col +  5] = half(s * NVFP4_TABLE[b02 >> 4]);
            B_tile_tg[row * 64 + col +  6] = half(s * NVFP4_TABLE[b03 & 0xF]);
            B_tile_tg[row * 64 + col +  7] = half(s * NVFP4_TABLE[b03 >> 4]);
            B_tile_tg[row * 64 + col +  8] = half(s * NVFP4_TABLE[b10 & 0xF]);
            B_tile_tg[row * 64 + col +  9] = half(s * NVFP4_TABLE[b10 >> 4]);
            B_tile_tg[row * 64 + col + 10] = half(s * NVFP4_TABLE[b11 & 0xF]);
            B_tile_tg[row * 64 + col + 11] = half(s * NVFP4_TABLE[b11 >> 4]);
            B_tile_tg[row * 64 + col + 12] = half(s * NVFP4_TABLE[b12 & 0xF]);
            B_tile_tg[row * 64 + col + 13] = half(s * NVFP4_TABLE[b12 >> 4]);
            B_tile_tg[row * 64 + col + 14] = half(s * NVFP4_TABLE[b13 & 0xF]);
            B_tile_tg[row * 64 + col + 15] = half(s * NVFP4_TABLE[b13 >> 4]);
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);

        // Wrap B_tile_tg as a tensor_inline (32 rows × K_TILE cols). Apple
        // convention: extents (innermost=K_TILE, outermost=32), strides (1, 64).
        auto B_ext = dextents<int32_t, 2>(K_TILE, N_TILE);
        array<int32_t, 2> B_str = {1, K_TILE};
        auto B_tile = tensor(B_tile_tg, B_ext, B_str);

        // A slice for this K-chunk: K_TILE cols of K, M_TILE rows of M.
        auto mA = A.slice<K_TILE, M_TILE>(k_base, tgid.x * M_TILE);
        auto mB = B_tile.slice<K_TILE, N_TILE>(0, 0);

        op.run(mA, mB, cT);
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    // Store accumulator to C.
    auto mC = C.slice<N_TILE, M_TILE>(tgid.y * N_TILE, tgid.x * M_TILE);
    cT.store(mC);
}
