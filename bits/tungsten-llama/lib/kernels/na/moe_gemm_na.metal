// Routed-expert (MoE) NVFP4 GEMM on the M5 GPU Neural Accelerators, classic
// encoder (FN_NA_MOE). Companion of moe_gemm_m8 in qwen4_fn/fn_multi.metal:
// the staged, expert-contiguous activations (order/offs from moe_sort_pairs)
// are consumed in 64-row blocks per expert, one block x one 64-wide output
// tile per threadgroup, with the NVFP4 weight tile dequantized into
// threadgroup memory and a masked per-pair scatter on store (the cooperative
// tensor store does not clip, so the tile is staged through threadgroup
// memory and only rows inside the expert's segment are written).
//
// Work list: moe_na_plan (one TG) turns offs[513] into (expert, row0) items
// for every expert with >= na_min staged rows; the recorded program keeps
// a FIXED grid of max_items x (n_rows/64) threadgroups and the GEMM exits on
// item >= count. Experts below na_min stay on moe_gemm_m8 (which skips
// experts >= na_min), so the two kernels write disjoint pairs.
//
// Numerics: half activations (moe_stage_x_h), NVFP4 -> half weights, f32
// accumulate, global scale applied at store — the same values moe_gemm_m8_h
// consumes; NOT bit-identical to the f32-staged m8 path.
//
// Threadgroup memory: B tile half[64*64] (8 KB) + C stage float[64*64] (16 KB).

#include <metal_stdlib>
#include <MetalPerformancePrimitives/MetalPerformancePrimitives.h>
using namespace metal;
using namespace mpp;
using namespace mpp::tensor_ops;

constant float MOE_NA_TABLE[16] = {
     0.0f,  0.5f,  1.0f,  1.5f,  2.0f,  3.0f,  4.0f,  6.0f,
    -0.0f, -0.5f, -1.0f, -1.5f, -2.0f, -3.0f, -4.0f, -6.0f,
};
static inline float moe_na_e4m3(uint b) {
    return float(as_type<half>(ushort((b & 127) << 7)) * 256.0h);
}
static inline uint moe_na_load_u32_le(device const uchar *p) {
    return (uint)p[0] | ((uint)p[1] << 8) | ((uint)p[2] << 16) | ((uint)p[3] << 24);
}

// items[i] = (expert, row0) for each 64-row block of every expert with at
// least na_min staged rows; count[0] = number of items. max_items must be a
// true bound (nk/64 + 512 covers every routing), the plan never drops blocks
// below it. Dispatch: 1 threadgroup x 512 threads (thread 0 walks the table).
kernel void moe_na_plan(
    device const int *__restrict__ offs   [[buffer(0)]],   // [513]
    constant int &na_min                  [[buffer(1)]],
    device int *__restrict__ items        [[buffer(2)]],   // [max_items][2]
    device int *__restrict__ count        [[buffer(3)]],   // [1]
    constant int &max_items               [[buffer(4)]],
    uint tid [[thread_position_in_threadgroup]]
) {
    if (tid != 0) return;
    int n = 0;
    for (int e = 0; e < 512; e++) {
        const int lo = offs[e];
        const int c = offs[e + 1] - lo;
        if (c < na_min) continue;
        for (int r0 = lo; r0 < lo + c && n < max_items; r0 += 64) {
            items[n * 2] = e;
            items[n * 2 + 1] = r0;
            n++;
        }
    }
    count[0] = n;
}

