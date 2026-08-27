// Wide (BATCH-token) NVFP4 matvec for deep MTP verification.
//
// Why this exists, given nvfp4_matvec_mlx_scaled_batch.metal already defines
// quad/quint: that kernel gives each SIMD group ONE output row, so per weight
// group it issues BATCH*4 float4 activation loads against 2 u32 weight loads --
// 256 bytes of activation per 8 bytes of weight at BATCH=4. The activations are
// cache-resident and individually cheap, but they compete for the load/store
// issue slots that the weight stream needs, and keeping that stream saturated
// is the kernel's entire job. It is the same defect the triplet hoist fixed,
// except a one-output-row kernel has nothing to hoist across. Measured
// consequence: quad/quint REGRESS against plain per-token qmv on mlp-down
// (0.96x and 0.77x in autotune_qwen38.w).
//
// The fix is structural rather than a hoist: give each SIMD group ROWS output
// rows and load the activations ONCE per group into registers shared by all of
// them. At ROWS=4 the per-output-row activation traffic drops 4x (32:1 -> 8:1).
// This is the shape of MLX's qmv_fast_crossrow_affine4_g64_wide, which shares
// one weight stream across NA input rows for exactly this reason.
//
// ROWS is a template parameter and every value is swept rather than reasoned
// about. On this kernel family register pressure has beaten instruction count
// before, and the cliff is not where an even split would put it -- MLX profiled
// M=9 as CHEAPER than M=8 (216 us vs 437 us) because M=8's even 4+4 split needs
// two simultaneous four-wide accumulator sets. Do not prune the ladder.
//
// Arithmetic and summation order per output row are identical to
// nvfp4_matvec_mlx_scaled_triplet_hoist: (v0.a0 + v1.a1) then (v2.a2 + v3.a3),
// then acc += s * d. Results are therefore bit-identical to the triplet path
// for BATCH=3, and to the per-token qmv for each row generally.

#include <metal_stdlib>
using namespace metal;

static inline half nvfp4_decode_half_wide(uint nibble) {
  half mag = as_type<half>(ushort((nibble & 7) << 9)) * 16384.0h;
  return (nibble & 8) ? -mag : mag;
}

static inline half e4m3_decode_half_wide(uint b) {
  return as_type<half>(ushort((b & 127) << 7)) * 256.0h;
}

