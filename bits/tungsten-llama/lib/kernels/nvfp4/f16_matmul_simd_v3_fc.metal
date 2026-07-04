// f16 matmul, K loop unrolled 4x (K=32 effective per loop iteration).
// Holds 4 A and 4 B simdgroup_matrix tiles concurrently, then 4 mma
// instructions back-to-back. Better instruction-level parallelism.

#include <metal_stdlib>
#include <metal_simdgroup_matrix>
using namespace metal;

constant int K_DIM_FC  [[function_constant(0)]];
constant int N_ROWS_FC [[function_constant(1)]];
constant int BATCH_FC  [[function_constant(2)]];

[[max_total_threads_per_threadgroup(128)]]
kernel void f16_matmul_simd_v3_fc(
  device const half  *__restrict__ w        [[buffer(0)]],
  device const half  *__restrict__ x_h      [[buffer(1)]],
  device float       *__restrict__ y        [[buffer(2)]],
  threadgroup half *tg_c [[threadgroup(0)]],
  uint tid_in_tg [[thread_position_in_threadgroup]],
  uint tg [[threadgroup_position_in_grid]],
  uint lane [[thread_index_in_simdgroup]],
  uint simd_id [[simdgroup_index_in_threadgroup]]
) {
  const int n_tiles_per_row = N_ROWS_FC / 32;
  int n_tile_block = int(tg) % n_tiles_per_row;
  int m_tile = int(tg) / n_tiles_per_row;
  if (m_tile >= BATCH_FC / 8) return;

  int m_start = m_tile * 8;
  int n_block_start = n_tile_block * 32;
  int n_start = n_block_start + int(simd_id) * 8;

  simdgroup_matrix<half, 8, 8> C(0.0h);

  for (int k = 0; k < K_DIM_FC; k += 32) {
    simdgroup_matrix<half, 8, 8> A0, A1, A2, A3;
    simdgroup_matrix<half, 8, 8> B0, B1, B2, B3;
    simdgroup_load(A0, x_h + m_start * K_DIM_FC + k + 0,  (ulong)K_DIM_FC);
    simdgroup_load(A1, x_h + m_start * K_DIM_FC + k + 8,  (ulong)K_DIM_FC);
    simdgroup_load(A2, x_h + m_start * K_DIM_FC + k + 16, (ulong)K_DIM_FC);
    simdgroup_load(A3, x_h + m_start * K_DIM_FC + k + 24, (ulong)K_DIM_FC);
    simdgroup_load(B0, w + n_start * K_DIM_FC + k + 0,  (ulong)K_DIM_FC, ulong2(0, 0), true);
    simdgroup_load(B1, w + n_start * K_DIM_FC + k + 8,  (ulong)K_DIM_FC, ulong2(0, 0), true);
    simdgroup_load(B2, w + n_start * K_DIM_FC + k + 16, (ulong)K_DIM_FC, ulong2(0, 0), true);
    simdgroup_load(B3, w + n_start * K_DIM_FC + k + 24, (ulong)K_DIM_FC, ulong2(0, 0), true);
    simdgroup_multiply_accumulate(C, A0, B0, C);
    simdgroup_multiply_accumulate(C, A1, B1, C);
    simdgroup_multiply_accumulate(C, A2, B2, C);
    simdgroup_multiply_accumulate(C, A3, B3, C);
  }

  simdgroup_store(C, tg_c + int(simd_id) * 64, (ulong)8);
  threadgroup_barrier(mem_flags::mem_threadgroup);
  for (int e = int(tid_in_tg); e < 256; e += 128) {
    int sub = e / 64;
    int sub_e = e % 64;
    int r = sub_e / 8;
    int c = sub_e % 8;
    y[(m_start + r) * N_ROWS_FC + (n_block_start + sub * 8 + c)] = float(tg_c[sub * 64 + sub_e]);
  }
}
