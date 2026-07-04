// f16 batched matmul (pre-dequanted weights). 4 simdgroups per TG (128
// threads), 8M × 32N output tile. Each simdgroup loads B (8 K × 8 N
// transposed) directly from device — no on-the-fly dequant.
//
// Dispatch (BATCH/8) * (N_ROWS/32) TGs.

#include <metal_stdlib>
#include <metal_simdgroup_matrix>
using namespace metal;

constant int K_DIM_FC  [[function_constant(0)]];
constant int N_ROWS_FC [[function_constant(1)]];
constant int BATCH_FC  [[function_constant(2)]];

[[max_total_threads_per_threadgroup(128)]]
kernel void f16_matmul_simd_v2_fc(
  device const half  *__restrict__ w        [[buffer(0)]],   // [N_ROWS × K_DIM] half row-major
  device const half  *__restrict__ x_h      [[buffer(1)]],   // [BATCH × K_DIM] half
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

  // Walk K in chunks of 8.
  for (int k = 0; k < K_DIM_FC; k += 8) {
    simdgroup_matrix<half, 8, 8> A;
    simdgroup_matrix<half, 8, 8> B;
    simdgroup_load(A, x_h + m_start * K_DIM_FC + k, (ulong)K_DIM_FC);
    // W is [N_ROWS × K_DIM] row-major. We want B[k=0..7, n=n_start..n_start+8],
    // i.e. an 8×8 tile from rows n_start..n_start+8 and cols k..k+8 of W,
    // transposed (because matmul C = A · B^T conceptually).
    simdgroup_load(B, w + n_start * K_DIM_FC + k, (ulong)K_DIM_FC, ulong2(0, 0), true);
    simdgroup_multiply_accumulate(C, A, B, C);
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