template <int BATCH, int ROWS, bool ADD_RESIDUAL, bool NO_DECODE = false>
static inline void nvfp4_matvec_mlx_scaled_wide_impl(
  device const uint  *__restrict__ w_packed,
  device const uchar *__restrict__ w_scales,
  device const float *__restrict__ x,
  device float       *__restrict__ y,
  constant int   &k_dim,
  constant int   &n_rows,
  constant float &global_scale,
  uint tg_id,
  uint simd_id,
  uint simd_lane
) {
  const int n_groups = k_dim / 16;
  const int u32s_per_row = k_dim / 8;
  const int row0 = int(tg_id) * (2 * ROWS) + int(simd_id) * ROWS;
  const int lane = int(simd_lane);

  float acc[ROWS][BATCH];
#pragma clang loop unroll(full)
  for (int r = 0; r < ROWS; r++) {
#pragma clang loop unroll(full)
    for (int b = 0; b < BATCH; b++) {
      acc[r][b] = 0.0f;
    }
  }

  for (int g_block = 0; g_block < n_groups; g_block += 32) {
    const int g = g_block + lane;
    if (g >= n_groups) continue;
    const int x_off = g * 16;

    // Loaded once, reused by every one of the ROWS output rows below.
    float4 av[BATCH][4];
#pragma clang loop unroll(full)
    for (int b = 0; b < BATCH; b++) {
      device const float4 *xp =
        (device const float4 *)(&x[b * k_dim + x_off]);
      av[b][0] = xp[0];
      av[b][1] = xp[1];
      av[b][2] = xp[2];
      av[b][3] = xp[3];
    }

#pragma clang loop unroll(full)
    for (int r = 0; r < ROWS; r++) {
      const int row = row0 + r;
      if (row >= n_rows) continue;

      const uint w0 = w_packed[row * u32s_per_row + g * 2];
      const float s = float(e4m3_decode_half_wide(
        uint(w_scales[row * n_groups + g])));
      const uint b00 = w0 & 0xff, b01 = (w0 >> 8) & 0xff;
      const uint b02 = (w0 >> 16) & 0xff, b03 = (w0 >> 24) & 0xff;
      float4 v0, v1;
      if (NO_DECODE) {
        // TIMING ABLATION ONLY -- results are wrong by construction. Prices the
        // nibble decode against the FMA work it feeds.
        v0 = float4(float(b00 & 0xf), float(b00 >> 4), float(b01 & 0xf), float(b01 >> 4));
        v1 = float4(float(b02 & 0xf), float(b02 >> 4), float(b03 & 0xf), float(b03 >> 4));
      } else {
        v0 = float4(nvfp4_decode_half_wide(b00 & 0xf),
          nvfp4_decode_half_wide(b00 >> 4),
          nvfp4_decode_half_wide(b01 & 0xf),
          nvfp4_decode_half_wide(b01 >> 4));
        v1 = float4(nvfp4_decode_half_wide(b02 & 0xf),
          nvfp4_decode_half_wide(b02 >> 4),
          nvfp4_decode_half_wide(b03 & 0xf),
          nvfp4_decode_half_wide(b03 >> 4));
      }

      float d[BATCH];
#pragma clang loop unroll(full)
      for (int b = 0; b < BATCH; b++) {
        d[b] = dot(v0, av[b][0]) + dot(v1, av[b][1]);
      }

      const uint w1 = w_packed[row * u32s_per_row + g * 2 + 1];
      const uint b10 = w1 & 0xff, b11 = (w1 >> 8) & 0xff;
      const uint b12 = (w1 >> 16) & 0xff, b13 = (w1 >> 24) & 0xff;
      float4 v2, v3;
      if (NO_DECODE) {
        v2 = float4(float(b10 & 0xf), float(b10 >> 4), float(b11 & 0xf), float(b11 >> 4));
        v3 = float4(float(b12 & 0xf), float(b12 >> 4), float(b13 & 0xf), float(b13 >> 4));
      } else {
        v2 = float4(nvfp4_decode_half_wide(b10 & 0xf),
          nvfp4_decode_half_wide(b10 >> 4),
          nvfp4_decode_half_wide(b11 & 0xf),
          nvfp4_decode_half_wide(b11 >> 4));
        v3 = float4(nvfp4_decode_half_wide(b12 & 0xf),
          nvfp4_decode_half_wide(b12 >> 4),
          nvfp4_decode_half_wide(b13 & 0xf),
          nvfp4_decode_half_wide(b13 >> 4));
      }

#pragma clang loop unroll(full)
      for (int b = 0; b < BATCH; b++) {
        d[b] += dot(v2, av[b][2]) + dot(v3, av[b][3]);
      }

#pragma clang loop unroll(full)
      for (int b = 0; b < BATCH; b++) {
        acc[r][b] += s * d[b];
      }
    }
  }

#pragma clang loop unroll(full)
  for (int r = 0; r < ROWS; r++) {
#pragma clang loop unroll(full)
    for (int b = 0; b < BATCH; b++) {
      acc[r][b] = simd_sum(acc[r][b]) * global_scale;
    }
  }

  if (lane == 0) {
#pragma clang loop unroll(full)
    for (int r = 0; r < ROWS; r++) {
      const int row = row0 + r;
      if (row >= n_rows) continue;
#pragma clang loop unroll(full)
      for (int b = 0; b < BATCH; b++) {
        if (ADD_RESIDUAL) {
          y[b * n_rows + row] += acc[r][b];
        } else {
          y[b * n_rows + row] = acc[r][b];
        }
      }
    }
  }
}

#define DEFINE_WIDE_ABL(NAME, BATCH, ROWS)                                  \
[[max_total_threads_per_threadgroup(64)]]                                   \
kernel void NAME(                                                           \
  device const uint *w [[buffer(0)]], device const uchar *s [[buffer(1)]],  \
  device const float *x [[buffer(2)]], device float *y [[buffer(3)]],       \
  constant int &k [[buffer(4)]], constant int &n [[buffer(5)]],             \
  constant float &g [[buffer(6)]],                                          \
  uint tg [[threadgroup_position_in_grid]],                                 \
  uint sg [[simdgroup_index_in_threadgroup]],                               \
  uint sl [[thread_index_in_simdgroup]]) {                                  \
  nvfp4_matvec_mlx_scaled_wide_impl<BATCH, ROWS, false, true>(              \
    w, s, x, y, k, n, g, tg, sg, sl);                                       \
}
DEFINE_WIDE_ABL(nvfp4_wide_b3_r2_nodecode, 3, 2)
DEFINE_WIDE_ABL(nvfp4_wide_b1_r2_nodecode, 1, 2)
#undef DEFINE_WIDE_ABL

