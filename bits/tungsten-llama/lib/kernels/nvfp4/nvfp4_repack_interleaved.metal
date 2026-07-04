// One-shot repack: take separate (quants u32 buffer, scales u8 buffer) and
// produce an interleaved buffer where each group is [1B scale | 8B quants],
// 9 bytes per group, K/16 groups per row. Run once per matrix at load time;
// the output buffer is then bound to nvfp4_matvec_mlx_inter at decode.
//
// Dispatch: grid = (n_groups × N rows, 1, 1). One thread per group per row.

#include <metal_stdlib>
using namespace metal;

kernel void nvfp4_repack_interleaved(
  device const uint  *__restrict__ quants [[buffer(0)]],   // [N × K/8]
  device const uchar *__restrict__ scales [[buffer(1)]],   // [N × K/16]
  device uchar       *__restrict__ out    [[buffer(2)]],   // [N × (K/16)*9]
  constant int &k_dim   [[buffer(3)]],
  constant int &n_rows  [[buffer(4)]],
  uint gid [[thread_position_in_grid]]
) {
  int n_groups = k_dim / 16;
  int total = n_groups * n_rows;
  if (int(gid) >= total) return;

  int row = int(gid) / n_groups;
  int g   = int(gid) % n_groups;

  uint w0 = quants[row * (k_dim / 8) + g * 2];
  uint w1 = quants[row * (k_dim / 8) + g * 2 + 1];
  uchar s = scales[row * n_groups + g];

  device uchar *gp = out + (row * n_groups + g) * 9;
  gp[0] = s;
  gp[1] = uchar(w0 & 0xFF);
  gp[2] = uchar((w0 >>  8) & 0xFF);
  gp[3] = uchar((w0 >> 16) & 0xFF);
  gp[4] = uchar((w0 >> 24) & 0xFF);
  gp[5] = uchar(w1 & 0xFF);
  gp[6] = uchar((w1 >>  8) & 0xFF);
  gp[7] = uchar((w1 >> 16) & 0xFF);
  gp[8] = uchar((w1 >> 24) & 0xFF);
}