// Dispatch (max_items, n_rows/64, 1) threadgroups x (128,1,1).
[[max_total_threads_per_threadgroup(128)]]
kernel void moe_gemm_na(
    device const uchar *__restrict__ q0 [[buffer(0)]],
    device const uchar *__restrict__ q1 [[buffer(1)]],
    device const uchar *__restrict__ q2 [[buffer(2)]],
    device const uchar *__restrict__ q3 [[buffer(3)]],
    device const int   *__restrict__ order    [[buffer(4)]],
    device const int   *__restrict__ offs     [[buffer(5)]],   // [513]
    device const int   *__restrict__ slot_map [[buffer(6)]],
    device half        *xg                    [[buffer(7)]],   // [xg_rows, k_dim] staged half
    device float       *__restrict__ y        [[buffer(8)]],   // [n*K, n_rows] per pair
    constant int &k_dim    [[buffer(9)]],
    constant int &n_rows   [[buffer(10)]],
    constant int &w0       [[buffer(11)]],
    constant int &w_stride [[buffer(12)]],
    constant int &s0       [[buffer(13)]],
    constant int &s_stride [[buffer(14)]],
    constant int &g0       [[buffer(15)]],
    constant int &g_stride [[buffer(16)]],
    device const int *__restrict__ items [[buffer(17)]],
    device const int *__restrict__ count [[buffer(18)]],
    constant int &xg_rows  [[buffer(19)]],                    // rows allocated in xg (>= nk + 64)
    uint3 tgid [[threadgroup_position_in_grid]],
    uint3 tid3 [[thread_position_in_threadgroup]]
) {
    const int tid = int(tid3.x);
    const int item = int(tgid.x);
    if (item >= count[0]) return;
    const int expert = items[item * 2];
    const int row0   = items[item * 2 + 1];
    const int rows_valid = min(64, offs[expert + 1] - row0);
    const int n0 = int(tgid.y) * 64;
    const int slot = slot_map[expert] & 0xFFFF;
    device const uchar *base = (expert < 128) ? q0
                             : (expert < 256) ? q1
                             : (expert < 384) ? q2 : q3;
    device const uint  *wq = (device const uint *)(base + (ulong)(uint)w0 + (ulong)(uint)slot * (ulong)(uint)w_stride);
    device const uchar *sq = base + (ulong)(uint)s0 + (ulong)(uint)slot * (ulong)(uint)s_stride;
    const float ws2 = as_type<float>(moe_na_load_u32_le(base + (ulong)(uint)g0 + (ulong)(uint)slot * (ulong)(uint)g_stride));
    const int u32s_per_row   = k_dim / 8;
    const int groups_per_row = k_dim / 16;

    threadgroup half  B_tile[64 * 64];
    threadgroup float C_tile[64 * 64];

    auto A = tensor(xg, dextents<int32_t, 2>(k_dim, xg_rows), array<int32_t, 2>{1, k_dim});
    constexpr auto desc = matmul2d_descriptor(
        64, 64, 64, false, true, false,
        matmul2d_descriptor::mode::multiply_accumulate);
    matmul2d<desc, execution_simdgroups<4>> op;
    auto cT = op.template get_destination_cooperative_tensor<decltype(A), decltype(A), float>();
    for (uint16_t i = 0; i < cT.get_capacity(); ++i) cT[i] = 0.0f;

    for (int k0 = 0; k0 < k_dim; k0 += 64) {
        // 64 output rows x 64 k = 256 spans of one 16-wide NVFP4 group.
        for (int span = int(tid); span < 256; span += 128) {
            const int row = span >> 2;
            const int col = (span & 3) * 16;
            const int nrow = min(n0 + row, n_rows - 1);
            const int g = (k0 + col) >> 4;
            const float s = moe_na_e4m3(uint(sq[nrow * groups_per_row + g]));
            const uint wa = wq[nrow * u32s_per_row + g * 2];
            const uint wb = wq[nrow * u32s_per_row + g * 2 + 1];
            const int bi = row * 64 + col;
            uint bs[8] = { wa&0xFF,(wa>>8)&0xFF,(wa>>16)&0xFF,(wa>>24)&0xFF,
                           wb&0xFF,(wb>>8)&0xFF,(wb>>16)&0xFF,(wb>>24)&0xFF };
            for (int j = 0; j < 8; ++j) {
                B_tile[bi + j*2 + 0] = half(s * MOE_NA_TABLE[bs[j] & 0xF]);
                B_tile[bi + j*2 + 1] = half(s * MOE_NA_TABLE[bs[j] >> 4]);
            }
        }
        threadgroup_barrier(mem_flags::mem_threadgroup);
        auto Bt = tensor(B_tile, dextents<int32_t, 2>(64, 64), array<int32_t, 2>{1, 64});
        auto mA = A.template slice<64, 64>(k0, row0);
        auto mB = Bt.template slice<64, 64>(0, 0);
        op.run(mA, mB, cT);
        threadgroup_barrier(mem_flags::mem_threadgroup);
    }

    // Stage the 64x64 f32 tile ((n, m) with n innermost, as the dense
    // kernels' C views) and scatter the valid rows to their pairs.
    auto Ct = tensor(C_tile, dextents<int32_t, 2>(64, 64), array<int32_t, 2>{1, 64});
    cT.store(Ct.template slice<64, 64>(0, 0));
    threadgroup_barrier(mem_flags::mem_threadgroup);
    for (int idx = int(tid); idx < 64 * 64; idx += 128) {
        const int m = idx >> 6;
        const int nn = idx & 63;
        if (m < rows_valid) {
            const int pair = order[row0 + m];
            y[pair * n_rows + n0 + nn] = C_tile[m * 64 + nn] * ws2;
        }
    }
}