#define DEFINE_WIDE_KERNEL(NAME, BATCH, ROWS, ADD_RESIDUAL)                 \
[[max_total_threads_per_threadgroup(64)]]                                   \
kernel void NAME(                                                           \
  device const uint *w [[buffer(0)]], device const uchar *s [[buffer(1)]],  \
  device const float *x [[buffer(2)]], device float *y [[buffer(3)]],       \
  constant int &k [[buffer(4)]], constant int &n [[buffer(5)]],             \
  constant float &g [[buffer(6)]],                                          \
  uint tg [[threadgroup_position_in_grid]],                                 \
  uint sg [[simdgroup_index_in_threadgroup]],                               \
  uint sl [[thread_index_in_simdgroup]]) {                                  \
  nvfp4_matvec_mlx_scaled_wide_impl<BATCH, ROWS, ADD_RESIDUAL>(             \
    w, s, x, y, k, n, g, tg, sg, sl);                                       \
}

// The ladder. Swept, not chosen.
DEFINE_WIDE_KERNEL(nvfp4_wide_b3_r2, 3, 2, false)
DEFINE_WIDE_KERNEL(nvfp4_wide_b3_r4, 3, 4, false)
DEFINE_WIDE_KERNEL(nvfp4_wide_b4_r1, 4, 1, false)
DEFINE_WIDE_KERNEL(nvfp4_wide_b4_r2, 4, 2, false)
DEFINE_WIDE_KERNEL(nvfp4_wide_b4_r4, 4, 4, false)
DEFINE_WIDE_KERNEL(nvfp4_wide_b5_r1, 5, 1, false)
DEFINE_WIDE_KERNEL(nvfp4_wide_b5_r2, 5, 2, false)
DEFINE_WIDE_KERNEL(nvfp4_wide_b5_r4, 5, 4, false)
// Odd row counts. The even split is not automatically the fast split -- MLX
// profiled M=9 (3+3+3) as cheaper than M=8 (4+4) for exactly this reason -- and
// width 4 shows an in-situ cliff (row ladder 32/35/37/45 ms) that the width-3
// numbers do not predict. Sweep, do not extrapolate.
DEFINE_WIDE_KERNEL(nvfp4_wide_b4_r3, 4, 3, false)
DEFINE_WIDE_KERNEL(nvfp4_wide_b5_r3, 5, 3, false)
DEFINE_WIDE_KERNEL(nvfp4_wide_b3_r3, 3, 3, false)

DEFINE_WIDE_KERNEL(nvfp4_wide_b3_r2_residual, 3, 2, true)
DEFINE_WIDE_KERNEL(nvfp4_wide_b3_r4_residual, 3, 4, true)
DEFINE_WIDE_KERNEL(nvfp4_wide_b4_r2_residual, 4, 2, true)
DEFINE_WIDE_KERNEL(nvfp4_wide_b4_r4_residual, 4, 4, true)
DEFINE_WIDE_KERNEL(nvfp4_wide_b5_r2_residual, 5, 2, true)
DEFINE_WIDE_KERNEL(nvfp4_wide_b5_r4_residual, 5, 4, true)
DEFINE_WIDE_KERNEL(nvfp4_wide_b4_r3_residual, 4, 3, true)
// Block-verify widths (DFlash2 verifies an anchor plus up to seven drafts in
// one pass). The hoisted footprint grows with BATCH (16 floats per row), so
// r1 is the only likely-resident shape at b8 on this template; the split
// variant below keeps the b4 footprint at b8 and is swept against it.
DEFINE_WIDE_KERNEL(nvfp4_wide_b6_r1, 6, 1, false)
DEFINE_WIDE_KERNEL(nvfp4_wide_b6_r2, 6, 2, false)
DEFINE_WIDE_KERNEL(nvfp4_wide_b7_r1, 7, 1, false)
DEFINE_WIDE_KERNEL(nvfp4_wide_b7_r2, 7, 2, false)
DEFINE_WIDE_KERNEL(nvfp4_wide_b8_r1, 8, 1, false)
DEFINE_WIDE_KERNEL(nvfp4_wide_b8_r2, 8, 2, false)
DEFINE_WIDE_KERNEL(nvfp4_wide_b6_r1_residual, 6, 1, true)
DEFINE_WIDE_KERNEL(nvfp4_wide_b6_r2_residual, 6, 2, true)
DEFINE_WIDE_KERNEL(nvfp4_wide_b7_r1_residual, 7, 1, true)
DEFINE_WIDE_KERNEL(nvfp4_wide_b7_r2_residual, 7, 2, true)
DEFINE_WIDE_KERNEL(nvfp4_wide_b8_r1_residual, 8, 1, true)
DEFINE_WIDE_KERNEL(nvfp4_wide_b8_r2_residual, 8, 2, true)

#undef DEFINE_WIDE_KERNEL

// Half-footprint variant: 8 K-values per lane instead of 16.
//
// Motivation is a measured cliff, not a guess. The in-situ row ladder is
// 36 / 40 / 42 / 51 ms at widths 1-4: marginal +4, +2, then +9. Width 4 is only
// 33% more arithmetic than width 3, so a +9 ms step is not work scaling -- it is
// occupancy. The wide kernel hoists av[BATCH][4] float4, which at BATCH=4 is 64
// floats of activation live per thread, plus accumulators and the decoded
// weights: ~88 registers, past the point where this GPU halves occupancy, and
// occupancy is exactly what hides weight-load latency on a bandwidth-bound
// kernel.
//
// Each lane now covers 8 K-values (one u32 of packed weights) rather than 16, so
// av is [BATCH][2] = 32 floats and the footprint drops to ~48. An NVFP4 group is
// 16 values, so a group is now split across two lanes -- which is free, because
// simd_sum already reduces across lanes and both halves share the same group
// scale. Only the rounding of (s*a + s*b) vs s*(a+b) differs.

template <int BATCH, int ROWS, bool ADD_RESIDUAL>
static inline void nvfp4_wide_half_impl(
  device const uint  *__restrict__ w_packed,
  device const uchar *__restrict__ w_scales,
  device const float *__restrict__ x,
  device float       *__restrict__ y,
  constant int   &k_dim,
  constant int   &n_rows,
  constant float &global_scale,
  uint tg_id,
  uint simd_id,
  uint simd_lane
) {
  const int n_groups = k_dim / 16;
  const int u32s_per_row = k_dim / 8;
  const int row0 = int(tg_id) * (2 * ROWS) + int(simd_id) * ROWS;
  const int lane = int(simd_lane);

  float acc[ROWS][BATCH];
#pragma clang loop unroll(full)
  for (int r = 0; r < ROWS; r++) {
#pragma clang loop unroll(full)
    for (int b = 0; b < BATCH; b++) acc[r][b] = 0.0f;
  }

  for (int k_block = 0; k_block < k_dim; k_block += 256) {
    const int kk = k_block + lane * 8;
    if (kk >= k_dim) continue;

    float4 av[BATCH][2];
#pragma clang loop unroll(full)
    for (int b = 0; b < BATCH; b++) {
      device const float4 *xp =
        (device const float4 *)(&x[b * k_dim + kk]);
      av[b][0] = xp[0];
      av[b][1] = xp[1];
    }

#pragma clang loop unroll(full)
    for (int r = 0; r < ROWS; r++) {
      const int row = row0 + r;
      if (row >= n_rows) continue;
      const uint w0 = w_packed[row * u32s_per_row + kk / 8];
      const float s = float(e4m3_decode_half_wide(
        uint(w_scales[row * n_groups + kk / 16])));
      const uint b00 = w0 & 0xff, b01 = (w0 >> 8) & 0xff;
      const uint b02 = (w0 >> 16) & 0xff, b03 = (w0 >> 24) & 0xff;
      const float4 v0 = float4(nvfp4_decode_half_wide(b00 & 0xf),
        nvfp4_decode_half_wide(b00 >> 4),
        nvfp4_decode_half_wide(b01 & 0xf),
        nvfp4_decode_half_wide(b01 >> 4));
      const float4 v1 = float4(nvfp4_decode_half_wide(b02 & 0xf),
        nvfp4_decode_half_wide(b02 >> 4),
        nvfp4_decode_half_wide(b03 & 0xf),
        nvfp4_decode_half_wide(b03 >> 4));
#pragma clang loop unroll(full)
      for (int b = 0; b < BATCH; b++) {
        acc[r][b] += s * (dot(v0, av[b][0]) + dot(v1, av[b][1]));
      }
    }
  }

#pragma clang loop unroll(full)
  for (int r = 0; r < ROWS; r++) {
#pragma clang loop unroll(full)
    for (int b = 0; b < BATCH; b++) {
      acc[r][b] = simd_sum(acc[r][b]) * global_scale;
    }
  }

  if (lane == 0) {
#pragma clang loop unroll(full)
    for (int r = 0; r < ROWS; r++) {
      const int row = row0 + r;
      if (row >= n_rows) continue;
#pragma clang loop unroll(full)
      for (int b = 0; b < BATCH; b++) {
        if (ADD_RESIDUAL) y[b * n_rows + row] += acc[r][b];
        else y[b * n_rows + row] = acc[r][b];
      }
    }
  }
}

#define DEFINE_WIDE_HALF(NAME, BATCH, ROWS, ADD_RESIDUAL)                   \
[[max_total_threads_per_threadgroup(64)]]                                   \
kernel void NAME(                                                           \
  device const uint *w [[buffer(0)]], device const uchar *s [[buffer(1)]],  \
  device const float *x [[buffer(2)]], device float *y [[buffer(3)]],       \
  constant int &k [[buffer(4)]], constant int &n [[buffer(5)]],             \
  constant float &g [[buffer(6)]],                                          \
  uint tg [[threadgroup_position_in_grid]],                                 \
  uint sg [[simdgroup_index_in_threadgroup]],                               \
  uint sl [[thread_index_in_simdgroup]]) {                                  \
  nvfp4_wide_half_impl<BATCH, ROWS, ADD_RESIDUAL>(                          \
    w, s, x, y, k, n, g, tg, sg, sl);                                       \
}

DEFINE_WIDE_HALF(nvfp4_wideh_b4_r2, 4, 2, false)
DEFINE_WIDE_HALF(nvfp4_wideh_b4_r4, 4, 4, false)
DEFINE_WIDE_HALF(nvfp4_wideh_b5_r2, 5, 2, false)
DEFINE_WIDE_HALF(nvfp4_wideh_b3_r2, 3, 2, false)
DEFINE_WIDE_HALF(nvfp4_wideh_b4_r2_residual, 4, 2, true)
DEFINE_WIDE_HALF(nvfp4_wideh_b4_r4_residual, 4, 4, true)
#undef DEFINE_WIDE_HALF

// Split-hoist variant for wide batches: the BATCH activation rows are
// hoisted in halves of HALF rows, so the live activation footprint is that of
// a BATCH=HALF kernel while the weight group is still decoded once per output
// row and reused across every batch row (the second half re-reads the same
// two u32s, an L1 hit, and re-decodes them). The per-(row, batch) expression
// is exactly nvfp4_matvec_mlx_scaled_wide_impl's, so results are
// bit-identical to that kernel and to the per-token qmv.
template <int BATCH, int HALF, int ROWS, bool ADD_RESIDUAL>
static inline void nvfp4_wide_split_impl(
  device const uint  *__restrict__ w_packed,
  device const uchar *__restrict__ w_scales,
  device const float *__restrict__ x,
  device float       *__restrict__ y,
  constant int   &k_dim,
  constant int   &n_rows,
  constant float &global_scale,
  uint tg_id,
  uint simd_id,
  uint simd_lane
) {
  const int n_groups = k_dim / 16;
  const int u32s_per_row = k_dim / 8;
  const int row0 = int(tg_id) * (2 * ROWS) + int(simd_id) * ROWS;
  const int lane = int(simd_lane);

  float acc[ROWS][BATCH];
#pragma clang loop unroll(full)
  for (int r = 0; r < ROWS; r++) {
#pragma clang loop unroll(full)
    for (int b = 0; b < BATCH; b++) acc[r][b] = 0.0f;
  }

  for (int g_block = 0; g_block < n_groups; g_block += 32) {
    const int g = g_block + lane;
    if (g >= n_groups) continue;
    const int x_off = g * 16;

#pragma clang loop unroll(full)
    for (int h = 0; h < BATCH; h += HALF) {
      float4 av[HALF][4];
#pragma clang loop unroll(full)
      for (int b = 0; b < HALF; b++) {
        device const float4 *xp =
          (device const float4 *)(&x[(h + b) * k_dim + x_off]);
        av[b][0] = xp[0];
        av[b][1] = xp[1];
        av[b][2] = xp[2];
        av[b][3] = xp[3];
      }

#pragma clang loop unroll(full)
      for (int r = 0; r < ROWS; r++) {
        const int row = row0 + r;
        if (row >= n_rows) continue;

        const uint w0 = w_packed[row * u32s_per_row + g * 2];
        const float s = float(e4m3_decode_half_wide(
          uint(w_scales[row * n_groups + g])));
        const uint b00 = w0 & 0xff, b01 = (w0 >> 8) & 0xff;
        const uint b02 = (w0 >> 16) & 0xff, b03 = (w0 >> 24) & 0xff;
        const float4 v0 = float4(nvfp4_decode_half_wide(b00 & 0xf),
          nvfp4_decode_half_wide(b00 >> 4),
          nvfp4_decode_half_wide(b01 & 0xf),
          nvfp4_decode_half_wide(b01 >> 4));
        const float4 v1 = float4(nvfp4_decode_half_wide(b02 & 0xf),
          nvfp4_decode_half_wide(b02 >> 4),
          nvfp4_decode_half_wide(b03 & 0xf),
          nvfp4_decode_half_wide(b03 >> 4));

        float d[HALF];
#pragma clang loop unroll(full)
        for (int b = 0; b < HALF; b++) {
          d[b] = dot(v0, av[b][0]) + dot(v1, av[b][1]);
        }

        const uint w1 = w_packed[row * u32s_per_row + g * 2 + 1];
        const uint b10 = w1 & 0xff, b11 = (w1 >> 8) & 0xff;
        const uint b12 = (w1 >> 16) & 0xff, b13 = (w1 >> 24) & 0xff;
        const float4 v2 = float4(nvfp4_decode_half_wide(b10 & 0xf),
          nvfp4_decode_half_wide(b10 >> 4),
          nvfp4_decode_half_wide(b11 & 0xf),
          nvfp4_decode_half_wide(b11 >> 4));
        const float4 v3 = float4(nvfp4_decode_half_wide(b12 & 0xf),
          nvfp4_decode_half_wide(b12 >> 4),
          nvfp4_decode_half_wide(b13 & 0xf),
          nvfp4_decode_half_wide(b13 >> 4));

#pragma clang loop unroll(full)
        for (int b = 0; b < HALF; b++) {
          d[b] += dot(v2, av[b][2]) + dot(v3, av[b][3]);
        }

#pragma clang loop unroll(full)
        for (int b = 0; b < HALF; b++) {
          acc[r][h + b] += s * d[b];
        }
      }
    }
  }

#pragma clang loop unroll(full)
  for (int r = 0; r < ROWS; r++) {
#pragma clang loop unroll(full)
    for (int b = 0; b < BATCH; b++) {
      acc[r][b] = simd_sum(acc[r][b]) * global_scale;
    }
  }

  if (lane == 0) {
#pragma clang loop unroll(full)
    for (int r = 0; r < ROWS; r++) {
      const int row = row0 + r;
      if (row >= n_rows) continue;
#pragma clang loop unroll(full)
      for (int b = 0; b < BATCH; b++) {
        if (ADD_RESIDUAL) y[b * n_rows + row] += acc[r][b];
        else y[b * n_rows + row] = acc[r][b];
      }
    }
  }
}

#define DEFINE_WIDE_SPLIT(NAME, BATCH, HALF, ROWS, ADD_RESIDUAL)            \
[[max_total_threads_per_threadgroup(64)]]                                   \
kernel void NAME(                                                           \
  device const uint *w [[buffer(0)]], device const uchar *s [[buffer(1)]],  \
  device const float *x [[buffer(2)]], device float *y [[buffer(3)]],       \
  constant int &k [[buffer(4)]], constant int &n [[buffer(5)]],             \
  constant float &g [[buffer(6)]],                                          \
  uint tg [[threadgroup_position_in_grid]],                                 \
  uint sg [[simdgroup_index_in_threadgroup]],                               \
  uint sl [[thread_index_in_simdgroup]]) {                                  \
  nvfp4_wide_split_impl<BATCH, HALF, ROWS, ADD_RESIDUAL>(                   \
    w, s, x, y, k, n, g, tg, sg, sl);                                       \
}

DEFINE_WIDE_SPLIT(nvfp4_wides_b8_r1, 8, 4, 1, false)
DEFINE_WIDE_SPLIT(nvfp4_wides_b8_r2, 8, 4, 2, false)
DEFINE_WIDE_SPLIT(nvfp4_wides_b8_r4, 8, 4, 4, false)
DEFINE_WIDE_SPLIT(nvfp4_wides_b6_r2, 6, 3, 2, false)
DEFINE_WIDE_SPLIT(nvfp4_wides_b8_r1_residual, 8, 4, 1, true)
DEFINE_WIDE_SPLIT(nvfp4_wides_b8_r2_residual, 8, 4, 2, true)
DEFINE_WIDE_SPLIT(nvfp4_wides_b8_r4_residual, 8, 4, 4, true)
DEFINE_WIDE_SPLIT(nvfp4_wides_b6_r2_residual, 6, 3, 2, true)
#undef DEFINE_WIDE_SPLIT

// Complete the (BATCH 2..8) x (ROWS 1/2/4) x (residual) grid so the
// runtime-width block verify can pick any rung; the bench sweeps them.
#define DEFINE_WIDE_GRID(NAME, BATCH, ROWS, ADD_RESIDUAL)                   \
[[max_total_threads_per_threadgroup(64)]]                                   \
kernel void NAME(                                                           \
  device const uint *w [[buffer(0)]], device const uchar *s [[buffer(1)]],  \
  device const float *x [[buffer(2)]], device float *y [[buffer(3)]],       \
  constant int &k [[buffer(4)]], constant int &n [[buffer(5)]],             \
  constant float &g [[buffer(6)]],                                          \
  uint tg [[threadgroup_position_in_grid]],                                 \
  uint sg [[simdgroup_index_in_threadgroup]],                               \
  uint sl [[thread_index_in_simdgroup]]) {                                  \
  nvfp4_matvec_mlx_scaled_wide_impl<BATCH, ROWS, ADD_RESIDUAL>(             \
    w, s, x, y, k, n, g, tg, sg, sl);                                       \
}
DEFINE_WIDE_GRID(nvfp4_wide_b2_r1, 2, 1, false)
DEFINE_WIDE_GRID(nvfp4_wide_b2_r1_residual, 2, 1, true)
DEFINE_WIDE_GRID(nvfp4_wide_b2_r2, 2, 2, false)
DEFINE_WIDE_GRID(nvfp4_wide_b2_r2_residual, 2, 2, true)
DEFINE_WIDE_GRID(nvfp4_wide_b2_r4, 2, 4, false)
DEFINE_WIDE_GRID(nvfp4_wide_b2_r4_residual, 2, 4, true)
DEFINE_WIDE_GRID(nvfp4_wide_b3_r1, 3, 1, false)
DEFINE_WIDE_GRID(nvfp4_wide_b3_r1_residual, 3, 1, true)
DEFINE_WIDE_GRID(nvfp4_wide_b4_r1_residual, 4, 1, true)
DEFINE_WIDE_GRID(nvfp4_wide_b5_r1_residual, 5, 1, true)
DEFINE_WIDE_GRID(nvfp4_wide_b6_r4, 6, 4, false)
DEFINE_WIDE_GRID(nvfp4_wide_b6_r4_residual, 6, 4, true)
DEFINE_WIDE_GRID(nvfp4_wide_b7_r4, 7, 4, false)
DEFINE_WIDE_GRID(nvfp4_wide_b7_r4_residual, 7, 4, true)
DEFINE_WIDE_GRID(nvfp4_wide_b8_r4, 8, 4, false)
DEFINE_WIDE_GRID(nvfp4_wide_b8_r4_residual, 8, 4, true)
DEFINE_WIDE_GRID(nvfp4_wide_b1_r1, 1, 1, false)
DEFINE_WIDE_GRID(nvfp4_wide_b1_r1_residual, 1, 1, true)
DEFINE_WIDE_GRID(nvfp4_wide_b1_r2, 1, 2, false)
DEFINE_WIDE_GRID(nvfp4_wide_b1_r2_residual, 1, 2, true)
DEFINE_WIDE_GRID(nvfp4_wide_b1_r4, 1, 4, false)
DEFINE_WIDE_GRID(nvfp4_wide_b1_r4_residual, 1, 4, true)
#undef DEFINE_WIDE_GRID
